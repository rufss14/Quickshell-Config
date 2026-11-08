#!/usr/bin/env python3
"""test-apply-wallpaper.py — the theming scripts' wave protocol, against FAKE tools.

    python3 scripts/test-apply-wallpaper.py

Safe to run: everything happens in a temp dir. HOME and every XDG dir point there,
and pywal, awww, gsettings, pkill, pgrep, hyprctl, pywalfox and notify-send are
fakes on a temp PATH that only log what they were asked — no real palette,
wallpaper, terminal, GTK setting or browser is touched.

What it pins (services/WallWave.qml, the header of apply-wallpaper.sh):
  · the palette the shell watches changes ONCE, between WAVE=ready and WAVE=go,
    and is already final there — your held colours merged, not arriving later;
  · pywal extracts into the private stage, never the live cache, sharing pywal's
    per-image scheme cache so a known picture keeps its palette;
  · in a wave, awww switches only after the water has landed (after WAVE=go, with
    no transition of its own) and the app fan-out starts only after WAVE=done;
  · without the shell (no QS_WAVE) the picture is set first with awww's own
    transition, as before;
  · theming off / colours fully held: only the water moves (no WAVE=ready);
  · reload-theme.sh on its own (a scheme, a pin) commits your edits the same way;
  · kitty's theme is written with the commit, so a window signalled as the front
    reaches it (services/Contagion.qml) already has the new colours;
  · `reload-theme.sh --app` recolours exactly one app, for the same reason — and the
    fan-out after the wave skips an app recoloured since this run's commit.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
APPLY = HERE / "apply-wallpaper.sh"
RELOAD = HERE / "reload-theme.sh"
MERGE = HERE / "merge-overrides.py"

# A fake pywal. `-i IMG` writes a palette derived from the image's NAME into
# PYWAL_CACHE_DIR (else $XDG_CACHE_HOME/wal); `--theme FILE` re-exports FILE's
# palette as templates, rewriting colors.json the way the real one does.
FAKE_WAL = r'''#!/usr/bin/env python3
import hashlib, json, os, sys
log = os.environ["FAKE_LOG"]
cache = os.environ.get("PYWAL_CACHE_DIR") or os.path.join(os.environ["XDG_CACHE_HOME"], "wal")
with open(log, "a") as f:
    f.write(json.dumps({"cmd": "wal", "args": sys.argv[1:], "cache": cache}) + "\n")
args = sys.argv[1:]
os.makedirs(cache, exist_ok=True)
def export(pal):
    with open(os.path.join(cache, "colors.json"), "w") as f:
        json.dump(pal, f, indent=4)
    with open(os.path.join(cache, "colors.sh"), "w") as f:
        f.write("background='%s'\nforeground='%s'\n" % (pal["special"]["background"], pal["special"]["foreground"]))
        for k, v in pal["colors"].items():
            f.write("%s='%s'\n" % (k, v))
    with open(os.path.join(cache, "colors-kitty.conf"), "w") as f:
        f.write("foreground %s\n" % pal["special"]["foreground"])
if "--theme" in args:
    src = args[args.index("--theme") + 1]
    export(json.load(open(src)))
elif "-i" in args:
    img = args[args.index("-i") + 1]
    h = hashlib.sha1(os.path.basename(img).encode()).hexdigest()
    pal = {"wallpaper": img, "alpha": "100",
           "special": {"background": "#" + h[0:6], "foreground": "#" + h[6:12], "cursor": "#" + h[6:12]},
           "colors": {"color%d" % i: "#" + (h * 3)[i * 2:i * 2 + 6] for i in range(16)}}
    os.makedirs(os.path.join(cache, "schemes"), exist_ok=True)
    export(pal)
    with open(os.path.join(cache, "wal"), "w") as f:
        f.write(img)
'''

# The same fake as a LIBRARY: scripts/stage-palette.py imports pywal instead of running
# `wal`. Same palette (a hash of the image's name), same files, every call logged as
# {"cmd": "pywal", "fn": …}. Never the real pywal here: its backend would run the
# faked `magick`, get no colours back and retry forever.
FAKE_PYWAL = {
    "__init__.py": "",
    "_fake.py": r'''import json, os
CACHE_DIR = os.environ.get("PYWAL_CACHE_DIR") or os.path.join(os.environ["XDG_CACHE_HOME"], "wal")
def log(fn, **kw):
    with open(os.environ["FAKE_LOG"], "a") as f:
        f.write(json.dumps(dict({"cmd": "pywal", "fn": fn}, **kw)) + "\n")
''',
    "image.py": r'''import os, sys
from ._fake import CACHE_DIR, log
def get(img, cache_dir=CACHE_DIR, iterative=False, recursive=False):
    log("image.get", img=img, cache=cache_dir)
    if not os.path.isfile(img):
        sys.exit(1)
    os.makedirs(cache_dir, exist_ok=True)
    with open(os.path.join(cache_dir, "wal"), "w") as f:
        f.write(img)
    return img
''',
    "colors.py": r'''import hashlib, os
from ._fake import CACHE_DIR, log
def get(img, light=False, backend="wal", cache_dir=CACHE_DIR, sat="", **kw):
    log("colors.get", img=img, cache=cache_dir, light=light, backend=backend)
    h = hashlib.sha1(os.path.basename(img).encode()).hexdigest()
    return {"wallpaper": img, "alpha": "100",
            "special": {"background": "#" + h[0:6], "foreground": "#" + h[6:12], "cursor": "#" + h[6:12]},
            "colors": {"color%d" % i: "#" + (h * 3)[i * 2:i * 2 + 6] for i in range(16)}}
''',
    "theme.py": r'''import json
def file(path, light=False, **kw):
    return json.load(open(path))
''',
    "sequences.py": r'''import os
from ._fake import CACHE_DIR, log
def send(colors, cache_dir=CACHE_DIR, to_send=True, vte_fix=False):
    log("sequences.send", cache=cache_dir, to_send=to_send)
    open(os.path.join(cache_dir, "sequences"), "w").write("seq")
''',
    "export.py": r'''import json, os
from ._fake import CACHE_DIR, log
def every(pal, output_dir=CACHE_DIR):
    log("export.every", out=output_dir)
    os.makedirs(output_dir, exist_ok=True)
    with open(os.path.join(output_dir, "colors.json"), "w") as f:
        json.dump(pal, f, indent=4)
    with open(os.path.join(output_dir, "colors.sh"), "w") as f:
        f.write("background='%s'\nforeground='%s'\n" % (pal["special"]["background"], pal["special"]["foreground"]))
        for k, v in pal["colors"].items():
            f.write("%s='%s'\n" % (k, v))
    with open(os.path.join(output_dir, "colors-kitty.conf"), "w") as f:
        f.write("foreground %s\n" % pal["special"]["foreground"])
''',
    "reload.py": r'''from ._fake import log
def env(xrdb_file=None, tty_reload=True):
    log("reload.env", tty=tty_reload)
''',
}

# Everything else that could touch the real desktop: log the call, succeed quietly.
# pgrep/pkill fail (nothing running), so no RESTART= lines and no signals anywhere.
FAKE_LOGGER = r'''#!/usr/bin/env python3
import json, os, sys
with open(os.environ["FAKE_LOG"], "a") as f:
    f.write(json.dumps({"cmd": os.path.basename(sys.argv[0]), "args": sys.argv[1:]}) + "\n")
name = os.path.basename(sys.argv[0])
if name == "gsettings" and sys.argv[1:2] == ["get"]:
    print("'Adwaita'")
sys.exit(1 if name in ("pgrep", "pkill") else 0)
'''

OLD = {"wallpaper": "/old.png", "alpha": "100",
       "special": {"background": "#010101", "foreground": "#fefefe", "cursor": "#fefefe"},
       "colors": {"color%d" % i: "#0%x0%x0%x" % (i, i, i) for i in range(16)}}

passed = failed = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
    else:
        failed += 1
        print(f"  FAIL  {name}" + (f"\n          {detail}" if detail else ""))


class Sandbox:
    def __init__(self):
        self.root = Path(tempfile.mkdtemp(prefix="wave-test-"))
        self.home = self.root / "home"
        self.cache = self.home / ".cache"
        self.bin = self.root / "bin"
        self.log = self.root / "calls.jsonl"
        self.shell = self.root / "shell"
        for d in (self.home, self.cache / "wal", self.bin, self.home / ".config", self.home / ".local/state"):
            d.mkdir(parents=True, exist_ok=True)
        (self.bin / "wal").write_text(FAKE_WAL)
        # curl too: the Spotify step POSTs to the shell's REAL bridge on 127.0.0.1.
        for name in ("awww", "gsettings", "pkill", "pgrep", "hyprctl", "pywalfox",
                     "notify-send", "spicetify", "magick", "curl"):
            (self.bin / name).write_text(FAKE_LOGGER)
        for p in self.bin.iterdir():
            p.chmod(0o755)
        (self.root / "pylib" / "pywal").mkdir(parents=True)
        for name, text in FAKE_PYWAL.items():
            (self.root / "pylib" / "pywal" / name).write_text(text)
        # A copy of the scripts dir, so theming/ (the overrides) is the sandbox's own.
        (self.shell / "scripts").mkdir(parents=True)
        (self.shell / "theming").mkdir()
        for f in HERE.iterdir():
            if f.is_file():
                (self.shell / "scripts" / f.name).write_bytes(f.read_bytes())
        # The themes/ tree too (lib.sh is the real one): the scripts look for Discord's and
        # Spotify's helpers in scripts/themes/, so the fakes below replace those files.
        shutil.copytree(HERE / "themes", self.shell / "scripts" / "themes")
        self.set_live(OLD)
        self.wall = self.root / "Pier.png"
        self.wall.write_bytes(b"\x89PNG not really")

    def midnight(self, text):
        """Stand in for the shipped pywal-midnight.py, and make Vencord a client the
        scripts will find (discord_clients lists a client by its directory)."""
        (self.home / ".config" / "Vencord" / "themes").mkdir(parents=True, exist_ok=True)
        (self.shell / "scripts" / "themes" / "discord" / "pywal-midnight.py").write_text(text)

    def pwspice(self, text):
        """Stand in for the shipped pwspice.py, and theme Spotify (QuickSpice installed)."""
        (self.home / ".config" / "spicetify" / "Themes" / "QuickSpice").mkdir(parents=True, exist_ok=True)
        (self.shell / "scripts" / "themes" / "spotify" / "pwspice.py").write_text(text)

    def set_live(self, pal):
        (self.cache / "wal" / "colors.json").write_text(json.dumps(pal, indent=2))

    def live(self):
        return json.loads((self.cache / "wal" / "colors.json").read_text())

    def overrides(self, doc):
        (self.shell / "theming" / "pywal-overrides.json").write_text(json.dumps(doc))

    def env(self, wave, extra=None):
        e = {"PATH": f"{self.bin}:/usr/bin:/bin", "HOME": str(self.home),
             "XDG_CACHE_HOME": str(self.cache), "XDG_CONFIG_HOME": str(self.home / ".config"),
             "XDG_STATE_HOME": str(self.home / ".local/state"), "FAKE_LOG": str(self.log),
             "LANG": "C.UTF-8", "PYTHONPATH": str(self.root / "pylib")}
        if wave:
            e.update({"QS_WAVE": "1", "QS_WAVE_FREEZE_MS": "300", "QS_WAVE_LAND_MS": "300"})
        e.update(extra or {})
        return e

    def calls(self, cmd=None):
        if not self.log.exists():
            return []
        rows = [json.loads(l) for l in self.log.read_text().splitlines() if l.strip()]
        return [r for r in rows if cmd is None or r["cmd"] == cmd]

    def run(self, script, args, wave, on_line=None, extra_env=None):
        """Run a script, calling on_line(line) as each stdout line arrives."""
        p = subprocess.Popen(["bash", str(self.shell / "scripts" / script)] + args,
                             env=self.env(wave, extra_env), stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, text=True)
        lines = []
        for line in p.stdout:
            line = line.rstrip("\n")
            lines.append(line)
            # Mark each line in the call log, so tools' calls can be ordered against it.
            with open(self.log, "a") as f:
                f.write(json.dumps({"cmd": "#line", "args": [line]}) + "\n")
            if on_line:
                on_line(line)
        err = p.stderr.read()
        p.wait(timeout=30)
        return p.returncode, lines, err


def order(lines, a, b):
    """True when line a appears, b appears, and a comes first."""
    try:
        return lines.index(a) < lines.index(b)
    except ValueError:
        return False


def first_index(lines, prefix):
    for i, l in enumerate(lines):
        if l.startswith(prefix):
            return i
    return -1


def wave_run_shell_render():
    """The user's default: the shell draws the wallpaper, colours from the picture."""
    sb = Sandbox()
    sb.overrides({"special": {}, "colors": {"color1": "#abcdef"}})
    seen = {}

    def on_line(line):
        if line in ("WAVE=ready", "WAVE=go", "WAVE=done"):
            seen[line] = sb.live()

    code, lines, err = sb.run("apply-wallpaper.sh", ["--no-daemon", str(sb.wall)], True, on_line)
    check("shell-render: exits 0", code == 0, err)
    check("shell-render: ready → go → done",
          order(lines, "WAVE=ready", "WAVE=go") and order(lines, "WAVE=go", "WAVE=done"), lines)
    check("shell-render: nothing committed before ready",
          seen.get("WAVE=ready") == OLD, seen.get("WAVE=ready"))
    at_go = seen.get("WAVE=go") or {}
    check("shell-render: new palette live at go",
          at_go.get("wallpaper") == str(sb.wall) and at_go.get("special", {}).get("background") != "#010101",
          at_go)
    check("shell-render: held colour already merged at go",
          at_go.get("colors", {}).get("color1") == "#abcdef", at_go.get("colors"))
    check("shell-render: unchanged from go to done", seen.get("WAVE=done") == at_go)
    after = sb.live()
    check("shell-render: final palette is the one committed at go",
          after.get("special") == at_go.get("special") and after.get("colors") == at_go.get("colors"))
    pw = sb.calls("pywal")
    extract = [c for c in pw if c["fn"] == "colors.get"]
    check("shell-render: pywal extracted once, through the stage's cache",
          len(extract) == 1 and extract[0]["cache"] == str(sb.cache / "wal-stage"), extract)
    check("shell-render: `wal -i`'s arguments (they're its cache key)",
          extract and extract[0]["backend"] is None and extract[0]["light"] is False, extract)
    renders = [c for c in pw if c["fn"] == "export.every"]
    check("shell-render: templates rendered ONCE, before the commit, into the stage",
          len(renders) == 1 and renders[0]["out"] == str(sb.cache / "wal-stage" / "out"), renders)
    check("shell-render: nothing sent to terminals before the wave",
          [c["to_send"] for c in pw if c["fn"] == "sequences.send"][:1] == [False], pw)
    check("shell-render: no `wal` process at all", sb.calls("wal") == [], sb.calls("wal"))
    check("shell-render: the fan-out installs what the commit rendered",
          (sb.cache / "wal" / "colors.sh").read_text() == (sb.cache / "wal-stage" / "committed" / "colors.sh").read_text())
    check("shell-render: …then tells the terminals, after the wave",
          any(c["fn"] == "sequences.send" and c["to_send"] for c in pw)
          and any(c["fn"] == "reload.env" for c in pw), pw)
    check("shell-render: stage shares pywal's scheme cache",
          (sb.cache / "wal-stage" / "schemes").is_symlink()
          and os.path.realpath(sb.cache / "wal-stage" / "schemes") == os.path.realpath(sb.cache / "wal" / "schemes"))
    check("shell-render: awww never called", sb.calls("awww") == [], sb.calls("awww"))
    check("shell-render: fan-out after the wave lands",
          first_index(lines, "WAVE=done") < first_index(lines, "STEP=export|"), lines)
    check("shell-render: marker written",
          (sb.cache / "current_wallpaper_name").read_text().strip() == sb.wall.name)
    check("shell-render: pywal's wallpaper note carried across",
          (sb.cache / "wal" / "wal").read_text() == str(sb.wall))
    check("shell-render: reports done ok", "STEP=done|ok|Wallpaper applied" in lines, lines[-3:])


