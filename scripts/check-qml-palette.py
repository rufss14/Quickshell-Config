#!/usr/bin/env python3
"""
check-qml-palette.py — a visual file reading the SHARED palette by mistake.

Since 2026-10-04 each screen can wear its own palette (a workspace's own wallpaper on
that screen — services/WorkspaceTheme, config/PaletteRoles). A visual file must read
its screen's roles:

    color: Colors.of(QsWindow.window).primary      // right: this window's screen
    color: Colors.primary                          // wrong: the shared palette

`Colors.x` stays right in services/, config/, state/ (no window) and for the members
that ARE the shared state (fileData, overlay, screenOverlays, data, baseData, preview, previewing, overlaid, reload, of).
Checks modules/, components/ and shell.qml, outside comments, strings and template
literals. No arguments = all of them; or pass files. Prints `palette-reads=N`.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEEP = {"fileData", "overlay", "screenOverlays", "data", "baseData", "preview", "previewing", "overlaid", "reload", "of"}
TOKEN = re.compile(r'\bColors\.([A-Za-z_]\w*)')


def code_parts(line, state):
    """The code (not comments/strings/template text) of a line, as one string."""
    out, i, n = [], 0, len(line)
    while i < n:
        ch = line[i]
        if state["tpl"]:
            if ch == "`" and (i == 0 or line[i - 1] != "\\"):
                state["tpl"] = False
            i += 1
            continue
        if ch == "/" and i + 1 < n and line[i + 1] == "/":
            break
        if ch in "\"'":
            j = i + 1
            while j < n and line[j] != ch:
                j += 2 if line[j] == "\\" else 1
            out.append(" ")
            i = j + 1
            continue
        if ch == "`":
            state["tpl"] = True
            i += 1
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def files():
    for top in ("modules", "components"):
        for d, _, fs in os.walk(os.path.join(ROOT, top)):
            for f in fs:
                if f.endswith(".qml"):
                    yield os.path.join(d, f)
    yield os.path.join(ROOT, "shell.qml")


bad = 0
for p in (sys.argv[1:] or sorted(files())):
    state = {"tpl": False}
    for n, line in enumerate(open(p), 1):
        for m in TOKEN.finditer(code_parts(line, state)):
            if m.group(1) not in KEEP:
                print("%s:%d: Colors.%s — use Colors.of(QsWindow.window).%s" % (os.path.relpath(p, ROOT), n, m.group(1), m.group(1)))
                bad += 1
print("palette-reads=%d" % bad)
sys.exit(1 if bad else 0)
