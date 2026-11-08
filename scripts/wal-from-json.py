#!/usr/bin/env python3
"""Expand a saved {special, colors} palette into a full pywal colors.json.

The colours panel stores palettes as {"special": {...}, "colors": {...}}. pywal's
own colors.json additionally carries "wallpaper" and "alpha", and some downstream
consumers read them, so a bare `cp` of a saved palette can trip them. This fills
exactly those gaps (keeping whatever the existing colors.json had) and writes the
result atomically, since the shell watches that file.

    wal-from-json.py <saved-palette.json> <out-colors.json>
    wal-from-json.py --selftest
"""
import json
import os
import sys
import tempfile


def build(saved: dict, prev: dict) -> dict:
    special = dict(saved.get("special", {}))
    colors = dict(saved.get("colors", {}))
    # cursor mirrors foreground, same default pywal uses.
    special.setdefault("cursor", special.get("foreground", "#ffffff"))
    return {
        "wallpaper": prev.get("wallpaper", "None"),
        "alpha": prev.get("alpha", "100"),
        "special": special,
        "colors": colors,
    }


def _load(path: str) -> dict:
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return {}


def main(src: str, out: str) -> int:
    saved = _load(src)
    if not saved.get("colors"):
        print(f"wal-from-json: {src} has no colours", file=sys.stderr)
        return 1
    doc = build(saved, _load(out))
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(out) or ".", suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump(doc, f, indent=4)
    os.replace(tmp, out)
    return 0


def _selftest() -> int:
    saved = {"special": {"background": "#000000", "foreground": "#ffffff"},
             "colors": {f"color{i}": "#123456" for i in range(16)}}
    prev = {"wallpaper": "/pics/x.png", "alpha": "90", "colors": {}}
    doc = build(saved, prev)
    assert doc["wallpaper"] == "/pics/x.png", doc
    assert doc["alpha"] == "90", doc
    assert doc["special"]["cursor"] == "#ffffff", doc
    assert doc["colors"]["color15"] == "#123456", doc
    # No prior file → sane defaults.
    doc2 = build(saved, {})
    assert doc2["wallpaper"] == "None" and doc2["alpha"] == "100", doc2
    print("ok")
    return 0


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--selftest":
        sys.exit(_selftest())
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
