#!/usr/bin/env python3
"""Show the Claude Code session you're in as Discord Rich Presence.

    python3 claude-presence.py

Reads commands on stdin, writes state snapshots on stdout, one JSON object per line.
Runs forever; a Discord that isn't running (or quits) is a state, not a failure — same
contract as discord-rpc.py, and for the same reason.

── Why this is a SEPARATE process from discord-rpc.py ────────────────────────
Same socket, same framing, completely different lifetime. `discord-rpc.py` holds an
OAuth'd session so it can drive the voice call; this one only ever sends SET_ACTIVITY,
and it must do so under a DIFFERENT application id, because the bold first line of a
rich presence card is the application's NAME. Measured against the existing app:

    {"cmd":"SET_ACTIVITY","data":{…,"name":"Quicktest",
     "application_id":"1531634092607668244","type":0},"evt":null}

Sharing the connection would mean every Claude session announced itself as "Quicktest".
One connection per application id is the only way to get "Claude Code" on that line.

── SET_ACTIVITY NEEDS NO OAUTH, whatever the docs say ────────────────────────
docs.discord.com/developers/topics/rpc states that "in order to call any commands over
RPC, you must be authenticated or you will receive a code 4006 error response". For
SET_ACTIVITY that is simply not true, and it was worth measuring rather than believing:
a bare handshake followed by SET_ACTIVITY answers `"evt": null` — success. So this file
needs a client id and NOTHING else. No secret, no scopes, no token on disk, none of
discord-credentials.py. If a future Discord starts enforcing what the docs claim, the
symptom is an `ERROR` frame with code 4006 and `stage` goes to "unauthorized".

── Where the session data comes from ─────────────────────────────────────────
Claude Code keeps a live registry at ~/.claude/sessions/<pid>.json, one file per running
session, removed when it exits:

    {"pid":39211,"sessionId":"2348…","cwd":"/home/user/.config/quicktest",
     "startedAt":1785872478264,"procStart":"808051","version":"2.1.221",
     "kind":"interactive","name":"fetch-customizability","status":"idle",
     "updatedAt":1785875525870}

`name` is the session name and it updates live. `status` is busy/idle. `startedAt` feeds
the elapsed-time line. Nothing here parses terminal output or greps `ps` — the registry
is the shell's own bookkeeping and it is already exactly the shape we need.

`procStart` is the process's start time from /proc/<pid>/stat field 22, and it is the
reason PID REUSE cannot fool this: a file naming a live pid whose start time disagrees
is a stale file about a dead session, not a running one.

── Why this one polls, when the rest of the repo refuses to ──────────────────
There is no event source for ~/.claude/sessions. It is a directory of small files that
another program rewrites in place, so a directory mtime doesn't even change when the
interesting part does. inotify via ctypes was considered and rejected: ~60 lines of
syscall plumbing to save a stat() of two or three files per second. The Hyprland half is
NOT polled — it comes off the event socket, which is what that socket is for.

── Rate limiting is not optional ─────────────────────────────────────────────
Discord drops SET_ACTIVITY frames sent faster than roughly 5 per 20 seconds, silently.
`status` flips busy/idle on nearly every keystroke you send Claude, so the naive version
of this file would spend most of its life rate-limited and showing a stale card. Updates
are COALESCED: the newest payload wins and is sent when the window opens, so what you
see is always the current state, just occasionally a few seconds late.
"""

import sys, os, re, json, struct, socket, selectors, signal, time, uuid, subprocess
import sys as _sys; _sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qspaths   # where secret files live (outside the repo)

import secretstore       # presenceClientId may live in the system keyring (see its header)

OP_HANDSHAKE, OP_FRAME, OP_CLOSE, OP_PING, OP_PONG = 0, 1, 2, 3, 4

# Discord tolerates ~5 SET_ACTIVITY per 20s. 5s between sends stays comfortably under
# that even if every single one carries a change.
MIN_UPDATE_INTERVAL = 5.0

# How often to re-stat the session registry. Cheap: two or three files.
SESSION_POLL_INTERVAL = 1.0

# A Discord that isn't running is the common case, not an error. Don't hammer it.
RECONNECT_INTERVAL = 10.0

CONFIG_PATH = qspaths.secret_file("discord-rpc.json")   # outside the repo: qspaths.py

