#!/usr/bin/env bash
# Startup check for a Bravery APK on a running emulator or device (via adb).
#
#   scripts/smoke-test.sh Bravery.apk out/
#
# Installs the APK, launches it, taps through the welcome screens, opens a web
# page, then taps, scrolls and long-presses on it. It watches throughout for
# Bravery's main process crashing.
#
# Exit codes: 0 passed, 1 crashed, 2 inconclusive (e.g. stuck on a screen it
# couldn't get past; see the screenshots). Writes a summary to out/result.txt
# and evidence (screenshots, UI dumps, crash log, logcat) to out/.
set -uo pipefail

APK="${1:?usage: smoke-test.sh <apk> <output dir>}"
OUT="${2:?usage: smoke-test.sh <apk> <output dir>}"
PKG="${SMOKE_PACKAGE:-com.brave.browser_bravery}"
URL=https://example.com/
# Matches Bravery's main process in Java ("Process: <pkg>, PID") and native
# (">>> <pkg> <<<") crash reports, but not its renderer/GPU processes.
CRASH_RE="(Process: ${PKG//./\\.}, |>>> ${PKG//./\\.} <<<)"
STEP=0

mkdir -p "$OUT"
log() { echo "[smoke] $*" | tee -a "$OUT/steps.txt" >&2; }
shot() { STEP=$((STEP + 1)); adb exec-out screencap -p > "$OUT/$(printf %02d "$STEP")-$1.png" 2>/dev/null || true; }
crashed() { adb logcat -d -b crash 2>/dev/null | grep -Eq "$CRASH_RE"; }
alive() { adb shell pidof "$PKG" >/dev/null 2>&1; }

# Current UI as XML on stdout (retries: uiautomator fails while animating).
ui() {

  for _ in 1 2 3; do
    if adb shell uiautomator dump /sdcard/bravery-ui.xml >/dev/null 2>&1; then
      adb shell cat /sdcard/bravery-ui.xml 2>/dev/null && return 0
    fi
    sleep 1
  done
  return 1
}

