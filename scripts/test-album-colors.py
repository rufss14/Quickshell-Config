#!/usr/bin/env python3
# ── test-album-colors.py ──────────────────────────────────────────────────────
# Tests for album-colors.py. Fully mocked and SAFE TO RUN: every case draws its own
# cover with Pillow into a temp dir and throws it away, so this never touches the
# network and never reads a real album cover. Same contract as
# test-discord-rpc.py (safe) rather than test-discord-press.py (touches the
# live app).
#
#   python3 scripts/test-album-colors.py
#
# ── What is actually worth testing here ──────────────────────────────────────
# Not "is the palette pretty" — that is a judgement call and a screenshot. What can
# be checked is every property the shell RELIES ON and would fail silently without:
#
#   · the three-colour mode still emits exactly the keys AlbumArt.qml parses, because
#     --scheme was added underneath it and that contract must not have moved;
#   · all eighteen slots exist and are real hex, because a missing color11 is not a
#     crash — it is one widget quietly falling through to its Tokyo Night fallback;
#   · foreground actually contrasts with background, on covers chosen to make that
#     hard (pure white, pure black, and a mid-grey that is far from both);
#   · color1 and color4 are DIFFERENT HUES. The shell requires primary and focus to be
#     distinguishable (see config/Colors.qml) and a monochrome cover is exactly the
#     input that collapses them;
#   · the same cover gives the same palette twice, because a scheme that drifts per
#     call would re-theme the desktop on every track change of the same album.
# ─────────────────────────────────────────────────────────────────────────────
import colorsys
import math
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "album-colors.py")

spec = importlib.util.spec_from_file_location("ac", SCRIPT)
ac = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ac)

try:
    from PIL import Image, ImageDraw
except ImportError:
    print("Pillow is not installed — album-colors.py needs it too. Skipping.")
    sys.exit(0)

# album-colors.py imports Pillow inside __main__ so a missing Pillow is a clean
# {"ok": false} rather than a traceback. Loading it as a module therefore leaves
# `Image` unbound, and every extraction would fail for the wrong reason.
ac.Image = Image

PASS = 0
FAIL = 0


def ok(name, cond):
    global PASS, FAIL
    if cond:
        PASS += 1
    else:
        FAIL += 1
        print(f"  FAIL  {name}")


def check(name, got, want):
    global PASS, FAIL
    if got == want:
        PASS += 1
    else:
        FAIL += 1
        print(f"  FAIL  {name}")
        print(f"        want: {want!r}")
        print(f"        got:  {got!r}")


# ── Covers ───────────────────────────────────────────────────────────────────
# Drawn rather than shipped: a real cover is someone else's artwork and has no
# business in a published repo, and a synthetic one can be made to hit the exact
# edge the test is about.
TMP = tempfile.mkdtemp(prefix="album-colors-test-")


def cover(name, bands, size=300):
    """A cover of horizontal bands. `bands` is a list of (r, g, b)."""
    path = os.path.join(TMP, name + ".png")
    im = Image.new("RGB", (size, size), bands[0])
    d = ImageDraw.Draw(im)
    h = size / len(bands)
    for i, c in enumerate(bands):
        d.rectangle((0, i * h, size, (i + 1) * h), fill=c)
    im.save(path)
    return path


