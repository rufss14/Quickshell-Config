#!/usr/bin/env python3
"""bench-ab.py — does this change make the shell cheaper? Alternating A/B in throwaway shells.

    scripts/bench-ab.py base nowave,cavaBg=false
    scripts/bench-ab.py --rounds 7 new old,ref=HEAD~1
    scripts/bench-ab.py --set wallFx=false --warm 25 --measure 45 a b,wpeFps=30

A variant is NAME followed by comma-separated settings:
    KEY=JSON     a Config preference, e.g. cavaBg=false  wpeFps=30  cavaBgStyle="bars"
    ref=GITREF   run the COMMITTED code at that ref (git archive), e.g. ref=HEAD~1
    tree=PATH    run a copy of the repo you made yourself
No ref/tree = this working tree. `--set KEY=JSON` applies to every variant.

Each round starts every variant once, in a rotated order (so slow drift in the machine does not
always favour the same one), lets it settle for --warm seconds, then counts CPU time for --measure
seconds. The table shows the MEDIAN and the min–max over the rounds. A single run is noise: the
spread between rounds of the SAME variant is the size of difference you cannot trust (use --rounds 5+).

What decides whether numbers compare: the same thing playing. The audio state (`playerctl status`) is
recorded at both ends of each round and a round where it changed is dropped. Nothing is played for you.
Run it with the desktop otherwise idle: the live shell and its renderer share the machine.

Config comes from your live preferences (read, never written); the throwaway saves into a scratch
XDG_STATE_HOME. Needs: quickshell, a Wayland session. `playerctl` and amdgpu/intel fdinfo are optional.
"""
import argparse
import json
import os
import shutil
import statistics
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bench_lib as B  # noqa: E402


def parse_variant(text, common):
    name, *rest = text.split(",")
    cfg, tree, ref = dict(common), None, None
    for item in rest:
        k, _, v = item.partition("=")
        if k == "ref":
            ref = v
        elif k == "tree":
            tree = os.path.abspath(v)
        else:
            try:
                cfg[k] = json.loads(v)
            except ValueError:
                sys.exit(f"bench-ab: {name}: {item!r}: value is not JSON (quote strings: key=\"text\")")
    return {"name": name, "cfg": cfg, "tree": tree, "ref": ref}


def audio():
    try:
        return subprocess.run(["playerctl", "status"], capture_output=True, text=True, timeout=3).stdout.strip() or "none"
    except (OSError, subprocess.TimeoutExpired):
        return "?"


def one_round(v, base_cfg, scratch, warm, measure):
    cfg = dict(base_cfg, **v["cfg"])
    state = tempfile.mkdtemp(prefix=v["name"] + "-", dir=scratch)
    with B.Throwaway(tree=v["tree"], state=state, config=cfg) as t:
        time.sleep(warm)
        a0 = audio()
        s0 = B.snapshot(t.pid)
        busy = []
        end = time.time() + measure
        while time.time() < end:
            time.sleep(1)
            c = B.card_busy()
            if c is not None:
                busy.append(c)
        s1 = B.snapshot(t.pid)
        a1 = audio()
    d = B.diff(s0, s1)
    d["card"] = statistics.mean(busy) if busy else None
    d["audio"] = a0 if a0 == a1 else f"{a0}->{a1}"
    # A shell that died, or never finished starting, reads as a cheap one: refuse the round.
    d["alive"] = d["rss_mb"] > 0 and d["render"] > 0
    return d


def fmt(rows, key, digits=1):
    vals = [r[key] for r in rows if r.get(key) is not None]
    if not vals:
        return "—"
    return f"{statistics.median(vals):.{digits}f} ({min(vals):.{digits}f}–{max(vals):.{digits}f})"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("variants", nargs="+")
    ap.add_argument("--rounds", type=int, default=5)
    ap.add_argument("--warm", type=float, default=20, help="seconds to settle before counting (default 20)")
    ap.add_argument("--measure", type=float, default=30, help="seconds to count (default 30)")
    ap.add_argument("--set", action="append", default=[], metavar="KEY=JSON", help="a preference for every variant")
    ap.add_argument("--config", help="preferences to start from (default: your live config.json)")
    ap.add_argument("--json", help="also write every round to this file")
    a = ap.parse_args()

    common = {}
    for item in a.set:
        k, _, v = item.partition("=")
        common[k] = json.loads(v)
    variants = [parse_variant(t, common) for t in a.variants]
    names = [v["name"] for v in variants]
    if len(set(names)) != len(names):
        sys.exit("bench-ab: variant names must differ")
    base_cfg = B.live_config(a.config)
    if not base_cfg:
        print("bench-ab: no live config.json found — starting from defaults", file=sys.stderr)

    scratch = tempfile.mkdtemp(prefix="qs-bench-ab-")
    try:
        for v in variants:
            if v["ref"]:
                v["tree"] = B.export_ref(v["ref"], os.path.join(scratch, "tree-" + v["name"]))
            elif v["tree"] is None:
                v["tree"] = B.REPO
        results = {v["name"]: [] for v in variants}
        dropped = 0
        for r in range(a.rounds):
            order = variants[r % len(variants):] + variants[:r % len(variants)]
            for v in order:
                d = one_round(v, base_cfg, scratch, a.warm, a.measure)
                ok = "->" not in d["audio"] and d["alive"]
                print(f"round {r + 1}/{a.rounds}  {v['name']:<14} gui {d['gui']:5.1f}  render {d['render']:5.1f}  "
                      f"helpers {d['helpers']:5.1f}  gpu {d['gpu'] if d['gpu'] is None else round(d['gpu'], 1)}  "
                      f"audio {d['audio']}{'' if ok else '  (dropped: ' + ('shell not running)' if not d['alive'] else 'audio changed)')}", flush=True)
                if ok:
                    results[v["name"]].append(d)
                else:
                    dropped += 1
        print()
        print(f"{'variant':<14} {'n':>2}  {'gui':<20} {'render':<20} {'process':<20} {'helpers':<20} {'gpu(shell)':<18} {'card%':<16} rss MB")
        for n in names:
            rows = results[n]
            print(f"{n:<14} {len(rows):>2}  {fmt(rows, 'gui'):<20} {fmt(rows, 'render'):<20} {fmt(rows, 'process'):<20} "
                  f"{fmt(rows, 'helpers'):<20} {fmt(rows, 'gpu'):<18} {fmt(rows, 'card', 0):<16} {fmt(rows, 'rss_mb', 0)}")
        print("\npercent of one core (median, min–max over rounds); helpers = the shell's child processes; gpu = shell's gfx engine time")
        if dropped:
            print(f"{dropped} round(s) dropped: the audio state changed, or the shell had not started / had died")
        if a.json:
            with open(a.json, "w") as f:
                json.dump(results, f, indent=1)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


if __name__ == "__main__":
    main()
