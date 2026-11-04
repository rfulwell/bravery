#!/usr/bin/env python3
"""Compare Bravery's default filter-list subscriptions with Brave's catalog.

Brave delivers its default ad-block lists through a component updater that
needs a private services key, so Bravery subscribes to their public source URLs
instead (kBraveryDefaultSubscriptionUrls in patches/*.patch). This script
fetches Brave's live list catalog, takes the lists Brave enables by default on
Android, and reports source URLs that Bravery is missing or no longer needs.

  scripts/check-filter-lists.py [--catalog FILE] [--report FILE]

Exit status: 0 in sync, 1 differences found, 2 error.
"""

import argparse
import json
import pathlib
import re
import sys
import urllib.request

CATALOG_URL = (
    "https://raw.githubusercontent.com/brave/adblock-resources/master/"
    "filter_lists/list_catalog.json"
)
BEGIN_MARKER = "BRAVERY_DEFAULT_SUBSCRIPTIONS_BEGIN"
END_MARKER = "BRAVERY_DEFAULT_SUBSCRIPTIONS_END"
ROOT = pathlib.Path(__file__).resolve().parent.parent


def load_catalog(path):
    if path:
        return json.loads(pathlib.Path(path).read_text())
    with urllib.request.urlopen(CATALOG_URL, timeout=60) as response:
        return json.load(response)


def android_default_sources(catalog):
    """Maps each source URL of an Android default list to its list title."""
    sources = {}
    for entry in catalog:
        if not entry.get("default_enabled"):
            continue
        platforms = [p.upper() for p in entry.get("platforms", [])]
        if platforms and "ANDROID" not in platforms:
            continue
        for source in entry.get("sources", []):
            url = source.get("url")
            if url:
                sources.setdefault(url, entry.get("title", entry.get("uuid")))
    return sources


def bravery_urls():
    """Reads the URL array from the last patch that defines it.

    Only added and context lines count, so a later patch that edits the array
    is read as its result. Adjacent string literals are joined like C++ does.
    """
    patches = sorted((ROOT / "patches").glob("*.patch"))
    block = None
    for patch in patches:
        lines = []
        inside = False
        for raw in patch.read_text().splitlines():
            if not raw or raw[0] not in "+ ":
                continue
            line = raw[1:]
            if BEGIN_MARKER in line:
                inside = True
                lines = []
                continue
            if END_MARKER in line and inside:
                block = lines
                inside = False
                continue
            if inside and not line.strip().startswith("//"):
                lines.append(line)
    if block is None:
        raise SystemExit(f"error: no {BEGIN_MARKER} block found in patches/")
    text = re.sub(r'"\s*"', "", "\n".join(block))
    return re.findall(r'"([^"]+)"', text)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--catalog", help="read the catalog from a local file")
    parser.add_argument("--report", help="also write the result as Markdown")
    args = parser.parse_args()

    try:
        expected = android_default_sources(load_catalog(args.catalog))
    except (OSError, ValueError) as error:
        print(f"error: could not read the catalog: {error}", file=sys.stderr)
        return 2
    ours = bravery_urls()

    missing = [url for url in expected if url not in ours]
    extra = [url for url in ours if url not in expected]
    duplicates = sorted({url for url in ours if ours.count(url) > 1})

    lines = []
    if missing:
        lines.append("Brave enables these by default but Bravery doesn't subscribe to them:")
        lines += [f"- {url} ({expected[url]})" for url in missing]
    if extra:
        lines.append("Bravery subscribes to these but Brave's defaults no longer include them:")
        lines += [f"- {url}" for url in extra]
    if duplicates:
        lines.append("Listed more than once in Bravery:")
        lines += [f"- {url}" for url in duplicates]

    if not lines:
        print(f"In sync: {len(ours)} default subscriptions match Brave's catalog.")
        return 0

    lines.append("")
    lines.append(
        "Update kBraveryDefaultSubscriptionUrls in the brave-core patches and "
        "re-export them. Installed copies add new URLs on their next start; "
        "removed URLs stay subscribed until the user removes them."
    )
    report = "\n".join(lines)
    print(report)
    if args.report:
        pathlib.Path(args.report).write_text(report + "\n")
    return 1


if __name__ == "__main__":
    sys.exit(main())
