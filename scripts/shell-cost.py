#!/usr/bin/env python3
"""shell-cost.py — what the RUNNING shell costs right now, by thread. Reads /proc only.

    scripts/shell-cost.py                      the live shell (pgrep), 5 s
    scripts/shell-cost.py 12345 10             that pid, 10 s
    scripts/shell-cost.py --json               one JSON object (what `framewatch cost` reads)

    gui      the main thread: every QML binding, handler and animation tick runs here
    render   the QSGRenderThreads summed: drawing and submitting, one thread per window
    other    the shell's remaining threads (Wayland, D-Bus, image loading, GC helpers)
    helpers  the shell's child processes (cava, music-pulse.py, wl-paste, ...), summed — top ones named
    gpu      the shell's own GPU time (drm-engine-gfx; None when the driver gives none)
Percent of ONE core. A thread or process that is not there at both ends of the interval counts 0.
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bench_lib as B  # noqa: E402
import time  # noqa: E402


def live_pid():
    for name in ("quickshell", "qs"):
        r = subprocess.run(["pgrep", "-x", name], capture_output=True, text=True)
        if r.stdout.split():
            return int(r.stdout.split()[0])
    return None


def main():
    args = [x for x in sys.argv[1:] if x != "--json"]
    as_json = "--json" in sys.argv[1:]
    pid = int(args[0]) if args else live_pid()
    secs = float(args[1]) if len(args) > 1 else 5.0
    if not pid:
        print(json.dumps({"ok": False, "error": "no running shell"}) if as_json else "shell-cost: no running shell")
        return 0 if as_json else 2
    try:
        a = B.snapshot(pid)
        time.sleep(secs)
        d = B.diff(a, B.snapshot(pid))
    except OSError as e:
        print(json.dumps({"ok": False, "error": str(e)}) if as_json else f"shell-cost: {e}")
        return 0 if as_json else 2
    top_threads = sorted(d["threads"].items(), key=lambda kv: -kv[1])[:6]
    top_helpers = sorted(d["helper_names"].items(), key=lambda kv: -kv[1])[:5]
    if as_json:
        print(json.dumps({"ok": True, "pid": pid, "seconds": round(d["seconds"], 1),
                          **{k: (round(d[k], 1) if d[k] is not None else None) for k in ("gui", "render", "other", "helpers", "gpu")},
                          "rssMb": d["rss_mb"],
                          "threads": {k: round(v, 1) for k, v in top_threads},
                          "helperNames": {k: round(v, 1) for k, v in top_helpers}}))
        return 0
    gpu = "n/a" if d["gpu"] is None else f"{d['gpu']:.1f}%"
    print(f"pid {pid}, {d['seconds']:.0f} s:  gui {d['gui']:.1f}%   render {d['render']:.1f}%   other {d['other']:.1f}%   "
          f"helpers {d['helpers']:.1f}%   gpu {gpu}   rss {d['rss_mb']} MB")
    print("  threads: " + ", ".join(f"{k} {v:.1f}" for k, v in top_threads if v >= 0.1))
    print("  helpers: " + (", ".join(f"{k} {v:.1f}" for k, v in top_helpers if v >= 0.1) or "none busy"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
