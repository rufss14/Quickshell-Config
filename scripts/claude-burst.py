#!/usr/bin/env python3
"""
claude-burst.py — turn assets/logos/Claude.webp into the sprite sheet the sidebar plays.

    python3 scripts/claude-burst.py            write assets/logos/claude-burst.png
    python3 scripts/claude-burst.py --check    exit 1 if the sheet isn't what this would write

The source is an animated WebP of Claude's burst: white on an orange rounded square, 192
frames of 20–200 ms. Qt here has no WebP plugin (`AnimatedImage` can't read it), and the
orange plate can't sit on the shell's surfaces anyway, so:

  · resampled to a fixed 40 ms step (the frame showing at each tick), which keeps the
    source's rhythm and lets QML step a frame index;
  · the plate is keyed out: every pixel is the plate colour mixed with white, so its
    alpha is how far along that line it sits. The result is WHITE with alpha, which
    components/ClaudeBurst tints (MultiEffect) to whatever the sidebar wants;
  · only the burst's own area is kept (the plate's edge is masked off — its anti-aliased
    rim would read as a faint ring), and the frames are packed into a grid.

components/ClaudeBurst.qml holds the same numbers (COLS, CELL, FRAMES, STEP_MS); --check
fails if they disagree with the sheet.
"""
import os
import re
import struct
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "assets", "logos", "Claude.webp")
OUT = os.path.join(ROOT, "assets", "logos", "claude-burst.png")
QML = os.path.join(ROOT, "components", "ClaudeBurst.qml")

STEP_MS = 40
CELL = 68            # the burst reaches 33px from the centre of the 80px frame
COLS = 13
PLATE = np.array([217.0, 113.0, 78.0])      # the orange the source declares
WHITE = np.array([255.0, 255.0, 255.0])
MASK_R = 36.0        # inside the plate's rounded corners, outside the burst


def durations(data):
    out, pos = [], 12
    while pos < len(data) - 8:
        tag, size = data[pos:pos + 4], struct.unpack("<I", data[pos + 4:pos + 8])[0]
        if tag == b"ANMF":
            out.append(int.from_bytes(data[pos + 8 + 12:pos + 8 + 15], "little"))
        pos += 8 + size + (size & 1)
    return out


def build():
    with open(SRC, "rb") as f:
        durs = durations(f.read())
    im = Image.open(SRC)
    assert im.n_frames == len(durs), "frame count and timings disagree"
    w, h = im.size
    yy, xx = np.mgrid[0:h, 0:w]
    inside = np.hypot(yy - (h - 1) / 2, xx - (w - 1) / 2) <= MASK_R
    axis = WHITE - PLATE
    alphas = []
    for i in range(im.n_frames):
        im.seek(i)
        px = np.array(im.convert("RGBA"), float)
        a = np.clip(((px[..., :3] - PLATE) @ axis) / (axis @ axis), 0, 1)
        a[~inside] = 0
        alphas.append(a)
    ends = np.cumsum(durs)
    ticks = range(0, int(ends[-1]), STEP_MS)
    picks = [alphas[int(np.searchsorted(ends, t, side="right"))] for t in ticks]
    n = len(picks)
    rows = -(-n // COLS)
    sheet = np.zeros((rows * CELL, COLS * CELL, 4), np.uint8)
    o = (w - CELL) // 2
    for k, a in enumerate(picks):
        r, c = divmod(k, COLS)
        cell = sheet[r * CELL:(r + 1) * CELL, c * CELL:(c + 1) * CELL]
        cell[..., :3] = 255
        cell[..., 3] = np.round(a[o:o + CELL, o:o + CELL] * 255)
    return Image.fromarray(sheet, "RGBA"), n


def qml_constants():
    t = open(QML).read()
    return {k: int(re.search(r"readonly property int %s:\s*(\d+)" % k, t).group(1))
            for k in ("frames", "cols", "cell", "stepMs")}


def main(argv):
    img, n = build()
    want = {"frames": n, "cols": COLS, "cell": CELL, "stepMs": STEP_MS}
    if "--check" in argv:
        ok = os.path.isfile(OUT) and Image.open(OUT).size == img.size and qml_constants() == want
        print("claude-burst.png is current" if ok else "claude-burst.png / ClaudeBurst.qml are out of step")
        return 0 if ok else 1
    img.save(OUT, optimize=True)
    print("wrote %s  %dx%d  %d frames  %s" % (OUT, img.width, img.height, n, want))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
