#!/usr/bin/env bash
# Builds a signed Bravery APK for one Brave release.
#
#   scripts/build.sh v1.98.61
#
# Development mode rebuilds the current brave-core checkout as it is, keeping
# your edits there: no checkout, sync or patching (plaster rules you changed
# are re-applied). Much faster for a debug/fix loop:
#
#   scripts/build.sh --dev
#
# Prints the path of the signed APK as the last line of stdout. Exit codes:
#   1  general failure (sync, compile, signing)
#   3  the Bravery patches no longer apply to this Brave release
set -euo pipefail
source "$(dirname "$0")/common.sh"
load_config

DEV=
if [[ "${1:-}" == --dev ]]; then
  DEV=1
  TAG="v$(node -p "require('$BRAVERY_BRAVE_CORE/package.json').version")"
else
  TAG="${1:?usage: build.sh <brave tag, e.g. v1.98.61> | --dev}"
fi
[[ "$TAG" == v* ]] || TAG="v$TAG"
VERSION="${TAG#v}"
ARCH="$BRAVERY_TARGET_ARCH"
OUT_DIR="$BRAVERY_SRC/out/android_Release_${ARCH}"
: "${BRAVERY_KEYSTORE:?set BRAVERY_KEYSTORE in $BRAVERY_CONF}"
: "${BRAVERY_KEYSTORE_PASSWORD:?set BRAVERY_KEYSTORE_PASSWORD in $BRAVERY_CONF}"
[[ -f "$BRAVERY_KEYSTORE" ]] || die "keystore $BRAVERY_KEYSTORE not found (run scripts/make-keystore.sh)"
command -v pnpm >/dev/null || die "pnpm not found (run scripts/setup-build-machine.sh)"

mkdir -p "$BRAVERY_SRC"

if [[ -z "$DEV" ]]; then
# --- 1. brave-core at the release tag ---------------------------------------
if [[ ! -d "$BRAVERY_BRAVE_CORE/.git" ]]; then
  log "Cloning brave-core"
  git clone https://github.com/brave/brave-core.git "$BRAVERY_BRAVE_CORE"
fi
cd "$BRAVERY_BRAVE_CORE"
git am --abort >/dev/null 2>&1 || true
log "Checking out brave-core $TAG"
git fetch --force origin "refs/tags/$TAG:refs/tags/$TAG"
git checkout --force --detach "$TAG"
# Drops files left by the previous build's patches; keeps ignored files such
# as .env, node_modules and vendor/depot_tools.
git clean -fd

# --- 2. Build configuration ---------------------------------------------------
PLACEHOLDER=bravery-no-key
cat > .env <<EOF
brave_services_key=${BRAVERY_BRAVE_SERVICES_KEY:-$PLACEHOLDER}
service_key_search=${BRAVERY_SERVICE_KEY_SEARCH:-$PLACEHOLDER}
service_key_aichat=${BRAVERY_SERVICE_KEY_AICHAT:-$PLACEHOLDER}
service_key_stt=${BRAVERY_SERVICE_KEY_STT:-$PLACEHOLDER}
EOF
if [[ -n "${BRAVERY_CONCURRENT_LINKS:-}" ]]; then
  # Each link of the main library can need 10+ GB, more with LTO.
  echo "concurrent_links=$BRAVERY_CONCURRENT_LINKS" >> .env
fi
chmod 600 .env

# --- 3. Chromium + Brave's own patches -----------------------------------------
# --no-history: shallow Chromium checkout, tens of GB and hours less to fetch.
SYNC_ARGS=(--target_os=android "--target_arch=$ARCH")
FETCH_ARGS=(--no-history)
# Runs `pnpm run init|sync ...`. When a new Chromium version starts tracking
# files that an old dependency checkout left behind, git refuses to overwrite
# them; move those aside (into $BRAVERY_WORKDIR/stale-checkouts, nothing is
# deleted) and retry.
sync_chromium() {
  local sync_log attempt
  sync_log="$(mktemp)"
  for attempt in 1 2 3 4; do
    if pnpm run "$@" 2>&1 | tee "$sync_log"; then
      rm -f "$sync_log"
      return 0
    fi
    (( attempt < 4 )) || break
    python3 "$BRAVERY_ROOT/scripts/move-stale-checkouts.py" "$sync_log" \
      "$BRAVERY_WORKDIR/stale-checkouts" || break
    log "Moved files left by an older Chromium version to $BRAVERY_WORKDIR/stale-checkouts; retrying"
  done
  rm -f "$sync_log"
  return 1
}
if [[ ! -d "$BRAVERY_SRC/.git" || ! -d vendor/depot_tools ]]; then
  log "First run: fetching Chromium (tens of GB, this takes a while)"
  sync_chromium init "${SYNC_ARGS[@]}" "${FETCH_ARGS[@]}"
