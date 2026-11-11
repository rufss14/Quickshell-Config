#!/usr/bin/env python3
"""check-qml-qmldir.py — a sibling type used by name but missing from its directory's qmldir.

A directory WITH a qmldir only offers the types that file lists: its implicit "every .qml
here is a type" import is gone. A new file used by name from a sibling (`BarDockPopups {`
in Bar.qml) without its qmldir line is `BarDockPopups is not a type` — and the file that
used it fails to exist, then everything above it ("Type Bar unavailable"): the whole shell
fails to load. The syntax sweep parses each file alone and passes it. Hit on 2026-11-08.

For each directory with a qmldir: every `Name {` in its .qml files where Name.qml sits in
that directory must have a `Name … Name.qml` line in the qmldir. Files loaded by URL
(Loader `source:`) don't need one and aren't flagged — only uses by type name are.

    python3 scripts/check-qml-qmldir.py          prints findings, then missing-qmldir-types=N
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP = ("config/settings", "plugin/build", ".git", "scripts")
USE = re.compile(r"(?:^|[\s:;{])([A-Z][A-Za-z0-9_]*)\s*\{")

findings = []
for dirpath, dirnames, filenames in os.walk(ROOT):
    rel = os.path.relpath(dirpath, ROOT)
    if rel.startswith(SKIP):
        dirnames[:] = []
        continue
    if "qmldir" not in filenames:
        continue
    listed = set()
    with open(os.path.join(dirpath, "qmldir"), encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            if parts and parts[-1].endswith(".qml"):
                listed.add(parts[-1][:-4])
    local = {n[:-4] for n in filenames if n.endswith(".qml")}
    for name in sorted(filenames):
        if not name.endswith(".qml"):
            continue
        with open(os.path.join(dirpath, name), encoding="utf-8") as f:
            for no, line in enumerate(f, 1):
                code = line.split("//", 1)[0]
                for t in USE.findall(code):
                    if t in local and t not in listed and t != name[:-4]:
                        findings.append(f"{os.path.join(rel, name)}:{no}: {t} is not in {rel}/qmldir")
                        listed.add(t)   # once per type is enough

for f in findings:
    print(f)
print(f"missing-qmldir-types={len(findings)}")