def wave_run_awww():
    sb = Sandbox()
    code, lines, err = sb.run("apply-wallpaper.sh", [str(sb.wall)], True)
    check("awww: exits 0", code == 0, err)
    calls = sb.calls()
    marks = [i for i, c in enumerate(calls) if c["cmd"] == "#line"]
    awww = [i for i, c in enumerate(calls) if c["cmd"] == "awww"]
    go = next((i for i in marks if calls[i]["args"][0] == "WAVE=go"), -1)
    done = next((i for i in marks if calls[i]["args"][0] == "WAVE=done"), -1)
    check("awww: called exactly once", len(awww) == 1, [calls[i] for i in awww])
    check("awww: switched under the water — after go, before done",
          len(awww) == 1 and go < awww[0] < done, (go, awww, done))
    check("awww: no transition of its own in a wave",
          len(awww) == 1 and calls[awww[0]]["args"][-2:] == ["--transition-type", "none"],
          [calls[i]["args"] for i in awww])


def no_wave_run():
    """Run by hand / animations off: the old order, nothing waits."""
    sb = Sandbox()
    t0 = time.monotonic()
    code, lines, err = sb.run("apply-wallpaper.sh", [str(sb.wall)], False)
    dt = time.monotonic() - t0
    check("no-wave: exits 0", code == 0, err)
    awww = sb.calls("awww")
    check("no-wave: awww first, with its own transition",
          len(awww) == 1 and "right" in awww[0]["args"]
          and first_index(lines, "STEP=wallpaper") < first_index(lines, "STEP=palette"),
          (awww, lines[:6]))
    check("no-wave: the palette still lands", sb.live().get("wallpaper") == str(sb.wall))
    check("no-wave: doesn't sleep for an animation nobody plays", dt < 5, dt)


