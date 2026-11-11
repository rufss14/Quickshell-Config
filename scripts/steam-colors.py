#!/usr/bin/env python3
# ── steam-colors.py ──────────────────────────────────────────────────────────
# Makes Steam's Material theme (Millennium, kuska1/Material-Theme, MIT) wear the shell's
# palette. The theme has a "Matugen" colour source: it reads a stylesheet of Material 3
# system colours (`--md-sys-color-*`) from css/main/colors/matugen.css and re-reads it
# regularly in every Steam window (js/main/colors/matugen.js). This script writes that one
# file from the pywal palette, with the same blends the shell's PaletteRoles uses, so a
# running Steam repaints by itself within a couple of seconds: no restart, no debug port,
# nothing written to Millennium's config.json.
#
#   steam-colors.py COLORS_JSON [--theme-dir DIR]     write matugen.css (default: the installed theme)
#   steam-colors.py COLORS_JSON --preview             print it, write nothing
#
# Role map (shell → Material 3):
#   primary / secondary    pywal color1 / color4, pulled to 4.5:1 on the background — the shell's
#                          own `primary` / `focus` (scripts/themes/spotify/pwspice.py _legible)
#   tertiary               pywal color5, same floor
#   surface*, containers   the shell's surface / surfaceContainer / surfaceHigh blends of
#                          background, text (color7) and primary
#   on-*, outline          text, and text mixed toward the background
#   error                  Material's own fixed red: the shell's `danger` is color1, which is
#                          usually the accent, so it would read as primary
# The file also sets the light/dark switches (--scheme-*, color-scheme) from the background's
# lightness, so a light wallpaper turns the whole theme light without touching its Appearance
# setting. --hue-rotate (which tints Steam's bitmap art) follows the accent's hue.
# ─────────────────────────────────────────────────────────────────────────────
import argparse
import colorsys
import importlib.util
import json
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
THEME = "Material-Theme"
RELATIVE = os.path.join("css", "main", "colors", "matugen.css")
_HEX = re.compile(r"^#[0-9a-fA-F]{6}$")

# Accent hue (degrees) → the --hue-rotate the theme's own presets use for it (purple.css,
# red.css, yellow.css, green.css, cyan.css, blue.css read off the shipped files); linear between.
HUE_ROTATE = [(15, 145), (50, 220), (96, 270), (186, 330), (217, 360), (265, 420)]


def rgb(h):
    h = h.lstrip("#")
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]


def mix(a, b, t):
    """Opaque blend of `t` of b into a — PaletteRoles.mix()."""
    return [x + (y - x) * t for x, y in zip(a, b)]


def lum(c):
    def lin(v):
        s = v / 255.0
        return s / 12.92 if s <= 0.03928 else ((s + 0.055) / 1.055) ** 2.4
    r, g, b = (lin(v) for v in c)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def legible(color, bg, target, toward):
    """services/palette.js legible(): the least shift toward `toward` that reaches `target`."""
    if contrast(color, bg) >= target:
        return list(color)
    if contrast(toward, bg) < target:
        return list(toward)
    lo, hi = 0.0, 1.0
    for _ in range(12):
        mid = (lo + hi) / 2
        if contrast(mix(color, toward, mid), bg) >= target:
            hi = mid
        else:
            lo = mid
    return mix(color, toward, hi)


def css(c):
    return "rgb(%d, %d, %d)" % tuple(max(0, min(255, round(v))) for v in c)


def hue_rotate(c):
    h = colorsys.rgb_to_hsv(*(v / 255.0 for v in c))[0] * 360.0
    pts = HUE_ROTATE
    if h < pts[0][0]:
        h += 360.0                          # reds below 15° sit between purple (265) and red (15+360)
    if h > pts[-1][0]:
        (h0, r0), (h1, r1) = pts[-1], (pts[0][0] + 360.0, pts[0][1] + 360.0)
        return round((r0 + (r1 - r0) * (h - h0) / (h1 - h0)) % 360)
    for (h0, r0), (h1, r1) in zip(pts, pts[1:]):
        if h0 <= h <= h1:
            return round((r0 + (r1 - r0) * (h - h0) / (h1 - h0)) % 360)
    return pts[0][1]


def parse(wal):
    try:
        bg = wal["special"]["background"]
        c = {i: wal["colors"]["color%d" % i] for i in (1, 4, 5, 7)}
    except (KeyError, TypeError) as e:
        raise ValueError("incomplete palette: %s" % e)
    for v in (bg, *c.values()):
        if not (isinstance(v, str) and _HEX.match(v)):
            raise ValueError("palette has a colour that isn't #rrggbb: %r" % (v,))
    return rgb(bg), {i: rgb(v) for i, v in c.items()}


