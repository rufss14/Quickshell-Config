#!/usr/bin/env python3
"""Tests for scripts/wall-colors.py: the dominant colour, and the cache (temporary directories only).

    python3 scripts/test-wall-colors.py
"""

import importlib.util
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("wallcolors", os.path.join(HERE, "wall-colors.py"))
wc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wc)

passed = failed = 0


def check(name, cond, detail=""):
    global passed, failed
    if cond:
        passed += 1
    else:
        failed += 1
        print("FAIL  " + name + ("  -> " + detail if detail else ""))


def hue_name(hexcol):
    import colorsys
    r, g, b = (int(hexcol[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return colorsys.rgb_to_hsv(r, g, b)


check("empty picture", wc.dominant([]) == "")
check("a red picture is red", wc.dominant([(250, 20, 20)] * 100) == "#fa1414")
# 70% grey sky, 30% blue: the blue wins, not their average
mix = [(120, 120, 120)] * 70 + [(20, 60, 230)] * 30
d = wc.dominant(mix)
h, s, v = hue_name(d)
check("vivid beats a grey majority", 0.55 < h < 0.72 and s > 0.7, d)
# two vivid hues: the bigger vote wins
two = [(230, 30, 30)] * 20 + [(30, 200, 40)] * 50
h, s, v = hue_name(wc.dominant(two))
check("the bigger hue wins", 0.25 < h < 0.42, str(h))
# nearly no vivid pixels: the plain average (a grey stays grey)
grey = [(100, 100, 100)] * 98 + [(250, 20, 20)] * 2
g = wc.dominant(grey)
check("a grey scene averages", abs(int(g[1:3], 16) - 103) < 6 and abs(int(g[3:5], 16) - 102) < 6, g)
check("black stays black", wc.dominant([(0, 0, 0)] * 50) == "#000000")

try:
    from PIL import Image
except ImportError:
    Image = None
if Image is None:
    print("skip  PIL missing: file cases not run")
else:
    with tempfile.TemporaryDirectory() as td:
        red = os.path.join(td, "red.png")
        blue = os.path.join(td, "blue.png")
        Image.new("RGB", (200, 120), (220, 20, 20)).save(red)
        Image.new("RGB", (200, 120), (20, 40, 220)).save(blue)
        cache = os.path.join(td, "sub", "cache.json")
        run = lambda *paths: subprocess.run([sys.executable, os.path.join(HERE, "wall-colors.py"), cache, "--", *paths],
                                            capture_output=True, text=True)
        r = run(red, blue, os.path.join(td, "missing.png"))
        rows = dict(line.split("\t")[::-1] for line in r.stdout.splitlines())
        check("file run prints a colour per readable picture", set(rows) == {red, blue}, r.stdout + r.stderr)
        check("the colours are right", rows[red].startswith("#d") and rows[blue].startswith("#1"), str(rows))
        saved = json.load(open(cache))
        check("the cache holds both, by path", set(saved) == {red, blue})
        # a second run answers from the cache: poison the entry, the poison comes back
        saved[red]["c"] = "#123456"
        json.dump(saved, open(cache, "w"))
        r = run(red, blue)
        check("a second run reads the cache", "#123456\t" + red in r.stdout)
        # a changed picture is read again
        Image.new("RGB", (200, 120), (20, 220, 20)).save(red)
        os.utime(red, (1, 1))
        r = run(red, blue)
        check("a changed picture is re-read", "#123456" not in r.stdout)
        # a picture gone from the library leaves the cache
        run(blue)
        check("a removed picture leaves the cache", set(json.load(open(cache))) == {blue})
        # a corrupt cache is only a cold start
        open(cache, "w").write("{nope")
        r = run(blue)
        check("a corrupt cache is a cold start", blue in r.stdout)
        check("usage error", subprocess.run([sys.executable, os.path.join(HERE, "wall-colors.py")],
                                            capture_output=True).returncode == 2)

print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