def theming_off():
    sb = Sandbox()
    code, lines, err = sb.run("apply-wallpaper.sh", ["--no-theme", str(sb.wall)], True)
    check("no-theme: exits 0", code == 0, err)
    check("no-theme: water only — go without ready",
          "WAVE=go" in lines and "WAVE=ready" not in lines, lines)
    check("no-theme: palette untouched", sb.live() == OLD)
    check("no-theme: pywal never ran", sb.calls("wal") == [] and sb.calls("pywal") == [], sb.calls("pywal"))


def fully_held():
    sb = Sandbox()
    held = {"special": {"background": "#222222", "foreground": "#dddddd"},
            "colors": {"color%d" % i: "#3%x3%x3%x" % (i, i, i) for i in range(16)}}
    sb.overrides(held)
    code, lines, err = sb.run("apply-wallpaper.sh", ["--no-daemon", str(sb.wall)], True)
    check("held: exits 0", code == 0, err)
    check("held: water only — go without ready", "WAVE=go" in lines and "WAVE=ready" not in lines, lines)
    check("held: pywal never ran", sb.calls("wal") == [] and sb.calls("pywal") == [], sb.calls("pywal"))


def palette_only():
    """The light/dark switch and a scene's colours: no picture, colours only."""
    sb = Sandbox()
    code, lines, err = sb.run("apply-wallpaper.sh", ["--palette-only", str(sb.wall)], True)
    check("palette-only: exits 0", code == 0, err)
    check("palette-only: ready → go", order(lines, "WAVE=ready", "WAVE=go"), lines)
    check("palette-only: awww never called", sb.calls("awww") == [])
    check("palette-only: current wallpaper not claimed",
          not (sb.cache / "current_wallpaper_name").exists())