COVERS = {
    # Four unmistakable hues plus a dark ground — the easy case, and the one where
    # the ANSI ordering should visibly land red in color1 and blue in color4.
    "quad":  cover("quad", [(20, 16, 30), (220, 50, 60), (40, 180, 90),
                            (60, 90, 230), (240, 200, 50)]),
    # One hue in several values. The case that used to come out as a rainbow.
    "blue":  cover("blue", [(8, 14, 40), (20, 40, 110), (40, 80, 180),
                            (90, 140, 220), (150, 190, 240)]),
    "duo":   cover("duo", [(14, 12, 18), (200, 40, 55), (30, 70, 200),
                           (14, 12, 18), (200, 40, 55)]),
    # ── One flat colour, and nothing else ────────────────────────────────────
    # The ONLY cover here that forces derive_variants() to work from a CHROMATIC
    # source, and therefore the only one that tests the invention guarantee where it
    # can actually be violated. Everything else either finds six real swatches (even
    # `duo` does — anti-aliased band edges quantise into extra colours) or is neutral,
    # where rotating a hue that does not exist is a no-op.
    #
    # Verified by mutation: a 35° hue rotation injected into the variant path passed
    # the entire suite until this cover existed.
    "solid": cover("solid", [(150, 35, 70)]),
    # No hue at all. Collapses primary and focus if nothing guards it.
    "grey":  cover("grey", [(18, 18, 18), (60, 60, 60), (110, 110, 110),
                            (170, 170, 170), (230, 230, 230)]),
    # Contrast torture: a cover that is nearly all one extreme.
    "white": cover("white", [(252, 252, 250), (248, 246, 244), (255, 255, 255)]),
    "black": cover("black", [(2, 2, 3), (6, 5, 8), (0, 0, 0)]),
    # A mid grey is the worst ground of all: neither raising nor lowering the text
    # helps much, so the contrast walk has to actually run to its limit.
    "mid":   cover("mid", [(128, 126, 130), (135, 130, 128), (120, 124, 132)]),
}

SLOTS = ["color%d" % i for i in range(16)]


def hex_ok(v):
    return (isinstance(v, str) and len(v) == 7 and v[0] == "#"
            and all(c in "0123456789ABCDEFabcdef" for c in v[1:]))


