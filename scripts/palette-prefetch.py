#!/usr/bin/env python3
"""palette-prefetch.py [--light] < paths — extract pywal palettes BEFORE they're needed.

Applying a wallpaper pywal has never seen costs its extraction (ImageMagick over the
full-resolution picture): 1.4s for a 1920×1080 PNG, 3.2s for a 5619×3746 JPEG,
measured here — the shell sits waiting for it before the wave can even start. A
picture seen before is a cache hit, ~0.1s. So services/Wallpaper runs this over the
library at idle, one image at a time, and every apply after is a hit.

── The cache entry is exactly `wal -i`'s ─────────────────────────────────────
The same calls with the same arguments as `wal -i <path> -n -s -t -e [-l]` (and so
scripts/stage-palette.py): image path through os.path.abspath (image.get), backend
None, sat None, c16 False, cst None — every one of them is in pywal's cache file name.
Nothing is extracted twice: an image with an entry is skipped without being read.
Full resolution, as the user chose: a downscaled proxy would shift the palette.

PYWAL_CACHE_DIR is pointed at a private temp dir whose schemes/ is the LIVE cache's,
so pywal writes nothing else anywhere (no colors.json, no `wal` note, no templates).

One line per extraction on stdout (`extracted <ms> <path>`), errors on stderr. A bad
image is skipped, never fatal. GIFs are skipped: their palette comes from a frame the
apply extracts itself.
"""
import os
import sys
import tempfile
import time


def main():
    light = "--light" in sys.argv[1:]
    cache = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    schemes = os.path.join(cache, "wal", "schemes")
    os.makedirs(schemes, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="palette-prefetch-") as tmp:
        os.symlink(schemes, os.path.join(tmp, "schemes"))
        os.environ["PYWAL_CACHE_DIR"] = tmp
        from pywal import colors
        # pywal narrates its retries ("couldn't generate a palette… trying 17") at
        # WARNING; the shell logs this script's stderr, so only real failures go there.
        import logging
        logging.disable(logging.WARNING)

        for line in sys.stdin:
            path = os.path.abspath(line.rstrip("\n"))
            if not path or path.lower().endswith(".gif") or not os.path.isfile(path):
                continue
            entry = os.path.join(*colors.cache_fname(path, None, light, tmp, None, c16=False))
            if os.path.isfile(entry):
                continue
            t = time.monotonic()
            try:
                colors.get(path, light, None, sat=None, c16=False, cst=None)
            except BaseException as e:          # pywal sys.exit()s on what it can't read
                print("prefetch: skipped %s: %r" % (path, e), file=sys.stderr, flush=True)
                continue
            print("extracted %d %s" % ((time.monotonic() - t) * 1000, path), flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
