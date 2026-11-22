#!/usr/bin/env python3
# Copyright (c) 2026 The Bravery Authors. All rights reserved.
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this file,
# You can obtain one at https://mozilla.org/MPL/2.0/.
"""Moves aside files that block a Chromium sync, so it can be retried.

When Chromium starts tracking a directory that used to be a separate DEPS
checkout (e.g. third_party/libsync/src in Chromium 158), gclient's checkout of
the new version fails with "untracked working tree files would be overwritten
by checkout". This reads a failed sync's log, and moves each blocking file, or
the old nested git checkout containing it, into <stash dir>/<timestamp>/ (it
deletes nothing).

  move-stale-checkouts.py <sync log> <stash dir>

Exits 0 if it moved something (retry the sync), 1 if the log shows no such
failure.
"""

import re
import shutil
import sys
import time
from pathlib import Path

COMMAND_FAILED = re.compile(r"returned non-zero exit status \d+ in (\S+)")
BLOCKED = re.compile(r"untracked working tree files would be "
                     r"(?:overwritten|removed) by checkout")


def blocking_paths(log):
    """Yields (repo dir, absolute path) for each file a checkout refused."""
    lines = log.splitlines()
    repo = None
    for i, line in enumerate(lines):
        if match := COMMAND_FAILED.search(line):
            repo = Path(match.group(1))
        if BLOCKED.search(line) and repo:
            for listed in lines[i + 1:]:
                if not listed.startswith('\t'):
                    break
                yield repo, repo / listed.strip()


def enclosing_checkout(repo, path):
    """The old nested git checkout containing path, or path itself."""
    for parent in path.parents:
        if parent == repo or repo not in parent.parents:
            break
        if (parent / '.git').exists():
            return parent
    return path


def main():
    log = Path(sys.argv[1]).read_text(errors='replace')
    stash = Path(sys.argv[2]) / time.strftime('%Y%m%d-%H%M%S')
    moved = set()
    for repo, path in blocking_paths(log):
        victim = enclosing_checkout(repo, path)
        if victim in moved or not (victim.exists() or victim.is_symlink()):
            continue
        dest = stash / repo.name / victim.relative_to(repo)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(victim), str(dest))
        print(f'moved {victim} -> {dest}', file=sys.stderr)
        moved.add(victim)
    sys.exit(0 if moved else 1)


if __name__ == '__main__':
    main()
