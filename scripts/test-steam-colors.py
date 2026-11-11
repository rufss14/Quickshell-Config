#!/usr/bin/env python3
# ── test-steam-colors.py ─────────────────────────────────────────────────────
# Tests for steam-colors.py (the pywal → Material "Matugen" stylesheet). Fully local and
# SAFE TO RUN: every case writes into a throwaway temp dir; the installed theme and
# Millennium's config are only ever READ (to check the role list), never written.
#
#   python3 scripts/test-steam-colors.py
# ─────────────────────────────────────────────────────────────────────────────
import colorsys
import json
import os
import re
import sys
import tempfile
from importlib.machinery import SourceFileLoader

HERE = os.path.dirname(os.path.abspath(__file__))
sc = SourceFileLoader("steam_colors", os.path.join(HERE, "steam-colors.py")).load_module()

PASS = FAIL = 0


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
    else:
        FAIL += 1
        print("FAIL: %s %s" % (name, detail))


def palette(bg="#1c1f2d", **over):
    c = {"color%d" % i: "#%02x%02x%02x" % (i * 15, 255 - i * 9, 40 + i * 10) for i in range(16)}
    c["color7"] = "#e9eaf4" if sc.lum(sc.rgb(bg)) < 0.4 else "#22232b"
    c.update(over)
    return {"special": {"background": bg, "foreground": c["color7"], "cursor": c["color7"]}, "colors": c}


def values(text):
    return dict(re.findall(r"--md-sys-color-([a-z-]+): (rgb\([^)]*\));", text))


def rgbof(css):
    return [int(v) for v in re.findall(r"\d+", css)]


DARK = palette()
text = sc.render(DARK)
vals = values(text)

# every role Material's own sheets read (read off the installed theme when there is one)
USED = {"primary", "on-surface", "on-surface-variant", "on-secondary-container", "on-primary", "outline",
        "secondary-container", "surface-container-high", "surface-container", "surface-container-low", "surface",
        "surface-container-highest", "outline-variant", "secondary", "on-secondary", "on-primary-container",
        "on-tertiary-container", "surface-variant", "error", "primary-container", "tertiary", "tertiary-container",
        "on-error-container", "on-error", "surface-container-lowest", "on-tertiary", "inverse-on-surface",
        "error-container", "primary-fixed", "inverse-surface", "on-primary-fixed", "tertiary-fixed",
        "on-tertiary-fixed", "surface-bright", "background", "on-background", "shadow", "scrim"}
theme = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share"),
                     "Steam", "millennium", "themes", "Material-Theme")
if os.path.isdir(os.path.join(theme, "css")):
    found = set()
    for d, _, files in os.walk(theme):
        for f in files:
            if f.endswith((".css", ".js")) and "material-color-utils" not in f:
                found |= set(re.findall(r"var\(--md-sys-color-([a-z0-9-]+)", open(os.path.join(d, f), errors="ignore").read()))
    check("covers every role the installed Material reads", found <= set(vals), sorted(found - set(vals)))
check("covers the roles Material is known to read", USED <= set(vals), sorted(USED - set(vals)))
check("every value is an rgb()", all(re.fullmatch(r"rgb\(\d+, \d+, \d+\)", v) for v in vals.values()))
check("every channel is 0-255", all(max(rgbof(v)) <= 255 for v in vals.values()))
check("theme source is Matugen", '--theme-color: "Matugen";' in text)

# the shell's own accents, legible on the surfaces they are drawn on
bg = sc.rgb("#1c1f2d")
for name, cases in (("dark", DARK),
                    ("near-black", palette(bg="#020406")),
                    ("light", palette(bg="#f4f1ea", color1="#f0c0c0", color4="#c0c0f0", color5="#e0d0a0")),
                    ("mid-grey", palette(bg="#808080"))):
    t = sc.render(cases)
    v = {k: rgbof(x) for k, x in values(t).items()}
    b = sc.rgb(cases["special"]["background"])
    if name == "mid-grey":      # the palette's own text is under 4.5:1 here, so nothing can be legible: only must not crash
        continue
    for role in ("primary", "secondary", "tertiary"):
        check("%s: %s is legible on the background" % (name, role), sc.contrast(v[role], b) >= 4.4, (v[role], b))
        check("%s: on-%s-container is legible on its container" % (name, role),
              sc.contrast(v["on-%s-container" % role], v["%s-container" % role]) >= 4.4)
    check("%s: text is legible on the surface" % name, sc.contrast(v["on-surface"], v["surface"]) >= 4.4)
    check("%s: text is legible on the highest container" % name,
          sc.contrast(v["on-surface"], v["surface-container-highest"]) >= 4.4)
    check("%s: on-primary is legible on primary" % name, sc.contrast(v["on-primary"], v["primary"]) >= 3.0,
          (v["on-primary"], v["primary"]))
    check("%s: error stays red-ish" % name, v["error"][0] > v["error"][2])