CLAUDE_HOME = os.path.expanduser("~/.claude")
SESSIONS_DIR = os.path.join(CLAUDE_HOME, "sessions")
PROJECTS_DIR = os.path.join(CLAUDE_HOME, "projects")

# Only the tail of a transcript is read when looking for the session's AI title —
# they reach 10 MB and the title is rewritten near the end on every turn.
TRANSCRIPT_TAIL_BYTES = 256 * 1024


# ── Where state goes and options come from ────────────────────────────────────
# Two modes, and the difference is only plumbing:
#
#   attached (default)   stdout/stdin. What the tests and a hand-run use.
#   detached (--state-file/--options-file)
#                        a state FILE and an options FILE.
#
# The detached pair exists because a pipe has exactly ONE reader: when Quickshell
# reloads, its end of the pipe closes and the daemon either dies or is writing into
# nothing. A file has no such relationship — the daemon writes it regardless of who is
# or isn't watching, and a freshly reloaded shell just reads it. Same reasoning as
# update-run.sh's log file, and the same reason it is a file rather than a socket.
STATE_FILE = ""
OPTIONS_FILE = ""


def emit(obj):
    """Publish a state snapshot: one JSON line on stdout, or the state file.

    The file write is atomic — a temp file in the same directory, then rename(2), which
    is atomic on the same filesystem. Without it a reader can catch a half-written file
    and see truncated JSON, and since the shell watches this path for changes it would
    catch it often rather than rarely.
    """
    if not STATE_FILE:
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()
        return
    tmp = STATE_FILE + ".tmp"
    try:
        os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
        with open(tmp, "w") as fh:
            json.dump(obj, fh)
        os.replace(tmp, STATE_FILE)
    except OSError as e:
        log("could not write state: %s" % e)


def log(msg):
    """Diagnostics go to stderr, which QML logs but never parses."""
    sys.stderr.write("claude-presence: %s\n" % msg)
    sys.stderr.flush()


# ══ The session registry ══════════════════════════════════════════════════════

def proc_start(pid):
    """Field 22 of /proc/<pid>/stat, as a string. None if the process is gone.

    Read from the raw line rather than split()[21] because field 2 is the executable
    name in parentheses and MAY CONTAIN SPACES — "(Web Content)" is a real one. Splitting
    the whole line shifts every field after it and silently returns the wrong number.
    """
    try:
        with open("/proc/%d/stat" % pid) as fh:
            line = fh.read()
    except OSError:
        return None
    close = line.rfind(")")
    if close < 0:
        return None
    fields = line[close + 2:].split()
    # After the ")" the fields are state(3), ppid(4), … so starttime(22) is index 19.
    return fields[19] if len(fields) > 19 else None


def parent_pid(pid):
    """PPID from /proc/<pid>/stat, with the same parenthesis caution as above."""
    try:
        with open("/proc/%d/stat" % pid) as fh:
            line = fh.read()
    except OSError:
        return None
    close = line.rfind(")")
    if close < 0:
        return None
    fields = line[close + 2:].split()
    try:
        return int(fields[1])          # state(3) is index 0, ppid(4) is index 1
    except (IndexError, ValueError):
        return None


def read_sessions():
    """Every LIVE interactive session, newest activity first.

    A file whose pid is dead — or alive but with a different start time, meaning the pid
    was reused — is skipped rather than shown. Claude Code removes these itself on a
    clean exit; a session killed with SIGKILL leaves one behind, and without this check
    the presence would happily advertise a session that ended days ago.
    """
    out = []
    try:
        names = os.listdir(SESSIONS_DIR)
    except OSError:
        return out

    for name in names:
        if not name.endswith(".json"):
            continue
        try:
            with open(os.path.join(SESSIONS_DIR, name)) as fh:
                s = json.load(fh)
        except (OSError, ValueError):
            continue

        pid = s.get("pid")
        if not isinstance(pid, int):
            continue
        live = proc_start(pid)
        if live is None or (s.get("procStart") and str(s["procStart"]) != live):
            continue
        # Non-interactive runs (`claude -p`, hooks, subagent shells) are not something
        # anyone means by "my terminal is running Claude Code".
        if s.get("kind") and s["kind"] != "interactive":
            continue
        out.append(s)

    out.sort(key=lambda s: s.get("updatedAt") or 0, reverse=True)
    return out


