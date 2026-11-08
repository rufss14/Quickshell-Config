#!/usr/bin/env python3
"""Tests for scripts/record-run.sh, the detached screen-recording runner.

    python3 scripts/test-record-run.py

Fully mocked and safe to run: the "backend" is a stub shell script written into a
temp directory. Nothing here records a screen, spawns a real encoder, touches the
user's recordings directory, or signals anything outside its own sandbox.

── What is actually worth testing here ──────────────────────────────────────────
The runner is thirty lines of process handling, and exactly two properties of it
are load-bearing and invisible from the outside:

  SIGINT, NOT SIGTERM   wf-recorder finalises the container on INT and dies where
                        it stands on TERM, leaving an unplayable file. The stub
                        records WHICH signal it got, so a future "simplification"
                        of `stop` into a plain kill fails here instead of in a
                        video that will not open.

  ONE AT A TIME         two backends writing one output file is a corrupt capture.
                        The flock has to refuse the second start.

Everything else (state transitions, the error path, the zero-byte guard) is here
because the QML side binds to those exact strings.
"""

import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

RUNNER = Path(__file__).resolve().parent / "record-run.sh"

passed = failed = 0


def check(name, cond, detail=""):
    global passed, failed
    if cond:
        passed += 1
    else:
        failed += 1
        print(f"  FAIL: {name}" + (f"\n        {detail}" if detail else ""))


def read_state(statedir, tries=100):
    """The runner writes the state file by rename, so a read either sees the whole
    old document or the whole new one — but it may not have been written yet."""
    p = Path(statedir) / "state.json"
    for _ in range(tries):
        if p.exists():
            try:
                return json.loads(p.read_text())
            except json.JSONDecodeError:
                pass
        time.sleep(0.05)
    return None


def wait_for(fn, tries=200):
    for _ in range(tries):
        if fn():
            return True
        time.sleep(0.05)
    return False


def make_stub(d, *, trap=True, exit_code=0, write_output=True, spin=True):
    """A stand-in for wf-recorder.

    Records the signal it received into <d>/signal so the test can assert that
    `stop` sent INT and not TERM — the single most important behaviour here.
    """
    path = Path(d) / "stub-recorder"
    out_marker = 'printf "video" > "$OUT"' if write_output else "true"
    body = f"""#!/usr/bin/env bash
set -u
OUT=""
# Mimic the real backends: the output path is the -f argument.
while [ $# -gt 0 ]; do
    case "$1" in
        -f) OUT="$2"; shift 2 ;;
        *)  shift ;;
    esac
done
echo "stub started with OUT=$OUT" >&2
"""
    if trap:
        body += f"""
finish() {{ echo INT > "{d}/signal"; {out_marker}; exit {exit_code}; }}
term()   {{ echo TERM > "{d}/signal"; exit 143; }}
trap finish INT
trap term TERM
"""
    else:
        # Deliberately ignores INT, to exercise the escalation path.
        body += """
trap '' INT
"""
    body += 'printf "ready" > "%s/ready"\n' % d
    body += "while true; do sleep 0.05; done\n" if spin else "exit %d\n" % exit_code
    path.write_text(body)
    path.chmod(0o755)
    return path


def start(statedir, out, backend, extra=None, wait=False):
    """Launch `start`. Detached (as QML does) unless the test wants the exit code."""
    cmd = ["bash", str(RUNNER), "start", statedir, out, str(backend), "-f", out]
    cmd += extra or []
    if wait:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    return subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def stop(statedir):
    return subprocess.run(["bash", str(RUNNER), "stop", statedir],
                          capture_output=True, text=True, timeout=30)


# ── stop sends SIGINT, and the capture finalises ─────────────────────────────
def test_stop_uses_sigint():
    print("stop sends SIGINT, not SIGTERM")
    with tempfile.TemporaryDirectory() as d:
        stub = make_stub(d)
        out = os.path.join(d, "out.mp4")
        proc = start(d, out, stub)

        check("backend actually started", wait_for(lambda: os.path.exists(f"{d}/ready")))

        st = read_state(d)
        check("state is 'recording'", st and st.get("state") == "recording", f"got {st}")
        check("state carries the output path", st and st.get("file") == out, f"got {st}")
        check("state carries a pid", st and isinstance(st.get("pid"), int), f"got {st}")
        check("state carries startedAt", st and isinstance(st.get("startedAt"), int), f"got {st}")

        stop(d)
        proc.wait(timeout=30)

        sig = Path(f"{d}/signal").read_text().strip() if os.path.exists(f"{d}/signal") else "(none)"
        check("the backend received INT", sig == "INT", f"received {sig}")

        st = read_state(d)
        check("final state is 'done'", st and st.get("state") == "done", f"got {st}")
        check("the output file survived", os.path.getsize(out) > 0)


