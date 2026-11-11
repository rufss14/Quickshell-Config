#!/usr/bin/env python3
"""
pwspice.py

Applies pywal colors to Spicetify color.ini.
Does not call spicetify — run `spicetify apply` separately after this.
"""
from __future__ import annotations
import argparse
import json
import os
import re
import time
from pathlib import Path
from colorsys import rgb_to_hls, hls_to_rgb
from datetime import datetime

DEFAULT_WAL_JSON = str(Path.home() / ".cache" / "wal" / "colors.json")
DEFAULT_OUTPUT   = str(Path.home() / ".config" / "spicetify" / "Themes" / "QuickZiro" / "color.ini")

# ── Utilities ──────────────────────────────────────────────────────────────────

def log(msg: str, level: str = "INFO"):
    ts = datetime.now().strftime('%H:%M:%S')
    print(f"[{ts}] [{level}] {msg}", flush=True)

def norm_hex(h):
    if not h: return None
    s = str(h).strip()
    h = ('#' + s.lstrip('#')).lower() if s else None
    if h and len(h) == 7:
        return h[1:].upper()
    return None

def hex_to_rgb_t(hexcolor):
    h = hexcolor.lstrip('#')
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def rgb_t_to_hex(rgb):
    return '{:02x}{:02x}{:02x}'.format(
        max(0, min(255, int(round(rgb[0])))),
        max(0, min(255, int(round(rgb[1])))),
        max(0, min(255, int(round(rgb[2]))))
    ).upper()

def hex_to_hsl(hexcolor):
    r, g, b = [x / 255.0 for x in hex_to_rgb_t(hexcolor)]
    h, l, s = rgb_to_hls(r, g, b)
    return (h * 360.0, s, l)

def hsl_to_hex(h_deg, s, l):
    h = (h_deg % 360.0) / 360.0
    r, g, b = hls_to_rgb(h, l, s)
    return rgb_t_to_hex((r * 255, g * 255, b * 255))

def clamp(v, a=0.0, b=1.0):
    return max(a, min(b, v))

def shift_lightness(hexcolor, delta):
    try:
        h_deg, s, l = hex_to_hsl(hexcolor)
    except Exception:
        return hexcolor
    return hsl_to_hex(h_deg, s, clamp(l + delta))

def is_dark(hexcolor):
    try:
        r, g, b = hex_to_rgb_t(hexcolor)
        lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
        return lum < 0.5
    except Exception:
        return True

# ── Pywal loader ───────────────────────────────────────────────────────────────

def wait_for_wal_json(colors_path: Path, timeout: float = 10.0, interval: float = 0.25) -> bool:
    """Poll until colors.json exists and is valid JSON (guards against wal write race)."""
    # Checked at least once: with timeout 0 ("it's already there, don't wait") the old
    # `while now < deadline` never looked at the file and always reported it missing.
    deadline = time.monotonic() + timeout
    while True:
        if colors_path.exists() and colors_path.stat().st_size > 10:
            try:
                if json.loads(colors_path.read_text(encoding='utf-8')):
                    return True
            except (json.JSONDecodeError, OSError):
                pass
        if time.monotonic() >= deadline:
            return False
        time.sleep(interval)

def load_pywal(colors_path: Path):
    """Return (palette_list, special_dict)."""
    try:
        data = json.loads(colors_path.read_text(encoding='utf-8'))
    except Exception as e:
        log(f"Failed to parse {colors_path}: {e}", "ERROR")
        return [], {}

    special = {}
    palette = []

    if isinstance(data, dict):
        raw_special = data.get('special') or {}
        for k, v in (raw_special.items() if isinstance(raw_special, dict) else []):
            if isinstance(v, str):
                special[k] = norm_hex(v)

        if 'colors' in data and isinstance(data['colors'], list):
            palette = [norm_hex(c) for c in data['colors'] if isinstance(c, str)]
        elif 'palette' in data and isinstance(data['palette'], list):
            palette = [norm_hex(c) for c in data['palette'] if isinstance(c, str)]
        else:
            colors_dict = data.get('colors', {})
            for i in range(16):
                k = f'color{i}'
                if k in data and isinstance(data[k], str):
                    palette.append(norm_hex(data[k]))
                elif isinstance(colors_dict, dict) and k in colors_dict:
                    palette.append(norm_hex(colors_dict[k]))
                elif k in raw_special and isinstance(raw_special[k], str):
                    palette.append(norm_hex(raw_special[k]))

    return [p for p in palette if p], special

