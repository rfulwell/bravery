#!/usr/bin/env python3
# Copyright (c) 2026 The Bravery Authors. All rights reserved.
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this file,
# You can obtain one at https://mozilla.org/MPL/2.0/.
"""Checks that plaster regex rules match the Chromium version a brave-core
checkout pins, without a Chromium checkout (files come from the GitHub mirror).

  check-plasters.py <patched brave-core dir> <rewrite/... .yaml>...
"""

import json
import re
import sys
import urllib.request
from pathlib import Path

import yaml


def chromium_tag(brave_core):
    package = json.loads((brave_core / 'package.json').read_text())
    return package['config']['projects']['chrome']['tag']


def fetch(tag, path):
    url = f'https://raw.githubusercontent.com/chromium/chromium/{tag}/{path}'
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read().decode('utf-8')


def check(brave_core, tag, plaster):
    source_path = str(plaster.relative_to(brave_core / 'rewrite'))[:-len('.yaml')]
    text = fetch(tag, source_path)
    ok = True
    for sub in yaml.safe_load(plaster.read_text())['substitutions']:
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
    results = [check(brave_core, tag, (brave_core / p).resolve())
               for p in sys.argv[2:]]
    sys.exit(0 if all(results) else 1)


if __name__ == '__main__':
    main()
