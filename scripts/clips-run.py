#!/usr/bin/env python3
"""clips-run.py — the runner behind services/Clips.qml (gpu-screen-recorder).

    scripts/clips-run.py start  <rundir> <replay|record> <argv-json>   # the daemon
    scripts/clips-run.py signal <rundir> <save|save:N|record|pause|stop>
    scripts/clips-run.py saved  <rundir> <path> <type>    # the recorder's -sc hook
    scripts/clips-run.py set    <rundir> <naming> <window|plain>   # a setting the hook reads
    scripts/clips-run.py check  <rundir>                  # reconcile a dead daemon
    scripts/clips-run.py status <rundir>                  # diagnostic

── Why a detached daemon ────────────────────────────────────────────────────────
The replay buffer is the whole point: it holds the last N minutes, and losing it
on a shell reload (ALT+Q, or any QML save — Quickshell hot-reloads) would throw
away exactly the moment you were about to clip. A recording killed mid-file is
worse. So the recorder is NOT a Quickshell child: QML `setsid`-detaches this
script, which runs gpu-screen-recorder and waits on it — update-run.sh's shape. Talking goes through FILES in
<rundir>:

  state.json    written here (temp + rename), watched by QML
  events.jsonl  one line per saved file, appended by the -sc hook, watched by QML
  recorder.log  the recorder's own output, for `status` and the error line
  lock          flock'd for the daemon's life: a second `start` exits 75

── Signals, not a socket ────────────────────────────────────────────────────────
gpu-screen-recorder takes SIGUSR1 (save the buffer), SIGRTMIN+1..6 (save the last
10s/30s/60s/5m/10m/30m), SIGRTMIN (start/stop a regular recording during the
buffer, into -ro), SIGUSR2 (pause) and SIGINT (stop; a recording is saved).
Newer builds also have an -ipc socket; signals are the interface every build
since 5.x shares, so they're what this uses.

The pid is checked against /proc/<pid>/comm before every signal: after a crash or
a reboot the state file's pid may belong to something else entirely.

── How a saved file is learned ──────────────────────────────────────────────────
The recorder runs `-sc <hook> <path> <type>` after writing each file — replay,
regular or screenshot. scripts/clips-saved.sh is that hook; it execs this script's
`saved`, which appends to events.jsonl. That covers saves nobody asked QML for, too:
a keybind that signals the recorder directly still gets its clip announced.

── Clips named after the window (2026-10-18) ─────────────────────────────────────
With `naming` = "window" (the default; `set … naming plain` turns it off) a saved file is renamed in the
hook to `<Game>_Replay_2026-10-18_21-41-05.mp4` — the active window's name (`window_label`: the title
for a Steam / Proton / Wine window, the class for anything else) in front of the recorder's own
name, so the library can group by game. A replay is named for the window at the moment it is saved. A
recording is named for the window when it STARTED, because by the time it ends you are somewhere
else: a plain recording gets the label put into its `-o` path before the recorder launches; a regular
recording during the buffer stores it in state (`label`) when it is toggled on. The event carries the
NEW path. The label never contains `_` (that is what the library splits on) or anything but
letters, digits, `.` and `-`.

Stdlib only. `python3 scripts/test-clips-run.py` covers it without a recorder.
"""

import fcntl
import json
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
HOOK = HERE / "clips-saved.sh"
RECORDER = "gpu-screen-recorder"
# Linux truncates `comm` to 15 characters.
COMM_PREFIX = "gpu-screen-reco"

# SIGRTMIN + n saves the last N seconds (the man page's table).
SAVE_OFFSETS = {10: 1, 30: 2, 60: 3, 300: 4, 600: 5, 1800: 6}

EVENTS_KEEP = 200        # lines kept once the log grows past twice that
ERROR_LINES = 4          # of the recorder's log, into `error` when it dies


# ── State ────────────────────────────────────────────────────────────────────
def _lock(rundir, name):
    """An exclusive flock on <rundir>/<name>, for read-modify-write of a file three
    processes touch (the daemon, `signal`, the hook)."""
    fd = os.open(rundir / name, os.O_RDWR | os.O_CREAT, 0o600)
    fcntl.flock(fd, fcntl.LOCK_EX)
    return fd


