#!/usr/bin/env python3
"""
test-darkreader-live.py — tests for scripts/darkreader-live.py.

    python3 scripts/test-darkreader-live.py

Safe: everything runs against temp dirs (XDG_* and HOME pointed at them) with a synthetic
xpi. The host test spawns the real script as a subprocess, the way Zen does, and talks to it
over its stdio and socket. It never touches a browser profile.
"""

import importlib.util
import json
import os
import struct
import subprocess
import sys
import tempfile
import time
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "darkreader-live.py")
spec = importlib.util.spec_from_file_location("drl", SCRIPT)
drl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(drl)

passed = failed = 0


def check(name, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {name}\n  got  {got!r}\n  want {want!r}")


def raises(name, fn, exc):
    global passed, failed
    try:
        fn()
    except exc:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {name}: no {exc.__name__}")


DARK = {"special": {"background": "#0C1A1B", "foreground": "#c2c5c6"},
        "colors": {"color0": "#000000", "color1": "#8D73AB", "color7": "#ffffff"}}

# ── palette → theme ──────────────────────────────────────────────────────────
check("dark palette: bg is the palette's own (Zen's sidebar/top bar)", drl.theme_from_palette(DARK), {
    "darkSchemeBackgroundColor": drl.tame("#0c1a1b"), "darkSchemeTextColor": "#c2c5c6", "selectionColor": "#8d73ab"})
light = {"special": {"background": "#f4f1ea", "foreground": "#222222"}, "colors": {"color1": "#aa3322"}}
check("light palette sets the light scheme", drl.theme_from_palette(light), {
    "lightSchemeBackgroundColor": "#f4f1ea", "lightSchemeTextColor": "#222222", "selectionColor": "#aa3322"})
check("falls back to color0/color7 without `special`", drl.theme_from_palette(
    {"colors": {"color0": "#101010", "color7": "#eeeeee", "color1": "#336699"}}), {
    "darkSchemeBackgroundColor": "#101010", "darkSchemeTextColor": "#eeeeee", "selectionColor": "#336699"})
raises("bad hex is refused", lambda: drl.theme_from_palette({"special": {"background": "red"}, "colors": {}}), ValueError)
raises("missing accent is refused", lambda: drl.theme_from_palette({"special": DARK["special"], "colors": {}}), ValueError)
check("tame caps a near-black saturated red (#0e0000 is 100% saturated)", drl.tame("#0e0000"), "#0a0404")
check("tame leaves greys alone", drl.tame("#1d1d1d"), "#1d1d1d")
check("tame leaves a muted colour alone", drl.tame("#172636"), "#172636")
r, g, b = (int(drl.tame("#ff0000")[i:i + 2], 16) for i in (1, 3, 5))
check("tame keeps the hue (a red stays red-dominant)", r > g == b, True)
check("tame is idempotent", drl.tame(drl.tame("#0e0000")), drl.tame("#0e0000"))
check("luminance black/white", (drl.luminance("#000000"), drl.luminance("#ffffff")), (0.0, 1.0))

# ── framing ──────────────────────────────────────────────────────────────────
f = drl.frame({"a": 1})
check("frame length prefix", struct.unpack("=I", f[:4])[0], len(f) - 4)
check("frame body", json.loads(f[4:]), {"a": 1})

# ── the xpi patch ────────────────────────────────────────────────────────────
BG = "x();\n            Messenger.init(_a.getMessengerAdapter());\n            y();\n"
MANIFEST = json.dumps({"version": "4.9.133", "permissions": ["storage", "tabs"]})


def make_xpi(path, bg=BG):
    with zipfile.ZipFile(path, "w") as z:
        z.writestr("manifest.json", MANIFEST)
        z.writestr("background/index.js", bg)
        z.writestr("META-INF/mozilla.rsa", "sig")
        z.writestr("ui/popup.html", "<html>")


def read_xpi(path):
    with zipfile.ZipFile(path) as z:
        return {n: z.read(n).decode() for n in z.namelist()}


with tempfile.TemporaryDirectory() as tmp:
    src, out = os.path.join(tmp, "dr.xpi"), os.path.join(tmp, "out", "patched.xpi")
    make_xpi(src)
    drl.build(src, out)
    got = read_xpi(out)
    manifest = json.loads(got["manifest.json"])
    check("permission added", manifest["permissions"], ["storage", "tabs", "nativeMessaging"])
    check("version bumped", manifest["version"], "4.9.133.1")
    check("signature stripped", [n for n in got if n.startswith("META-INF")], [])
    check("other files kept", got["ui/popup.html"], "<html>")
    js = got["background/index.js"]
    check("patch lands after the anchor", js.index("Messenger.init") < js.index("quicktest-live:begin") < js.index("y();"), True)
    check("patch body is the file", open(drl.PATCH_JS).read() in js, True)

    again = os.path.join(tmp, "again.xpi")
    drl.build(out, again)    # rebuild from an already-patched copy
    got2 = read_xpi(again)
    check("rebuild is idempotent: one patch", got2["background/index.js"].count("quicktest-live:begin"), 1)
    check("rebuild keeps the version", json.loads(got2["manifest.json"])["version"], "4.9.133.1")
    check("rebuild keeps permissions once", json.loads(got2["manifest.json"])["permissions"].count("nativeMessaging"), 1)

    bad = os.path.join(tmp, "bad.xpi")
    make_xpi(bad, bg="no anchor here")
    raises("a moved anchor fails loudly", lambda: drl.build(bad, os.path.join(tmp, "b.xpi")), SystemExit)
    make_xpi(bad, bg=BG + BG)
    raises("an ambiguous anchor fails loudly", lambda: drl.build(bad, os.path.join(tmp, "b.xpi")), SystemExit)

    # ── user.js ──────────────────────────────────────────────────────────────
    uj = os.path.join(tmp, "user.js")
    open(uj, "w").write('user_pref("mine", 1);\nuser_pref("xpinstall.signatures.required", true);\n')
    check("set_pref changes", drl.set_pref(uj, drl.SIGN_PREF, "false"), True)
    check("set_pref keeps the user's lines",
          open(uj).read(), 'user_pref("mine", 1);\nuser_pref("xpinstall.signatures.required", false);\n')
    check("set_pref is idempotent", drl.set_pref(uj, drl.SIGN_PREF, "false"), False)

# ── the host, end to end ─────────────────────────────────────────────────────


def read_msg(proc, timeout=5):
    """One framed message from the host's stdout, or None on timeout."""
    import select
    end = time.time() + timeout
    buf = b""

    def take(n):
        nonlocal buf
        while len(buf) < n:
            left = end - time.time()
            if left <= 0 or not select.select([proc.stdout], [], [], left)[0]:
                return None
            chunk = os.read(proc.stdout.fileno(), n - len(buf))
            if not chunk:
                return None
            buf += chunk
        data, buf = buf[:n], buf[n:]
        return data
    head = take(4)
    body = take(struct.unpack("=I", head)[0]) if head else None
    return json.loads(body) if body else None


with tempfile.TemporaryDirectory() as tmp:
    cache, run = os.path.join(tmp, "cache"), os.path.join(tmp, "run")
    os.makedirs(os.path.join(cache, "wal"))
    os.makedirs(run, mode=0o700)
    colors = os.path.join(cache, "wal", "colors.json")
    json.dump(DARK, open(colors, "w"))
    env = dict(os.environ, XDG_CACHE_HOME=cache, XDG_RUNTIME_DIR=run, HOME=tmp)
    push_cli = lambda cmd: subprocess.run([sys.executable, SCRIPT, cmd], env=env).returncode  # noqa: E731

    check("probe with no host", push_cli("probe"), 1)
    proc = subprocess.Popen([sys.executable, SCRIPT, "/m.json", drl.EXT_ID], env=env,
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE)
    first = read_msg(proc)
    check("host sends the palette on connect", first and first["theme"]["darkSchemeBackgroundColor"], "#0c1a1b")
    check("probe finds the host", push_cli("probe"), 0)

    json.dump({"special": {"background": "#112233", "foreground": "#ddeeff"}, "colors": {"color1": "#445566"}},
              open(colors, "w"))
    check("push succeeds", push_cli("push"), 0)
    second = read_msg(proc)
    check("push re-reads the palette", second and second["theme"]["darkSchemeBackgroundColor"], drl.tame("#112233"))

    open(colors, "w").write("{ not json")
    push_cli("push")
    check("a broken palette sends nothing", read_msg(proc, timeout=0.5), None)
    check("and the host survives it", proc.poll(), None)

    proc.stdin.close()   # the browser quitting
    check("host exits when the browser closes", proc.wait(timeout=5), 0)
    check("its socket is gone", [n for n in os.listdir(run) if n.endswith(".sock")], [])
    check("probe after exit", push_cli("probe"), 1)

print(f"{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
