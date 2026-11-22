#!/usr/bin/env python3
"""What each wallpaper is mostly: one "#rrggbb" per picture, for the gallery's colour sort and colour search.

    wall-colors.py CACHE.json -- PATH [PATH ...]

Prints `#rrggbb<TAB>path` for every path it could read (a path it cannot is left out). Results are cached in
CACHE.json by path and modification time, so a library is read once and only what changed is read again.

The colour is the picture's DOMINANT VIVID colour: the hue (of 24) that most saturated, mid-bright pixels
vote for, averaged over the pixels in it. A picture with next to no vivid pixels (a grey scene, a night sky)
has none, and gets its plain average, which `wallpaperlib.js` then calls black / white / grey. Pictures are
shrunk to 48 px first, so a whole library costs a few seconds, once.

Tested by scripts/test-wall-colors.py.
"""

import colorsys
import json
import os
import sys
import tempfile

BINS = 24
VIVID_SHARE = 0.06      # fewer vivid pixels than this: no dominant hue, use the average


def dominant(pixels):
    """pixels: [(r, g, b)] 0-255 → "#rrggbb"."""
    if not pixels:
        return ""
    votes = [0.0] * BINS
    sums = [[0.0, 0.0, 0.0] for _ in range(BINS)]
    vivid = 0
    tr = tg = tb = 0
    for r, g, b in pixels:
        tr += r
        tg += g
        tb += b
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if s < 0.25 or v < 0.15 or v > 0.97:
            continue
        vivid += 1
        k = min(BINS - 1, int(h * BINS))
        votes[k] += s * v
        sums[k][0] += r
        sums[k][1] += g
        sums[k][2] += b
    n = len(pixels)
    if vivid / n < VIVID_SHARE:
        return "#%02x%02x%02x" % (round(tr / n), round(tg / n), round(tb / n))
    k = max(range(BINS), key=lambda i: votes[i])
    c = sum(1 for r, g, b in pixels
            if colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)[1] >= 0.25
            and min(BINS - 1, int(colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)[0] * BINS)) == k)
    c = max(1, c)
    return "#%02x%02x%02x" % (round(sums[k][0] / c), round(sums[k][1] / c), round(sums[k][2] / c))


def read_pixels(path):
    from PIL import Image
    with Image.open(path) as im:
        try:
            im.draft("RGB", (96, 96))      # a JPEG decodes at a fraction of its size
        except Exception:
            pass
        im = im.convert("RGB")
        im.thumbnail((48, 48))
        return list(im.getdata())


def load_cache(cache):
    try:
        with open(cache, encoding="utf-8") as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def save_cache(cache, data):
    folder = os.path.dirname(cache) or "."
    os.makedirs(folder, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=folder, prefix=".wall-colors-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(data, f)
        os.replace(tmp, cache)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def main(argv):
    if len(argv) < 3 or argv[2] != "--":
        print("usage: wall-colors.py CACHE.json -- PATH...", file=sys.stderr)
        return 2
    cache, paths = argv[1], argv[3:]
    data = load_cache(cache)
    keep, dirty = {}, False
    for p in paths:
        try:
            m = os.stat(p).st_mtime
        except OSError:
            continue
        hit = data.get(p)
        if isinstance(hit, dict) and hit.get("m") == m and isinstance(hit.get("c"), str):
            colour = hit["c"]
        else:
            try:
                colour = dominant(read_pixels(p))
            except Exception:
                continue
            dirty = True
        if colour:
            keep[p] = {"m": m, "c": colour}
            print(colour + "\t" + p, flush=True)
    # The cache holds exactly what is in the library now: a removed picture's entry goes with it.
    if dirty or set(keep) != set(data):
        save_cache(cache, keep)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
