#!/usr/bin/env bash
# Checks, without building, that the Bravery patches still apply to a Brave
# release and that their plaster rules still match its Chromium version.
#
#   scripts/check-patches.sh v1.98.61
#
# Needs git, python3 with PyYAML, and network access to GitHub. ~2 GB of disk.
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
GIT_COMMITTER_NAME=Bravery GIT_COMMITTER_EMAIL=bravery@localhost \
  GIT_AUTHOR_NAME=Bravery GIT_AUTHOR_EMAIL=bravery@localhost \
  git am -3 "$BRAVERY_ROOT"/patches/*.patch || { git am --abort; exit 3; }

mapfile -t PLASTERS < <(git diff --name-only "HEAD~$(ls "$BRAVERY_ROOT"/patches/*.patch | wc -l)" HEAD -- rewrite/)
if (( ${#PLASTERS[@]} )); then
  log "Checking plaster rules against Chromium"
  python3 "$BRAVERY_ROOT/scripts/check-plasters.py" . "${PLASTERS[@]}" || exit 3
fi
log "Patches are good for $TAG"
