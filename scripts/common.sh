# Shared helpers for Bravery scripts. Source, don't execute.
# shellcheck shell=bash

BRAVERY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRAVERY_CONF="${BRAVERY_CONF:-$HOME/.bravery/bravery.conf}"

log() { printf '\n\033[1;34m[bravery]\033[0m %s\n' "$*" >&2; }
die() { printf '\n\033[1;31m[bravery] error:\033[0m %s\n' "$*" >&2; exit 1; }

load_config() {
  [[ -f "$BRAVERY_CONF" ]] || die "missing $BRAVERY_CONF (copy config/bravery.conf.example)"
  # shellcheck source=/dev/null
  source "$BRAVERY_CONF"
  : "${BRAVERY_REPO:?set BRAVERY_REPO in $BRAVERY_CONF}"
  BRAVERY_WORKDIR="${BRAVERY_WORKDIR:-$HOME/bravery-build}"
  BRAVERY_TARGET_ARCH="${BRAVERY_TARGET_ARCH:-arm64}"
  BRAVERY_OFFICIAL_BUILD="${BRAVERY_OFFICIAL_BUILD:-1}"
  BRAVERY_SRC="$BRAVERY_WORKDIR/src"
  BRAVERY_BRAVE_CORE="$BRAVERY_SRC/brave"
  BRAVERY_REVISION="$(tr -d '[:space:]' < "$BRAVERY_ROOT/BRAVERY_REVISION")"
}

# Release tag for a Brave version, e.g. v1.98.61 -> v1.98.61-bravery1
release_tag_for() {
  echo "v${1#v}-bravery${BRAVERY_REVISION}"
}
