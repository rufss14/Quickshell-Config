#!/usr/bin/env python3
"""test-gamemode-steam.py — scripts/gamemode-steam.py with fake windows and fake environments. Safe: no /proc.

    python3 scripts/test-gamemode-steam.py
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("gs", os.path.join(HERE, "gamemode-steam.py"))
gs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gs)

passed = failed = 0
def check(name, ok):
    global passed, failed
    if ok: passed += 1
    else:
        failed += 1
        print("FAIL", name)

# The Silksong environment, as read off the real process.
real = b"HOME=/home/u\0SteamAppId=1030300\0SteamGameId=1030300\0STEAM_COMPAT_APP_ID=1030300\0SteamOverlayGameId=1030300\0"
check("reads the app id (native game)", gs.app_id(real) == "1030300")
check("either key will do", gs.app_id(b"SteamGameId=730\0") == "730" and gs.app_id(b"SteamAppId=730\0") == "730")
check("an app id of 0 is nothing", gs.app_id(b"SteamAppId=0\0") == "")
check("a non-number is nothing", gs.app_id(b"SteamAppId=abc\0SteamGameId=\0") == "")
check("no Steam variables is nothing", gs.app_id(b"HOME=/x\0PATH=/bin\0") == "" and gs.app_id(b"") == "")
check("a longer variable that merely starts the same is not it", gs.app_id(b"SteamAppIdX=5\0") == "")

envs = {10: real, 20: b"HOME=/x\0", 30: b"SteamGameId=730\0"}
def win(pid, cls, addr, title="t"): return {"pid": pid, "class": cls, "address": addr, "title": title}
out = gs.games([win(10, "Hollow Knight Silksong", "0xa1"), win(20, "kitty", "0xb1"), win(30, "cs2", "0xc1"),
                win(40, "gone", "0xd1")], lambda p: envs.get(p, b""))
check("finds the games by environment, not class", [g["address"] for g in out] == ["0xa1", "0xc1"])
check("carries class, title and id", out[0] == {"address": "0xa1", "class": "Hollow Knight Silksong", "title": "t", "appId": "1030300"})
check("a bad pid or address is skipped",
      gs.games([win(0, "x", "0x1"), win(-1, "x", "0x2"), win("5", "x", "0x3"), win(5, "x", "nope")], lambda p: real) == [])
check("junk input is an empty list", gs.games(None) == [] and gs.games([None, 3, "x"]) == [])

print(f"gamemode-steam: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
