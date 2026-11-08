#!/usr/bin/env python3
"""Does writing the credentials file take effect without a restart?"""
import os, sys, json, socket, struct, subprocess, threading, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # derived, not literal: this config is published
tmp = tempfile.mkdtemp(prefix="setup-")
run_dir, cfg_dir, cache_dir = (os.path.join(tmp, d) for d in ("run", "cfg", "cache"))
for d in (run_dir, os.path.join(cfg_dir, "quicktest"), os.path.join(cache_dir, "quicktest")):
    os.makedirs(d, exist_ok=True)
with open(os.path.join(cache_dir, "quicktest", "discord-token.json"), "w") as f:
    json.dump({"access_token": "t", "expires_at": time.time() + 99999}, f)

# No credentials only means "wait for setup" when the shared sign-in is switched off;
# otherwise the helper connects as StreamKit (covered by test-discord-shared.py).
with open(os.path.join(cfg_dir, "quicktest", "discord-rpc.json"), "w") as f:
    json.dump({"sharedApp": False}, f)

SOCK = os.path.join(run_dir, "discord-ipc-0")
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(SOCK); srv.listen(1)

env = dict(os.environ, XDG_RUNTIME_DIR=run_dir, XDG_CONFIG_HOME=cfg_dir,
           XDG_CACHE_HOME=cache_dir, XDG_STATE_HOME=os.path.join(cfg_dir, "..", "state"))
proc = subprocess.Popen([sys.executable, os.path.join(ROOT, "scripts/discord-rpc.py")],
                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE, env=env, text=True, bufsize=1)

lines = []
threading.Thread(target=lambda: [lines.append(l.strip()) or print("[out]", l.strip())
                                 for l in proc.stdout], daemon=True).start()
threading.Thread(target=lambda: [print("[err]", l.rstrip()) for l in proc.stderr],
                 daemon=True).start()

connected = threading.Event()
def accept():
    conn, _ = srv.accept()
    connected.set()
    buf = b""
    while True:
        try:
            c = conn.recv(65536)
        except OSError:
            return
        if not c:
            return
        buf += c
        while len(buf) >= 8:
            op, ln = struct.unpack("<II", buf[:8])
            if len(buf) < 8 + ln: break
            msg = json.loads(buf[8:8+ln].decode()); buf = buf[8+ln:]
            body = json.dumps({"cmd": "DISPATCH", "evt": "READY", "data": {"v": 1}}
                              if op == 0 else
                              {"cmd": msg.get("cmd"), "data": {}, "nonce": msg.get("nonce")}).encode()
            conn.sendall(struct.pack("<II", 1, len(body)) + body)
threading.Thread(target=accept, daemon=True).start()

time.sleep(1.5)
assert any('"no-credentials"' in l for l in lines), "expected no-credentials announcement"
assert not connected.is_set(), "should not have connected without credentials"
print("  ok  announced no-credentials, did not connect")

print("\n=== writing credentials file (no restart) ===")
# Where the helper reads it now: it moved the first file there at start (qspaths.py).
with open(os.path.join(cfg_dir, "..", "state", "quicktest", "secrets", "discord-rpc.json"), "w") as f:
    json.dump({"clientId": "1", "clientSecret": "s",
               "keys": {"camera": "ctrl+shift+v", "screenshare": "ctrl+shift+g"}}, f)

if not connected.wait(timeout=15):
    print("FAIL: helper never connected after credentials appeared"); proc.kill(); sys.exit(1)
print("  ok  picked up credentials and connected — no restart needed")

time.sleep(1.0)
assert any('"t":"config"' in l and "ctrl+shift+g" in l for l in lines), \
    "keys should be forwarded to the shell"
print("  ok  forwarded keybinds to the shell")
assert not any("clientSecret" in l or '"s"' == l for l in lines), "secret must never hit stdout"
print("  ok  client secret never appeared on stdout")

proc.stdin.close()
proc.wait(timeout=5)
print("  ok  clean exit (rc=%s)" % proc.returncode)
print("\nPASSED")