def reload_standalone():
    """A scheme / a pinned colour: reload-theme.sh commits your edits on the wave."""
    sb = Sandbox()
    sb.overrides({"special": {"background": "#123456"}, "colors": {"color4": "#654321"}})
    seen = {}

    def on_line(line):
        if line in ("WAVE=ready", "WAVE=go"):
            seen[line] = sb.live()

    code, lines, err = sb.run("reload-theme.sh", [], True, on_line)
    check("reload: exits 0", code == 0, err)
    check("reload: ready → go → done",
          order(lines, "WAVE=ready", "WAVE=go") and order(lines, "WAVE=go", "WAVE=done"), lines)
    check("reload: old palette until ready", seen.get("WAVE=ready") == OLD)
    at_go = seen.get("WAVE=go") or {}
    check("reload: edits live at go",
          at_go.get("special", {}).get("background") == "#123456"
          and at_go.get("colors", {}).get("color4") == "#654321", at_go)
    check("reload: fan-out after the wave",
          first_index(lines, "WAVE=done") < first_index(lines, "STEP=export|"), lines)


def reload_committed():
    """apply-wallpaper.sh's fan-out: no second merge, no second wave."""
    sb = Sandbox()
    sb.overrides({"special": {"background": "#123456"}, "colors": {}})
    code, lines, err = sb.run("reload-theme.sh", ["--committed"], True)
    check("committed: exits 0", code == 0, err)
    check("committed: no wave lines", not any(l.startswith("WAVE=") for l in lines), lines)
    check("committed: doesn't merge again", sb.live().get("special", {}).get("background") == "#010101")


