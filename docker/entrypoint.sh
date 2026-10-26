#!/usr/bin/env bash
# Commands (docker compose run --rm bravery <command>):
#   setup               create ~/.bravery/bravery.conf and the signing key
#   register <token>    connect to GitHub as a self-hosted runner (one time)
#   runner              wait for builds from GitHub (the default)
#   build [brave tag]   build and publish now, without GitHub Actions
#   shell               a shell inside the build environment
set -euo pipefail

REPO="${BRAVERY_REPO:-rfulwell/bravery}"
REPO_URL="https://github.com/$REPO"
RUNNER_DIR="$HOME/actions-runner"
CHECKOUT="$BRAVERY_WORKDIR/bravery"

checkout() {
  if [[ -d "$CHECKOUT/.git" ]]; then
    git -C "$CHECKOUT" pull --ff-only --quiet
  else
    git clone --quiet "$REPO_URL" "$CHECKOUT"
  fi
}

ensure_runner() {
  [[ -x "$RUNNER_DIR/run.sh" ]] || cp -a /opt/actions-runner/. "$RUNNER_DIR/"
}

case "${1:-runner}" in
  setup)
    checkout
    if [[ ! -f "$HOME/.bravery/bravery.conf" ]]; then
      sed "s#^BRAVERY_REPO=.*#BRAVERY_REPO=$REPO#" \
        "$CHECKOUT/config/bravery.conf.example" > "$HOME/.bravery/bravery.conf"
      chmod 600 "$HOME/.bravery/bravery.conf"
      echo "Created ~/.bravery/bravery.conf"
    fi
    if [[ ! -f "$HOME/.bravery/bravery.keystore" ]]; then
      "$CHECKOUT/scripts/make-keystore.sh" "$HOME/.bravery/bravery.keystore"
    fi
    echo "Now set BRAVERY_KEYSTORE_PASSWORD in ~/.bravery/bravery.conf on your Mac."
    ;;
  register)
    token="${2:?usage: register <token from Settings > Actions > Runners > New self-hosted runner>}"
    ensure_runner
    cd "$RUNNER_DIR"
    ./config.sh --unattended --replace --url "$REPO_URL" --token "$token" \
      --name "${RUNNER_NAME:-bravery-docker}" --labels bravery --work _work
    ;;
  runner)
    ensure_runner
    cd "$RUNNER_DIR"
    if [[ ! -f .runner ]]; then
      echo "Not registered yet: docker compose run --rm bravery register <token>" >&2
      exit 1
    fi
    exec ./run.sh
    ;;
  build)
    checkout
    BRAVERY_UPDATED=1 BRAVERY_BRAVE_TAG="${2:-}" exec "$CHECKOUT/scripts/auto-update.sh"
    ;;
  shell)
    exec bash
    ;;
  *)
    exec "$@"
    ;;
esac
