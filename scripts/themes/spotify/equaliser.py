#!/usr/bin/env python3
"""
equaliser.py

Prints QuickSpice's two equaliser masks as CSS custom properties, for pasting into
spicetify/Themes/QuickSpice/user.css (the `:root` block beside --qs-wave):

  --qs-eq        an animated WebP: VisualizerPill's bars, moving
  --qs-eq-still  an SVG: the same bars at rest

Spotify's "this is playing" mark is an <img> of its own green GIF; user.css paints that
img's box in the accent THROUGH one of these. They are masks, so only alpha matters.

The shell's bars (VisualizerPill, Spectrum): 3px wide, centred on the row, square ends
(Spectrum turns rounding off below 4px), held still when nothing moves them. Spotify's
mark is 14px, so three bars with 2.5px gaps fill it exactly; drawn at 4x (56px) so the
browser's downscale smooths them at any size the img is given.

Why a WebP and not an SVG with CSS animation: an animated SVG image is serviced every
frame (60Hz) on the page's main thread, which is the thread Spotify keeps saturated. An
animated bitmap repaints once per frame of its own — 20 a second here, against the 33 of
the GIF it replaces.
"""
import base64
import io
import math
import urllib.parse

from PIL import Image, ImageDraw

SIZE   = 56                      # 4 x 14px
BAR_W  = 12                      # 3px
GAP    = 10                      # 2.5px
BARS   = 3
FRAMES = 24
MS     = 50                      # 20fps, a 1.2s loop
LOW, HIGH = 0.22, 1.0            # a bar never vanishes: at its lowest it is a 3px square
# Whole cycles per loop (so it repeats seamlessly) and a phase per bar, so the three
# never move as one.
CYCLES = (2, 3, 1)
PHASES = (0.0, 2.1, 4.2)
STILL  = (0.42, 0.56, 0.42)      # at rest: the idle wave's arch, crest in the middle


def bar_rects(levels):
    """(x0, y0, x1, y1) per bar, centred vertically; heights kept even so they stay centred."""
    out = []
    for i, level in enumerate(levels):
        h = max(2, round(level * SIZE / 2) * 2)
        x = i * (BAR_W + GAP)
        y = (SIZE - h) // 2
        out.append((x, y, x + BAR_W, y + h))
    return out


def frame(levels):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for x0, y0, x1, y1 in bar_rects(levels):
        draw.rectangle((x0, y0, x1 - 1, y1 - 1), fill=(255, 255, 255, 255))
    return img


def levels_at(f):
    t = 2 * math.pi * f / FRAMES
    return [LOW + (HIGH - LOW) * (0.5 + 0.5 * math.sin(c * t + p)) for c, p in zip(CYCLES, PHASES)]


def animated_webp():
    frames = [frame(levels_at(f)) for f in range(FRAMES)]
    buf = io.BytesIO()
    frames[0].save(buf, "WEBP", save_all=True, append_images=frames[1:],
                   duration=MS, loop=0, lossless=True)
    return "data:image/webp;base64," + base64.b64encode(buf.getvalue()).decode()


def still_svg():
    rects = "".join('<rect x="%d" y="%d" width="%d" height="%d"/>' % (x0, y0, x1 - x0, y1 - y0)
                    for x0, y0, x1, y1 in bar_rects(STILL))
    svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d">%s</svg>' % (SIZE, SIZE, rects)
    return "data:image/svg+xml," + urllib.parse.quote(svg, safe="")


if __name__ == "__main__":
    print('  --qs-eq: url("%s");' % animated_webp())
    print('  --qs-eq-still: url("%s");' % still_svg())