def kitty_staged():
    """Contagion signals each kitty window as the front reaches it — the theme file
    must already hold the new colours at WAVE=go."""
    sb = Sandbox()
    kitty = sb.home / ".config" / "kitty"
    kitty.mkdir(parents=True)
    (kitty / "current-theme.conf").write_text("foreground #fefefe\n")
    seen = {}

    def on_line(line):
        if line in ("WAVE=ready", "WAVE=go"):
            seen[line] = (kitty / "current-theme.conf").read_text()

    code, lines, err = sb.run("apply-wallpaper.sh", ["--no-daemon", str(sb.wall)], True, on_line)
    fg = sb.live()["special"]["foreground"]
    check("kitty: exits 0", code == 0, err)
    check("kitty: old theme until ready", seen.get("WAVE=ready") == "foreground #fefefe\n", seen)
    check("kitty: new theme by go", seen.get("WAVE=go") == f"foreground {fg}\n", (seen, fg))
    check("kitty: no stray temp file", not (kitty / ".current-theme.conf.new").exists())


def gtk_staged():
    """An open GTK app repaints the moment its sheet changes (GTK4 with the live module) or when
    gtk-theme flips (GTK3), so BOTH must happen WITH the commit — under the curtain, between
    ready and go — not in the fan-out after the wave, where Nautilus visibly changed after the
    front had passed it. And the flip must happen once: the fan-out's own call is skipped."""
    sb = Sandbox()
    sheets = {}
    for v in ("3.0", "4.0"):
        d = sb.home / ".config" / f"gtk-{v}"
        d.mkdir(parents=True)
        (d / "gtk.css").write_text("/* old */\n")
        sheets[v] = d / "gtk.css"
    seen = {}

    def on_line(line):
        if line in ("WAVE=ready", "WAVE=go"):
            seen[line] = {v: p.read_text() for v, p in sheets.items()}

    # A background that is NOT color0 — the fake wal makes them equal, and then nothing
    # here could tell which one the sheets stand on.
    sb.overrides({"special": {"background": "#123456"}, "colors": {}})
    code, lines, err = sb.run("apply-wallpaper.sh", ["--no-daemon", str(sb.wall)], True, on_line)
    bg = sb.live()["special"]["background"]
    check("gtk: exits 0", code == 0, err)
    check("gtk: fixture background differs from color0", bg != sb.live()["colors"]["color0"], sb.live())
    for v, key in (("4.0", f"@define-color window_bg_color {bg};"), ("3.0", "@define-color accent_color ")):
        check(f"gtk{v[0]}: old sheet until ready", seen.get("WAVE=ready", {}).get(v) == "/* old */\n", seen)
        check(f"gtk{v[0]}: new sheet by go", key in seen.get("WAVE=go", {}).get(v, ""), (v, seen.get("WAVE=go", {}).get(v, "")[:120]))
        check(f"gtk{v[0]}: no stray temp file", not sheets[v].with_name("gtk.css.tmp").exists())
    # Every surface on the same ground as the shell, kitty, Discord and Qt — never color0
    # (GTK4 windows stood on a visibly lighter colour than everything around them).
    for v, names in (("4.0", ("window", "view", "headerbar", "card", "dialog", "popover", "sidebar")),
                     ("3.0", ("window", "view", "headerbar", "card", "popover", "sidebar"))):
        sheet = sheets[v].read_text()
        off = [n for n in names if f"@define-color {n}_bg_color {bg};" not in sheet]
        check(f"gtk{v[0]}: every surface on the background", off == [], (off, sheet[:400]))
    check("gtk4: an unfocused header bar on the background, not the accent",
          f"@define-color headerbar_backdrop_color {bg};" in sheets["4.0"].read_text())
    check("gtk4: step still reported", any(l.startswith("STEP=gtk4|ok") for l in lines), lines)
    check("gtk3: step still reported", any(l.startswith("STEP=gtk3|ok") for l in lines), lines)
    for _ in range(20):   # the refresh runs in the background (it sleeps between its two writes)
        sets = [c for c in sb.calls("gsettings") if c["args"][:1] == ["set"] and "gtk-theme" in c["args"]]
        if len(sets) >= 2:
            break
        time.sleep(0.1)
    time.sleep(0.5)       # a second, wrongly-run flip would land by now
    sets = [c["args"][-1] for c in sb.calls("gsettings") if c["args"][:1] == ["set"] and "gtk-theme" in c["args"]]
    check("gtk3: ONE flip (there and back), not one at the commit and one in the fan-out",
          sets == ["Adwaita-dark", "Adwaita"], sets)


