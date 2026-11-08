#!/usr/bin/env python3
"""
claude-sessions.py — every Claude Code session worth showing, for the sidebar's Claude module:
the ones running now, the recent ones you can resume, and the account's rate limit.

services/ClaudeSessions.qml runs this while the module is placed; JSON lines out,
commands in.

── Where it comes from ─────────────────────────────────────────────────────────
  1. Claude Code's own session registry, ~/.claude/sessions/<pid>.json — read with
     scripts/claude-presence.py's reader (imported, not copied): live interactive
     sessions only, a dead or reused pid skipped. busy / idle, name, cwd, start time.
     The AI title, model and context size come from the transcript's tail, re-read
     only when the transcript file changes.
  2. OPTIONAL hook state, $XDG_RUNTIME_DIR/quickshell-quicktest-claude/<session_id>.json
     (scripts/claude-hook.py, installed by scripts/install-claude-hooks.py): "waiting
     on your permission", what tool it's running, the last reply's first line.

  3. Recent sessions: the newest transcripts under ~/.claude/projects that no live process
     holds — any project, so `cd ~/.config/quicktest && claude` (how this shell is worked
     on) lists the same as one started anywhere else. The session's own recorded cwd is
     what a resume enters (`claude --resume` only finds a session from the directory it
     was started in). Programmatic runs (`claude -p`, the SDK) are left out.
  4. The rate limit: the 5-hour and weekly usage, from scripts/claude-statusline.py's
     saved block — Claude Code writes it nowhere else.

Polled once a second, like claude-presence.py (its header says why: a directory of
small files rewritten in place has no event worth the plumbing). A line goes out only
when something changed.

── Protocol ────────────────────────────────────────────────────────────────────
out  {"t":"sessions","sessions":[{pid, sid, title, project, cwd, status, since,
        startedAt, model, context, attention, message, activity, last, hooked}]}
     {"t":"recent","sessions":[{sid, title, project, cwd, since, model, context}]}
     {"t":"rate","at":ms,"five_hour":{pct,resetsAt}|null,"seven_day":…}   at 0 = never seen
     {"t":"hooks","installed":bool,"path":str}
     {"t":"located","pid":N,"address":"0x…"|""}   the terminal window it runs in
in   {"c":"locate","pid":N}     N must be a session this listed
     {"c":"hooks"}              re-check whether the hook is installed

    python3 scripts/test-claude-sessions.py   — fake HOME and runtime dir, no Claude
"""

import importlib.util
import json
import os
import re
import selectors
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
POLL = 1.0
HOOK_STALE_S = 3600        # a hook file for no live session, older than this, is removed
RECENT_MAX = 8             # resumable sessions listed
RECENT_SCAN = 40           # newest transcripts looked into to find them
HEAD_BYTES = 64 * 1024     # where a transcript's cwd and first prompt are
# A session id ends up as an argument to `claude --resume`: never a flag, never a path.
SID_OK = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,127}")

_spec = importlib.util.spec_from_file_location("claude_presence", os.path.join(HERE, "claude-presence.py"))
P = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(P)


def die_with_parent():
    try:
        import ctypes, signal
        ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM, 0, 0, 0)
    except Exception:
        pass


def emit(obj):
    try:
        sys.stdout.write(json.dumps(obj, separators=(",", ":"), ensure_ascii=False) + "\n")
        sys.stdout.flush()
    except BrokenPipeError:
        os._exit(0)


def hook_dir():
    return os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "quickshell-quicktest-claude")


def read_hooks(live_sids, now):
    out = {}
    d = hook_dir()
    try:
        names = os.listdir(d)
    except OSError:
        return out
    for name in names:
        if not name.endswith(".json"):
            continue
        path = os.path.join(d, name)
        sid = name[:-5]
        try:
            if sid not in live_sids and now - os.path.getmtime(path) > HOOK_STALE_S:
                os.unlink(path)
                continue
            with open(path) as f:
                st = json.load(f)
        except (OSError, ValueError):
            continue
        if isinstance(st, dict):
            out[sid] = st
    return out


