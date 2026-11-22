#!/usr/bin/env python3
# Copyright (c) 2026 The Bravery Authors. All rights reserved.
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this file,
# You can obtain one at https://mozilla.org/MPL/2.0/.
"""Checks that plaster regex rules match the Chromium version a brave-core
checkout pins, without a Chromium checkout (files come from the GitHub mirror).

  check-plasters.py <patched brave-core dir> <rewrite/... .yaml>...

Exits 1 if a rule no longer matches, 2 if a Chromium file couldn't be
downloaded.
"""

import base64
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import yaml


def chromium_tag(brave_core):
    package = json.loads((brave_core / 'package.json').read_text())
    return package['config']['projects']['chrome']['tag']


class FetchError(Exception):
    pass


def _get(url, headers=None):
    request = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def fetch(tag, path):
    """A Chromium source file at a tag: GitHub's mirror (authenticated when a
    token is available, which raises its rate limit), retried with backoff,
    then Chromium's own server as a fallback."""
    token = os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
    headers = {'Authorization': f'token {token}'} if token else {}
    sources = [
        lambda: _get(f'https://raw.githubusercontent.com/chromium/chromium/{tag}/{path}',
                     headers),
        lambda: base64.b64decode(_get(
            f'https://chromium.googlesource.com/chromium/src/+/refs/tags/{tag}/{path}'
            '?format=TEXT')),
    ]
    errors = []
    for source in sources:
        for attempt in range(4):
            try:
                return source().decode('utf-8')
            except urllib.error.HTTPError as e:
                errors.append(f'{e.url}: HTTP {e.code}')
                if e.code == 404:
                    break
                retry_after = e.headers.get('Retry-After', '')
                delay = int(retry_after) if retry_after.isdigit() else 5 * 2 ** attempt
            except (urllib.error.URLError, TimeoutError) as e:
                errors.append(f'{path}: {e}')
                delay = 5 * 2 ** attempt
            time.sleep(min(delay, 60))
    raise FetchError(f'could not download {path} at Chromium {tag}:\n  ' +
                     '\n  '.join(errors[-4:]))


def check(brave_core, tag, plaster):
    source_path = str(plaster.relative_to(brave_core / 'rewrite'))[:-len('.yaml')]
    text = fetch(tag, source_path)
    ok = True
    for sub in yaml.safe_load(plaster.read_text())['substitutions']:
        if 'regex' not in sub:
            # Brave's own non-regex rewriters (add_before_line etc.); plaster
            # checks those during the real build.
            print(f'skip {source_path}: {next(iter(sub.keys() - {"description", "count"}), "?")} rule')
            continue
        rule = sub['regex']
        pattern = (re.escape(rule['pattern'])
                   if 'pattern' in rule else rule['re_pattern'])
        flags = 0
        for flag in rule.get('re_flags', []):
            flags |= getattr(re, flag)
        text, count = re.subn(pattern, rule['replace'], text, flags=flags)
        expected = sub.get('count', 1)
        matched = count >= 1 if expected == 0 else count == expected
        print(f'{"ok  " if matched else "FAIL"} {source_path}: '
              f'{count} match(es), expected {expected or ">=1"}')
        ok &= matched
    return ok


def main():
    brave_core = Path(sys.argv[1]).resolve()
    tag = chromium_tag(brave_core)
    print(f'Chromium {tag}')
    try:
        results = [check(brave_core, tag, (brave_core / p).resolve())
                   for p in sys.argv[2:]]
    except FetchError as e:
        # A network problem, not a broken rule.
        print(f'error: {e}', file=sys.stderr)
        sys.exit(2)
    sys.exit(0 if all(results) else 1)


if __name__ == '__main__':
    main()