# Reads UI XML on stdin; prints "x y label" for the first welcome-flow button
# to press, "foreground" if Bravery is showing but has no such button, or
# nothing if Bravery isn't on screen.
next_button() {
  python3 -c '
import re, sys, xml.etree.ElementTree as ET
pkg = sys.argv[1]
labels = re.compile(r"^(continue|get started|accept|accept (and|&) continue|next|skip|"
                    r"not now|no thanks|maybe later|done|got it|allow|ok|okay|close|"
                    r"dismiss|cancel|i agree|agree|start browsing|let.s go)$", re.I)
try:
    root = ET.fromstring(sys.stdin.read())
except ET.ParseError:
    sys.exit()
nodes = list(root.iter("node"))
ours = [n for n in nodes if n.get("package") == pkg]
dialogs = [n for n in nodes if "permissioncontroller" in (n.get("package") or "")]
for n in ours + dialogs:
    label = (n.get("text") or n.get("content-desc") or "").strip()
    if n.get("clickable") == "true" and labels.match(label):
        x1, y1, x2, y2 = map(int, re.findall(r"\d+", n.get("bounds")))
        print((x1 + x2) // 2, (y1 + y2) // 2, label)
        sys.exit()
if ours:
    print("foreground")
' "$PKG"
}

# Reads UI XML on stdin; succeeds if the address bar shows the test page.
page_loaded() {
  python3 -c '
import sys, xml.etree.ElementTree as ET
try:
    root = ET.fromstring(sys.stdin.read())
except ET.ParseError:
    sys.exit(1)
for n in root.iter("node"):
    if (n.get("resource-id") or "").endswith("id/url_bar") and "example.com" in (n.get("text") or ""):
        sys.exit(0)
sys.exit(1)
'
}

finish() {
  local code=$1 message=$2
  log "$message"
  shot final
  adb logcat -d -b crash > "$OUT/crash-buffer.txt" 2>/dev/null
  adb logcat -d -v threadtime > "$OUT/logcat-full.txt" 2>/dev/null
  # The crash itself plus Bravery's last log lines, for the issue body.
  python3 - "$OUT" "$PKG" <<'PY' > "$OUT/crash-excerpt.txt"
import re, sys
out, pkg = sys.argv[1], sys.argv[2]
crash = open(f"{out}/crash-buffer.txt", errors="replace").read().splitlines()
blocks, current = [], []
for line in crash:
    if re.search(r"FATAL EXCEPTION|\*\*\* \*\*\* \*\*\*|Fatal signal", line) and current:
        blocks.append(current); current = []
    current.append(line)
if current:
    blocks.append(current)
ours = [b for b in blocks if any(f"Process: {pkg}," in l or f">>> {pkg} <<<" in l for l in b)]
print("\n".join(ours[0][:120]) if ours else "(no crash of the main process in the crash buffer)")
full = open(f"{out}/logcat-full.txt", errors="replace").read().splitlines()
pids = set(re.findall(rf"(?:Start proc |pid=?)(\d+):?{re.escape(pkg)}/", "\n".join(full)))
pids |= set(re.findall(rf"Process: {re.escape(pkg)}, PID: (\d+)", "\n".join(crash)))
mine = [l for l in full if len(l.split()) > 2 and l.split()[2] in pids]
if mine:
    print("\n--- last log lines from Bravery's main process ---")
    print("\n".join(mine[-40:]))
PY
  echo "$message" > "$OUT/result.txt"
  exit "$code"
}

adb wait-for-device
ABIS="$(adb shell getprop ro.product.cpu.abilist | tr -d '\r')"
log "Device ABIs: $ABIS, Android $(adb shell getprop ro.build.version.release | tr -d '\r')"
[[ "$ABIS" == *arm64-v8a* ]] || finish 2 "Inconclusive: this emulator image can't run arm64 apps ($ABIS)."

log "Installing $(basename "$APK")"
adb uninstall "$PKG" >/dev/null 2>&1
adb install -r -g "$APK" > "$OUT/install.txt" 2>&1 \
  || finish 2 "Inconclusive: install failed: $(tail -n 1 "$OUT/install.txt")"
adb logcat -b all -c

log "Launching"
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
SHOWN=0 IDLE=0
for _ in $(seq 1 45); do
  sleep 4
  crashed && finish 1 "Crashed during startup or the welcome screens."
  button="$(ui | next_button)"
  if [[ -z "$button" ]]; then
    # Not on screen yet (slow first start under ARM translation), or gone.
    (( SHOWN )) && ! alive && finish 1 "Bravery's process died during startup (no crash report)."
    continue
  fi
  SHOWN=1
  if [[ "$button" == foreground ]]; then
    (( ++IDLE >= 3 )) && break
    continue
  fi
  IDLE=0
  read -r x y label <<< "$button"
  shot "tap-${label// /-}"
  log "Tapping \"$label\""
  adb shell input tap "$x" "$y"
done
(( SHOWN )) || finish 2 "Inconclusive: Bravery never appeared on screen."
shot after-welcome

log "Opening $URL"
adb shell am start -a android.intent.action.VIEW -d "$URL" -p "$PKG" >/dev/null 2>&1
LOADED=0
for _ in $(seq 1 30); do
  sleep 3
  crashed && finish 1 "Crashed after the welcome screens, while opening a web page."
  if ui | page_loaded; then LOADED=1; break; fi
done
shot page
(( LOADED )) || { alive || finish 1 "Bravery's process died after the welcome screens (no crash report)."; }

if (( LOADED )); then
  read -r W H < <(adb shell wm size | grep -o '[0-9]*x[0-9]*' | tail -n 1 | tr x ' ')
  log "Exercising the page (${W}x${H}): tap-to-scroll zone, swipe, long-press"
  adb shell input tap $((W / 2)) $((H * 9 / 10)); sleep 3
  adb shell input swipe $((W / 2)) $((H * 7 / 10)) $((W / 2)) $((H * 3 / 10)) 300; sleep 3
  adb shell input swipe $((W / 2)) $((H / 2)) $((W / 2)) $((H / 2)) 1500; sleep 3
  shot long-press
  adb shell input keyevent KEYCODE_BACK; sleep 5
fi

crashed && finish 1 "Crashed while using a web page."
alive || finish 1 "Bravery's process died while using a web page (no crash report)."
(( LOADED )) || finish 2 "Inconclusive: Bravery is running but never showed the test page; it may be stuck on a welcome screen this script doesn't recognise."
finish 0 "Passed: started, got through the welcome screens, loaded a page and survived tapping, scrolling and long-pressing."
