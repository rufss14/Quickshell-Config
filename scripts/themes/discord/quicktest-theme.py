#!/usr/bin/env python3
"""
quicktest-theme.py

Rewrites the two generated blocks of the Quicktest Discord theme (vencord/quicktest.theme.css):

  palette   the five colour inputs, from pywal's colors.json. The CSS derives every other role from
            them with color-mix(), the same blends as config/PaletteRoles.qml. Roles come from
            scripts/themes/spotify/pwspice.py, so Discord's accent is the SAME colour as the bar's
            and Spotify's (primary/focus floored at 4.5:1 exactly as PaletteRoles does).
  shape     Settings -> Type & Shape: spacing, radii, the faces, motion durations, shadows, icon shape.
            The shell hands over the RESOLVED values (services/DiscordTheme.qml reads Tokens/Motion,
            which already apply the scales, square corners, the "Rounder" ladder and the installed-
            font fallback), as services/Cursor.qml does for the cursor: re-deriving them here would
            be a second opinion about what the shell looks like.

    quicktest-theme.py --css <theme.css> [--colors <colors.json>] [--shape <json>] [--preview]

`--colors` alone is the old pywal-midnight.py-compatible call (scripts/apps-lib.sh); `--shape` alone is
the shell's. Both blocks are written under one lock, so the wave's recolour and a Type & Shape change
can't overwrite each other. Exit 0 = written or already current, 2 = nothing usable (no palette, bad
shape, or the theme lacks the marker block).
"""
from __future__ import annotations

import argparse
import fcntl
import importlib.util
import json
import math
import os
import re
import sys
import tempfile
from pathlib import Path

BEGIN = "/* qs-palette:begin"
END = "/* qs-palette:end */"
SHAPE_BEGIN = "/* qs-shape:begin"
SHAPE_END = "/* qs-shape:end */"


