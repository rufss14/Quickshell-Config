#!/usr/bin/env python3
"""
test-claude-sessions.py — claude-hook.py, claude-statusline.py, install-claude-hooks.py, claude-sessions.py.

    python3 scripts/test-claude-sessions.py

Safe: every file lives in a temp dir — a fake HOME (its own ~/.claude registry and
transcript), a fake XDG_RUNTIME_DIR and a fake CLAUDE_CONFIG_DIR. Nothing reads or
writes your real Claude Code settings or sessions.
"""
import importlib.util
import json
import os
import select
import stat
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
passed = failed = 0


def check(name, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print("FAIL %s\n  got:  %r\n  want: %r" % (name, got, want))


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, file))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


tmp = tempfile.mkdtemp(prefix="claude-sessions-test-")
run = os.path.join(tmp, "run")
home = os.path.join(tmp, "home")
cfg = os.path.join(tmp, "cfg")
for d in (run, home, cfg):
    os.makedirs(d)

# ── The hook's state ──────────────────────────────────────────────────────────
hook = load("claude_hook", "claude-hook.py")
st = hook.update({}, {"session_id": "s1", "hook_event_name": "PermissionRequest", "tool_name": "Bash",
                      "tool_input": {"command": "export TOKEN=secret"}}, 1000)
check("permission", (st["attention"], st["message"]), ("permission", "Wants to use Bash"))
check("no command line kept", "secret" in json.dumps(st), False)
st = hook.update(st, {"session_id": "s1", "hook_event_name": "PostToolUse", "tool_name": "Bash"}, 1001)
check("answered clears", st["attention"], "")
st = hook.update(st, {"session_id": "s1", "hook_event_name": "PreToolUse", "tool_name": "Edit",
                      "tool_input": {"file_path": "/home/x/project/secret-dir/VoicePanel.qml"}}, 1002)
check("activity is the basename", st["activity"], "Edit · VoicePanel.qml")
st = hook.update(st, {"session_id": "s1", "hook_event_name": "PreToolUse", "tool_name": "Bash",
                      "tool_input": {"command": "rm -rf /"}}, 1003)
check("bash activity, no command", st["activity"], "Bash")
st = hook.update(st, {"session_id": "s1", "hook_event_name": "Notification", "type": "idle_prompt",
                      "message": "Claude is waiting for your input"}, 1004)
check("idle prompt", (st["attention"], st["message"]), ("input", "Claude is waiting for your input"))
st = hook.update(st, {"session_id": "s1", "hook_event_name": "Stop", "last_assistant_message": "x" * 500}, 1005)
check("stop clears and keeps a clipped last", (st["attention"], st["activity"], len(st["last"])), ("", "", 200))

env = dict(os.environ, XDG_RUNTIME_DIR=run, HOME=home, CLAUDE_CONFIG_DIR=cfg)


def hook_run(ev):
    return subprocess.run([sys.executable, os.path.join(HERE, "claude-hook.py")],
                          input=json.dumps(ev), capture_output=True, text=True, env=env)


r = hook_run({"session_id": "abc-1", "hook_event_name": "PermissionRequest", "tool_name": "Write"})
path = os.path.join(run, "quickshell-quicktest-claude", "abc-1.json")
check("hook silent, exit 0", (r.returncode, r.stdout, r.stderr), (0, "", ""))
check("hook file written", os.path.isfile(path), True)
check("hook file private", stat.S_IMODE(os.stat(path).st_mode), 0o600)
check("hook bad id ignored", hook_run({"session_id": "../../etc", "hook_event_name": "Stop"}).returncode, 0)
check("hook garbage ignored", subprocess.run([sys.executable, os.path.join(HERE, "claude-hook.py")],
      input="{", capture_output=True, text=True, env=env).returncode, 0)
hook_run({"session_id": "abc-1", "hook_event_name": "SessionEnd"})
check("SessionEnd removes it", os.path.exists(path), False)

