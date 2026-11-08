#!/usr/bin/env python3
"""test-proc-cost.py — scripts/proc-cost.py on processes this test owns. Safe: reads /proc.

    python3 scripts/test-proc-cost.py
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import importlib.util
spec = importlib.util.spec_from_file_location("pc", os.path.join(HERE, "proc-cost.py"))
pc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pc)

passed = failed = 0
def check(name, ok):
    global passed, failed
    if ok: passed += 1
    else:
        failed += 1
        print("FAIL", name)

# A busy child under a sleeping parent: the parent's tree must carry the child's CPU.
parent = subprocess.Popen([sys.executable, "-c",
    "import subprocess,sys,time; c=subprocess.Popen([sys.executable,'-c','while True: pass']); time.sleep(30)"])
try:
    import time; time.sleep(0.4)
    r = pc.measure(parent.pid)
    check("ok", r.get("ok") is True)
    check("tree includes the child", r.get("procs", 0) >= 2)
    check("busy child counts (>40% of a core)", r.get("cpu", 0) > 40)
    check("memory is read", r.get("rssMb", 0) > 1)
finally:
    for p in pc.tree(parent.pid, pc.children_map())[::-1]:
        try: os.kill(p, 9)
        except OSError: pass
    parent.wait()

check("gone pid", pc.measure(4194300).get("ok") is False)
out = subprocess.run([sys.executable, os.path.join(HERE, "proc-cost.py"), "1; rm -rf /"], capture_output=True, text=True)
check("junk argument refused, exit 0", out.returncode == 0 and json.loads(out.stdout)["ok"] is False)
check("cycle-safe tree", pc.tree(1, {1: [2], 2: [1]}) == [1, 2])

print(f"{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