def pick_session(sessions):
    """Which session the card is about.

    A session actively working beats one sitting at a prompt, because that's the one you
    would point at if someone asked what you were doing. Ties break on most recently
    updated. Returns None when nothing is running, which clears the presence.
    """
    if not sessions:
        return None
    busy = [s for s in sessions if s.get("status") == "busy"]
    return (busy or sessions)[0]


def project_dir_for(cwd):
    """~/.claude/projects/<munged cwd>, using Claude Code's own munging.

    Every "/" and "." becomes "-", so /home/user/.config/quicktest is stored as
    -home-user--config-quicktest (the double dash is the "/." of "/.config").
    """
    munged = cwd.replace("/", "-").replace(".", "-")
    return os.path.join(PROJECTS_DIR, munged)


def read_transcript(session):
    """{title, model, context} from the tail of the session's transcript.

    All three come from ONE pass over the same bytes. The transcript is JSONL and each
    of these is written repeatedly as the session goes, so the LAST occurrence wins.
    Only the tail is read: these files reach ten megabytes and re-reading one on every
    update would be the most expensive thing this process does, for values that live
    near the end by construction. 64 KB was enough on a 3.8 MB transcript; the 256 KB
    here is slack for a long turn.
    """
    out = {"title": "", "model": "", "context": 0}
    sid, cwd = session.get("sessionId"), session.get("cwd")
    if not sid or not cwd:
        return out
    # `_path` is for a caller that already has the file (a finished session found by
    # scanning the projects directory): the munging above is Claude Code's, and a cwd
    # with a character it also rewrites would miss the file.
    path = session.get("_path") or os.path.join(project_dir_for(cwd), sid + ".jsonl")
    try:
        with open(path, "rb") as fh:
            fh.seek(0, os.SEEK_END)
            size = fh.tell()
            fh.seek(max(0, size - TRANSCRIPT_TAIL_BYTES))
            chunk = fh.read()
    except OSError:
        return out

    # A partial first line is expected when the seek lands mid-record; it fails to parse
    # and is skipped like any other malformed line.
    for raw in chunk.split(b"\n"):
        if b'"ai-title"' not in raw and b'"usage"' not in raw:
            continue
        try:
            rec = json.loads(raw)
        except ValueError:
            continue

        if rec.get("type") == "ai-title" and rec.get("aiTitle"):
            out["title"] = rec["aiTitle"]
            continue

        if rec.get("type") != "assistant":
            continue
        msg = rec.get("message") or {}
        model, usage = msg.get("model"), msg.get("usage")
        # "<synthetic>" is a real value here — it marks messages the CLI injected
        # rather than the model producing them (interrupts, error notices). Taking it
        # at face value makes the card periodically announce a model called
        # "<synthetic>", which is both wrong and impossible to explain.
        if not model or model == "<synthetic>" or not isinstance(usage, dict):
            continue
        out["model"] = model
        # How full the window is. Cache reads are the bulk of it and they ARE the
        # context — the same conversation re-sent each turn — so they belong in this
        # sum. What they must NOT be is accumulated across turns: adding every turn's
        # cache_read together gives ~38M for a session holding 204k, a number that is
        # arithmetically real and completely meaningless.
        out["context"] = (usage.get("input_tokens") or 0) \
            + (usage.get("cache_read_input_tokens") or 0) \
            + (usage.get("cache_creation_input_tokens") or 0)
    return out


def ai_title(session):
    """Just the title. Kept because the state emitter wants only this."""
    return read_transcript(session)["title"]


def pretty_model(model_id):
    """"claude-opus-5" → "Opus 5". "" for anything unrecognisable.

    Trims the provider prefixes and the trailing date stamp that Bedrock/Vertex ids
    carry, so the card shows a name rather than a slug. Unknown shapes fall through to
    a best-effort title-case instead of being dropped: a model this doesn't recognise
    is far likelier to be one that shipped after this was written than a bug.
    """
    if not model_id or model_id == "<synthetic>":
        return ""
    s = model_id.split("/")[-1]
    s = re.sub(r"^(us|eu|apac)\.", "", s)
    s = re.sub(r"^anthropic\.", "", s)
    s = re.sub(r"^claude-", "", s)
    s = re.sub(r"-v\d+:\d+$", "", s)          # bedrock "-v1:0"
    s = re.sub(r"-?\d{8}$", "", s)            # trailing yyyymmdd
    parts = [p for p in s.split("-") if p]
    if not parts:
        return ""
    family = parts[0][:1].upper() + parts[0][1:]
    version = ".".join(parts[1:])
    return (family + " " + version).strip()


