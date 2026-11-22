#!/usr/bin/env python3
"""app-gradient.py: the shell's gradient in the apps that can wear one.

The shell writes the gradient it wears (colours resolved against the palette, angle, strength) to
$XDG_STATE_HOME/quicktest/gradient.json. Each app takes it as a marked block in a file of its own, or has
the block removed when the gradient is off:

    kitty    a PNG over the terminal's background, `background_image` in current-theme.conf
    gtk4     `window.background` in gtk-4.0/gtk.css (libadwaita repaints live)
    discord  the quicktest theme in each Vencord/Vesktop themes dir: the three base surfaces go
             transparent over a gradient on #app-mount
    spotify  the active QuickZiro / QuickSpice theme's user.css, then `spicetify refresh -s -n`

Those files are rewritten by every colour change (the theme copies in wave-lib.sh and reload-theme.sh, the
Discord and Spotify recolour), so the callers run this right after: without it the gradient would last until
the next colour change.

    python3 scripts/app-gradient.py [all|kitty|gtk4|discord|spotify]... [--reload]

With --reload kitty is told to re-read its config. The mixing is services/gradient.js `colours()` again: each
stop moves strength * 0.6 of the way from the app's ground to its colour (STRENGTH_MAX there), the middle
sits at `mid` between them.
"""
import glob
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import zlib

STRENGTH_MAX = 0.6
BEGIN = "# >>> quicktest gradient (managed) >>>"
END = "# <<< quicktest gradient <<<"
W, H = 960, 540


def _home(var, fallback):
    return os.environ.get(var) or os.path.join(os.path.expanduser("~"), fallback)


def rgb(h):
    h = h.lstrip("#")
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)]


def mix(a, b, t):
    return [a[i] + (b[i] - a[i]) * t for i in range(3)]


def stops(doc, ground):
    k = max(0.0, min(1.0, float(doc.get("strength", 0.6)))) * STRENGTH_MAX
    cols = [mix(ground, rgb(s), k) for s in doc["stops"][:3]]
    mid = max(0.1, min(0.9, float(doc.get("mid", 0.5))))
    if len(cols) == 2:
        cols = [cols[0], mix(cols[0], cols[1], mid), cols[1]]
    return cols, mid


def render(doc, ground, path):
    cols, mid = stops(doc, ground)
    a = math.radians(float(doc.get("angle", 30)))
    cx, sy = math.cos(a), math.sin(a)
    half = (abs(W * cx) + abs(H * sy)) / 2 or 1
    dx, dy = cx * 2 * half, sy * 2 * half
    x0, y0 = W / 2 - cx * half, H / 2 - sy * half
    d2 = dx * dx + dy * dy
    rows = []
    for y in range(H):
        row = bytearray([0])
        for x in range(W):
            t = max(0.0, min(1.0, ((x - x0) * dx + (y - y0) * dy) / d2))
            c = mix(cols[0], cols[1], t / mid) if t < mid else mix(cols[1], cols[2], (t - mid) / (1 - mid))
            # under one level of ordered dither: a dark gradient bands badly in 8 bits
            n = ((x * 7 + y * 13) % 16) / 16.0 - 0.5
            row += bytes(max(0, min(255, int(v + n + 0.5))) for v in c)
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".new"
    with open(tmp, "wb") as f:
        f.write(png)
    os.replace(tmp, path)


CSS_BEGIN = "/* >>> quicktest gradient (managed) >>> */"
CSS_END = "/* <<< quicktest gradient <<< */"


def load_doc():
    try:
        doc = json.load(open(os.path.join(_home("XDG_STATE_HOME", ".local/state"), "quicktest", "gradient.json")))
    except (OSError, ValueError):
        return None
    ok = (doc.get("on") is True and isinstance(doc.get("stops"), list) and len(doc["stops"]) >= 2
          and all(isinstance(s, str) and re.fullmatch(r"#[0-9a-fA-F]{6}", s) for s in doc["stops"]))
    return doc if ok else None