class Transcripts:
    """read_transcript, cached on the transcript file's (mtime, size)."""

    def __init__(self):
        self.cache = {}

    def get(self, s):
        sid, cwd = s.get("sessionId"), s.get("cwd")
        if not sid or not cwd:
            return {"title": "", "model": "", "context": 0}
        path = os.path.join(P.project_dir_for(cwd), sid + ".jsonl")
        try:
            st = os.stat(path)
            key = (st.st_mtime_ns, st.st_size)
        except OSError:
            key = None
        hit = self.cache.get(sid)
        if hit and hit[0] == key:
            return hit[1]
        val = P.read_transcript(s)
        self.cache[sid] = (key, val)
        return val


def row(s, hook, tr):
    sid = s.get("sessionId") or ""
    cwd = s.get("cwd") or ""
    # Hook state from before this session started (a resumed id) says nothing now.
    hooked = bool(hook) and (hook.get("at") or 0) >= (s.get("startedAt") or 0)
    h = hook if hooked else {}
    status = s.get("status") or ""
    return {
        "pid": s.get("pid"),
        "sid": sid,
        "title": tr.get("title") or s.get("name") or os.path.basename(cwd) or "Claude Code",
        "project": os.path.basename(cwd.rstrip("/")) or cwd,
        "cwd": cwd,
        "status": status,
        "since": s.get("statusUpdatedAt") or s.get("updatedAt") or 0,
        "startedAt": s.get("startedAt") or 0,
        "model": P.pretty_model(tr.get("model") or ""),
        "context": tr.get("context") or 0,
        "attention": h.get("attention") or "",
        "message": h.get("message") or "",
        "activity": (h.get("activity") or "") if status == "busy" else "",
        "last": h.get("last") or "",
        "hooked": hooked,
    }


def rate_path():
    return os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "quickshell-quicktest-claude-rate.json")


def _window(w):
    if not isinstance(w, dict):
        return None
    pct, at = w.get("pct"), w.get("resetsAt")
    if isinstance(pct, bool) or isinstance(at, bool) or not isinstance(pct, (int, float)) \
            or not isinstance(at, (int, float)):
        return None
    return {"pct": max(0.0, min(100.0, float(pct))), "resetsAt": int(at)}


def read_rate():
    """claude-statusline.py's saved block, re-checked (it is a file, so anything could be in it)."""
    none = {"t": "rate", "at": 0, "five_hour": None, "seven_day": None}
    try:
        with open(rate_path()) as f:
            d = json.load(f)
    except (OSError, ValueError):
        return none
    if not isinstance(d, dict) or not isinstance(d.get("at"), (int, float)):
        return none
    return {"t": "rate", "at": int(d["at"]), "five_hour": _window(d.get("five_hour")),
            "seven_day": _window(d.get("seven_day"))}


