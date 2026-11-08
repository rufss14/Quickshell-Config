#!/usr/bin/env python3
"""Press a keybind inside Discord's window.

    discord-press.py ctrl+shift+s [--address 0x55e82b0affc0] [--class discord ...]
    discord-press.py --probe          # report which injection tools exist, press nothing

Exists because screen share and camera have NO Discord RPC command — the only way to
reach them is to act like a user and press Discord's own keybind. Everything else the
shell does with Discord is real RPC; this is the one part that isn't.

── Why not just wtype ────────────────────────────────────────────────────────
Because Discord runs under XWAYLAND, and that changes which injection method can
possibly work.

`wtype` speaks the Wayland virtual-keyboard protocol. Against an X11 client it EXITS 0
having delivered the keystroke precisely nowhere — no error, no warning, nothing in any
log. Measured here: focus confirmed on Discord, `wtype` exit 0, Discord's mute state
unchanged. A silent success is the worst failure mode there is, and it's why the button
"did nothing" for a while with no evidence to go on.

X11 clients need XTEST (`xdotool key`), which the X server delivers as genuine input.
Note that `xdotool key --window <id>` is NOT the same thing: that uses XSendEvent, and
Chromium/Electron deliberately ignore synthetic events sent that way. The window has to
be really focused and the key really injected.

── Choosing a window ─────────────────────────────────────────────────────────
`xdotool search --class discord` returns THREE windows here — the real one plus a 10x10
and a 200x200 helper. Activating a helper would focus nothing you can see and send the
keystroke into it. Largest-area wins, with a floor so a run with only helpers around
fails loudly instead of quietly pressing keys at a 10x10 window.

── Not everyone runs the official client ─────────────────────────────────────
Vesktop, WebCord, Legcord and friends all speak the same RPC socket, so every other
part of this feature is client-agnostic for free. Only window matching isn't, so the
classes to look for are PASSED IN (`--class`, repeatable) rather than baked in. The
shell reads them from discord-rpc.json; the default below is only for running this by
hand. Match is by prefix, so `discord` also covers Canary and PTB.

Exit codes: 0 pressed · 2 no Discord window · 3 no injection tool · 4 bad keyspec.
"""

import argparse, re, shutil, subprocess, sys, time

# Only for standalone runs. The shell always passes --class explicitly, sourced from
# discord-rpc.json — see DEFAULT_WINDOW_CLASSES in discord-rpc.py, which is the list
# that actually governs, and the note there on which of these are verified.
DEFAULT_CLASSES = ["discord", "vesktop", "webcord", "legcord", "armcord", "dorion"]

# xdotool's modifier names. The keyspec is user-supplied (it comes from
# discord-rpc.json), so it is validated rather than passed to a shell — nothing here
# ever builds a command string.
MODS = {"ctrl", "control", "shift", "alt", "super", "meta", "hyper", "altgr"}
KEY_RE = re.compile(r"^[A-Za-z0-9_]+$")

# wtype spells its modifiers differently, and has no "super"/"meta".
WTYPE_MODS = {"ctrl": "ctrl", "control": "ctrl", "shift": "shift", "alt": "alt",
              "altgr": "altgr", "super": "logo", "meta": "logo", "hyper": "logo"}

# Anything smaller than this is one of Discord's invisible helper windows.
MIN_WINDOW_AREA = 10000


def parse_spec(spec):
    """"ctrl+shift+s" → (["ctrl", "shift"], "s"). Raises ValueError on anything odd."""
    parts = [p.strip().lower() for p in spec.split("+") if p.strip()]
    if not parts:
        raise ValueError("empty keyspec")
    key, mods = parts[-1], parts[:-1]
    if not KEY_RE.match(key):
        raise ValueError("bad key %r" % key)
    for m in mods:
        if m not in MODS:
            raise ValueError("unknown modifier %r (use %s)"
                             % (m, ", ".join(sorted(MODS))))
    return mods, key


def run(cmd, timeout=5):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None


