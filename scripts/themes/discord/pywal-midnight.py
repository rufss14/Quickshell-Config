#!/usr/bin/env python3
"""
apply_pywal_to_midnight.py

Full pywal -> midnight.theme.css mapper (midnight-style mapping).

Saves a .bak if --backup is passed. Use --preview to see the injected variables
without writing the file.

Default paths:
  Theme:  ~/.config/Vencord/themes/midnight.theme.css
  Pywal:  ~/.cache/wal/colors.json
"""
from pathlib import Path
import json, argparse, os, re
from colorsys import rgb_to_hls, hls_to_rgb

# ----------------- Utilities -----------------

def norm_hex(h):
    if not h: return None
    s = str(h).strip()
    return ('#' + s.lstrip('#')).lower() if s else None

def hex_to_rgb_t(hexcolor):
    h = hexcolor.lstrip('#')
    return tuple(int(h[i:i+2], 16) for i in (0,2,4))

def rgb_t_to_hex(rgb):
    return '#{:02x}{:02x}{:02x}'.format(
        max(0, min(255, int(round(rgb[0])))),
        max(0, min(255, int(round(rgb[1])))),
        max(0, min(255, int(round(rgb[2]))))
    )

def hex_to_hsl(hexcolor):
    r,g,b = [x/255.0 for x in hex_to_rgb_t(hexcolor)]
    h,l,s = rgb_to_hls(r,g,b)
    return (h*360.0, s, l)

def hsl_to_hex(h_deg, s, l):
    h = (h_deg % 360.0) / 360.0
    r,g,b = hls_to_rgb(h, l, s)
    return rgb_t_to_hex((r*255, g*255, b*255))

def clamp(v, a=0.0, b=1.0):
    return max(a, min(b, v))

# small helper to shift lightness by delta in HSL space
def shift_lightness(hexcolor, delta):
    try:
        h_deg, s, l = hex_to_hsl(hexcolor)
    except Exception:
        return hexcolor
    new_l = clamp(l + delta)
    return hsl_to_hex(h_deg, s, new_l)

# create n shades centered on base lightness with offsets list
def make_shades_from_hex(hexcolor, offsets):
    try:
        h_deg, s, l = hex_to_hsl(hexcolor)
    except Exception:
        # fallback blue
        hexcolor = '#57c7ff'
        h_deg, s, l = hex_to_hsl(hexcolor)
    s = clamp(s, 0.12, 0.95)
    shades = []
    for d in offsets:
        L = clamp(l + d)
        shades.append(hsl_to_hex(h_deg, s, L))
    return shades

# ----------------- Pywal loader -----------------

def load_pywal(colors_path: Path):
    """Return (palette_list, special_dict). palette_list in order color0..colorN"""
    if not colors_path.exists():
        return [], {}
    try:
        data = json.loads(colors_path.read_text(encoding='utf-8'))
    except Exception:
        return [], {}
    special = {}
    palette = []
    if isinstance(data, dict):
        raw_special = data.get('special') or {}
        for k,v in (raw_special.items() if isinstance(raw_special, dict) else []):
            if isinstance(v, str):
                special[k] = norm_hex(v)
        if 'colors' in data and isinstance(data['colors'], list):
            palette = [norm_hex(c) for c in data['colors'] if isinstance(c, str)]
        elif 'palette' in data and isinstance(data['palette'], list):
            palette = [norm_hex(c) for c in data['palette'] if isinstance(c, str)]
        else:
            # look for color0..color15 keys top-level or in special
            for i in range(16):
                k = f'color{i}'
                if k in data and isinstance(data[k], str):
                    palette.append(norm_hex(data[k]))
                elif k in raw_special and isinstance(raw_special[k], str):
                    palette.append(norm_hex(raw_special[k]))
    return [p for p in palette if p], special

# ----------------- Mapping strategy (midnight-style) ---------------

