#!/usr/bin/env python3
"""Extract a small palette from an album cover, for the shell's media cards.

    album-colors.py <url|file://path|path>  ->  {"ok":true,"bg":"#…","accent":"#…","fg":"#…"}

Always prints JSON and always exits 0. A failure is `{"ok": false}` and the shell falls
back to the pywal palette — a lyrics card must never be left unstyled because a cover
404'd.

Three colours, each with a different job:

  bg      the card's fill. The darkest swatch that actually carries weight, so the card
          reads as the cover's own shadow rather than as an unrelated dark rectangle.

  accent  the live lyric line, the seek bar, the play button. Scored on SATURATION, not
          on frequency. Frequency picks the most *common* colour, and on a muted cover
          that is a grey — which is exactly the look we're trying to get away from.
          A flat cover gets its chroma nudged up so it still reads as a colour.

  fg      body text. The lightest swatch, then forced away from `bg` until it is actually
          legible. Text contrast is not negotiable against an arbitrary image.
"""

import sys, json, io, colorsys, urllib.request

TIMEOUT = 8
UA = "quickshell-album-colors/1"


def load(src):
    if src.startswith(("http://", "https://")):
        req = urllib.request.Request(src, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return Image.open(io.BytesIO(r.read()))
    return Image.open(src[7:] if src.startswith("file://") else src)


def hexs(rgb):
    return "#%02X%02X%02X" % tuple(max(0, min(255, int(round(c)))) for c in rgb)


def hls(rgb):
    r, g, b = (c / 255 for c in rgb)
    return colorsys.rgb_to_hls(r, g, b)


def rgb(h, l, s):
    return tuple(c * 255 for c in colorsys.hls_to_rgb(h, l, s))


def relative_luminance(c):
    """WCAG. Used to guarantee the text is readable, not to look pretty."""
    def chan(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (chan(x) for x in c)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = relative_luminance(a), relative_luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def extract(src, n=8):
    im = load(src).convert("RGB").resize((64, 64), Image.BILINEAR)
    q = im.quantize(colors=n, method=Image.MEDIANCUT)
    pal = q.getpalette()
    counts = q.getcolors()
    if not counts:
        raise ValueError("no colours")

    total = sum(c for c, _ in counts)
    sw = []
    for count, idx in counts:
        c = tuple(pal[idx * 3: idx * 3 + 3])
        h, l, s = hls(c)
        sw.append({"rgb": c, "h": h, "l": l, "s": s, "w": count / total})

    # ── accent ───────────────────────────────────────────────────────────────
    # Vibrancy, weighted toward mid-lightness (a colour that is nearly black or nearly
    # white carries no hue you can see), with only a mild bonus for being common.
    def score(c):
        mid = max(0.0, 1 - abs(c["l"] - 0.55) * 2)
        return (c["s"] ** 1.5) * mid * (0.35 + c["w"])

    accent = max(sw, key=score)
    ah, al, as_ = accent["h"], accent["l"], accent["s"]

    # The most saturated colour the cover ACTUALLY has, BEFORE any boosting. This is the
    # honest "is this cover monochrome?" signal the shell uses to decide whether to fall
    # back to the source's brand colours — the boosted accent below would hide it.
    raw_sat = max(c["s"] for c in sw)

    # A genuinely monochrome cover has nothing to boost — leave it alone rather than
    # inventing a hue that isn't in the artwork. But a merely *muted* one gets lifted, or
    # the card is grey again and the whole exercise was pointless.
    if as_ < 0.45:
        as_ = min(0.62, as_ * 1.9 + 0.12)
    al = min(max(al, 0.45), 0.72)
    accent_rgb = rgb(ah, al, as_)

    # ── bg ───────────────────────────────────────────────────────────────────
    heavy = [c for c in sw if c["w"] > 0.04] or sw
    bg = min(heavy, key=lambda c: c["l"])
    bh, bl, bs = bg["h"], bg["l"], bg["s"]
    bl = min(bl, 0.16)                      # keep it a backdrop, never a subject
    bs = min(bs, 0.45)
    bg_rgb = rgb(bh, bl, bs)

    # ── fg ───────────────────────────────────────────────────────────────────
    # Start from the lightest swatch (keeps the cover's tint), then walk it toward white
    # until it clears WCAG AA against bg. Guaranteed legible, still album-coloured.
    fg = max(sw, key=lambda c: c["l"])
    fh, fl, fs = fg["h"], fg["l"], min(fg["s"], 0.25)
    fl = max(fl, 0.80)
    fg_rgb = rgb(fh, fl, fs)

    guard = 0
    while contrast(fg_rgb, bg_rgb) < 4.5 and guard < 24:
        fl = min(1.0, fl + 0.02)
        fs = max(0.0, fs - 0.01)
        fg_rgb = rgb(fh, fl, fs)
        guard += 1

    return {
        "ok": True,
        "bg": hexs(bg_rgb),
        "accent": hexs(accent_rgb),
        "fg": hexs(fg_rgb),
        "sat": round(raw_sat, 3),
        "contrast": round(contrast(fg_rgb, bg_rgb), 2),
    }


if __name__ == "__main__":
    try:
        from PIL import Image  # imported here so a missing Pillow is a clean {"ok":false}
        print(json.dumps(extract(sys.argv[1])))
    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e)}))
