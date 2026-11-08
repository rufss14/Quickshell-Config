#!/usr/bin/env python3
"""Extract a palette from an album cover.

    album-colors.py <src>            ->  {"ok":true,"bg":"#…","accent":"#…","fg":"#…"}
    album-colors.py --scheme <src>   ->  {"ok":true,"special":{…},"colors":{color0…color15}}
    album-colors.py --scheme --light <src>

`<src>` is a url, a file:// url, or a path.

Always prints JSON and always exits 0. A failure is `{"ok": false}` and the shell falls
back to the pywal palette — a lyrics card must never be left unstyled because a cover
404'd.

── The three-colour mode ────────────────────────────────────────────────────────
The media cards' own dressing. Three colours, each with a different job:

  bg      the card's fill. The darkest swatch that actually carries weight, so the card
          reads as the cover's own shadow rather than as an unrelated dark rectangle.

  accent  the live lyric line, the seek bar, the play button. Scored on SATURATION, not
          on frequency. Frequency picks the most *common* colour, and on a muted cover
          that is a grey — which is exactly the look we're trying to get away from.
          A flat cover gets its chroma nudged up so it still reads as a colour.

  fg      body text. The lightest swatch, then forced away from `bg` until it is actually
          legible. Text contrast is not negotiable against an arbitrary image.

── `--scheme`: the whole shell ──────────────────────────────────────────────────
Emits the SAME SHAPE pywal writes to ~/.cache/wal/colors.json — `special` plus
color0..color15 — so everything downstream that already understands a wallpaper
palette understands an album one with no second format to teach it.

Deliberately a separate mode rather than a wider default: the three-colour output
above is what AlbumArt.qml parses on every track, and it stays byte-for-byte what it
was. Two callers, two contracts, one extraction.

── Nothing enters this palette that was not in the artwork ─────────────────────
The one rule. Six accents are taken from the cover by AREA, kept apart by perceptual
distance, and where the sleeve has fewer than six distinguishable colours the ramp is
filled by moving the ones it does have LIGHTER OR DARKER — never by adding a hue.
Black and white count as colours: a monochrome sleeve produces a monochrome palette.

Two things are still allowed to move a colour, both for legibility and neither of them
touching hue or chroma:

  · lightness is clamped into a band, and then walked away from the background until
    the accent clears 3:1 against it. An accent that is faithful and invisible is not
    faithful — this landed a near-black navy in color1, which is the shell's `primary`,
    the fill under every button.
  · the foreground is walked to 7:1 against the background, because text contrast is
    not negotiable against an arbitrary image.

Everything else is the cover's. Three earlier cuts each invented colour in a different
way and each looked wrong in the same way — a saturation FLOOR that turned a
black-and-white sleeve into confident teals and purples; missing slots filled at the
ANSI slot's own hue, which rainbowed a wholly blue cover; and missing slots fanned out
from the dominant hue, which was merely a subtler version of the same mistake.

Accents are then *reordered* onto the ANSI slots by which canonical hue each is
nearest — red-ish into color1, blue-ish into color4. Reordering only, and free: the
shell remaps these to roles anyway (color1 = primary, color4 = focus), so the ordering
exists purely so a terminal wearing this palette gets the least-wrong ANSI available.
Neutrals carry no hue to match on and take the remaining slots darkest-first.
"""

import sys, json, io, math, colorsys, urllib.request

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


def swatches(src, n=8, size=64):
    """The cover reduced to `n` weighted swatches, each carrying its HLS.

    Shared by both modes so there is one answer to "what colours are in this cover".
    `size` is larger for --scheme: six hues have to be told apart, and a 64px thumbnail
    quantised to sixteen buckets starts inventing near-duplicates out of JPEG noise.
    """
    im = load(src).convert("RGB").resize((size, size), Image.BILINEAR)
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
        # HLS for the three-colour mode, which is written in it; Lab for --scheme,
        # which needs a measure of colourfulness that behaves at the ends of the scale.
        sw.append({"rgb": c, "h": h, "l": l, "s": s, "w": count / total,
                   "lab": to_lab(c)})
    return sw


def extract(src, n=8):
    sw = swatches(src, n)

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


# ── --scheme ─────────────────────────────────────────────────────────────────────

# Where each ANSI slot's hue nominally sits. Used ONLY to order accents that already
# exist — nothing is ever rotated toward these, and a cover with no red gets no red.
CANON = [
    (1, 0.000),   # red
    (2, 0.333),   # green
    (3, 0.125),   # yellow
    (4, 0.611),   # blue
    (5, 0.833),   # magenta
    (6, 0.500),   # cyan
]


