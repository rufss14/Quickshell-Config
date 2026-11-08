#!/usr/bin/env python3
# ── steam-live.py ────────────────────────────────────────────────────────────
# Repaints an OPEN Steam from the live palette, so Steam joins the wave like Discord and
# Zen do, instead of waiting for a restart (steam-colors.py only writes Millennium's config,
# which Steam reads when a window loads).
#
#   steam-live.py push      push the simply-dark colours — and Steam's own recoloured blues/greens —
#                           into every open Steam window
#   steam-live.py scan [--if-needed]
#                           read the colour literals out of Steam's stylesheets (steam-scan.js) so
#                           steam-accent.py can recolour them; --if-needed: only when they changed
#   steam-live.py probe     exit 0 when a push could work right now (opted in, port answers)
#   steam-live.py flag      put Steam's debug-port flag file back (when opted in)
#   steam-live.py enable    opt in (see below) and drop the flag
#   steam-live.py disable   opt out and remove the flag
#   steam-live.py status
#
# ── How, and what it costs ───────────────────────────────────────────────────
# Millennium 3.5 talks to Steam over a private debug PIPE, which nothing else can join. The
# only way in from outside is Steam's own CEF debug port, which Steam opens on 127.0.0.1:8080
# when `~/.local/share/Steam/.cef-enable-remote-debugging` exists AT START (it deletes the
# file as it reads it, so it has to be put back before every launch — `flag`, called from
# shell-env.sh, every theme run and ThemeRunner's Restart button).
#
# THAT PORT IS UNAUTHENTICATED: while Steam runs, any program running as you can drive its
# UI. Millennium moved to the pipe to avoid exactly that, so this is OFF unless you ask for it:
# `enable` writes a marker, and without it nothing here creates the flag, `probe` says no, and
# the shell treats Steam as restart-only. Not enabled by default because the repo is published.
#
# Whether the port coexists with Millennium's pipe was not known when this was written; if a
# push finds nothing listening (`probe` fails with Steam open) that is the first suspect.
#
# What a push does: for each Steam window (a CDP "page" target) set the theme's colour
# variables as inline properties on the document root — above every stylesheet, so no removing
# of what Millennium injected — then wait two animation frames so the process exits only once the
# new colours are painted. A HIDDEN window (Steam has ~10: every menu and supernav) is not waited
# on: it gets no frames, and Chromium throttles its timers to 1s, so even the cap would cost a
# second each — measured, the first version took 2s for a push that is 3ms in a visible window. The values are the
# same ones steam-colors.py bakes into the config, so a window opened later agrees.
# ─────────────────────────────────────────────────────────────────────────────
import base64
import concurrent.futures
import hashlib
import importlib.util
import json
import os
import re
import socket
import struct
import sys
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
HOST = "127.0.0.1"
PORT = int(os.environ.get("STEAM_LIVE_PORT", "8080"))
THEME = "simply-dark"
GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
PAINT_CAP_MS = 150          # two frames is ~35ms; a window that never paints must not stall the wave

# exit codes
OK, FAILED, NOTHING_TO_DO, PORT_CLOSED = 0, 2, 3, 4

_NAME = re.compile(r"^--[A-Za-z0-9-]+$")
_VALUE = re.compile(r"^(#[0-9a-fA-F]{6}|rgba\(\d{1,3},\d{1,3},\d{1,3},[0-9.]+\))$")


# ── Opt-in, and Steam's flag file ────────────────────────────────────────────

def state_dir():
    return os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "quicktest")


def marker():
    return os.path.join(state_dir(), "steam-live")


def enabled():
    return os.path.exists(marker())


def steam_root():
    data = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    for d in (os.path.join(data, "Steam"), os.path.expanduser("~/.steam/steam")):
        if os.path.isdir(d):
            return d
    return None


def flag_path():
    root = steam_root()
    return os.path.join(root, ".cef-enable-remote-debugging") if root else None


def put_flag():
    """Recreate the flag Steam consumes at start. False when opted out or Steam isn't installed."""
    path = flag_path()
    if not enabled() or not path:
        return False
    with open(path, "a"):
        os.utime(path, None)
    return True


# ── A just-enough WebSocket client (CDP is JSON over one) ────────────────────