def _pwspice():
    p = Path(__file__).resolve().parent.parent / "spotify" / "pwspice.py"
    spec = importlib.util.spec_from_file_location("pwspice", p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def roles(pw, palette: list, special: dict) -> dict:
    """The five inputs, plus the few alphas the shell weakens or strengthens on a light palette."""
    c = pw.generate_spicetify_colors(palette, special)
    base = "#" + (special.get("background") or "000000")
    dark = pw.is_dark(base)
    return {
        "base": base.lower(),
        "text": "#" + c["text"].lower(),
        "primary": "#" + c["button"].lower(),          # legible(color1)
        "focus": "#" + c["button-active"].lower(),     # legible(color4)
        "on-primary": base.lower(),                    # fgOnPrimary
        # PaletteRoles._lightMode: outline 0.32, fgDim 0.62, fgFaint 0.45; shadows lighter.
        # (The shell reads Config.themeMode; a theme has no config, so luminance stands in.)
        "a-outline": "22%" if dark else "32%",
        "a-dim": "58%" if dark else "62%",
        "a-faint": "30%" if dark else "45%",
        "a-shadow-card": "38%" if dark else "16%",
        "a-shadow-popup": "46%" if dark else "22%",
    }


def block(r: dict) -> str:
    lines = [
        f"{BEGIN} (rewritten by scripts/themes/discord/quicktest-theme.py; edit nothing inside) */",
        ":root {",
        f"  --qs-base: {r['base']};",
        f"  --qs-text: {r['text']};",
        f"  --qs-primary: {r['primary']};",
        f"  --qs-focus: {r['focus']};",
        f"  --qs-on-primary: {r['on-primary']};",
        # PaletteRoles.shadow: occlusion, not a tint, so the one constant in the palette.
        "  --qs-shadow: #000000;",
        f"  --qs-a-outline: {r['a-outline']};",
        f"  --qs-a-dim: {r['a-dim']};",
        f"  --qs-a-faint: {r['a-faint']};",
        f"  --qs-a-shadow-card: {r['a-shadow-card']};",
        f"  --qs-a-shadow-popup: {r['a-shadow-popup']};",
        "}",
        END,
    ]
    return "\n".join(lines)


def splice(css: str, new_block: str, begin: str = BEGIN, end: str = END) -> str | None:
    """`css` with the marker block replaced, or None when the markers aren't exactly one pair."""
    if css.count(begin) != 1 or css.count(end) != 1:
        return None
    a = css.index(begin)
    b = css.index(end)
    if b < a:
        return None
    return css[:a] + new_block + css[b + len(end):]


# ── shape ────────────────────────────────────────────────────────────────────
# What the committed theme ships, and what Settings -> Type & Shape reads at its defaults
# (Tokens.qml, Motion.qml). scripts/test-discord-theme.py checks the committed block IS this.
DEFAULT_SHAPE = {
    "spacing": {"xs": 2, "sm": 4, "md": 8, "lg": 12, "xl": 16, "xxl": 24},
    "radius": {"xs": 4, "sm": 8, "pill": 12, "card": 16, "xl": 24},
    "font": "CodeNewRoman Nerd Font",
    "mono": "CodeNewRoman Nerd Font Mono",
    "motion": {"respond": 100, "fast": 120, "standard": 150, "emphasized": 340, "exit": 200, "slow": 400,
               "ripple": 500, "spring-fast": 322, "spring": 371},
    # Tokens.shadowDp/Blur/Spread/OffsetY at dp 6 (card) and 12 (popup); None = shadows off.
    "shadow": {"card": {"y": 3, "blur": 10.8, "spread": -1.4}, "popup": {"y": 6, "blur": 17.6, "spread": -2.2}},
    "icon": "default",   # Config.iconShape
}
# ShapeBox.qml: the cookie is Scallop 8 petals at depth 0.13, the clover 4 at 0.20; a squircle is a 36% corner.
# "default" is each place's own shape: a cookie behind a section icon, a rounded square on a button.
ICON_SHAPES = ("default", "squircle", "cookie", "clover", "circle")
PETALS = {"cookie": (8, 0.13), "clover": (4, 0.20)}
HOT_DEPTH = 0.07   # how much deeper a petalled holder gets while hovered (ShapeBox.extraPetal)


def scallop_polygon(petals: int, depth: float, points: int = 120) -> str:
    """Scallop.qml's outline as a CSS polygon(): r(a) = (R - amp) + amp * (0.5 + 0.5 * cos(n a)), amp = depth * R,
    tips on the box edge. 120 vertices, so a rest and a hot polygon interpolate (clip-path transitions need equal counts).
    At (8, 0.13) this is the shell's cookie outline (Scallop.qml)."""
    pts = []
    for i in range(points):
        a = 2 * math.pi * i / points
        r = (1 - depth) + depth * (0.5 + 0.5 * math.cos(petals * a))
        pts.append(f"{50 + 50 * r * math.cos(a):.1f}% {50 + 50 * r * math.sin(a):.1f}%")
    return "polygon(" + ",".join(pts) + ")"


def icon_vars(icon: str) -> list:
    """The four clip-path variables the CSS reads: a holder behind an icon (sidebar rows) and an icon button, each at rest
    and hovered. The petalled shapes deepen on hover; the plain ones don't change."""
    holder = "cookie" if icon == "default" else icon
    button = "rounded" if icon == "default" else icon
    def hot(name):
        return f"{name}-hot" if name in PETALS else name
    return [f"  --qs-clip-holder: var(--qs-clip-{holder});", f"  --qs-clip-holder-hot: var(--qs-clip-{hot(holder)});",
            f"  --qs-clip-button: var(--qs-clip-{button});", f"  --qs-clip-button-hot: var(--qs-clip-{hot(button)});"]
# The shell's own fallbacks, for a machine without the chosen face (this theme is shipped to others).
FONT_FALLBACK = '"JetBrains Mono", "Fira Code", ui-monospace, "SF Mono", Menlo, Consolas, monospace'
MONO_FALLBACK = '"JetBrains Mono", ui-monospace, monospace'
FONT_NAME = re.compile(r'[^"\\\x00-\x1f]{1,64}')   # anything that can't end a quoted CSS string


def _num(v, lo, hi, what):
    if isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) or not lo <= v <= hi:
        raise ValueError(f"{what}: {v!r} is not a number in {lo}..{hi}")
    return v


def clean_shape(raw) -> dict:
    """The shape the shell sent, validated and merged onto the defaults. Raises ValueError.

    argv is a trust boundary: these values end up inside a stylesheet, so a font name that could
    close a string or a rule, or a number that isn't one, is refused rather than written."""
    if not isinstance(raw, dict):
        raise ValueError("shape must be an object")
    out = json.loads(json.dumps(DEFAULT_SHAPE))
    for k in raw:
        if k not in out:
            raise ValueError(f"unknown shape key {k!r}")
    for group, hi in (("spacing", 200), ("radius", 200), ("motion", 5000)):
        for k, v in (raw.get(group) or {}).items():
            if k not in out[group]:
                raise ValueError(f"unknown {group} key {k!r}")
            out[group][k] = int(round(_num(v, 0, hi, f"{group}.{k}")))
    for k in ("font", "mono"):
        if k in raw:
            if not isinstance(raw[k], str) or not FONT_NAME.fullmatch(raw[k]):
                raise ValueError(f"{k}: {raw[k]!r} is not a plain font name")
            out[k] = raw[k]
    if "icon" in raw:
        if raw["icon"] not in ICON_SHAPES:
            raise ValueError(f"icon: {raw['icon']!r} is not one of {ICON_SHAPES}")
        out["icon"] = raw["icon"]
    if "shadow" in raw:
        sh = raw["shadow"]
        if sh is None:
            out["shadow"] = None
        elif isinstance(sh, dict):
            for level in sh:
                if level not in ("card", "popup"):
                    raise ValueError(f"unknown shadow level {level!r}")
                for k, (lo, hi) in {"y": (0, 100), "blur": (0, 200), "spread": (-100, 100)}.items():
                    out["shadow"][level][k] = float(_num((sh[level] or {}).get(k, out["shadow"][level][k]), lo, hi, f"shadow.{level}.{k}"))
        else:
            raise ValueError("shadow must be an object or null")
    return out


