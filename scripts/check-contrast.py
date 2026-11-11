#!/usr/bin/env python3
"""Contrast of the text roles against the lightest common surface, per bundled scheme.

Reads the guard's targets and floor alphas out of config/PaletteRoles.qml (the `Contrast.alphaFor`
calls behind fgMuted and fgDim), applies the guard the way the palette does (services/contrast.js:
the least alpha that reaches the target over surfaceHigh, never below the floor; fgMuted kept
0.06 above fgDim), mixes the result over surfaceHigh, and fails if a role still drops below its
target — which only happens when even a solid text colour can't reach it. fgFaint is
for things that are meant to recede (disabled, decorative) and is not checked.
Light mode: the light alphas (the first number in each `_lightMode ?` ternary) are measured on
every scheme that ships a "light" variant. Only one bundled scheme does; a wallpaper's light
palette is generated per wallpaper (pywal), so this is a spot check, not coverage.

    python3 scripts/check-contrast.py
"""
import glob, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FLOORS = {"fgMuted": 4.5, "fgDim": 4.0}   # the guard's targets; fgFaint is not guarded

def rgb(h):
    h = h.lstrip("#")
    return [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]

def lin(v):
    return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4

def lum(c):
    r, g, b = (lin(x) for x in c)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def mix(a, b, t):
    return [x * (1 - t) + y * t for x, y in zip(a, b)]

def ratio(a, b):
    hi, lo = sorted((lum(a), lum(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)

src = open(os.path.join(ROOT, "config", "PaletteRoles.qml")).read()
# role -> {"target": T, "dark": floor alpha, "light": floor alpha}, from
#   Contrast.alphaFor(text, surfaceHigh, T, root._lightMode ? L : D)   or   (…, T, A)
# where T may be `root._hc ? H : T`: high contrast's own target, then the one measured here
# (this checks the default palette; high contrast only raises the targets).
floors = {}
for role, prop in (("fgMuted", "_mutedAlpha"), ("fgDim", "_dimAlpha")):
    m = re.search(r"%s:[^\n]*?Contrast\.alphaFor\(text, surfaceHigh, (?:root\._hc \? [\d.]+ : )?([\d.]+),\s*(?:root\._lightMode \? ([\d.]+) : ([\d.]+)|([\d.]+))\)" % prop, src, re.S)
    if not m:
        sys.exit("could not read the %s guard from PaletteRoles.qml" % role)
    dark = float(m.group(3) or m.group(4))
    floors[role] = {"target": float(m.group(1)), "dark": dark, "light": float(m.group(2) or dark)}
    if floors[role]["target"] != FLOORS[role]:
        sys.exit("%s: PaletteRoles targets %s, this script says %s" % (role, floors[role]["target"], FLOORS[role]))

def alpha_for(fg, bg, target, floor):
    """services/contrast.js alphaFor, in Python."""
    if ratio(mix(bg, fg, floor), bg) >= target:
        return floor
    if ratio(fg, bg) < target:
        return 1.0
    lo, hi = floor, 1.0
    for _ in range(16):
        mid = (lo + hi) / 2
        if ratio(mix(bg, fg, mid), bg) >= target:
            hi = mid
        else:
            lo = mid
    return hi

def measure(label, pal, mode):
    """One row for a palette read the way PaletteRoles reads it. Returns the below-floor count."""
    base, text = rgb(pal["special"]["background"]), rgb(pal["colors"]["color7"])
    primary = rgb(pal["colors"].get("color4", "#888888"))
    surface = mix(mix(base, text, 0.12), primary, 0.10)  # surfaceHigh
    dim = alpha_for(text, surface, floors["fgDim"]["target"], floors["fgDim"][mode])
    muted = max(alpha_for(text, surface, floors["fgMuted"]["target"], floors["fgMuted"][mode]), min(1.0, dim + 0.06))
    row, bad = [], 0
    for role, a in (("fgMuted", muted), ("fgDim", dim)):
        c = ratio(mix(surface, text, a), surface)
        row.append("%s %.1f (a %.2f)" % (role, c, a))
        if c < FLOORS[role] - 0.05:
            bad += 1
            row[-1] += " <" + str(FLOORS[role])
    print("%-30s %s" % (label, "  ".join(row)))
    return bad

bad = 0
for f in sorted(glob.glob(os.path.join(ROOT, "colorschemes", "*.json"))):
    d = json.load(open(f))
    name = os.path.basename(f)[:-5]
    variants = d.get("variants") or {}
    bad += measure(name + (" (dark)" if variants else ""), variants.get("dark", d), "dark")
    if variants.get("light"):
        bad += measure(name + " (light)", variants["light"], "light")
print("below-floor=%d" % bad)
sys.exit(1 if bad else 0)