def app_only():
    """--app: one app from the committed palette, nothing else (Contagion's call)."""
    sb = Sandbox()
    marker = sb.root / "vencord-ran"
    sb.midnight(f"open({str(marker)!r}, 'w').write('ok')\n")
    # A client counts only once the theme is installed in it (discord_themes).
    (sb.home / ".config" / "Vencord" / "themes" / "midnight.theme.css").write_text(":root { --bg: #010101; }\n")
    code, lines, err = sb.run("reload-theme.sh", ["--app", "discord"], True)
    check("app discord: exits 0", code == 0, err)
    check("app discord: ran Vencord's script", marker.exists())
    check("app discord: nothing else", not any(l.startswith(("STEP=export", "WAVE=")) for l in lines), lines)
    code, lines, err = sb.run("reload-theme.sh", ["--app", "browser"], True)
    check("app browser: pywalfox asked", any(c["args"] == ["update"] for c in sb.calls("pywalfox")))
    check("app browser: nothing else", not any(l.startswith(("STEP=export", "WAVE=")) for l in lines), lines)
    code, lines, err = sb.run("reload-theme.sh", ["--app", "nope"], True)
    check("app unknown: refused", code == 2, (code, lines))


def spotify_once():
    """Contagion recolours Spotify under the wave's curtain (--app spotify); the
    fan-out after the wave must then skip it — a second recolour re-fetches its
    stylesheets, visibly, a second after the wave. Without the wave's run it must not."""
    sb = Sandbox()
    spice = sb.home / ".config" / "spicetify"
    spice.mkdir(parents=True)
    count = sb.root / "spotify-runs"
    sb.pwspice(f"open({str(count)!r}, 'a').write('x')\n")

    def on_line(line):
        if line == "WAVE=go":   # what Contagion does once the palette is live
            subprocess.run(["bash", str(sb.shell / "scripts" / "reload-theme.sh"), "--app", "spotify"],
                           env=sb.env(True), capture_output=True, timeout=10)

    code, lines, err = sb.run("apply-wallpaper.sh", ["--no-daemon", str(sb.wall)], True, on_line)
    runs = count.read_text().count("x") if count.exists() else 0
    check("spotify: exits 0", code == 0, err)
    check("spotify: recoloured exactly once", runs == 1, runs)
    check("spotify: the fan-out says why it skipped",
          "STEP=spotify|skip|recoloured with the wave" in lines, [l for l in lines if "spotify" in l])

    # An old stamp (an earlier wave) must not suppress this run's recolour.
    sb2 = Sandbox()
    spice2 = sb2.home / ".config" / "spicetify"
    spice2.mkdir(parents=True)
    count2 = sb2.root / "spotify-runs"
    sb2.pwspice(f"open({str(count2)!r}, 'a').write('x')\n")
    (sb2.cache / "wal-stage").mkdir(parents=True)
    (sb2.cache / "wal-stage" / ".app-spotify").write_text("1000\n")
    code, lines, err = sb2.run("apply-wallpaper.sh", ["--no-daemon", str(sb2.wall)], True)
    runs2 = count2.read_text().count("x") if count2.exists() else 0
    check("spotify: a stale stamp doesn't skip it", runs2 == 1, (runs2, [l for l in lines if "spotify" in l]))


def landed_marker():
    """The script's after-the-wave work waits for the SHELL's word that the water has
    landed (QS_WAVE_LANDED, created on WallWave.landed) — the spread may be held while
    a slow app repaints — and QS_WAVE_LAND_MS is only the timeout."""
    sb = Sandbox()
    flag = sb.root / "quickshell-quicktest-wave-7.landed"
    flag.write_text("")                  # left over from an earlier session: must not count
    seen = {}

    def on_line(line):
        if line == "WAVE=go":
            seen["go"] = time.monotonic()
            threading.Timer(0.5, lambda: flag.write_text("")).start()
        elif line == "WAVE=done":
            seen["done"] = time.monotonic()

    code, lines, err = sb.run("apply-wallpaper.sh", [str(sb.wall)], True, on_line,
                              {"QS_WAVE_LANDED": str(flag), "QS_WAVE_LAND_MS": "6000"})
    waited = seen.get("done", 0) - seen.get("go", 0)
    check("landed: exits 0", code == 0, err)
    check("landed: waited for the shell's word — not the stale file, not the timeout",
          0.45 <= waited < 3.0, waited)
    check("landed: the marker is cleaned up", not flag.exists())
    awww = [i for i, c in enumerate(sb.calls()) if c["cmd"] == "awww"]
    check("landed: awww only after it", len(awww) == 1)

    # A path that isn't the shell's own naming is never trusted — nor deleted.
    sb2 = Sandbox()
    precious = sb2.root / "precious.txt"
    precious.write_text("keep me")
    code, lines, err = sb2.run("apply-wallpaper.sh", ["--no-daemon", str(sb2.wall)], True, None,
                               {"QS_WAVE_LANDED": str(precious)})
    check("landed: a foreign path is left alone", precious.exists() and precious.read_text() == "keep me")
    check("landed: …and the run still finishes", code == 0 and "WAVE=done" in lines, err)



