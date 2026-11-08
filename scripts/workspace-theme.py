#!/usr/bin/env python3
"""
workspace-theme.py — the per-workspace wallpaper's two jobs that need a process
(services/WorkspaceTheme.qml runs it; nothing here commits a palette).

    workspace-theme.py palette IMAGE [--light] [--key NAME]
        The palette apply-wallpaper.sh WOULD make from IMAGE — the same stage-palette.py,
        the same arguments (your held colours, a saved palette, the Arch black point) —
        built into a private cache instead of committed. Prints one JSON line:
            {"image": IMAGE, "file": ".../colors.json", "palette": {...}}
        or {"image": IMAGE, "error": "..."}. Cached by the picture's identity (path,
        size, mtime), light/dark and everything else that changes the result, so a
        switch back costs a file read. The pywal scheme cache is shared with every run.
        --key: the saved-palette name (a scene passes "scene_<id>" with its preview, as
        apply-wallpaper.sh --palette-key does); default the picture's file name. A GIF
        is read from its first frame (ImageMagick), as apply-wallpaper.sh does.

    workspace-theme.py palette-json
        The same, for a palette you already HAVE — a saved colour scheme, the album's — read from
        the environment (WS_PALETTE, a {special, colors} document; off argv, so it is not in `ps`)
        and expanded into a full pywal colors.json (wal-from-json.py's own rule) under the same
        private cache, keyed by the document's content: the same colours are the same file.
        Nothing is extracted, so there is no picture. Prints {"image": "json", "file": ...,
        "palette": {...}} or {"image": "json", "error": "..."}.

    workspace-theme.py terminals PALETTE PID...
        That palette's colours to the terminals of these processes only (their shells'
        ptys, found by walking each pid's children) — pywal's own escape sequences, the
        ones `wal` sends to EVERY pty. Prints {"sent": N}.

    python3 scripts/test-workspace-theme.py
"""
import hashlib
import importlib.util
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SHELL_DIR = os.path.dirname(HERE)
CACHE = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
WAL_CACHE = os.path.join(CACHE, "wal")
ROOT = os.path.join(CACHE, "quickshell-quicktest", "ws-palettes")
OVERRIDES = os.path.join(SHELL_DIR, "theming", "pywal-overrides.json")
SAVED_DIR = os.path.join(SHELL_DIR, "theming", "wallpaper-palettes")
KEEP = 40                  # palettes kept; the oldest go past this
WALK_MAX = 256             # processes walked per terminal


def _stamp(path):
    try:
        st = os.stat(path)
        return "%d:%d" % (st.st_size, st.st_mtime_ns)
    except OSError:
        return "-"


KEY_OK = __import__("re").compile(r"^[A-Za-z0-9._ -]{1,128}$")


def saved_for(image, key):
    name = key if key and KEY_OK.match(key) and "/" not in key else os.path.basename(image)
    return os.path.join(SAVED_DIR, name + ".json")


def cache_key(image, light, key=""):
    """Everything that changes the palette: the picture, the mode, your held colours,
    a saved palette for it, and the builder itself."""
    saved = saved_for(image, key)
    parts = [os.path.realpath(image), _stamp(image), "light" if light else "dark",
             _stamp(OVERRIDES), _stamp(saved), _stamp(os.path.join(HERE, "stage-palette.py"))]
    return hashlib.sha1("|".join(parts).encode()).hexdigest()[:20]


def _prune():
    try:
        dirs = [os.path.join(ROOT, d) for d in os.listdir(ROOT)]
    except OSError:
        return
    dirs = [d for d in dirs if os.path.isdir(d)]
    dirs.sort(key=lambda d: os.path.getmtime(d), reverse=True)
    for d in dirs[KEEP:]:
        subprocess.run(["rm", "-rf", "--", d], check=False)