# ── A second start while one is live must refuse ─────────────────────────────
def test_refuses_concurrent_start():
    print("a second start is refused while one is recording")
    with tempfile.TemporaryDirectory() as d:
        stub = make_stub(d)
        out = os.path.join(d, "out.mp4")
        proc = start(d, out, stub)
        check("first start is running", wait_for(lambda: os.path.exists(f"{d}/ready")))

        second = start(d, os.path.join(d, "other.mp4"), stub, wait=True)
        check("second start exits 3", second.returncode == 3, f"got {second.returncode}")
        check("second start explains itself",
              "already running" in second.stderr, f"stderr={second.stderr!r}")

        st = read_state(d)
        check("the live recording is untouched",
              st and st.get("state") == "recording", f"got {st}")

        stop(d)
        proc.wait(timeout=30)


# ── A backend that isn't installed reports, it doesn't hang ──────────────────
def test_missing_backend():
    print("a missing backend becomes an error state")
    with tempfile.TemporaryDirectory() as d:
        r = start(d, os.path.join(d, "out.mp4"), "definitely-not-a-real-recorder", wait=True)
        check("exits non-zero", r.returncode == 4, f"got {r.returncode}")
        st = read_state(d)
        check("state is 'error'", st and st.get("state") == "error", f"got {st}")
        check("the message names the tool",
              st and "definitely-not-a-real-recorder" in st.get("message", ""), f"got {st}")


# ── A backend that fails leaves an error carrying its own words ──────────────
def test_backend_failure_is_reported():
    print("a failing backend reports its own stderr")
    with tempfile.TemporaryDirectory() as d:
        stub = make_stub(d, spin=False, exit_code=1, write_output=False)
        r = start(d, os.path.join(d, "out.mp4"), stub, wait=True)
        check("exits non-zero", r.returncode != 0, f"got {r.returncode}")
        st = read_state(d)
        check("state is 'error'", st and st.get("state") == "error", f"got {st}")
        check("the message quotes the backend",
              st and "stub started" in st.get("message", ""), f"got {st}")


# ── A zero-byte capture is a failure even on a clean exit ────────────────────
def test_empty_output_is_a_failure():
    print("a zero-byte capture is not reported as success")
    with tempfile.TemporaryDirectory() as d:
        stub = make_stub(d, spin=False, exit_code=0, write_output=False)
        r = start(d, os.path.join(d, "out.mp4"), stub, wait=True)
        st = read_state(d)
        check("state is 'error', not 'done'", st and st.get("state") == "error", f"got {st}")


# ── stop with nothing running is a no-op, not a crash ────────────────────────
def test_stop_when_idle():
    print("stop with nothing running settles on idle")
    with tempfile.TemporaryDirectory() as d:
        r = stop(d)
        check("exits 0", r.returncode == 0, f"got {r.returncode} stderr={r.stderr!r}")
        st = read_state(d)
        check("state is 'idle'", st and st.get("state") == "idle", f"got {st}")


# ── A backend that ignores INT is escalated, and it is reported ──────────────
def test_escalation_when_int_ignored():
    print("a backend that ignores INT is escalated to TERM")
    with tempfile.TemporaryDirectory() as d:
        stub = make_stub(d, trap=False)
        out = os.path.join(d, "out.mp4")
        proc = start(d, out, stub)
        check("backend started", wait_for(lambda: os.path.exists(f"{d}/ready")))

        t0 = time.time()
        r = stop(d)
        elapsed = time.time() - t0

        check("waited out the grace period before escalating",
              elapsed >= 9.5, f"escalated after {elapsed:.1f}s")
        check("says it escalated", "escalating" in r.stderr, f"stderr={r.stderr!r}")
        proc.wait(timeout=30)


def main():
    if not RUNNER.exists():
        print(f"missing {RUNNER}")
        return 1
    for t in (test_stop_uses_sigint,
              test_refuses_concurrent_start,
              test_missing_backend,
              test_backend_failure_is_reported,
              test_empty_output_is_a_failure,
              test_stop_when_idle,
              test_escalation_when_int_ignored):
        t()
    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
