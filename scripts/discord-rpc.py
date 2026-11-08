#!/usr/bin/env python3
"""Drive Discord's voice call from the shell, over its local RPC socket.

    python3 discord-rpc.py

Speaks Discord's binary RPC protocol on one side and line-delimited JSON on the other.
Reads commands on stdin, writes state snapshots on stdout, one JSON object per line.
Runs forever; a Discord that isn't running (or quits) is a state, not a failure.

── Why this exists as a process at all ───────────────────────────────────────
Discord's IPC is BINARY framed — little-endian u32 opcode, little-endian u32 length,
then a JSON body. Quickshell's `Socket` is line/text oriented and cannot express a
length-prefixed binary frame, so QML cannot speak this protocol directly no matter how
it's coaxed. The framing has to happen somewhere with real byte handling, and that's
here. Everything above this file gets to think in JSON lines.

── The protocol, as actually observed ────────────────────────────────────────
    op 0  HANDSHAKE   {"v": 1, "client_id": "…"}       → replies DISPATCH/READY
    op 1  FRAME       commands and events both ways
    op 2  CLOSE       either side, with a code
    op 3  PING / 4 PONG

A command is `{"cmd": …, "args": {…}, "nonce": "…"}` and its reply carries the same
nonce back. An EVENT is a `{"cmd": "DISPATCH", "evt": …, "data": …}` with NO nonce —
which is the one distinction the read loop actually needs to make.

── EVERYTHING IS ASYNC, AND IT HAS TO BE ─────────────────────────────────────
There is exactly one read loop, and no code path below it ever blocks on a reply.
This is not stylistic. The first version of this file had a blocking `command()` used
by both the setup path and, indirectly, by the event handlers — `VOICE_CHANNEL_SELECT`
→ re-read the channel → blocking recv. By then the socket is non-blocking, so the
first recv raises `BlockingIOError` and the helper dies. Joining a voice call, the
single most important event this thing handles, would have killed it every time.

So: replies are correlated by nonce through `self.pending` and dispatched to callbacks
(`request`). The only blocking-ish helper, `call()`, pumps the real loop rather than
reading the socket behind its back, and is used ONLY during setup — before the steady
loop starts, where re-entering the pump is impossible. Anything reachable from
`on_event` must use `request`.

── What Discord will and won't let you do ────────────────────────────────────
Available and used here: mute, deafen, input/output volume, per-user volume, leaving
the call, the participant list, who is speaking, connection state and ping.

NOT AVAILABLE, at all: screen share and camera. There is no RPC command for either —
they are simply absent from the surface, not gated behind a scope. The shell drives
those two by focusing Discord and injecting a keystroke instead; that lives in QML,
deliberately not in here, so this file stays a pure RPC client.

── Scopes ────────────────────────────────────────────────────────────────────
`rpc`, `rpc.voice.read` and `rpc.voice.write` are whitelist-gated for public apps, but
an application's OWNER can always authorize their own app. That's why the setup asks
you to make your own Discord application rather than shipping a client id here: the
alternative is embedding someone else's credentials, which breaks the moment they're
rotated and was never ours to use.

── Secrets ───────────────────────────────────────────────────────────────────
The client secret and the access token NEVER go to stdout. Stdout is read by the shell
and is trivially observable; diagnostics that might carry a token go nowhere at all.
"""

import sys, os, json, struct, socket, selectors, time, uuid
import sys as _sys; _sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qspaths   # where secret files live (outside the repo)

import secretstore       # the client secret may live in the system keyring (see its header)
import urllib.request, urllib.parse, urllib.error

# ── Protocol constants ────────────────────────────────────────────────────────
OP_HANDSHAKE, OP_FRAME, OP_CLOSE, OP_PING, OP_PONG = 0, 1, 2, 3, 4

SCOPES = ["rpc", "rpc.voice.read", "rpc.voice.write"]
TOKEN_URL = "https://discord.com/api/oauth2/token"

# Zero-setup identity. rpc.* scopes are whitelist-gated (an app's owner + <=50 testers),
# so nobody else can use this repo author's client id. Discord's own StreamKit overlay is
# approved, and its code-for-token proxy holds the secret server-side (the route
# trigg/Discover uses, with only the plain `rpc` scope). With no clientId/clientSecret
# configured we authenticate as StreamKit. Borrowed, UNDOCUMENTED, a terms-of-service
# grey area: your own app in discord-rpc.json always wins; "sharedApp": false disables it.
# NOT verified live: that mute/deafen/per-user volume work with the plain `rpc` scope.
SHARED_CLIENT_ID = "207646673902501888"
SHARED_TOKEN_URL = "https://streamkit.discord.com/overlay/token"
SHARED_SCOPES = ["rpc"]

# Cloudflare fronts Discord's API and 403s urllib's default agent. See exchange_token.
USER_AGENT = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
              "(KHTML, like Gecko) Chrome/120.0 Safari/537.36")

