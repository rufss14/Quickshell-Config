#!/usr/bin/env python3
"""
install-claude-hooks.py — add (or remove) the shell's Claude Code hook and status line.

    python3 scripts/install-claude-hooks.py            install
    python3 scripts/install-claude-hooks.py --remove   take it out again
    python3 scripts/install-claude-hooks.py --check    {"installed": bool, "path": …}

Merges scripts/claude-hook.py into Claude Code's USER settings
($CLAUDE_CONFIG_DIR/settings.json, else ~/.claude/settings.json) as an async command
hook on the events it reads, so the sidebar's Claude module can say "waiting on your
permission" and what a session is doing (see claude-hook.py for exactly what it
records).

It also sets the status line to scripts/claude-statusline.py, which keeps only the
`rate_limits` block (the 5-hour / weekly usage and when each resets) for the panel's
usage bars. A status line you already have is WRAPPED, not replaced — it runs as before
and --remove puts your command back exactly as it was.

Optional: the module works without either, from Claude Code's session registry.

── Careful with someone else's file ────────────────────────────────────────────
  · everything already in settings.json is kept — other hooks on the same events too;
  · ours are found by the script's path, so installing twice changes nothing and
    --remove takes out only ours;
  · the old file is copied to settings.json.bak-quicktest first, and the new one
    written to a temp file and renamed over it;
  · a settings.json that isn't valid JSON is left alone, with an error.
Claude Code reads hook changes for new sessions; a running one may need /hooks or a
restart to pick them up.
"""

import json
import os
import shlex
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
HOOK = os.path.join(HERE, "claude-hook.py")
MARK = "claude-hook.py"
STATUS = os.path.join(HERE, "claude-statusline.py")
STATUS_MARK = "claude-statusline.py"
WRAP = " -- "              # ours, then WRAP, then the status line that was there before
# Tool events take a matcher ("*" = every tool); the rest don't use one.
EVENTS = {
    "SessionStart": None, "UserPromptSubmit": None, "PreToolUse": "*", "PostToolUse": "*",
    "PermissionRequest": "*", "Notification": None, "Stop": None, "SessionEnd": None,
}


def settings_path():
    base = os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")
    return os.path.join(base, "settings.json")


def command():
    return "python3 " + shlex.quote(HOOK)


def ours(hook):
    return isinstance(hook, dict) and MARK in str(hook.get("command", ""))


def strip(settings):
    """settings without our hook entries (empty groups and events dropped)."""
    hooks = settings.get("hooks")
    if not isinstance(hooks, dict):
        return settings
    for event in list(hooks):
        groups = hooks[event]
        if not isinstance(groups, list):
            continue
        kept = []
        for g in groups:
            if isinstance(g, dict) and isinstance(g.get("hooks"), list):
                g = dict(g, hooks=[h for h in g["hooks"] if not ours(h)])
                if not g["hooks"]:
                    continue
            kept.append(g)
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]
    if not hooks:
        settings.pop("hooks", None)
    return settings


def add(settings):
    """settings with our hook on every event (after stripping any older copy)."""
    settings = strip(settings)
    hooks = settings.setdefault("hooks", {})
    for event, matcher in EVENTS.items():
        group = {"hooks": [{"type": "command", "command": command(), "async": True, "timeout": 10}]}
        if matcher is not None:
            group = dict({"matcher": matcher}, **group)
        hooks.setdefault(event, []).append(group)
    return add_status(settings)


def status_command(previous=""):
    return "python3 " + shlex.quote(STATUS) + (WRAP + previous if previous else "")


def status_ours(settings):
    sl = settings.get("statusLine")
    return isinstance(sl, dict) and STATUS_MARK in str(sl.get("command", ""))


def strip_status(settings):
    """settings without our status line — the one that was there before put back."""
    if not status_ours(settings):
        return settings
    cmd = str(settings["statusLine"].get("command", ""))
    previous = cmd.split(WRAP, 1)[1].strip() if WRAP in cmd else ""
    if previous:
        settings["statusLine"] = dict(settings["statusLine"], command=previous)
    else:
        del settings["statusLine"]
    return settings


def add_status(settings):
    settings = strip_status(settings)
    sl = settings.get("statusLine")
    previous = str(sl.get("command", "")).strip() if isinstance(sl, dict) and sl.get("type") == "command" else ""
    settings["statusLine"] = dict(sl if isinstance(sl, dict) and previous else {},
                                  type="command", command=status_command(previous))
    return settings


def installed(settings):
    hooks = settings.get("hooks") if isinstance(settings, dict) else None
    if not isinstance(hooks, dict):
        return False
    have = {e for e, groups in hooks.items() if isinstance(groups, list)
            and any(isinstance(g, dict) and any(ours(h) for h in g.get("hooks") or []) for g in groups)}
    return set(EVENTS) <= have and status_ours(settings)


def load(path):
    try:
        with open(path) as f:
            data = json.load(f)
    except FileNotFoundError:
        return {}
    if not isinstance(data, dict):
        raise ValueError("settings.json isn't a JSON object")
    return data


def save(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path):
        shutil.copy2(path, path + ".bak-quicktest")
    tmp = path + ".tmp-quicktest"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    if os.path.exists(path):
        shutil.copymode(path, tmp)
    os.replace(tmp, path)


def main(argv):
    path = settings_path()
    try:
        data = load(path)
    except (ValueError, OSError) as e:
        print(json.dumps({"ok": False, "error": "can't read %s: %s" % (path, e), "path": path}))
        return 1
    if "--check" in argv:
        print(json.dumps({"ok": True, "installed": installed(data), "path": path}))
        return 0
    data = strip_status(strip(data)) if "--remove" in argv else add(data)
    try:
        save(path, data)
    except OSError as e:
        print(json.dumps({"ok": False, "error": str(e), "path": path}))
        return 1
    print(json.dumps({"ok": True, "installed": installed(data), "path": path}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
