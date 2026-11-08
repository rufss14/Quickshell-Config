#!/usr/bin/env python3
"""check-qml-singletons.py — a singleton used in a file that never imports its directory.

`PowerSaver.active` in a page that imports config/ and components/ but not services/ is
`ReferenceError: PowerSaver is not defined`, logged per binding while everything it feeds is
undefined. Not a load failure, so the syntax sweep passes it, and the smoke test only sees it
if it happens to build that file — a settings page hidden on this machine (Battery, without a
battery) is never built. Found exactly that way on 2026-11-08.

Reads every `singleton Name …` line from the qmldir files in services/, config/, state/ and
components/, then for each .qml checks every `Name.` use: the file must import that directory
(a relative `import "…"` that resolves to it) or live in it.

    python3 scripts/check-qml-singletons.py          prints findings, then missing-singleton-imports=N
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = ["services", "config", "state", "components"]
SKIP = ("config/settings", "plugin/build", ".git", "scripts")   # scripts/: test harnesses with their own -I paths


def singletons():
    out = {}
    for d in DIRS:
        q = os.path.join(ROOT, d, "qmldir")
        if not os.path.exists(q):
            continue
        for ln in open(q):
            m = re.match(r"\s*singleton\s+(\w+)\s", ln)
            if m:
                out[m.group(1)] = os.path.join(ROOT, d)
    return out


def strip(src):
    # Strings and comments out, so a name in a comment or a message isn't a use.
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    src = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', src)
    src = re.sub(r"'(?:\\.|[^'\\\n])*'", "''", src)
    src = re.sub(r"`(?:\\.|[^`\\])*`", "``", src, flags=re.S)
    return re.sub(r"//[^\n]*", "", src)


def main():
    names = singletons()
    use = re.compile(r"(?<![\w.])(" + "|".join(sorted(names, key=len, reverse=True)) + r")\.(?=\w)")
    findings = 0
    for dp, dn, fs in os.walk(ROOT):
        rel = os.path.relpath(dp, ROOT)
        if rel.startswith(SKIP):
            dn[:] = []
            continue
        for f in fs:
            if not f.endswith(".qml"):
                continue
            path = os.path.join(dp, f)
            raw = open(path, encoding="utf-8", errors="replace").read()
            imported = {os.path.normpath(os.path.join(dp, m)) for m in re.findall(r'^\s*import\s+"([^"]+)"', raw, re.M)}
            body = strip(raw)
            missing = {}
            for m in use.finditer(body):
                d = names[m.group(1)]
                if os.path.normpath(d) == os.path.normpath(dp) or os.path.normpath(d) in imported:
                    continue
                # A local id, property or inline component of the same name shadows it.
                n = m.group(1)
                if re.search(r"\bid:\s*" + n + r"\b|\bproperty\s+\S+\s+" + n + r"\b|\bcomponent\s+" + n + r"\b", body):
                    continue
                line = body.count("\n", 0, m.start()) + 1
                missing.setdefault(n, line)
            for n, line in sorted(missing.items(), key=lambda kv: kv[1]):
                print("%s:%d: %s used without importing %s/" % (os.path.relpath(path, ROOT), line, n,
                                                              os.path.relpath(names[n], ROOT)))
                findings += 1
    print("missing-singleton-imports=%d" % findings)


if __name__ == "__main__":
    main()
