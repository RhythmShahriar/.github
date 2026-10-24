#!/usr/bin/env python3
# Copyright (c) 2026 Rhythm Shahriar <me@rhy.io>
# SPDX-License-Identifier: MIT
"""Adds the copyright and license header to every tracked source file.

Each file gets two lines in its own comment syntax:

    Copyright (c) 2026 Rhythm Shahriar <me@rhy.io>
    SPDX-License-Identifier: <license>

The license comes from the LICENSE file nearest to the file (so Tuner's
checks/ folder, which is MIT inside an AGPL repository, is labelled
right). The header goes first, after a shebang or "<?php" when there is
one. Files that already carry an SPDX line are left alone, so the script
can run again at any time.

Usage: add-headers.py [--check] [path ...]   (default: the current repository)
  --check  change nothing; list files without a header and exit 1
"""

import subprocess
import sys
from pathlib import Path

OWNER = "Copyright (c) 2026 Rhythm Shahriar <me@rhy.io>"
SLASH = {".go", ".ts", ".tsx", ".js", ".mjs", ".php"}
HASH = {".sh", ".ps1", ".py", ".yml", ".yaml"}
SKIP_PARTS = {"node_modules", "vendor", "dist", "testdata", ".git"}
SKIP_NAMES = {"pnpm-lock.yaml", "pnpm-workspace.yaml"}


def tracked(root):
    out = subprocess.run(["git", "-C", root, "ls-files", "-z"], capture_output=True, check=True)
    return [Path(root) / n for n in out.stdout.decode().split("\0") if n]


def wanted(path):
    if path.suffix not in SLASH | HASH or path.name in SKIP_NAMES:
        return False
    return not SKIP_PARTS.intersection(path.parts)


def license_for(path, root, cache={}):
    """The SPDX ID of the LICENSE nearest to path, walking up to root."""
    d = path.parent
    root = root.resolve()
    while True:
        if d not in cache:
            cache[d] = None
            for name in ("LICENSE", "LICENSE.md", "LICENSE.txt"):
                f = d / name
                if f.is_file():
                    head = f.read_text(encoding="utf-8", errors="replace")[:400].upper()
                    if "MIT LICENSE" in head or head.startswith("MIT"):
                        cache[d] = "MIT"
                    elif "AFFERO" in head:
                        cache[d] = "AGPL-3.0-only"
                    break
        if cache[d] or d.resolve() == root or d.parent == d:
            return cache[d]
        d = d.parent


def header(path, spdx):
    mark = "//" if path.suffix in SLASH else "#"
    return f"{mark} {OWNER}\n{mark} SPDX-License-Identifier: {spdx}\n"


def has_header(text):
    return "SPDX-License-Identifier" in "\n".join(text.split("\n")[:12])


def generated(text):
    return "Code generated" in text[:400] and "DO NOT EDIT" in text[:400]


def insert(path, text, spdx):
    """Returns text with the header in place, keeping a shebang, <?php or a
    leading Go build line pairing intact."""
    h = header(path, spdx)
    lines = text.split("\n")
    first = lines[0] if lines else ""
    if first.startswith("#!") or first.strip() == "<?php":
        rest = "\n".join(lines[1:]).lstrip("\n")
        return f"{first}\n{h}\n{rest}" if rest else f"{first}\n{h}"
    # A blank line after the header keeps it apart from a Go package doc
    # comment, so godoc doesn't read the copyright as package documentation.
    return f"{h}\n{text}"


def main(argv):
    if any(a in ("-h", "--help") for a in argv):
        print(__doc__.strip())
        return 0
    check = "--check" in argv
    roots = [a for a in argv if a != "--check"] or ["."]
    missing, changed, unknown = [], 0, []
    for root in roots:
        for f in tracked(root):
            if not wanted(f) or not f.is_file():
                continue
            text = f.read_text(encoding="utf-8")
            if has_header(text) or generated(text):
                continue
            spdx = license_for(f, Path(root))
            if not spdx:
                unknown.append(f)
                continue
            if check:
                missing.append(f)
                continue
            f.write_text(insert(f, text, spdx), encoding="utf-8")
            changed += 1
    for f in unknown:
        print(f"{f}: no LICENSE found above it", file=sys.stderr)
    if check:
        for f in missing:
            print(f"{f}: no copyright header")
        if missing:
            print(f"\n{len(missing)} file{'s' if len(missing) != 1 else ''} without a header; run add-headers.py to add them.", file=sys.stderr)
        return 1 if missing or unknown else 0
    print(f"Added the header to {changed} file{'s' if changed != 1 else ''}.")
    return 1 if unknown else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
