#!/usr/bin/env python3
"""palette-prefetch.py must leave EXACTLY the cache entry `wal -i` would.

    python3 scripts/test-palette-prefetch.py

Hermetic: generated images, a temp XDG_CACHE_HOME (its own schemes cache), nothing under
~/.cache touched. The real `wal -i` runs into a second temp cache; the scheme files the
two leave must have the same names and bytes, so an apply finds the prefetched one.
"""
import filecmp
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


def main():
    try:
        from PIL import Image
    except ImportError:
        print("SKIP: Pillow not installed"); return 0
    if not shutil.which("wal"):
        print("SKIP: pywal not installed"); return 0

    tmp = tempfile.mkdtemp(prefix="prefetch-test-")
    try:
        imgs = []
        for n, (a, b) in enumerate([(3, 5), (11, 2)]):
            p = os.path.join(tmp, "pic %d.png" % n)        # a space, as real names have
            im = Image.new("RGB", (120, 80))
            im.putdata([((x * a) % 256, (y * b) % 256, ((x + y) * 7) % 256) for y in range(80) for x in range(120)])
            im.save(p)
            imgs.append(p)
        gif = os.path.join(tmp, "anim.gif")
        Image.new("RGB", (10, 10)).save(gif)
        bad = os.path.join(tmp, "bad.png")
        open(bad, "w").write("nope")

        home = os.path.join(tmp, "cacheA")
        env = dict(os.environ, XDG_CACHE_HOME=home)
        env.pop("PYWAL_CACHE_DIR", None)
        feed = "\n".join(imgs + [gif, bad, os.path.join(tmp, "missing.png")]) + "\n"
        for light in (False, True):
            args = [sys.executable, os.path.join(HERE, "palette-prefetch.py")] + (["--light"] if light else [])
            r = subprocess.run(args, input=feed, env=env, capture_output=True, text=True, timeout=120)
            mode = "light" if light else "dark"
            check(mode + ": exits 0 past a bad image, a gif and a missing file", r.returncode == 0, r.stderr[-300:])
            check(mode + ": extracted both pictures", r.stdout.count("extracted ") == 2, r.stdout)
            r2 = subprocess.run(args, input=feed, env=env, capture_output=True, text=True, timeout=60)
            check(mode + ": a second pass extracts nothing", r2.stdout.count("extracted ") == 0, r2.stdout)

        # The same pictures through the real CLI, into a cache of its own.
        ref = os.path.join(tmp, "cacheB")
        for light in (False, True):
            for p in imgs:
                subprocess.run(["wal", "-i", p, "-n", "-s", "-t", "-e"] + (["-l"] if light else []),
                               env=dict(env, PYWAL_CACHE_DIR=ref), capture_output=True, check=True, timeout=60)
        a = os.path.join(home, "wal", "schemes")
        b = os.path.join(ref, "schemes")
        na, nb = sorted(os.listdir(a)), sorted(os.listdir(b))
        check("same cache entries as `wal -i` (names)", na == nb and len(na) == 4, (na, nb))
        check("same cache entries as `wal -i` (bytes)",
              all(filecmp.cmp(os.path.join(a, n), os.path.join(b, n), shallow=False) for n in na if n in nb))
        check("wrote nothing but schemes", sorted(os.listdir(os.path.join(home, "wal"))) == ["schemes"],
              os.listdir(os.path.join(home, "wal")))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print("%d passed" % passed + (", %d FAILED" % failed if failed else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
