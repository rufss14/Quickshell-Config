#!/usr/bin/env python3
"""
gamemode-steam.py — which open windows are Steam games, however Steam started them.

    gamemode-steam.py        → one JSON object on stdout, always; exit 0

out  {"ok":true,"games":[{"address":"0x…","class":"Hollow Knight Silksong","title":"…","appId":"1030300"}]}
err  {"ok":false,"error":"…"}

Why not the window class: a Proton game wears `steam_app_<id>`, but a NATIVE Linux game wears whatever it
likes (Hollow Knight: Silksong is "Hollow Knight Silksong"), so the class missed it. Steam puts the game's
id in the environment of every game it launches — SteamAppId / SteamGameId, native or Proton, with or
without launch options — so that is what is read: /proc/<pid>/environ of each window's process. The Steam
client's own windows carry neither. Only this user's processes are readable; anything else is skipped.

    python3 scripts/test-gamemode-steam.py
"""
import json
import os
import re
import subprocess
import sys

ADDR = re.compile(r"^0x[0-9a-f]{1,16}$")
KEYS = (b"SteamGameId=", b"SteamAppId=")


def app_id(environ):
    """environ bytes (NUL-separated) → the Steam app id as a string, or ""."""
    vals = {}
    for item in environ.split(b"\0"):
        for k in KEYS:
            if item.startswith(k):
                vals[k] = item[len(k):].decode("ascii", "replace")
    for k in KEYS:
        v = vals.get(k, "")
        if v.isdigit() and v != "0":
            return v
    return ""


def read_environ(pid):
    try:
        with open(f"/proc/{pid}/environ", "rb") as f:
            return f.read()
    except OSError:
        return b""


def games(clients, environ_of=read_environ):
    out = []
    for c in clients if isinstance(clients, list) else []:
        if not isinstance(c, dict):
            continue
        pid, addr = c.get("pid"), str(c.get("address") or "")
        if not isinstance(pid, int) or pid <= 0 or not ADDR.match(addr):
            continue
        aid = app_id(environ_of(pid))
        if aid:
            out.append({"address": addr, "class": str(c.get("class") or ""),
                        "title": str(c.get("title") or ""), "appId": aid})
    return out


def main():
    try:
        clients = json.loads(subprocess.run(["hyprctl", "-j", "clients"], capture_output=True, text=True, timeout=5).stdout)
    except (OSError, ValueError, subprocess.SubprocessError):
        print(json.dumps({"ok": False, "error": "hyprctl clients failed"}))
        return 0
    print(json.dumps({"ok": True, "games": games(clients)}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