else
  log "Syncing Chromium and dependencies for $TAG"
  sync_chromium sync "${SYNC_ARGS[@]}" "${FETCH_ARGS[@]}" -D
fi
export PATH="$BRAVERY_BRAVE_CORE/vendor/depot_tools:$PATH"

# The Docker image installs these at image build time and leaves this marker.
[[ -f /etc/bravery/build-deps-done ]] && BRAVERY_DEPS_MARKER=/etc/bravery/build-deps-done
DEPS_MARKER="${BRAVERY_DEPS_MARKER:-$BRAVERY_WORKDIR/.install-build-deps-done}"
if [[ ! -f "$DEPS_MARKER" ]]; then
  if sudo -n true 2>/dev/null; then
    log "Installing Chromium's Android build dependencies"
    sudo "$BRAVERY_SRC/build/install-build-deps.sh" --android --no-prompt
    touch "$DEPS_MARKER"
  else
    die "run once: sudo $BRAVERY_SRC/build/install-build-deps.sh --android && touch $DEPS_MARKER"
  fi
fi

# --- 4. Bravery's patches -------------------------------------------------------
log "Applying Bravery patches"
if ! GIT_COMMITTER_NAME=Bravery GIT_COMMITTER_EMAIL=bravery@localhost \
    git am -3 --quiet "$BRAVERY_ROOT"/patches/*.patch; then
  git am --abort || true
  echo "The Bravery patches do not apply cleanly to brave-core $TAG." >&2
  exit 3
fi

# Chromium-side changes are plaster rules (regex rewrites); turn them into
# patches against this exact Chromium version and apply them.
mapfile -t PLASTERS < <(python3 "$BRAVERY_ROOT/scripts/merge-rewrites.py" .)
if (( ${#PLASTERS[@]} )); then
  log "Applying plaster rules: ${PLASTERS[*]}"
  if ! vpython3 tools/cr/plaster.py apply "${PLASTERS[@]}"; then
    echo "A Bravery plaster rule no longer matches Chromium for $TAG." >&2
    exit 3
  fi
  pnpm run apply_patches Release
fi

else
  [[ -d "$BRAVERY_BRAVE_CORE/vendor/depot_tools" ]] || die "--dev needs a previous full build"
  cd "$BRAVERY_BRAVE_CORE"
  export PATH="$BRAVERY_BRAVE_CORE/vendor/depot_tools:$PATH"
  # Re-merge and re-apply Bravery's plaster rules, including uncommitted edits
  # in bravery-rewrite/.
  mapfile -t PLASTERS < <(python3 "$BRAVERY_ROOT/scripts/merge-rewrites.py" .)
  if (( ${#PLASTERS[@]} )); then
    log "Applying plaster rules: ${PLASTERS[*]}"
    vpython3 tools/cr/plaster.py apply "${PLASTERS[@]}"
    pnpm run apply_patches Release
  fi
fi

# --- 5. Compile -------------------------------------------------------------------
BUILD_ARGS=(
  Release
  --target_os=android
  "--target_arch=$ARCH"
  --target_android_output_format=apk
  "--android_override_version_name=$VERSION-bravery$BRAVERY_REVISION"
  --gn=chrome_public_manifest_package:com.brave.browser_bravery
  # Trimmed to what a modern 64-bit-only phone (e.g. Pixel 7 and later) needs:
  # official builds otherwise compile all native code a second time for
  # 32-bit ARM.
  --gn=enable_android_secondary_abi:false
  # No debug symbols: faster compiles, much faster and lighter links. Only
  # matters for symbolizing native crash dumps, which Bravery doesn't upload.
  --gn=symbol_level:0
  # Skip Java lint and static analysis; Brave's CI already runs them.
  --gn=android_static_analysis:off
  --gn=disable_android_lint:true
)
if [[ "$BRAVERY_OFFICIAL_BUILD" != 1 ]]; then
  BUILD_ARGS+=(--gn=is_official_build:false --gn=dcheck_always_on:false)
fi
if [[ -n "${BRAVERY_JOBS:-}" ]]; then
  # Caps parallel compile jobs (siso's local limit) to fit a smaller Docker VM.
  BUILD_ARGS+=(--ninja "j:$BRAVERY_JOBS")
fi
# Generated files a target no longer lists, left in $OUT_DIR by a build of an
# older Brave version; Android resource steps refuse to run with them present.
stale_outputs() {
  [[ -f "$OUT_DIR/siso_output" ]] || return 0
  sed -n '/Found files not listed in the sources list/,/^[[:space:]]*$/p' "$OUT_DIR/siso_output" \
    | grep -E '^gen/[^[:space:]]+$' | grep -v '\.\.' | sort -u || true
}

log "Building (several hours on a first build)"
for attempt in 1 2 3 4; do
  pnpm run build "${BUILD_ARGS[@]}" && break
  mapfile -t STALE < <(stale_outputs)
  if (( attempt < 4 && ${#STALE[@]} )); then
    # Moved, not deleted (brave-core's rules: never delete build output).
    STASH="$BRAVERY_WORKDIR/stale-outputs/$(date +%Y%m%d-%H%M%S)"
    for f in "${STALE[@]}"; do
      [[ -e "$OUT_DIR/$f" ]] || continue
      mkdir -p "$STASH/$(dirname "$f")"
      mv "$OUT_DIR/$f" "$STASH/$f"
    done
    log "Moved files left by an older Brave build to $STASH: ${STALE[*]}; retrying"
    continue
  fi
  # siso only says "1 failed" at the end; the compiler's error scrolled past
  # tens of thousands of lines earlier. Repeat it here, between markers that
  # auto-update.sh copies into the GitHub issue.
  {
    echo "=== Bravery: failed build steps ==="
    if [[ -s "$OUT_DIR/siso_output" ]]; then
      tail -n 200 "$OUT_DIR/siso_output"
    else
      echo "(no $OUT_DIR/siso_output; see the full log)"
    fi
    echo "=== end of failed build steps ==="
  } >&2
  exit 1
done

UNSIGNED="$OUT_DIR/apks/BraveMono${ARCH}.apk"
[[ -f "$UNSIGNED" ]] || UNSIGNED="$OUT_DIR/apks/ChromePublic.apk"
[[ -f "$UNSIGNED" ]] || die "build finished but no APK found in $OUT_DIR/apks"

# --- 6. Sign ------------------------------------------------------------------------
APKSIGNER="$(ls -d "$BRAVERY_SRC"/third_party/android_sdk/public/build-tools/*/apksigner | sort -V | tail -1)"
[[ -x "$APKSIGNER" ]] || die "apksigner not found in the Android SDK checkout"
DIST="$BRAVERY_WORKDIR/dist"
mkdir -p "$DIST"
SIGNED="$DIST/Bravery-$VERSION-bravery$BRAVERY_REVISION${DEV:+-dev}-$ARCH.apk"
log "Signing $SIGNED"
export BRAVERY_KEYSTORE_PASSWORD
export BRAVERY_KEY_PASSWORD="${BRAVERY_KEY_PASSWORD:-$BRAVERY_KEYSTORE_PASSWORD}"
"$APKSIGNER" sign \
  --ks "$BRAVERY_KEYSTORE" \
  --ks-key-alias "${BRAVERY_KEY_ALIAS:-bravery}" \
  --ks-pass env:BRAVERY_KEYSTORE_PASSWORD \
  --key-pass env:BRAVERY_KEY_PASSWORD \
  --out "$SIGNED" "$UNSIGNED"
"$APKSIGNER" verify "$SIGNED"

echo "$SIGNED"
