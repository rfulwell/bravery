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
Brave release ──► auto-update.sh (cron/systemd on your VM)
                    │  latest stable tag from github.com/brave/brave-browser
                    │  already published? → stop
                    ▼
                  build.sh
                    1. brave-core @ tag, Chromium synced by Brave's tooling
                    2. git am patches/*.patch           (Bravery's changes)
                    3. plaster rules → Chromium patches  (regex rewrites, rebase-friendly)
                    4. pnpm run build Release (android, arm64, apk,
                       package com.brave.browser_bravery)
                    5. apksigner with your key
                    ▼
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
- **`check-patches.yml`** runs daily on free GitHub runners. It tests the patches
  against Brave's latest **stable and beta** releases without building, and opens
  an issue if they stop applying. Beta gives you weeks of warning.
- If the build itself fails, `auto-update.sh` opens an issue with the end of the log.

## Setting up the build machine

You need an x86-64 Ubuntu 22.04/24.04 VM with 16+ cores, 64 GB RAM (or 32 GB
with `BRAVERY_OFFICIAL_BUILD=0`) and about 400 GB of SSD. The first build
downloads around 100 GB and takes several hours. Later builds reuse the checkout
and are much faster.

```bash
git clone https://github.com/rfulwell/bravery ~/bravery
cd ~/bravery
scripts/setup-build-machine.sh      # packages, Node 24, pnpm, gh; creates ~/.bravery/bravery.conf
gh auth login                       # needs write access to this repo (releases, issues)
scripts/make-keystore.sh            # your signing key; put its password in bravery.conf
$EDITOR ~/.bravery/bravery.conf
scripts/auto-update.sh              # first full build + release
```

> [!IMPORTANT]
> Back up `~/.bravery/bravery.keystore` and its password. Android only installs
> an update signed with the same key, so losing the key means uninstalling Bravery
> and losing its data.

The first run stops once and asks you to run Chromium's
`install-build-deps.sh --android` with sudo (unless passwordless sudo is set up).

### Scheduling

Choose one of these.

- **systemd timer (recommended):** copy `config/systemd/bravery-update.*` to
  `~/.config/systemd/user/`, then run
  `systemctl --user enable --now bravery-update.timer` and
  `sudo loginctl enable-linger $USER`. This checks every 6 hours.
- **cron:** `0 3 * * * $HOME/bravery/scripts/auto-update.sh >> $HOME/bravery-update.log 2>&1`
- **VM that only boots on a schedule:** run `scripts/auto-update.sh` at boot and
  set `BRAVERY_SHUTDOWN_WHEN_DONE=1` so the VM powers off when it finishes.
- **GitHub Actions:** register the VM as a self-hosted runner with the label
  `bravery`, and `.github/workflows/build.yml` runs the same script.

`auto-update.sh` does nothing when the latest Brave release is already
published, so it's safe to run often.

## Installing on your phone

1. Install [Obtainium](https://github.com/ImranR98/Obtainium) (from its GitHub
   releases or F-Droid).
2. In Obtainium, **Add app** with the URL `https://github.com/rfulwell/bravery`.
   If the repo is private, add a GitHub token in Obtainium's settings.
3. Install Bravery. It appears as **Bravery** (package `com.brave.browser_bravery`)
   next to Brave, with its own profile.
4. In Obtainium, enable background updates. On Android 12+ updates then install
   without prompts.
5. **Settings → Sync** in Bravery: join the same sync chain as Brave (see the risk
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
| `scripts/auto-update.sh` | Scheduled entry point: detect, build, publish, report |
| `scripts/build.sh` | Sync, patch, compile, sign one Brave release |
| `scripts/publish.sh` | Create the GitHub release Obtainium installs from |
| `scripts/check-patches.sh` | Apply-only check against any Brave tag (no build) |
| `scripts/latest-brave-release.sh` | Latest Brave stable or beta tag |
| `scripts/setup-build-machine.sh` | One-time machine setup |
| `scripts/make-keystore.sh` | One-time signing key |
| `scripts/export-patches.sh` | Write patches back after editing them in brave-core |
| `config/` | Config template and systemd units |

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
