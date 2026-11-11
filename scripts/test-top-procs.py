#!/usr/bin/env python3
"""test-top-procs.py — scripts/top-procs.py: the stat parser and the ranking, on made-up
snapshots, then one real run. Safe: reads /proc.

    python3 scripts/test-top-procs.py
"""
import importlib.util
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tp", os.path.join(HERE, "top-procs.py"))
tp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tp)

passed = failed = 0
def check(name, ok):
    global passed, failed
    if ok: passed += 1
    else:
        failed += 1
        print("FAIL", name)

def stat(pid, comm, utime, stime):
    return f"{pid} ({comm}) S 1 1 1 0 -1 4194304 100 0 0 0 {utime} {stime} 0 0 20 0 1 0 100 1000 50"

check("plain name", tp.parse_stat(stat(5, "bash", 10, 4)) == ("bash", 14))
check("a name with a space", tp.parse_stat(stat(5, "Web Content", 7, 1)) == ("Web Content", 8))
check("a name with parentheses", tp.parse_stat(stat(5, "(sd-pam)", 1, 2)) == ("(sd-pam)", 3))
check("a name that ends in ') S'", tp.parse_stat(stat(5, "a) S 9 9", 3, 3)) == ("a) S 9 9", 6))
check("garbage", tp.parse_stat("nothing here") is None)
check("truncated", tp.parse_stat("5 (x) S 1 2") is None)

before = {1: ("firefox", 100, 1000), 2: ("firefox", 50, 500), 3: ("idle", 10, 10), 4: ("gone", 5, 5)}
after  = {1: ("firefox", 150, 1000), 2: ("firefox", 75, 600), 3: ("idle", 10, 10),
          5: ("fresh", 900, 4000),                    # started inside the window
          6: ("reused", 500, 20)}
before[6] = ("other", 0, 20)                          # the pid was someone else a moment ago
r = tp.rank(before, after, seconds=0.5, hz=100, page_kb=4, limit=5)
fx = next(x for x in r["cpu"] if x["name"] == "firefox")
check("grouped by name", fx["procs"] == 2)
check("cpu is percent of one core", fx["cpu"] == 150.0)          # 75 ticks / 100 Hz / 0.5 s
check("memory adds up", fx["mb"] == round(1600 * 4 / 1024, 1))
check("idle is not in the cpu list", all(x["name"] != "idle" for x in r["cpu"]))
check("a new process has no cpu yet", all(x["name"] != "fresh" for x in r["cpu"]))
check("a reused pid is not charged the old one's ticks", all(x["name"] != "reused" for x in r["cpu"]))
check("biggest first", r["mem"][0]["name"] == "fresh")
check("an ended process is gone", all(x["name"] != "gone" for x in r["mem"]))
check("limit", len(tp.rank(before, after, 0.5, 100, 4, limit=2)["mem"]) == 2)
check("zero window divides nothing", tp.rank(before, after, 0, 100, 4)["cpu"] == [])

out = json.loads(subprocess.run([sys.executable, os.path.join(HERE, "top-procs.py"), "3"],
                                capture_output=True, text=True, timeout=10).stdout)
check("a real run answers", out.get("ok") is True and 1 <= len(out["mem"]) <= 3)
check("a bad argument still answers", json.loads(subprocess.run(
    [sys.executable, os.path.join(HERE, "top-procs.py"), "x"], capture_output=True, text=True, timeout=10).stdout).get("ok") is True)

print(f"{'ok ' if not failed else 'FAIL'} {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