def wal_ground():
    try:
        d = json.load(open(os.path.join(_home("XDG_CACHE_HOME", ".cache"), "wal", "colors.json")))
        return rgb(d["special"]["background"])
    except (OSError, ValueError, KeyError):
        return [16, 16, 16]


def css_gradient(doc, ground):
    cols, mid = stops(doc, ground)
    hexes = ["#%02x%02x%02x" % tuple(int(round(v)) for v in c) for c in cols]
    # CSS angles run clockwise from "up"; the shell's from "right"
    return "linear-gradient(%ddeg, %s 0%%, %s %d%%, %s 100%%)" % (
        round(float(doc.get("angle", 30)) + 90) % 360, hexes[0], hexes[1], round(mid * 100), hexes[2])


def strip_css(text):
    return re.sub(r"\n?" + re.escape(CSS_BEGIN) + r".*?" + re.escape(CSS_END) + r"\n?", "\n", text, flags=re.S)


def write_if_changed(path, text):
    try:
        if open(path).read() == text:
            return False
    except OSError:
        pass
    tmp = path + ".gradient.new"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, path)
    return True


def css_block(path, block):
    """Put `block` (or nothing) as the managed block of the CSS file `path`. True when the file changed."""
    try:
        text = open(path).read()
    except OSError:
        return False
    text = strip_css(text).rstrip("\n") + "\n"
    if block:
        text += "\n" + CSS_BEGIN + "\n" + block.strip("\n") + "\n" + CSS_END + "\n"
    return write_if_changed(path, text)


def do_kitty(doc, reload_):
    theme = os.path.join(_home("XDG_CONFIG_HOME", ".config"), "kitty", "current-theme.conf")
    if not os.path.isfile(theme):
        return
    text = open(theme).read()
    text = re.sub(r"\n?" + re.escape(BEGIN) + r".*?" + re.escape(END) + r"\n?", "\n", text, flags=re.S)
    if doc:
        m = re.search(r"^\s*background\s+(#[0-9a-fA-F]{6})\s*$", text, flags=re.M)
        ground = rgb(m.group(1)) if m else [16, 16, 16]
        png = os.path.join(_home("XDG_CACHE_HOME", ".cache"), "quicktest", "kitty-gradient.png")
        render(doc, ground, png)
        text = text.rstrip("\n") + "\n\n" + BEGIN + "\nbackground_image " + png + "\nbackground_image_layout scaled\n" \
            "background_tint 0\n" + END + "\n"
    write_if_changed(theme, text)
    if reload_:
        subprocess.run(["pkill", "-USR1", "kitty"], check=False)


def rgba(c, a):
    return "rgba(%d, %d, %d, %.2f)" % (round(c[0]), round(c[1]), round(c[2]), a)


def do_gtk4(doc):
    css = os.path.join(_home("XDG_CONFIG_HOME", ".config"), "gtk-4.0", "gtk.css")
    css = os.path.realpath(css)
    if not os.path.isfile(css):
        return
    block = ""
    if doc:
        g = wal_ground()
        # libadwaita paints from these named colours (a later @define-color wins): the window and its bars let the
        # gradient through, the sidebars, lists and cards become veils of the ground over it. Popovers and dialogs
        # stay solid, so a menu is readable over whatever is under it.
        veil = [("window_bg_color", 0.0), ("headerbar_bg_color", 0.0), ("headerbar_backdrop_color", 0.0),
                ("sidebar_bg_color", 0.42), ("secondary_sidebar_bg_color", 0.30), ("view_bg_color", 0.34),
                ("card_bg_color", 0.34), ("thumbnail_bg_color", 0.34), ("dialog_bg_color", 0.0)]
        block = "".join("@define-color %s %s;\n" % (n, rgba(g, a)) for n, a in veil)
        block += ("window.background, .background {\n  background-image: %s;\n}\n"
                  "headerbar, .titlebar { box-shadow: none; }\n") % css_gradient(doc, g)
    css_block(css, block)