# elevation steps away from the background, in the right direction
v = {k: rgbof(x) for k, x in values(text).items()}
L = lambda k: sc.lum(v[k])
check("dark: containers get lighter with elevation",
      L("surface-container-lowest") < L("surface") <= L("surface-container") < L("surface-container-high") < L("surface-container-highest"))
vl = {k: rgbof(x) for k, x in values(sc.render(palette(bg="#f4f1ea"))).items()}
Ll = lambda k: sc.lum(vl[k])
check("light: containers get darker with elevation",
      Ll("surface-container-lowest") > Ll("surface") >= Ll("surface-container") > Ll("surface-container-high") > Ll("surface-container-highest"))

# light / dark switches follow the background
check("dark palette: dark switches", "--scheme-dark: var(--ON);" in text and "--scheme-light: var(--OFF);" in text and "only dark" in text)
tl = sc.render(palette(bg="#f4f1ea"))
check("light palette: light switches", "--scheme-light: var(--ON);" in tl and "--scheme-dark: var(--OFF);" in tl and "only light" in tl)

# --hue-rotate reproduces the theme's own presets at their hues, and stays in 0..359
for name, hue, want in (("red", 15, 145), ("yellow", 50, 220), ("green", 96, 270), ("cyan", 186, 330),
                        ("blue", 217, 0), ("purple", 265, 60)):
    c = [x * 255 for x in colorsys.hsv_to_rgb(hue / 360, 0.5, 0.8)]
    check("hue-rotate %s" % name, sc.hue_rotate(c) == want, sc.hue_rotate(c))
check("hue-rotate always in 0..359", all(0 <= sc.hue_rotate([x * 255 for x in colorsys.hsv_to_rgb(h / 360, .6, .8)]) < 360 for h in range(0, 360, 5)))
check("a grey palette doesn't crash", "--hue-rotate:" in sc.render(palette(bg="#101010", color1="#808080", color4="#909090", color5="#a0a0a0")))

# a palette that isn't usable is refused
for name, bad in (("empty", {}), ("no colors", {"special": {"background": "#000000"}}),
                  ("named colour", palette(color1="red")), ("short hex", dict(palette(), special={"background": "#fff"})),
                  ("not a dict", None)):
    try:
        sc.render(bad)
        check("refuses " + name, False)
    except ValueError:
        check("refuses " + name, True)

# the shell's own legible() agrees with this file's copy where it matters
a = sc.shell_legible()([100, 80, 90], bg, 4.5, sc.rgb("#e9eaf4"))
b = sc.legible([100, 80, 90], bg, 4.5, sc.rgb("#e9eaf4"))
check("pwspice's legible() and the fallback agree", all(abs(x - y) <= 3 for x, y in zip(a, b)), (a, b))

# write_if_changed + main(): atomic, idempotent, no stray temp files, never a half-written palette
with tempfile.TemporaryDirectory() as td:
    p = os.path.join(td, "matugen.css")
    check("first write reports a change", sc.write_if_changed(p, text) is True)
    mtime = os.stat(p).st_mtime_ns
    check("same content reports no change", sc.write_if_changed(p, text) is False)
    check("same content leaves the file alone", os.stat(p).st_mtime_ns == mtime)
    check("no temp files left", os.listdir(td) == ["matugen.css"], os.listdir(td))
    check("readable by Steam", oct(os.stat(p).st_mode & 0o777) == "0o644")

    wal = os.path.join(td, "colors.json")
    json.dump(DARK, open(wal, "w"))
    th = os.path.join(td, "Material-Theme")
    os.mkdir(th)
    check("preview exits 0", sc.main([wal, "--preview", "--theme-dir", th]) == 0 and os.listdir(th) == [])
    check("write exits 0", sc.main([wal, "--theme-dir", th]) == 0)
    target = os.path.join(th, sc.RELATIVE)
    check("written where Material reads it", os.path.isfile(target) and values(open(target).read()) == values(sc.render(DARK, sc.shell_legible())))
    os.environ["XDG_DATA_HOME"] = os.path.join(td, "none")
    os.environ["HOME"] = os.path.join(td, "nohome")
    check("not installed is exit 3", sc.main([wal]) == 3)
    open(wal, "w").write("{not json")
    check("bad palette is exit 2", sc.main([wal, "--theme-dir", th]) == 2)
    check("bad palette keeps the old file", values(open(target).read()) == values(sc.render(DARK, sc.shell_legible())))

print("%d passed, %d failed" % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