def read_state(rundir):
    try:
        with open(rundir / "state.json") as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def write_state(rundir, d):
    tmp = rundir / "state.json.tmp"
    with open(tmp, "w") as f:
        json.dump(d, f)
    os.replace(tmp, rundir / "state.json")


def update_state(rundir, **changes):
    fd = _lock(rundir, "state.lock")
    try:
        d = read_state(rundir)
        d.update(changes)
        write_state(rundir, d)
        return d
    finally:
        os.close(fd)


def now_ms():
    return int(time.time() * 1000)


# ── The recorder's pid, checked ──────────────────────────────────────────────
def live_pid(rundir):
    """The recorder's pid if it is still OUR recorder, else None."""
    pid = read_state(rundir).get("pid")
    if not isinstance(pid, int) or pid <= 1:
        return None
    try:
        comm = Path(f"/proc/{pid}/comm").read_text().strip()
    except OSError:
        return None
    return pid if comm.startswith(COMM_PREFIX) else None


# ── Validation of what QML hands the daemon ──────────────────────────────────
def valid_argv(argv):
    """The argv came from clips.js recorderArgv, but it crossed a process boundary
    as a string: re-check its shape before running it. A list of strings, the
    recorder first, and no -sc of its own (the hook is ours to add)."""
    return (isinstance(argv, list) and len(argv) >= 3
            and all(isinstance(a, str) and "\0" not in a for a in argv)
            and argv[0] == RECORDER and "-sc" not in argv)


def output_of(argv):
    try:
        return argv[argv.index("-o") + 1]
    except (ValueError, IndexError):
        return ""


# ── Naming a clip after what you were playing ────────────────────────────────
def clean_label(raw):
    """Letters, digits, dots and hyphens only (no `_`: the library splits on it), at most 32."""
    s = re.sub(r"[^A-Za-z0-9.]+", "-", str(raw or ""))
    s = re.sub(r"-{2,}", "-", s).strip("-.")
    return s[:32].strip("-.")


def window_label(cls, title):
    """The name a window gives a clip, "" for none. A game's own title is its name; a window of
    anything else is its class — a clip cut in a browser is "firefox_…", not the page's name. Games
    run under Steam, Proton or Wine have a class that says nothing (steam_app_1245620, gamescope,
    game.exe), so those use the title. Our own windows are nobody's game."""
    c = str(cls or "").strip()
    t = str(title or "").strip()
    low = c.lower()
    if low.startswith(("quickshell", "org.quickshell")):
        return ""
    by_title = (low.startswith("steam_app_") or low in ("gamescope", "steam_proton")
                or low.endswith(".exe") or "wine" in low or "proton" in low)
    if by_title and t:
        return clean_label(t)
    if "." in c and not by_title:
        c = c.rsplit(".", 1)[-1]          # org.vinegarhq.Sober → Sober
    return clean_label(c)


def active_window():
    """(class, title) of the focused window, or None (no compositor, hyprctl slow or broken)."""
    try:
        r = subprocess.run(["hyprctl", "activewindow", "-j"], capture_output=True, text=True, timeout=1.5)
        d = json.loads(r.stdout or "{}")
        if not isinstance(d, dict):
            return None
        return str(d.get("class", "")), str(d.get("title", ""))
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None


def current_label():
    aw = active_window()
    return window_label(*aw) if aw else ""


KINDS = re.compile(r"^(Replay|Recording|Video)_")


def with_label(name, label):
    """`Replay_…` → `<label>_Replay_…`; anything else (already named, a rename, no label) unchanged."""
    return f"{label}_{name}" if label and KINDS.match(name) else name


def renamed(path, label):
    """Rename a saved file to carry `label`, never over another file; the new path (or the old one when
    there is nothing to do or the rename failed)."""
    p = Path(path)
    new = with_label(p.stem, label)
    if new == p.stem or not p.is_file():
        return path
    dest = p.with_name(new + p.suffix)
    i = 2
    while dest.exists():
        dest = p.with_name(f"{new}-{i}{p.suffix}")
        i += 1
    try:
        os.rename(p, dest)
    except OSError:
        return path
    return str(dest)


def naming_on(rundir):
    return read_state(rundir).get("naming") != "plain"


