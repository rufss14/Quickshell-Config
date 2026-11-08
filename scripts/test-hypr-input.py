#!/usr/bin/env python3
"""hypr-config.py set-input: the pointer/touchpad keys, read by table and inserted when
absent. Runs on temp copies of hypr/ (and of ~/.config/hypr/hardware.lua when present);
each result must pass `luac -p` (inside the script) and, when Hyprland is installed,
`Hyprland --verify-config`."""
import json, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
SCRIPT = os.path.join(HERE, "hypr-config.py")
passed = failed = 0


def check(name, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print("FAIL %s\n      got  %r\n      want %r" % (name, got, want))


def run(d, *args):
    p = subprocess.run([sys.executable, SCRIPT] + list(args) + ["--dir", d], capture_output=True, text=True, timeout=30)
    return json.loads(p.stdout)


sources = [("repo", os.path.join(REPO, "hypr", "hardware.lua"))]
live = os.path.expanduser("~/.config/hypr/hardware.lua")
if os.path.exists(live):
    sources.append(("installed", live))

for label, hw in sources:
    d = tempfile.mkdtemp(prefix="hypr-input-test-")
    for f in os.listdir(os.path.join(REPO, "hypr")):
        if f.endswith(".lua"):
            shutil.copy(os.path.join(REPO, "hypr", f), d)
    shutil.copy(hw, os.path.join(d, "hardware.lua"))
    before_ns = run(d, "read")["input"]["natural_scroll"]["value"]

    steps = [("tap_to_click", "false", False), ("disable_while_typing", "false", False),
             ("touchpad_scroll_factor", "0.5", 0.5), ("mouse_scroll_factor", "2", 2.0),
             ("accel_profile", "flat", "flat"), ("left_handed", "true", True),
             ("clickfinger_behavior", "true", True), ("tap_and_drag", "false", False),
             ("tap_to_click", "true", True), ("accel_profile", "adaptive", "adaptive")]
    for name, val, want in steps:
        r = run(d, "set-input", "--name", name, "--value", val)
        check("%s: set %s=%s ok" % (label, name, val), r.get("ok"), True)
        if r.get("ok"):
            check("%s: %s reads back" % (label, name), r["data"]["pointer"][name]["value"], want)
    data = run(d, "read")
    check("%s: two scroll factors stay apart" % label,
          (data["pointer"]["mouse_scroll_factor"]["value"], data["pointer"]["touchpad_scroll_factor"]["value"]), (2.0, 0.5))
    check("%s: touchpad natural_scroll untouched" % label, data["input"]["natural_scroll"]["value"], before_ns)
    for name, val in [("accel_profile", 'x"); os.execute("id'), ("accel_profile", ""), ("mouse_scroll_factor", "99"),
                      ("tap_to_click_typo", "true"), ("mouse_scroll_factor", "abc")]:
        check("%s: refused %s=%r" % (label, name, val), run(d, "set-input", "--name", name, "--value", val).get("ok"), False)
    if shutil.which("Hyprland"):
        v = subprocess.run(["Hyprland", "--verify-config", "-c", os.path.join(d, "hyprland.lua")],
                           capture_output=True, text=True, timeout=30)
        out = v.stdout + v.stderr
        check("%s: Hyprland --verify-config" % label, "config ok" in out, True)
        if "config ok" not in out: print(out[-600:])
    shutil.rmtree(d)

print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