def build_full_replacements(palette, special, accent_index=5, accent_hex_override=None, force_hue=None):
    """
    Return dict of variable -> hex or var(...) values to upsert into :root.
    Strategy for midnight theme:
      - bg tiers: derived from special.background (darken progressively)
      - text tiers: derived from special.foreground (lighten/darken progressively)
      - semantic families: map standard palette indices to families and create shades
      - accent: midnight uses blue by default, but we'll use palette[accent_index] (default 5 for purple)
      - ensure accent-1..5 reference blue family (midnight's default accent color)
    """
    # Fallbacks
    fallback_accent = '#57c7ff'
    bg_base = special.get('background') or '#0b0710'
    fg_base = special.get('foreground') or '#c5c8cc'

    # Decide base accent (midnight defaults to blue, but we'll make it configurable)
    if accent_hex_override:
        accent_base = norm_hex(accent_hex_override)
    else:
        accent_base = None
        if palette and 0 <= accent_index < len(palette):
            accent_base = palette[accent_index]
        if not accent_base and palette and len(palette) > 4:
            accent_base = palette[4]  # fallback to color4 (blue)
        if not accent_base and palette:
            accent_base = palette[0]
        if not accent_base:
            # check special keys
            for k in ('color4','color5','accent','accent_color','foreground','background'):
                if k in special:
                    accent_base = special[k]; break
        if not accent_base:
            accent_base = fallback_accent
    accent_base = norm_hex(accent_base)

    # Build bg tiers by progressively lightening background
    # midnight: bg-4 main background (darkest), bg-3, bg-2, bg-1 (progressively lighter)
    replacements = {}
    replacements['--bg-4'] = shift_lightness(bg_base, -0.00)   # main (use base)
    replacements['--bg-3'] = shift_lightness(bg_base,  0.03)
    replacements['--bg-2'] = shift_lightness(bg_base,  0.06)
    replacements['--bg-1'] = shift_lightness(bg_base,  0.10)

    # Text tiers: text-1 is primary text (brightest), text-5 is muted (darkest)
    replacements['--text-1'] = norm_hex(fg_base)
    replacements['--text-2'] = shift_lightness(fg_base, -0.04)
    replacements['--text-3'] = shift_lightness(fg_base, -0.10)
    replacements['--text-4'] = shift_lightness(fg_base, -0.30)
    replacements['--text-5'] = shift_lightness(fg_base, -0.55)

    # Semantic families mapping to pywal common indices:
    # red = color1, green = color2, yellow = color3, blue = color4, purple = color5, cyan = color6
    def pick_palette(i, fallback):
        if palette and 0 <= i < len(palette):
            return palette[i]
        return fallback

    semantic_bases = {
        'red':    pick_palette(1, '#ff5c57'),
        'green':  pick_palette(2, '#5af78e'),
        'yellow': pick_palette(3, '#f3f99d'),
        'blue':   pick_palette(4, accent_base),  # midnight uses blue as accent
        'purple': pick_palette(5, '#c5a3ff'),
        'cyan':   pick_palette(6, '#9aedfe'),
    }

    # For each family create 5 shades (light->dark) centered on base
    # offsets chosen to create nice gradients
    offsets = [0.18, 0.08, 0.0, -0.07, -0.18]
    for fam, base in semantic_bases.items():
        shades = make_shades_from_hex(base or '#808080', offsets)
        # map to variables e.g. --red-1..--red-5
        for i, shade in enumerate(shades, start=1):
            replacements[f'--{fam}-{i}'] = shade

    # Midnight uses blue as accent (unlike system24 which uses purple)
    replacements['--accent-1'] = 'var(--blue-1)'
    replacements['--accent-2'] = 'var(--blue-2)'
    replacements['--accent-3'] = 'var(--blue-3)'
    replacements['--accent-4'] = 'var(--blue-4)'
    replacements['--accent-5'] = 'var(--blue-5)'

    # Status indicators - map to semantic mid shades
    replacements['--online'] = replacements.get('--green-2')
    replacements['--dnd'] = replacements.get('--red-2')
    replacements['--idle'] = replacements.get('--yellow-2')

    # brand-experiment - create light-to-dark from accent_base
    brand_shades = make_shades_from_hex(accent_base or fallback_accent, [0.28, 0.10, 0.0, -0.06, -0.14])
    replacements['--brand-experiment'] = brand_shades[2]
    replacements['--brand-experiment-100'] = brand_shades[0]
    replacements['--brand-experiment-200'] = brand_shades[1]
    replacements['--brand-experiment-300'] = brand_shades[2]
    replacements['--brand-experiment-400'] = brand_shades[3]
    replacements['--brand-experiment-500'] = brand_shades[4]
    replacements['--brand-experiment-contrast'] = '#ffffff' if is_dark(accent_base) else '#000000'

    # Hover/active states - midnight uses hsla with alpha
    replacements['--hover'] = 'hsla(221, 19%, 40%, 0.1)'
    replacements['--active'] = 'hsla(220, 19%, 40%, 0.2)'
    replacements['--active-2'] = 'hsla(220, 19%, 40%, 0.3)'
    replacements['--message-hover'] = 'hsla(220, 0%, 0%, 0.1)'

    # Additional midnight-specific variables
    replacements['--accent-new'] = 'var(--accent-2)'
    replacements['--mention'] = 'linear-gradient(to right, color-mix(in hsl, var(--accent-2), transparent 90%) 40%, transparent)'
    replacements['--mention-hover'] = 'linear-gradient(to right, color-mix(in hsl, var(--accent-2), transparent 95%) 40%, transparent)'
    replacements['--reply'] = 'linear-gradient(to right, color-mix(in hsl, var(--text-3), transparent 90%) 40%, transparent)'
    replacements['--reply-hover'] = 'linear-gradient(to right, color-mix(in hsl, var(--text-3), transparent 95%) 40%, transparent)'

    return replacements

