#!/usr/bin/env python3
"""Flag a QML property declared with the name of one of Item's FINAL properties.

`property real left: 1` on any Item is `Cannot override FINAL property` — a hard load
failure of the whole file, which cascades (PowerMenu → shell.qml "Type unavailable").
Invisible to the syntax check and to the other checkers. `left` reads like an ordinary
word ("time left"), which is exactly how it got in.

The list is QQuickItem's FINAL properties as the installed Qt declares them (read from
plugins.qmltypes at run time, with a fallback list), so a Qt upgrade that finalises more
is picked up. A declaration on a non-Item (`QtObject`, a `Singleton`) is legal and
skipped: the innermost enclosing object is tracked by a brace stack (JS blocks count as
anonymous levels).

Usage: python3 scripts/check-qml-final.py [files…]   (no args: the whole repo)
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FALLBACK = ("parent x y z width height opacity visible childrenRect anchors left right "
            "horizontalCenter top bottom verticalCenter baseline focus activeFocus "
            "activeFocusOnTab transform layer").split()


# Objects that aren't Items: a property there may take any name.
NON_ITEMS = ("QtObject", "Singleton", "Connections", "Timer", "Process", "Binding")


def final_names():
    path = "/usr/lib/qt6/qml/QtQuick/plugins.qmltypes"
    try:
        t = open(path, encoding="utf-8").read()
        i = t.index('name: "QQuickItem"')
        start, end = t.rfind("Component {", 0, i), t.find("\n    Component {", i)
        names = []
        for m in re.finditer(r"Property \{([^}]*)\}", t[start:end]):
            if "isFinal: true" in m.group(1):
                names.append(re.search(r'name: "([^"]+)"', m.group(1)).group(1))
        return names or FALLBACK
    except (OSError, ValueError, AttributeError):
        return FALLBACK


def files(args):
    if args:
        return args
    out = []
    for d, dirs, fs in os.walk(ROOT):
        dirs[:] = [x for x in dirs if not x.startswith(".")
                   and os.path.relpath(os.path.join(d, x), ROOT) != os.path.join("config", "settings")]
        out += [os.path.join(d, f) for f in fs if f.endswith(".qml")]
    return sorted(out)


def main():
    names = final_names()
    decl = re.compile(r"^\s*(?:(?:readonly|required|default)\s+)*property\s+[\w<>.]+\s+("
                      + "|".join(map(re.escape, names)) + r")\b")
    hits = 0
    for f in files(sys.argv[1:]):
        try:
            lines = open(f, encoding="utf-8").read().split("\n")
        except OSError:
            continue
        stack = []          # innermost-last: an object's type name, or None for a JS block
        for n, line in enumerate(lines, 1):
            code = line.split("//", 1)[0]
            m = decl.match(code)
            owner = next((t for t in reversed(stack) if t is not None), None)
            for ch_i, ch in enumerate(code):
                if ch == "{":
                    head = re.search(r"(?:^|[\s:])([A-Z][\w.]*)\s*$", code[:ch_i])
                    stack.append(head.group(1).split(".")[-1] if head else None)
                elif ch == "}" and stack:
                    stack.pop()
            if m and owner not in NON_ITEMS:
                hits += 1
                print("%s:%d: property named %r — Item's FINAL property" % (os.path.relpath(f, ROOT), n, m.group(1)))
    print("final-overrides=%d" % hits)
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main())