def _prompt_text(rec):
    """What the user typed in a transcript record, or "" for anything the CLI wrote
    on their behalf (slash-command wrappers, caveats, tool results)."""
    if rec.get("type") != "user" or rec.get("isMeta") or rec.get("isSidechain"):
        return ""
    c = (rec.get("message") or {}).get("content")
    if isinstance(c, list):
        c = " ".join(b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text")
    if not isinstance(c, str):
        return ""
    c = " ".join(c.split())
    return "" if c.startswith(("<", "Caveat:")) else c


class Recents:
    """Sessions that have ended, newest first, each read once per change to its file."""

    def __init__(self):
        self.cache = {}

    def _head(self, path):
        """(cwd, entrypoint, first prompt) from the start of the transcript."""
        cwd = ent = prompt = ""
        try:
            with open(path, "rb") as fh:
                chunk = fh.read(HEAD_BYTES)
        except OSError:
            return cwd, ent, prompt
        for raw in chunk.split(b"\n"):
            if not raw.startswith(b"{"):
                continue
            try:
                rec = json.loads(raw)
            except ValueError:
                continue
            cwd = cwd or (rec.get("cwd") if isinstance(rec.get("cwd"), str) else "")
            ent = ent or (rec.get("entrypoint") if isinstance(rec.get("entrypoint"), str) else "")
            prompt = prompt or _prompt_text(rec)
            if cwd and ent and prompt:
                break
        return cwd, ent, prompt[:120]

    def _info(self, sid, path, mtime):
        cwd, ent, prompt = self._head(path)
        # Not ours to list: a programmatic run, one with nothing said in it, or a
        # directory that is gone (a resume would start in the wrong place).
        if (ent and ent != "cli") or not os.path.isabs(cwd) or not os.path.isdir(cwd):
            return None
        tr = P.read_transcript({"sessionId": sid, "cwd": cwd, "_path": path})
        title = tr.get("title") or prompt
        if not title:
            return None
        return {"sid": sid, "title": title, "project": os.path.basename(cwd.rstrip("/")) or cwd,
                "cwd": cwd, "since": int(mtime * 1000), "model": P.pretty_model(tr.get("model") or ""),
                "context": tr.get("context") or 0}

    def get(self, live_sids):
        files = []
        try:
            for d in os.scandir(P.PROJECTS_DIR):
                if not d.is_dir():
                    continue
                for f in os.scandir(d.path):
                    if f.name.endswith(".jsonl") and f.is_file():
                        try:
                            st = f.stat()
                        except OSError:
                            continue
                        files.append((st.st_mtime, st.st_size, f.path))
        except OSError:
            return []
        files.sort(reverse=True)
        out = []
        for mtime, size, path in files[:RECENT_SCAN]:
            sid = os.path.basename(path)[:-6]
            if sid in live_sids or not SID_OK.fullmatch(sid):
                continue
            hit = self.cache.get(sid)
            if hit and hit[0] == (mtime, size):
                info = hit[1]
            else:
                info = self._info(sid, path, mtime)
                self.cache[sid] = ((mtime, size), info)
            if info:
                out.append(info)
                if len(out) >= RECENT_MAX:
                    break
        return out


def ancestors(pid, depth=24):
    out = []
    while pid and pid > 1 and len(out) < depth:
        out.append(pid)
        pid = P.parent_pid(pid)
    return out


def locate(pid):
    """The Hyprland window whose process is this session or one of its parents (the
    terminal it runs in). "" when none is — tmux, ssh, a terminal server."""
    chain = set(ancestors(pid))
    try:
        r = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=3)
        clients = json.loads(r.stdout or "[]")
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return ""
    for c in clients if isinstance(clients, list) else []:
        if isinstance(c, dict) and c.get("pid") in chain:
            return str(c.get("address") or "")
    return ""


def check_hooks():
    try:
        r = subprocess.run([sys.executable, os.path.join(HERE, "install-claude-hooks.py"), "--check"],
                           capture_output=True, text=True, timeout=10)
        d = json.loads(r.stdout or "{}")
        return {"t": "hooks", "installed": bool(d.get("installed")), "path": str(d.get("path") or "")}
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return {"t": "hooks", "installed": False, "path": ""}


def main():
    die_with_parent()
    tr = Transcripts()
    recents = Recents()
    last = last_recent = last_rate = None
    live_pids = set()
    emit(check_hooks())

    sel = selectors.DefaultSelector()
    sel.register(sys.stdin, selectors.EVENT_READ)
    buf = ""
    while True:
        now = time.time()
        sessions = P.read_sessions()
        live_pids = {s.get("pid") for s in sessions}
        hooks = read_hooks({s.get("sessionId") for s in sessions}, now)
        rows = [row(s, hooks.get(s.get("sessionId")), tr.get(s)) for s in sessions]
        rows.sort(key=lambda r: (r["attention"] == "", r["status"] != "busy", -(r["since"] or 0)))
        line = json.dumps(rows, sort_keys=True)
        if line != last:
            last = line
            emit({"t": "sessions", "sessions": rows})

        recent = recents.get({s.get("sessionId") for s in sessions})
        line = json.dumps(recent, sort_keys=True)
        if line != last_recent:
            last_recent = line
            emit({"t": "recent", "sessions": recent})

        rate = read_rate()
        line = json.dumps(rate, sort_keys=True)
        if line != last_rate:
            last_rate = line
            emit(rate)

        for _key, _ev in sel.select(timeout=POLL):
            chunk = os.read(sys.stdin.fileno(), 65536)
            if not chunk:
                return 0
            buf += chunk.decode("utf-8", "replace")
            while "\n" in buf:
                raw, buf = buf.split("\n", 1)
                try:
                    cmd = json.loads(raw)
                except ValueError:
                    continue
                if not isinstance(cmd, dict):
                    continue
                if cmd.get("c") == "locate":
                    pid = cmd.get("pid")
                    if isinstance(pid, int) and not isinstance(pid, bool) and pid in live_pids:
                        emit({"t": "located", "pid": pid, "address": locate(pid)})
                elif cmd.get("c") == "hooks":
                    emit(check_hooks())


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