# ── The status line: only the rate limit is kept ──────────────────────────────
sl = load("claude_statusline", "claude-statusline.py")
rec = sl.parse({"session_id": "s", "cwd": "/secret/path", "model": {"id": "x"}, "cost": {"total": 9},
                "rate_limits": {"five_hour": {"used_percentage": 83.46, "resets_at": 1789264200},
                                "seven_day": {"used_percentage": 12, "resets_at": "2026-10-09T14:00:00Z"}}}, 5000)
check("five-hour kept", rec["five_hour"], {"pct": 83.5, "resetsAt": 1789264200})
check("ISO reset time → epoch seconds", rec["seven_day"]["resetsAt"], 1791554400)
check("nothing else kept", sorted(rec), ["at", "five_hour", "seven_day"])
check("no secret in it", "secret" in json.dumps(rec), False)
check("ms reset time → seconds", sl.epoch(1789264200000), 1789264200)
check("pct clamped", sl.window({"used_percentage": 400, "resets_at": 1789264200})["pct"], 100.0)
check("bad pct dropped", sl.window({"used_percentage": "x", "resets_at": 1789264200}), None)
check("no rate_limits → nothing to save", sl.parse({"session_id": "s"}, 1), None)
check("one window is enough", sl.parse({"rate_limits": {"five_hour": {"used_percentage": 1, "resets_at": 5}}}, 1)["seven_day"], None)


def statusline(payload, *args):
    return subprocess.run([sys.executable, os.path.join(HERE, "claude-statusline.py"), *args],
                          input=payload if isinstance(payload, str) else json.dumps(payload),
                          capture_output=True, text=True, env=env)


ratefile = os.path.join(run, "quickshell-quicktest-claude-rate.json")
r = statusline({"rate_limits": {"five_hour": {"used_percentage": 40, "resets_at": 1789264200}}})
check("statusline silent, exit 0", (r.returncode, r.stdout, r.stderr), (0, "", ""))
check("rate file written, private", stat.S_IMODE(os.stat(ratefile).st_mode), 0o600)
statusline({"session_id": "no limits this time"})
check("a payload without limits leaves the last figures", json.load(open(ratefile))["five_hour"]["pct"], 40)
check("garbage in, exit 0", statusline("{").returncode, 0)
r = statusline({"x": 1}, "--", "cat | tr a-z A-Z")
check("a wrapped status line gets the same input and speaks", r.stdout, '{"X": 1}')

