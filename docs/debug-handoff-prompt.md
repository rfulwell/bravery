You're taking over debugging and fixing my Bravery browser build on this Mac.
It installs on my Pixel 8 Pro but crashes on startup right after the
welcome/onboarding screens, every time. Find the cause, fix it, and verify the
fix on the phone, then get it into the automated release pipeline.

## What Bravery is

My personal build of Brave for Android, repo https://github.com/rfulwell/bravery
(cloned at `~/bravery`; `git pull` first). Read `README.md` to understand it. It
installs as package `com.brave.browser_bravery`, alongside regular Brave, and
adds three features:

- native tap to scroll
- a setting that lets the toolbar auto-hide even when an accessibility service is on
- long-press "Auto-hide banner" / "Remove banner"

The code lives as a `git format-patch` series against brave-core in
`~/bravery/patches/`. Chromium-level changes are "plaster" regex rules
(`rewrite/*.yaml`) inside those patches. Brave documents them in
`docs/plaster.md` in brave-core.

Where the code lives, inside the patches:

| brave-core path | Role |
| --- | --- |
| `android/java/org/chromium/chrome/browser/bravery/*.java` | All Bravery Java code. `BraveryController` hooks every page view; then tap to scroll, banner hiding, menus, prefs, settings |
| `components/embedder_support/.../view/BraveContentView.java` | Hook that reports page touches and WebContents changes to `BraveryController` |
| `android/java/org/chromium/chrome/browser/BraveApplicationImplBase.java` | Calls `BraveryController.install()` at process start |
| `android/java/.../contextmenu/BraveChromeContextMenuPopulator.java` | Adds Bravery's long-press menu items |
| `android/java/.../settings/BraveMainPreferencesBase.java`, `android/java/brave-res/xml/brave_main_preferences.xml` | Settings → Bravery entry |
| `browser/android/bravery/` | JNI bridge + `bravery_banner_hider.js`, run in Brave's internal isolated world |
| `rewrite/.../TabStateBrowserControlsVisibilityDelegate.java.yaml`, `rewrite/.../gesture_manager.cc.yaml`, `rewrite/chrome/android/expectations/expectations.gni.yaml` | Plaster rules |
| `app/theme/brave/android/res_brave_base/values/channel_constants.xml` | App name |

None of this had run on a device before this build. The Java was only
compile-checked against stubs, so suspect Bravery's own code first, but go by
the evidence.

## The build environment on this Mac

- Docker Desktop, `~/bravery/docker/compose.yaml`, service `bravery`
  (linux/amd64 image). It's also a GitHub Actions self-hosted runner that
  GitHub uses to build releases.
- Config and the signing key are in `~/.bravery` on the Mac, mounted into the
  container. Never print or copy the keystore password anywhere.
- The checkout is in the `build` Docker volume at `/home/bravery/bravery-build`:
  - `src/` is Chromium
  - `src/brave` is brave-core at tag `v1.98.60` with the Bravery patches applied
    as 3 commits
  - `src/out/android_Release_arm64` is the build output from the published build
    (`BRAVERY_OFFICIAL_BUILD=0`)
- `scripts/build.sh --dev` rebuilds that checkout as it is, keeping your edits:
  no checkout, sync or patching, and only what changed recompiles. It re-applies
  plaster rules you edit, signs with my key, and writes
  `~/bravery-build/dist/Bravery-…-dev-arm64.apk`. Because it's signed with the
  same key, `adb install -r` updates the installed app in place.
- The brave-core checkout has its own `.claude/CLAUDE.md`. Follow its rule:
  never delete caches or `out/` directories without asking me.

## Rules

- **Pause automatic builds while you work.** Run `docker compose stop` in
  `~/bravery/docker` before editing. A release build that starts in the middle
  would reset `src/brave` and wipe your edits. `docker compose run --rm bravery …`
  still works while it's stopped. Run `docker compose up -d` again when you're done.
- I do everything on the phone (taps, pairing codes, opening the app). Tell me
  exactly what to do and wait.
- Ask me before:
  - pushing to GitHub
  - triggering a release build
  - anything that deletes data on this Mac or the phone, including uninstalling
    Bravery or clearing its data
- Never push to Brave's repos. Changes reach Bravery only as updated
  `patches/*.patch` in `~/bravery`.
- Keep full device logs on this Mac. Only show me or commit the relevant lines.

## Steps

1. **Capture the crash.** Follow `~/bravery/docs/crash-log-prompt.md` (adb over
   wireless debugging, logcat, symbolizing a native crash) and show me the report.

2. **Diagnose.** Read the relevant code in the container:
   ```bash
   docker compose run --rm bravery shell
   cd ~/bravery-build/src/brave
   ```
   Explain the root cause to me in a few sentences before fixing it. If the
   evidence isn't conclusive, add logging rather than guessing.

3. **Fix and loop.** Edit in `~/bravery-build/src/brave`, then:
   ```bash
   docker compose run --rm -v ~/bravery-dist:/out bravery bash -c \
     'git -C ~/bravery-build/bravery pull -q --ff-only &&
      apk=$(~/bravery-build/bravery/scripts/build.sh --dev | tail -n1) && cp "$apk" /out/'
   adb install -r ~/bravery-dist/Bravery-*-dev-arm64.apk
   ```
   If `~/bravery-build/bravery` is missing, `docker compose run --rm bravery setup`
   clones it without touching my config or key. Then ask me to open Bravery, and
   check logcat again. Repeat until it starts cleanly.

4. **Test the features with me** once it starts:
   - tap near the top and bottom edges (links and buttons must still work)
   - long-press a cookie banner or sticky header (both banner items)
   - the address bar hides while scrolling
   - Settings → Bravery opens
   - Settings → Sync can join my sync chain
   - `brave://components` → ad-block components update

   Note what fails. Fix Bravery bugs the same way. The Sync and filter-list
   checks depend on Brave's servers accepting a build without Brave's private
   service key, so if those fail, just report it to me.

5. **Hand the fix to the pipeline.**
   - Commit your edits on top of the 3 patch commits in `src/brave`: a fixup to
     the commit it belongs to, or a new commit. Use
     `git -c user.name=Claude -c user.email=noreply@anthropic.com`.
   - Write the patches straight into the Mac's `~/bravery`:
     `docker compose run --rm -v ~/bravery:/repo bravery /repo/scripts/export-patches.sh ~/bravery-build/src/brave v1.98.60`
   - In `~/bravery`, bump `BRAVERY_REVISION` to 2 and run
     `scripts/check-patches.sh v1.98.60`. It needs Python with PyYAML; if the
     Mac lacks it, run it in the container with the same `-v ~/bravery:/repo` mount.
   - Show me the diff, and commit once I agree.
   - Ask me before pushing and before running
     `gh workflow run watch-brave.yml --repo rfulwell/bravery`. That builds
     `v1.98.60-bravery2`, which Obtainium then installs.

6. **Clean up.** `docker compose up -d` to resume automatic builds, and remind
   me to turn off Wireless debugging. Give me a short summary of:
   - the root cause
   - the fix
   - what was tested on the phone and what wasn't
   - anything left open

## Optional follow-ups (ask me first)

- The APK is 479 MB, mostly because the first build used
  `BRAVERY_OFFICIAL_BUILD=0`. An official build should be about half the size
  and faster, but needs more memory to link.
- Uploading Chromium's crash dumps to my own Sentry project instead of Brave's
  crash server.
