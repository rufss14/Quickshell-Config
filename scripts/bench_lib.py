#!/usr/bin/env python3
"""bench_lib — the shared half of the performance tools (docs/performance.md).

    bench-ab.py            A/B: variants of config or code, alternating rounds, medians
    qt-render-timing.py    per-window scene-graph timing (QSG_RENDER_TIMING)
    shell-cost.py          what the RUNNING shell costs, by thread (also `framewatch cost`)

What lives here: starting a THROWAWAY shell that cannot touch the real one, and taking /proc
snapshots of a shell. A throwaway gets its own XDG_STATE_HOME holding a copy of the live
config.json, so nothing it saves (preferences, scores, history) reaches the real state. It does
share the session: its windows appear over the desktop, and it runs its own helpers for as long as
it lives. Nothing here is imported by the shell.

Numbers are percent of ONE core (like top), except `gpu` (percent of the gfx engine's time).
`gpu` comes from /proc/PID/fdinfo `drm-engine-gfx` (amdgpu and intel expose it), so it is the
SHELL's GPU time, not the whole card's; `card` is the card's gpu_busy_percent where sysfs has it.
"""
import glob
import io
import json
import os
import re
import signal
import subprocess
import tarfile
import tempfile
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HZ = os.sysconf("SC_CLK_TCK")
ANSI = re.compile(r"\x1b\[[0-9;]*m")


def state_home():
    return os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")


def live_config(path=None):
    """The newest live preferences document as a dict ({} if there is none). Read, never written."""
    if path is None:
        found = glob.glob(os.path.join(state_home(), "quickshell", "by-shell", "*", "config.json"))
        path = max(found, key=os.path.getmtime) if found else None
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, TypeError, ValueError):
        return {}


# ── a tree to run ─────────────────────────────────────────────────────────────
def export_ref(ref, dest):
    """`git archive REF` into dest: the COMMITTED code at that ref (not the working tree)."""
    os.makedirs(dest, exist_ok=True)
    arc = subprocess.run(["git", "-C", REPO, "archive", ref], capture_output=True, check=True).stdout
    with tarfile.open(fileobj=io.BytesIO(arc)) as t:
        t.extractall(dest, filter="data")
    return dest


# ── a throwaway shell ─────────────────────────────────────────────────────────
def _pids_named(comm):
    out = set()
    for d in os.listdir("/proc"):
        if d.isdigit():
            try:
                if open(f"/proc/{d}/comm").read().strip() == comm:
                    out.add(int(d))
            except OSError:
                pass
    return out


