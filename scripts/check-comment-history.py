#!/usr/bin/env python3
"""Comments that narrate history instead of explaining the code as it is.

    python3 scripts/check-comment-history.py            top 20 files, and the total
    python3 scripts/check-comment-history.py FILE...    every finding in those files
    python3 scripts/check-comment-history.py --count    the total only

A comment should say why the code is the way it is NOW. "Until 2026-10-04 this…", "used to",
"no longer", "previously" belong in the commit message (docs/standards.md, "Comments"). A
measured fact can stay, without its diary ("measured on Qt 6.12: …" is fine; the date it was
measured on is not). Not gated: there are far too many to fix in one pass; this counts them so
the number only goes down, and lists a file's findings before you edit it.
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP = ("/config/settings/", "/plugin/build/", "/node_modules/", "/.git/")
EXT = {".qml": "//", ".js": "//", ".py": "#", ".sh": "#", ".frag": "//", ".vert": "//", ".lua": "--"}
HIST = re.compile(
    r"\b20\d\d-[01]\d-[0-3]\d\b"           # a date
    # "used to" as history, not "is used to" (a purpose)
    r"|(?<!\bis )(?<!\bare )(?<!\bbe )(?<!\bwas )(?<!\bwere )(?<!\bbeen )(?<!; )\bused to\b"
    r"|\bpreviously\b|\bthe old (?:code|version)\b"
    r"|\b(?:until|since|before) (?:20\d\d|the fix)\b",
    re.I)


def comment_of(line, marker):
    s = line.lstrip()
    if s.startswith(marker):
        return s
    # a trailing comment after code (skip markers inside strings, roughly: after the last quote)
    i = line.find(" " + marker + " ")
    if i >= 0 and line[:i].count('"') % 2 == 0 and line[:i].count("'") % 2 == 0:
        return line[i:]
    return None


def findings(path):
    marker = EXT.get(os.path.splitext(path)[1])
    if not marker:
        return []
    out = []
    try:
        lines = open(path, errors="replace").read().split("\n")
    except OSError:
        return []
    for n, line in enumerate(lines, 1):
        if n == 1 and line.startswith("#!"):
            continue
        c = comment_of(line, marker)
        if c and HIST.search(c):
            out.append((n, c.strip()[:110]))
    return out


def all_files():
    for d, _, fs in os.walk(ROOT):
        if any(s in d + "/" for s in SKIP):
            continue
        for f in fs:
            if os.path.splitext(f)[1] in EXT and not f.startswith("test-"):
                yield os.path.join(d, f)


def main(argv):
    if argv and argv[0] != "--count":
        total = 0
        for p in argv:
            for n, c in findings(p):
                print("%s:%d: %s" % (os.path.relpath(p, ROOT), n, c))
                total += 1
        print("comment-history-findings: %d" % total)
        return 0
    per = sorted(((len(findings(p)), os.path.relpath(p, ROOT)) for p in all_files()), reverse=True)
    total = sum(n for n, _ in per)
    if argv == ["--count"]:
        print(total)
        return 0
    for n, p in per[:20]:
        if n:
            print("%5d  %s" % (n, p))
    print("total: %d" % total)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
