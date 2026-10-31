#!/usr/bin/env bash
# Publishes a signed APK as a GitHub release that Obtainium can install from.
#
#   scripts/publish.sh v1.98.61 /path/to/Bravery.apk
set -euo pipefail
source "$(dirname "$0")/common.sh"
load_config

TAG="${1:?usage: publish.sh <brave tag> <apk>}"
APK="${2:?usage: publish.sh <brave tag> <apk>}"
RELEASE="$(release_tag_for "$TAG")"
VERSION="${TAG#v}"

NOTES="Bravery built from Brave ${TAG} with Bravery patch revision ${BRAVERY_REVISION}.

- Brave release notes: https://github.com/brave/brave-browser/releases/tag/${TAG}
- Bravery patches: https://github.com/${BRAVERY_REPO}/tree/$(git -C "$BRAVERY_ROOT" rev-parse HEAD)/patches
- SHA-256: $(sha256sum "$APK" | cut -d' ' -f1)

Published as a pre-release until the startup check passes on an emulator."

log "Publishing $RELEASE to $BRAVERY_REPO"
# Published as a pre-release, which Obtainium ignores by default; the startup
# check (smoke-test.yml) promotes it once it has run on an emulator.
PRERELEASE=(--prerelease)
[[ "${BRAVERY_SKIP_STARTUP_CHECK:-0}" == 1 ]] && PRERELEASE=()
gh release create "$RELEASE" "$APK" "${PRERELEASE[@]}" \
  --repo "$BRAVERY_REPO" \
  --title "Bravery $VERSION (r$BRAVERY_REVISION)" \
  --notes "$NOTES" \
  --target "$(git -C "$BRAVERY_ROOT" rev-parse HEAD)"