# How long to wait for each setup stage.
#
# ── HANDSHAKE_TIMEOUT is generous ON PURPOSE ─────────────────────────────────
# Discord does NOT service a new IPC client promptly when others are already
# connected — it queues them. Measured on this machine with VS Code's Rich Presence
# extension holding a connection: READY arrived 13.1 SECONDS after the handshake was
# sent, and a client that gave up at 5s never connected at all. It looked exactly like
# a bad client_id or a broken config, and it was neither.
#
# Connecting to the unix socket itself is instant, so that keeps a short timeout; it's
# only the protocol handshake that has to be patient.
CONNECT_TIMEOUT   = 5
HANDSHAKE_TIMEOUT = 45
COMMAND_TIMEOUT   = 30
AUTHORIZE_TIMEOUT = 180

# Steady-state loop tick. Doubles as the coalescing window for snapshots: speaking
# events arrive in bursts, and this caps stdout at ~20 lines/sec however chatty the
# call gets.
TICK = 0.05

# Backoff between reconnect attempts when Discord isn't running. Capped, so a Discord
# that's been shut all day is still noticed within seconds of coming back.
RECONNECT_MIN, RECONNECT_MAX = 1.0, 8.0

# How often to re-check for a credentials file that doesn't exist yet. One stat call,
# and it's what lets writing the file take effect without reloading the shell.
SETUP_POLL = 3.0

CONFIG_PATH = qspaths.secret_file("discord-rpc.json")   # outside the repo: qspaths.py
TOKEN_PATH = os.path.join(
    os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
    "quicktest", "discord-token.json",
)


class StdinClosed(Exception):
    """The shell went away. Unwinds the pump from wherever it happens to be."""


def emit(obj):
    """One JSON object, one line, flushed. The shell's entire view of this process."""
    sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def log(msg):
    """Diagnostics to stderr, which lands in the shell's log and never in a binding."""
    sys.stderr.write("discord-rpc: %s\n" % msg)
    sys.stderr.flush()


def stdin_pollable():
    """Can stdin go in an epoll set?

    Under the shell it's a pipe and the answer is yes. Run by hand with `< /dev/null`
    (or with stdin on a regular file) it is NOT — epoll rejects both with EPERM, which
    crashed this helper on startup rather than doing the obvious thing. Determined once,
    by asking, because the failure is a permission error rather than anything you can
    infer from the fd.
    """
    try:
        sel = selectors.DefaultSelector()
        sel.register(sys.stdin, selectors.EVENT_READ)
        sel.close()
        return True
    except (OSError, ValueError):
        return False


STDIN_POLLABLE = stdin_pollable()


def wait_stdin(seconds):
    """Sleep, but keep watching stdin. Raises StdinClosed when the shell goes away.

    A plain `time.sleep` anywhere outside the main loop is how you get an orphan: while
    waiting — for a reconnect backoff, or for credentials to appear — nothing else is
    watching stdin, so the process outlives the shell that started it and spins forever.
    """
    if not STDIN_POLLABLE:
        # Unpollable stdin: read once instead. /dev/null answers EOF immediately, which
        # is exactly right — nothing is driving us, so stop.
        if not os.read(sys.stdin.fileno(), 65536):
            raise StdinClosed()
        time.sleep(seconds)
        return

    sel = selectors.DefaultSelector()
    sel.register(sys.stdin, selectors.EVENT_READ)
    try:
        deadline = time.monotonic() + seconds
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return
            if sel.select(timeout=remaining):
                if not os.read(sys.stdin.fileno(), 65536):
                    raise StdinClosed()
                # Commands arriving while disconnected are dropped: there is nothing to
                # send them to, and replaying them later would apply stale intent to a
                # fresh session.
    finally:
        sel.close()


# ── Socket discovery ──────────────────────────────────────────────────────────
# Discord numbers its sockets: the first instance takes -0, a second takes -1, and so
# on. Flatpak and Snap builds bury theirs a level down, and those paths cost nothing
# to check on a system that has neither.
def candidate_paths():
    base = (os.environ.get("XDG_RUNTIME_DIR")
            or os.environ.get("TMPDIR")
            or "/tmp").rstrip("/")
    prefixes = [base,
                base + "/app/com.discordapp.Discord",
                base + "/app/com.discordapp.DiscordCanary",
                base + "/snap.discord"]
    return ["%s/discord-ipc-%d" % (p, i) for p in prefixes for i in range(10)]


def avatar_url(user):
    """A CDN URL an Image can point at, including for users with no avatar set."""
    uid = str(user.get("id") or "")
    av  = user.get("avatar")
    if av:
        ext = "gif" if str(av).startswith("a_") else "png"
        return "https://cdn.discordapp.com/avatars/%s/%s.%s?size=64" % (uid, av, ext)

    # Default avatars: the modern (pomelo) scheme keys off the snowflake, the legacy
    # one off the 4-digit discriminator. Users of both kinds are still around.
    disc = str(user.get("discriminator") or "0")
    try:
        idx = (int(uid) >> 22) % 6 if disc in ("0", "") else int(disc) % 5
    except (ValueError, TypeError):
        idx = 0
    return "https://cdn.discordapp.com/embed/avatars/%d.png" % idx


def display_name(entry):
    """Server nickname, then global display name, then username. Discord's own order."""
    user = entry.get("user") or {}
    return (entry.get("nick")
            or user.get("global_name")
            or user.get("username")
            or "Unknown")