def hue_gap(a, b):
    """Distance around the wheel, so 0.98 and 0.02 are close rather than opposite."""
    d = abs(a - b) % 1.0
    return min(d, 1.0 - d)


# ── Perceptual distance ──────────────────────────────────────────────────────────
# Separation used to be measured as a HUE GAP, and that is the bug behind both "it
# sometimes has trouble creating colours" and the invented ones. Hue is undefined for a
# grey and unstable for anything near-grey, so:
#
#   · every neutral swatch was thrown out of the running (`s < 0.08`), which is most of
#     a black-and-white sleeve and much of a muted one;
#   · two colours differing only in LIGHTNESS — navy and sky, charcoal and bone — read
#     as "the same hue" and were rejected as duplicates;
#   · with too few survivors, hues had to be fabricated to fill the ramp.
#
# CIELAB distance answers the question actually being asked, which is "can you tell
# these two apart", and it answers it for greys as readily as for colours.
def to_lab(rgb_t):
    def lin(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (lin(float(c)) for c in rgb_t)
    x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047
    y = (r * 0.2126 + g * 0.7152 + b * 0.0722)
    z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883

    def f(t):
        return t ** (1.0 / 3.0) if t > 0.008856 else (7.787 * t + 16.0 / 116.0)
    fx, fy, fz = f(x), f(y), f(z)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def delta_e(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def lab_to_rgb(L, a, b):
    """Inverse of to_lab, clamped into gamut."""
    fy = (L + 16) / 116.0
    fx, fz = fy + a / 500.0, fy - b / 200.0

    def finv(t):
        return t ** 3 if t ** 3 > 0.008856 else (t - 16.0 / 116.0) / 7.787
    x, y, z = finv(fx) * 0.95047, finv(fy), finv(fz) * 1.08883

    r = x * 3.2406 + y * -1.5372 + z * -0.4986
    g = x * -0.9689 + y * 1.8758 + z * 0.0415
    bb = x * 0.0557 + y * -0.2040 + z * 1.0570

    def gam(c):
        c = max(0.0, min(1.0, c))
        return 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055
    return tuple(gam(v) * 255 for v in (r, g, bb))


def chroma_of(lab):
    return math.hypot(lab[1], lab[2])


def with_lightness(lab, L, cap=None):
    """Move a colour's LIGHTNESS, keeping its hue, and never letting chroma GROW.

    ── The phantom-chroma bug ───────────────────────────────────────────────
    This used to be done in HLS: keep `s`, change `l`. That is wrong at the ends of the
    scale and wrong in the worst possible way. A near-white pixel like (252, 252, 250)
    has an HLS saturation of 0.25 — the formula divides by a vanishing range — and a
    near-black one like (2, 2, 3) has 0.2. Both are perceptually colourless. Carry that
    "saturation" down to a mid lightness and it becomes REAL: measured, a white sleeve
    produced tan and olive accents (#A37A52, #CDCDAC) and a black one produced violet
    (#54548C, #68568A), none of which is in either cover.

    Real sleeves are full of near-black shadow and near-white highlight, so this fired
    constantly — it is the whole of "it sometimes has trouble creating colours".

    In LCh the question is asked properly: chroma is an absolute distance from grey, so
    a colourless pixel has none, and lightening it yields grey. Chroma is additionally
    capped, never scaled up, so nothing can gain colour on the way through.
    """
    c = chroma_of(lab)
    if cap is not None:
        c = min(c, cap)
    if c < 1e-6:
        return lab_to_rgb(L, 0.0, 0.0)

    # Direction in the a/b plane is the hue; only its length changes.
    ux, uy = lab[1] / chroma_of(lab), lab[2] / chroma_of(lab)

    # Lightening at a fixed chroma can leave the sRGB gamut, and the clamp in
    # lab_to_rgb() would silently shift the hue if it did. Backing the chroma off until
    # it fits keeps the hue honest — a duller version of the right colour beats a
    # clipped version of the wrong one.
    for _ in range(12):
        out = lab_to_rgb(L, ux * c, uy * c)
        if delta_e(to_lab(out), (L, ux * c, uy * c)) < 2.0:
            return out
        c *= 0.85
    return lab_to_rgb(L, 0.0, 0.0)


# How far apart two FINAL accents must be, tried in order. Roughly: 26 is "obviously a
# different colour", 15 "clearly distinguishable", 9 "adjacent but not the same", 5
# "side by side you can see it". The cover's own colours are taken at the widest
# separation available before anything is derived from them.
#
# The 5.0 tier earns its place on monochrome sleeves and changes nothing else: measured
# across the test covers, stopping at 9.0 left a black-and-white cover with four
# distinct accents and two repeats, while 5.0 fills all six and leaves a four-colour
# cover byte-identical. A 3.0 tier was tried and is worse — it crams six greys into the
# range one end of the scale, which reads as banding rather than as a palette.
DELTAS = (26.0, 15.0, 9.0, 5.0)


def fit(lab, light, bg_rgb, lo, hi, cap=None):
    """Put a colour where it can be SEEN, without changing what colour it is.

    Lightness only, in two steps: clamp L* into a band, then walk away from the
    background until it clears a 3:1 contrast ratio. Hue is untouched and chroma can
    only ever go DOWN — see with_lightness() for why that is the whole ballgame.

    The contrast walk is not optional. The band alone let a derived variant land at
    near-black navy on a near-black ground — as color1, which is the shell's `primary`,
    the fill under every button. Faithful and invisible is not faithful.
    """
    L = min(max(lab[0], lo), hi)
    out = with_lightness(lab, L, cap)
    guard = 0
    while contrast(out, bg_rgb) < 3.0 and guard < 50:
        L = min(100.0, L + 2.0) if not light else max(0.0, L - 2.0)
        out = with_lightness(lab, L, cap)
        guard += 1
    return out


# The L* band a cover's own swatch is held to, and the wider one a DERIVED variant may
# use. Variants get more room on purpose: they exist to make up the numbers on a sleeve
# that has few distinct colours, and inside the tight band a black-and-white cover
# yields about two distinguishable greys rather than six. The contrast floor in fit()
# is what keeps the extra room honest.
#
# In L*, not HLS lightness: the bands are separation budgets measured against a
# perceptual DELTAS threshold, so they have to be in the same units as that threshold.
BAND      = {False: (46.0, 80.0), True: (30.0, 60.0)}
BAND_WIDE = {False: (30.0, 94.0), True: (14.0, 78.0)}


def pick_accents(sw, light, bg_rgb, want=6):
    """The cover's own most prominent colours, as many as are actually distinguishable.

    Ranked by AREA first. A faithful palette is made of the colours that are genuinely
    there, so the swatch covering a third of the sleeve outranks a vivid speck of it —
    the old scoring was the other way round and would pick a stray highlight over the
    colour the record actually looks like.

    Separation is measured on the NORMALISED colour, not the raw one, which is the
    subtle half of the fix: two near-black swatches are far apart in Lab until the
    lightness clamp lands them both on the same mid-tone, and only then are they
    duplicates. Comparing before normalising let visibly-identical accents through.

    Returns FEWER than `want` when the sleeve genuinely has fewer distinguishable
    colours in it. That is a truthful answer and derive_variants() takes it from there.
    """
    def score(c):
        return c["w"] * (0.6 + 0.4 * min(chroma_of(c["lab"]) / 60.0, 1.0))

    lo, hi = BAND[light]
    ranked = sorted(range(len(sw)), key=lambda i: score(sw[i]), reverse=True)
    picked, used = [], set()
    for d in DELTAS:
        for i in ranked:
            if i in used:
                continue
            out = fit(sw[i]["lab"], light, bg_rgb, lo, hi)
            lab = to_lab(out)
            if all(delta_e(lab, p["lab"]) >= d for p in picked):
                picked.append({"rgb": out, "lab": lab, "w": sw[i]["w"]})
                used.add(i)
                if len(picked) == want:
                    return picked
    return picked


def derive_variants(picked, light, bg_rgb, want=6):
    """Make up the numbers from the cover's OWN colours — never a new hue.

    A sleeve with three colours in it has three colours in it. The ramp still needs six
    entries, so the shortfall is filled by taking what was picked and moving it in
    LIGHTNESS: the same colour, lighter or darker. Nothing enters the palette that was
    not in the artwork.

    This is what the request "faithful to the cover, no extra colours, unless it's one
    colour only" asks for, and it is the one place a monochrome sleeve is allowed to
    expand: black and white are colours here, so a black-and-white cover produces a
    black-and-white ramp rather than being rejected or, worse, rainbowed. Two earlier
    cuts both invented hues — one at the ANSI slot's own hue, one fanned out from the
    dominant one — and both were wrong in the same way.
    """
    out = list(picked)
    if not out:
        return out

    lo, hi = BAND_WIDE[light]
    # Widening excursions in L*, alternating lighter and darker, so the first variants
    # stay closest to the colour they came from.
    #
    # More steps than looks necessary, because the contrast floor in fit() keeps
    # pushing candidates back INTO occupied territory — a variant aimed at L 36 on a
    # dark ground comes back at L 45, collides with something already taken, and is
    # rejected. Measured on an all-white sleeve, the coarse list (12/22/32/44) ran out
    # of options at five distinct accents and the sixth became a repeat; this list
    # fills all six on every test cover and changes none of the ones that already fit.
    steps = [12, -12, 18, -18, 24, -24, 30, -30, 38, -38, 46, -46]
    for d in DELTAS:
        for step in steps:
            for src in list(out):
                if len(out) >= want:
                    return out
                moved = (src["lab"][0] + step, src["lab"][1], src["lab"][2])
                cand = fit(moved, light, bg_rgb, lo, hi)
                lab = to_lab(cand)
                if all(delta_e(lab, p["lab"]) >= d for p in out):
                    out.append({"rgb": cand, "lab": lab, "w": 0.0})

    # ── Still short: repeat, never invent ────────────────────────────────────
    # A black-and-white sleeve yields perhaps four greys that are honestly
    # distinguishable, and no amount of wanting six will produce a fifth. The ramp is
    # filled by REUSING what the cover gave us, cycling from the most prominent.
    #
    # The alternative shipped briefly and was a bug: unfilled slots fell through to a
    # single constant grey, so color5 and color6 came out byte-identical — which in a
    # terminal is magenta and cyan being the same colour. A repeat is a truthful
    # statement about a sleeve that only has four colours in it; a duplicated fallback
    # constant is just a hole.
    i = 0
    while len(out) < want and picked:
        out.append(dict(picked[i % len(picked)]))
        i += 1
    return out


def assign_slots(accents):
    """Put the accents on slots 1..6. Reordering only — no colour is altered.

    Chromatic accents go to the canonical hue they are nearest, greedily over every
    (accent, slot) pair closest-first, so the most obviously-red colour claims color1
    before a merely warm one can. It costs nothing, and it means a cover that DOES hold
    a red puts it where a terminal expects red.

    Neutrals carry no hue to match on, so they take whatever slots are left, darkest
    first. On a black-and-white sleeve that is every slot, and the ramp comes out as an
    ordered grey scale rather than an arbitrary shuffle.
    """
    # Chromatic in the PERCEPTUAL sense. An HLS-saturation test here would call a
    # near-white swatch colourful and hand it a hue slot on the strength of a chroma it
    # does not have.
    chromatic = [i for i, a in enumerate(accents) if chroma_of(a["lab"]) >= 8.0]
    neutral = [i for i, a in enumerate(accents) if chroma_of(a["lab"]) < 8.0]

    pairs = sorted(
        ((hue_gap(hls(accents[ai]["rgb"])[0], ch), ai, slot)
         for ai in chromatic
         for slot, ch in CANON),
        key=lambda t: t[0],
    )
    out, used_a, used_s = {}, set(), set()
    for _, ai, slot in pairs:
        if ai in used_a or slot in used_s:
            continue
        out[slot] = accents[ai]
        used_a.add(ai)
        used_s.add(slot)

    spare = sorted((i for i in neutral if i not in used_a),
                   key=lambda i: accents[i]["lab"][0])
    for slot, _ in CANON:
        if slot in out:
            continue
        if not spare:
            break
        out[slot] = accents[spare.pop(0)]
    return out


def scheme(src, light=False):
    sw = swatches(src, n=16, size=128)
    raw_sat = max(c["s"] for c in sw)

    # ── The hue the cover is "about" ─────────────────────────────────────────
    # Carried into the greys so the neutrals belong to the same picture rather than
    # being generic slate — and carried only as far as the sleeve actually is coloured.
    # `tint_c` is a CHROMA ceiling in Lab units, so a black-and-white cover contributes
    # nothing and its neutrals come out neutral. Judged by chroma rather than HLS
    # saturation for the reason in with_lightness(): on a monochrome sleeve, HLS calls
    # the JPEG noise "saturated" and the whole desktop came out faintly lilac.
    tintish = max(sw, key=lambda c: chroma_of(c["lab"]) * (0.3 + c["w"]))
    tint_lab = tintish["lab"]
    tint_c = min(chroma_of(tint_lab), 8.0)

    # ── background / foreground ──────────────────────────────────────────────
    # Same reasoning as the three-colour mode, but taken further: this is the whole
    # desktop's ground, so it is clamped harder. A background carrying real chroma
    # reads as a coloured overlay over everything, which is exactly the "cursed light
    # mode" failure apply-wallpaper.sh has its own repair step for.
    heavy = [c for c in sw if c["w"] > 0.03] or sw
    if light:
        b = max(heavy, key=lambda c: c["lab"][0])
        bg = with_lightness(b["lab"], max(b["lab"][0], 97.0), 5.0)
        fg_L, fg_step = 22.0, -2.0
    else:
        b = min(heavy, key=lambda c: c["lab"][0])
        bg = with_lightness(b["lab"], min(b["lab"][0], 12.0), 10.0)
        fg_L, fg_step = 93.0, 2.0

    # Text contrast is not negotiable against an arbitrary image — same walk the
    # three-colour mode does, held to AA-for-body (7.0) because this palette dresses
    # every application, not one card.
    fg = with_lightness(tint_lab, fg_L, tint_c * 0.6)
    guard = 0
    while contrast(fg, bg) < 7.0 and guard < 50:
        fg_L = min(100.0, max(0.0, fg_L + fg_step))
        fg = with_lightness(tint_lab, fg_L, tint_c * 0.6)
        guard += 1

    # ── the six accents ──────────────────────────────────────────────────────
    # Straight from the cover. fit() has already clamped lightness into a legible band
    # and enforced contrast against the ground; hue and chroma are the sleeve's own,
    # and nothing here adds either.
    picked = pick_accents(sw, light, bg)
    slots = assign_slots(derive_variants(picked, light, bg))

    colors = {}
    for slot in range(1, 7):
        a = slots.get(slot)
        if a is None:
            # Reachable only for a cover that yielded nothing at all. Fall back to the
            # tint rather than inventing: an unfillable slot is a real answer about the
            # artwork, and this is still one of the artwork's own colours.
            a = {"rgb": with_lightness(tint_lab, 60.0 if not light else 45.0, tint_c),
                 "lab": None}
            a["lab"] = to_lab(a["rgb"])
        colors["color%d" % slot] = hexs(a["rgb"])
        # The bright half is the same colour, lifted. Same hue, same chroma — bold text
        # must brighten, not change colour.
        bright_L = min(96.0, a["lab"][0] + 12.0) if not light \
            else max(8.0, a["lab"][0] - 12.0)
        colors["color%d" % (slot + 8)] = hexs(with_lightness(a["lab"], bright_L))

    # ── the neutrals ─────────────────────────────────────────────────────────
    # color0/8 are the shell's surfaces and the terminal's black; color7/15 its text.
    # Tinted with the cover's hue only as far as the cover is actually tinted.
    bg_lab, fg_lab = to_lab(bg), to_lab(fg)
    colors["color0"] = hexs(with_lightness(
        bg_lab, bg_lab[0] + (-5.0 if light else 5.0), tint_c))
    colors["color8"] = hexs(with_lightness(tint_lab, 62.0 if light else 45.0, tint_c))
    colors["color7"] = hexs(with_lightness(
        fg_lab, fg_lab[0] + (7.0 if light else -7.0), tint_c * 0.6))
    colors["color15"] = hexs(fg)

    return {
        "ok": True,
        # pywal writes these two and reload-theme.sh's template re-export reads the file
        # back whole — omitting them would hand `wal --theme` a file it does not fully
        # recognise.
        "wallpaper": src,
        "alpha": "100",
        "special": {
            "background": hexs(bg),
            "foreground": hexs(fg),
            "cursor": colors["color1"],
        },
        "colors": colors,
        "sat": round(raw_sat, 3),
        "contrast": round(contrast(fg, bg), 2),
    }


if __name__ == "__main__":
    try:
        from PIL import Image  # imported here so a missing Pillow is a clean {"ok":false}
        args = sys.argv[1:]
        want_scheme = "--scheme" in args
        light = "--light" in args
        rest = [a for a in args if not a.startswith("--")]
        if not rest:
            raise ValueError("no source given")
        print(json.dumps(scheme(rest[0], light) if want_scheme else extract(rest[0])))
    except Exception as e:
        print(json.dumps({"ok": False, "error": str(e)}))
