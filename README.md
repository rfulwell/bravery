# Bravery

Bravery is the Brave browser for Android plus a few personal features. It
installs alongside the regular Brave app, stays in sync with Brave releases,
and updates itself on your phone the way a store app would.

## Features

| Feature | What it does |
| --- | --- |
| **Tap to scroll** | Tap a scroll zone (top/bottom edges, left/right sides, or corners) to scroll by part of a screen. Built into the browser, so taps on links, buttons, form fields and script-driven controls behave normally; only taps the page ignored scroll. The scroll is a real drag at the tap point, so inner scrollers work and the address bar hides as it would for a swipe. You can turn it off per site from the long-press menu. |
| **Auto-hiding address bar** | Chromium pins the address bar whenever an accessibility app that can perform gestures is running (Tap2Scroll was one). That was why the URL bar never hid. Bravery turns that lock into a setting and lets the bar hide by default. |
| **Banner hiding** | Long-press a banner (cookie notice, "open in app" bar, sticky header, overlay) and choose **Auto-hide banner** (it slides away as you scroll down and comes back when you scroll up, like the address bar) or **Remove banner**. Long-pressing text inside a banner offers **Hide banner** in the text selection menu. Choices are remembered per site, except in private tabs. |

All settings are under **Settings → Bravery**.

## Status

> [!WARNING]
> **No APK has been built from these patches yet.** The code has been checked as
> far as possible without a full browser build (about 3 hours on a large machine).
> The first build on your VM is the real test, and it may need a fix or two.

What has been verified:

- The patches apply cleanly to brave-core `v1.98.61` (stable) and `v1.100.31` (nightly).
- The two Chromium-level rewrite rules match Chromium `156.0.8078.48` exactly once each.
- The Java compiles against the Android 14 API and stubs whose signatures were
  copied from the Chromium 156 sources. It has not been compiled against the real
  Chromium classes.
- The banner script passes 14 behavioural checks in headless Chromium: finding
  fixed and sticky banners from a point or a text selection, both hiding modes,
  scroll show/hide, per-site rules re-applied on reload, late-inserted banners,
  and unlocking scroll after removing a modal.

Not yet verified: native tap-to-scroll on a device, the long-press menu
appearing on empty areas, Sync, and filter-list updates.

### Brave Sync and filter-list updates: known risk

Brave's official builds include a private "services key" that is sent with
requests to some Brave servers, including **Sync** and the **component updater
that delivers ad-block filter lists**. Custom builds don't have that key. Bravery
sends a placeholder, and whether Brave's servers accept requests without a real
key is unknown until it's tried. After the first install, check:

1. `brave://components`: click **Check for update** on the ad-block components.
2. **Settings → Sync**: join your existing sync chain with its code words.

If either fails, that feature needs a key. You can set your own legitimately
obtained keys in `bravery.conf` (`BRAVERY_BRAVE_SERVICES_KEY` and others). The
regular Brave app keeps working either way, since Bravery is a separate app.

## How it works

```
GitHub's free runners, every 4 hours (watch-brave.yml)
  latest stable tag from github.com/brave/brave-browser
  already published, or a build already queued? → stop
  patches still apply? (no compiling) → no: open an issue, stop
  → queue "Build Bravery"
        ▼
Your machine, as a self-hosted runner (build.yml → auto-update.sh)
  build.sh
    1. brave-core @ tag, Chromium synced by Brave's tooling
    2. git am patches/*.patch           (Bravery's changes)
    3. plaster rules → Chromium patches  (regex rewrites, rebase-friendly)
    4. pnpm run build Release (android, arm64, apk,
       package com.brave.browser_bravery)
    5. apksigner with your key
  publish.sh → GitHub release v1.98.61-bravery1 (+ APK)
        ▼
Obtainium on your phone installs the update
```

- **`patches/`** is a `git format-patch` series against brave-core. Most changes
  are new files, so most of the series survives Brave updates unchanged.
