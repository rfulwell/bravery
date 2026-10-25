#!/usr/bin/env bash
# One-time: creates the signing key every Bravery build is signed with.
set -euo pipefail
source "$(dirname "$0")/common.sh"

KEYSTORE="${1:-$HOME/.bravery/bravery.keystore}"
[[ -e "$KEYSTORE" ]] && die "$KEYSTORE already exists; refusing to overwrite your signing key"
mkdir -p "$(dirname "$KEYSTORE")"
chmod 700 "$(dirname "$KEYSTORE")"

read -rsp 'New keystore password (min 6 chars): ' PASS; echo
keytool -genkeypair -v -keystore "$KEYSTORE" -alias bravery \
  -keyalg RSA -keysize 4096 -validity 36500 \
  -storepass "$PASS" -keypass "$PASS" -dname 'CN=Bravery'
chmod 600 "$KEYSTORE"

log "Created $KEYSTORE"
log "Set BRAVERY_KEYSTORE_PASSWORD and BRAVERY_KEY_PASSWORD in $BRAVERY_CONF."
log "Back this file up somewhere safe. Without it you cannot update Bravery."