# ── Color generation ───────────────────────────────────────────────────────────
#
# Spicetify has fifteen colour slots; the shell's palette (config/PaletteRoles.qml) has
# more roles than that and derives them from five inputs. So the slots carry the INPUTS
# and QuickSpice's user.css derives the rest with color-mix(), the same blends:
#
#   main sidebar player misc   base     the wallpaper's background
#   text                       text     pywal color7
#   button, tab-active         primary  legible(color1) — what the shell calls `primary`
#   button-active, selected-row focus   legible(color4) — and `focus`
#   shadow                     base     "text drawn ON an accent fill" (fgOnPrimary)
#   card, notification         surface / surfaceHigh, pre-mixed (they are opaque there too)
#   button-disabled            surfaceContainer
#
# Why not "palette[5]" as before: pywal's ramp is ordered by hue, not by legibility, so a
# fixed slot lands on a colour that can sit at 2.5:1 on the background — the shell measured
# exactly that for color1 and floors both accents at 4.5:1 (PaletteRoles, "Accents").
# Matching its floor is what makes Spotify's accent the SAME colour as the bar's.

def _rgb(hexcolor):
    return [float(v) for v in hex_to_rgb_t(hexcolor)]

def _mix(a, b, t):
    """Opaque blend of `t` of b into a — PaletteRoles.mix(), on hex strings."""
    ra, rb = _rgb(a), _rgb(b)
    return rgb_t_to_hex([x + (y - x) * t for x, y in zip(ra, rb)])

def _luminance(hexcolor):
    def lin(v):
        s = v / 255.0
        return s / 12.92 if s <= 0.03928 else ((s + 0.055) / 1.055) ** 2.4
    r, g, b = (lin(v) for v in _rgb(hexcolor))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def _contrast(a, b):
    la, lb = _luminance(a), _luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)

def _legible(hexcolor, bg, target, toward):
    """services/palette.js legible(): the least shift toward `toward` that reaches `target`."""
    if _contrast(hexcolor, bg) >= target:
        return hexcolor
    if _contrast(toward, bg) < target:
        return toward
    lo, hi = 0.0, 1.0
    for _ in range(12):
        mid = (lo + hi) / 2
        if _contrast(_mix(hexcolor, toward, mid), bg) >= target:
            hi = mid
        else:
            lo = mid
    return _mix(hexcolor, toward, hi)

def generate_spicetify_colors(palette, special, style='spice'):
    def slot(i, fallback):
        return palette[i] if 0 <= i < len(palette) else fallback

    base = special.get('background') or '000000'
    text = slot(7, special.get('foreground') or 'FFFFFF')

    primary = _legible(slot(1, text), base, 4.5, text)
    focus   = _legible(slot(4, text), base, 4.5, text)

    surface   = _mix(base, primary, 0.03)
    container = _mix(_mix(base, text, 0.07), primary, 0.08)
    high      = _mix(_mix(base, text, 0.12), primary, 0.10)

    # QuickZiro (Ziro with these slots). Its user.css reads the slots directly, no
    # color-mix(), so each slot has to be the finished colour: cards, the track list and
    # inputs sit one step AWAY from the page (darker on a dark page, white-ward on a light
    # one, as Ziro's own schemes do), and `button-disabled` is the hover/border/seekbar
    # step, a visible notch off the page the other way.
    if style == 'ziro':
        away = '000000' if _luminance(base) < 0.2 else 'FFFFFF'
        surface   = _mix(_mix(base, away, 0.30), primary, 0.03)
        container = _mix(_mix(base, text, 0.10), primary, 0.08)
        high      = surface

    return {
        'text':               text,
        'subtext':            _mix(text, base, 0.42),   # fgDim, as a solid
        'main':               base,
        'sidebar':            base,
        'player':             base,
        'card':               surface,
        'shadow':             base,
        'selected-row':       focus,
        'button':             primary,
        'button-active':      focus,
        'button-disabled':    container,
        'tab-active':         primary,
        'notification':       high,
        # The shell's `danger` is color1, and Spotify draws it as TEXT (an error, a failed
        # download): raw, it can land on the base itself (1.22:1 measured), so it gets the
        # accents' floor.
        'notification-error': _legible(slot(1, 'FC8783'), base, 4.5, text),
        'misc':               base,
    }

