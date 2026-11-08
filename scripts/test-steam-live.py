#!/usr/bin/env python3
# ── test-steam-live.py ───────────────────────────────────────────────────────
# Tests for steam-live.py against a FAKE Chrome-DevTools server on a free local port.
# Fully local and SAFE TO RUN: no Steam, no real port 8080, and every XDG dir points at a temp
# dir, so neither the real Millennium config nor Steam's flag file is touched.
#
#   python3 scripts/test-steam-live.py
#
# The fake behaves like Chromium where it matters to the client: it sends an event the client
# didn't ask for BEFORE the reply, a ping, and a text message split into fragments.
# ─────────────────────────────────────────────────────────────────────────────
import base64
import hashlib
import json
import os
import socket
import struct
import subprocess
import sys
import tempfile
import threading
from importlib.machinery import SourceFileLoader

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "steam-live.py")
GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

PASS = 0
FAIL = 0


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
    else:
        FAIL += 1
        print("FAIL: %s %s" % (name, detail))


def frame(op, payload, fin=True):
    n = len(payload)
    head = bytearray([(0x80 if fin else 0) | op])
    if n < 126:
        head.append(n)
    elif n < 65536:
        head += bytes([126]) + struct.pack(">H", n)
    else:
        head += bytes([127]) + struct.pack(">Q", n)
    return bytes(head) + payload


class FakeCDP:
    """GET /json and a websocket per page. Records every Runtime.evaluate it receives."""

    def __init__(self, targets, reply=None):
        self.sock = socket.socket()
        self.sock.bind(("127.0.0.1", 0))
        self.sock.listen(8)
        self.port = self.sock.getsockname()[1]
        self.targets = targets
        self.reply = reply or (lambda m: {"result": {"result": {"type": "number", "value": 1}}})
        self.evals = []
        self.lock = threading.Lock()
        threading.Thread(target=self._accept, daemon=True).start()

    def listing(self):
        out = []
        for t in self.targets:
            t = dict(t)
            if t.get("webSocketDebuggerUrl") == "AUTO":
                t["webSocketDebuggerUrl"] = "ws://127.0.0.1:%d/devtools/page/%s" % (self.port, t["id"])
            out.append(t)
        return out

    def _accept(self):
        while True:
            try:
                c, _ = self.sock.accept()
            except OSError:
                return
            threading.Thread(target=self._serve, args=(c,), daemon=True).start()

    def _serve(self, c):
        try:
            buf = b""
            while b"\r\n\r\n" not in buf:
                d = c.recv(4096)
                if not d:
                    return
                buf += d
            head, rest = buf.split(b"\r\n\r\n", 1)
            req = head.decode().split("\r\n")
            if req[0].startswith("GET /json"):
                body = json.dumps(self.listing()).encode()
                c.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\n"
                          b"Connection: close\r\n\r\n" % len(body) + body)
                return
            key = [l.split(": ", 1)[1] for l in req if l.lower().startswith("sec-websocket-key")][0]
            acc = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest())
            c.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                      b"Sec-WebSocket-Accept: " + acc + b"\r\n\r\n")
            while True:
                while len(rest) < 2:
                    d = c.recv(65536)
                    if not d:
                        return
                    rest += d
                n = rest[1] & 0x7F
                off = 2
                if n == 126:
                    while len(rest) < 4:
                        rest += c.recv(65536)
                    n = struct.unpack(">H", rest[2:4])[0]
                    off = 4
                while len(rest) < off + 4 + n:
                    rest += c.recv(65536)
                mask = rest[off:off + 4]
                data = bytes(b ^ mask[i % 4] for i, b in enumerate(rest[off + 4:off + 4 + n]))
                rest = rest[off + 4 + n:]
                m = json.loads(data)
                with self.lock:
                    self.evals.append(m)
                reply = dict(self.reply(m), id=m["id"])
                payload = json.dumps(reply).encode()
                cut = len(payload) // 2
                c.sendall(frame(0x1, json.dumps({"method": "Runtime.executionContextCreated", "params": {}}).encode())
                          + frame(0x9, b"hi")                              # a ping the client must answer
                          + frame(0x1, payload[:cut], fin=False)           # then the reply, fragmented
                          + frame(0x0, payload[cut:]))
        except (OSError, IndexError, ValueError):
            pass
        finally:
            c.close()

    def close(self):
        self.sock.close()


