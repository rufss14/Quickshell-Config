#!/usr/bin/env python3
"""
claude-presence-gif.py — Claude's burst, orange on black, as the Discord presence icon.

    python3 scripts/claude-presence-gif.py          write assets/logos/claude-presence.gif
    python3 scripts/claude-presence-gif.py --check  exit 1 if the gif isn't what this would write

Discord only animates a rich-presence image that comes from an external URL; an uploaded
asset is always a still. So this makes the file that gets hosted (raw.githubusercontent.com
from the published repo) and `Config.claudePresenceImageUrl` points at.

It reads the white-on-transparent sprite sheet claude-burst.py already keyed out of
Claude.webp, so the two never disagree about the frames or their 40 ms rhythm. Each frame's
alpha becomes a blend from black to ClaudeGlyph's orange, and a GIF has one 256-colour
palette — which here is simply that black→orange ramp, so there is no dithering or banding
beyond the ramp itself.
"""
import importlib.util
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "assets", "logos", "claude-presence.gif")

SIZE = 256                                   # Discord shows it ≤ ~100px; 2-3x for hi-dpi
ORANGE = (0xD9, 0x77, 0x57)                  # ClaudeGlyph.claudeOrange
PAD = 6                                      # px of black around the burst (sheet cell → SIZE)


def _burst():
    spec = importlib.util.spec_from_file_location("claude_burst", os.path.join(HERE, "claude-burst.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def build():
    cb = _burst()
    sheet = np.array(Image.open(cb.OUT).convert("RGBA"))
    k = cb.qml_constants()
    cell, cols = k["cell"], k["cols"]
    # palette index i = i/255 of the way from black to orange
    ramp = np.array([[round(c * i / 255) for c in ORANGE] for i in range(256)], np.uint8)
    inner = SIZE - 2 * PAD
    frames = []
    for n in range(k["frames"]):
        r, c = divmod(n, cols)
        a = sheet[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell, 3]
        a = Image.fromarray(a, "L").resize((inner, inner), Image.LANCZOS)
        canvas = Image.new("L", (SIZE, SIZE), 0)
        canvas.paste(a, (PAD, PAD))
        p = canvas.copy().convert("P")
        p.putpalette(ramp.flatten().tolist())
        frames.append(p)
    return frames, k["stepMs"]


def write(path):
    frames, step = build()
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=step, loop=0,
                   optimize=False, disposal=1)
    return len(frames), step


def main(argv):
    if "--check" in argv:
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            tmp = os.path.join(d, "x.gif")
            write(tmp)
            ok = os.path.isfile(OUT) and open(tmp, "rb").read() == open(OUT, "rb").read()
        print("claude-presence.gif is current" if ok else "claude-presence.gif is out of date")
        return 0 if ok else 1
    n, step = write(OUT)
    print("wrote %s  %dx%d  %d frames  %d ms  %d KB" % (OUT, SIZE, SIZE, n, step, os.path.getsize(OUT) // 1024))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
