#!/usr/bin/env python3
"""scripts/wifi-hidden.py: validation, the settings it sends, and its stdin/stdout
contract on bad input. Never touches NetworkManager (no case reaches D-Bus)."""
import importlib.util
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("wifi_hidden", os.path.join(HERE, "wifi-hidden.py"))
W = importlib.util.module_from_spec(spec)
spec.loader.exec_module(W)

passed = failed = 0


def check(name, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print("FAIL %s\n      got  %r\n      want %r" % (name, got, want))


check("valid: name + passphrase", W.validate("Home", "correcthorse"), "")
check("valid: open network", W.validate("Cafe", ""), "")
check("valid: 64 hex digits is a raw key", W.validate("Home", "a" * 64), "")
check("bad: empty name", W.validate("", "correcthorse") != "", True)
check("bad: name over 32 bytes", W.validate("x" * 33, "") != "", True)
check("bad: 32 bytes of multibyte is fine", W.validate("é" * 16, ""), "")
check("bad: 17 two-byte chars is 34 bytes", W.validate("é" * 17, "") != "", True)
check("bad: short passphrase", W.validate("Home", "short") != "", True)
check("bad: 64 chars that aren't hex", W.validate("Home", "z" * 64) != "", True)
check("bad: not strings", W.validate(None, "x") != "", True)

s = W.settings("Home", "correcthorse")
check("settings: hidden", s["802-11-wireless"]["hidden"], True)
check("settings: ssid as bytes", s["802-11-wireless"]["ssid"], list(b"Home"))
check("settings: wpa-psk", s["802-11-wireless-security"], {"key-mgmt": "wpa-psk", "psk": "correcthorse"})
check("settings: linked security", s["802-11-wireless"]["security"], "802-11-wireless-security")
o = W.settings("Cafe", "")
check("settings: open has no security", "802-11-wireless-security" in o or "security" in o["802-11-wireless"], False)


def run(stdin):
    p = subprocess.run([sys.executable, os.path.join(HERE, "wifi-hidden.py")], input=stdin,
                       capture_output=True, text=True, timeout=10)
    return p.returncode, json.loads(p.stdout or "{}")


check("cli: garbage stdin", run("not json\n"), (2, {"ok": False, "error": "bad request"}))
rc, out = run(json.dumps({"ssid": "Home", "psk": "short"}) + "\n")
check("cli: invalid psk refused before any D-Bus", (rc, out["ok"]), (2, False))

print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
