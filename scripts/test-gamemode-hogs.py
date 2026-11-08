#!/usr/bin/env python3
"""test-gamemode-hogs.py — scripts/gamemode-hogs.py with a fake window list and fake memory. Safe: no /proc.

    python3 scripts/test-gamemode-hogs.py
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("gh", os.path.join(HERE, "gamemode-hogs.py"))
gh = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gh)

passed = failed = 0
def check(name, ok):
    global passed, failed
    if ok: passed += 1
    else:
        failed += 1
        print("FAIL", name)

def win(pid, cls, addr, title="t"):
    return {"pid": pid, "class": cls, "address": addr, "title": title}

# pid 10 (a browser) has children 11, 12; pid 20 is a terminal; pid 30 a game.
kids = {10: [11, 12], 20: [], 30: []}
kb = {10: 100 * 1024, 11: 900 * 1024, 12: 800 * 1024, 20: 50 * 1024, 30: 6000 * 1024, 40: 700 * 1024}
rss = lambda pids: sum(kb.get(p, 0) for p in pids)

clients = [
    win(10, "firefox", "0xa1"), win(10, "firefox", "0xa2"),
    win(20, "kitty", "0xb1"),
    win(30, "steam_app_730", "0xc1"),
    win(40, "code", "0xd1"),
]
out = gh.hogs(clients, kids, rss)
check("a process with two windows is one row", [r["pid"] for r in out].count(10) == 1)
check("the row carries both addresses", out[0]["addrs"] == ["0xa1", "0xa2"])
check("memory is the whole tree, biggest first", [r["pid"] for r in out] == [10, 40, 20])
check("tree size is summed in MB", out[0]["rssMb"] == 1800.0 and out[0]["procs"] == 3)
check("the game is never listed", all(r["pid"] != 30 for r in out))

check("the limit caps the list", len(gh.hogs(clients, kids, rss, 2)) == 2)
check("a bad pid or address is skipped",
      gh.hogs([win(0, "x", "0x1"), win(-1, "x", "0x2"), win("5", "x", "0x3"), win(5, "x", "nope"), win(5, "x", "0x4; rm")],
              {}, rss) == [])
check("proton, gamescope and .exe windows are games",
      gh.hogs([win(1, "gamescope", "0x1"), win(2, "steam_proton", "0x2"), win(3, "game.exe", "0x3")], {}, rss) == [])
check("junk input is an empty list", gh.hogs(None, {}, rss) == [] and gh.hogs([None, 3, "x"], {}, rss) == [])
check("a missing title is an empty string", gh.hogs([win(20, "kitty", "0xb1", None)], kids, rss)[0]["title"] == "")

print(f"gamemode-hogs: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