# ── The installer ─────────────────────────────────────────────────────────────
inst = os.path.join(HERE, "install-claude-hooks.py")
settings = os.path.join(cfg, "settings.json")
original = {"model": "opus", "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "notify-send done"}]}]}}
with open(settings, "w") as f:
    json.dump(original, f)


def installer(*a):
    r = subprocess.run([sys.executable, inst, *a], capture_output=True, text=True, env=env)
    return json.loads(r.stdout or "{}")


check("check before", installer("--check")["installed"], False)
check("install", installer()["installed"], True)
data = json.load(open(settings))
check("other settings kept", data["model"], "opus")
check("other hook kept", data["hooks"]["Stop"][0]["hooks"][0]["command"], "notify-send done")
check("ours async", data["hooks"]["Notification"][0]["hooks"][0]["async"], True)
check("tool events matched", data["hooks"]["PreToolUse"][0]["matcher"], "*")
check("backup made", os.path.isfile(settings + ".bak-quicktest"), True)
check("status line set to ours", ("claude-statusline.py" in data["statusLine"]["command"], data["statusLine"]["type"]),
      (True, "command"))
check("…with nothing wrapped", " -- " in data["statusLine"]["command"], False)
installer()
data2 = json.load(open(settings))
check("installing twice changes nothing", data2, data)
check("remove", installer("--remove")["installed"], False)
check("remove restores the original", json.load(open(settings)), original)

# A status line the user already has is wrapped, and comes back exactly.
mine = {"statusLine": {"type": "command", "command": "~/bin/my-status --fancy", "padding": 2}, "model": "opus"}
with open(settings, "w") as f:
    json.dump(mine, f)
check("install over a status line", installer()["installed"], True)
data = json.load(open(settings))
check("theirs is wrapped, not dropped", data["statusLine"]["command"].endswith(" -- ~/bin/my-status --fancy"), True)
check("their other status-line keys kept", data["statusLine"]["padding"], 2)
installer()
check("installing again does not wrap twice", json.load(open(settings)), data)
installer("--remove")
check("remove gives their status line back", json.load(open(settings)), mine)
with open(settings, "w") as f:
    json.dump(original, f)
installer()
installer("--remove")
with open(settings, "w") as f:
    f.write("{ not json")
check("broken settings left alone", installer().get("ok"), False)
check("…untouched", open(settings).read(), "{ not json")

# ── The watcher, against a fake registry ──────────────────────────────────────
# qspaths.py resolves discord-rpc.json at import: both XDG dirs into the temp tree first,
# or loading the script would move (or read) the real one.
os.environ["XDG_STATE_HOME"] = os.path.join(tmp, "state")
os.environ["XDG_CONFIG_HOME"] = os.path.join(tmp, "config")
P = load("claude_presence", "claude-presence.py")
sessions_dir = os.path.join(home, ".claude", "sessions")
os.makedirs(sessions_dir)
me = os.getpid()
cwd = "/home/someone/projects/quicktest"
sid = "11111111-2222-3333-4444-555555555555"
now_ms = int(time.time() * 1000)
with open(os.path.join(sessions_dir, "%d.json" % me), "w") as f:
    json.dump({"pid": me, "sessionId": sid, "cwd": cwd, "startedAt": now_ms - 60000,
               "procStart": P.proc_start(me), "kind": "interactive", "name": "derived-name",
               "status": "busy", "statusUpdatedAt": now_ms - 1000, "updatedAt": now_ms - 1000}, f)
# A dead session must not show.
with open(os.path.join(sessions_dir, "999999.json"), "w") as f:
    json.dump({"pid": 999999, "sessionId": "dead", "cwd": "/x", "kind": "interactive", "status": "idle"}, f)
proj = os.path.join(home, ".claude", "projects", cwd.replace("/", "-").replace(".", "-"))
os.makedirs(proj)
with open(os.path.join(proj, sid + ".jsonl"), "w") as f:
    f.write(json.dumps({"type": "ai-title", "aiTitle": "Build the lens"}) + "\n")

# Ended sessions: one to resume (cwd recorded INSIDE the transcript, not decoded from the
# directory name), and the ones that must not be offered.
work = os.path.join(tmp, "work", "quicktest")
os.makedirs(work)


def transcript(sid_, cwd_, entrypoint="cli", prompt="fix the bar", title=None, age=0):
    d = os.path.join(home, ".claude", "projects", cwd_.replace("/", "-").replace(".", "-"))
    os.makedirs(d, exist_ok=True)
    path_ = os.path.join(d, sid_ + ".jsonl")
    with open(path_, "w") as f:
        f.write(json.dumps({"type": "file-history-snapshot"}) + "\n")
        f.write(json.dumps({"type": "user", "isMeta": True, "message": {"content": "meta"},
                            "cwd": cwd_, "entrypoint": entrypoint}) + "\n")
        f.write(json.dumps({"type": "user", "message": {"content": "<command-name>/clear</command-name>"},
                            "cwd": cwd_, "entrypoint": entrypoint}) + "\n")
        if prompt:
            f.write(json.dumps({"type": "user", "message": {"content": prompt},
                                "cwd": cwd_, "entrypoint": entrypoint}) + "\n")
        if title:
            f.write(json.dumps({"type": "ai-title", "aiTitle": title}) + "\n")
    if age:
        os.utime(path_, (time.time() - age, time.time() - age))


transcript("aaaa1111-0000-0000-0000-000000000001", work, title="Fix the bar", age=60)
transcript("aaaa1111-0000-0000-0000-000000000002", work, prompt="no ai title yet", age=120)
transcript("aaaa1111-0000-0000-0000-000000000003", work, entrypoint="sdk-cli", age=30)       # programmatic
transcript("aaaa1111-0000-0000-0000-000000000004", work, prompt="", age=40)                  # said nothing
transcript("aaaa1111-0000-0000-0000-000000000005", os.path.join(tmp, "gone"), age=50)        # directory deleted
transcript("-rf-flag-looking-id", work, age=20)                                              # not a safe id
hook_run({"session_id": sid, "hook_event_name": "PreToolUse", "tool_name": "Edit",
          "tool_input": {"file_path": "/a/Lens.qml"}})
hook_run({"session_id": sid, "hook_event_name": "PermissionRequest", "tool_name": "Bash"})

os.unlink(ratefile)                  # the status-line checks above wrote one
w = subprocess.Popen([sys.executable, os.path.join(HERE, "claude-sessions.py")], env=env,
                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=False, bufsize=0)


_inbuf = b""


def read_until(pred, timeout=8):
    """The next message satisfying pred. Reads the pipe itself: select() can't see lines
    that arrived together and are already sitting in a Python-side buffer."""
    global _inbuf
    fd = w.stdout.fileno()
    end = time.time() + timeout
    while time.time() < end:
        while b"\n" in _inbuf:
            line, _inbuf = _inbuf.split(b"\n", 1)
            m = json.loads(line)
            if pred(m):
                return m
        if select.select([fd], [], [], 0.1)[0]:
            chunk = os.read(fd, 65536)
            if not chunk:
                return None
            _inbuf += chunk
    return None


try:
    m = read_until(lambda m: m["t"] == "hooks")
    check("hooks status reported", m is not None and m["installed"] is False, True)
    m = read_until(lambda m: m["t"] == "sessions")
    rows = m["sessions"] if m else []
    check("one live session (the dead one skipped)", len(rows), 1)
    r0 = rows[0] if rows else {}
    check("title from the transcript", r0.get("title"), "Build the lens")
    check("project", r0.get("project"), "quicktest")
    check("waiting on permission", (r0.get("attention"), r0.get("message")), ("permission", "Wants to use Bash"))
    check("activity while busy", r0.get("activity"), "Edit · Lens.qml")
    m = read_until(lambda m: m["t"] == "recent")
    rec_ = m["sessions"] if m else []
    check("recent: the two real ones, newest first", [r["sid"][-1] for r in rec_], ["1", "2"])
    check("recent: AI title", rec_[0]["title"], "Fix the bar")
    check("recent: first prompt when there is no title", rec_[1]["title"], "no ai title yet")
    check("recent: where it resumes (its recorded cwd)", (rec_[0]["cwd"], rec_[0]["project"]), (work, "quicktest"))
    check("recent: the live session is not offered", sid in [r["sid"] for r in rec_], False)
    m = read_until(lambda m: m["t"] == "rate")
    check("no rate reported → at 0", m is not None and (m["at"], m["five_hour"]), (0, None))
    hook_run({"session_id": sid, "hook_event_name": "PostToolUse", "tool_name": "Bash"})
    m = read_until(lambda m: m["t"] == "sessions" and m["sessions"] and m["sessions"][0]["attention"] == "")
    check("answering clears it (next poll)", m is not None, True)
    statusline({"rate_limits": {"five_hour": {"used_percentage": 61, "resets_at": 1789264200}}})
    m = read_until(lambda m: m["t"] == "rate" and m["at"] > 0)
    check("the saved rate limit is passed on", m is not None and m["five_hour"], {"pct": 61.0, "resetsAt": 1789264200})
    transcript("aaaa1111-0000-0000-0000-000000000009", work, prompt="a newer one")
    m = read_until(lambda m: m["t"] == "recent" and m["sessions"] and m["sessions"][0]["sid"].endswith("9"))
    check("a new transcript shows up", m is not None, True)
    w.stdin.write((json.dumps({"c": "locate", "pid": 1}) + "\n").encode())      # not a session: refused
    w.stdin.write((json.dumps({"c": "locate", "pid": me}) + "\n").encode())
    w.stdin.flush()
    m = read_until(lambda m: m["t"] == "located")
    check("locate answers only for a listed session", m is not None and m["pid"] == me, True)
finally:
    w.stdin.close()
    try:
        check("stdin EOF → exit 0", w.wait(timeout=5), 0)
    except subprocess.TimeoutExpired:
        w.kill()
        check("stdin EOF → exit 0", "hung", 0)

print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
