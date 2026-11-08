#!/usr/bin/env python3
"""
claude-statusline.py — Claude Code's status-line command, used to learn the rate limit.

Claude Code runs the configured status-line command after each turn and passes the
session as JSON on stdin. Among the fields is `rate_limits` — the account's 5-hour and
7-day usage windows, each a `used_percentage` and a `resets_at` — which nothing else on
disk carries (a transcript records a quota only when a request is REJECTED). This saves
exactly that block, for the sidebar's Claude panel:

    $XDG_RUNTIME_DIR/quickshell-quicktest-claude-rate.json   (0600)
    {"at": ms, "five_hour": {"pct": 0..100, "resetsAt": epoch s} | null, "seven_day": …}

Nothing else from the payload is kept — not the prompt, the path, the cost or the model.

── Installed by scripts/install-claude-hooks.py, never by hand ─────────────────
It prints nothing, so the status line is empty. If you already have a status line, the
installer wraps it:  claude-statusline.py -- <your command>  — this runs it with the same
stdin and prints what IT prints, so yours looks and works exactly as before.

── Never in Claude's way ───────────────────────────────────────────────────────
Whatever goes wrong here, it exits 0: a broken status line is drawn in someone's terminal.
`rate_limits` is absent until a session's first reply, and for API-key accounts; then
nothing is written and the last known figures stay.

    python3 scripts/test-claude-sessions.py
"""

import datetime
import json
import os
import subprocess
import sys
import time


def rate_path():
    return os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "quickshell-quicktest-claude-rate.json")


def epoch(v):
    """A reset time as epoch SECONDS, from whatever the payload spells it as: seconds,
    milliseconds, or an ISO-8601 string. None when it is none of those."""
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return int(v / 1000) if v > 1e11 else int(v)
    if isinstance(v, str) and v:
        try:
            return int(datetime.datetime.fromisoformat(v.replace("Z", "+00:00")).timestamp())
        except ValueError:
            return None
    return None


def window(w):
    if not isinstance(w, dict):
        return None
    pct, at = w.get("used_percentage"), epoch(w.get("resets_at"))
    if isinstance(pct, bool) or not isinstance(pct, (int, float)) or at is None:
        return None
    return {"pct": round(max(0.0, min(100.0, float(pct))), 1), "resetsAt": at}


def parse(payload, now_ms):
    """The record to save, or None when the payload carries no usable rate limit."""
    rl = payload.get("rate_limits") if isinstance(payload, dict) else None
    if not isinstance(rl, dict):
        return None
    five, week = window(rl.get("five_hour")), window(rl.get("seven_day"))
    if five is None and week is None:
        return None
    return {"at": now_ms, "five_hour": five, "seven_day": week}


def save(rec, path):
    tmp = path + ".tmp%d" % os.getpid()
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(rec, f, separators=(",", ":"))
    os.replace(tmp, path)


def main(argv):
    raw = sys.stdin.read()
    try:
        rec = parse(json.loads(raw), int(time.time() * 1000))
        if rec:
            save(rec, rate_path())
    except Exception:
        pass
    # `-- <command>`: the user's own status line, fed the same input.
    if "--" in argv:
        cmd = " ".join(argv[argv.index("--") + 1:]).strip()
        if cmd:
            try:
                r = subprocess.run(cmd, shell=True, input=raw, capture_output=True, text=True, timeout=30)
                sys.stdout.write(r.stdout)
                sys.stderr.write(r.stderr)
            except Exception:
                pass
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception:
        sys.exit(0)