- Chromium-level changes are **plaster** rules (`rewrite/*.yaml` inside the
  patches): Brave's regex rewriting tool, made for surviving Chromium upgrades.
  There are two: the accessibility toolbar lock, and making Blink count a tap
  as handled when the page visibly reacted to it.
- **Only what a Pixel needs is built:** Android, 64-bit ARM, one APK. The 32-bit
  copy of the native code (which official builds include by default, roughly
  doubling native compile time) is skipped, as are debug symbols, Java lint and
  static analysis. The Chromium checkout is shallow. The result runs on any
  64-bit-only phone, such as a Pixel 7 or newer. Brave's local-build defaults
  also avoid rebuilding thousands of files just because the version changed. One
  side effect is that `brave://version` shows e.g. `1.98.0` instead of `1.98.61`.
  The installed app and the release tag still show the full version.
- All the checking happens on GitHub's free runners. Your machine never polls;
  it only works when there's a new release to build.
- **`check-patches.yml`** also runs daily on free runners, testing the patches
  against Brave's latest **beta** as well as stable. Beta gives you weeks of
  warning before a stable release would need a patch fix.
- If the build itself fails, `auto-update.sh` opens an issue with the end of the log.
- **Startup check (experimental, off by default):** `smoke-test.yml` installs an
  APK on an Android emulator, taps through the welcome screens, opens a page,
  and watches for crashes. It isn't usable on GitHub's free runners yet:
  - On the x86_64 emulator, Chromium crashes under ARM translation, and
    official Brave crashes the same way.
  - The ARM runners (`arm64` option) have no KVM, so they can't run an
    accelerated emulator.

  It needs a runner that can run a native ARM64 emulator, such as a
  self-hosted runner on an Apple Silicon Mac outside Docker. With one, setting
  the repository variable `BRAVERY_STARTUP_CHECK=gate` makes every build
  publish as a pre-release, which Obtainium ignores by default, and promotes it
  only if the check passes. The `apk_url` field on **Actions → Startup check →
  Run workflow** tests any APK, such as official Brave, as a control.

## Setting up the build machine

