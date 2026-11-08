#!/usr/bin/env python3
"""
check-qml-imports.py — a file naming `QsWindow` without `import Quickshell`.

`QsWindow` (the attached window lookup every visual file reads its screen's palette through) belongs to the
Quickshell module. Without the import it is "ReferenceError: QsWindow is not defined" — logged at runtime, once per
binding, and every colour that read it comes out undefined. It is not a load failure, so the shell starts and the
panel just renders wrong; and it passes the syntax sweep and every other checker. Found when the setup rebuild's
new files (SetupStepRow, SetupPassword) shipped without it, and then two older ones (ClipsPeek, KaraokeMarks).

Looks in code, not comments. No arguments = every .qml outside config/settings/; or pass files.
Prints `missing-quickshell-import=N`.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
USES = re.compile(r'\bQsWindow\b')
HAS = re.compile(r'^\s*import\s+Quickshell\s*(//.*)?$', re.M)


def code_of(text):
    """The text without // comments and /* */ blocks (strings with // in them are rare enough to lose)."""
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return "\n".join(re.sub(r'//.*$', '', ln) for ln in text.split("\n"))


def files(args):
    if args:
        return args
    out = []
    for base, dirs, names in os.walk(ROOT):
        rel = os.path.relpath(base, ROOT)
        if rel.startswith(("config/settings", ".git", "node_modules")):
            dirs[:] = []
            continue
        out += [os.path.join(base, n) for n in names if n.endswith(".qml")]
    return out


bad = 0
for path in files(sys.argv[1:]):
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        continue
    if USES.search(code_of(text)) and not HAS.search(text):
        bad += 1
        print(f"{os.path.relpath(path, ROOT)}: uses QsWindow, no `import Quickshell`")
print(f"missing-quickshell-import={bad}")
sys.exit(1 if bad else 0)
