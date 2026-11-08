#!/usr/bin/env python3
"""test-theme-logo.py — scripts/theme-logo.py against a fake icon theme.

Temp dirs only: XDG_DATA_DIRS/XDG_DATA_HOME point at a scratch theme, so nothing
on the machine is read or written. Run: python3 scripts/test-theme-logo.py
"""
import os
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "theme-logo.py")

# Papirus's shape (razercommander.svg): tile shadow, tile, mark shadow, mark, highlight.
PAPIRUS = """<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" version="1">
 <rect style="opacity:0.2" width="56" height="56" x="4" y="5" rx="2.8" ry="2.8"/>
 <rect style="fill:#4f4f4f" width="56" height="56" x="4" y="4" rx="2.8" ry="2.8"/>
 <path style="opacity:0.2" d="M 20,21 H 44 V 45 H 20 Z"/>
 <path style="fill:#3ffe3f" d="M 20,20 H 44 V 44 H 20 Z"/>
 <path style="opacity:0.1;fill:#ffffff" d="M 4,4 H 60 V 5 H 4 Z"/>
</svg>"""

passed = failed = 0


def check(name, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"  FAIL  {name}\n          got  {got!r}\n          want {want!r}")


def run(tmp, *names):
    env = dict(os.environ, XDG_DATA_DIRS=os.path.join(tmp, "share"),
               XDG_DATA_HOME=os.path.join(tmp, "home"), HOME=os.path.join(tmp, "home"))
    out = os.path.join(tmp, "cache", "logo.svg")
    res = subprocess.run([sys.executable, SCRIPT, out, *names], capture_output=True, text=True, env=env)
    return res, out


with tempfile.TemporaryDirectory() as tmp:
    for size in ("16x16", "64x64"):
        d = os.path.join(tmp, "share", "icons", "Fake", size, "apps")
        os.makedirs(d)
        with open(os.path.join(d, "razercommander.svg"), "w") as f:
            f.write(PAPIRUS.replace('width="64"', f'width="{size.split("x")[0]}"'))

    res, out = run(tmp, "missing-name", "razercommander")
    check("found by a later name, prints OUT", res.stdout.strip(), out)
    check("exits cleanly", res.returncode, 0)
    root = ET.parse(out).getroot()
    shapes = [el.tag.split("}")[-1] for el in root.iter()][1:]
    check("only the mark is left", shapes, ["path"])
    check("it's the solid one", list(root.iter())[1].get("style"), "fill:#3ffe3f")
    vb = [float(v) for v in root.get("viewBox").split()]
    check("framed square", vb[2] == vb[3], True)
    # Cropped to the mark (20..44) with ImageMagick, or the tile (4..60) without.
    check("framed on the mark or the tile", vb[2] in (24.0, 56.0) or abs(vb[2] - 24) < 1.0, True)

    res, _ = run(tmp, "no-such-icon")
    check("no icon: prints nothing", res.stdout, "")
    check("no icon: still exits 0", res.returncode, 0)

    d = os.path.join(tmp, "share", "icons", "Fake", "64x64", "apps")
    with open(os.path.join(d, "tileonly.svg"), "w") as f:
        f.write('<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64"/></svg>')
    res, _ = run(tmp, "tileonly")
    check("nothing left after stripping: prints nothing", res.stdout, "")

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
