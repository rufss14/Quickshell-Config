#!/usr/bin/env python3
# ── steam-colors.py ──────────────────────────────────────────────────────────
# Recolours Millennium's simply-dark theme from the live pywal palette, by writing
# the theme's colour inputs into Millennium's config.json (Settings → Themes → "Edit
# colors" is the same store: `themes.themeColors.<theme>` is injected as a :root block
# and cascades over the theme's own colors.css).
#
#   steam-colors.py CONFIG COLORS_JSON [--theme-dir DIR] [--preview]
#
# Why a ramp, not the pywal names: the stock theme does not read `--color0…15`. Its inputs
# are ~20 greys and two status colours (`--color-dark`, `--grey`, `--white`, `--online`…),
# so baking the pywal names (what this step used to do) recoloured nothing. Each of the
# theme's own variables is mapped by how light it is: its stock grey picks a point on the
# line from the palette's background to its foreground, anchored so the theme's MAIN
# BACKGROUND is exactly the palette background (see ramp()). Lighter steps keep their layering
# above it, whites reach the foreground, so the theme keeps the contrast it was designed with,
# in the palette's hue. `--ingame` / `--online` keep a hue (palette green / cyan) so a friend's
# status still reads on a muted palette.
#
# The stock values are read from the theme's colors.css, NOT from config.json: after the
# first run config.json holds OUR output, and ramping that again would drift the palette a
# little further toward the middle on every wallpaper change.
#
# The pywal names are still written alongside, for a theme (an older local copy whose
# colors.css is a symlink to the wal cache) that does read them.
# ─────────────────────────────────────────────────────────────────────────────
import argparse
import importlib.util
import json
import os
import re
import sys
import tempfile

THEME = "simply-dark"

# simply-dark's colors.css as shipped — the fallback when the theme folder can't be found.
STOCK = {
    "--color-light": "rgb(48, 48, 48)", "--color-dark": "#212121",
    "--color-darker": "#191919", "--color-darkest": "#141414", "--scrollbar": "#303030",
    "--black": "#000000", "--blacker-ish": "#1b1b1b", "--blacker": "#1c1c1c",
    "--grey": "#2e2e2f", "--lightgrey": "#3e3e3f", "--lightergrey": "#353535",
    "--grey-ish": "#454545", "--darkergrey": "#151515", "--thegrey": "#181818",
    "--begrey": "#262627", "--littlegrey": "#282828", "--darkgrey": "#1e1e1f",
    "--darkerwhite": "#b8b6b4", "--darkwhite": "#d9dadd", "--white": "#ffffff",
    "--ingame": "#90ba3c", "--online": "#57cbde", "--offline": "#898989",
}

# Status colours keep a hue: name → pywal colour index (green, cyan).
HUES = {"--ingame": 2, "--online": 6}

_HEX = re.compile(r"^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$")
_RGB = re.compile(r"^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)")
_DECL = re.compile(r"^\s*(--[A-Za-z0-9-]+)\s*:\s*([^;]+);", re.M)


def parse_color(text):
    """'#rgb' / '#rrggbb' / 'rgb(r,g,b)' → (r, g, b), else None."""
    text = text.strip()
    m = _HEX.match(text)
    if m:
        h = m.group(1)
        if len(h) == 3:
            h = "".join(c * 2 for c in h)
        return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
    m = _RGB.match(text)
    if m:
        return tuple(min(255, int(g)) for g in m.groups())
    return None


def to_hex(rgb):
    return "#%02x%02x%02x" % tuple(round(c) for c in rgb)


def lightness(rgb):
    return sum(rgb) / 765


def ramp(l, base=0.0):
    """Where on bg→fg a stock grey of lightness l (0..1) lands (0..1).

    Surfaces (up to ~#666) keep the stock steps — against a foreground about as light as
    white that is the theme's own contrast between layers, which a gentler slope flattens into
    one slab; text-range lights then close the rest of the way, so #fff reaches the
    foreground exactly.

    `base` anchors it: the stock theme lifts its MAIN BACKGROUND a little off pure black
    (#191919), and reproduced proportionally that left Steam's main surface ~16 levels lighter
    than the palette background every other app puts under theirs (measured: 79% of what Steam
    paints was that one colour). With `base` = the raw ramp at the main background's stock grey,
    that grey lands exactly on the palette background, everything lighter keeps its step above
    it, and anything darker (the theme's few inset shades) is clamped to it."""
    t = l * 0.9 if l <= 0.4 else 0.36 + (l - 0.4) / 0.6 * 0.64
    return max(0.0, (t - base) / (1.0 - base))


# The theme's own doc comment on this variable (colors.css): "Darker Color — Main Background".
MAIN_BG = "--color-darker"


def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def read_palette(path):
    """(bg, fg, [color0..15]) as RGB tuples, or raise ValueError."""
    with open(path, encoding="utf-8") as f:
        wal = json.load(f)
    try:
        special = wal["special"]
        colors = [parse_color(wal["colors"]["color%d" % i]) for i in range(16)]
        bg, fg = parse_color(special["background"]), parse_color(special["foreground"])
    except (KeyError, TypeError) as e:
        raise ValueError("incomplete palette: %s" % e)
    if bg is None or fg is None or None in colors:
        raise ValueError("palette has a colour that isn't #rrggbb")
    return bg, fg, colors, wal