def fmt_tokens(n):
    """204441 → "204k". Rounded, because a presence card is not a billing report."""
    if not n or n <= 0:
        return ""
    if n < 1000:
        return str(n)
    if n < 1000000:
        return "%dk" % round(n / 1000.0)
    return "%.1fM" % (n / 1000000.0)


# ══ Hyprland: which workspace is that terminal on ═════════════════════════════
#
# The session's pid is Claude Code itself, which is a grandchild of the terminal window:
#
#     claude(39211) → bash(39007) → kitty(38993)
#
# Hyprland knows the terminal's pid, not Claude's, so the ancestor chain is walked until
# one of them matches a client. `hyprctl clients -j` is asked ONCE per terminal window
# and the address cached, because a window's pid never changes — after that the workspace
# is tracked off the event socket, which pushes moves at us for free.

MAX_ANCESTOR_HOPS = 6


class Hypr:
    def __init__(self):
        self.sock = None
        self._addr_by_pid = {}         # claude pid → window address ("" = no match)
        self._workspace = {}           # window address → workspace name

    # ── The event socket ──────────────────────────────────────────────────────
    def runtime_dir(self):
        sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
        if not sig:
            return None
        base = os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid()
        return os.path.join(base, "hypr", sig)

    def connect(self):
        """Subscribe to Hyprland's event stream. Absent Hyprland is not an error —
        the workspace line just never appears."""
        d = self.runtime_dir()
        if not d:
            return None
        path = os.path.join(d, ".socket2.sock")
        if not os.path.exists(path):
            return None
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(path)
            s.setblocking(False)
            self.sock = s
            return s
        except OSError as e:
            log("hyprland event socket: %s" % e)
            return None

    def drain(self):
        """Read whatever the event socket has. Returns True if anything we care about
        happened, meaning cached window→workspace mapping is now suspect."""
        if not self.sock:
            return False
        dirty = False
        try:
            while True:
                data = self.sock.recv(65536)
                if not data:
                    self.sock.close()
                    self.sock = None
                    return True
                for line in data.decode("utf-8", "replace").splitlines():
                    evt = line.split(">>", 1)[0]
                    if evt in ("workspace", "workspacev2", "movewindow", "movewindowv2",
                               "openwindow", "closewindow", "focusedmon"):
                        dirty = True
        except BlockingIOError:
            pass
        except OSError:
            self.sock = None
            dirty = True
        return dirty

    def invalidate(self):
        self._workspace = {}

    def forget_pid(self, pid):
        self._addr_by_pid.pop(pid, None)

    # ── The one subprocess, and when it runs ──────────────────────────────────
    def _clients(self):
        try:
            out = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True,
                                 timeout=3, text=True)
        except (OSError, subprocess.SubprocessError) as e:
            log("hyprctl clients: %s" % e)
            return []
        if out.returncode != 0:
            return []
        try:
            return json.loads(out.stdout or "[]")
        except ValueError:
            return []

    def workspace_for(self, pid):
        """Workspace name for the window that owns `pid`, or "" if it can't be placed."""
        if pid is None:
            return ""

        addr = self._addr_by_pid.get(pid)
        if addr is None:                      # never resolved for this session
            addr = self._resolve(pid)
            self._addr_by_pid[pid] = addr
        if not addr:
            return ""

        if addr in self._workspace:
            return self._workspace[addr]

        for c in self._clients():
            a = c.get("address")
            if a:
                self._workspace[a] = str((c.get("workspace") or {}).get("name") or "")
        # A window that has since closed answers "" and stays cached as such until the
        # next event invalidates the map.
        return self._workspace.get(addr, "")

    def _resolve(self, pid):
        """Walk pid → parent → parent… until one matches a Hyprland client."""
        clients = self._clients()
        if not clients:
            return ""
        by_pid = {c.get("pid"): c.get("address") for c in clients if c.get("pid")}

        cur, hops = pid, 0
        while cur and cur > 1 and hops < MAX_ANCESTOR_HOPS:
            if cur in by_pid:
                for c in clients:
                    if c.get("pid") == cur:
                        self._workspace[c.get("address")] = \
                            str((c.get("workspace") or {}).get("name") or "")
                return by_pid[cur]
            cur = parent_pid(cur)
            hops += 1
        return ""


