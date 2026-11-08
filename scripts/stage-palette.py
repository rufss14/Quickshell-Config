#!/usr/bin/env python3
"""stage-palette.py — build a theming run's whole palette in ONE process.

    stage-palette.py --out DIR [--from colors.json] [--image SRC [--light] [--blackpoint]]
                     [--saved palette.json] [--overrides overrides.json] [--held-exit]

Writes DIR/colors.json and every pywal template (DIR/colors.sh, colors-kitty.conf, …,
the user's own templates included), ready for wave-lib.sh's commit_stage to swap in.

── Why one process ────────────────────────────────────────────────────────────
This used to be five: a Python check of the overrides file, `wal -i` (which exports
every template), a Python merge of the held colours, and `wal --theme` (which exports
every template AGAIN, only because the merge had made the first export stale) — plus
Python one-liners for the corrections. Each paid Python's start and pywal's 45ms
import, and the templates were rendered twice: ~310ms on a cached palette before the
shell could even start the wave. Here pywal is imported once and exports once, after
the merge: ~90ms. Measured on this machine, 2026-10-01.

── The palette is exactly `wal -i`'s ────────────────────────────────────────────
The image path runs the very calls `wal -i <src> -n -s -t -e [-l]` makes, with the
very arguments its parser gives them (backend None, sat None, c16 False, cst None):
those go into pywal's cache key, so a palette extracted before — by wal, or by
scripts/palette-prefetch.py — is found, and a new one is cached where wal looks. The
export reads the final document back through theme.file, exactly as `wal --theme`
did, so every template comes out byte-for-byte as before.

PYWAL_CACHE_DIR must be the run's stage (its schemes/ a symlink to the live cache):
pywal reads it at import, and it is where cache lookups go.

── Protocol ───────────────────────────────────────────────────────────────────
STEP=<id>|<status>|<text> lines on stdout, as apply-wallpaper.sh's own; the log on
stderr. Exit 0: staged. 10: --held-exit and the overrides hold every slot (nothing
to extract — the caller only changes the picture). 1: no palette.
"""
import argparse
import importlib.util
import json
import math
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
NEED = {"background", "foreground"} | {"color%d" % i for i in range(16)}