def theme_stock(theme_dir):
    """The theme's own colour inputs, from its colors.css, over the shipped table."""
    stock = dict(STOCK)
    path = os.path.join(theme_dir, "colors.css") if theme_dir else ""
    try:
        with open(path, encoding="utf-8") as f:
            found = {k: v.strip() for k, v in _DECL.findall(f.read())}
    except OSError:
        return stock
    # Only what is actually a colour (the file also documents itself in comments).
    stock.update({k: v for k, v in found.items() if parse_color(v) is not None})
    return stock


def main_bg_base(stock):
    """The ramp's anchor: where the theme's main background sits, so it can be put on the palette bg."""
    main = parse_color(stock.get(MAIN_BG, ""))
    return ramp(lightness(main)) if main else 0.0


def derive(bg, fg, colors, stock, wal=None):
    """The themeColors block for `stock`'s variables, plus the pywal names."""
    out = {}
    base = main_bg_base(stock)
    for name, value in stock.items():
        if name in HUES:
            out[name] = to_hex(colors[HUES[name]])
            continue
        rgb = parse_color(value)
        if rgb is not None:
            out[name] = to_hex(mix(bg, fg, ramp(lightness(rgb), base)))
    special = (wal or {}).get("special", {})
    out["--background"], out["--foreground"] = to_hex(bg), to_hex(fg)
    out["--cursor"] = special.get("cursor") or to_hex(fg)
    for i, c in enumerate(colors):
        out["--color%d" % i] = to_hex(c)
    return out


def default_theme_dirs():
    data = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return [os.path.join(data, "Steam", "millennium", "themes", THEME),
            os.path.expanduser("~/.steam/steam/millennium/themes/" + THEME)]


def write_atomic(path, text):
    """Rename into place: Millennium reading mid-write must never see half a file."""
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", prefix=".config.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.chmod(tmp, os.stat(path).st_mode & 0o777)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def main(argv=None):
    ap = argparse.ArgumentParser(description="Recolour simply-dark from the pywal palette.")
    ap.add_argument("config")
    ap.add_argument("colors_json")
    ap.add_argument("--theme-dir")
    ap.add_argument("--preview", action="store_true", help="print the colours, write nothing")
    args = ap.parse_args(argv)

    try:
        bg, fg, colors, wal = read_palette(args.colors_json)
    except (OSError, ValueError) as e:
        print("steam-colors: palette unreadable: %s" % e, file=sys.stderr)
        return 2
    theme_dir = args.theme_dir or next((d for d in default_theme_dirs() if os.path.isdir(d)), "")
    block = derive(bg, fg, colors, theme_stock(theme_dir), wal)

    if args.preview:
        for k in sorted(block):
            print("%-16s %s" % (k, block[k]))
        return 0

    try:
        with open(args.config, encoding="utf-8") as f:
            cfg = json.load(f)
    except (OSError, ValueError) as e:
        print("steam-colors: millennium config unreadable: %s" % e, file=sys.stderr)
        return 2
    accent = accent_parts(colors, theme_stock(theme_dir), bg, fg)
    block.update(accent["vars"])
    cfg.setdefault("themes", {}).setdefault("themeColors", {}).setdefault(THEME, {}).update(block)
    write_atomic(args.config, json.dumps(cfg, indent=2, sort_keys=True))
    print("steam-colors: wrote %d colours for %s (%d of them Steam's own, recoloured)"
          % (len(block), THEME, len(accent["vars"])))
    write_accent_quickcss(args.config, accent["css"])
    return 0


def _load_accent():
    spec = importlib.util.spec_from_file_location(
        "steam_accent", os.path.join(os.path.dirname(os.path.abspath(__file__)), "steam-accent.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def accent_parts(colors, stock, bg, fg):
    """Steam's own blues, greens and tinted greys (steam-accent.py), from the rules steam-live.py
    scanned out of a running Steam: {"vars": {--qs-…: colour} for themeColors — the palette's half,
    "css": the static stylesheet or None}. Empty before the first scan, and never fatal: the theme's
    own colours are written either way."""
    try:
        acc = _load_accent()
        cache = acc.load_cache()
        if not cache:
            return {"vars": {}, "css": None}
        return {"vars": acc.variables(cache["rules"], bg, fg, colors[1], main_bg_base(stock)),
                "css": acc.rules_css(cache["rules"])}
    except Exception as e:
        print("steam-colors: Steam's own colours skipped: %s" % e, file=sys.stderr)
        return {"vars": {}, "css": None}


def write_accent_quickcss(config, css):
    """The static stylesheet into Millennium's Quick CSS, which injects it into every window as it
    loads. It doesn't depend on the palette, so on a normal theme run this finds nothing to change."""
    if not css:
        return
    try:
        if _load_accent().write_quickcss(os.path.join(os.path.dirname(config), "quick.css"), css):
            print("steam-colors: updated Quick CSS")
    except OSError as e:
        print("steam-colors: Quick CSS not written: %s" % e, file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main())