class WS:
    def __init__(self, url, timeout=2.0):
        u = urllib.parse.urlsplit(url)
        # /json is served by the port we asked, but is still data: never connect elsewhere on its say-so.
        if u.scheme != "ws" or u.hostname != HOST or u.port != PORT:
            raise ValueError("refusing a debugger URL that isn't %s:%d: %s" % (HOST, PORT, url))
        self.s = socket.create_connection((HOST, PORT), timeout=timeout)
        key = base64.b64encode(os.urandom(16)).decode()
        path = u.path + ("?" + u.query if u.query else "")
        self.s.sendall(("GET %s HTTP/1.1\r\nHost: %s:%d\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                        "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n"
                        % (path, HOST, PORT, key)).encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = self.s.recv(4096)
            if not chunk:
                raise ConnectionError("closed during handshake")
            buf += chunk
        head, self.buf = buf.split(b"\r\n\r\n", 1)
        lines = head.decode("latin-1").split("\r\n")
        if " 101 " not in lines[0]:
            raise ConnectionError("handshake refused: " + lines[0])
        accept = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
        if ("sec-websocket-accept: " + accept).lower() not in [l.lower() for l in lines]:
            raise ConnectionError("bad Sec-WebSocket-Accept")
        self.n = 0

    def _need(self, n):
        while len(self.buf) < n:
            chunk = self.s.recv(65536)
            if not chunk:
                raise EOFError("connection closed")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def _send_frame(self, opcode, payload):
        n = len(payload)
        head = bytearray([0x80 | opcode])
        if n < 126:
            head.append(0x80 | n)
        elif n < 65536:
            head += bytes([0x80 | 126]) + struct.pack(">H", n)
        else:
            head += bytes([0x80 | 127]) + struct.pack(">Q", n)
        mask = os.urandom(4)
        self.s.sendall(bytes(head) + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))

    def recv_text(self):
        """The next complete text message; answers pings, reassembles fragments, raises on close."""
        msg = b""
        while True:
            b1, b2 = self._need(2)
            op, n = b1 & 0x0F, b2 & 0x7F
            if n == 126:
                n = struct.unpack(">H", self._need(2))[0]
            elif n == 127:
                n = struct.unpack(">Q", self._need(8))[0]
            data = self._need(n)     # server frames are unmasked
            if op == 0x8:
                raise EOFError("closed by the server")
            if op == 0x9:
                self._send_frame(0xA, data)
                continue
            if op == 0xA:
                continue
            msg += data
            if b1 & 0x80:
                return msg.decode("utf-8")

    def call(self, method, **params):
        self.n += 1
        self._send_frame(0x1, json.dumps({"id": self.n, "method": method, "params": params}).encode())
        while True:
            m = json.loads(self.recv_text())
            if m.get("id") == self.n:       # anything else is an event we didn't ask for
                return m

    def close(self):
        try:
            self.s.close()
        except OSError:
            pass


def targets(timeout=1.0):
    with urllib.request.urlopen("http://%s:%d/json" % (HOST, PORT), timeout=timeout) as r:
        return json.load(r)


def pages(timeout=1.0):
    return [t for t in targets(timeout) if t.get("type") == "page" and t.get("webSocketDebuggerUrl")]


# ── The colours ──────────────────────────────────────────────────────────────

