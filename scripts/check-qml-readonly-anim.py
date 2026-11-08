#!/usr/bin/env python3
# ── check-qml-readonly-anim.py ────────────────────────────────────────────────
# Finds `Behavior on X` / `<Animation> on X` where X is declared `readonly` in the
# SAME object. An animation writes the value it animates, and QML refuses that
# on a readonly property:
#
#     Invalid property assignment: "metered" is a read-only property
#
# — a hard load failure of the file that cascades like an invalid alias does
# (DockIconStrip unavailable → DockHost → Bar → shell.qml: nothing starts), and
# invisible to the syntax sweep and the other checkers.
#
# Scoped to the enclosing object on purpose: a readonly `metered` on a parent item
# and a writable `metered` on the child being animated are different properties,
# and a file-wide match flags the good code.
#
#     python3 scripts/check-qml-readonly-anim.py        (prints readonly-anims=N)
# ─────────────────────────────────────────────────────────────────────────────
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def strip(src):
    """Blank out comments and string literals, keeping offsets (and newlines)."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i)); i = j
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append("".join("\n" if ch == "\n" else " " for ch in src[i:j])); i = j
        elif c in "\"'`":
            j = i + 1
            while j < n and src[j] != c:
                j += 2 if src[j] == "\\" else 1
            j = min(j + 1, n)
            out.append(c + " " * (j - i - 2) + (c if j - i >= 2 else "")); i = j
        else:
            out.append(c); i += 1
    return "".join(out)


def enclosing_block(s, pos):
    """(start, end) of the { … } object body containing pos."""
    depth = 0
    i = pos
    while i >= 0:
        if s[i] == "}": depth += 1
        elif s[i] == "{":
            if depth == 0: break
            depth -= 1
        i -= 1
    start = i
    depth = 0
    j = start
    while j < len(s):
        if s[j] == "{": depth += 1
        elif s[j] == "}":
            depth -= 1
            if depth == 0: break
        j += 1
    return start, j


def own_readonly(s, start, end):
    """readonly property names declared directly in this block (depth 1)."""
    names = set()
    depth = 0
    for m in re.finditer(r"[{}]|readonly\s+property\s+[\w.<>]+\s+(\w+)", s[start:end + 1]):
        tok = m.group(0)
        if tok == "{": depth += 1
        elif tok == "}": depth -= 1
        elif depth == 1: names.add(m.group(1))
    return names


def main():
    found = 0
    for f in sorted(ROOT.rglob("*.qml")):
        rel = f.relative_to(ROOT)
        if rel.parts[:2] == ("config", "settings") or "build" in rel.parts:
            continue
        s = strip(f.read_text(errors="replace"))
        for m in re.finditer(r"\b(Behavior|\w*Animation)\s+on\s+(\w+)\s*\{", s):
            start, end = enclosing_block(s, m.start())
            if start < 0: continue
            if m.group(2) in own_readonly(s, start, end):
                line = s[:m.start()].count("\n") + 1
                print(f"{rel}:{line}: {m.group(1)} on readonly '{m.group(2)}'")
                found += 1
    print(f"readonly-anims={found}")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
