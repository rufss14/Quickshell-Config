#!/usr/bin/env python3
"""stage-palette.py must produce EXACTLY what the old five-process pipeline did.

    python3 scripts/test-stage-palette.py

The old way, replayed with the real `wal` CLI: `wal -i … -n -s -t -e [-l]`, the
corrections, merge-overrides.py, `wal --theme`. The new way: one stage-palette.py.
Every file both write is compared byte for byte. Hermetic: generated images, temp
cache dirs with their own (cold) schemes cache, nothing under ~/.cache touched.
Needs pywal and Pillow (both already dependencies of this shell).
"""
import filecmp
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
passed = failed = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
    else:
        failed += 1
        print("FAIL", name, detail)


def run(cmd, cache, **kw):
    env = dict(os.environ, PYWAL_CACHE_DIR=cache)
    return subprocess.run(cmd, env=env, capture_output=True, text=True, **kw)


def old_way(img, cache, light=False, blackpoint=False, overrides=None, saved=None, base=None):
    os.makedirs(cache, exist_ok=True)
    cj = os.path.join(cache, "colors.json")
    if base:
        shutil.copy(base, cj)
    if saved:
        run([sys.executable, os.path.join(HERE, "wal-from-json.py"), saved, cj], cache, check=True)
    else:
        run(["wal", "-i", img, "-n", "-s", "-t", "-e"] + (["-l"] if light else []), cache, check=True)
        d = json.load(open(cj))
        if blackpoint and not light:
            d["special"]["background"] = "#000000"
            d["colors"]["color0"] = "#000000"
            d["colors"]["color8"] = "#444444"
        if light:
            sys.path.insert(0, HERE)
            spec = __import__("importlib.util").util.spec_from_file_location("sp", os.path.join(HERE, "stage-palette.py"))
            sp = __import__("importlib.util").util.module_from_spec(spec)
            spec.loader.exec_module(sp)
            sp.lightfix(d)          # the same arithmetic, moved verbatim
        json.dump(d, open(cj, "w"), indent=4)
    if overrides:
        run([sys.executable, os.path.join(HERE, "merge-overrides.py"), overrides, cj], cache, check=True)
    run(["wal", "--theme", cj, "-n", "-s", "-t", "-e"], cache, check=True)
    return cache


def new_way(img, stage, light=False, blackpoint=False, overrides=None, saved=None, base=None):
    os.makedirs(stage, exist_ok=True)
    out = os.path.join(stage, "out")
    cmd = [sys.executable, os.path.join(HERE, "stage-palette.py"), "--out", out]
    if base:
        cmd += ["--from", base]
    if img:
        cmd += ["--image", img]
    if light:
        cmd += ["--light"]
    if blackpoint:
        cmd += ["--blackpoint"]
    if saved:
        cmd += ["--saved", saved]
    if overrides:
        cmd += ["--overrides", overrides, "--held-exit"]
    r = run(cmd, stage)
    return out, r


def compare(name, a, b):
    skip = {"schemes", "last_used_theme", "wal", "colors.json.tmp"}
    names = sorted(set(os.listdir(a)) - skip)
    missing = [n for n in names if not os.path.exists(os.path.join(b, n))]
    check(name + ": every old file exists", not missing, missing[:5])
    diff = [n for n in names if os.path.isfile(os.path.join(a, n)) and os.path.exists(os.path.join(b, n))
            and not filecmp.cmp(os.path.join(a, n), os.path.join(b, n), shallow=False)]
    check(name + ": every file identical", not diff, diff[:5])
    check(name + ": renders the full template set", len(names) > 40, len(names))


def main():
    try:
        from PIL import Image
    except ImportError:
        print("SKIP: Pillow not installed"); return 0
    if not shutil.which("wal"):
        print("SKIP: pywal not installed"); return 0

    tmp = tempfile.mkdtemp(prefix="stage-palette-test-")
    try:
        img = os.path.join(tmp, "pic.png")
        im = Image.new("RGB", (160, 90))
        im.putdata([((x * 3) % 256, (y * 5) % 256, ((x + y) * 7) % 256) for y in range(90) for x in range(160)])
        im.save(img)

        ovr = os.path.join(tmp, "ovr.json")
        json.dump({"colors": {"color4": "#123456", "nope": "#000000"}, "special": {"cursor": "red"}}, open(ovr, "w"))

        for label, kw in [("dark", {}), ("light", {"light": True}), ("blackpoint", {"blackpoint": True}),
                          ("overrides", {"overrides": ovr})]:
            a = old_way(img, os.path.join(tmp, "old-" + label), **kw)
            b, r = new_way(img, os.path.join(tmp, "new-" + label), **kw)
            check(label + ": exits 0", r.returncode == 0, r.stderr[-300:])
            check(label + ": reports steps", "STEP=render|ok|" in r.stdout, r.stdout)
            compare(label, a, b)

        # A saved palette on top of the live one (scheme path shape), then overrides.
        base = os.path.join(tmp, "old-dark", "colors.json")
        saved = os.path.join(tmp, "saved.json")
        json.dump({"special": {"background": "#101010", "foreground": "#eeeeee"},
                   "colors": {"color%d" % i: "#%02x%02x%02x" % (i * 9, 40, 200 - i * 7) for i in range(16)}},
                  open(saved, "w"))
        a = old_way(None, os.path.join(tmp, "old-saved"), saved=saved, base=base, overrides=ovr)
        b, r = new_way(None, os.path.join(tmp, "new-saved"), saved=saved, base=base, overrides=ovr)
        check("saved: exits 0", r.returncode == 0, r.stderr[-300:])
        compare("saved", a, b)

        # The scheme path: the live palette with overrides merged.
        b, r = new_way(None, os.path.join(tmp, "new-scheme"), base=base, overrides=ovr)
        d = json.load(open(os.path.join(b, "colors.json")))
        check("scheme: override landed", d["colors"]["color4"] == "#123456")
        check("scheme: junk override skipped", "nope" not in d["colors"] and d["special"]["cursor"] != "red")

        # Every slot held: exit 10 before any work.
        full = os.path.join(tmp, "full.json")
        json.dump({"special": {"background": "#000000", "foreground": "#ffffff"},
                   "colors": {"color%d" % i: "#111111" for i in range(16)}}, open(full, "w"))
        _, r = new_way(img, os.path.join(tmp, "new-held"), overrides=full)
        check("held: exit 10", r.returncode == 10, r.returncode)
        check("held: nothing rendered", not os.path.exists(os.path.join(tmp, "new-held", "out", "colors.json")))

        # No image and no base: a clean failure, not a traceback.
        _, r = new_way(None, os.path.join(tmp, "new-none"))
        check("nothing to start from: exit 1", r.returncode == 1 and "STEP=palette|fail|" in r.stdout, r.stdout)

        # A broken image fails cleanly too.
        bad = os.path.join(tmp, "bad.png")
        open(bad, "w").write("not an image")
        _, r = new_way(bad, os.path.join(tmp, "new-bad"))
        check("bad image: exit 1", r.returncode == 1 and "STEP=palette|fail|" in r.stdout, r.stdout + r.stderr[-200:])
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print("%d passed" % passed + (", %d FAILED" % failed if failed else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
