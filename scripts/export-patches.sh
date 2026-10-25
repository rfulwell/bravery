#!/usr/bin/env bash
# After fixing or extending the patches in a brave-core checkout (commits on top
# of a Brave release tag), write them back to patches/.
#
#   scripts/export-patches.sh ~/bravery-build/src/brave v1.98.61
set -euo pipefail
source "$(dirname "$0")/common.sh"

BRAVE_CORE="${1:?usage: export-patches.sh <brave-core dir> <base tag>}"
BASE="${2:?usage: export-patches.sh <brave-core dir> <base tag>}"
rm -f "$BRAVERY_ROOT"/patches/*.patch
git -C "$BRAVE_CORE" format-patch --quiet --zero-commit --no-signature \
  -o "$BRAVERY_ROOT/patches" "$BASE..HEAD"
ls "$BRAVERY_ROOT/patches"
log "Bump BRAVERY_REVISION if you want a rebuild of an already-published Brave version."