def do_discord(doc):
    cfg = _home("XDG_CONFIG_HOME", ".config")
    for path in sorted(glob.glob(os.path.join(cfg, "*", "themes", "quicktest.theme.css"))):
        block = ""
        if doc:
            # The theme sets its tokens on `body` and on the four theme classes with :not(...), which outranks
            # a bare class or :root, so the same selectors are repeated here, later in the file.
            sel = ("body,\n.theme-dark:not(.custom-user-profile-theme),\n.theme-light:not(.custom-user-profile-theme),\n"
                   ".theme-darker:not(.custom-user-profile-theme),\n.theme-midnight:not(.custom-user-profile-theme)")
            veil = "color-mix(in srgb, var(--qs-base) 40%, transparent)"
            lift = "color-mix(in srgb, var(--qs-fg) 9%, transparent)"
            block = ("#app-mount { background-image: %s !important; }\n%s {\n  --app-frame-background: transparent;\n" % (css_gradient(doc, wal_ground()), sel)
                     + "".join("  --%s: %s;\n" % (t, veil) for t in (
                         "background-base-lowest", "background-base-lower", "background-base-low", "background-primary",
                         "background-secondary-alt", "chat-background-default", "home-background"))
                     + "".join("  --%s: %s;\n" % (t, lift) for t in (
                         "background-accent", "background-code", "card-background-default", "background-surface-high",
                         "background-mod-normal"))
                     + "}\n")
        css_block(path, block)


def do_spotify(doc):
    root = os.path.join(_home("XDG_CONFIG_HOME", ".config"), "spicetify", "Themes")
    if not shutil.which("spicetify") or not os.path.isdir(root):
        return
    try:
        cur = subprocess.run(["spicetify", "config", "current_theme"], capture_output=True, text=True,
                             timeout=10).stdout.strip().split()[0]
    except (OSError, subprocess.SubprocessError, IndexError):
        return
    if cur not in ("QuickZiro", "QuickSpice"):
        cur = "QuickZiro"
    path = os.path.join(root, cur, "user.css")
    if not os.path.isfile(path):
        return
    block = ""
    if doc:
        veil = "color-mix(in srgb, var(--spice-main) 40%, transparent)"
        block = ("body, .Root, .Root__top-container { background-image: %s !important; }\n"
                 ".Root, .Root__nav-bar, .Root__main-view, .Root__now-playing-bar, .Root__ads-container,\n"
                 ".main-view-container, .main-view-container__scroll-node, .main-view-container__scroll-node-child,\n"
                 ".main-topBar-background, .main-topBar-overlay, .main-nowPlayingBar-container, .nav-bar-container,\n"
                 ".main-home-content, .main-entityHeader-container, .main-actionBar-ActionBar {\n"
                 "  background: %s !important;\n}\n"
                 ".encore-dark-theme, .encore-dark-theme .encore-base-set {\n"
                 "  --background-base: transparent;\n  --background-elevated-base: %s;\n}\n") % (css_gradient(doc, wal_ground()), veil, veil)
    if css_block(path, block):
        subprocess.run(["spicetify", "refresh", "-s", "-n"], capture_output=True, timeout=60, check=False)
        port = os.environ.get("QS_SPOTIFY_BRIDGE_PORT", "47821")
        if port.isdigit():
            subprocess.run(["curl", "-sS", "-m", "2", "-X", "POST", "http://127.0.0.1:%s/restyle" % port],
                           capture_output=True, check=False)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    which = set(args) or {"all"}
    if "all" in which:
        which = {"kitty", "gtk4", "discord", "spotify"}
    doc = load_doc()
    reload_ = "--reload" in sys.argv
    for name, fn in (("kitty", lambda: do_kitty(doc, reload_)), ("gtk4", lambda: do_gtk4(doc)),
                     ("discord", lambda: do_discord(doc)), ("spotify", lambda: do_spotify(doc))):
        if name in which:
            try:
                fn()
            except Exception as e:  # one app must not stop the rest
                print("app-gradient: %s: %s" % (name, e), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
