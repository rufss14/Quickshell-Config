#!/usr/bin/env python3
"""test-clips-run.py — scripts/clips-run.py against a FAKE gpu-screen-recorder.

    python3 scripts/test-clips-run.py

Safe to run: everything happens in a temp dir. The fake recorder is a bash script
on a temp PATH that answers the same signals the real one does (SIGUSR1 saves a
"replay", SIGRTMIN toggles a regular recording and saves it on the way off, SIGINT
exits) and runs the -sc hook like the real one — so the whole loop is exercised:
daemon → state.json → signal → hook → events.jsonl. It never captures a screen.
"""

import json
import os
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
RUN = HERE / "clips-run.py"
sys.path.insert(0, str(HERE))
import importlib.util
spec = importlib.util.spec_from_file_location("clips_run", RUN)
cr = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cr)

FAKE = r"""#!/bin/bash
out=""; sc=""; fail=""
while [ $# -gt 0 ]; do
  case "$1" in -o) out="$2"; shift;; -sc) sc="$2"; shift;; --fail) fail=1;; esac
  shift
done
if [ -n "$fail" ]; then echo "gsr error: failed to capture monitor"; exit 1; fi
rec=0
trap '"$sc" "$out/Replay_1.mp4" replay' USR1
trap '"$sc" "$out/Replay_30.mp4" replay' RTMIN+2
trap 'if [ $rec = 1 ]; then rec=0; "$sc" "$out/Video_1.mp4" regular; else rec=1; fi' RTMIN
trap 'exit 0' INT
echo "update fps: 60"
while :; do sleep 0.05; done
"""

passed = failed = 0


def check(name, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"  FAIL  {name}\n          got  {got!r}\n          want {want!r}")


def wait_for(pred, timeout=5.0):
    end = time.time() + timeout
    while time.time() < end:
        if pred():
            return True
        time.sleep(0.05)
    return False


