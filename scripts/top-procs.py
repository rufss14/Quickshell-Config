#!/usr/bin/env python3
"""
top-procs.py — what is using the machine right now, for the System stats panel's "Busiest" tile.

    top-procs.py [N]     → one JSON object on stdout, always; exit 0

out  {"ok":true,"cpu":[{"name":"firefox","cpu":41.2,"mb":2310.4,"procs":19}, …],   busiest first
              "mem":[…same rows, biggest first…]}                                  at most N (5) each
err  {"ok":false,"error":"…"}

Processes are grouped BY NAME: a browser is one row with its renderers added up, because that is
the thing you would close. `cpu` is percent of ONE core over a half-second window (so 250 means two
and a half cores), `mb` is resident memory. Kernel threads (no memory of their own) are left out.

Reads /proc twice, half a second apart. Nothing is written and nothing is signalled.

    python3 scripts/test-top-procs.py
"""
import json
import os
import sys
import time


def parse_stat(text):
    """One /proc/<pid>/stat → (name, ticks). The name sits in parentheses and may itself hold
    spaces and parentheses ("(Web Content)", "(sd-pam)", "((sd-pam))"), so it runs to the LAST ')'."""
    a, b = text.find("("), text.rfind(")")
    if a < 0 or b < a:
        return None
    rest = text[b + 2:].split()
    try:
        # After the name: state is field 3, utime 14 and stime 15 (1-based) → rest[11], rest[12].
        return text[a + 1:b], int(rest[11]) + int(rest[12])
    except (IndexError, ValueError):
        return None


def snapshot(proc="/proc"):
    """pid → (name, ticks, rss_pages) for every process with memory of its own."""
    out = {}
    for d in os.listdir(proc):
        if not d.isdigit():
            continue
        try:
            with open(f"{proc}/{d}/stat") as f:
                st = parse_stat(f.read())
            with open(f"{proc}/{d}/statm") as f:
                rss = int(f.read().split()[1])
        except (OSError, IndexError, ValueError):
            continue          # it ended between the listing and the read
        if st and rss > 0:
            out[int(d)] = (st[0], st[1], rss)
    return out


def rank(before, after, seconds, hz, page_kb, limit=5):
    """Two snapshots → {"cpu": rows, "mem": rows}. A pid only in `after` started inside the
    window: its memory counts, its CPU doesn't (there is nothing to subtract from)."""
    groups = {}
    for pid, (name, ticks, rss) in after.items():
        g = groups.setdefault(name, {"name": name, "ticks": 0, "kb": 0, "procs": 0})
        prev = before.get(pid)
        if prev and prev[0] == name:
            g["ticks"] += max(0, ticks - prev[1])
        g["kb"] += rss * page_kb
        g["procs"] += 1
    rows = [{"name": g["name"],
             "cpu": round(g["ticks"] / hz / seconds * 100, 1) if seconds > 0 else 0.0,
             "mb": round(g["kb"] / 1024, 1),
             "procs": g["procs"]} for g in groups.values()]
    by_cpu = sorted(rows, key=lambda r: (-r["cpu"], -r["mb"], r["name"]))
    by_mem = sorted(rows, key=lambda r: (-r["mb"], -r["cpu"], r["name"]))
    return {"cpu": [r for r in by_cpu if r["cpu"] > 0][:limit], "mem": by_mem[:limit]}


def main(argv):
    try:
        limit = max(1, min(20, int(argv[1]))) if len(argv) > 1 else 5
    except ValueError:
        limit = 5
    try:
        a = snapshot()
        t0 = time.monotonic()
        time.sleep(0.5)
        b = snapshot()
        out = rank(a, b, time.monotonic() - t0, os.sysconf("SC_CLK_TCK"),
                   os.sysconf("SC_PAGE_SIZE") // 1024, limit)
        out["ok"] = True
    except OSError as e:
        out = {"ok": False, "error": str(e)}
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
