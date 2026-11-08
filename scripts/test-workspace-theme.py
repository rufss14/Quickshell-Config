#!/usr/bin/env python3
"""
test-workspace-theme.py — scripts/workspace-theme.py and scripts/workspace-apps.sh.

    python3 scripts/test-workspace-theme.py

Safe: a temp XDG_CACHE_HOME (its own wal/ and palette cache), a generated picture and
the real pywal; the terminal walk runs over a FAKE /proc tree. No terminal is written
to, no app is restyled.
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
passed = failed = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
    else:
        failed += 1
        print("FAIL %s%s" % (name, ("\n      %s" % (detail,)) if detail else ""))


tmp = tempfile.mkdtemp(prefix="ws-theme-test-")
cache = os.path.join(tmp, "cache")
os.makedirs(os.path.join(cache, "wal", "schemes"))
live = {"wallpaper": "/x", "alpha": "100",
        "special": {"background": "#101010", "foreground": "#efefef", "cursor": "#efefef"},
        "colors": {"color%d" % i: "#%02x%02x%02x" % (i * 9, i * 7, i * 5) for i in range(16)}}
with open(os.path.join(cache, "wal", "colors.json"), "w") as f:
    json.dump(live, f)

try:
    from PIL import Image
except ImportError:
    print("Pillow missing — can't generate a picture"); sys.exit(1)
pic = os.path.join(tmp, "Sunset.png")
img = Image.new("RGB", (64, 36))
for x in range(64):
    for y in range(36):
        img.putpixel((x, y), (200 - x * 2, 60 + y * 3, 90 + x))
img.save(pic)

env = dict(os.environ, XDG_CACHE_HOME=cache)
SCRIPT = os.path.join(HERE, "workspace-theme.py")


def run(*a):
    r = subprocess.run([sys.executable, SCRIPT, *a], env=env, capture_output=True, text=True, timeout=120)
    try:
        return json.loads(r.stdout.strip().splitlines()[-1])
    except Exception:
        return {"raw": r.stdout, "err": r.stderr}


t0 = time.monotonic()
a = run("palette", pic)
t1 = time.monotonic()
check("palette: made", "file" in a and os.path.isfile(a.get("file", "")), a)
check("palette: 16 colours + specials",
      len(a.get("palette", {}).get("colors", {})) == 16 and "background" in a.get("palette", {}).get("special", {}), a)
check("palette: into the private cache, never the live one",
      a.get("file", "").startswith(os.path.join(cache, "quickshell-quicktest", "ws-palettes")), a.get("file"))
with open(os.path.join(cache, "wal", "colors.json")) as f:
    check("palette: the live colors.json untouched", json.load(f) == live)
b = run("palette", pic)
t2 = time.monotonic()
check("palette: second time is the cached file", b.get("file") == a.get("file"), (a.get("file"), b.get("file")))
check("palette: …and much faster", (t2 - t1) < (t1 - t0), (t1 - t0, t2 - t1))
c = run("palette", pic, "--light")
check("palette: light mode is its own palette", c.get("file") and c.get("file") != a.get("file"), c)
check("palette: a missing picture is an error, not a crash", "error" in run("palette", os.path.join(tmp, "nope.png")))
check("palette: a relative path is refused", "error" in run("palette", "Sunset.png"))

# A scene's preview can be a GIF: read from its first frame, and keyed by --key.
gif = os.path.join(tmp, "preview.gif")
img.save(gif)
g = run("palette", gif, "--key", "scene_3661092645")
check("palette: a GIF preview works (first frame)", "file" in g and len(g.get("palette", {}).get("colors", {})) == 16, g)
g2 = run("palette", gif)
check("palette: the key is part of the cache identity", g.get("file") != g2.get("file"), (g.get("file"), g2.get("file")))

# ── A palette you already have (a scheme, the album's) ───────────────────────────
good = {"special": {"background": "#102030", "foreground": "#E0E0E0"},
        "colors": {"color%d" % i: "#%02x%02x%02x" % (20 + i * 10, 40 + i * 5, 60 + i * 8) for i in range(16)}}


def run_json(doc, raw=None):
    r = subprocess.run([sys.executable, SCRIPT, "palette-json"], capture_output=True, text=True, timeout=60,
                       env=dict(env, WS_PALETTE=raw if raw is not None else json.dumps(doc)))
    try:
        return json.loads(r.stdout.strip().splitlines()[-1])
    except Exception:
        return {"raw": r.stdout, "err": r.stderr}


j1 = run_json(good)
check("json: made", "file" in j1 and os.path.isfile(j1.get("file", "")), j1)
check("json: a full pywal colors.json (cursor, wallpaper, alpha)",
      json.load(open(j1["file"])).keys() >= {"wallpaper", "alpha", "special", "colors"}
      and json.load(open(j1["file"]))["special"].get("cursor") == "#e0e0e0", j1)
check("json: into the private cache", j1.get("file", "").startswith(os.path.join(cache, "quickshell-quicktest", "ws-palettes")))
check("json: the same colours are the same file", run_json(good).get("file") == j1.get("file"))
good2 = json.loads(json.dumps(good)); good2["colors"]["color3"] = "#ffffff"
check("json: other colours, another file", run_json(good2).get("file") != j1.get("file"))
check("json: not JSON is an error", "error" in run_json(None, raw="{nope"))
check("json: no colours is an error", "error" in run_json({"special": {"background": "#000000"}, "colors": {}}))
dirty = json.loads(json.dumps(good)); dirty["colors"]["color2"] = "red; rm -rf /"; dirty["colors"]["evil"] = "#ffffff"
d1 = run_json(dirty)
check("json: a bad value and an unknown slot are dropped, not written",
      "color2" not in d1.get("palette", {}).get("colors", {}) and "evil" not in d1.get("palette", {}).get("colors", {}), d1)
check("json: the live colors.json untouched", json.load(open(os.path.join(cache, "wal", "colors.json"))) == live)

# ── The terminal walk, over a fake /proc ───────────────────────────────────────
spec = importlib.util.spec_from_file_location("wst", SCRIPT)
W = importlib.util.module_from_spec(spec)
spec.loader.exec_module(W)
proc = os.path.join(tmp, "proc")


def fake(pid, kids, tty=None):
    os.makedirs(os.path.join(proc, str(pid), "task", str(pid)), exist_ok=True)
    with open(os.path.join(proc, str(pid), "task", str(pid), "children"), "w") as f:
        f.write(" ".join(map(str, kids)))
    os.makedirs(os.path.join(proc, str(pid), "fd"), exist_ok=True)
    if tty:
        os.symlink(tty, os.path.join(proc, str(pid), "fd", "0"))


fake(100, [101, 102], "/dev/ptmx")         # the terminal emulator
fake(101, [103], "/dev/pts/4")             # a shell
fake(102, [], "/dev/pts/9")                # another window's shell
fake(103, [], "/dev/pts/4")                # a program in the first shell
check("ptys: each shell once, the emulator's master skipped",
      sorted(W.ptys_of(100, proc)) == ["/dev/pts/4", "/dev/pts/9"], W.ptys_of(100, proc))
check("ptys: a pid with nothing under it", W.ptys_of(103, proc) == [])
check("ptys: a pid that isn't there", W.ptys_of(99999, proc) == [])
fake(200, [201], None)
fake(201, [200], "/dev/pts/5")             # a loop must not hang
check("ptys: a cycle ends", W.ptys_of(200, proc) == ["/dev/pts/5"], W.ptys_of(200, proc))

# ── Saved palettes by key ──────────────────────────────────────────────────────
check("saved: a scene key", W.saved_for("/x/preview.jpg", "scene_42").endswith("/scene_42.json"))
check("saved: no key = the picture's name", W.saved_for("/x/Pier.png", "").endswith("/Pier.png.json"))
check("saved: a key with a path in it is ignored", W.saved_for("/x/Pier.png", "../../etc").endswith("/Pier.png.json"))

# ── What may be sent ───────────────────────────────────────────────────────────
W.ROOT = os.path.join(cache, "quickshell-quicktest", "ws-palettes")
W.WAL_CACHE = os.path.join(cache, "wal")
check("terminals: a palette it made is allowed", W.allowed_palette(a.get("file", "")))
check("terminals: a JSON-made palette is allowed too", W.allowed_palette(j1.get("file", "")))
check("terminals: the live one is allowed", W.allowed_palette(os.path.join(cache, "wal", "colors.json")))
check("terminals: anything else is refused", not W.allowed_palette("/etc/passwd"))
r = run("terminals", "/etc/passwd", "1234")
check("terminals: refused end to end", r.get("sent") == 0 and "error" in r, r)

apps = os.path.join(HERE, "workspace-apps.sh")
r = subprocess.run(["bash", apps, "/etc/passwd", "discord"], env=env, capture_output=True, text=True)
check("apps: a foreign palette is refused", r.returncode == 2 and "Not a palette" in r.stdout, r.stdout)
r = subprocess.run(["bash", apps, a.get("file", "/nope"), "nonsense"], env=dict(env, HOME=tmp),
                   capture_output=True, text=True)
check("apps: an unknown app is reported, not run", "Unknown app nonsense" in r.stdout and r.returncode == 0, r.stdout)

print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