# ── INI writing ────────────────────────────────────────────────────────────────

KEY_ORDER = [
    'text', 'subtext', 'main', 'sidebar', 'player', 'card', 'shadow',
    'selected-row', 'button', 'button-active', 'button-disabled',
    'tab-active', 'notification', 'notification-error', 'misc'
]

def read_color_ini(path: str):
    if not os.path.exists(path):
        return None
    try:
        with open(path, 'r', encoding='utf-8') as f:
            return f.read()
    except Exception as e:
        log(f"Could not read {path}: {e}", "WARN")
        return None

def update_pywal_section(content: str, colors: dict):
    pad          = 19
    section_lines = ['[Pywal]'] + [f"{k.ljust(pad)}= {colors.get(k, '')}" for k in KEY_ORDER]
    new_section  = '\n'.join(section_lines)

    if content is None:
        return new_section + '\n'

    # Anchored to a line start: a comment that merely MENTIONS the section was matched mid-line.
    match = re.search(r'^\[Pywal\].*?(?=\n\[|\Z)', content, re.DOTALL | re.IGNORECASE | re.MULTILINE)
    if match:
        return content[:match.start()] + new_section + content[match.end():]

    return content.rstrip('\n') + '\n\n' + new_section + '\n'

def write_color_ini(path: str, content: str, backup: bool = False):
    os.makedirs(os.path.dirname(path) or '.', exist_ok=True)

    if backup and os.path.exists(path):
        ts  = datetime.now().strftime('%Y%m%d-%H%M%S')
        bak = f"{path}.{ts}.bak"
        try:
            with open(path, 'rb') as src, open(bak, 'wb') as dst:
                dst.write(src.read())
            log(f"Backup: {bak}")
        except Exception as e:
            log(f"Could not create backup: {e}", "WARN")

    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
    log(f"Written: {path}")

# ── CLI ────────────────────────────────────────────────────────────────────────

def parse_args():
    p = argparse.ArgumentParser(description='Write pywal colors to Spicetify color.ini.')
    p.add_argument('-w', '--wal-json',     default=DEFAULT_WAL_JSON)
    p.add_argument('-o', '--out',          default=DEFAULT_OUTPUT)
    p.add_argument('--accent-index',       type=int, default=5, help=argparse.SUPPRESS)  # ignored; kept so old invocations still parse
    p.add_argument('--style',              choices=('spice', 'ziro'), default='ziro',
                   help="slot layout: ziro (QuickZiro) reads the slots as finished colours; spice derives roles in CSS (a leftover QuickSpice install)")
    p.add_argument('--backup',             action='store_true')
    p.add_argument('--preview',            action='store_true', help='Print colors, do not write')
    p.add_argument('--wait-for-wal',       type=float, default=10.0, metavar='SECONDS')
    return p.parse_args()

def main():
    args        = parse_args()
    colors_path = Path(os.path.expanduser(args.wal_json))

    log(f"Waiting for {colors_path} ...")
    if not wait_for_wal_json(colors_path, timeout=args.wait_for_wal):
        log(f"colors.json not ready after {args.wait_for_wal}s", "ERROR")
        return 2

    palette, special = load_pywal(colors_path)
    if not palette and not special:
        log("No colors loaded from pywal JSON", "ERROR")
        return 2

    log(f"Loaded {len(palette)} palette colors, special: {list(special.keys())}")
    colors = generate_spicetify_colors(palette, special, args.style)

    if args.preview:
        print('[Pywal]')
        for k in KEY_ORDER:
            print(f'{k.ljust(19)}= {colors.get(k, "")}')
        return 0

    output_path     = os.path.expanduser(args.out)
    existing        = read_color_ini(output_path)
    updated         = update_pywal_section(existing, colors)
    write_color_ini(output_path, updated, backup=args.backup)
    log("Done. color.ini updated — spicetify will pick up the change.")
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