# ── start: the daemon ────────────────────────────────────────────────────────
def cmd_start(rundir, mode, argv_json):
    rundir.mkdir(parents=True, exist_ok=True)
    # The lock FIRST: a refused start must not write over a live daemon's state.
    lock_fd = os.open(rundir / "lock", os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return 75       # already running: starting is idempotent

    try:
        argv = json.loads(argv_json)
    except ValueError:
        argv = None
    if mode not in ("replay", "record") or not valid_argv(argv):
        update_state(rundir, state="idle", pid=0, error="Refused an invalid recorder command", at=now_ms())
        return 2

    label = ""
    if mode == "record" and naming_on(rundir):
        label = current_label()
        i = argv.index("-o") + 1 if "-o" in argv else 0
        if label and i and i < len(argv):
            o = Path(argv[i])
            argv[i] = str(o.with_name(with_label(o.stem, label) + o.suffix))

    out = output_of(argv)
    folder = out if mode == "replay" else os.path.dirname(out)
    if folder:
        os.makedirs(folder, exist_ok=True)

    env = dict(os.environ, CLIPS_RUNDIR=str(rundir))
    log = open(rundir / "recorder.log", "w")
    try:
        proc = subprocess.Popen(argv + ["-sc", str(HOOK)], stdin=subprocess.DEVNULL,
                                stdout=log, stderr=subprocess.STDOUT, env=env)
    except OSError as e:
        update_state(rundir, state="idle", pid=0, error=f"Couldn't start the recorder: {e.strerror}",
                     at=now_ms())
        return 1

    started = now_ms()
    update_state(rundir, state=mode, pid=proc.pid, since=started, output=out,
                 recording=(mode == "record"), recordSince=started if mode == "record" else 0,
                 paused=False, stopping=False, error="", at=started, label=label)

    # A TERM or HUP to the daemon (logout, `kill`) stops the recorder the way the
    # user would: SIGINT, so a recording is written out rather than cut off.
    def forward(_sig, _frm):
        update_state(rundir, stopping=True)
        try:
            proc.send_signal(signal.SIGINT)
        except ProcessLookupError:
            pass
    for s in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        signal.signal(s, forward)

    code = proc.wait()
    log.close()

    st = read_state(rundir)
    error = ""
    if code != 0 and not st.get("stopping"):
        error = last_lines(rundir / "recorder.log", ERROR_LINES) or f"The recorder exited ({code})"
    update_state(rundir, state="idle", pid=0, recording=False, paused=False, stopping=False,
                 code=code, error=error, at=now_ms())
    return 0


def last_lines(path, n):
    try:
        lines = [l.strip() for l in Path(path).read_text(errors="replace").splitlines() if l.strip()]
    except OSError:
        return ""
    # The recorder prints its fps counter every second; that's not an error.
    lines = [l for l in lines if not l.lower().startswith(("update fps", "fps:", "damage"))]
    return " · ".join(lines[-n:])


# ── signal: talk to the running recorder ─────────────────────────────────────
def signal_for(what, mode):
    """(signal number, a state change) for a command, or (None, reason)."""
    if what == "stop":
        return signal.SIGINT, {"stopping": True}
    if what == "save" or what.startswith("save:"):
        if mode != "replay":
            return None, "No replay buffer is running"
        if what == "save":
            return signal.SIGUSR1, {}
        try:
            n = int(what.split(":", 1)[1])
        except ValueError:
            return None, "Bad length"
        if n not in SAVE_OFFSETS:
            return None, "The recorder can't cut that length on a signal"
        return signal.SIGRTMIN + SAVE_OFFSETS[n], {}
    if what == "record":
        if mode != "replay":
            return None, "A regular recording only toggles during the buffer"
        return signal.SIGRTMIN, None     # the toggle: resolved against state below
    if what == "pause":
        if mode != "record":
            return None, "Only a recording pauses"
        return signal.SIGUSR2, None
    return None, "Unknown command"


def cmd_signal(rundir, what):
    pid = live_pid(rundir)
    if pid is None:
        print("not running", file=sys.stderr)
        return 1
    fd = _lock(rundir, "state.lock")
    try:
        st = read_state(rundir)
        sig, change = signal_for(what, st.get("state"))
        if sig is None:
            print(change, file=sys.stderr)
            return 1
        if change is None and what == "record":
            on = not st.get("recording")
            change = {"recording": on, "recordSince": now_ms() if on else 0}
            if on:
                change["label"] = current_label() if naming_on(rundir) else ''
        elif change is None and what == "pause":
            change = {"paused": not st.get("paused")}
        os.kill(pid, sig)
        st.update(change)
        write_state(rundir, st)
    except ProcessLookupError:
        print("not running", file=sys.stderr)
        return 1
    finally:
        os.close(fd)
    return 0


# ── saved: the -sc hook ──────────────────────────────────────────────────────
def cmd_saved(rundir, path, kind):
    if not path or not os.path.isabs(path):
        return 2
    rundir.mkdir(parents=True, exist_ok=True)
    # Named after the window (see the header). A recording's label was taken when it started.
    if kind in ("replay", "regular") and naming_on(rundir):
        st = read_state(rundir)
        label = st.get("label", "") if kind == "regular" and st.get("label") else current_label()
        path = renamed(path, label)
    line = json.dumps({"path": path, "type": kind, "t": now_ms()}) + "\n"
    fd = _lock(rundir, "events.lock")
    try:
        ev = rundir / "events.jsonl"
        with open(ev, "a") as f:
            f.write(line)
        # Kept short. QML reads by time, not line count, so a trim loses nothing.
        lines = ev.read_text().splitlines(keepends=True)
        if len(lines) > EVENTS_KEEP * 2:
            tmp = rundir / "events.jsonl.tmp"
            tmp.write_text("".join(lines[-EVENTS_KEEP:]))
            os.replace(tmp, ev)
    finally:
        os.close(fd)
    # A regular recording started during the buffer ends by being saved.
    if kind == "regular" and read_state(rundir).get("state") == "replay":
        update_state(rundir, recording=False, recordSince=0)
    return 0


SETTINGS = {"naming": ("window", "plain")}


def cmd_set(rundir, key, value):
    """A setting the hook reads while the buffer runs (it can't be an argument: the daemon is
    started once). Kept in state.json, which every start merges into rather than replaces."""
    if key not in SETTINGS or value not in SETTINGS[key]:
        print("Unknown setting", file=sys.stderr)
        return 2
    rundir.mkdir(parents=True, exist_ok=True)
    update_state(rundir, **{key: value})
    return 0


def cmd_check(rundir):
    """Reconcile a state file whose daemon is gone (killed -9, a crash): it would
    otherwise claim a buffer that isn't running. QML runs this once at start.
    Also makes both files exist, so QML's FileViews never read a missing one (each
    such read is a logged warning)."""
    rundir.mkdir(parents=True, exist_ok=True)
    (rundir / "events.jsonl").touch()
    fd = _lock(rundir, "state.lock")
    try:
        st = read_state(rundir)
        if not (rundir / "state.json").exists():
            write_state(rundir, {"state": "idle", "pid": 0, "error": "", "at": now_ms()})
        elif st.get("state") in ("replay", "record") and live_pid(rundir) is None:
            st.update(state="idle", pid=0, recording=False, paused=False, stopping=False, at=now_ms())
            write_state(rundir, st)
    finally:
        os.close(fd)
    return 0


def cmd_status(rundir):
    st = read_state(rundir)
    st["alive"] = live_pid(rundir) is not None
    try:
        st["events"] = sum(1 for _ in open(rundir / "events.jsonl"))
    except OSError:
        st["events"] = 0
    print(json.dumps(st, indent=2))
    return 0


def main(argv):
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    cmd, rundir = argv[1], Path(argv[2])
    if cmd == "start" and len(argv) == 5:
        return cmd_start(rundir, argv[3], argv[4])
    if cmd == "signal" and len(argv) == 4:
        return cmd_signal(rundir, argv[3])
    if cmd == "saved" and len(argv) >= 4:
        return cmd_saved(rundir, argv[3], argv[4] if len(argv) > 4 else "")
    if cmd == "set" and len(argv) == 5:
        return cmd_set(rundir, argv[3], argv[4])
    if cmd == "check":
        return cmd_check(rundir)
    if cmd == "status":
        return cmd_status(rundir)
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
