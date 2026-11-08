#!/usr/bin/env python3
"""
proc-cost.py — what one window costs: its process and everything it started.

    proc-cost.py <pid>      → one JSON object on stdout, always; exit 0

out  {"ok":true,"cpu":12.5,"rssMb":840.2,"procs":7}
     cpu    percent of ONE core, summed over the tree, measured over 0.5 s (a browser's
            renderers count — they're what's busy, not the window's own process)
     rssMb  resident memory, summed (shared pages count once per process, so a tree of
            many processes reads a little high — the same as top's RES column summed)
err  {"ok":false,"error":"…"}

services/ProcCost.qml runs this every couple of seconds while the overview's window
inspector shows a window. Reads /proc only; the pid is an integer argument, never text
put into a command.
"""
import json
import os
import sys
import time


def children_map():
    kids = {}
    for d in os.listdir("/proc"):
        if not d.isdigit():
            continue
        try:
            with open(f"/proc/{d}/stat") as f:
                ppid = int(f.read().rsplit(")", 1)[1].split()[1])
        except (OSError, ValueError, IndexError):
            continue
        kids.setdefault(ppid, []).append(int(d))
    return kids


def tree(root, kids):
    out, stack, seen = [], [root], set()
    while stack:
        p = stack.pop()
        if p in seen:
            continue
        seen.add(p)
        out.append(p)
        stack.extend(kids.get(p, []))
    return out


def ticks(pids):
    total = 0
    for p in pids:
        try:
            with open(f"/proc/{p}/stat") as f:
                fields = f.read().rsplit(")", 1)[1].split()
            total += int(fields[11]) + int(fields[12])   # utime, stime (fields 14 and 15)
        except (OSError, ValueError, IndexError):
            pass
    return total


def rss_kb(pids):
    total = 0
    for p in pids:
        try:
            with open(f"/proc/{p}/status") as f:
                for line in f:
                    if line.startswith("VmRSS:"):
                        total += int(line.split()[1])
                        break
        except (OSError, ValueError, IndexError):
            pass
    return total


def measure(pid, window=0.5):
    if not os.path.exists(f"/proc/{pid}"):
        return {"ok": False, "error": "gone"}
    pids = tree(pid, children_map())
    t0, w0 = ticks(pids), time.monotonic()
    time.sleep(window)
    t1, w1 = ticks(pids), time.monotonic()
    hz = os.sysconf("SC_CLK_TCK")
    cpu = max(0.0, (t1 - t0) / hz / max(1e-6, w1 - w0) * 100)
    return {"ok": True, "cpu": round(cpu, 1), "rssMb": round(rss_kb(pids) / 1024, 1), "procs": len(pids)}


def main(argv):
    try:
        pid = int(argv[1])
        if not 0 < pid < 4194305:
            raise ValueError
    except (IndexError, ValueError):
        print(json.dumps({"ok": False, "error": "usage: proc-cost.py <pid>"}))
        return 0
    print(json.dumps(measure(pid)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