class Throwaway:
    """One shell started from `tree` with its own state dir. `with Throwaway(...) as t: t.pid`."""

    def __init__(self, tree=REPO, state=None, env=None, log=None, config=None):
        self.tree = tree
        self.state = state or tempfile.mkdtemp(prefix="qs-bench-")
        self.env = env or {}
        self.log = log or os.path.join(self.state, "shell.log")
        self.config = config
        self.proc = None
        self._wpe_before = set()

    def _start(self):
        env = dict(os.environ, XDG_STATE_HOME=self.state, **self.env)
        cmd = f'source "{self.tree}/scripts/shell-env.sh"; exec quickshell -p "{self.tree}"'
        self._log = open(self.log, "w")
        self.proc = subprocess.Popen(["bash", "-c", cmd], stdout=self._log, stderr=subprocess.STDOUT,
                                     env=env, start_new_session=True)

    def _shell_id(self):
        m = re.search(r'Shell ID: "([0-9a-f]+)"', ANSI.sub("", open(self.log).read()))
        return m.group(1) if m else None

    def __enter__(self):
        self._wpe_before = _pids_named("linux-wallpape")
        if self.config is not None:
            # The state dir is named after the shell's id, which only the shell knows: let a first
            # start say it, then put the config where the second start will read it.
            self._start()
            for _ in range(60):
                time.sleep(0.25)
                if self._shell_id():
                    break
            sid = self._shell_id()
            self._kill()
            if not sid:
                raise RuntimeError("throwaway printed no Shell ID — see " + self.log)
            d = os.path.join(self.state, "quickshell", "by-shell", sid)
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, "config.json"), "w") as f:
                json.dump(self.config, f)
        self._start()
        self.pid = self.proc.pid
        return self

    def _kill(self):
        if self.proc is None:
            return
        try:
            os.killpg(self.proc.pid, signal.SIGTERM)
            self.proc.wait(8)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                os.killpg(self.proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        self.proc = None

    def __exit__(self, *a):
        self._kill()
        # The wallpaper renderer is started detached (its own session) so a reload doesn't reload
        # the scene; a throwaway's copy is therefore not in its process group. Kill what is new.
        for pid in _pids_named("linux-wallpape") - self._wpe_before:
            try:
                os.kill(pid, signal.SIGTERM)
            except OSError:
                pass
        time.sleep(1.5)


# ── snapshots ─────────────────────────────────────────────────────────────────
def _stat(path):
    with open(path) as f:
        head, tail = f.read().rsplit(")", 1)
    x = tail.split()
    return head.split("(", 1)[1], int(x[11]) + int(x[12]), int(x[1])      # comm, utime+stime, ppid


def _descendants(root):
    kids = {}
    for d in os.listdir("/proc"):
        if d.isdigit():
            try:
                kids.setdefault(_stat(f"/proc/{d}/stat")[2], []).append(int(d))
            except (OSError, ValueError, IndexError):
                pass
    out, stack = [], list(kids.get(root, []))
    while stack:
        p = stack.pop()
        out.append(p)
        stack.extend(kids.get(p, []))
    return out


def _gpu_ns(pid):
    """Summed drm-engine-gfx nanoseconds over the process's DISTINCT drm clients (an fd per client
    is shared by dup'd descriptors). None when the driver exposes no engine time."""
    seen, total, any_ = set(), 0, False
    for fd in glob.glob(f"/proc/{pid}/fdinfo/*"):
        try:
            txt = open(fd).read()
        except OSError:
            continue
        if "drm-driver" not in txt:
            continue
        cid = re.search(r"drm-client-id:\s*(\d+)", txt)
        eng = re.search(r"drm-engine-gfx:\s*(\d+)", txt)
        if not cid or cid.group(1) in seen:
            continue
        seen.add(cid.group(1))
        if eng:
            total += int(eng.group(1))
            any_ = True
    return total if any_ else None


def snapshot(pid):
    threads = {}
    for t in os.listdir(f"/proc/{pid}/task"):
        try:
            c, ticks, _ = _stat(f"/proc/{pid}/task/{t}/stat")
            threads[int(t)] = (c, ticks)
        except (OSError, ValueError, IndexError):
            pass
    helpers = {}
    for p in _descendants(pid):
        try:
            c, ticks, _ = _stat(f"/proc/{p}/stat")
            helpers[p] = (c, ticks)
        except (OSError, ValueError, IndexError):
            pass
    rss = 0
    try:
        rss = int(re.search(r"VmRSS:\s+(\d+)", open(f"/proc/{pid}/status").read()).group(1)) // 1024
    except (OSError, AttributeError):
        pass
    return {"t": time.time(), "pid": pid, "threads": threads, "helpers": helpers,
            "gpu_ns": _gpu_ns(pid), "rss_mb": rss}


def card_busy():
    """The first card's gpu_busy_percent, or None."""
    for f in glob.glob("/sys/class/drm/card*/device/gpu_busy_percent"):
        try:
            return int(open(f).read())
        except (OSError, ValueError):
            pass
    return None


def diff(a, b):
    """Percent-of-one-core between two snapshots of the same pid."""
    dt = b["t"] - a["t"]
    pct = lambda ticks: ticks / HZ / dt * 100
    gui = render = other = 0.0
    named = {}
    for tid, (name, ticks) in b["threads"].items():
        d = pct(ticks - a["threads"].get(tid, (name, ticks))[1])
        if tid == a["pid"]:
            gui += d
        elif name.startswith("QSGRender"):
            render += d
        else:
            other += d
        named[name] = named.get(name, 0) + d
    helpers = {}
    for p, (name, ticks) in b["helpers"].items():
        if p in a["helpers"]:
            helpers[name] = helpers.get(name, 0) + pct(ticks - a["helpers"][p][1])
    gpu = None
    if a["gpu_ns"] is not None and b["gpu_ns"] is not None:
        gpu = (b["gpu_ns"] - a["gpu_ns"]) / (dt * 1e9) * 100
    return {"gui": gui, "render": render, "other": other, "process": gui + render + other,
            "helpers": sum(helpers.values()), "gpu": gpu, "rss_mb": b["rss_mb"],
            "threads": named, "helper_names": helpers, "seconds": dt}