# What the shell may set on Discord's voice settings, and nothing else.
PROCESSING = {"noise": "noise_suppression", "echo": "echo_cancellation",
              "agc": "automatic_gain_control"}
INPUT_MODES = ("VOICE_ACTIVITY", "PUSH_TO_TALK")


def devices(raw):
    """Discord's available_devices → [{id, name}], dropping anything malformed."""
    out = []
    for d in raw or []:
        if isinstance(d, dict) and d.get("id") is not None:
            out.append({"id": str(d["id"]), "name": str(d.get("name") or d["id"])})
    return out


def pan(raw):
    """Discord's {left, right} gains (0..1 each) → one balance, -1 … 1."""
    if not isinstance(raw, dict):
        return 0.0
    try:
        left, right = float(raw.get("left", 1)), float(raw.get("right", 1))
    except (TypeError, ValueError):
        return 0.0
    return round(max(-1.0, min(1.0, right - left)), 3)


class Client:
    # Per-channel events must be subscribed WITH the channel id and unsubscribed when
    # you leave — they do not follow you, and leaving them behind accumulates dead
    # subscriptions across a session of hopping between channels.
    CHANNEL_EVENTS = ("VOICE_STATE_CREATE", "VOICE_STATE_UPDATE", "VOICE_STATE_DELETE",
                      "SPEAKING_START", "SPEAKING_STOP")

    def __init__(self, config):
        self.config = config
        self.sock = None
        self.sel = None
        self.buf = b""            # partial frame bytes
        self.stdin_buf = ""       # partial command line
        self.pending = {}         # nonce → callback(data, err)
        self.last_line = None     # last snapshot emitted, for deduplication
        self.last_error = None
        self.reset_state()

    def reset_state(self):
        """Everything a snapshot is built from. Cleared per connection — a reconnect
        must never present a stale call as current."""
        self.authed = False
        self.ready = False
        # Your own account id, out of the READY payload. Needed because Discord puts YOU
        # in your own voice_states like anyone else, and reports your volume as 0 (you
        # don't hear yourself) — which reads as "muted to 0%" unless you know which row
        # is you.
        self.me = ""
        self.channel = None          # {id, name, guild, guildId}
        self.guild_names = {}        # guild_id → name, resolved once each
        self.users = {}              # user_id → participant dict
        self.speaking = set()        # user_ids currently transmitting
        self.mute = False
        self.deaf = False
        self.input_volume = 100
        self.output_volume = 100
        # The rest of Discord's Voice & Video page that RPC reaches: processing
        # switches, the input mode, and which devices (with the lists to pick from).
        self.processing = {"noise": False, "echo": False, "agc": False}
        self.input_mode = "VOICE_ACTIVITY"
        self.input_device, self.output_device = "", ""
        self.input_devices, self.output_devices = [], []
        self.status = "DISCONNECTED"
        self.ping = 0
        self.subscribed_channel = None
        self.dirty = True

    # ── Framing ───────────────────────────────────────────────────────────────
    def send(self, op, payload):
        body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.sock.sendall(struct.pack("<II", op, len(body)) + body)

    def request(self, cmd, args=None, cb=None, evt=None):
        """Fire a command. `cb(data, err)` runs when its reply lands, if given.

        This is the ONLY way to talk to Discord from anywhere reachable by an event.
        """
        nonce = str(uuid.uuid4())
        payload = {"cmd": cmd, "args": args or {}, "nonce": nonce}
        if evt:
            payload["evt"] = evt
        if cb:
            self.pending[nonce] = cb
        self.send(OP_FRAME, payload)

    def call(self, cmd, args=None, timeout=COMMAND_TIMEOUT):
        """Send a command and pump the real loop until its reply lands.

        SETUP ONLY. Calling this from inside `on_event` would re-enter the pump and
        process events out of order — see the header. Everything in the steady state
        uses `request` with a callback instead.
        """
        box = {}
        self.request(cmd, args, lambda data, err: box.update(data=data, err=err))
        self.wait_for(lambda: bool(box), timeout, cmd)
        if box["err"]:
            raise RuntimeError("%s: %s" % (cmd, box["err"]))
        return box["data"] or {}

    def wait_for(self, pred, timeout, what):
        deadline = time.monotonic() + timeout
        while not pred():
            if time.monotonic() >= deadline:
                raise TimeoutError("%s timed out" % what)
            self.pump(TICK)

    # ── The one read loop ─────────────────────────────────────────────────────
    def pump(self, timeout):
        for key, _ in self.sel.select(timeout=timeout):
            if key.data == "sock":
                self.pump_socket()
            else:
                self.pump_stdin()

    def pump_socket(self):
        """Drain whatever's readable, dispatching every COMPLETE frame in it.

        The socket hands over arbitrary byte counts — a frame can arrive split across
        two reads, and two frames can arrive in one. Buffer, then parse only what's
        whole.
        """
        chunk = self.sock.recv(65536)
        if not chunk:
            raise ConnectionError("Discord closed the socket")
        self.buf += chunk

        while len(self.buf) >= 8:
            op, length = struct.unpack("<II", self.buf[:8])
            if len(self.buf) < 8 + length:
                break
            payload, self.buf = self.buf[8:8 + length], self.buf[8 + length:]
            msg = json.loads(payload.decode("utf-8")) if length else {}

            if op == OP_PING:
                self.send(OP_PONG, msg)
                continue
            if op == OP_CLOSE:
                raise ConnectionError("Discord sent CLOSE: %s"
                                      % (msg.get("message") or msg))

            nonce = msg.get("nonce")
            cb = self.pending.pop(nonce, None) if nonce else None
            if cb:
                if msg.get("evt") == "ERROR":
                    cb(None, (msg.get("data") or {}).get("message", "unknown error"))
                else:
                    cb(msg.get("data") or {}, None)
            elif msg.get("cmd") == "DISPATCH":
                self.on_event(msg)

    def pump_stdin(self):
        data = os.read(sys.stdin.fileno(), 65536)
        if not data:
            raise StdinClosed()
        self.stdin_buf += data.decode("utf-8", "replace")
        while "\n" in self.stdin_buf:
            line, self.stdin_buf = self.stdin_buf.split("\n", 1)
            if line.strip():
                self.handle_command(line)

    # ── Connect + authenticate ────────────────────────────────────────────────
    def connect(self):
        last = None
        for path in candidate_paths():
            if not os.path.exists(path):
                continue
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.settimeout(CONNECT_TIMEOUT)
                s.connect(path)
                s.setblocking(False)
                self.sock, self.buf, self.pending = s, b"", {}

                self.sel = selectors.DefaultSelector()
                self.sel.register(s, selectors.EVENT_READ, "sock")
                # Skipped when stdin can't be polled — see stdin_pollable(). Commands
                # are then unreachable, which is correct for the cases that hit it:
                # nothing is on the other end to send any.
                if STDIN_POLLABLE:
                    self.sel.register(sys.stdin, selectors.EVENT_READ, "stdin")
                return path
            except OSError as e:
                last = e
        raise ConnectionError("no Discord IPC socket (%s)" % (last or "none found"))

    def close(self):
        if self.sel:
            self.sel.close()
            self.sel = None
        if self.sock:
            try:
                self.sock.close()
            except OSError:
                pass
            self.sock = None

    def handshake(self):
        self.send(OP_HANDSHAKE, {"v": 1, "client_id": self.config["clientId"]})
        self.wait_for(lambda: self.ready, HANDSHAKE_TIMEOUT, "handshake")

    def authenticate(self):
        """Reach an authenticated session, minting or refreshing a token as needed."""
        tok = load_token(self.config["clientId"])

        if tok and tok.get("access_token"):
            if tok.get("expires_at", 0) > time.time() + 60:
                try:
                    self.call("AUTHENTICATE", {"access_token": tok["access_token"]})
                    self.authed = True
                    return
                except (RuntimeError, TimeoutError) as e:
                    log("cached token rejected (%s); re-authorizing" % e)
            elif tok.get("refresh_token"):
                # Refresh silently rather than making the user click again. Discord's
                # tokens last a week; without this you'd get a consent dialog every
                # seventh time the shell restarted.
                new = exchange_token(self.config, refresh_token=tok["refresh_token"])
                if new:
                    new["client_id"] = self.config["clientId"]
                    save_token(new)
                    self.call("AUTHENTICATE", {"access_token": new["access_token"]})
                    self.authed = True
                    return
                log("refresh failed; re-authorizing")

        # Nothing usable cached — ask the user. This waits on a human.
        emit({"t": "auth", "stage": "awaiting-consent"})
        try:
            data = self.call("AUTHORIZE",
                             {"client_id": self.config["clientId"],
                              "scopes": SHARED_SCOPES if self.config.get("shared") else SCOPES},
                             timeout=AUTHORIZE_TIMEOUT)
        except RuntimeError as e:
            # ── The one failure that looks like a bug and isn't ───────────────
            # Using SOMEONE ELSE'S clientId fails here, and Discord's own message
            # ("Invalid scope", "Oauth2 application does not..." — it varies) says
            # nothing about why. The rpc.* scopes are whitelist-gated: an app's OWNER
            # can always authorize it, anyone else cannot. So a config copied from
            # another person's dotfiles gets rejected at exactly this line, forever,
            # with an error that reads like the shell is broken.
            #
            # Rewritten only for the rejection cases — a timeout means the consent
            # dialog is still sitting there unanswered, which is a different problem
            # with a different fix, and must keep its own message.
            if self.config.get("shared"):
                raise RuntimeError("%s — the shared StreamKit sign-in was refused; Discord "
                                   "may have changed it. Set up your own application." % e)
            raise RuntimeError(
                "%s — if you copied discord-rpc.json from someone else, that's why: "
                "Discord only lets an application's OWNER grant it rpc scopes. "
                "Make your own app at discord.com/developers/applications and use its "
                "clientId and clientSecret." % e)

        new = exchange_token(self.config, code=data.get("code"))
        if not new:
            raise RuntimeError("token exchange failed — check clientSecret, and that "
                               "redirectUri is registered on the application")
        new["client_id"] = self.config["clientId"]
        save_token(new)
        self.call("AUTHENTICATE", {"access_token": new["access_token"]})
        self.authed = True
        emit({"t": "auth", "stage": ""})

    # ── Subscriptions ─────────────────────────────────────────────────────────
    def subscribe_global(self):
        for evt in ("VOICE_SETTINGS_UPDATE", "VOICE_CHANNEL_SELECT",
                    "VOICE_CONNECTION_STATUS"):
            self.request("SUBSCRIBE", {}, evt=evt)

    def set_channel_subscriptions(self, channel_id):
        if self.subscribed_channel == channel_id:
            return
        for cmd, cid in (("UNSUBSCRIBE", self.subscribed_channel),
                         ("SUBSCRIBE", channel_id)):
            if not cid:
                continue
            for evt in self.CHANNEL_EVENTS:
                self.request(cmd, {"channel_id": cid}, evt=evt)
        self.subscribed_channel = channel_id

    # ── State ─────────────────────────────────────────────────────────────────
    def apply_voice_settings(self, d):
        if not d:
            return
        self.mute = bool(d.get("mute", self.mute))
        self.deaf = bool(d.get("deaf", self.deaf))
        inp, out = d.get("input") or {}, d.get("output") or {}
        if "volume" in inp:
            self.input_volume = int(round(inp["volume"]))
        if "volume" in out:
            self.output_volume = int(round(out["volume"]))
        for key, field in (("noise", "noise_suppression"), ("echo", "echo_cancellation"),
                           ("agc", "automatic_gain_control")):
            if field in d:
                self.processing[key] = bool(d[field])
        mode = (d.get("mode") or {}).get("type")
        if mode in INPUT_MODES:
            self.input_mode = mode
        if "device_id" in inp:
            self.input_device = str(inp["device_id"] or "")
        if "device_id" in out:
            self.output_device = str(out["device_id"] or "")
        if "available_devices" in inp:
            self.input_devices = devices(inp["available_devices"])
        if "available_devices" in out:
            self.output_devices = devices(out["available_devices"])
        self.dirty = True

    def apply_voice_state(self, entry, removed=False):
        user = entry.get("user") or {}
        uid = str(user.get("id") or "")
        if not uid:
            return
        if removed:
            self.users.pop(uid, None)
            self.speaking.discard(uid)
        else:
            vs = entry.get("voice_state") or {}
            self.users[uid] = {
                "id": uid,
                "isSelf": uid == self.me,
                "name": display_name(entry),
                "avatar": avatar_url(user),
                "mute": bool(entry.get("mute")),        # muted BY you, locally
                "selfMute": bool(vs.get("self_mute")),
                "selfDeaf": bool(vs.get("self_deaf")),
                "serverMute": bool(vs.get("mute")),
                "serverDeaf": bool(vs.get("deaf")),
                "volume": int(round(entry.get("volume", 100))),
                "pan": pan(entry.get("pan")),
                "bot": bool(user.get("bot")),
            }
        self.dirty = True

    def on_user_settings(self, uid, data, err):
        """SET_USER_VOICE_SETTINGS' reply: { user_id, volume, mute, pan }."""
        if err:
            self.emit_error("Couldn't change that person's settings: %s" % err)
            return
        user = self.users.get(uid)
        if user is None:
            return
        if "volume" in data:
            user["volume"] = int(round(data["volume"]))
        if "mute" in data:
            user["mute"] = bool(data["mute"])
        if "pan" in data:
            user["pan"] = pan(data["pan"])
        self.dirty = True

    def resolve_guild(self, guild_id):
        """Fill in the server name, asynchronously. The channel payload carries only
        an id, and a failure here is cosmetic — the card just shows the channel."""
        if not guild_id or guild_id in self.guild_names:
            return
        self.guild_names[guild_id] = ""     # claim it, so we ask exactly once

        def done(data, err):
            if err or not data:
                log("guild lookup failed: %s" % (err or "no data"))
                return
            self.guild_names[guild_id] = data.get("name") or ""
            if self.channel and self.channel.get("guildId") == guild_id:
                self.channel["guild"] = self.guild_names[guild_id]
                self.dirty = True

        self.request("GET_GUILD", {"guild_id": guild_id}, done)

    def refresh_channel(self):
        """Re-read the selected voice channel and rebuild the participant list."""
        def done(data, err):
            if err:
                log("channel read failed: %s" % err)
                return
            self.set_channel(data)

        self.request("GET_SELECTED_VOICE_CHANNEL", {}, done)

    def set_channel(self, data):
        if not data:
            self.channel = None
            self.users = {}
            self.speaking.clear()
            self.status = "DISCONNECTED"
            self.ping = 0
            self.set_channel_subscriptions(None)
            self.dirty = True
            return

        cid, gid = str(data.get("id")), data.get("guild_id")
        self.channel = {
            "id": cid,
            "name": data.get("name") or "",
            "guildId": gid,
            "guild": self.guild_names.get(gid, ""),
        }
        self.resolve_guild(gid)

        self.users = {}
        self.speaking.clear()
        for entry in (data.get("voice_states") or []):
            self.apply_voice_state(entry)

        self.set_channel_subscriptions(cid)
        self.dirty = True

    def on_event(self, msg):
        evt, data = msg.get("evt"), (msg.get("data") or {})

        if evt == "READY":
            self.ready = True
            self.me = str((data.get("user") or {}).get("id") or "")

        elif evt == "VOICE_SETTINGS_UPDATE":
            self.apply_voice_settings(data)

        elif evt == "VOICE_CHANNEL_SELECT":
            # Fires on join AND leave (channel_id null on leave). Either way the
            # participant list is now wrong, so re-read rather than patch.
            self.refresh_channel()

        elif evt in ("VOICE_STATE_CREATE", "VOICE_STATE_UPDATE"):
            self.apply_voice_state(data)

        elif evt == "VOICE_STATE_DELETE":
            self.apply_voice_state(data, removed=True)

        elif evt in ("SPEAKING_START", "SPEAKING_STOP"):
            uid = str(data.get("user_id") or "")
            if uid:
                (self.speaking.add if evt == "SPEAKING_START"
                 else self.speaking.discard)(uid)
                self.dirty = True

        elif evt == "VOICE_CONNECTION_STATUS":
            self.status = data.get("state") or self.status
            avg = data.get("average_ping")
            if avg is not None:
                self.ping = int(round(avg))
            self.dirty = True

    def snapshot(self):
        users = []
        for u in self.users.values():
            row = dict(u)
            row["speaking"] = u["id"] in self.speaking
            users.append(row)
        # Name order, with yourself winning any tie — two accounts really can share a
        # display name, and an unstable order between them would make the list jitter.
        users.sort(key=lambda r: (r["name"].lower(), not r["isSelf"]))

        return {
            "t": "state",
            "connected": self.authed,
            "inCall": self.channel is not None,
            "channel": self.channel,
            "mute": self.mute,
            "deaf": self.deaf,
            "inputVolume": self.input_volume,
            "outputVolume": self.output_volume,
            "processing": self.processing,
            "inputMode": self.input_mode,
            "inputDevice": self.input_device,
            "outputDevice": self.output_device,
            "inputDevices": self.input_devices,
            "outputDevices": self.output_devices,
            "status": self.status,
            "ping": self.ping,
            "users": users,
        }

    def emit_snapshot(self):
        """Emit, but only if anything actually changed.

        Without this, a Discord that stays shut re-emits an identical "disconnected"
        line on every reconnect attempt, and each one costs the shell a fresh `users`
        array — which is exactly the reassignment the snapshot compare upstairs exists
        to avoid. Deduplicating at the source is cheaper than deduplicating twice.
        """
        line = json.dumps(self.snapshot(), separators=(",", ":"))
        if line == self.last_line:
            return
        self.last_line = line
        sys.stdout.write(line + "\n")
        sys.stdout.flush()

    def emit_error(self, msg):
        """Same idea: a failing reconnect loop should say so once, not every second."""
        if msg == self.last_error:
            return
        self.last_error = msg
        emit({"t": "error", "msg": msg})

    # ── Commands from the shell ───────────────────────────────────────────────
    def handle_command(self, line):
        try:
            cmd = json.loads(line)
        except ValueError:
            return
        if not self.authed:
            return

        c, v = cmd.get("c"), cmd.get("v")
        try:
            if c == "mute":
                self.request("SET_VOICE_SETTINGS", {"mute": bool(v)})
            elif c == "deaf":
                self.request("SET_VOICE_SETTINGS", {"deaf": bool(v)})
            elif c == "inputVolume":
                self.request("SET_VOICE_SETTINGS",
                             {"input": {"volume": max(0.0, min(100.0, float(v)))}})
            elif c == "outputVolume":
                self.request("SET_VOICE_SETTINGS",
                             {"output": {"volume": max(0.0, min(200.0, float(v)))}})
            elif c == "processing":
                field = PROCESSING.get(cmd.get("key"))
                if field:
                    self.request("SET_VOICE_SETTINGS", {field: bool(v)})
            elif c == "inputMode":
                if v in INPUT_MODES:
                    self.request("SET_VOICE_SETTINGS", {"mode": {"type": v}})
            elif c in ("inputDevice", "outputDevice"):
                # Only an id Discord itself listed: the shell's word is not enough.
                side, known = (("input", self.input_devices) if c == "inputDevice"
                               else ("output", self.output_devices))
                if any(d["id"] == v for d in known):
                    self.request("SET_VOICE_SETTINGS", {side: {"device_id": v}})
            elif c == "userPan":
                # Balance, -1 (left) … 1 (right), as Discord's pair of gains: the far
                # side fades, the near side stays whole.
                uid, b = str(cmd.get("id") or ""), max(-1.0, min(1.0, float(v)))
                if uid:
                    self.request("SET_USER_VOICE_SETTINGS",
                                 {"user_id": uid, "pan": {"left": round(min(1.0, 1.0 - b), 3),
                                                          "right": round(min(1.0, 1.0 + b), 3)}},
                                 cb=lambda d, err, uid=uid: self.on_user_settings(uid, d, err))
            elif c in ("userVolume", "userMute"):
                # Someone else's volume or mute, FOR YOU only (Discord's own "User
                # Volume" / "Mute" on a person). The reply carries what Discord kept,
                # and no event follows it, so the reply is what updates the list.
                uid = str(cmd.get("id") or "")
                if uid:
                    args = {"user_id": uid}
                    if c == "userVolume":
                        args["volume"] = max(0, min(200, int(v)))
                    else:
                        args["mute"] = bool(v)
                    self.request("SET_USER_VOICE_SETTINGS", args,
                                 cb=lambda d, err, uid=uid: self.on_user_settings(uid, d, err))
            elif c == "disconnect":
                # `force` skips the confirmation Discord shows while you're streaming.
                self.request("SELECT_VOICE_CHANNEL",
                             {"channel_id": None, "force": True})
            elif c == "refresh":
                self.refresh_channel()
        except (TypeError, ValueError) as e:
            log("bad command %r: %s" % (line[:80], e))

    # ── Steady state ──────────────────────────────────────────────────────────
    def run(self):
        """Pump until the connection drops or the shell goes away."""
        while True:
            self.pump(TICK)
            # Coalesced: many events in one tick produce exactly one line out.
            if self.dirty:
                self.dirty = False
                self.emit_snapshot()


