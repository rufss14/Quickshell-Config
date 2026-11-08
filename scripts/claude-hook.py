#!/usr/bin/env python3
"""
claude-hook.py — a Claude Code hook that tells the shell what a session is doing.

Installed (optionally) into Claude Code's settings by scripts/install-claude-hooks.py,
as an ASYNC command hook on: SessionStart, UserPromptSubmit, PreToolUse, PostToolUse,
PermissionRequest, Notification, Stop, SessionEnd. Claude Code passes the event as JSON
on stdin; this writes one small state file per session that scripts/claude-sessions.py
merges into what the sidebar's Claude module shows:

    $XDG_RUNTIME_DIR/quickshell-quicktest-claude/<session_id>.json   (dir 0700, file 0600)
    {"sid", "event", "at": ms, "attention": "permission"|"input"|"", "message",
     "activity": "Edit · Foo.qml"|"", "last": "…"}

Without these hooks the module still works off Claude Code's own session registry
(~/.claude/sessions): busy or idle. The hooks add the one thing the registry can't —
"it's waiting on YOUR permission" — and what it's doing right now.

── What is and isn't written ───────────────────────────────────────────────────
  · a tool's NAME, and for file tools the file's BASENAME — never a command line or
    any tool input (a Bash command can carry a secret);
  · Claude Code's own notification text ("Claude needs your permission to use Bash");
  · the first 200 characters of the last reply (Stop), for the "done" line;
  · never a prompt you typed.
All on tmpfs, private to you, removed at SessionEnd.

── Never in Claude's way ───────────────────────────────────────────────────────
It's async (Claude doesn't wait for it), prints nothing, and exits 0 whatever happens
— a hook that fails or talks would show up in someone's session.
"""

import json
import os
import re
import sys
import time

SID = re.compile(r"[A-Za-z0-9_\-]{1,128}")
FILE_TOOLS = ("Edit", "Write", "Read", "MultiEdit", "NotebookEdit")
TEXT_MAX = 200


def state_dir():
    base = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    return os.path.join(base, "quickshell-quicktest-claude")


def clip(s, n=TEXT_MAX):
    s = " ".join(str(s or "").split())
    return s if len(s) <= n else s[: n - 1] + "…"


def activity_for(tool, tool_input):
    """'Edit · Foo.qml', 'Bash', 'Grep'… — the tool, and a file's basename only."""
    tool = clip(tool, 40)
    if not tool:
        return ""
    if tool in FILE_TOOLS and isinstance(tool_input, dict):
        path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
        if isinstance(path, str) and path:
            return tool + " · " + clip(os.path.basename(path), 60)
    return tool


def update(prev, ev, now_ms):
    """The new state for an event, from the previous one. Pure (tested)."""
    name = ev.get("hook_event_name") or ""
    st = dict(prev or {})
    st.update({"sid": ev.get("session_id"), "event": name, "at": now_ms})
    st.setdefault("attention", "")
    st.setdefault("message", "")
    st.setdefault("activity", "")
    st.setdefault("last", "")
    if name == "PermissionRequest":
        st["attention"] = "permission"
        st["message"] = "Wants to use " + clip(ev.get("tool_name"), 40)
    elif name == "Notification":
        kind = ev.get("type") or ev.get("notification_type") or ""
        if kind == "permission_prompt":
            st["attention"] = "permission"
        elif kind in ("idle_prompt", "agent_needs_input", "elicitation_dialog", "elicitation_url_dialog"):
            st["attention"] = "input"
        st["message"] = clip(ev.get("message"))
    elif name == "PreToolUse":
        st["attention"] = ""
        st["activity"] = activity_for(ev.get("tool_name"), ev.get("tool_input"))
    elif name in ("PostToolUse", "UserPromptSubmit", "SessionStart"):
        st["attention"] = ""
        st["message"] = ""
        if name != "PostToolUse":
            st["activity"] = ""
    elif name == "Stop":
        st["attention"] = ""
        st["activity"] = ""
        st["message"] = ""
        st["last"] = clip(ev.get("last_assistant_message"))
    return st


def main():
    try:
        ev = json.load(sys.stdin)
    except Exception:
        return 0
    if not isinstance(ev, dict):
        return 0
    sid = ev.get("session_id")
    if not isinstance(sid, str) or not SID.fullmatch(sid):
        return 0
    d = state_dir()
    path = os.path.join(d, sid + ".json")
    try:
        os.makedirs(d, mode=0o700, exist_ok=True)
        if ev.get("hook_event_name") == "SessionEnd":
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
            return 0
        try:
            with open(path) as f:
                prev = json.load(f)
        except (OSError, ValueError):
            prev = {}
        st = update(prev, ev, int(time.time() * 1000))
        tmp = path + ".%d.tmp" % os.getpid()
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            json.dump(st, f)
        os.replace(tmp, path)
    except OSError:
        pass
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
