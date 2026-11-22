#!/usr/bin/env python3
"""test-app-gradient.py: scripts/app-gradient.py in a sandbox (temp XDG dirs, nothing real touched).

It adds a managed block to each app's file when the gradient is on, leaves the rest of the file alone, adds
it exactly once however often it runs, and takes it out when the gradient is off.
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
fails = 0


def ok(name, cond):
    global fails
    if not cond:
        fails += 1
        print("  FAIL ", name)


def run(env):
    subprocess.run([sys.executable, "-I", os.path.join(HERE, "app-gradient.py"), "all"], env=env, check=True)


with tempfile.TemporaryDirectory() as d:
    cfg, state, cache = (os.path.join(d, x) for x in ("c", "s", "ca"))
    files = {
        "kitty": os.path.join(cfg, "kitty", "current-theme.conf"),
        "gtk4": os.path.join(cfg, "gtk-4.0", "gtk.css"),
        "discord": os.path.join(cfg, "Vencord", "themes", "quicktest.theme.css"),
    }
    seed = {"kitty": "background #1a0a2e\nforeground #fff\n", "gtk4": "@define-color a #fff;\n", "discord": ":root{--x:1}\n"}
    for k, p in files.items():
        os.makedirs(os.path.dirname(p))
        open(p, "w").write(seed[k])
    os.makedirs(os.path.join(state, "quicktest"))
    os.makedirs(os.path.join(cache, "wal"))
    json.dump({"special": {"background": "#1a0a2e"}}, open(os.path.join(cache, "wal", "colors.json"), "w"))
    gj = os.path.join(state, "quicktest", "gradient.json")
    env = dict(os.environ, XDG_CONFIG_HOME=cfg, XDG_STATE_HOME=state, XDG_CACHE_HOME=cache, PATH="/usr/bin:/bin")

    json.dump({"on": True, "angle": 70, "mid": 0.5, "strength": 1, "stops": ["#4a4ff0", "#f03fa0", "#ff9a3c"]}, open(gj, "w"))
    run(env)
    run(env)
    for k, p in files.items():
        t = open(p).read()
        ok(k + ": block added once", t.count("quicktest gradient (managed)") == 1)
        ok(k + ": the file's own text is kept", t.startswith(seed[k].splitlines()[0]))
    ok("kitty: the image exists", os.path.getsize(os.path.join(cache, "quicktest", "kitty-gradient.png")) > 1000)
    ok("gtk4: css angle is the shell's + 90", "linear-gradient(160deg," in open(files["gtk4"]).read())

    json.dump({"on": False, "stops": []}, open(gj, "w"))
    run(env)
    for k, p in files.items():
        ok(k + ": block removed", open(p).read().strip() == seed[k].strip())

    # a damaged or hostile document changes nothing
    open(gj, "w").write('{"on": true, "stops": ["red; } body { display:none", "#112233"]}')
    run(env)
    for k, p in files.items():
        ok(k + ": a bad stop is refused", open(p).read().strip() == seed[k].strip())

print("passed" if not fails else "%d failed" % fails)
sys.exit(1 if fails else 0)