# ── Token storage ─────────────────────────────────────────────────────────────
def load_token(client_id):
    """The cached token, only if minted for THIS client id (shared vs your own app).
    An unstamped token predates this and is tried; a rejection re-authorizes."""
    try:
        with open(TOKEN_PATH, "r", encoding="utf-8") as f:
            tok = json.load(f)
    except (OSError, ValueError):
        return None
    if not isinstance(tok, dict) or tok.get("client_id", client_id) != client_id:
        return None
    return tok


def save_token(tok):
    """0600, and CREATED 0600 — not chmod'd afterwards.

    Writing the file and then tightening it leaves a window where the token is
    world-readable, which for a credential is the whole ballgame. `os.open` with the
    mode up front has no such window.
    """
    os.makedirs(os.path.dirname(TOKEN_PATH), exist_ok=True)
    tmp = TOKEN_PATH + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(tok, f)
    os.replace(tmp, TOKEN_PATH)


def exchange_token(config, code=None, refresh_token=None):
    """Swap an authorization code (or a refresh token) for an access token.

    Returns the token dict with an absolute `expires_at`, or None. Errors are logged
    WITHOUT their response body: a failed token exchange can echo the request back,
    and the request contains the client secret.
    """
    if config.get("shared"):
        return exchange_shared(code)
    form = {"client_id": config["clientId"], "client_secret": config["clientSecret"]}
    if refresh_token:
        form.update({"grant_type": "refresh_token", "refresh_token": refresh_token})
    else:
        form.update({"grant_type": "authorization_code", "code": code,
                     "redirect_uri": config.get("redirectUri", "http://localhost")})

    # ── The User-Agent is REQUIRED ────────────────────────────────────────────
    # Discord's API sits behind Cloudflare, which answers urllib's default
    # `Python-urllib/3.x` with a flat 403 — before Discord ever sees the request. It
    # looks exactly like a rejected client secret, which is a maddening thing to debug
    # because the credentials are fine. scripts/lyrics.py carries a UA for the same
    # reason; this is the same trap, one API over.
    req = urllib.request.Request(
        TOKEN_URL,
        data=urllib.parse.urlencode(form).encode(),
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "User-Agent": USER_AGENT,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            tok = json.load(r)
    except urllib.error.HTTPError as e:
        # The RESPONSE body is safe to show — the secret travels in the request, not
        # back. Discord's is a small JSON like {"error": "invalid_client"}, which is
        # the difference between "wrong secret" and "unregistered redirect URI".
        detail = ""
        try:
            detail = " — " + e.read().decode("utf-8", "replace")[:200].strip()
        except Exception:
            pass
        log("token exchange rejected: HTTP %s%s" % (e.code, detail))
        return None
    except (urllib.error.URLError, ValueError, OSError) as e:
        log("token exchange failed: %s" % type(e).__name__)
        return None

    if not tok.get("access_token"):
        return None
    tok["expires_at"] = time.time() + int(tok.get("expires_in", 604800))
    return tok


def exchange_shared(code):
    """StreamKit's proxy: POST {"code"} -> {"access_token"}. No secret, no refresh token
    (a refresh arrives as code=None and falls through to a fresh AUTHORIZE)."""
    if not code:
        return None
    req = urllib.request.Request(
        SHARED_TOKEN_URL, data=json.dumps({"code": code}).encode(),
        headers={"Content-Type": "application/json", "User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            tok = json.load(r)
    except urllib.error.HTTPError as e:
        log("shared token exchange rejected: HTTP %s" % e.code)
        return None
    except (urllib.error.URLError, ValueError, OSError) as e:
        log("shared token exchange failed: %s" % type(e).__name__)
        return None
    if not isinstance(tok, dict) or not tok.get("access_token"):
        return None
    tok["expires_at"] = time.time() + int(tok.get("expires_in", 604800))
    return tok


# ── Which Discord are you running? ────────────────────────────────────────────
# The RPC socket is the same for all of them — every client in this list writes
# `discord-ipc-0`, which is why the panel itself is client-agnostic and needed no list
# until now. But KEYSTROKE INJECTION has to find and focus a window, and that means
# matching a window class, and there the clients diverge completely.
#
# Matched as a PREFIX, case-insensitively, so `discord` alone also covers Canary
# (`discordcanary`), PTB (`discordptb`) and development builds without listing them.
#
# ── This list is a starting point, not an authority ──────────────────────────
# Only `discord` is confirmed on this machine (`hyprctl clients` → class "discord").
# The rest are the classes these forks are *expected* to set and are unverified here —
# which is exactly why the list is CONFIGURABLE. If your client isn't recognised, run
# `hyprctl clients -j | grep class`, add the value to `windowClasses` in
# discord-rpc.json, and nothing needs recompiling or reloading beyond the helper.
DEFAULT_WINDOW_CLASSES = [
    "discord",     # official, and by prefix: discordcanary / discordptb / development
    "vesktop",     # by far the most common on Wayland
    "webcord",
    "legcord",     # ArmCord's successor
    "armcord",
    "dorion",
]


def window_classes(cfg):
    """The configured client list, falling back to the defaults.

    Anything non-string or empty is dropped rather than passed on: these end up in an
    argv entry for discord-press.py, and a null in the middle of that list would take
    out injection for every client, not just the malformed one.
    """
    raw = cfg.get("windowClasses")
    if not isinstance(raw, list):
        return DEFAULT_WINDOW_CLASSES
    out = [c.strip().lower() for c in raw if isinstance(c, str) and c.strip()]
    return out or DEFAULT_WINDOW_CLASSES


def load_config():
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            cfg = json.load(f)
    except OSError:
        cfg = {}          # no file at all is the zero-setup case
    except ValueError:
        return None       # unparseable: left for the user to fix
    if not isinstance(cfg, dict):
        return None
    secret = secretstore.resolve(cfg, "clientSecret", "discord-client-secret")
    if cfg.get("clientId") and secret:
        return dict(cfg, clientSecret=secret)
    if cfg.get("sharedApp") is False:
        return None
    return dict(cfg, clientId=SHARED_CLIENT_ID, shared=True)


IDLE_STATE = {"t": "state", "connected": False, "inCall": False, "channel": None,
              "mute": False, "deaf": False, "inputVolume": 100, "outputVolume": 100,
              "status": "DISCONNECTED", "ping": 0, "users": []}


# ── Entry point ───────────────────────────────────────────────────────────────
def main():
    # ── Wait for credentials, rather than giving up on them ───────────────────
    # A missing config is a SETUP state, not an error — the shell renders it as "not
    # connected yet" rather than as a fault. This used to block on stdin forever, which
    # meant writing the credentials file appeared to do nothing until the shell was
    # reloaded: the most confusing possible moment to demand a reload, because you've
    # just done the one thing you were told to do.
    #
    # Announced ONCE, then re-checked quietly. The poll is every few seconds against a
    # single stat — this is a state a machine can sit in for weeks.
    config = load_config()
    if not config:
        emit({"t": "auth", "stage": "no-credentials"})
        emit(IDLE_STATE)
        while not config:
            try:
                wait_stdin(SETUP_POLL)
            except (KeyboardInterrupt, StdinClosed):
                return
            config = load_config()
        emit({"t": "auth", "stage": ""})

    # The keybinds for screen share / camera live in the same file as the credentials,
    # because they're all "how this machine talks to Discord". They're forwarded to the
    # shell from HERE rather than having QML read that file itself — so the client
    # secret never enters the QML layer, where it would sit in an inspectable property.
    #
    # `windowClasses` rides along for the same reason. It's how the shell recognises
    # WHICH Discord you run — see DEFAULT_WINDOW_CLASSES.
    emit({"t": "config",
          "keys": config.get("keys") or {},
          "windowClasses": window_classes(config)})

    backoff = RECONNECT_MIN
    client = Client(config)

    while True:
        try:
            path = client.connect()
            log("connected on %s" % os.path.basename(path))
            client.reset_state()

            client.handshake()
            client.authenticate()
            client.subscribe_global()

            # Both async: the first snapshot may go out before they land, and a
            # second follows when they do. That's the contract the shell is built
            # for, and it keeps the setup path off the blocking `call()`.
            client.request("GET_VOICE_SETTINGS", {},
                           lambda d, e: client.apply_voice_settings(d))
            client.refresh_channel()

            client.last_error = None
            client.emit_snapshot()
            backoff = RECONNECT_MIN
            client.run()

        except (KeyboardInterrupt, StdinClosed):
            client.close()
            return
        except (ConnectionError, TimeoutError, OSError, RuntimeError,
                ValueError, struct.error) as e:
            log("%s: %s" % (type(e).__name__, e))
            client.emit_error(str(e))

        client.close()

        # Disconnected. Say so, then wait — Discord being shut is entirely normal,
        # and the card must stop claiming you're in a call the moment it happens.
        client.reset_state()
        client.authed = False
        client.emit_snapshot()

        try:
            wait_stdin(backoff)
        except (KeyboardInterrupt, StdinClosed):
            return
        backoff = min(RECONNECT_MAX, backoff * 2)


if __name__ == "__main__":
    main()
