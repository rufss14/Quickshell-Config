#!/usr/bin/env python3
"""
darkreader-live.py — Dark Reader wears the desktop palette, live.

Dark Reader has no external API: it takes settings only from its own popup, never reads
storage again after startup, and rewrites it whole on any change. So the only live route is
code inside its own background page. `build` makes a patched copy of the INSTALLED Dark Reader
(same add-on id, so the same settings) that asks a native-messaging host for the palette:

    reload-theme.sh ─ push ─▶ host (spawned by Zen) ─ native messaging ─▶ patched Dark Reader
                       unix socket                                          └▶ setTheme(), as the popup does

    python3 scripts/darkreader-live.py build        patched xpi into the cache dir
    python3 scripts/darkreader-live.py install      build + native-host manifest + the signing pref
    python3 scripts/darkreader-live.py uninstall    undo the manifest and the pref
    python3 scripts/darkreader-live.py probe|push   used by apps-lib.sh (exit 1: no host running)

Zen is invoked as `darkreader-live.py <manifest> <extension-id>`, which is host mode.

The signing pref: the patched xpi has no Mozilla signature. This Zen build has
MOZ_REQUIRE_SIGNING=false, so `xpinstall.signatures.required=false` is honoured (read from its
omni.ja); the cost is that the profile then accepts ANY unsigned extension.
"""

import colorsys
import glob
import json
import os
import re
import selectors
import socket
import struct
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
HOST_NAME = "quicktest_darkreader"
EXT_ID = "addon@darkreader.org"
SIGN_PREF = "xpinstall.signatures.required"
PATCH_JS = os.path.join(HERE, "darkreader-live-patch.js")
ANCHOR = "Messenger.init(_a.getMessengerAdapter());"
BEGIN, END = "/* quicktest-live:begin */", "/* quicktest-live:end */"
HEX = re.compile(r"^#[0-9a-fA-F]{6}$")


def cache_dir():
    return os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")


def config_dir():
    return os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")


def run_dir():
    return os.environ.get("XDG_RUNTIME_DIR") or cache_dir()


def palette_path():
    return os.path.join(cache_dir(), "wal", "colors.json")


# ── palette → Dark Reader theme ──────────────────────────────────────────────

