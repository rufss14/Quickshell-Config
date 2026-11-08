#!/usr/bin/env python3
"""check-glyphs.py — a Nerd Font glyph in QML that will draw NOTHING.

MaterialIcon draws a `glyph:` either as the Material Symbol that services/icons.js maps
its codepoint to (NAME), or straight from the bundled assets/fonts/QuicktestGlyphs.otf.
A codepoint that is in neither is a blank square on every machine — silently: the
parse is fine, nothing is logged, the header or card just has no icon. (Window tuning's
header and three cards of the 2026-10-07 settings redesign shipped that way.)

The fonts are cut by scripts/material-symbols-map.py --emit from what the tree spells;
the fix is either a codepoint the font already has, or a re-emit (then a restart).

Usage: python3 scripts/check-glyphs.py [files…]   (no arguments = the whole tree)
Needs fontTools (python-fonttools).
"""
import re
import sys
from pathlib import Path

from fontTools.ttLib import TTFont

REPO = Path(__file__).resolve().parent.parent

cmap = set(TTFont(REPO / "assets/fonts/QuicktestGlyphs.otf").getBestCmap().keys())
icons = (REPO / "services/icons.js").read_text(encoding="utf-8")
mapped = {int(k, 16) for k in re.findall(r'"([0-9A-F]{4,5})":', icons)}

GLYPH = re.compile(r"[\U000F0000-\U000F1FFF\uE000-\uF8FF]")
ESC5 = re.compile(r"\\u\{([0-9A-Fa-f]+)\}")
ESC4 = re.compile(r"\\u([EeFf][0-9A-Fa-f]{3})\b")

files = [Path(a) for a in sys.argv[1:]] or [
    p for p in REPO.rglob("*.qml") if "config/settings" not in str(p)]

bad = 0
for f in files:
    for ln, line in enumerate(f.read_text(encoding="utf-8").split("\n"), 1):
        code = line.split("//")[0]
        cps = [ord(c) for c in GLYPH.findall(code)]
        cps += [int(m, 16) for m in ESC5.findall(code)]
        cps += [int(m, 16) for m in ESC4.findall(code)]
        for cp in cps:
            if cp not in mapped and cp not in cmap:
                print(f"{f.relative_to(REPO) if f.is_absolute() else f}:{ln}: U+{cp:X} is neither mapped nor in QuicktestGlyphs")
                bad += 1
print(f"blank-glyphs={bad}")
sys.exit(1 if bad else 0)