def main():
    tmp = Path(tempfile.mkdtemp(prefix="clips-test-"))
    bindir, rundir, out = tmp / "bin", tmp / "run", tmp / "Clips"
    bindir.mkdir()
    fake = bindir / "gpu-screen-recorder"
    fake.write_text(FAKE)
    fake.chmod(0o755)
    env = dict(os.environ, PATH=f"{bindir}:{os.environ['PATH']}")

    def run(*args):
        return subprocess.run([sys.executable, str(RUN), *args], env=env,
                              capture_output=True, text=True, timeout=10)

    # ── Pure pieces ──────────────────────────────────────────────────────────
    check("valid argv", cr.valid_argv(["gpu-screen-recorder", "-w", "DP-1"]), True)
    check("argv: another binary", cr.valid_argv(["sh", "-c", "x"]), False)
    check("argv: brings its own -sc", cr.valid_argv(["gpu-screen-recorder", "-sc", "/x"]), False)
    check("argv: not strings", cr.valid_argv(["gpu-screen-recorder", "-f", 60]), False)
    check("argv: not a list", cr.valid_argv("gpu-screen-recorder -w DP-1"), False)
    check("argv: NUL", cr.valid_argv(["gpu-screen-recorder", "-w", "a\0b"]), False)
    check("output", cr.output_of(["gpu-screen-recorder", "-o", "/v"]), "/v")
    check("output: none", cr.output_of(["gpu-screen-recorder", "-o"]), "")
    check("signal: save", cr.signal_for("save", "replay")[0], signal.SIGUSR1)
    check("signal: save 30s", cr.signal_for("save:30", "replay")[0], signal.SIGRTMIN + 2)
    check("signal: save 45s refused", cr.signal_for("save:45", "replay")[0], None)
    check("signal: save while recording refused", cr.signal_for("save", "record")[0], None)
    check("signal: pause during replay refused", cr.signal_for("pause", "replay")[0], None)
    check("signal: stop", cr.signal_for("stop", "record")[0], signal.SIGINT)
    check("signal: unknown", cr.signal_for("rm", "replay")[0], None)
    check("log: fps lines are not an error",
          (lambda p: (p.write_text("update fps: 60\nreal problem\nupdate fps: 59\n"),
                      cr.last_lines(p, 4))[1])(tmp / "l.log"), "real problem")

    # ── Not running ──────────────────────────────────────────────────────────
    check("signal with nothing running", run("signal", str(rundir), "save").returncode, 1)
    check("refuses a bad argv", run("start", str(rundir), "replay", '["sh","-c","id"]').returncode, 2)
    check("…and says so", "invalid" in cr.read_state(rundir).get("error", ""), True)

    # ── A replay buffer ──────────────────────────────────────────────────────
    argv = json.dumps(["gpu-screen-recorder", "-w", "DP-1", "-r", "60", "-o", str(out), "-ro", str(out)])
    daemon = subprocess.Popen([sys.executable, str(RUN), "start", str(rundir), "replay", argv], env=env)
    check("daemon comes up", wait_for(lambda: cr.live_pid(rundir) is not None), True)
    st = cr.read_state(rundir)
    check("state: replay", [st.get("state"), st.get("recording"), st.get("error")], ["replay", False, ""])
    check("output folder made", out.is_dir(), True)
    check("a second start is refused", run("start", str(rundir), "replay", argv).returncode, 75)
    check("…without touching the state", cr.read_state(rundir).get("state"), "replay")
    time.sleep(0.3)     # let bash install its traps

    check("save", run("signal", str(rundir), "save").returncode, 0)
    ev = rundir / "events.jsonl"
    check("the hook logged the clip", wait_for(lambda: ev.exists() and "Replay_1" in ev.read_text()), True)
    line = json.loads(ev.read_text().splitlines()[-1])
    check("event shape", [line["path"], line["type"], line["t"] > 0], [str(out / "Replay_1.mp4"), "replay", True])

    check("save 30s", run("signal", str(rundir), "save:30").returncode, 0)
    check("…logged", wait_for(lambda: "Replay_30" in ev.read_text()), True)

    check("record on", run("signal", str(rundir), "record").returncode, 0)
    st = cr.read_state(rundir)
    check("state: recording", [st.get("recording"), st.get("recordSince", 0) > 0], [True, True])
    time.sleep(0.2)
    check("record off", run("signal", str(rundir), "record").returncode, 0)
    check("the regular file is logged",
          wait_for(lambda: "Video_1" in ev.read_text()), True)
    check("…and clears recording", wait_for(lambda: cr.read_state(rundir).get("recording") is False), True)

    check("pause refused during replay", run("signal", str(rundir), "pause").returncode, 1)
    check("stop", run("signal", str(rundir), "stop").returncode, 0)
    check("daemon exits", daemon.wait(timeout=5), 0)
    st = cr.read_state(rundir)
    check("state: idle, no error", [st.get("state"), st.get("error"), st.get("pid")], ["idle", "", 0])

    # ── A recorder that dies ────────────────────────────────────────────────
    bad = json.dumps(["gpu-screen-recorder", "--fail", "-o", str(out / "x.mp4")])
    check("a failing recorder", run("start", str(rundir), "record", bad).returncode, 0)
    st = cr.read_state(rundir)
    check("…reports its own words", [st.get("state"), st.get("error")],
          ["idle", "gsr error: failed to capture monitor"])

    # ── A stale state file (daemon killed -9) ───────────────────────────────
    cr.write_state(rundir, {"state": "replay", "pid": 999999999})
    check("stale pid isn't live", cr.live_pid(rundir), None)
    run("check", str(rundir))
    check("check reconciles it", cr.read_state(rundir).get("state"), "idle")
    fresh = tmp / "fresh"
    run("check", str(fresh))
    check("check makes both files on a fresh dir",
          [(fresh / "state.json").exists(), (fresh / "events.jsonl").exists(),
           cr.read_state(fresh).get("state")], [True, True, "idle"])
    cr.write_state(rundir, {"state": "replay", "pid": os.getpid()})
    check("a pid that isn't a recorder isn't live", cr.live_pid(rundir), None)

    # ── The hook ────────────────────────────────────────────────────────────
    check("hook refuses a relative path", run("saved", str(rundir), "clip.mp4", "replay").returncode, 2)
    for i in range(cr.EVENTS_KEEP * 2 + 5):
        cr.cmd_saved(rundir, f"/v/c{i}.mp4", "replay")
    n = len(ev.read_text().splitlines())
    check("the log is trimmed", n <= cr.EVENTS_KEEP * 2 and n >= cr.EVENTS_KEEP, True)
    check("…keeping the newest", ev.read_text().splitlines()[-1].find(f"c{cr.EVENTS_KEEP * 2 + 4}.mp4") > 0, True)

    # ── Clips named after the window ────────────────────────────────────────
    check("label: a Steam game uses its title", cr.window_label("steam_app_1245620", "Elden Ring"), "Elden-Ring")
    check("label: punctuation and symbols are squashed", cr.window_label("steam_app_1", "ELDEN RING™: Shadow (DLC)"), "ELDEN-RING-Shadow-DLC")
    check("label: gamescope uses the title", cr.window_label("gamescope", "Hades"), "Hades")
    check("label: wine uses the title", cr.window_label("hl2.exe", "Half-Life 2"), "Half-Life-2")
    check("label: a plain app is its class", cr.window_label("firefox", "Some page - Firefox"), "firefox")
    check("label: a reverse-DNS class keeps its last part", cr.window_label("org.vinegarhq.Sober", "Roblox"), "Sober")
    check("label: no underscore ever (the library splits on it)", "_" in cr.window_label("my_game", "x_y"), False)
    check("label: our own windows are nobody's game", cr.window_label("quickshell", "Settings"), "")
    check("label: no window", cr.window_label("", ""), "")
    check("label: a steam game with no title falls back to the class", cr.window_label("steam_app_9", ""), "steam-app-9")
    check("label: capped", len(cr.window_label("steam_app_1", "x" * 90)), 32)
    check("label: only safe characters", bool(__import__("re").fullmatch(r"[A-Za-z0-9.-]*", cr.window_label("steam_app_1", "a/b\\c ../d"))), True)
    check("name: a replay", cr.with_label("Replay_2026-10-18_21-41-05", "Hades"), "Hades_Replay_2026-10-18_21-41-05")
    check("name: a recording", cr.with_label("Recording_2026-10-18_21-41-05", "Hades"), "Hades_Recording_2026-10-18_21-41-05")
    check("name: a rename is left alone", cr.with_label("Ace clutch", "Hades"), "Ace clutch")
    check("name: already labelled is left alone", cr.with_label("Hades_Replay_2026-10-18", "Hades"), "Hades_Replay_2026-10-18")
    check("name: no label is no change", cr.with_label("Replay_2026-10-18", ""), "Replay_2026-10-18")

    nd = tmp / "named"
    nd.mkdir()
    (nd / "Replay_2026-10-18_21-41-05.mp4").write_text("x")
    check("renamed: the file moves", [Path(cr.renamed(str(nd / "Replay_2026-10-18_21-41-05.mp4"), "Hades")).name,
                                      (nd / "Replay_2026-10-18_21-41-05.mp4").exists()],
          ["Hades_Replay_2026-10-18_21-41-05.mp4", False])
    (nd / "Replay_2026-10-18_21-41-05.mp4").write_text("y")
    check("renamed: never over another file", Path(cr.renamed(str(nd / "Replay_2026-10-18_21-41-05.mp4"), "Hades")).name,
          "Hades_Replay_2026-10-18_21-41-05-2.mp4")
    check("renamed: a file that isn't there is left", cr.renamed(str(nd / "nope.mp4"), "Hades"), str(nd / "nope.mp4"))

    # The hook, with a pretend window.
    nrun = tmp / "nrun"
    cr.active_window = lambda: ("steam_app_1245620", "Elden Ring")
    (nd / "Replay_A.mp4").write_text("x")
    cr.cmd_saved(nrun, str(nd / "Replay_A.mp4"), "replay")
    last = json.loads((nrun / "events.jsonl").read_text().splitlines()[-1])
    check("hook: a replay is renamed and the event carries the new path",
          [Path(last["path"]).name, (nd / "Elden-Ring_Replay_A.mp4").exists()], ["Elden-Ring_Replay_A.mp4", True])
    check("hook: screenshots are never renamed", (lambda: (cr.cmd_saved(nrun, str(nd / "Shot.png"), "screenshot"),
          json.loads((nrun / "events.jsonl").read_text().splitlines()[-1])["path"])[1])(), str(nd / "Shot.png"))
    check("set: refused", [run("set", str(nrun), "naming", "weird").returncode, run("set", str(nrun), "nope", "window").returncode], [2, 2])
    check("set: plain", [run("set", str(nrun), "naming", "plain").returncode, cr.read_state(nrun).get("naming")], [0, "plain"])
    (nd / "Replay_B.mp4").write_text("x")
    cr.cmd_saved(nrun, str(nd / "Replay_B.mp4"), "replay")
    check("hook: plain leaves the recorder's name", (nd / "Replay_B.mp4").exists(), True)
    run("set", str(nrun), "naming", "window")
    # A regular recording uses the label taken when it STARTED, not the window you ended on.
    cr.update_state(nrun, state="replay", label="Hades")
    (nd / "Video_C.mp4").write_text("x")
    cr.cmd_saved(nrun, str(nd / "Video_C.mp4"), "regular")
    check("hook: a recording takes the label from its start", (nd / "Hades_Video_C.mp4").exists(), True)

    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
