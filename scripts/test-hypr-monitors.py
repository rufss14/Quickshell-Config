#!/usr/bin/env python3
"""scripts/hypr-monitors.py --write-spec / --print-spec: validation and the lines written.
Works on a temp copy of hypr/hardware.lua; never runs hyprctl."""
import json, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "hypr-monitors.py")
passed = failed = 0


def check(name, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print("FAIL %s\n      got  %r\n      want %r" % (name, got, want))


def run(args, stdin):
    p = subprocess.run([sys.executable, SCRIPT] + args, input=stdin, capture_output=True, text=True, timeout=10)
    return p.returncode, p.stdout


tmp = tempfile.mkdtemp(prefix="hypr-mon-test-")
hw = os.path.join(tmp, "hardware.lua")
shutil.copy(os.path.join(HERE, "..", "hypr", "hardware.lua"), hw)
before = open(hw).read()

good = [{"name": "DP-2", "width": 1920, "height": 1080, "refresh": 165.003, "x": 0, "y": 0, "scale": 1, "transform": 0, "vrr": True},
        {"name": "HDMI-A-1", "width": 1680, "height": 1050, "refresh": 59.95, "x": 1920, "y": 30, "scale": 1.25, "transform": 1, "vrr": False}]
rc, out = run(["--write-spec", hw], json.dumps(good))
check("write: ok", (rc, json.loads(out)), (0, {"ok": True, "lines": 2}))
after = open(hw).read()
check("write: DP-2 line", 'hl.monitor({ output = "DP-2", mode = "1920x1080@165", position = "0x0", scale = 1, vrr = 1 })' in after, True)
check("write: rotated, scaled", 'hl.monitor({ output = "HDMI-A-1", mode = "1680x1050@60", position = "1920x30", scale = 1.25, transform = 1 })' in after, True)
check("write: the generic line is gone", 'output = "", mode = "preferred"' in after, False)
check("write: the rest of the file is untouched", after.split("-- ── Input")[1] == before.split("-- ── Input")[1], True)
rc, _ = run(["--write-spec", hw], json.dumps(good))
check("write: idempotent", open(hw).read(), after)

for label, bad in [
    ("lua injection in a name", [dict(good[0], name='x" }) os.execute("id") --')]),
    ("string where a number goes", [dict(good[0], width="1920")]),
    ("out-of-range scale", [dict(good[0], scale=9)]),
    ("bool as a number", [dict(good[0], x=True)]),
    ("everything off", [{"name": "DP-2", "disabled": True}]),
    ("duplicate output", [good[0], good[0]]),
    ("not a list", {"name": "DP-2"}),
]:
    rc, out = run(["--write-spec", hw], json.dumps(bad))
    check("refused: " + label, (rc, json.loads(out)["ok"]), (2, False))
check("refusals left the file alone", open(hw).read(), after)

foreign = os.path.join(tmp, "mine.lua")
open(foreign, "w").write('hl.monitor({ output = "DP-1", mode = "preferred" })\n')
rc, out = run(["--write-spec", foreign], json.dumps(good))
check("refused: a file without the Monitors section", (rc, open(foreign).read()), (2, 'hl.monitor({ output = "DP-1", mode = "preferred" })\n'))

rc, out = run(["--print-spec"], json.dumps([good[0], {"name": "HDMI-A-1", "disabled": True}]))
check("print: lines only", out.strip().splitlines()[1], 'hl.monitor({ output = "HDMI-A-1", disabled = true })')

print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
