Help me capture why Bravery crashes on my Pixel 8 Pro, using adb from this Mac.

## Context

Bravery is my custom build of Brave for Android (package
`com.brave.browser_bravery`, repo https://github.com/rfulwell/bravery). It was
built on this Mac in Docker (`~/bravery/docker`, service `bravery`). The build
output, including the unstripped native library, is in the container's
`/home/bravery/bravery-build/src/out/android_Release_arm64`. Bravery installs
fine, but it crashes on startup right after the welcome/onboarding screens,
every time it's opened.

I want a crash report I can hand to another Claude session that wrote the code.
Your job is to capture and clean up the crash, not to fix it.

## Rules

- I do everything on the phone (taps, pairing codes, opening Bravery). Tell me
  exactly what to tap and wait for me to confirm.
- Don't uninstall Bravery, clear its data, or change any phone settings beyond
  enabling wireless debugging.
- Logs contain other apps' data. Keep full logs on this Mac only. The report you
  give me should contain only lines from Bravery's crash.

## Steps

1. **adb.** If `adb` is missing, install it with
   `brew install --cask android-platform-tools`. Check `adb version`.

2. **Connect wirelessly.** Walk me through it:
   - If Developer options aren't on: Settings → About phone, tap **Build number**
     7 times.
   - Settings → System → Developer options → **Wireless debugging** on. The phone
     must be on the same Wi-Fi as this Mac.
   - Tap **Pair device with pairing code**. I'll read you the IP:port and code,
     or run `adb pair <ip:port>` myself and type the code.
   - Then run `adb connect <ip:port>` with the address shown on the Wireless
     debugging screen. That's a different port from the pairing one.
   - Confirm with `adb devices` and
     `adb shell dumpsys package com.brave.browser_bravery | grep -m1 versionName`.
     It should say `1.98.60-bravery1`.

3. **Reproduce.** Run `adb logcat -c`, then ask me to open Bravery and wait for it
   to crash. Then save:
   ```bash
   mkdir -p ~/bravery-crash
   adb logcat -d -b crash > ~/bravery-crash/crash-buffer.txt
   adb logcat -d -v threadtime > ~/bravery-crash/full.txt
   ```
   Repeat once to confirm the crash is consistent. Save the second run as
   `crash-buffer-2.txt` and `full-2.txt`.

4. **Find the crash.**
   - **Java crash:** look for `FATAL EXCEPTION` / `AndroidRuntime` with
     `Process: com.brave.browser_bravery`. Copy the whole exception, including
     every `Caused by:` section and its full `at ...` lines.
   - **Native crash:** look for `Fatal signal`, `*** *** ***`, `backtrace:` and
     `libchrome.so`. Copy the whole backtrace block, including the signal, fault
     address and abort message if any.
   - Also copy, from the main log, the last ~40 lines logged by Bravery's process
     ID(s) before the crash. Find the PID from the crash lines or with
     `grep com.brave.browser_bravery`.
   - If neither buffer shows a crash, check `adb shell dumpsys dropbox --print`
     for `data_app_crash` / `data_app_native_crash` entries from
     `com.brave.browser_bravery`. As a last resort, ask me before running
     `adb bugreport ~/bravery-crash/bugreport.zip`; it's large and holds
     tombstones.

5. **Symbolize a native crash.** Skip this for a Java crash. Chromium's `stack`
   script turns the backtrace into function names using the build output:
   ```bash
   cd ~/bravery/docker
   docker compose run --rm -v ~/bravery-crash:/crash bravery bash -c '
     cd ~/bravery-build/src &&
     third_party/android_platform/development/scripts/stack \
       --output-directory out/android_Release_arm64 /crash/crash-buffer.txt \
       > /crash/symbolized.txt 2>&1'
   ```
   If the script complains, show me its error, try once to adjust (for example
   feeding it only the backtrace lines), and otherwise keep the raw backtrace.

6. **Report.** Write `~/bravery-crash/report.md` with:
   - the app version and Android version (`adb shell getprop ro.build.version.release`)
   - whether the crash is Java or native, and whether it reproduced both times
   - the full Java exception, or the native backtrace (symbolized if step 5 worked)
   - the ~40 Bravery log lines before the crash

   Then print the report here so I can copy it. Don't speculate about a fix.

7. **Afterwards.** Remind me I can turn **Wireless debugging** off again.