def palette(image, light, name=""):
    if not os.path.isabs(image) or not os.path.isfile(image):
        return {"image": image, "error": "not a readable file"}
    key = cache_key(image, light, name)
    d = os.path.join(ROOT, key)
    out = os.path.join(d, "out", "colors.json")
    if not os.path.isfile(out):
        os.makedirs(d, exist_ok=True)
        # pywal's scheme cache is the live one: a picture seen before costs nothing.
        schemes = os.path.join(d, "schemes")
        os.makedirs(os.path.join(WAL_CACHE, "schemes"), exist_ok=True)
        if not os.path.islink(schemes):
            subprocess.run(["rm", "-rf", "--", schemes], check=False)
            os.symlink(os.path.join(WAL_CACHE, "schemes"), schemes)
        src = image
        if image.lower().endswith(".gif"):
            src = os.path.join(d, "frame.png")
            r = subprocess.run(["magick", image + "[0]", src], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if r.returncode != 0 or not os.path.isfile(src):
                return {"image": image, "error": "couldn't read a frame from the GIF (ImageMagick)"}
        args = [sys.executable, os.path.join(HERE, "stage-palette.py"), "--out", os.path.join(d, "out"),
                "--from", os.path.join(WAL_CACHE, "colors.json"), "--image", src,
                "--overrides", OVERRIDES, "--held-exit"]
        if light:
            args.append("--light")
        if os.path.basename(image) == "Arch.png":
            args.append("--blackpoint")
        saved = saved_for(image, name)
        if os.path.isfile(saved):
            args += ["--saved", saved]
        env = dict(os.environ, PYWAL_CACHE_DIR=d)
        r = subprocess.run(args, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if r.returncode == 10:
            # Your scheme holds every slot: the palette IS the one on disk.
            out = os.path.join(WAL_CACHE, "colors.json")
        elif r.returncode != 0 or not os.path.isfile(out):
            return {"image": image, "error": "stage-palette.py failed (%d)" % r.returncode}
        _prune()
    else:
        os.utime(d)        # recently used: kept by the prune
    try:
        with open(out) as f:
            pal = json.load(f)
    except (OSError, ValueError):
        return {"image": image, "error": "unreadable palette"}
    return {"image": image, "file": out, "palette": {"special": pal.get("special", {}), "colors": pal.get("colors", {})}}


# ── A palette you already have ───────────────────────────────────────────────
HEX = __import__("re").compile(r"^#[0-9a-fA-F]{6}$")
SLOTS = {"background", "foreground", "cursor"} | {"color%d" % i for i in range(16)}


def clean_palette(doc):
    """{special, colors} reduced to known slots holding #rrggbb, or None when it has no
    colours worth wearing. The input is a hand-editable scheme file or an extractor's
    output, so it is checked rather than trusted (it ends up in terminals' escape
    sequences and app theme files)."""
    if not isinstance(doc, dict):
        return None
    out = {"special": {}, "colors": {}}
    for sec in ("special", "colors"):
        part = doc.get(sec)
        if isinstance(part, dict):
            for k, v in part.items():
                if k in SLOTS and isinstance(v, str) and HEX.match(v):
                    out[sec][k] = v.lower()
    return out if len(out["colors"]) >= 8 and "background" in out["special"] else None


def palette_json(raw):
    try:
        doc = clean_palette(json.loads(raw))
    except ValueError:
        doc = None
    if doc is None:
        return {"image": "json", "error": "not a palette"}
    key = hashlib.sha1(json.dumps(doc, sort_keys=True).encode()).hexdigest()[:20]
    d = os.path.join(ROOT, "json-" + key)
    out = os.path.join(d, "out", "colors.json")
    if not os.path.isfile(out):
        os.makedirs(os.path.dirname(out), exist_ok=True)
        spec = importlib.util.spec_from_file_location("wal_from_json", os.path.join(HERE, "wal-from-json.py"))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        tmp = out + ".tmp"
        with open(tmp, "w") as f:
            json.dump(mod.build(doc, {}), f, indent=4)
        os.replace(tmp, out)
        _prune()
    else:
        os.utime(d)
    return {"image": "json", "file": out, "palette": doc}


# ── Terminals ─────────────────────────────────────────────────────────────────
def children(pid, proc="/proc"):
    out = []
    try:
        for tid in os.listdir(os.path.join(proc, str(pid), "task")):
            try:
                with open(os.path.join(proc, str(pid), "task", tid, "children")) as f:
                    out += [int(x) for x in f.read().split()]
            except (OSError, ValueError):
                pass
    except OSError:
        pass
    return out


def ptys_of(pid, proc="/proc"):
    """The pseudo-terminals the processes under `pid` read from (its shells'), without
    the pid itself (a terminal emulator holds the master, not a pts)."""
    seen, found, todo = set(), [], children(pid, proc)
    while todo and len(seen) < WALK_MAX:
        p = todo.pop()
        if p in seen:
            continue
        seen.add(p)
        try:
            tty = os.readlink(os.path.join(proc, str(p), "fd", "0"))
        except OSError:
            tty = ""
        if tty.startswith("/dev/pts/") and tty[9:].isdigit() and tty not in found:
            found.append(tty)
        todo += children(p, proc)
    return found


def allowed_palette(path):
    real = os.path.realpath(path)
    return os.path.isfile(real) and (real.startswith(os.path.realpath(ROOT) + os.sep)
                                     or real == os.path.realpath(os.path.join(WAL_CACHE, "colors.json")))


def terminals(path, pids):
    if not allowed_palette(path):
        return {"sent": 0, "error": "not a palette this shell made"}
    from pywal import sequences, theme
    seq = sequences.create_sequences(theme.file(path))
    sent = 0
    uid = os.getuid()
    for pid in pids:
        for tty in ptys_of(pid):
            try:
                if os.stat(tty).st_uid != uid:
                    continue
                with open(tty, "w") as f:
                    f.write(seq)
                sent += 1
            except OSError:
                pass
    return {"sent": sent}


def main(argv):
    if len(argv) >= 2 and argv[0] == "palette":
        rest = argv[2:]
        name = rest[rest.index("--key") + 1] if "--key" in rest and rest.index("--key") + 1 < len(rest) else ""
        print(json.dumps(palette(argv[1], "--light" in rest, name)))
        return 0
    if argv and argv[0] == "palette-json":
        print(json.dumps(palette_json(os.environ.get("WS_PALETTE", ""))))
        return 0
    if len(argv) >= 3 and argv[0] == "terminals":
        pids = [int(p) for p in argv[2:] if p.isdigit() and int(p) > 1]
        print(json.dumps(terminals(argv[1], pids)))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