# helper used in brand contrast
def is_dark(hexcolor):
    try:
        r,g,b = hex_to_rgb_t(hexcolor)
        lum = (0.2126*r + 0.7152*g + 0.0722*b)/255.0
        return lum < 0.5
    except Exception:
        return True

# ----------------- CSS Upsert and Aggressive Replace -------------------------

def upsert_root_variables(css_text, replacements):
    root_re = re.compile(r'(:root\s*\{)(.*?)(\})', re.DOTALL)
    m = root_re.search(css_text)
    lines = []
    for k in sorted(replacements.keys()):
        v = replacements[k]
        lines.append(f'    {k}: {v}; /* pywal */ /* pywal */ /* pywal */')
    inject_block = '\n'.join(lines) + '\n'
    if not m:
        return ':root {\n' + inject_block + '}\n\n' + css_text
    prefix, body, suffix = m.group(1), m.group(2), m.group(3)
    # detect existing variables
    var_re = re.compile(r'(--[A-Za-z0-9_\-]+)\s*:\s*([^;]+);')
    existing = {mm.group(1): mm.group(2).strip() for mm in var_re.finditer(body)}
    for k,v in replacements.items():
        if k in existing:
            # replace value while keeping trailing comments
            body = re.sub(r'(' + re.escape(k) + r'\s*:\s*)([^;]+)(;)', r'\1' + v + r'\3 /* pywal */ /* pywal */ /* pywal */', body)
        else:
            body += f'    {k}: {v}; /* pywal */ /* pywal */ /* pywal */\n'
    return css_text[:m.start()] + prefix + body + suffix + css_text[m.end():]

def force_accent_vars_to_blue_aggressive(css_text):
    """Midnight uses blue for accent, not purple"""
    total = 0
    for i in range(1,6):
        pattern = re.compile(r'(--accent-' + str(i) + r'\s*:\s*)([^;]*)(;)', re.IGNORECASE)
        css_text, n = pattern.subn(r'\1 var(--blue-' + str(i) + r')\3', css_text)
        total += n
    return css_text, total

# ---------------- CLI and main -----------------------------------------------

def parse_args():
    p = argparse.ArgumentParser(description='Full pywal -> midnight.theme.css mapper.')
    p.add_argument('--css', '-c', default='~/.config/Vencord/themes/midnight.theme.css')
    p.add_argument('--colors', default='~/.cache/wal/colors.json')
    p.add_argument('--accent-index', type=int, default=4,
                   help='Palette index for accent color (default: 4 for blue)')
    p.add_argument('--accent-hex', help='Override accent hex (optional)')
    p.add_argument('--force-hue', type=float, default=None,
                   help='Force hue (degrees) when generating shades (optional)')
    p.add_argument('--preview', action='store_true', help='Print planned replacements and exit')
    p.add_argument('--backup', action='store_true', help='Create .bak backup of theme before writing')
    return p.parse_args()

def main():
    args = parse_args()
    css_path = Path(os.path.expanduser(args.css))
    colors_path = Path(os.path.expanduser(args.colors))
    if not css_path.exists():
        raise FileNotFoundError(f'Theme file not found: {css_path}')

    palette, special = load_pywal(colors_path)

    replacements = build_full_replacements(palette, special,
                                          accent_index=args.accent_index,
                                          accent_hex_override=args.accent_hex,
                                          force_hue=args.force_hue)

    # Ensure accent variables reference blue (midnight's default)
    replacements['--accent-1'] = 'var(--blue-1)'
    replacements['--accent-2'] = 'var(--blue-2)'
    replacements['--accent-3'] = 'var(--blue-3)'
    replacements['--accent-4'] = 'var(--blue-4)'
    replacements['--accent-5'] = 'var(--blue-5)'

    if args.preview:
        print('pywal palette:', palette if palette else '(empty)')
        print('pywal special:', special)
        print('PLANNED REPLACEMENTS:')
        for k in sorted(replacements.keys()):
            print(f'{k}: {replacements[k]}')
        return

    original = css_path.read_text(encoding='utf-8')
    if args.backup:
        bak = css_path.with_suffix(css_path.suffix + '.bak')
        bak.write_text(original, encoding='utf-8')
        print('Backup created at', bak)

    patched = upsert_root_variables(original, replacements)
    patched, n = force_accent_vars_to_blue_aggressive(patched)
    if n:
        print(f'Forced replacement of {n} accent assignments to var(--blue-N)')

    css_path.write_text(patched, encoding='utf-8')
    print('Theme updated:', css_path)
    print('Accent used (approx):', replacements.get('--blue-3'))

if __name__ == '__main__':
    main()
