#!/usr/bin/env bash
# One-time setup of an Ubuntu 22.04/24.04 x86-64 machine (or VM) for Bravery
# builds. Run as a normal user with sudo rights:
#
#   scripts/setup-build-machine.sh
#
# Recommended machine: 16+ cores, 64 GB RAM (32 GB with BRAVERY_OFFICIAL_BUILD=0),
# 400 GB free disk on an SSD.
set -euo pipefail
source "$(dirname "$0")/common.sh"

NODE_MAJOR=24

[[ "$(uname -m)" == x86_64 ]] || die "Chromium for Android must be built on x86-64 Linux"

log "Installing system packages"
sudo apt-get update
sudo apt-get install -y \
  build-essential ca-certificates curl git git-lfs gnupg lsb-release \
  python3 python3-venv openjdk-17-jdk-headless unzip zip

if ! node --version 2>/dev/null | grep -q "^v$NODE_MAJOR\."; then
  log "Installing Node.js $NODE_MAJOR"
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | sudo -E bash -
  sudo apt-get install -y nodejs
fi

log "Enabling pnpm"
sudo corepack enable
corepack prepare pnpm@latest --activate

if ! command -v gh >/dev/null; then
  log "Installing GitHub CLI"
  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update
  sudo apt-get install -y gh
fi

mkdir -p "$HOME/.bravery"
chmod 700 "$HOME/.bravery"
if [[ ! -f "$BRAVERY_CONF" ]]; then
  cp "$BRAVERY_ROOT/config/bravery.conf.example" "$BRAVERY_CONF"
  chmod 600 "$BRAVERY_CONF"
  log "Created $BRAVERY_CONF; edit it before building"
fi

cat >&2 <<EOF

Next steps:
  1. gh auth login                       (needs write access to the Bravery repo)
  2. scripts/make-keystore.sh            (then put the password in $BRAVERY_CONF)
  3. scripts/auto-update.sh              (first run downloads ~100 GB and builds for hours;
                                          it stops once to ask you to run Chromium's
                                          install-build-deps.sh with sudo)
  4. Schedule scripts/auto-update.sh     (see README: cron or systemd timer)
EOF