def _g(v):
    return f"{v:g}"


def shape_block(sh: dict) -> str:
    shadow = lambda lv, a: ("none" if sh["shadow"] is None else
                            f"0 {_g(sh['shadow'][lv]['y'])}px {_g(sh['shadow'][lv]['blur'])}px {_g(sh['shadow'][lv]['spread'])}px "
                            f"color-mix(in srgb, var(--qs-shadow) var(--qs-a-shadow-{lv}), transparent)")
    lines = [f"{SHAPE_BEGIN} (rewritten by scripts/themes/discord/quicktest-theme.py from Settings -> Type & Shape; edit nothing inside) */",
             ":root {"]
    lines += [f"  --qs-sp-{k}: {v}px;" for k, v in sh["spacing"].items()]
    lines += [f"  --qs-r-{k}: {v}px;" for k, v in sh["radius"].items()]
    lines += [f'  --qs-font: "{sh["font"]}", {FONT_FALLBACK};',
              f'  --qs-font-mono: "{sh["mono"]}", {MONO_FALLBACK};']
    lines += [f"  --qs-t-{k}: {v}ms;" for k, v in sh["motion"].items()]
    lines += [f"  --qs-shadow-card: {shadow('card', 0)};", f"  --qs-shadow-popup: {shadow('popup', 0)};"]
    lines += icon_vars(sh["icon"])
    lines += ["}", SHAPE_END]
    return "\n".join(lines)


def _locked():
    """One lock for every writer of any theme file, in the runtime dir (not beside the theme, which
    Vencord watches). Held for the read-modify-write, so two runs can't both start from the same text."""
    d = os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir()
    f = open(os.path.join(d, "quicktest-discord-theme.lock"), "w")
    fcntl.flock(f, fcntl.LOCK_EX)
    return f


def main() -> int:
    wal = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    cfg = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    ap = argparse.ArgumentParser(description="Write the shell's palette and Type & Shape into the Quicktest Discord theme.")
    ap.add_argument("--css", default=os.path.join(cfg, "Vencord", "themes", "quicktest.theme.css"))
    ap.add_argument("--colors", help="pywal colors.json; the default when --shape is not given either")
    ap.add_argument("--shape", help="JSON: the resolved Type & Shape values (see DEFAULT_SHAPE)")
    ap.add_argument("--preview", action="store_true", help="print the block(s), write nothing")
    args = ap.parse_args()

    blocks = []   # (begin, end, new_block)
    if args.colors is not None or args.shape is None:
        colors = args.colors or os.path.join(wal, "wal", "colors.json")
        pw = _pwspice()
        palette, special = pw.load_pywal(Path(colors))
        if not palette and not special:
            print(f"quicktest-theme: no usable palette in {colors}", file=sys.stderr)
            return 2
        blocks.append((BEGIN, END, block(roles(pw, palette, special))))
    if args.shape is not None:
        try:
            blocks.append((SHAPE_BEGIN, SHAPE_END, shape_block(clean_shape(json.loads(args.shape)))))
        except (ValueError, json.JSONDecodeError) as e:
            print(f"quicktest-theme: bad --shape: {e}", file=sys.stderr)
            return 2
    if args.preview:
        print("\n".join(b for _, _, b in blocks))
        return 0

    lock = _locked()   # noqa: F841 - held until exit
    try:
        old = Path(args.css).read_text(encoding="utf-8")
    except OSError as e:
        print(f"quicktest-theme: {e}", file=sys.stderr)
        return 2
    new = old
    for begin, end, text in blocks:
        new = splice(new, text, begin, end)
        if new is None:
            print(f"quicktest-theme: {args.css} has no single {begin.strip('/* ')} block", file=sys.stderr)
            return 2
    if new == old:
        return 0   # Vencord re-parses the whole theme on any write; don't give it a reason to
    tmp = args.css + ".qs-new"
    Path(tmp).write_text(new, encoding="utf-8")
    os.replace(tmp, args.css)   # atomic: Vencord watches the directory and must never read half a theme
    return 0


if __name__ == "__main__":
    sys.exit(main())
