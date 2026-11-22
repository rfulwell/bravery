#!/usr/bin/env bash
# Checks, without building, that the Bravery patches still apply to a Brave
# release and that their plaster rules still match its Chromium version.
#
#   scripts/check-patches.sh v1.98.61
#
# Needs git, python3 with PyYAML, and network access to GitHub. ~2 GB of disk.
# Exit codes: 3 the patches or plaster rules no longer apply, other non-zero
# for anything else (e.g. a network failure).
set -euo pipefail
source "$(dirname "$0")/common.sh"

TAG="${1:?usage: check-patches.sh <brave tag>}"
[[ "$TAG" == v* ]] || TAG="v$TAG"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

log "Fetching brave-core $TAG"
git clone --quiet --depth 1 --branch "$TAG" https://github.com/brave/brave-core.git "$WORK/brave-core"
cd "$WORK/brave-core"

log "Applying patches"
export GIT_COMMITTER_NAME=Bravery GIT_COMMITTER_EMAIL=bravery@localhost
export GIT_AUTHOR_NAME=Bravery GIT_AUTHOR_EMAIL=bravery@localhost
if ! git am "$BRAVERY_ROOT"/patches/*.patch; then
  # Show exactly which hunks fail; git am's own message can name the wrong file.
  git am --show-current-patch=diff > "$WORK/failed.patch" 2>/dev/null || true
  git apply --check "$WORK/failed.patch" 2>&1 | head -n 20 >&2 || true
  git am --abort || true
  exit 3
fi

mapfile -t PLASTERS < <(python3 "$BRAVERY_ROOT/scripts/merge-rewrites.py" .)
if (( ${#PLASTERS[@]} )); then
  log "Checking plaster rules against Chromium"
  status=0
  python3 "$BRAVERY_ROOT/scripts/check-plasters.py" . "${PLASTERS[@]}" || status=$?
  # 1: a rule no longer matches (exit 3, like a patch that doesn't apply).
  # 2: couldn't download Chromium sources; a network problem, so exit 1.
  (( status == 0 )) || exit $(( status == 1 ? 3 : 1 ))
fi
log "Patches are good for $TAG"
