#!/usr/bin/env python3
"""test-gamemode-art.py — scripts/gamemode-art.py against a fake Steam library in a temp dir. Safe: no network.

    python3 scripts/test-gamemode-art.py
"""
import importlib.util
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("ga", os.path.join(HERE, "gamemode-art.py"))
ga = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ga)

passed = failed = 0
def check(name, ok):
    global passed, failed
    if ok: passed += 1
    else:
        failed += 1
        print("FAIL", name)

def touch(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "wb").write(b"\xff\xd8x")

with tempfile.TemporaryDirectory() as t:
    steam = os.path.join(t, "Steam")
    lc = os.path.join(steam, "appcache", "librarycache", "1030300")
    touch(os.path.join(lc, "aaa", "library_capsule.jpg"))
    touch(os.path.join(lc, "bbb", "library_hero.jpg"))
    touch(os.path.join(lc, "ccc", "library_header.jpg"))
    touch(os.path.join(lc, "ddd.jpg"))            # a top-level jpg is an icon, never the picture
    cache = os.path.join(t, "cache")
    calls = []
    def fake(appid, dest):
        calls.append(appid); touch(dest); return dest

    # A Steam hit is COPIED into our cache and the copy is what comes back, so it outlives Steam's.
    made = []
    def fresh(): made.append(1); return os.path.join(t, "cache%d" % len(made))
    c1 = fresh()
    got = ga.find_art("1030300", [steam], c1, fake)
    check("a Steam hit is kept in our cache", got == os.path.join(c1, "1030300.jpg") and os.path.isfile(got))
    check("a Steam hit fetches nothing", calls == [])
    shutil.rmtree(os.path.join(steam, "appcache"))
    check("the kept copy outlives Steam's cache", ga.find_art("1030300", [steam], c1, None) == got)

    touch(os.path.join(lc, "aaa", "library_capsule.jpg"))
    touch(os.path.join(lc, "bbb", "library_hero.jpg"))
    touch(os.path.join(lc, "ccc", "library_header.jpg"))
    open(os.path.join(lc, "ccc", "library_header.jpg"), "wb").write(b"\xff\xd8header")
    open(os.path.join(lc, "bbb", "library_hero.jpg"), "wb").write(b"\xff\xd8hero")
    open(os.path.join(lc, "aaa", "library_capsule.jpg"), "wb").write(b"\xff\xd8capsule")
    def body(c): return open(os.path.join(c, "1030300.jpg"), "rb").read()
    c2 = fresh(); ga.find_art("1030300", [steam], c2, None)
    check("prefers the header", body(c2).endswith(b"header"))
    os.remove(os.path.join(lc, "ccc", "library_header.jpg"))
    c3 = fresh(); ga.find_art("1030300", [steam], c3, None)
    check("falls back to the hero", body(c3).endswith(b"hero"))
    os.remove(os.path.join(lc, "bbb", "library_hero.jpg"))
    c4 = fresh(); ga.find_art("1030300", [steam], c4, None)
    check("then the capsule", body(c4).endswith(b"capsule"))
    cache = c4

    check("an app Steam has never shown is fetched once", ga.find_art("55", [steam], cache, fake) == os.path.join(cache, "55.jpg")
          and calls == ["55"])
    check("and then comes from the cache, not the network", ga.find_art("55", [steam], cache, fake) == os.path.join(cache, "55.jpg")
          and calls == ["55"])
    check("no downloader, no picture", ga.find_art("77", [steam], cache, None) == "")
    check("a failed fetch is empty", ga.find_art("78", [steam], cache, lambda a, d: "") == "")
    check("a second Steam install is searched", ga.find_art("9", [os.path.join(t, "none"), steam], cache, None) == "")

env = {"HOME": "/h", "XDG_DATA_HOME": "/d", "XDG_CACHE_HOME": "/c"}
check("paths follow XDG", ga.bases(env)[0] == "/d/Steam" and ga.cache_dir(env) == "/c/quicktest/gamemode-art")
check("paths fall back to HOME", ga.bases({"HOME": "/h"})[0] == "/h/.local/share/Steam"
      and ga.cache_dir({"HOME": "/h"}) == "/h/.cache/quicktest/gamemode-art")
check("only digits are app ids", all(not ga.ID.match(x) for x in ["", "1a", "../x", "1;rm", "12345678901"]) and ga.ID.match("1030300"))

print(f"gamemode-art: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
