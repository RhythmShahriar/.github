#!/usr/bin/env python3
# Copyright (c) 2026 Rhythm Shahriar <me@rhy.io>
# SPDX-License-Identifier: MIT
"""Checks the Rhythm writing rules in a repository's tracked text.

The rules: no em dashes, and no comma before "and" or "but". They cover
docs, help text, messages and comments, so every tracked text file is
read, except generated output, vendored code and test fixtures.

A line that must keep the pattern (quoted third-party text, say) opts
out with "style:ignore" anywhere on it.

Usage: check-style.py [path ...]   (default: the current repository)
Exit codes: 0 clean, 1 problems found, 2 usage error.
"""

import re
import subprocess
import sys
from pathlib import Path

EXTENSIONS = {
    ".md", ".mdx", ".txt", ".go", ".php", ".ts", ".tsx", ".js", ".mjs",
    ".sh", ".ps1", ".yml", ".yaml", ".tmpl", ".html", ".py",
}
SKIP_PARTS = {"node_modules", "vendor", "dist", "testdata", "fixtures", ".git"}
SKIP_NAMES = {"package-lock.json", "pnpm-lock.yaml", "composer.lock", "go.sum"}

RULES = [
    ("em dash", re.compile("—")),
    # Across a line break too: "…, and" at a line end followed by text.
    ("comma before and/but", re.compile(r",[ \t]*\n?[ \t]*(?:and|but)\b")),
]


def tracked(roots):
    files = []
    for root in roots:
        out = subprocess.run(["git", "-C", root, "ls-files", "-z"], capture_output=True, check=True)
        for name in out.stdout.decode().split("\0"):
            if name:
                files.append(Path(root) / name)
    return files


def wanted(path):
    if path.suffix not in EXTENSIONS or path.name in SKIP_NAMES:
        return False
    return not SKIP_PARTS.intersection(path.parts)


def check(path):
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return []
    lines = text.split("\n")
    problems = []
    for label, rule in RULES:
        for m in rule.finditer(text):
            line = text.count("\n", 0, m.start()) + 1
            if "style:ignore" in lines[line - 1]:
                continue
            col = m.start() - (text.rfind("\n", 0, m.start()) + 1) + 1
            problems.append((line, col, label, lines[line - 1].strip()))
    return sorted(problems)


def main(argv):
    if any(a in ("-h", "--help") for a in argv):
        print(__doc__.strip())
        return 0
    roots = argv or ["."]
    try:
        files = [f for f in tracked(roots) if wanted(f)]
    except subprocess.CalledProcessError as err:
        print(f"check-style: not a git repository: {err.cmd[2]}", file=sys.stderr)
        return 2
    total = 0
    for f in files:
        for line, col, label, src in check(f):
            total += 1
            print(f"{f}:{line}:{col}: {label}: {src[:120]}")
    if total:
        print(f"\n{total} problem{'s' if total != 1 else ''}. Rephrase, or add style:ignore to a line that must keep it.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