def load_steam_colors():
    spec = importlib.util.spec_from_file_location("steam_colors", os.path.join(HERE, "steam-colors.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def load_accent():
    spec = importlib.util.spec_from_file_location("steam_accent", os.path.join(HERE, "steam-accent.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def palette_parts(colors_json):
    """(bg, fg, accent, base) as the accent stylesheet wants them."""
    sc = load_steam_colors()
    bg, fg, colors, _ = sc.read_palette(colors_json)
    theme_dir = next((d for d in sc.default_theme_dirs() if os.path.isdir(d)), "")
    return bg, fg, colors[1], sc.main_bg_base(sc.theme_stock(theme_dir))


def millennium_config():
    return os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"),
                        "millennium", "config.json")


def theme_block(colors_json, config=None):
    """{variable: #rrggbb} the theme reads, from the palette — or None when simply-dark isn't active."""
    sc = load_steam_colors()
    try:
        with open(config or millennium_config(), encoding="utf-8") as f:
            if json.load(f).get("themes", {}).get("activeTheme") != THEME:
                return None
    except (OSError, ValueError):
        return None
    bg, fg, colors, wal = sc.read_palette(colors_json)
    theme_dir = next((d for d in sc.default_theme_dirs() if os.path.isdir(d)), "")
    stock = sc.theme_stock(theme_dir)
    block = sc.derive(bg, fg, colors, stock, wal)
    # Only the theme's own variables: the pywal names steam-colors.py also writes are for a theme
    # that reads them, and have no business on every Steam window's root.
    block = {k: v for k, v in block.items() if k in stock and _NAME.match(k) and _VALUE.match(v)}
    acc = load_accent()
    cache = acc.load_cache()
    if cache:            # Steam's own blues/greens/tinted greys: the variables the scanned stylesheet reads
        block.update({k: v for k, v in acc.variables(cache["rules"], bg, fg, colors[1], sc.main_bg_base(stock)).items()
                      if _NAME.match(k) and _VALUE.match(v)})
    return block


def script_for(block):
    """The expression run in every window: the colours as inline properties on the document root,
    then (visible windows only) two painted frames."""
    return ("(async()=>{const r=document.documentElement.style,c=%s;"
            "for(const k in c)r.setProperty(k,c[k]);"
            "if(!document.hidden)await Promise.race([new Promise(a=>requestAnimationFrame(()=>requestAnimationFrame(a))),"
            "new Promise(a=>setTimeout(a,%d))]);return 1})()" % (json.dumps(block), PAINT_CAP_MS))


def inject_script(css):
    """Put the static stylesheet in a window as <style id=quicktest-steam>. Done by `scan` only: it
    doesn't depend on the palette, and Quick CSS carries it into every window loaded later."""
    return ("(()=>{let st=document.getElementById('quicktest-steam');"
            "if(!st){st=document.createElement('style');st.id='quicktest-steam';document.head.appendChild(st)}"
            "if(st.textContent!==%s)st.textContent=%s;return 1})()" % (json.dumps(css), json.dumps(css)))


def push_page(target, script):
    ws = WS(target["webSocketDebuggerUrl"])
    try:
        m = ws.call("Runtime.evaluate", expression=script, awaitPromise=True, returnByValue=True)
        return "exceptionDetails" not in m.get("result", {}) and "error" not in m
    finally:
        ws.close()


def cmd_push(colors_json):
    if not enabled():
        print("steam-live: not enabled (steam-live.py enable) — nothing pushed")
        return NOTHING_TO_DO
    try:
        block = theme_block(colors_json)
    except (OSError, ValueError) as e:
        print("steam-live: palette unreadable: %s" % e, file=sys.stderr)
        return FAILED
    if block is None:
        print("steam-live: %s isn't the active Millennium theme — nothing to push" % THEME)
        return NOTHING_TO_DO
    try:
        found = pages()
    except OSError:
        print("steam-live: debug port %d not open (Steam closed, not enabled, or started before the flag existed)" % PORT)
        return PORT_CLOSED
    if not found:
        print("steam-live: the port answers but lists no windows")
        return PORT_CLOSED
    if load_accent().load_cache() is None:
        print("steam-live: no scan yet — Steam's own blues/greens stay as they are (run: steam-live.py scan)")
    script = script_for(block)
    ok = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(8, len(found))) as pool:
        for t, fut in [(t, pool.submit(push_page, t, script)) for t in found]:
            try:
                ok += bool(fut.result())
            except Exception as e:      # one window going away mid-push must not fail the rest
                print("steam-live: skipped %r: %s" % (t.get("title", "")[:30], e), file=sys.stderr)
    print("steam-live: pushed %d colours into %d of %d window(s)" % (len(block), ok, len(found)))
    return OK if ok else FAILED


SIG_JS = ("(()=>{let n=0;for(const ss of document.styleSheets){if(ss.ownerNode&&['quicktest-steam','MillenniumQuickCss']"
          ".includes(ss.ownerNode.id))continue;try{n+=ss.cssRules.length}catch(e){}}return n})()")


def _eval(target, expression):
    ws = WS(target["webSocketDebuggerUrl"], timeout=10.0)
    try:
        m = ws.call("Runtime.evaluate", expression=expression, returnByValue=True, awaitPromise=True)
        if "exceptionDetails" in m.get("result", {}):
            raise RuntimeError(m["result"]["exceptionDetails"].get("text", "page threw"))
        return m["result"]["result"].get("value")
    finally:
        ws.close()


def _main_page():
    for t in pages():
        if t.get("title") == "Steam":
            return t
    return None


def theme_vars():
    sc = load_steam_colors()
    theme_dir = next((d for d in sc.default_theme_dirs() if os.path.isdir(d)), "")
    return sc.theme_stock(theme_dir)


def cmd_scan(colors_json, if_needed):
    if not enabled():
        print("steam-live: not enabled (steam-live.py enable) — nothing scanned")
        return NOTHING_TO_DO
    acc = load_accent()
    try:
        main = _main_page()
    except OSError:
        print("steam-live: debug port %d not open — nothing to scan" % PORT)
        return PORT_CLOSED
    if main is None:
        print("steam-live: the main Steam window isn't listed — nothing to scan")
        return PORT_CLOSED
    cache = acc.load_cache()
    if if_needed and cache is not None:
        try:
            if int(_eval(main, SIG_JS)) == cache.get("sig"):
                print("steam-live: Steam's stylesheets are unchanged since the last scan")
                return OK
        except (OSError, ValueError, RuntimeError) as e:
            print("steam-live: couldn't read the stylesheet signature: %s" % e, file=sys.stderr)
            return FAILED
    with open(os.path.join(HERE, "steam-scan.js"), encoding="utf-8") as f:
        js = f.read()
    # Every Steam UI window: the sheets differ a little between them (menus, overlay, friends).
    # A popup's target URL is `about:blank?createflags=…` until it navigates, so the main window
    # looks like that too — what is NOT Steam's own UI is a web page (the store) or a data: URL.
    ui = [t for t in pages() if not t.get("url", "").startswith(("http://", "https://", "data:"))
          or t.get("url", "").startswith("https://steamloopback.host")]
    rules, seen, sig = [], set(), None
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(8, max(1, len(ui)))) as pool:
        for t, fut in [(t, pool.submit(_eval, t, js)) for t in ui]:
            try:
                data = json.loads(fut.result())
            except Exception as e:
                print("steam-live: skipped %r: %s" % (t.get("title", "")[:30], e), file=sys.stderr)
                continue
            if t is main or t.get("id") == main.get("id"):
                sig = data["sig"]
            for r in data["rules"]:
                key = (tuple(r["w"]), r["s"], r["p"], r["v"])
                if key not in seen:
                    seen.add(key)
                    rules.append(r)
    # The variables the THEME reads (--color-dark …) and ours are set by the shell; a stylesheet rule
    # declaring one is the theme's own default, and recolouring it would override what is pushed.
    owned = set(load_steam_colors().STOCK) | set(theme_vars())
    rules = [r for r in rules if not (r["p"] in owned or r["p"].startswith("--qs-"))]
    if sig is None or not rules:
        print("steam-live: the scan found nothing to save")
        return FAILED
    acc.save_cache(sig, rules)
    print("steam-live: scanned %d window(s): %d declarations in Steam's cool colours" % (len(ui), len(rules)))
    css = acc.rules_css(rules)
    try:        # for the next launch, and any window opened later
        if acc.write_quickcss(os.path.join(os.path.dirname(millennium_config()), "quick.css"), css):
            print("steam-live: Quick CSS updated (%d KB)" % (len(css) // 1024))
    except OSError as e:
        print("steam-live: Quick CSS not written: %s" % e, file=sys.stderr)
    script = inject_script(css)             # and now, in every open window
    done = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(8, max(1, len(ui)))) as pool:
        for fut in [pool.submit(_eval, t, script) for t in ui]:        # Steam's UI only: not the store's web page
            try:
                done += bool(fut.result())
            except Exception as e:
                print("steam-live: a window refused the stylesheet: %s" % e, file=sys.stderr)
    print("steam-live: stylesheet injected into %d window(s)" % done)
    return cmd_push(colors_json)     # the palette's half: the variables it reads


def cmd_probe():
    if not enabled():
        return NOTHING_TO_DO
    try:
        return OK if pages(0.4) else PORT_CLOSED
    except OSError:
        return PORT_CLOSED


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    cmd = argv[0] if argv else "status"
    if cmd == "push":
        colors = argv[1] if len(argv) > 1 else os.path.join(
            os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "wal", "colors.json")
        return cmd_push(colors)
    if cmd == "scan":
        rest = argv[1:]
        colors = next((a for a in rest if not a.startswith("--")), os.path.join(
            os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "wal", "colors.json"))
        return cmd_scan(colors, "--if-needed" in rest)
    if cmd == "probe":
        return cmd_probe()
    if cmd == "flag":
        put_flag()
        return OK
    if cmd == "enable":
        os.makedirs(state_dir(), exist_ok=True)
        open(marker(), "a").close()
        flagged = put_flag()
        print("steam-live: enabled. While Steam runs, 127.0.0.1:%d accepts connections from any program "
              "running as you and can drive Steam's UI. %s" % (PORT, "Flag placed; restart Steam once."
              if flagged else "Steam isn't installed here yet; the flag is placed when it is."))
        return OK
    if cmd == "disable":
        for p in (marker(), flag_path()):
            if p and os.path.exists(p):
                os.unlink(p)
        print("steam-live: disabled; Steam closes the port the next time it starts.")
        return OK
    if cmd == "status":
        print("enabled: %s\nsteam:   %s\nflag:    %s\nport:    %s" % (
            enabled(), steam_root(), bool(flag_path() and os.path.exists(flag_path())),
            "open" if cmd_probe() == OK else "closed"))
        return OK
    print("usage: steam-live.py push [colors.json] | scan [--if-needed] | probe | flag | enable | disable | status", file=sys.stderr)
    return FAILED


if __name__ == "__main__":
    sys.exit(main())
