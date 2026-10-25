#!/usr/bin/env bash
# Prints the tag of Brave's latest release on a channel (default: release).
#
#   scripts/latest-brave-release.sh [release|beta]
#
# For the release channel, prefers releases that shipped Android APKs.
set -euo pipefail

CHANNEL="${1:-release}"
gh api -X GET 'repos/brave/brave-browser/releases' -f per_page=60 \
  | CHANNEL="$CHANNEL" python3 -c '
import json, os, re, sys
channel = os.environ["CHANNEL"]
prefix = {"release": "Release", "beta": "Beta"}[channel]
releases = [r for r in json.load(sys.stdin)
            if not r["draft"] and (r.get("name") or "").startswith(prefix)
            and (channel != "release" or not r["prerelease"])]
def has_android(r):
    return any(re.search(r"arm64.*\.apk$", a["name"], re.I) for a in r["assets"])
picked = next((r for r in releases if has_android(r)), None) or (releases[0] if releases else None)
if not picked:
    sys.exit(f"no {channel} Brave release found")
print(picked["tag_name"])
'
