# Bravery build machine as a container. Chromium's Android toolchain only
# ships x86-64 Linux binaries, so this image is always linux/amd64: native on
# Intel, run through Rosetta by Docker Desktop on Apple Silicon.
FROM --platform=linux/amd64 ubuntu:24.04

# Chromium version whose dependency list is installed. Bumping it is only
# needed if a new Chromium starts requiring extra system packages.
ARG CHROMIUM_DEPS_TAG=156.0.8078.48
# GitHub Actions runner version; "latest" resolves at build time.
ARG RUNNER_VERSION=latest
ARG NODE_MAJOR=24

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential ca-certificates curl file git git-lfs gnupg jq \
      lsb-release openjdk-17-jdk-headless python3 python3-venv python3-yaml \
      sudo unzip xz-utils zip \
    && rm -rf /var/lib/apt/lists/*

# Node.js from nodejs.org (Brave requires the 24.x line), checksum-verified.
RUN cd /tmp \
    && base="https://nodejs.org/dist/latest-v${NODE_MAJOR}.x" \
    && curl -fsSLO "$base/SHASUMS256.txt" \
    && tarball="$(grep -o 'node-v[0-9.]*-linux-x64.tar.xz' SHASUMS256.txt)" \
    && curl -fsSLO "$base/$tarball" \
    && grep " $tarball\$" SHASUMS256.txt | sha256sum -c - \
    && tar -xJf "$tarball" -C /usr/local --strip-components=1 --no-same-owner \
    && rm -f "$tarball" SHASUMS256.txt \
    && corepack enable \
    && node --version

RUN mkdir -p -m 755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
       -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
       > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Chromium's own list of build dependencies for Android.
RUN mkdir /tmp/deps && cd /tmp/deps \
    && for f in install-build-deps.sh install-build-deps.py; do \
         curl -fsSLO "https://raw.githubusercontent.com/chromium/chromium/${CHROMIUM_DEPS_TAG}/build/$f"; \
       done \
    && chmod +x install-build-deps.* \
    && ./install-build-deps.sh --android --no-prompt --no-chromeos-fonts --no-nacl \
    && rm -rf /tmp/deps /var/lib/apt/lists/* \
    && mkdir -p /etc/bravery && touch /etc/bravery/build-deps-done

# GitHub Actions runner, copied into its volume on first start.
RUN if [ "$RUNNER_VERSION" = latest ]; then \
      RUNNER_VERSION="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/actions/runner/releases/latest | sed 's#.*/v##')"; \
    fi \
    && mkdir -p /opt/actions-runner && cd /opt/actions-runner \
    && curl -fsSL "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" | tar xz \
    && ./bin/installdependencies.sh \
    && rm -rf /var/lib/apt/lists/*

# Ubuntu 24.04 images ship a uid-1000 "ubuntu" user; reuse the uid.
RUN userdel -r ubuntu 2>/dev/null; \
    useradd -m -u 1000 -s /bin/bash bravery \
    && echo 'bravery ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/bravery \
    && mkdir -p /home/bravery/bravery-build /home/bravery/actions-runner /home/bravery/.bravery \
    && chown -R bravery:bravery /home/bravery /opt/actions-runner

COPY entrypoint.sh /usr/local/bin/bravery-entrypoint

USER bravery
WORKDIR /home/bravery
ENV BRAVERY_DEPS_MARKER=/etc/bravery/build-deps-done \
    BRAVERY_WORKDIR=/home/bravery/bravery-build

ENTRYPOINT ["/usr/local/bin/bravery-entrypoint"]
CMD ["runner"]