# ══ Discord ═══════════════════════════════════════════════════════════════════

def ipc_candidates():
    """Every place Discord might have put its socket, in the order worth trying.

    Flatpak and snap builds nest it; the plain build puts it straight in the runtime
    dir. Ten indices because a second Discord (Canary alongside stable) takes the next
    one — the same reason discord-rpc.json carries a LIST of window classes rather than
    assuming the official build.
    """
    base = (os.environ.get("XDG_RUNTIME_DIR") or os.environ.get("TMPDIR")
            or os.environ.get("TMP") or "/tmp").rstrip("/")
    for tail in ("", "/app/com.discordapp.Discord", "/app/com.discordapp.DiscordCanary",
                 "/snap.discord", "/.flatpak/dev.vencord.Vesktop/xdg-run"):
        for i in range(10):
            yield "%s%s/discord-ipc-%d" % (base, tail, i)


class Discord:
    """A connection that only ever sends SET_ACTIVITY."""

    def __init__(self, client_id):
        self.client_id = client_id
        self.sock = None
        self.ready = False
        self.buf = b""
        self.last_send = 0.0
        self.sent = None               # the activity Discord currently believes
        self.error = ""

    def connect(self):
        for path in ipc_candidates():
            if not os.path.exists(path):
                continue
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.settimeout(2.0)
                s.connect(path)
                s.setblocking(False)
                self.sock, self.buf, self.ready, self.sent = s, b"", False, None
                self._send_frame(OP_HANDSHAKE, {"v": 1, "client_id": self.client_id})
                return True
            except OSError:
                continue
        return False

    def close(self):
        if self.sock:
            try:
                self.sock.close()
            except OSError:
                pass
        self.sock, self.ready, self.sent = None, False, None

    def _send_frame(self, op, payload):
        if not self.sock:
            return
        body = json.dumps(payload).encode()
        try:
            self.sock.sendall(struct.pack("<II", op, len(body)) + body)
        except OSError as e:
            log("send: %s" % e)
            self.close()

    def pump(self):
        """Read whatever is waiting. Returns True if the connection state changed."""
        if not self.sock:
            return False
        changed = False
        try:
            while True:
                data = self.sock.recv(65536)
                if not data:
                    self.close()
                    return True
                self.buf += data
        except BlockingIOError:
            pass
        except OSError:
            self.close()
            return True

        while len(self.buf) >= 8:
            op, ln = struct.unpack("<II", self.buf[:8])
            if len(self.buf) < 8 + ln:
                break
            body, self.buf = self.buf[8:8 + ln], self.buf[8 + ln:]
            try:
                msg = json.loads(body or b"{}")
            except ValueError:
                continue

            if op == OP_PING:
                self._send_frame(OP_PONG, msg)
                continue
            if op == OP_CLOSE:
                log("closed by discord: %s" % json.dumps(msg)[:200])
                self.close()
                return True
            if msg.get("evt") == "READY":
                self.ready, self.error, changed = True, "", True
            elif msg.get("evt") == "ERROR":
                d = msg.get("data") or {}
                self.error = "%s %s" % (d.get("code", ""), d.get("message", ""))
                log("error frame: %s" % self.error)
                changed = True
        return changed

    def apply(self, activity):
        """Push `activity` (or None to clear) if it differs and the window is open.

        Returns the seconds to wait before this is worth calling again, or None if there
        is nothing pending — that value becomes the select() timeout, so a coalesced
        update lands as soon as it legally can rather than on the next poll tick.
        """
        if not (self.sock and self.ready):
            return None
        if activity == self.sent:
            return None
        wait = MIN_UPDATE_INTERVAL - (time.time() - self.last_send)
        if wait > 0:
            return wait
        self._send_frame(OP_FRAME, {
            "cmd": "SET_ACTIVITY",
            "nonce": str(uuid.uuid4()),
            "args": {"pid": os.getpid(), "activity": activity},
        })
        self.sent = activity
        self.last_send = time.time()
        return None


# ══ The card ══════════════════════════════════════════════════════════════════