def x11_window(classes):
    """Discord's real X11 window id, or None. Largest wins — see the header.

    One search per class rather than a regex alternation: xdotool's --class takes a
    POSIX ERE and I have not verified on this machine whether it compiles it with
    REG_ICASE (xdotool isn't installed here — see the header of the shell's setup
    notes). Several small exact searches have no such ambiguity, cost one process each,
    and can't silently match nothing because of a case mismatch. Anchored with ^ so
    `discord` still picks up discordcanary/discordptb by prefix without matching some
    unrelated window that merely contains the word.
    """
    ids = []
    for cls in classes:
        r = run(["xdotool", "search", "--class", "^" + re.escape(cls)])
        # A class nobody is running exits non-zero. That's the normal case for every
        # entry in the list except yours, so it is not an error.
        if r and r.returncode == 0:
            ids += r.stdout.split()
    if not ids:
        return None

    best, best_area = None, 0
    for wid in dict.fromkeys(ids):   # de-duped, order preserved
        g = run(["xdotool", "getwindowgeometry", "--shell", wid])
        if not g or g.returncode != 0:
            continue
        dims = dict(line.split("=", 1) for line in g.stdout.splitlines() if "=" in line)
        try:
            area = int(dims.get("WIDTH", 0)) * int(dims.get("HEIGHT", 0))
        except ValueError:
            continue
        if area > best_area:
            best, best_area = wid, area

    return best if best_area >= MIN_WINDOW_AREA else None


def press_x11(spec, classes):
    wid = x11_window(classes)
    if not wid:
        return False

    # --sync blocks until the window really is active. Without it the key races the
    # activation and lands wherever focus happened to be — which, when that's a
    # terminal or a browser, is a keystroke sent to the wrong application.
    a = run(["xdotool", "windowactivate", "--sync", wid], timeout=8)
    if not a or a.returncode != 0:
        return False

    # Electron settles its focus a frame or two after the X server reports the window
    # active; without this the first keystroke after a workspace switch gets dropped.
    time.sleep(0.15)

    k = run(["xdotool", "key", "--clearmodifiers", spec])
    return bool(k and k.returncode == 0)


def press_wayland(spec, address):
    """Fallback for a Discord that is NOT running under XWayland.

    Untested against a real native-Wayland Discord — the official client is X11 here.
    Kept because it's the correct method for that case and costs nothing, but the X11
    path above is the one that actually runs on this machine.
    """
    if not shutil.which("wtype"):
        return False

    if address:
        run(["hyprctl", "dispatch",
             'hl.dsp.focus({ window = "address:%s" })' % address])
        time.sleep(0.2)

    mods, key = parse_spec(spec)
    argv = ["wtype"]
    for m in mods:
        argv += ["-M", WTYPE_MODS[m]]
    argv += ["-k", key]
    for m in reversed(mods):
        argv += ["-m", WTYPE_MODS[m]]

    r = run(argv)
    return bool(r and r.returncode == 0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("keyspec", nargs="?", default="")
    ap.add_argument("--address", default="", help="Hyprland window address, Wayland path")
    ap.add_argument("--class", dest="classes", action="append", default=[],
                    metavar="NAME", help="window class to match; repeatable")
    # ── Why a probe mode ──────────────────────────────────────────────────────
    # Without it the shell can only discover a missing xdotool by pressing the button
    # and reading an exit code — i.e. the user finds out by the thing not working. This
    # lets the card disable the button up front and say what to install, which is the
    # difference between "broken" and "not set up yet". Prints one line of
    # `tool=0|1` pairs; presses nothing and always exits 0.
    ap.add_argument("--probe", action="store_true",
                    help="report available tools and exit")
    args = ap.parse_args()

    if args.probe:
        sys.stdout.write("xdotool=%d wtype=%d\n"
                         % (bool(shutil.which("xdotool")), bool(shutil.which("wtype"))))
        return 0

    if not args.keyspec:
        sys.stderr.write("discord-press: no keyspec given\n")
        return 4

    classes = args.classes or DEFAULT_CLASSES

    try:
        parse_spec(args.keyspec)
    except ValueError as e:
        sys.stderr.write("discord-press: %s\n" % e)
        return 4

    if shutil.which("xdotool") and press_x11(args.keyspec, classes):
        return 0

    if press_wayland(args.keyspec, args.address):
        return 0

    if not shutil.which("xdotool") and not shutil.which("wtype"):
        sys.stderr.write("discord-press: neither xdotool nor wtype is installed\n")
        return 3

    sys.stderr.write("discord-press: could not find or focus a Discord window\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