Using Docker Desktop on a Mac? Skip to [Building on a Mac with Docker Desktop](#building-on-a-mac-with-docker-desktop).

You need an x86-64 Ubuntu 22.04/24.04 VM with 16+ cores, 64 GB RAM (or 32 GB
with `BRAVERY_OFFICIAL_BUILD=0`) and about 400 GB of SSD. The first build
downloads around 100 GB and takes several hours. Later builds reuse the checkout
and are much faster.

```bash
git clone https://github.com/rfulwell/bravery ~/bravery
cd ~/bravery
scripts/setup-build-machine.sh      # packages, Node 24, pnpm, gh; creates ~/.bravery/bravery.conf
scripts/make-keystore.sh            # your signing key; put its password in bravery.conf
$EDITOR ~/.bravery/bravery.conf
```

> [!IMPORTANT]
> Back up `~/.bravery/bravery.keystore` and its password. Android only installs
> an update signed with the same key, so losing the key means uninstalling Bravery
> and losing its data.

The first build stops once and asks you to run Chromium's
`install-build-deps.sh --android` with sudo, unless passwordless sudo is set up.

### Connecting the machine to GitHub

Register the machine as a self-hosted runner so GitHub can hand it builds:

1. In the repo, open **Settings → Actions → Runners → New self-hosted runner**,
   choose Linux x64, and run the download and `./config.sh` commands it shows in
   `~/actions-runner`. When `config.sh` asks for labels, enter `bravery`.
2. Install it as a service so it starts at boot:
   `cd ~/actions-runner && sudo ./svc.sh install "$USER" && sudo ./svc.sh start`.
3. Start the first build from **Actions → Watch for Brave releases → Run workflow**.
   It queues **Build Bravery** on your machine.

After that, everything is automatic. If the machine is off when a build is
queued, the job waits up to 24 hours and starts as soon as the runner comes
online. If it waits longer, the watcher queues it again on its next run. For a
VM that boots on a schedule, set `BRAVERY_SHUTDOWN_WHEN_DONE=1` so it powers off
after a build. That needs passwordless `sudo shutdown`. The GitHub token the job
uses covers releases and issues, so `gh auth login` is only needed on the
machine if you run the scripts by hand.

Prefer no runner? `scripts/auto-update.sh` does the same check, build and
publish by itself, from cron or the systemd units in `config/systemd/`. In that
setup the machine polls instead of GitHub, and it needs `gh auth login`.

## Building on a Mac with Docker Desktop

`docker/` packages the whole build machine, including the GitHub runner, as a
container. Chromium's Android toolchain only exists for x86-64 Linux, so the
container is always `linux/amd64`. On an Intel Mac it runs natively. On Apple
Silicon, Docker Desktop runs it through Rosetta, which works but is slower than
native (rough guess: 30–50% slower).

**Docker Desktop settings**

| Setting | Value |
| --- | --- |
| General → *Use Rosetta for x86_64/amd64 emulation on Apple Silicon* | On. Without it, QEMU emulation would take days per build. |
| General → *Start Docker Desktop when you sign in* | On |
| Resources → Memory | 48–56 GB of your 64 GB |
| Resources → CPU | All cores |
| Resources → Swap | 4 GB or more |
| Resources → Disk usage limit | 400 GB or more. The disk image can live on an external SSD (Resources → Advanced). |

Also keep the Mac awake: **System Settings → Energy → Prevent automatic
sleeping when the display is off**. Docker Desktop only runs while you're
logged in.

**Memory:** 64 GB is enough, but the container gets less than that after macOS
takes its share. Bravery builds without debug symbols, which keeps links far
lighter. Still, for the first build set `BRAVERY_OFFICIAL_BUILD=0` and
`BRAVERY_CONCURRENT_LINKS=1` in `~/.bravery/bravery.conf`. Once that works, try
`BRAVERY_OFFICIAL_BUILD=1`. It's a little faster on the phone, but compiles
noticeably slower and needs the most memory when linking.

Using Claude Code on the Mac? Paste [docs/mac-mini-setup-prompt.md](docs/mac-mini-setup-prompt.md)
into a session there and it will walk through all of this with you.

**Setup**, in Terminal on the Mac:

```bash
git clone https://github.com/rfulwell/bravery ~/bravery
cd ~/bravery/docker
mkdir -p ~/.bravery                          # config + signing key live here, on the Mac
docker compose build                         # ~10 minutes
docker compose run --rm bravery setup        # creates bravery.conf and the signing key
nano ~/.bravery/bravery.conf                 # keystore password, BRAVERY_OFFICIAL_BUILD=0, BRAVERY_CONCURRENT_LINKS=1
```

Then connect it to GitHub. In the repo, open **Settings → Actions → Runners →
New self-hosted runner** and copy only the token from the `./config.sh` line:

```bash
docker compose run --rm bravery register <token>
docker compose up -d                         # runner starts now and with Docker Desktop
```

Start the first build from **Actions → Watch for Brave releases → Run workflow**.
Follow it in the Actions tab or with `docker compose logs -f`. The Brave and
Chromium checkout (~350 GB with build output) lives in a Docker volume, not in a
Mac folder. A volume is much faster, and Chromium needs a case-sensitive
filesystem. Your config and key stay in `~/.bravery`, so include that folder in
your backups.

Other commands: `docker compose run --rm bravery build [vX.Y.Z]` builds and
publishes without GitHub Actions (run `gh auth login` in
`docker compose run --rm bravery shell` first), and `... shell` opens a shell in
the build environment.

## Installing on your phone

1. Install [Obtainium](https://github.com/ImranR98/Obtainium) (from its GitHub
   releases or F-Droid).
2. In Obtainium, **Add app** with the URL `https://github.com/rfulwell/bravery`.
   If the repo is private, add a GitHub token in Obtainium's settings.
3. Install Bravery. It appears as **Bravery** (package `com.brave.browser_bravery`)
   next to Brave, with its own profile.
4. Leave Obtainium's "Include prereleases" off for Bravery. If the startup check
   gates releases, releases that haven't passed it yet are pre-releases.
5. In Obtainium, enable background updates. On Android 12+ updates then install
   without prompts.
6. **Settings → Sync** in Bravery: join the same sync chain as Brave (see the risk
   note above).

If you used Tap2Scroll, disable its accessibility service. Bravery's built-in
tap-to-scroll replaces it, and Brave's address bar starts auto-hiding again even
without Bravery.

## When Brave changes break a patch

The daily check opens an issue. To fix it:

```bash
cd ~/bravery-build/src/brave
git checkout --force vX.Y.Z
git am -3 ~/bravery/patches/*.patch     # resolve conflicts, git am --continue
~/bravery/scripts/check-patches.sh vX.Y.Z
~/bravery/scripts/export-patches.sh ~/bravery-build/src/brave vX.Y.Z
```

Then commit and push. The next scheduled run builds it. To rebuild a Brave
version that's already published, for example after a patch fix, bump
`BRAVERY_REVISION`.

## Repository layout

| Path | Purpose |
| --- | --- |
| `patches/` | Bravery's changes to brave-core, as a `git format-patch` series |
| `BRAVERY_REVISION` | Patch revision, part of each release tag (`v1.98.61-bravery1`) |
| `.github/workflows/watch-brave.yml` | Free-runner watcher: detect release, check patches, queue build |
| `.github/workflows/build.yml` | Build job for your machine (self-hosted runner) |
| `scripts/auto-update.sh` | Build entry point: build if unpublished, publish, report failures |
| `scripts/build.sh` | Sync, patch, compile, sign one Brave release |
| `scripts/publish.sh` | Create the GitHub release Obtainium installs from |
| `scripts/check-patches.sh` | Apply-only check against any Brave tag (no build) |
| `scripts/latest-brave-release.sh` | Latest Brave stable or beta tag |
| `scripts/setup-build-machine.sh` | One-time machine setup |
| `scripts/make-keystore.sh` | One-time signing key |
| `scripts/export-patches.sh` | Write patches back after editing them in brave-core |
| `config/` | Config template; systemd units for the no-runner setup |
| `docker/` | Build machine as a container (Docker Desktop on a Mac) |

## Where the code lives (inside the patches)

| brave-core path | Role |
| --- | --- |
| `android/java/.../bravery/BraveryTapToScroll.java` | Tap detection, zones, synthetic drag |
| `android/java/.../bravery/BraveryController.java` | Attaches features to every page view |
| `android/java/.../bravery/BraveryBannerHider.java` | Banner commands, per-site rules |
| `android/java/.../bravery/BraveryContextMenu.java` | Long-press menu items |
| `android/java/.../bravery/BraverySelectionMenuDelegate.java` | "Hide banner" in the text selection menu |
| `android/java/.../bravery/BraveryPreferences.java` | Settings → Bravery |
| `browser/android/bravery/bravery_banner_hider.js` | Page-side banner logic (Brave's isolated world) |
| `browser/android/bravery/bravery_banner_hider_android.cc` | Runs that script from Java (JNI) |
| `components/embedder_support/.../BraveContentView.java` | Hook that reports page touches |
| `rewrite/.../TabStateBrowserControlsVisibilityDelegate.java.yaml` | Toolbar accessibility lock → setting |
| `rewrite/.../gesture_manager.cc.yaml` | Taps the page reacted to count as handled |
| `app/theme/brave/android/res_brave_base/values/channel_constants.xml` | App name "Bravery" |

Bravery is a personal modification of Brave, which is licensed under the
[MPL 2.0](https://mozilla.org/MPL/2.0/). It is not affiliated with Brave Software.
