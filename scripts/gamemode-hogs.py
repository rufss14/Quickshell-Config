#!/usr/bin/env python3
"""
gamemode-hogs.py — which open windows hold the most memory, for the Game Mode panel's
"close these first" list.

    gamemode-hogs.py [N]     → one JSON object on stdout, always; exit 0

out  {"ok":true,"apps":[{"pid":4121,"class":"firefox","title":"…","addrs":["0x…"],
                         "rssMb":2310.4,"procs":19}, …]}      biggest first, at most N (4)
err  {"ok":false,"error":"…"}

A window's cost is its whole process tree (a browser's renderers count — they are what
holds the RAM), summed over every window of the same process, so a browser with six
windows is one row with six addresses. Games (steam_app_*, gamescope, Proton) are never
listed: they are what the memory is being freed FOR.

Reads /proc and asks `hyprctl -j clients` once. Closing is NOT done here — the panel asks
each window to close politely (Hyprland's own close), so an app with unsaved work gets to
say so.

    python3 scripts/test-gamemode-hogs.py
"""
import importlib.util
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("proc_cost", os.path.join(HERE, "proc-cost.py"))
pc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pc)

GAME_CLASS = re.compile(r"^(steam_app_\d+|steam_proton|gamescope.*|.*\.exe)$")
ADDR = re.compile(r"^0x[0-9a-f]{1,16}$")


def hogs(clients, kids, rss_kb, limit=4):
    """clients: `hyprctl -j clients`; kids: pid → [child pids]; rss_kb: [pid] → kB."""
    by_pid = {}
    for c in clients if isinstance(clients, list) else []:
        if not isinstance(c, dict):
            continue
        pid = c.get("pid")
        cls = str(c.get("class") or "")
        addr = str(c.get("address") or "")
        if not isinstance(pid, int) or pid <= 0 or GAME_CLASS.match(cls) or not ADDR.match(addr):
            continue
        row = by_pid.setdefault(pid, {"pid": pid, "class": cls, "title": str(c.get("title") or ""), "addrs": []})
        row["addrs"].append(addr)
    out = []
    for pid, row in by_pid.items():
        members = pc.tree(pid, kids)
        row["rssMb"] = round(rss_kb(members) / 1024, 1)
        row["procs"] = len(members)
        out.append(row)
    out.sort(key=lambda r: (-r["rssMb"], r["pid"]))
    return out[:max(0, limit)]


def main(argv):
    try:
        limit = int(argv[1]) if len(argv) > 1 else 4
        if not 0 < limit <= 20:
            raise ValueError
    except ValueError:
        print(json.dumps({"ok": False, "error": "usage: gamemode-hogs.py [N 1-20]"}))
        return 0
    try:
        raw = subprocess.run(["hyprctl", "-j", "clients"], capture_output=True, text=True, timeout=5).stdout
        clients = json.loads(raw)
    except (OSError, ValueError, subprocess.SubprocessError):
        print(json.dumps({"ok": False, "error": "hyprctl clients failed"}))
        return 0
    print(json.dumps({"ok": True, "apps": hogs(clients, pc.children_map(), pc.rss_kb, limit)}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
