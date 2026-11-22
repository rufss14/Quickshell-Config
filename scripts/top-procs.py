#!/usr/bin/env python3
"""
top-procs.py — what is using the machine right now, for the System stats panel's "Busiest" tile.

    top-procs.py [N]     → one JSON object on stdout, always; exit 0 (N = rows per list, 1..200, default 5)

out  {"ok":true,"cpu":[{"name":"firefox","cpu":41.2,"mb":2310.4,"procs":19,"pids":[…]}, …],   busiest first
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


# How many pids a row keeps for the Tasks tab to end. A browser with more renderers is ended by its first 64.
PIDS_PER_ROW = 64


def read_io(path):
    """Bytes this process has moved to and from storage (read_bytes + write_bytes from /proc/<pid>/io). 0 when
    /proc does not let us read it (another user's process), so the disk column simply stays quiet for it."""
    try:
        with open(path) as f:
            vals = dict(line.split(":", 1) for line in f if ":" in line)
        return int(vals["read_bytes"]) + int(vals["write_bytes"])
    except (OSError, KeyError, ValueError):
        return 0


def read_gpu(pid_dir):
    """GPU time this process has used, in ns, summed over its engines (drm-engine-gfx, -compute, … in
    /proc/<pid>/fdinfo for each open /dev/dri file). One DRM client can be open on several fds, so each
    drm-client-id counts once. 0 for a process that does not use the GPU, one we cannot look into, or a driver
    that does not report it (amdgpu and recent Intel do; NVIDIA's proprietary driver does not)."""
    seen = {}
    try:
        fds = os.listdir(pid_dir + "/fd")
    except OSError:
        return 0
    for fd in fds:
        try:
            if not os.readlink(f"{pid_dir}/fd/{fd}").startswith("/dev/dri/"):
                continue
            with open(f"{pid_dir}/fdinfo/{fd}") as f:
                client, ns = None, 0
                for line in f:
                    k, _, v = line.partition(":")
                    if k == "drm-client-id":
                        client = v.strip()
                    elif k.startswith("drm-engine-") and not k.startswith("drm-engine-capacity"):
                        ns += int(v.split()[0])
        except (OSError, ValueError, IndexError):
            continue
        if client is not None:
            seen[client] = max(seen.get(client, 0), ns)
    return sum(seen.values())


def snapshot(proc="/proc"):
    """pid → (name, ticks, rss_pages, storage_bytes, gpu_ns) for every process with memory of its own."""
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
            out[int(d)] = (st[0], st[1], rss, read_io(f"{proc}/{d}/io"), read_gpu(f"{proc}/{d}"))
    return out


# How many of a row's own processes the Tasks tab can expand to show, by their own CPU and memory.
MEMBERS_PER_ROW = 16


def rank(before, after, seconds, hz, page_kb, limit=5):
    """Two snapshots → {"cpu": rows, "mem": rows}. A pid only in `after` started inside the
    window: its memory counts, its CPU and disk don't (there is nothing to subtract from).
    A row: name, cpu (% of one core), mb, procs, disk (MB/s), gpu (% of the GPU's time), pids (up to PIDS_PER_ROW), members (the
    busiest MEMBERS_PER_ROW processes, each {pid, cpu, mb, disk})."""
    groups = {}
    for pid, v in after.items():
        name, ticks, rss = v[0], v[1], v[2]
        io = v[3] if len(v) > 3 else 0
        gpu = v[4] if len(v) > 4 else 0
        g = groups.setdefault(name, {"name": name, "ticks": 0, "kb": 0, "procs": 0, "io": 0, "gpu": 0, "pids": [], "members": []})
        if len(g["pids"]) < PIDS_PER_ROW:
            g["pids"].append(pid)
        prev = before.get(pid)
        d_ticks = d_io = d_gpu = 0
        if prev and prev[0] == name:
            d_ticks = max(0, ticks - prev[1])
            d_io = max(0, io - (prev[3] if len(prev) > 3 else 0))
            d_gpu = max(0, gpu - (prev[4] if len(prev) > 4 else 0))
        g["ticks"] += d_ticks
        g["io"] += d_io
        g["gpu"] += d_gpu
        g["kb"] += rss * page_kb
        g["procs"] += 1
        g["members"].append({"pid": pid, "ticks": d_ticks, "kb": rss * page_kb, "io": d_io, "gpu": d_gpu})

    def rate(ticks):
        return round(ticks / hz / seconds * 100, 1) if seconds > 0 else 0.0

    def gpu_pct(ns):
        return min(100.0, round(ns / 1e9 / seconds * 100, 1)) if seconds > 0 else 0.0

    def mbps(nbytes):
        return round(nbytes / 1048576 / seconds, 2) if seconds > 0 else 0.0

    rows = []
    for g in groups.values():
        members = sorted(g["members"], key=lambda m: (-m["ticks"], -m["kb"], m["pid"]))[:MEMBERS_PER_ROW]
        rows.append({"name": g["name"], "cpu": rate(g["ticks"]), "mb": round(g["kb"] / 1024, 1),
                     "procs": g["procs"], "disk": mbps(g["io"]), "gpu": gpu_pct(g["gpu"]), "pids": sorted(g["pids"]),
                     "members": [{"pid": m["pid"], "cpu": rate(m["ticks"]), "mb": round(m["kb"] / 1024, 1),
                                  "disk": mbps(m["io"]), "gpu": gpu_pct(m["gpu"])} for m in members]})
    by_cpu = sorted(rows, key=lambda r: (-r["cpu"], -r["mb"], r["name"]))
    by_mem = sorted(rows, key=lambda r: (-r["mb"], -r["cpu"], r["name"]))
    return {"cpu": [r for r in by_cpu if r["cpu"] > 0][:limit], "mem": by_mem[:limit]}


def main(argv):
    try:
        limit = max(1, min(200, int(argv[1]))) if len(argv) > 1 else 5
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