# A pywal-midnight script with the real one's shape: --css/--colors with those defaults,
# and its bug — three `/* pywal */` APPENDED to every variable on every run. And its other
# habit: a palette file that isn't there is NOT an error — it writes its own built-in
# colours (#0b0710 ground) and exits 0. That is what made the no-wave race invisible.
FAKE_MIDNIGHT = r"""import argparse, json, os, re
p = argparse.ArgumentParser()
p.add_argument('--css', '-c', default='~/.config/Vencord/themes/midnight.theme.css')
p.add_argument('--colors', default='~/.cache/wal/colors.json')
a = p.parse_args()
css = os.path.expanduser(a.css)
try:
    d = json.load(open(os.path.expanduser(a.colors)))
    bg = d["colors"]["color0"]
except FileNotFoundError:
    d, bg = {}, '#0b0710'
# Like the real one: the accent only from a TOP-LEVEL color4 (it can't read pywal's
# `colors` object), else its fallback.
acc = d.get("color4", "#57c7ff")
t = open(css).read()
t = re.sub(r'(--accent\s*:\s*)([^;]+)(;)', r'\g<1>' + acc + r'\3', t)
t = re.sub(r'(--bg\s*:\s*)([^;]+)(;)', r'\g<1>' + bg + r'\3 /* pywal */ /* pywal */ /* pywal */', t)
open(css, 'w').write(t)
"""


def discord_staged():
    """Discord's script runs BEFORE the freeze, on a private copy of its theme; under
    the curtain only a rename is left (`--app discord --staged`), and the fan-out
    doesn't do it again."""
    sb = Sandbox()
    vencord = sb.home / ".config" / "Vencord"
    (vencord / "themes").mkdir(parents=True)
    sb.midnight(FAKE_MIDNIGHT)
    theme = vencord / "themes" / "midnight.theme.css"
    old = ":root {\n    --bg: #010101; /* pywal */ /* pywal */ /* pywal */ /* pywal */ /* pywal */ /* pywal */\n}\n"
    theme.write_text(old)
    seen = {}

    def on_line(line):
        if line == "WAVE=ready":            # the curtain is up: what Contagion does
            seen["before"] = theme.read_text()
            r = subprocess.run(["bash", str(sb.shell / "scripts" / "reload-theme.sh"), "--app", "discord", "--staged"],
                               env=sb.env(False), capture_output=True, text=True, timeout=10)
            seen["code"] = r.returncode
            seen["after"] = theme.read_text()
            r2 = subprocess.run(["bash", str(sb.shell / "scripts" / "reload-theme.sh"), "--app", "discord", "--staged"],
                                env=sb.env(False), capture_output=True, text=True, timeout=10)
            seen["again"] = r2.returncode

    code, lines, err = sb.run("apply-wallpaper.sh", ["--no-daemon", str(sb.wall)], True, on_line)
    bg = sb.live()["colors"]["color0"]
    check("discord staged: exits 0", code == 0, err)
    check("discord staged: theme untouched until the curtain asks", seen.get("before") == old, seen.get("before"))
    check("discord staged: shown with the staged palette", f"--bg: {bg};" in seen.get("after", ""), seen.get("after"))
    check("discord staged: the comment pile collapsed to one marker",
          seen.get("after", "").count("/* pywal */") == 1, seen.get("after"))
    check("discord staged: --staged exits 0", seen.get("code") == 0, seen)
    check("discord staged: consumed — a second ask has nothing (3)", seen.get("again") == 3, seen)
    check("discord staged: the fan-out skips it",
          "STEP=discord|skip|recoloured with the wave" in lines, [l for l in lines if "discord" in l])
    check("discord staged: no temp file left beside the theme",
          sorted(p.name for p in (vencord / "themes").iterdir()) == ["midnight.theme.css"])

    # Not asked under a curtain (no window on screen): the fan-out shows it instead.
    sb2 = Sandbox()
    v2 = sb2.home / ".config" / "Vencord"
    (v2 / "themes").mkdir(parents=True)
    sb2.midnight(FAKE_MIDNIGHT)
    (v2 / "themes" / "midnight.theme.css").write_text(old)
    code, lines, err = sb2.run("apply-wallpaper.sh", ["--no-daemon", str(sb2.wall)], True)
    bg2 = sb2.live()["colors"]["color0"]
    after2 = (v2 / "themes" / "midnight.theme.css").read_text()
    check("discord fan-out: recoloured from the staged copy", f"--bg: {bg2};" in after2 and after2.count("/* pywal */") == 1, after2)

    # Nothing staged at all (a run that staged nothing): --staged refuses, touching nothing.
    sb3 = Sandbox()
    r = subprocess.run(["bash", str(sb3.shell / "scripts" / "reload-theme.sh"), "--app", "discord", "--staged"],
                       env=sb3.env(False), capture_output=True, text=True, timeout=10)
    check("discord: --staged with nothing staged exits 3", r.returncode == 3, (r.returncode, r.stdout))


def discord_no_wave():
    """The album scheme's system-wide run: reload-theme.sh with NO shell watching (no
    QS_WAVE), so no freeze holds the commit. The app preps start in the background and
    the commit moved $STAGE/out away within milliseconds — Vencord's script found no
    palette, wrote its own defaults, and the fan-out published them: Discord reloaded on
    every track into the same colours. The preps read a snapshot now (apps_palette)."""
    sb = Sandbox()
    vencord = sb.home / ".config" / "Vencord"
    (vencord / "themes").mkdir(parents=True)
    # Slow to start, like the real one (a cp, then a 300-line script's imports): the real
    # commit landed ~30ms after the preps began. Without the delay this fake reads the
    # palette before the commit moves it, and the test passes against the broken code.
    sb.midnight("import time; time.sleep(0.3)\n" + FAKE_MIDNIGHT)
    theme = vencord / "themes" / "midnight.theme.css"
    theme.write_text(":root {\n    --bg: #010101; /* pywal */\n    --accent: #010101;\n}\n")
    # An overrides file is what sends a standalone run through the stage and the commit
    # (without one it renders the old way, and there is nothing to race).
    sb.overrides({})
    code, lines, err = sb.run("reload-theme.sh", [], False)
    bg = sb.live()["colors"]["color0"]
    after = theme.read_text()
    check("discord no wave: exits 0", code == 0, err)
    check("discord no wave: the palette, not the script's defaults",
          f"--bg: {bg};" in after and "#0b0710" not in after, after)
    check("discord no wave: the accent is the palette's color4 (handed in a shape it reads)",
          f"--accent: {sb.live()['colors']['color4']};" in after, after)