def step(sid, status, text):
    print("STEP=%s|%s|%s" % (sid, status, text), flush=True)


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def _script(name):
    """A sibling script's functions (merge-overrides.py, wal-from-json.py) — one copy
    of each rule, whether run from the shell or from here."""
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), os.path.join(HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def _load(path):
    try:
        with open(path) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except Exception:
        return {}


def fully_held(overrides):
    if not overrides:
        return False
    d = _load(overrides)
    have = set(d.get("special") or {}) | set(d.get("colors") or {})
    return NEED <= have


# ── Corrections, unchanged from apply-wallpaper.sh's inline copies ────────────────
def blackpoint(d):
    # The Arch logo extracts to a near-black pywal lifts to a washed-out grey.
    d["special"]["background"] = "#000000"
    d["colors"]["color0"] = "#000000"
    d["colors"]["color8"] = "#444444"


def lightfix(d):
    """Make pywal's -l palette a light theme worth wearing.

    pywal's -l does two things: it lightens the background 95% of the way to white,
    and it MEANS to darken the accents, but its loop never assigns the result — so the
    accents arrive exactly as the dark extraction's. The page is a flat, near-white
    grey (#f2f2f3 on a violet wallpaper) and nothing on it says which wallpaper it is.

    This used to fix that in HLS: accents clamped to lightness <= 0.45 and saturation
    >= 0.35, the background only ever raised. That darkened every accent whether it
    needed it or not (a lavender #9863EC came out a deep #5e19cd), invented colour for
    near-greys (HLS saturation is meaningless near the ends of the scale — the
    phantom-chroma bug album-colors.py documents), and left the page near-white.

    Now, in CIELAB (album-colors.py's helpers, one copy of the colour maths):
      · the page is a soft PAPER tinted with the accents' own mean hue, at L* 91 —
        off-white you can see, not white; a grey wallpaper gives a grey page;
      · the ink (foreground, color7, color15) is the same hue, dark;
      · an accent is left EXACTLY as extracted when it already reads on that page
        (3:1, the UI-component bar; services/palette.js's legible() lifts the roles
        that carry text further, at runtime), and otherwise only its lightness drops,
        hue and chroma kept — the least change that makes it read.
    """
    ac = _script("album-colors")

    def rgbt(h):
        h = h.lstrip("#")
        return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

    def hexs(t):
        return ac.hexs(t).lower()

    c, sp = d["colors"], d["special"]
    slots = ["color%d" % i for i in list(range(1, 7)) + list(range(9, 15)) if "color%d" % i in c]
    labs = [ac.to_lab(rgbt(c[k])) for k in slots]

    # The tint: the accents' mean a/b vector — its direction is the dominant hue, and
    # its length is small when the accents disagree or are grey, so the tint fades
    # with them instead of picking an arbitrary hue.
    ma = sum(l[1] for l in labs) / max(1, len(labs))
    mb = sum(l[2] for l in labs) / max(1, len(labs))
    mc = math.hypot(ma, mb)
    ux, uy = (ma / mc, mb / mc) if mc > 1e-6 else (0.0, 0.0)

    def tone(L, chroma):
        k = min(chroma, mc)
        return hexs(ac.with_lightness((L, ux * k, uy * k), L))

    bg = tone(91.0, 6.0)
    ink = tone(20.0, 7.0)
    sp["background"] = c["color0"] = bg
    sp["foreground"] = c["color7"] = ink
    c["color15"] = tone(30.0, 7.0)
    c["color8"] = tone(56.0, 8.0)

    bg_rgb = rgbt(bg)
    for k, lab in zip(slots, labs):
        if ac.contrast(rgbt(c[k]), bg_rgb) >= 3.0:
            continue
        lo, hi = 0.0, lab[0]          # bisect L* down: the lightest that reads
        for _ in range(14):
            mid = (lo + hi) / 2
            if ac.contrast(ac.with_lightness(lab, mid), bg_rgb) >= 3.0:
                lo = mid
            else:
                hi = mid
        c[k] = hexs(ac.with_lightness(lab, lo))


def write_json(path, doc):
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump(doc, f, indent=4)
    os.replace(tmp, path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--from", dest="base", default="")
    ap.add_argument("--image", default="")
    ap.add_argument("--light", action="store_true")
    ap.add_argument("--blackpoint", action="store_true")
    ap.add_argument("--saved", default="")
    ap.add_argument("--overrides", default="")
    ap.add_argument("--held-exit", action="store_true")
    a = ap.parse_args()

    if a.held_exit and fully_held(a.overrides):
        return 10

    os.makedirs(a.out, exist_ok=True)
    doc = None
    extracted = False

    # 1c. A palette saved for this wallpaper replaces extraction (and its corrections).
    if a.saved:
        saved = _load(a.saved)
        if saved.get("colors"):
            step("palette", "run", "Restoring this wallpaper's saved palette")
            doc = _script("wal-from-json").build(saved, _load(a.base) if a.base else {})
            step("palette", "ok", "Restoring this wallpaper's saved palette")
        else:
            log("saved palette %s has no colours — extracting instead" % a.saved)

    # Imported only now: a scheme run or a saved palette with no export to do would
    # still need it below, but the held exit above must stay cheap.
    try:
        from pywal import colors as pw_colors, export, image, sequences, theme
    except Exception as e:
        step("palette", "fail", "pywal not installed")
        log("pywal import failed:", e)
        return 1

    # 2. Extract — `wal -i <src> -n -s -t -e [-l]`, the same calls and arguments.
    if doc is None and a.image:
        text = "Extracting colours (light)" if a.light else "Extracting colours"
        step("palette", "run", text)
        try:
            img = image.get(a.image, cache_dir=a.out)
            doc = pw_colors.get(img, a.light, None, sat=None, c16=False, cst=None)
            extracted = True
        except BaseException as e:      # pywal sys.exit()s on a bad image
            step("palette", "fail", text)
            log("extraction failed:", repr(e))
            return 1
        step("palette", "ok", text)

    if doc is None:
        doc = _load(a.base)
        if not doc.get("colors"):
            step("palette", "fail", "No palette to start from")
            return 1
    # pywal hands back its own dict; corrections and the merge edit plain JSON.
    doc = json.loads(json.dumps(doc))

    # 3. Per-wallpaper corrections — after a FRESH extraction only, as before.
    if extracted and a.blackpoint and not a.light:
        blackpoint(doc)
        step("patch", "ok", "Correcting black point")
    if extracted and a.light:
        lightfix(doc)
        step("lightfix", "ok", "Repairing light-mode contrast")

    # 4. Your held colours, last — after everything else that writes the palette.
    if a.overrides and os.path.isfile(a.overrides):
        doc, skipped = _script("merge-overrides").merge(doc, _load(a.overrides))
        if skipped:
            log("merge-overrides: skipped (not a slot / not #rrggbb):", ", ".join(skipped))
        step("overrides", "ok", "Applying your colour edits")
    else:
        step("overrides", "skip", "no overrides file")

    # 5. Every template, once, from the final document — `wal --theme`'s calls.
    step("render", "run", "Rendering colour files")
    path = os.path.join(a.out, "colors.json")
    write_json(path, doc)
    final = theme.file(path, False, c16=False)
    sequences.send(final, cache_dir=a.out, to_send=False)
    export.every(final, a.out)
    step("render", "ok", "Rendering colour files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