def rgb_of(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hls_of(h):
    r, g, b = (c / 255 for c in rgb_of(h))
    return colorsys.rgb_to_hls(r, g, b)


def hue_of(h):
    return hls_of(h)[0]


def lum_of(h):
    return ac.relative_luminance(rgb_of(h))


def hue_angle(lab):
    """Hue as an angle in Lab's a/b plane, in degrees."""
    return math.degrees(math.atan2(lab[2], lab[1])) % 360.0


def angle_gap(a, b):
    d = abs(a - b) % 360.0
    return min(d, 360.0 - d)


# ── The three-colour contract has not moved ──────────────────────────────────
def test_card_mode():
    print("three-colour mode")
    for name, path in COVERS.items():
        d = ac.extract(path)
        check(f"{name} ok", d["ok"], True)
        # AlbumArt.qml reads exactly these. Adding --scheme must not have widened,
        # narrowed or renamed them.
        check(f"{name} keys", sorted(d.keys()),
              ["accent", "bg", "contrast", "fg", "ok", "sat"])
        ok(f"{name} colours are hex", all(hex_ok(d[k]) for k in ("bg", "accent", "fg")))
        ok(f"{name} fg is legible on bg",
           ac.contrast(rgb_of(d["fg"]), rgb_of(d["bg"])) >= 4.4)

    # The grey-cover signal AlbumArt.qml's brand fallback keys on. If this stops
    # being near zero, a monochrome cover silently stops getting Spotify green.
    ok("grey cover reports low saturation", ac.extract(COVERS["grey"])["sat"] < 0.15)
    ok("quad cover reports high saturation", ac.extract(COVERS["quad"])["sat"] > 0.5)


# ── The scheme is shaped like a pywal palette ────────────────────────────────
def test_scheme_shape():
    print("scheme shape")
    for name, path in COVERS.items():
        d = ac.scheme(path)
        check(f"{name} ok", d["ok"], True)
        check(f"{name} has all 16 ramp slots", sorted(d["colors"].keys()),
              sorted(SLOTS))
        ok(f"{name} ramp is hex", all(hex_ok(v) for v in d["colors"].values()))
        check(f"{name} special keys", sorted(d["special"].keys()),
              ["background", "cursor", "foreground"])
        ok(f"{name} special is hex", all(hex_ok(v) for v in d["special"].values()))
        # reload-theme.sh re-exports templates by handing colors.json back to
        # `wal --theme`, which wants the file whole.
        ok(f"{name} carries wallpaper and alpha",
           d["wallpaper"] == path and d["alpha"] == "100")


# ── Legibility, on the covers built to break it ──────────────────────────────
def test_contrast():
    print("contrast")
    for name, path in COVERS.items():
        for light in (False, True):
            d = ac.scheme(path, light)
            bg, fg = d["special"]["background"], d["special"]["foreground"]
            tag = f"{name} {'light' if light else 'dark'}"
            ok(f"{tag} fg clears body-text contrast",
               ac.contrast(rgb_of(fg), rgb_of(bg)) >= 7.0)
            # color7 is the terminal's normal text and the shell's muted foreground.
            # It is allowed to be softer than color15, but not invisible.
            ok(f"{tag} color7 stays readable",
               ac.contrast(rgb_of(d["colors"]["color7"]), rgb_of(bg)) >= 4.0)

            # ── The ground and the text must stay near-neutral ───────────────
            # A background carrying real chroma reads as a coloured film over every
            # window — the same failure apply-wallpaper.sh keeps a light-mode repair
            # step for. These are the slots that dress whole surfaces, so they take
            # only as much of the cover's hue as `tint_c` allows.
            for slot, limit in (("background", 14.0), ("foreground", 12.0)):
                c = ac.chroma_of(ac.to_lab(rgb_of(d["special"][slot])))
                ok(f"{tag} {slot} stays near-neutral (chroma {c:.1f})", c <= limit)
            for slot in ("color0", "color7", "color8", "color15"):
                c = ac.chroma_of(ac.to_lab(rgb_of(d["colors"][slot])))
                ok(f"{tag} {slot} stays near-neutral (chroma {c:.1f})", c <= 14.0)


def test_mode():
    print("light vs dark")
    for name, path in COVERS.items():
        dark = ac.scheme(path, False)
        light = ac.scheme(path, True)
        ok(f"{name} dark ground is dark",
           lum_of(dark["special"]["background"]) < 0.09)
        ok(f"{name} light ground is light",
           lum_of(light["special"]["background"]) > 0.70)
        # A white cover in dark mode is the case that tempts an implementation into
        # simply passing the lightest swatch through.
        ok(f"{name} dark fg is lighter than dark bg",
           lum_of(dark["special"]["foreground"]) > lum_of(dark["special"]["background"]))
        ok(f"{name} light fg is darker than light bg",
           lum_of(light["special"]["foreground"]) < lum_of(light["special"]["background"]))


# ── Every accent must be tellable from every other ───────────────────────────
def test_accent_separation():
    print("accent separation")
    for name, path in COVERS.items():
        for light in (False, True):
            d = ac.scheme(path, light)
            tag = f"{name} {'light' if light else 'dark'}"
            labs = [ac.to_lab(rgb_of(d["colors"]["color%d" % i])) for i in range(1, 7)]
            worst = min(ac.delta_e(labs[i], labs[j])
                        for i in range(6) for j in range(i + 1, 6))
            # Measured in Lab, not hue. Hue is undefined for a grey, which is why the
            # hue-gap version threw every neutral out of the ramp and then had to
            # invent colours to refill it.
            ok(f"{tag} six accents are all distinguishable", worst >= ac.DELTAS[-1] - 1e-6)

            # The pair config/Colors.qml maps to primary and focus. Indistinguishable
            # here means a hovered button and an active one look identical.
            ok(f"{tag} primary and focus differ",
               ac.delta_e(ac.to_lab(rgb_of(d["colors"]["color1"])),
                          ac.to_lab(rgb_of(d["colors"]["color4"]))) >= ac.DELTAS[-1] - 1e-6)

        # Bright half must track its own dim half, or bold terminal text changes colour
        # rather than merely brightening. Measured as a Lab hue ANGLE: a tight HLS
        # tolerance fails here for a reason that is not a bug — lightening a saturated
        # colour runs into the edge of the sRGB gamut, and with_lightness() backs the
        # chroma off to stay inside it, which moves HLS hue slightly while leaving the
        # perceived hue alone. Measured drift across the test covers is under 2°.
        d = ac.scheme(path)
        for i in range(1, 7):
            dim, bright = d["colors"]["color%d" % i], d["colors"]["color%d" % (i + 8)]
            dl, bl = ac.to_lab(rgb_of(dim)), ac.to_lab(rgb_of(bright))
            if ac.chroma_of(dl) >= 8.0:
                ok(f"{name} color{i + 8} matches color{i}'s hue",
                   angle_gap(hue_angle(dl), hue_angle(bl)) < 8.0)
                # Nor may it gain colour on the way — that is the phantom-chroma bug
                # in the one place it would be least visible.
                ok(f"{name} color{i + 8} gains no chroma over color{i}",
                   ac.chroma_of(bl) <= ac.chroma_of(dl) + 2.0)
            ok(f"{name} color{i + 8} is brighter than color{i}",
               lum_of(bright) > lum_of(dim))


# ── Nothing in the palette may be a colour the cover does not contain ────────
# The rule the whole --scheme mode exists to obey, and the one three separate earlier
# implementations broke. Asserted directly rather than via a proxy: every chromatic
# slot's hue must match a hue that is actually present in the artwork.
def test_no_invented_colour():
    print("no invented colour")
    # ── Everything here is measured in Lab, deliberately ─────────────────────
    # An earlier version of THIS TEST asked the question in HLS and got nonsense
    # answers, for the same reason the code did: HLS saturation is huge for a
    # near-white or near-black pixel that has no perceptible colour in it. It called a
    # flat grey cover "chromatic", then demanded its output be neutral by a threshold
    # measured at a different lightness. Chroma is an absolute distance from grey and
    # behaves at both ends of the scale.
    CHROMATIC = 8.0        # below this a colour reads as a neutral
    IN_COVER = 5.0         # a cover swatch needs at least this to define a hue
    TOLERANCE = 8.0        # degrees of Lab hue

    for name, path in COVERS.items():
        sw = ac.swatches(path, n=16, size=128)
        cover_hues = [hue_angle(s["lab"]) for s in sw
                      if ac.chroma_of(s["lab"]) >= IN_COVER]
        for light in (False, True):
            d = ac.scheme(path, light)
            tag = f"{name} {'light' if light else 'dark'}"
            worst, worst_slot = 0.0, None
            for i in list(range(1, 7)) + list(range(9, 15)):
                lab = ac.to_lab(rgb_of(d["colors"]["color%d" % i]))
                if ac.chroma_of(lab) < CHROMATIC:
                    continue                 # a neutral has no hue to have invented
                if not cover_hues:
                    # A colourless sleeve must not produce a chromatic accent at all.
                    ok(f"{tag} color{i} stays neutral on a colourless cover", False)
                    continue
                gap = min(angle_gap(hue_angle(lab), ch) for ch in cover_hues)
                if gap > worst:
                    worst, worst_slot = gap, i
            ok(f"{tag} every hue comes from the cover (worst {worst:.1f}°"
               + (f" at color{worst_slot}" if worst_slot else "") + ")",
               worst <= TOLERANCE)

    # The specific regressions, named. A wholly blue cover came back as a
    # red/green/yellow rainbow when absent slots were filled at their canonical hue.
    blue = ac.scheme(COVERS["blue"])["colors"]
    blue_hue = hue_angle(ac.to_lab(rgb_of("#3C5AE6")))
    bluish = sum(1 for i in range(1, 7)
                 if angle_gap(hue_angle(ac.to_lab(rgb_of(blue["color%d" % i]))),
                              blue_hue) < 40)
    ok(f"a blue cover stays blue ({bluish}/6 accents near blue)", bluish >= 5)

    # A colourless sleeve must come back colourless. Two separate regressions land
    # here: the saturation FLOOR that forced every accent to s >= 0.48, and the
    # phantom chroma that HLS reports for near-white and near-black pixels — which
    # turned a white cover into tan and olive and a black one into violet.
    for name in ("grey", "white", "black", "mid"):
        for light in (False, True):
            d = ac.scheme(COVERS[name], light)
            worst = max(ac.chroma_of(ac.to_lab(rgb_of(d["colors"]["color%d" % i])))
                        for i in list(range(1, 7)) + list(range(9, 15)))
            ok(f"{name} {'light' if light else 'dark'} stays neutral "
               f"(max chroma {worst:.1f})", worst < CHROMATIC)


# ── An accent nobody can see is not faithful ─────────────────────────────────
def test_accent_legibility():
    print("accent legibility")
    for name, path in COVERS.items():
        for light in (False, True):
            d = ac.scheme(path, light)
            bg = rgb_of(d["special"]["background"])
            tag = f"{name} {'light' if light else 'dark'}"
            worst = min(ac.contrast(rgb_of(d["colors"]["color%d" % i]), bg)
                        for i in range(1, 7))
            # color1 is the shell's `primary` — the fill under every button. A derived
            # variant once landed there at near-black navy on a near-black ground.
            ok(f"{tag} every accent clears 3:1 against the ground "
               f"(worst {worst:.2f})", worst >= 2.99)


# ── The album should still be recognisable in the result ─────────────────────
def test_fidelity():
    print("fidelity")
    quad = ac.scheme(COVERS["quad"])["colors"]
    # A cover with an obvious red and an obvious blue should put them where a
    # terminal expects them. This is the ordering pass, and it is the only part of
    # the ANSI mapping that is ever asserted — the rest is the cover's business.
    ok("quad red lands in color1", ac.hue_gap(hue_of(quad["color1"]), 0.0) < 0.05)
    ok("quad blue lands in color4", ac.hue_gap(hue_of(quad["color4"]), 0.611) < 0.08)


# ── Same cover, same palette ─────────────────────────────────────────────────
def test_stable():
    print("stability")
    for name, path in COVERS.items():
        a = ac.scheme(path)
        b = ac.scheme(path)
        ok(f"{name} is deterministic", a == b)
        # Re-theming the whole desktop is expensive and visible. Two tracks off the
        # same record hand us the same cover url, and the service dedupes on the
        # palette — so an unstable extraction would repaint on every track change.
        ok(f"{name} dark and light differ", ac.scheme(path, True) != a)


# ── Failure is JSON, not a traceback ─────────────────────────────────────────
def test_failure_paths():
    print("failure paths")
    missing = os.path.join(TMP, "does-not-exist.png")
    for args in (["--scheme", missing], [missing],
                 ["--scheme", "--light", missing]):
        r = subprocess.run([sys.executable, SCRIPT] + args,
                           capture_output=True, text=True)
        check(f"{' '.join(args[:-1]) or 'plain'} exits 0", r.returncode, 0)
        try:
            d = json.loads(r.stdout)
        except Exception:
            ok(f"{args} prints JSON", False)
            continue
        check(f"{args[0]} reports not-ok", d["ok"], False)
        ok(f"{args[0]} says why", bool(d.get("error")))

    # No argument at all — the shell should never do this, but a hand-run must not
    # traceback either.
    r = subprocess.run([sys.executable, SCRIPT], capture_output=True, text=True)
    check("no argument exits 0", r.returncode, 0)
    check("no argument reports not-ok", json.loads(r.stdout)["ok"], False)


# ── The CLI is what QML actually calls ───────────────────────────────────────
def test_cli():
    print("cli")
    path = COVERS["quad"]
    plain = json.loads(subprocess.run(
        [sys.executable, SCRIPT, path], capture_output=True, text=True).stdout)
    ok("plain cli matches extract()", plain == ac.extract(path))

    for argv in ([SCRIPT, "--scheme", path], [SCRIPT, path, "--scheme"]):
        d = json.loads(subprocess.run([sys.executable] + argv,
                                      capture_output=True, text=True).stdout)
        ok(f"--scheme works at position {argv.index('--scheme')}",
           d == ac.scheme(path))

    d = json.loads(subprocess.run(
        [sys.executable, SCRIPT, "--scheme", "--light", path],
        capture_output=True, text=True).stdout)
    ok("--light reaches the scheme", d == ac.scheme(path, True))

    # file:// is what MPRIS hands us for a locally-stored cover.
    d = json.loads(subprocess.run(
        [sys.executable, SCRIPT, "--scheme", "file://" + path],
        capture_output=True, text=True).stdout)
    ok("file:// url is accepted", d["ok"] is True)


def main():
    test_card_mode()
    test_scheme_shape()
    test_contrast()
    test_mode()
    test_accent_separation()
    test_no_invented_colour()
    test_accent_legibility()
    test_fidelity()
    test_stable()
    test_failure_paths()
    test_cli()
    print(f"\n{PASS} passed, {FAIL} failed")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
