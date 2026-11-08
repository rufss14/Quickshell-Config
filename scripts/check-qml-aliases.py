#!/usr/bin/env python3
# ── check-qml-aliases.py ──────────────────────────────────────────────────────
# Finds `property alias x: someId.y` where `someId` is not declared in the same
# file. An invalid alias is a HARD LOAD FAILURE of the whole component — and it
# cascades, because every file using that component then reports "Type unavailable".
#
# Worth a script because nothing else catches it: qmlformat parses the file
# perfectly (the syntax is fine), and the failure only appears at runtime, in a
# warning that names the CONSUMER rather than the file with the mistake.
#
# Caused by exactly one edit shape: deleting or renaming an object that an alias
# still points at. That is the commonest thing a layout refactor does.
import re, sys

alias  = re.compile(r'^\s*(?:readonly\s+)?property\s+alias\s+\w+\s*:\s*([A-Za-z_]\w*)\s*\.')
declid = re.compile(r'^\s*id\s*:\s*([A-Za-z_]\w*)')

bad = 0
# No arguments = every .qml in the repo (config/settings/ excepted). It used to check
# only what it was given, so the bare command CLAUDE.md documents checked NOTHING and
# still printed 0 (found 2026-10-04, when it let two Component.onDestruction through).
import os as _os
def _all_qml():
    root = _os.path.dirname(_os.path.dirname(_os.path.abspath(__file__)))
    for d, dirs, fs in _os.walk(root):
        dirs[:] = [x for x in dirs if x != ".git" and not _os.path.join(d, x).endswith("config/settings")]
        for f in fs:
            if f.endswith(".qml"):
                yield _os.path.join(d, f)
for path in (sys.argv[1:] or sorted(_all_qml())):
    src = open(path).read().split('\n')
    ids = {m.group(1) for l in src if (m := declid.match(l))}
    for n, l in enumerate(src, 1):
        m = alias.match(l)
        if m and m.group(1) not in ids and m.group(1) not in ('parent', 'root'):
            print(f"{path}:{n}: alias points at id '{m.group(1)}' which is not declared here")
            bad += 1
print(f"invalid-aliases={bad}")