def luminance(hex_colour):
    """WCAG relative luminance, 0 (black) to 1 (white)."""
    def lin(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (int(hex_colour[i:i + 2], 16) for i in (1, 3, 5))
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


# Dark Reader gives every NEUTRAL colour on a page the hue and saturation of the background it
# is handed, keeping the page's own lightness. HSL saturation is unstable near black: #0e0000
# is "100% red", so a whole page tinted neon red beside a sidebar that reads as near-black.
# Capping it keeps the hue (the palette's identity) and calms the tint. A judgement call
# (the user's, 2026-10-06: "tame the saturation, keep dynamic"); raise it for a stronger tint.
MAX_SATURATION = 0.4


def tame(hex_colour):
    """The same colour with its HSL saturation capped at MAX_SATURATION; hue, lightness, greys
    and anything already muted are unchanged."""
    r, g, b = (int(hex_colour[i:i + 2], 16) / 255 for i in (1, 3, 5))
    h, l, sat = colorsys.rgb_to_hls(r, g, b)
    if sat > MAX_SATURATION:
        r, g, b = colorsys.hls_to_rgb(h, l, MAX_SATURATION)
    return "#%02x%02x%02x" % tuple(int(c * 255 + 0.5) for c in (r, g, b))


def theme_from_palette(pal):
    """The roles update-zen-colors.sh uses: background, foreground (color7), accent (color1).
    The background is the palette's own — what Zen's sidebar and top bar wear (they point at
    `--lwt-accent-color`, Pywalfox's frame), measured from a screenshot: #000000 for a #000000
    palette. (Pywalfox's toolbar/popup colour, `backgroundLight`, is NOT what Zen shows there.)
    Saturation is capped (`tame`) so a near-black palette doesn't tint pages neon.
    A dark palette sets Dark Reader's dark scheme, a light one its light scheme — the other
    scheme and the mode stay the user's."""
    special, colors = pal.get("special", {}), pal.get("colors", {})
    bg = special.get("background") or colors.get("color0")
    fg = special.get("foreground") or colors.get("color7")
    accent = colors.get("color1")
    for c in (bg, fg, accent):
        if not (isinstance(c, str) and HEX.match(c)):
            raise ValueError(f"palette colour is not #rrggbb: {c!r}")
    scheme = "light" if luminance(bg) > 0.5 else "dark"
    return {
        f"{scheme}SchemeBackgroundColor": tame(bg),
        f"{scheme}SchemeTextColor": fg.lower(),
        "selectionColor": accent.lower(),
    }


def current_theme():
    with open(palette_path(), encoding="utf-8") as f:
        return theme_from_palette(json.load(f))


# ── native messaging: 4-byte native-endian length, then JSON ─────────────────

def frame(obj):
    data = json.dumps(obj).encode()
    return struct.pack("=I", len(data)) + data


def write_all(fd, data):
    while data:
        data = data[os.write(fd, data):]


def socket_glob():
    return os.path.join(run_dir(), "quicktest-darkreader-*.sock")


def host():
    """Spawned by the browser for as long as it runs. One socket per host (two browsers can
    each have the patched extension); it accepts only the word `push`, never a colour — the
    palette always comes from the file."""
    path = os.path.join(run_dir(), f"quicktest-darkreader-{os.getpid()}.sock")
    srv = socket.socket(socket.AF_UNIX)
    srv.bind(path)
    os.chmod(path, 0o600)
    srv.listen(4)

    def send_theme():
        try:
            write_all(1, frame({"theme": current_theme()}))
        except (OSError, ValueError, json.JSONDecodeError) as e:
            print(f"darkreader-live: no theme sent: {e}", file=sys.stderr)

    sel = selectors.DefaultSelector()
    sel.register(0, selectors.EVENT_READ)
    sel.register(srv, selectors.EVENT_READ)
    try:
        send_theme()
        while True:
            for key, _ in sel.select():
                if key.fileobj is srv:
                    conn, _ = srv.accept()
                    conn.settimeout(1)
                    try:
                        if conn.recv(16).startswith(b"push"):
                            send_theme()
                    except OSError:
                        pass
                    conn.close()
                elif not os.read(0, 65536):   # browser closed our stdin: it is gone
                    return 0
    finally:
        srv.close()
        try:
            os.unlink(path)
        except OSError:
            pass


def live_hosts():
    """Connected sockets of every running host; a socket nobody answers is a dead host's."""
    found = []
    for path in glob.glob(socket_glob()):
        s = socket.socket(socket.AF_UNIX)
        try:
            s.connect(path)
            found.append(s)
        except OSError:
            s.close()
            try:
                os.unlink(path)
            except OSError:
                pass
    return found


def push():
    hosts = live_hosts()
    for s in hosts:
        s.sendall(b"push\n")
        s.close()
    return 0 if hosts else 1


def probe():
    hosts = live_hosts()
    for s in hosts:
        s.close()
    return 0 if hosts else 1


# ── build: a patched copy of the installed Dark Reader ───────────────────────

def profile_dirs():
    """Every Zen profile directory, from profiles.ini (never a literal profile name)."""
    out = []
    for root in (os.path.join(config_dir(), "zen"), os.path.join(os.path.expanduser("~"), ".zen")):
        ini = os.path.join(root, "profiles.ini")
        if not os.path.isfile(ini):
            continue
        path = rel = None
        for line in open(ini, encoding="utf-8").read().splitlines() + ["["]:
            if line.startswith("["):
                if path and re.match(r"\[Profile\d+\]", cur):
                    out.append(os.path.join(root, path) if rel != "0" else path)
                cur, path, rel = line, None, "1"
            elif line.startswith("Path="):
                path = line[5:]
            elif line.startswith("IsRelative="):
                rel = line[11:]
    return out


def installed_xpis():
    return [p for d in profile_dirs()
            for p in [os.path.join(d, "extensions", EXT_ID + ".xpi")] if os.path.isfile(p)]


def patch_background(js):
    """Insert the patch after Messenger.init — replacing a previous one, so a rebuild from an
    already-patched copy works. The anchor is Dark Reader's own code: if an update moves it,
    fail here rather than ship an extension that silently does nothing."""
    js = re.sub(re.escape(BEGIN) + r".*?" + re.escape(END) + r"\n?", "", js, flags=re.S)
    if js.count(ANCHOR) != 1:
        raise SystemExit(f"darkreader-live: expected exactly one `{ANCHOR}` in Dark Reader's "
                         "background/index.js — this Dark Reader version needs the patch re-anchored")
    with open(PATCH_JS, encoding="utf-8") as f:
        body = f.read()
    return js.replace(ANCHOR, f"{ANCHOR}\n{BEGIN}\n{body}{END}")


def patch_manifest(text):
    m = json.loads(text)
    if "nativeMessaging" not in m["permissions"]:
        m["permissions"].append("nativeMessaging")
        m["version"] += ".1"   # an upgrade over the installed one; a rebuild keeps it
    return json.dumps(m, indent=2) + "\n"


def build(src=None, out=None):
    src = src or next(iter(sorted(installed_xpis(), key=os.path.getmtime, reverse=True)), None)
    if not src:
        raise SystemExit("darkreader-live: no installed Dark Reader found in a Zen profile")
    out = out or os.path.join(cache_dir(), "quickshell-quicktest", "darkreader", "darkreader-quicktest.xpi")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    tmp = out + ".tmp"
    with zipfile.ZipFile(src) as zin, zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zout:
        for item in zin.infolist():
            if item.filename.startswith("META-INF/"):
                continue   # Mozilla's signature covers the original bytes; it no longer verifies
            data = zin.read(item.filename)
            if item.filename == "manifest.json":
                data = patch_manifest(data.decode()).encode()
            elif item.filename == "background/index.js":
                data = patch_background(data.decode()).encode()
            zout.writestr(item.filename, data)
    os.replace(tmp, out)
    return out


# ── install / uninstall ──────────────────────────────────────────────────────

def host_manifest_path():
    return os.path.join(os.path.expanduser("~"), ".mozilla", "native-messaging-hosts", HOST_NAME + ".json")


def set_pref(user_js, key, value):
    """Make user.js say exactly `key = value` and touch no other line — it is the user's file."""
    line = f'user_pref("{key}", {value});'
    lines = open(user_js, encoding="utf-8").read().splitlines() if os.path.exists(user_js) else []
    if line in lines:
        return False
    lines = [l for l in lines if not l.startswith(f'user_pref("{key}",')] + [line]
    with open(user_js + ".tmp", "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    os.replace(user_js + ".tmp", user_js)
    return True


def profiles_with_darkreader():
    return [os.path.dirname(os.path.dirname(p)) for p in installed_xpis()]


def install():
    out = build()
    os.chmod(__file__, os.stat(__file__).st_mode | 0o111)
    manifest = host_manifest_path()
    os.makedirs(os.path.dirname(manifest), exist_ok=True)
    with open(manifest, "w", encoding="utf-8") as f:
        json.dump({"name": HOST_NAME, "description": "Quicktest palette for Dark Reader",
                   "path": os.path.abspath(__file__), "type": "stdio",
                   "allowed_extensions": [EXT_ID]}, f, indent=2)
    print(f"wrote {manifest}")
    for d in profiles_with_darkreader():
        set_pref(os.path.join(d, "user.js"), SIGN_PREF, "false")
        print(f"user.js: {SIGN_PREF} = false in {d}")
    print(f"""
Built {out}
Now, once:
  1. Restart Zen (the pref is read at startup).
  2. about:addons → ⚙ → Install Add-on From File… → the .xpi above. It replaces Dark Reader
     in place and keeps its settings.
  3. Dark Reader → ⋯ → Automatic Updates: Off. An AMO update would replace the patch.
After that every wallpaper or scheme change repaints Dark Reader live.""")
    return 0


def uninstall():
    try:
        os.unlink(host_manifest_path())
        print(f"removed {host_manifest_path()}")
    except OSError:
        pass
    for d in profiles_with_darkreader():
        set_pref(os.path.join(d, "user.js"), SIGN_PREF, "true")
        print(f"user.js: {SIGN_PREF} = true in {d}")
    print("Reinstall Dark Reader from addons.mozilla.org (the patched copy fails its signature check).")
    return 0


COMMANDS = {"build": lambda: print(build()) or 0, "install": install, "uninstall": uninstall,
            "push": push, "probe": probe}

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd in COMMANDS:
        sys.exit(COMMANDS[cmd]())
    sys.exit(host())   # the browser passes a manifest path and the extension id