def build_activity(session, workspace, opts, _tr=None, session_count=1):
    """The Discord activity object, or None when nothing should be shown.

    details — the session name, which is what the CLI itself calls this session,
              followed by the model.
    state   — the project folder, plus whichever of workspace / context tokens are
              switched on, plus how many OTHER live sessions aren't shown.

    `_tr` injects the transcript read, so the line-composition rules can be tested
    without a transcript on disk for every case. Production always leaves it None.
    """
    if not session:
        return None

    tr = read_transcript(session) if _tr is None else _tr

    name = ""
    if opts.get("useAiTitle"):
        name = tr["title"]
    if not name:
        name = session.get("name") or ""
    if not name:
        name = "Claude Code"

    # ── Line two, built from whichever parts are switched on ──────────────────
    # Assembled as a list rather than by string concatenation so that a part being
    # absent — no workspace resolved, tokens off, a transcript with no usage yet —
    # leaves no stray separator behind.
    # Rendered FIRST, because whether line two is crowded depends on what actually
    # comes out, not on whether the raw values are present. "<synthetic>" is a truthy
    # model id that renders to nothing — checking the raw value shortened "workspace 2"
    # to "ws 2" to make room for something that then didn't appear.
    model  = pretty_model(tr["model"]) if opts.get("showModel", True) else ""
    tokens = fmt_tokens(tr["context"]) if opts.get("showTokens", True) else ""

    # ── Line one: what you're doing, and what's doing it ──────────────────────
    # The model sits here rather than on line two because it belongs with the
    # session's identity, and because line two was carrying four values.
    details = " · ".join([p for p in (name, model) if p])

    # ── Line two: where it's happening ────────────────────────────────────────
    # Joined from a list rather than concatenated so a missing part — no workspace
    # resolved, tokens switched off, a transcript with no usage yet — leaves no
    # stray separator behind.
    parts = [os.path.basename((session.get("cwd") or "").rstrip("/")) or "~"]

    if workspace and opts.get("showWorkspace", True):
        # "workspace 2" spelled out when it has the line to itself, "ws 2" when it is
        # sharing with the token count. The full word is nicer to read and the short
        # one is what makes both fit.
        parts.append(("ws %s" if tokens else "workspace %s") % workspace)

    if tokens:
        parts.append(tokens)

    # Otherwise the card looks like a single terminal even with three open — a
    # stranger thing to hide than the workspace or token count already on this line.
    if session_count > 1 and opts.get("showSessionCount", True):
        parts.append("+%d more" % (session_count - 1))

    state = " · ".join(parts)

    activity = {
        # Discord truncates at 128; trimming here keeps the ellipsis ours.
        "details": details[:126],
        "state": state[:126],
        "timestamps": {"start": int((session.get("startedAt") or 0) / 1000)},
    }

    # ── The bold first line ───────────────────────────────────────────────────
    # Defaults to the Discord APPLICATION's name, and for a long time that looked
    # like the only possibility — the echo of a payload without this field carries the
    # app name back whether you asked for it or not. It turns out to be settable, which
    # matters because Discord's portal REFUSES some application names: this one had to
    # be registered as "Claw'd Code" because "Claude" was rejected, and without this
    # field that misspelling is what every session announces.
    #
    # Measured, since the docs list `name` under the gateway Activity object and say
    # nothing about it for SET_ACTIVITY:
    #     sent {"name": "Claude Code", …}  →  echoed  "name": "Claude Code"
    # against an application actually named "Claw'd Code". Honoured for activity types
    # 0, 2 and 3 alike.
    app_name = opts.get("appName") or ""
    if app_name:
        activity["name"] = app_name[:126]

    image = opts.get("largeImage") or ""
    if image:
        activity["assets"] = {
            "large_image": image,
            "large_text": session.get("version") and ("Claude Code %s" % session["version"])
                          or "Claude Code",
        }
    return activity


# ══ The loop ══════════════════════════════════════════════════════════════════

def load_client_id():
    """`presenceClientId` out of discord-rpc.json, or the keyring when it has moved there.

    Deliberately a DIFFERENT key from `clientId`: that one is the voice-control app, and
    the presence card is titled with the application's own name, so they cannot be the
    same application. Absent is the expected state on a fresh install — it becomes the
    "needs-setup" stage the settings page renders as a prompt, exactly like the voice
    panel does for its own credentials.
    """
    try:
        with open(CONFIG_PATH) as fh:
            cfg = json.load(fh)
    except (OSError, ValueError):
        return ""
    # A file value wins; a keyring one is asked for only when the file lists it under
    # "_keyring", so a machine that never used the keyring never talks to one.
    return secretstore.resolve(cfg, "presenceClientId", "discord-presence-client-id")


