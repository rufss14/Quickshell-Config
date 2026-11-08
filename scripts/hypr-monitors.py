#!/usr/bin/env python3
"""hypr-monitors.py — write real hl.monitor() lines into hardware.lua.

    hypr-monitors.py <path/to/hardware.lua>   rewrite the monitor block in place
    hypr-monitors.py --print                  print the lines, touch nothing
    hypr-monitors.py --write-spec <file>      write a layout given as JSON on stdin
    hypr-monitors.py --print-spec             print that layout's lines, touch nothing

The shipped hardware.lua applies one generic line to every output
(`hl.monitor({ output = "", mode = "preferred", ... })`). When Hyprland is
running we can do better: this asks `hyprctl monitors -j` and writes one line
per connected output with its real mode, position and scale, wrapped in marker
comments so a later re-run just refreshes them. Everything else in the file is
left byte-for-byte.

Fails soft — a clear message and a non-zero exit — when hyprctl isn't reachable
(installing from a TTY, a different session), so the caller can carry on with
the generic line.
"""
import json
import re
import subprocess
import sys

BEGIN = "-- >>> hypr-monitors.py — auto-detected; re-run the script to refresh >>>"
END = "-- <<< hypr-monitors.py <<<"


def monitors():
    out = subprocess.run(
        ["hyprctl", "monitors", "-j"],
        capture_output=True, text=True, check=True,
    ).stdout
    return json.loads(out)


def _scale(v):
    f = float(v)
    return int(f) if f.is_integer() else round(f, 6)


def line_for(m):
    name = m["name"]
    if m.get("disabled"):
        return f'hl.monitor({{ output = "{name}", disabled = true }})'
    hz = round(m.get("refreshRate", 60))
    mode = f'{m["width"]}x{m["height"]}@{hz}'
    pos = f'{m.get("x", 0)}x{m.get("y", 0)}'
    extra = ""
    if m.get("transform"):
        extra += f', transform = {int(m["transform"])}'
    if m.get("vrr"):
        extra += ", vrr = 1"
    return (
        f'hl.monitor({{ output = "{name}", mode = "{mode}", '
        f'position = "{pos}", scale = {_scale(m.get("scale", 1))}{extra} }})'
    )


def build_block():
    mons = monitors()
    if not mons:
        raise SystemExit("hypr-monitors: hyprctl reported no monitors — skipping")
    return "\n".join([BEGIN] + [line_for(m) for m in mons] + [END])


def rewrite(path, block):
    with open(path) as f:
        src = f.read()

    # The managed region is everything between the "── Monitors" header and the
    # blank line before the next section — the shipped generic line and its
    # comment, or a block an earlier run of this script wrote. Replaced whole, so
    # re-running is idempotent.
    m = re.search(
        r"(^-- ── Monitors[^\n]*\n)(.*?)(\n[ \t]*\n)",
        src, flags=re.S | re.M,
    )
    if m:
        src = src[: m.start(2)] + block + src[m.end(2):]
    else:
        src = block + "\n\n" + src

    with open(path, "w") as f:
        f.write(src)


# ── A layout from Settings › Displays ──────────────────────────────────────────
# `--write-spec <hardware.lua>` reads a JSON list on stdin (services/displays.js spec():
# name, width, height, refresh, x, y, scale, transform, vrr — or name + disabled) and
# writes it as the monitor block. Every field is checked before anything is written: the
# values end up inside Lua source, so a name is a name and a number is a number.
NAME_RE = re.compile(r"^[A-Za-z0-9._-]{1,64}$")


def _num(v, lo, hi, kind=float):
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        raise ValueError("not a number: %r" % (v,))
    v = kind(v)
    if not (lo <= v <= hi):
        raise ValueError("out of range: %r" % (v,))
    return v


def from_spec(items):
    """Validated spec → the dicts line_for() reads (hyprctl's shape)."""
    if not isinstance(items, list) or not items:
        raise ValueError("expected a non-empty list")
    out, names = [], set()
    for it in items:
        if not isinstance(it, dict) or not isinstance(it.get("name"), str) or not NAME_RE.match(it["name"]):
            raise ValueError("bad monitor name")
        if it["name"] in names:
            raise ValueError("duplicate monitor")
        names.add(it["name"])
        if it.get("disabled") is True:
            out.append({"name": it["name"], "disabled": True})
            continue
        out.append({
            "name": it["name"],
            "width": _num(it.get("width"), 320, 16384, int),
            "height": _num(it.get("height"), 200, 16384, int),
            "refreshRate": _num(it.get("refresh"), 1, 1000),
            "x": _num(it.get("x"), -65536, 65536, int),
            "y": _num(it.get("y"), -65536, 65536, int),
            "scale": _num(it.get("scale"), 0.25, 4),
            "transform": _num(it.get("transform", 0), 0, 7, int),
            "vrr": it.get("vrr") is True,
        })
    if all(m.get("disabled") for m in out):
        raise ValueError("at least one monitor must stay on")
    return out


def write_spec(path, items):
    with open(path) as f:
        if not re.search(r"^-- ── Monitors", f.read(), flags=re.M):
            # Not the bundled hardware.lua: refuse rather than prepend lines to a file
            # someone else wrote.
            raise ValueError("%s has no '-- ── Monitors' section" % path)
    block = "\n".join([BEGIN] + [line_for(m) for m in from_spec(items)] + [END])
    rewrite(path, block)
    return block


def main():
    args = sys.argv[1:]
    if args[:1] == ["--write-spec"] and len(args) == 2:
        try:
            block = write_spec(args[1], json.loads(sys.stdin.read() or "null"))
        except (ValueError, OSError) as e:
            print(json.dumps({"ok": False, "error": str(e)}))
            sys.exit(2)
        print(json.dumps({"ok": True, "lines": block.count("hl.monitor(")}))
        return
    if args[:1] == ["--print-spec"]:
        # The same lines, printed, for a config this page may not edit (copy & paste).
        try:
            items = from_spec(json.loads(sys.stdin.read() or "null"))
        except ValueError as e:
            print(json.dumps({"ok": False, "error": str(e)}))
            sys.exit(2)
        print("\n".join(line_for(m) for m in items))
        return
    try:
        block = build_block()
    except FileNotFoundError:
        raise SystemExit("hypr-monitors: hyprctl not found — skipping monitor setup")
    except subprocess.CalledProcessError:
        raise SystemExit("hypr-monitors: hyprctl not answering — skipping monitor setup")

    if not args or args[0] == "--print":
        print(block)
        return

    rewrite(args[0], block)
    n = block.count("hl.monitor(")
    print(f"hypr-monitors: wrote {n} monitor line{'' if n == 1 else 's'} to {args[0]}")


if __name__ == "__main__":
    main()
