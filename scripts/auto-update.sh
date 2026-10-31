#!/usr/bin/env bash
# The scheduled entry point: if Brave has a stable release that Bravery has not
# been built for yet, build it and publish it. Safe to run as often as you like.
set -euo pipefail
source "$(dirname "$0")/common.sh"

# Pick up new Bravery patches first, then re-run this script from the update.
if [[ -z "${BRAVERY_UPDATED:-}" ]]; then
  git -C "$BRAVERY_ROOT" pull --ff-only --quiet || log "could not update the Bravery repo; using local copy"
  BRAVERY_UPDATED=1 exec "$BRAVERY_ROOT/scripts/auto-update.sh" "$@"
fi
load_config

finish() {
  local status=$?
  if [[ "${BRAVERY_SHUTDOWN_WHEN_DONE:-0}" == 1 ]]; then
    log "Shutting down (BRAVERY_SHUTDOWN_WHEN_DONE=1)"
    sudo -n shutdown -h +1 || true
  fi
  exit $status
}
trap finish EXIT

TAG="${BRAVERY_BRAVE_TAG:-$("$BRAVERY_ROOT/scripts/latest-brave-release.sh")}"
RELEASE="$(release_tag_for "$TAG")"
log "Latest stable Brave: $TAG -> Bravery release $RELEASE"

if gh release view "$RELEASE" --repo "$BRAVERY_REPO" >/dev/null 2>&1; then
  log "$RELEASE already published; nothing to do"
  exit 0
fi

LOG_DIR="$BRAVERY_WORKDIR/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/build-$RELEASE-$(date +%Y%m%d-%H%M%S).log"
log "Building; full log in $LOG"

set +e
"$BRAVERY_ROOT/scripts/build.sh" "$TAG" 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}
set -e

if [[ $STATUS -ne 0 ]]; then
  if [[ $STATUS -eq 3 ]]; then
    TITLE="Bravery patches need updating for Brave $TAG"
  else
    TITLE="Bravery build failed for Brave $TAG"
  fi
  log "$TITLE"
  if ! gh issue list --repo "$BRAVERY_REPO" --state open --search "\"$TITLE\" in:title" \
      --json number --jq '.[0].number' | grep -q .; then
    {
      echo "Automatic build of $RELEASE failed with exit code $STATUS on $(hostname)."
      echo
      echo "Last lines of \`$LOG\`:"
      echo
      echo '```'
      tail -n 80 "$LOG"
      echo '```'
    } | gh issue create --repo "$BRAVERY_REPO" --title "$TITLE" --body-file - || true
  fi
  exit "$STATUS"
fi

APK="$(tail -n 1 "$LOG")"
[[ -f "$APK" ]] || die "build reported success but $APK is missing"
"$BRAVERY_ROOT/scripts/publish.sh" "$TAG" "$APK"
# Lets build.yml hand the new release to the startup check.
[[ -n "${GITHUB_OUTPUT:-}" ]] && echo "release=$RELEASE" >> "$GITHUB_OUTPUT"
log "Done: $RELEASE"