def palette():
    colors = {"color%d" % i: "#%02x%02x%02x" % (i * 16, 255 - i * 16, 40 + i * 8) for i in range(16)}
    return {"special": {"background": "#0c1a1b", "foreground": "#c2c5c6", "cursor": "#c2c5c6"}, "colors": colors}


def run(args, env, port):
    e = dict(os.environ, STEAM_LIVE_PORT=str(port), **env)
    r = subprocess.run([sys.executable, SCRIPT] + args, env=e, capture_output=True, text=True, timeout=30)
    return r.returncode, r.stdout, r.stderr


with tempfile.TemporaryDirectory() as tmp:
    cfgdir = os.path.join(tmp, "config")
    os.makedirs(os.path.join(cfgdir, "millennium"))
    cfg = os.path.join(cfgdir, "millennium", "config.json")
    wal = os.path.join(tmp, "colors.json")
    json.dump(palette(), open(wal, "w"))

    def set_theme(name):
        json.dump({"themes": {"activeTheme": name}}, open(cfg, "w"))

    env = {"XDG_CONFIG_HOME": cfgdir, "XDG_DATA_HOME": os.path.join(tmp, "data"),
           "XDG_STATE_HOME": os.path.join(tmp, "state"), "XDG_CACHE_HOME": os.path.join(tmp, "cache"), "HOME": tmp}
    os.makedirs(os.path.join(tmp, "data", "Steam"))
    set_theme("simply-dark")
    mark = os.path.join(tmp, "state", "quicktest", "steam-live")

    def opt(on):
        if on:
            os.makedirs(os.path.dirname(mark), exist_ok=True)
            open(mark, "a").close()
        elif os.path.exists(mark):
            os.unlink(mark)

    opt(True)       # push and scan are opt-in too; the opt-in block below turns it off and on itself

    # ── a push reaches every PAGE, and only pages ────────────────────────────
    fake = FakeCDP([
        {"id": "A", "type": "page", "title": "Steam", "webSocketDebuggerUrl": "AUTO"},
        {"id": "B", "type": "page", "title": "Friends", "webSocketDebuggerUrl": "AUTO"},
        {"id": "S", "type": "service_worker", "title": "sw", "webSocketDebuggerUrl": "AUTO"},
    ])
    code, out, err = run(["push", wal], env, fake.port)
    check("push exits 0", code == 0, out + err)
    check("push reports both windows", "into 2 of 2 window(s)" in out, out)
    evals = [m for m in fake.evals if m.get("method") == "Runtime.evaluate"]
    check("one evaluate per page, none for the worker", len(evals) == 2, len(evals))
    p = evals[0]["params"] if evals else {}
    check("waits for the promise (paint) and returns by value", p.get("awaitPromise") is True and p.get("returnByValue") is True, p)
    expr = p.get("expression", "")
    check("sets the theme's own variables", "--color-dark" in expr and "--grey" in expr and "--white" in expr, expr[:200])
    check("not the pywal names", '"--color0"' not in expr and '"--background"' not in expr, expr[:200])
    check("values are plain #rrggbb", all(len(v) == 7 for v in __import__("re").findall(r'"(#[0-9a-f]{6})"', expr)))
    check("capped wait for a window that never paints", "setTimeout" in expr and "requestAnimationFrame" in expr)
    check("a hidden window is not waited on (no frames, throttled timers)", "if(!document.hidden)await" in expr, expr[-260:])

    # ── a bad window doesn't stop the rest ───────────────────────────────────
    fake2 = FakeCDP([
        {"id": "A", "type": "page", "title": "ok", "webSocketDebuggerUrl": "AUTO"},
        {"id": "X", "type": "page", "title": "elsewhere", "webSocketDebuggerUrl": "ws://10.1.2.3:8080/devtools/page/X"},
    ])
    code, out, err = run(["push", wal], env, fake2.port)
    check("a foreign debugger URL is refused, the rest pushed", code == 0 and "into 1 of 2" in out and "refusing" in err, (code, out, err))

    # ── the page says it threw ───────────────────────────────────────────────
    fake3 = FakeCDP([{"id": "A", "type": "page", "title": "t", "webSocketDebuggerUrl": "AUTO"}],
                    reply=lambda m: {"result": {"exceptionDetails": {"text": "boom"}}})
    code, out, err = run(["push", wal], env, fake3.port)
    check("an exception in the page is a failure", code == 2, (code, out, err))


    # ── scan: the stylesheet is read, cached, written to Quick CSS and injected ──
    OWNED = {"w": [], "s": ":root", "p": "--color-darker", "v": "\u00010\u0001", "c": [[28, 41, 42, 1, "#1c292a"]]}
    RULES = [{"w": [], "s": ".tab", "p": "border-bottom-color", "v": "\u00010\u0001", "c": [[26, 159, 255, 1, "#1a9fff"]]},
             {"w": [], "s": ".panel", "p": "background-color", "v": "\u00010\u0001", "c": [[34, 36, 42, 1, "#22242a"]]}]
    sig_now = {"n": 777}

    def scan_reply(m):
        e = m.get("params", {}).get("expression", "")
        if e.startswith("(()=>{let n=0"):
            return {"result": {"result": {"type": "number", "value": sig_now["n"]}}}
        if "JSON.stringify({ sig: sig" in e:
            return {"result": {"result": {"type": "string", "value": json.dumps({"sig": 777, "rules": RULES + [OWNED]})}}}
        return {"result": {"result": {"type": "number", "value": 1}}}

    fake4 = FakeCDP([
        {"id": "M", "type": "page", "title": "Steam", "url": "about:blank?createflags=18&minwidth=1010", "webSocketDebuggerUrl": "AUTO"},
        {"id": "U", "type": "page", "title": "Friends Root Menu", "url": "https://steamloopback.host/index.html?x=1", "webSocketDebuggerUrl": "AUTO"},
        {"id": "W", "type": "page", "title": "Store", "url": "https://store.steampowered.com/", "webSocketDebuggerUrl": "AUTO"},
        {"id": "D", "type": "page", "title": "data:text/html", "url": "data:text/html,<body>", "webSocketDebuggerUrl": "AUTO"},
    ], reply=scan_reply)
    exprs = lambda: [m.get("params", {}).get("expression", "") for m in fake4.evals if m.get("method") == "Runtime.evaluate"]
    code, out, err = run(["scan", wal], env, fake4.port)
    check("scan exits 0", code == 0, out + err)
    check("scan reads Steam's UI windows — about:blank popups included — not the store or a data: URL",
          sum("JSON.stringify({ sig: sig" in e for e in exprs()) == 2, [e[:40] for e in exprs()])
    state = os.path.join(tmp, "state", "quicktest", "steam-accent-rules.json")
    cached = json.load(open(state)) if os.path.exists(state) else {}
    check("the rules are cached with the main window's signature", cached.get("sig") == 777 and len(cached.get("rules", [])) == 2, cached.keys())
    check("a variable the theme owns (--color-darker) is never cached, whatever sheet declared it",
          not any(r["p"] == "--color-darker" for r in cached.get("rules", [])), [r["p"] for r in cached.get("rules", [])])
    qcss = os.path.join(cfgdir, "millennium", "quick.css")
    qtext = open(qcss).read() if os.path.exists(qcss) else ""
    check("Quick CSS gets the static stylesheet in a marked block", "quicktest-steam:begin" in qtext and "var(--qs-1a9fffff)" in qtext, qtext[:200])
    injected = [e for e in exprs() if "quicktest-steam" in e and "createElement" in e]
    check("the stylesheet is injected into Steam's UI windows only", len(injected) == 2, len(injected))
    pushed = [e for e in exprs() if "setProperty" in e]
    check("the palette's half goes in the same run, as variables", pushed and "--qs-1a9fffff" in pushed[0] and "--color-dark" in pushed[0], pushed[:1] and pushed[0][:120])
    check("…and the push no longer carries the stylesheet", pushed and "quicktest-steam" not in pushed[0] and len(pushed[0]) < 60000, len(pushed[0]) if pushed else 0)

    n = len(fake4.evals)
    code, out, _ = run(["scan", "--if-needed", wal], env, fake4.port)
    check("--if-needed: unchanged stylesheets → no rescan", code == 0 and "unchanged" in out and not any(
        "JSON.stringify({ sig: sig" in e for e in [m.get("params", {}).get("expression", "") for m in fake4.evals[n:]]), (code, out))
    sig_now["n"] = 999
    code, out, _ = run(["scan", "--if-needed", wal], env, fake4.port)
    check("--if-needed: changed stylesheets → rescanned", code == 0 and "scanned" in out, (code, out))

    # a later plain push re-sends only variables
    n = len(fake4.evals)
    run(["push", wal], env, fake4.port)
    later = [m.get("params", {}).get("expression", "") for m in fake4.evals[n:] if m.get("method") == "Runtime.evaluate"]
    check("a plain push after a scan sends variables and no stylesheet",
          later and all("--qs-1a9fffff" in e and "createElement" not in e for e in later), len(later))
    fake4.close()

    # ── nothing listening / wrong theme / bad palette ────────────────────────
    s = socket.socket(); s.bind(("127.0.0.1", 0)); dead = s.getsockname()[1]; s.close()
    code, out, _ = run(["push", wal], env, dead)
    check("port closed → exit 4", code == 4, (code, out))
    set_theme("Material-Theme")
    code, out, _ = run(["push", wal], env, fake.port)
    check("another active theme → exit 3, nothing pushed", code == 3, (code, out))
    set_theme("simply-dark")
    bad = os.path.join(tmp, "bad.json"); open(bad, "w").write("{nope")
    code, _, err = run(["push", bad], env, fake.port)
    check("unreadable palette → exit 2", code == 2, (code, err))
    n_before = len(fake.evals)
    run(["push", bad], env, fake.port)
    check("…and nothing was sent", len(fake.evals) == n_before)

    opt(False)
    n_ev = len(fake.evals)
    code, out, _ = run(["push", wal], env, fake.port)
    check("push refuses until opted in", code == 3 and "not enabled" in out, (code, out))
    code, out, _ = run(["scan", wal], env, fake.port)
    check("scan refuses until opted in", code == 3 and "not enabled" in out, (code, out))
    check("…and connected to nothing", len(fake.evals) == n_ev, len(fake.evals) - n_ev)

    # ── opt-in, the flag, probe ──────────────────────────────────────────────
    flag = os.path.join(tmp, "data", "Steam", ".cef-enable-remote-debugging")
    code, _, _ = run(["probe"], env, fake.port)
    check("probe before opting in → 3 even with a port up", code == 3, code)
    run(["flag"], env, fake.port)
    check("flag does nothing until opted in", not os.path.exists(flag))
    code, out, _ = run(["enable"], env, fake.port)
    check("enable places the flag and warns about the port", code == 0 and os.path.exists(flag) and "any program" in out, out)
    os.unlink(flag)
    run(["flag"], env, fake.port)
    check("flag puts it back once opted in", os.path.exists(flag))
    code, _, _ = run(["probe"], env, fake.port)
    check("probe: opted in and the port answers → 0", code == 0, code)
    code, _, _ = run(["probe"], env, dead)
    check("probe: port closed → 4", code == 4, code)
    code, _, _ = run(["disable"], env, fake.port)
    check("disable removes marker and flag", code == 0 and not os.path.exists(flag)
          and not os.path.exists(os.path.join(tmp, "state", "quicktest", "steam-live")))
    code, _, _ = run(["probe"], env, fake.port)
    check("probe after disabling → 3", code == 3, code)

    # ── Steam not installed: enable is still fine ────────────────────────────
    env2 = dict(env, XDG_DATA_HOME=os.path.join(tmp, "nodata"), HOME=os.path.join(tmp, "nohome"))
    code, out, _ = run(["enable"], env2, fake.port)
    check("enable without Steam installed doesn't fail", code == 0 and "isn't installed" in out, (code, out))

    for f in (fake, fake2, fake3):
        f.close()

print("%d passed, %d failed" % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