def spotify_staged():
    """Spotify's pwspice + `spicetify refresh` run BEFORE the freeze, from the staged
    palette; under the curtain only the POST to the bridge is left."""
    sb = Sandbox()
    spice = sb.home / ".config" / "spicetify"
    spice.mkdir(parents=True)
    sb.pwspice(
        "import json, os, sys\n"
        "w = sys.argv[sys.argv.index('-w') + 1]\n"
        f"open({str(sb.log)!r}, 'a').write(json.dumps({{'cmd': 'pwspice', 'args': sys.argv[1:], "
        "'bg': json.load(open(w))['colors']['color0']}) + '\\n')\n")
    # A bridge with the extension attached.
    (sb.bin / "curl").write_text(
        "#!/usr/bin/env python3\nimport json, os, sys\n"
        "open(os.environ['FAKE_LOG'], 'a').write(json.dumps({'cmd': 'curl', 'args': sys.argv[1:]}) + '\\n')\n"
        "print('{\"seq\": 1, \"listening\": true}' if any(a.endswith('/restyle') for a in sys.argv) "
        "else '{\"ok\":true,\"listening\":true}')\n")
    (sb.bin / "curl").chmod(0o755)
    seen = {}

    def on_line(line):
        if line == "WAVE=ready":
            seen["posts_before"] = [c for c in sb.calls("curl") if c["args"][-1].endswith("/restyle")]
            r = subprocess.run(["bash", str(sb.shell / "scripts" / "reload-theme.sh"), "--app", "spotify", "--staged"],
                               env=sb.env(False), capture_output=True, text=True, timeout=10)
            seen["code"] = r.returncode

    code, lines, err = sb.run("apply-wallpaper.sh", ["--no-daemon", str(sb.wall)], True, on_line)
    pw = sb.calls("pwspice")
    posts = [c for c in sb.calls("curl") if c["args"][-1].endswith("/restyle")]
    refresh = [c for c in sb.calls("spicetify") if c["args"][:1] == ["refresh"]]
    check("spotify staged: exits 0", code == 0, err)
    check("spotify staged: pwspice read the STAGED palette",
          len(pw) == 1 and pw[0]["bg"] == sb.live()["colors"]["color0"]
          and pw[0]["args"][1].endswith("wal-stage/apps/colors.json"), pw)
    check("spotify staged: spicetify refreshed once", len(refresh) == 1, refresh)
    check("spotify staged: nothing POSTed before the curtain asked", seen.get("posts_before") == [], seen)
    check("spotify staged: --staged exits 0", seen.get("code") == 0, seen)
    check("spotify staged: repainted exactly once", len(posts) == 1, posts)
    check("spotify staged: the fan-out skips it",
          "STEP=spotify|skip|recoloured with the wave" in lines, [l for l in lines if "spotify" in l])


def fanout_parallel():
    """The fan-out's steps run together: a slow one doesn't hold up the rest."""
    sb = Sandbox()
    (sb.shell / "scripts" / "generate-qt6ct-colors").write_text("import time; time.sleep(1.0)\n")
    (sb.shell / "scripts" / "generate-qt6ct-colors").chmod(0o755)
    (sb.shell / "scripts" / "generate-mangohud-config").write_text("import time; time.sleep(1.0)\n")
    (sb.shell / "scripts" / "generate-mangohud-config").chmod(0o755)
    t0 = time.monotonic()
    code, lines, err = sb.run("reload-theme.sh", ["--committed"], False)
    dt = time.monotonic() - t0
    check("fan-out: exits 0", code == 0, err)
    check("fan-out: two 1s steps took ~1s, not 2s", dt < 1.8, dt)
    check("fan-out: both reported", "STEP=qt6|ok|Recolouring Qt apps" in lines
          and "STEP=mangohud|ok|Recolouring MangoHud" in lines, lines)
    check("fan-out: every STEP line whole", all(l.count("|") >= 2 for l in lines if l.startswith("STEP=")), lines)

def merge_selftest():
    r = subprocess.run([sys.executable, str(MERGE), "--selftest"], capture_output=True, text=True)
    check("merge-overrides selftest", r.returncode == 0 and r.stdout.strip() == "ok", r.stdout + r.stderr)


def main():
    for t in (merge_selftest, discord_staged, discord_no_wave, spotify_staged, fanout_parallel, wave_run_shell_render, wave_run_awww, no_wave_run,
              theming_off, fully_held, palette_only, reload_standalone, reload_committed,
              kitty_staged, gtk_staged, app_only, spotify_once, landed_marker):
        t()
    print(f"{passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