class Runner:
    def __init__(self):
        # These have to be RIGHT, not merely present. The daemon is detached and starts
        # independently of the shell, so it publishes at least one card before QML has
        # written options.json — and on a boot where the shell never gets that far, it
        # publishes on these forever. `largeImage` was "claude" here, which is not a key
        # that exists in the application's asset library, and Discord answers a bad key
        # by silently dropping the image: a perfect card with no icon and nothing to say
        # why. It duplicates ClaudePresence.qml's `assetKey` deliberately — the QML
        # value is authoritative once it speaks, but "correct only once someone tells
        # it" is not a reasonable default for a process that runs on its own.
        self.opts = {"useAiTitle": False, "showWorkspace": True, "showModel": True,
                     "showTokens": True, "showSessionCount": True,
                     "largeImage": "claude-orange-on-black", "appName": "Claude Code"}
        self.client_id = load_client_id()
        self.discord = Discord(self.client_id) if self.client_id else None
        self.hypr = Hypr()
        self.sel = selectors.DefaultSelector()
        self.last_poll = 0.0
        self.last_connect_try = 0.0
        self.options_mtime = None
        self.session = None
        self.workspace = ""
        self.activity = None
        self.published = None

    # ── Options, when they arrive as a file rather than on stdin ──────────────
    # Polled by mtime rather than watched. This runs inside a loop that already wakes
    # once a second for the session registry, so noticing a changed options file costs
    # one extra stat() on a tick that was happening anyway.
    def poll_options_file(self):
        if not OPTIONS_FILE:
            return
        try:
            mtime = os.stat(OPTIONS_FILE).st_mtime
        except OSError:
            return
        if mtime == self.options_mtime:
            return
        self.options_mtime = mtime
        try:
            with open(OPTIONS_FILE) as fh:
                incoming = json.load(fh)
        except (OSError, ValueError):
            return
        if not isinstance(incoming, dict):
            return
        # Only known keys, so a stray field in the file can't become a payload field.
        for k in ("useAiTitle", "showWorkspace", "showModel", "showTokens",
                  "showSessionCount", "largeImage", "appName"):
            if k in incoming:
                self.opts[k] = incoming[k]
        self.reload_client_id()
        self.refresh(force=True)

    def reload_client_id(self):
        new = load_client_id()
        if new == self.client_id:
            return
        if self.discord:
            self.discord.close()
        self.client_id = new
        self.discord = Discord(new) if new else None
        self.last_connect_try = 0.0

    # ── stdin: the QML side changing its mind ─────────────────────────────────
    def handle_command(self, line):
        try:
            cmd = json.loads(line)
        except ValueError:
            return
        c = cmd.get("c")
        if c == "options":
            for k in ("useAiTitle", "showWorkspace", "showModel", "showTokens",
                      "showSessionCount", "largeImage", "appName"):
                if k in cmd:
                    self.opts[k] = cmd[k]
            self.refresh(force=True)
        elif c == "reloadClientId":
            self.reload_client_id()
            self.emit_state()
        elif c == "refresh":
            self.refresh(force=True)

    # ── State out ─────────────────────────────────────────────────────────────
    def stage(self):
        if not self.client_id:
            return "no-client-id"
        if self.discord and self.discord.error.startswith("4006"):
            return "unauthorized"
        if not (self.discord and self.discord.ready):
            return "no-discord"
        return ""

    def emit_state(self):
        s = self.session or {}
        tr = read_transcript(s) if s else {"title": "", "model": "", "context": 0}
        emit({
            "model":   pretty_model(tr["model"]),
            "context": tr["context"],
            "stage": self.stage(),
            "connected": bool(self.discord and self.discord.ready),
            "sessionCount": self.session_count,
            "session": {
                "name": s.get("name") or "",
                "title": tr["title"] if self.opts.get("useAiTitle") else "",
                "cwd": s.get("cwd") or "",
                "status": s.get("status") or "",
                "version": s.get("version") or "",
                "startedAt": s.get("startedAt") or 0,
            } if s else None,
            "workspace": self.workspace,
            "details": (self.activity or {}).get("details", ""),
            "state": (self.activity or {}).get("state", ""),
            "error": (self.discord.error if self.discord else ""),
        })

    session_count = 0

    # ── Recompute what should be on screen ────────────────────────────────────
    def refresh(self, force=False):
        sessions = read_sessions()
        self.session_count = len(sessions)
        session = pick_session(sessions)

        pid = session.get("pid") if session else None
        workspace = self.hypr.workspace_for(pid) if pid else ""

        activity = build_activity(session, workspace, self.opts,
                                   session_count=self.session_count)

        if not force and activity == self.activity and workspace == self.workspace:
            return
        self.session, self.workspace, self.activity = session, workspace, activity

        snapshot = json.dumps([activity, workspace, self.stage()], sort_keys=True)
        if snapshot != self.published:
            self.published = snapshot
            self.emit_state()

    def run(self):
        # Detached, stdin is /dev/null and closes immediately — registering it would
        # make the very first select() report EOF and shut the daemon down before it
        # published anything. The options file is the command channel there instead.
        if not OPTIONS_FILE:
            self.sel.register(sys.stdin, selectors.EVENT_READ, "stdin")
        hypr_sock = self.hypr.connect()
        if hypr_sock:
            self.sel.register(hypr_sock, selectors.EVENT_READ, "hypr")

        self.emit_state()
        registered = None

        while True:
            now = time.time()

            # Reconnect to Discord when it isn't there. Quiet, and not too eager.
            if self.discord and not self.discord.sock and \
                    now - self.last_connect_try > RECONNECT_INTERVAL:
                self.last_connect_try = now
                if self.discord.connect():
                    if registered:
                        try:
                            self.sel.unregister(registered)
                        except (KeyError, ValueError):
                            pass
                    registered = self.discord.sock
                    self.sel.register(registered, selectors.EVENT_READ, "discord")

            if now - self.last_poll >= SESSION_POLL_INTERVAL:
                self.last_poll = now
                self.poll_options_file()
                self.refresh()

            pending = self.discord.apply(self.activity) if self.discord else None

            timeout = SESSION_POLL_INTERVAL
            if pending is not None:
                timeout = min(timeout, max(0.05, pending))

            for key, _ in self.sel.select(timeout):
                what = key.data
                if what == "stdin":
                    line = sys.stdin.readline()
                    if not line:
                        return
                    self.handle_command(line.strip())
                elif what == "discord":
                    if self.discord.pump():
                        if not self.discord.sock and registered:
                            try:
                                self.sel.unregister(registered)
                            except (KeyError, ValueError):
                                pass
                            registered = None
                        self.emit_state()
                        self.refresh(force=True)
                elif what == "hypr":
                    if self.hypr.drain():
                        self.hypr.invalidate()
                        self.refresh()
                    if not self.hypr.sock:
                        try:
                            self.sel.unregister(hypr_sock)
                        except (KeyError, ValueError):
                            pass


