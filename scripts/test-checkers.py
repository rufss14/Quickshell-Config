#!/usr/bin/env python3
"""The static checkers, checked: each is fed a file with the mistake it exists to catch.

A checker that silently stops matching still prints `name=0` and passes check-all.sh, which is how
check-qml-duplicates.py went on claiming to catch a redeclared-and-assigned property it never
matched. Each case here is (checker, QML, the summary line it must print).

    python3 scripts/test-checkers.py
"""
import os, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

CASES = [
    ("aliases", "missing id", """import QtQuick
Item {
    property alias gone: missingId.width
    Item { id: here }
}
""", "invalid-aliases=1"),
    ("duplicates", "same property twice", """import QtQuick
Item {
    width: 10
    width: 20
}
""", "duplicates=1"),
    ("duplicates", "declared with a value, then assigned", """import QtQuick
Item {
    property color accent: "red"
    accent: "blue"
}
""", "duplicates=1"),
    ("duplicates", "twice on one line", """import QtQuick
Item {
    Row { x: 1; y: 2; x: 3 }
}
""", "duplicates=1"),
    ("duplicates", "an attached handler twice", """import QtQuick
Item {
    Component.onCompleted: console.log(1)
    Component.onCompleted: console.log(2)
}
""", "duplicates=1"),
    ("duplicates", "clean: same name in sibling objects, a for(;;), a ternary", """import QtQuick
Item {
    Rectangle { width: 1 }
    Rectangle { width: 2 }
    function f(a) { for (let i = 0; i < 2; i++) { a = i }; return a ? 1 : 2 }
    property int n: 1
}
""", "duplicates=0"),
    ("final", "a FINAL name", """import QtQuick
Item {
    property real left: 0
}
""", "final-overrides=1"),
    ("final", "a FINAL name on one line", """import QtQuick
Item {
    Rectangle { property int layer: 1 }
}
""", "final-overrides=1"),
    ("final", "clean: any name on a QtObject", """import QtQuick
QtObject {
    property real left: 0
}
""", "final-overrides=0"),
    ("final", "an id that is a JS global", """import QtQuick
Item {
    Item { id: gc }
}
""", "illegal-names=1"),
    ("final", "signal set", """import QtQuick
Item {
    signal set(int v)
}
""", "illegal-names=1"),
    ("palette", "the shared palette in a visual file", """import QtQuick
import Quickshell
import "../../config"
Rectangle {
    color: Colors.primary
}
""", "palette-reads=1"),
    ("imports", "QsWindow without Quickshell", """import QtQuick
Rectangle {
    color: Colors.of(QsWindow.window).primary
}
""", "missing-quickshell-import=1"),
]

failed = 0
with tempfile.TemporaryDirectory() as tmp:
    d = os.path.join(tmp, "modules", "x")
    os.makedirs(d)
    for i, (checker, what, qml, want) in enumerate(CASES):
        path = os.path.join(d, "Case%02d.qml" % i)
        with open(path, "w") as f:
            f.write(qml)
        out = subprocess.run([sys.executable, os.path.join(HERE, "check-qml-%s.py" % checker), path],
                             capture_output=True, text=True).stdout
        ok = want in out.split("\n")
        failed += not ok
        print("%s  %s: %s" % ("ok  " if ok else "FAIL", checker, what))
        if not ok:
            print("      wanted %s, got:\n      %s" % (want, out.strip().replace("\n", "\n      ")))

print("%d cases, %d failed" % (len(CASES), failed))
sys.exit(1 if failed else 0)
