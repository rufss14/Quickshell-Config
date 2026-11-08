#!/usr/bin/env python3
# ── test-generate-mangohud-config.py ─────────────────────────────────────────
# Tests for generate-mangohud-config. Fully mocked and SAFE TO RUN: every case
# runs the script with XDG_CONFIG_HOME / XDG_CACHE_HOME pointed at a throwaway
# temp dir, so the real ~/.config/MangoHud is never touched. Same contract as
# test-discord-rpc.py.
#
#   python3 scripts/test-generate-mangohud-config.py
#
# The point worth testing is the surgical merge: switching a preset or refreshing
# colours must rewrite ONLY the two marked regions and leave every other line —
# including ones added after them — byte-for-byte.
# ─────────────────────────────────────────────────────────────────────────────
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "generate-mangohud-config")

PALETTE = {
    "special": {"background": "#101015", "foreground": "#e0e0e8", "cursor": "#e0e0e8"},
    "colors": {"color%d" % i: "#%02x2030" % (i * 16) for i in range(16)},
}

PASS = 0
FAIL = 0


def check(name, cond):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("  ok   %s" % name)
    else:
        FAIL += 1
        print("  FAIL %s" % name)


def run(tmp, *args):
    env = dict(os.environ, XDG_CONFIG_HOME=os.path.join(tmp, "config"),
               XDG_CACHE_HOME=os.path.join(tmp, "cache"))
    r = subprocess.run([sys.executable, SCRIPT, *args], env=env,
                       capture_output=True, text=True)
    return r


def setup(tmp):
    wal_dir = os.path.join(tmp, "cache", "wal")
    os.makedirs(wal_dir, exist_ok=True)
    json.dump(PALETTE, open(os.path.join(wal_dir, "colors.json"), "w"))


def conf_path(tmp):
    return os.path.join(tmp, "config", "MangoHud", "MangoHud.conf")


def test_fresh():
    with tempfile.TemporaryDirectory(prefix="mhc-") as tmp:
        setup(tmp)
        r = run(tmp)
        check("fresh: exits 0", r.returncode == 0)
        text = open(conf_path(tmp)).read()
        check("fresh: has colours region", "### quicktest:colors" in text)
        check("fresh: seeds the default preset", "### quicktest:preset=full" in text)
        check("fresh: keybind header present", "toggle_hud=Shift_R+F12" in text)
        check("fresh: colours are bare RRGGBB (no '#')",
              "\ngpu_color=" in text and "gpu_color=#" not in text)


def test_no_palette():
    with tempfile.TemporaryDirectory(prefix="mhc-") as tmp:
        r = run(tmp)
        check("no palette: exits 1", r.returncode == 1)
        check("no palette: says why", "no palette" in r.stderr)


def test_surgical_merge():
    with tempfile.TemporaryDirectory(prefix="mhc-") as tmp:
        setup(tmp)
        run(tmp)  # seed
        # A person edits: changes position, adds a key AFTER the managed regions.
        with open(conf_path(tmp), "a") as f:
            f.write("position=top-right\nmy_pet_option=42\n")
        before = open(conf_path(tmp)).read()

        r = run(tmp, "--preset", "compact")
        check("merge: preset switch exits 0", r.returncode == 0)
        after = open(conf_path(tmp)).read()

        check("merge: user line after regions kept", "my_pet_option=42" in after)
        check("merge: user 'position=top-right' kept", "position=top-right" in after)
        check("merge: preset marker now says compact", "### quicktest:preset=compact" in after)
        check("merge: 'swap' (full-only metric) gone", "\nswap\n" not in after)
        check("merge: exactly one colours region", after.count("### quicktest:colors —") == 1)
        check("merge: exactly one preset region", after.count("### quicktest:preset=") == 1)
        check("merge: header keybind survived", "reload_cfg=Shift_L+F4" in after)
        # Everything the person wrote is still there and in order.
        check("merge: tail block intact",
              after.rstrip().endswith("position=top-right\nmy_pet_option=42"))
        check("merge: only regions changed",
              before.replace(_region(before, "colors"), "").replace(_region(before, "preset"), "")
              == after.replace(_region(after, "colors"), "").replace(_region(after, "preset"), ""))


def test_idempotent():
    with tempfile.TemporaryDirectory(prefix="mhc-") as tmp:
        setup(tmp)
        run(tmp, "--preset", "fps")
        a = open(conf_path(tmp)).read()
        run(tmp)               # colours-only refresh keeps the chosen preset
        b = open(conf_path(tmp)).read()
        check("idempotent: colours refresh keeps preset=fps", "### quicktest:preset=fps" in b)
        check("idempotent: no drift on re-run", a == b)


def test_bad_args():
    with tempfile.TemporaryDirectory(prefix="mhc-") as tmp:
        setup(tmp)
        check("bad preset name: exits 2", run(tmp, "--preset", "ultra").returncode == 2)
        check("stray arg: exits 2", run(tmp, "wat").returncode == 2)


def _region(text, kind):
    """Extract a marked region including its markers, or '' if absent."""
    begin = "### quicktest:%s" % kind
    lines = text.split("\n")
    out, inside = [], False
    for ln in lines:
        if ln.strip().startswith(begin):
            inside = True
        if inside:
            out.append(ln)
        if inside and ln.strip().startswith("### end quicktest:%s" % kind):
            break
    return "\n".join(out)


def main():
    for t in (test_fresh, test_no_palette, test_surgical_merge,
              test_idempotent, test_bad_args):
        print(t.__name__)
        t()
    print("\n%d passed, %d failed" % (PASS, FAIL))
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