def parse_args(argv):
    """--state-file / --options-file switch this from a child process to a daemon."""
    global STATE_FILE, OPTIONS_FILE
    it = iter(argv)
    for arg in it:
        if arg == "--state-file":
            STATE_FILE = next(it, "")
        elif arg == "--options-file":
            OPTIONS_FILE = next(it, "")
        elif arg in ("-h", "--help"):
            sys.stdout.write(__doc__ or "")
            raise SystemExit(0)


def main():
    parse_args(sys.argv[1:])

    # SIGTERM must unwind rather than terminate. Python's default handler kills the
    # process outright, so the `finally` below — the only thing that clears the activity
    # from the profile — never runs, and Discord goes on showing a session that ended
    # until it notices the socket is gone, which takes minutes. Raising SystemExit
    # instead makes a stop look exactly like a Ctrl-C.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))

    runner = Runner()
    try:
        runner.run()
    except (KeyboardInterrupt, SystemExit):
        pass
    finally:
        # Leave nothing behind on the profile: a presence that outlives the process is
        # a lie Discord will happily keep telling for minutes.
        if runner.discord and runner.discord.sock and runner.discord.ready:
            runner.discord._send_frame(OP_FRAME, {
                "cmd": "SET_ACTIVITY", "nonce": str(uuid.uuid4()),
                "args": {"pid": os.getpid(), "activity": None}})
            time.sleep(0.2)
            runner.discord.close()


if __name__ == "__main__":
    main()