def roles(bg, c, legible=legible):
    """({--md-sys-color name: [r, g, b]}, primary, is_light). `legible` is injectable."""
    text = c[7]
    light = lum(bg) > 0.4
    away = [255, 255, 255] if light else [0, 0, 0]          # the extreme behind the surfaces
    primary = legible(c[1], bg, 4.5, text)
    secondary = legible(c[4], bg, 4.5, text)
    tertiary = legible(c[5], bg, 4.5, text)

    surface = mix(bg, primary, 0.03)
    container = mix(mix(bg, text, 0.07), primary, 0.08)
    high = mix(mix(bg, text, 0.12), primary, 0.10)
    highest = mix(mix(bg, text, 0.17), primary, 0.12)

    def accent(color):
        cont = mix(container, color, 0.26)
        return cont, legible(mix(color, text, 0.6), cont, 4.5, text)

    p_cont, on_p_cont = accent(primary)
    s_cont, on_s_cont = accent(secondary)
    t_cont, on_t_cont = accent(tertiary)
    if light:
        err, on_err, err_cont, on_err_cont = [186, 26, 26], [255, 255, 255], [255, 218, 214], [147, 0, 10]
    else:
        err, on_err, err_cont, on_err_cont = [255, 180, 171], [105, 0, 5], [147, 0, 10], [255, 218, 214]

    r = {
        "primary": primary, "surface-tint": primary, "on-primary": bg,
        "primary-container": p_cont, "on-primary-container": on_p_cont,
        "secondary": secondary, "on-secondary": bg,
        "secondary-container": s_cont, "on-secondary-container": on_s_cont,
        "tertiary": tertiary, "on-tertiary": bg,
        "tertiary-container": t_cont, "on-tertiary-container": on_t_cont,
        "error": err, "on-error": on_err, "error-container": err_cont, "on-error-container": on_err_cont,
        "background": surface, "on-background": text,
        "surface": surface, "on-surface": text,
        "surface-variant": high, "on-surface-variant": mix(text, bg, 0.22),
        "outline": mix(bg, text, 0.45), "outline-variant": mix(bg, text, 0.20),
        "shadow": [0, 0, 0], "scrim": [0, 0, 0],
        "inverse-surface": text, "inverse-on-surface": bg,
        "inverse-primary": legible(primary, text, 4.5, bg),
        "surface-dim": surface, "surface-bright": mix(mix(bg, text, 0.20), primary, 0.12),
        "surface-container-lowest": mix(surface, away, 0.35),
        "surface-container-low": mix(surface, container, 0.5),
        "surface-container": container,
        "surface-container-high": high,
        "surface-container-highest": highest,
    }
    # Material's "fixed" roles are the same in light and dark.
    for name, base, cont, on_cont in (("primary", primary, p_cont, on_p_cont),
                                      ("secondary", secondary, s_cont, on_s_cont),
                                      ("tertiary", tertiary, t_cont, on_t_cont)):
        r[name + "-fixed"] = cont
        r[name + "-fixed-dim"] = base
        r["on-" + name + "-fixed"] = bg
        r["on-" + name + "-fixed-variant"] = on_cont
    return r, primary, light


def render(wal, legible=legible):
    bg, c = parse(wal)
    r, primary, light = roles(bg, c, legible)
    on, off = "var(--ON)", "var(--OFF)"
    head = [
        "/* Written by scripts/steam-colors.py from the shell's palette; see its header. */",
        ":root {",
        '    --theme-color: "Matugen";',
        "    --hue-rotate: %ddeg;" % hue_rotate(primary),
        # The theme's Appearance switches, set by the background so a light wallpaper goes light.
        "    color-scheme: only %s !important;" % ("light" if light else "dark"),
        "    --scheme: %s;" % ("light" if light else "dark"),
        "    --scheme-light: %s;" % (on if light else off),
        "    --scheme-dark: %s;" % (off if light else on),
        "    --scheme-color: %s;" % ("white" if light else "black"),
        "    --scheme-color-inverse: %s;" % ("black" if light else "white"),
    ]
    body = ["    --md-sys-color-%s: %s;" % (k, css(v)) for k, v in r.items()]
    return "\n".join(head + body + ["}", ""])


def default_theme_dirs():
    data = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return [os.path.join(data, "Steam", "millennium", "themes", THEME),
            os.path.expanduser("~/.steam/steam/millennium/themes/" + THEME)]


def write_if_changed(path, text):
    """Atomic rename; untouched when the content is already right, so a run that didn't move
    the palette gives the theme's poll nothing to repaint."""
    try:
        with open(path, encoding="utf-8") as f:
            if f.read() == text:
                return False
    except OSError:
        pass
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".matugen.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    return True


def shell_legible():
    """pwspice's legible() — the one definition of the shell's accent floor — adapted to RGB
    lists. Falls back to this file's copy when pwspice can't be loaded."""
    try:
        spec = importlib.util.spec_from_file_location(
            "pwspice", os.path.join(HERE, "themes", "spotify", "pwspice.py"))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        fn = mod._legible
    except Exception:
        return legible

    def hexs(c):
        return "#%02x%02x%02x" % tuple(max(0, min(255, round(v))) for v in c)

    def adapted(color, bg, target, toward):
        return rgb(fn(hexs(color), hexs(bg), target, hexs(toward)))
    return adapted


def main(argv=None):
    ap = argparse.ArgumentParser(description="Write Material's matugen.css from the shell's palette.")
    ap.add_argument("colors_json")
    ap.add_argument("--theme-dir")
    ap.add_argument("--preview", action="store_true", help="print the file, write nothing")
    args = ap.parse_args(argv)

    try:
        with open(args.colors_json, encoding="utf-8") as f:
            text = render(json.load(f), shell_legible())
    except (OSError, ValueError) as e:
        print("steam-colors: palette unreadable: %s" % e, file=sys.stderr)
        return 2
    if args.preview:
        sys.stdout.write(text)
        return 0
    theme_dir = args.theme_dir or next((d for d in default_theme_dirs() if os.path.isdir(d)), "")
    if not theme_dir:
        print("steam-colors: %s isn't installed (scripts/theme-setup.sh steam)" % THEME, file=sys.stderr)
        return 3
    target = os.path.join(theme_dir, RELATIVE)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    changed = write_if_changed(target, text)
    print("steam-colors: %s" % ("updated matugen.css" if changed else "matugen.css already current"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
