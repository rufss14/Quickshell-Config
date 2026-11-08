#!/usr/bin/env python3
"""Show the Counter-Strike 2 match you're in as Discord Rich Presence.

    python3 cs2-presence.py

Reads commands on stdin, writes state snapshots on stdout, one JSON object per line.
Runs forever; a Discord that isn't running (or quits) is a state, not a failure — the
same contract as claude-presence.py, which this file is closely modelled on.

── Why this exists at all ───────────────────────────────────────────────────
Discord's built-in game detection cannot show CS2 on Linux. Its detectables database
(cdn.discordapp.com/detectables/games-v1.json) lists only `win64/cs2.exe` for
"Counter-Strike 2" — there is no Linux executable entry, unlike CS:GO's
`csgo_linux64`. So a native-Linux `cs2` process never matches, and Discord falls back
to the bare process name "cs2" with no art and no detail. CS2 itself ships no Discord
rich presence. This daemon fills both gaps.

── Where the match data comes from: Game State Integration ───────────────────
CS2 (and CS:GO) will POST a JSON snapshot of game state to a local HTTP endpoint on a
regular tick whenever a `gamestate_integration_*.cfg` file is present in the game's
cfg directory — scripts/install-cs2-gsi.sh writes that file. GSI is an official,
VAC-safe, read-only feature: the same feed every CS scoreboard overlay is built on.
It carries the map, the mode, the round phase, both teams' scores and your own
kills/deaths:

    { "provider": {"steamid": "7656…"},
      "map":    {"name": "de_dust2", "mode": "competitive", "phase": "live",
                 "team_ct": {"score": 7}, "team_t": {"score": 5}},
      "player": {"steamid": "7656…", "team": "CT",
                 "match_stats": {"kills": 12, "deaths": 8, "assists": 3}} }

`player` follows your SPECTATOR target the moment you die, so `player.match_stats` is
only yours while `player.steamid == provider.steamid` — see normalise().

── Stop is a timeout, not an event ─────────────────────────────────────────
CS2 sends no "goodbye" when it quits; the POSTs simply stop. The presence is cleared
when the feed has been silent for GSI_STALE_SECONDS, rather than by watching for a
process to disappear (which would cost a poll this otherwise doesn't need).

── The HTTP listener runs on a thread ──────────────────────────────────────
The main loop is a selectors loop (Discord socket + stdin), and CS2's POSTs have to
land somewhere with a real HTTP parser. `http.server` on a daemon thread is that,
with a lock over the one payload it keeps and a self-pipe byte to wake the main loop.
GSI ticks ~2/s during a round and the Discord rate limit is one send per 5s, so the
main loop picking the payload up on its own 1s tick would be fine on its own; the
wake just makes the first card after "match found" appear a second sooner.

── Everything else — the binary framing, the coalesced rate limiting, the
reconnect backoff, the detached-daemon state-file / options-file plumbing, the
SIGTERM-unwinds-so-the-card-is-cleared rule — is claude-presence.py's, for
claude-presence.py's reasons. Read that file's header; this one won't repeat it.
"""

import sys, os, re, json, struct, socket, selectors, signal, time, uuid, threading
import sys as _sys; _sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qspaths   # where secret files live (outside the repo)
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import secretstore       # cs2PresenceClientId may live in the system keyring

OP_HANDSHAKE, OP_FRAME, OP_CLOSE, OP_PING, OP_PONG = 0, 1, 2, 3, 4

# Discord tolerates ~5 SET_ACTIVITY per 20s. 5s between sends stays under that even
# when every one carries a change (a score line moves every round).
MIN_UPDATE_INTERVAL = 5.0

# No POST for this long ⇒ CS2 is gone. This MUST be several times the .cfg's
# `heartbeat` (install-cs2-gsi.sh writes 15s): in a menu or on a loading screen the
# heartbeat is the only traffic, and a threshold near it clears the card every time a
# beat lands late — a visible flicker to "Waiting for CS2" and back. 90s is six missed
# beats. The cost is the card lingering ~90s after you quit CS2, which is fine —
# disabling the feature (SIGTERM) clears it at once regardless.
GSI_STALE_SECONDS = 90.0

# A Discord that isn't running is the common case, not an error. Don't hammer it.
RECONNECT_INTERVAL = 10.0

# Main-loop tick. Doubles as the poll interval for the options file.
TICK = 1.0

DEFAULT_PORT = 3000

# Valve's real, registered "Counter-Strike 2" Discord application. Handshaking as it
# makes the card's bold first line read "Counter-Strike 2" and its icon the CS2 logo
# with NO setup — no app to register, no art to upload. SET_ACTIVITY needs no OAuth
# (claude-presence.py's header has the measurement), and the RPC handshake accepts any
# valid application id, so this works without owning the app. Override it with
# `cs2PresenceClientId` in discord-rpc.json only if you'd rather run your own.
DEFAULT_CLIENT_ID = "1158877933042143272"

CONFIG_PATH = qspaths.secret_file("discord-rpc.json")   # outside the repo: qspaths.py

# Written by scripts/install-cs2-gsi.sh: {"port": 3000, "token": "…"}. The token is
# the shared secret in the .cfg that CS2 echoes back in every POST — checked so a
# different local process can't spoof game state onto your profile. Absent is fine:
# the listener then binds the default port and accepts any token (the socket is
# loopback-only, so the worst case is cosmetic and local).
GSI_CONFIG_PATH = qspaths.secret_file("cs2-gsi.json")


# ── Detached vs attached, exactly as claude-presence.py ───────────────────────
STATE_FILE = ""
OPTIONS_FILE = ""


def emit(obj):
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
    sys.stderr.write("cs2-presence: %s\n" % msg)
    sys.stderr.flush()


# ══ Game State Integration ════════════════════════════════════════════════════

class _Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_a):
        pass                                   # its default logs every POST to stderr

    def _drain_body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length > 0 else b""

    def do_POST(self):
        raw = self._drain_body()
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()
        try:
            data = json.loads(raw)
        except ValueError:
            return
        if isinstance(data, dict):
            self.server.listener.ingest(data)

    def do_GET(self):
        # So `curl localhost:3000` is a clear "yes, something is listening" while
        # setting the .cfg up, rather than a connection refused.
        body = b"cs2-presence GSI listener\n"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class _Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    listener = None                            # set right after construction


class GsiListener:
    """The HTTP endpoint CS2 POSTs to, and the last payload it delivered."""

    def __init__(self, wake_fd):
        self.wake_fd = wake_fd
        self.lock = threading.Lock()
        self.payload = None
        self.stamp = 0.0                       # monotonic-ish wall time of last POST
        self.token = ""
        self.server = None
        self.thread = None
        self.port = 0
        self.error = ""

    def rebind(self, port, token):
        """(Re)start the listener on `port`. A no-op when already there."""
        self.token = token or ""
        if self.server is not None and self.port == port:
            return
        self.stop()
        try:
            srv = _Server(("127.0.0.1", port), _Handler)
        except OSError as e:
            self.error = "GSI port %d unavailable: %s" % (port, e)
            log(self.error)
            return
        srv.listener = self
        self.server, self.port, self.error = srv, port, ""
        self.thread = threading.Thread(target=srv.serve_forever, name="gsi",
                                       daemon=True)
        self.thread.start()
        log("GSI listening on 127.0.0.1:%d" % port)

    def stop(self):
        if self.server is not None:
            try:
                self.server.shutdown()
                self.server.server_close()
            except Exception:
                pass
            self.server = None

    def ingest(self, data):
        """Called from the HTTP thread. Validates the token, stores the payload,
        nudges the main loop awake."""
        if self.token:
            got = str((data.get("auth") or {}).get("token") or "")
            if got != self.token:
                return
        with self.lock:
            self.payload = data
            self.stamp = time.time()
        try:
            os.write(self.wake_fd, b"x")
        except OSError:
            pass

    def latest(self):
        """The last payload and how long ago it arrived, or (None, inf)."""
        with self.lock:
            if self.payload is None:
                return None, float("inf")
            return self.payload, time.time() - self.stamp


# ══ Payload → the handful of fields the card needs ════════════════════════════

# Active-duty and the common non-competitive maps get a real name; anything else is
# de-prefixed and title-cased, which is right often enough (workshop maps included).
MAP_NAMES = {
    "de_dust2": "Dust II", "de_mirage": "Mirage", "de_inferno": "Inferno",
    "de_nuke": "Nuke", "de_overpass": "Overpass", "de_vertigo": "Vertigo",
    "de_ancient": "Ancient", "de_anubis": "Anubis", "de_train": "Train",
    "de_cache": "Cache", "de_dust": "Dust", "cs_office": "Office",
    "cs_italy": "Italy", "cs_agency": "Agency", "de_shortdust": "Short Dust",
    "ar_baggage": "Baggage", "ar_shoots": "Shoots", "ar_pool_day": "Pool Day",
}

MODE_NAMES = {
    "competitive": "Competitive", "premier": "Premier", "casual": "Casual",
    "deathmatch": "Deathmatch", "scrimcomp2v2": "Wingman",
    "gungameprogressive": "Arms Race", "gungametrbomb": "Demolition",
    "survival": "Danger Zone", "cooperative": "Co-op", "coopmission": "Guardian",
    "skirmish": "Skirmish", "training": "Training", "custom": "Custom",
    "casualsdm": "Casual",
}


def pretty_map(name):
    name = name or ""
    if name in MAP_NAMES:
        return MAP_NAMES[name]
    stripped = re.sub(r"^(de|cs|ar|dz|gd|coop|lobby|am|workshop)_", "", name)
    return stripped.replace("_", " ").strip().title() or "a map"


def pretty_mode(mode):
    key = (mode or "").lower()
    if key in MODE_NAMES:
        return MODE_NAMES[key]
    return (mode or "").replace("_", " ").strip().title() or "Casual"


def normalise(payload):
    """CS2's GSI dict → {menu} or {menu:False, map, mode, phase, ct, t, team,
    kills, deaths}. Returns None only for a payload that isn't a dict.

    kills/deaths come back None unless the payload's `player` is actually YOU — it
    follows your spectator target once you're dead. The Runner carries the last real
    pair forward across those gaps; see refresh().
    """
    if not isinstance(payload, dict):
        return None

    me = str((payload.get("provider") or {}).get("steamid") or "")
    player = payload.get("player") or {}
    mp = payload.get("map") or {}

    # In menus and lobbies CS2 keeps POSTing, just with no `map`. That's a state of
    # its own — "online, between matches" — not missing data.
    if not mp.get("name"):
        return {"menu": True}

    ct = (mp.get("team_ct") or {}).get("score")
    t = (mp.get("team_t") or {}).get("score")
    stats = player.get("match_stats") or {}
    mine = me != "" and str(player.get("steamid") or "") == me

    def as_int(v):
        try:
            return int(v)
        except (TypeError, ValueError):
            return None

    return {
        "menu": False,
        "map": mp.get("name") or "",
        "mode": mp.get("mode") or "",
        "phase": mp.get("phase") or "",            # warmup | live | intermission | gameover
        "ct": as_int(ct),
        "t": as_int(t),
        "team": (player.get("team") or "").upper(),
        "kills": as_int(stats.get("kills")) if mine else None,
        "deaths": as_int(stats.get("deaths")) if mine else None,
    }


# ══ The card ══════════════════════════════════════════════════════════════════

def build_activity(st, opts, since):
    """The Discord activity object, or None when nothing should show.

    details — "<Mode> · <Map>", e.g. "Competitive · Dust II". "In the main menu"
              between matches.
    state   — "CT 7 : 5 T · 12/8 K/D", with either half droppable from settings, and
              replaced wholesale by "Warming up" / "Match over" at those phases.
    """
    if not st:
        return None

    act = {}
    name = opts.get("appName") or "Counter-Strike 2"
    if name:
        act["name"] = name[:126]
    img = opts.get("largeImage") or ""
    if img:
        act["assets"] = {"large_image": img, "large_text": "Counter-Strike 2"}

    if st.get("menu"):
        act["details"] = "In the main menu"
        return act

    mode = pretty_mode(st["mode"]) if opts.get("showMode", True) else ""
    act["details"] = (" · ".join(p for p in (mode, pretty_map(st["map"])) if p))[:126]

    tally = []
    if opts.get("showScore", True) and st["ct"] is not None and st["t"] is not None:
        tally.append("CT %d : %d T" % (st["ct"], st["t"]))
    if opts.get("showKd", True) and st["kills"] is not None and st["deaths"] is not None:
        tally.append("%d/%d K/D" % (st["kills"], st["deaths"]))
    joined = " · ".join(tally)

    if st["phase"] == "warmup":
        act["state"] = "Warming up"
    elif st["phase"] == "gameover":
        act["state"] = ("Match over — " + joined) if joined else "Match over"
    elif joined:
        act["state"] = joined[:126]

    if since:
        act["timestamps"] = {"start": int(since)}
    return act


# ══ Discord ═══════════════════════════════════════════════════════════════════
# Byte-for-byte claude-presence.py's Discord class — same socket, same framing, same
# "only ever SET_ACTIVITY" job. Kept as a copy rather than shared because the two
# daemons have separate lifetimes and nothing else in common.

def ipc_candidates():
    base = (os.environ.get("XDG_RUNTIME_DIR") or os.environ.get("TMPDIR")
            or os.environ.get("TMP") or "/tmp").rstrip("/")
    for tail in ("", "/app/com.discordapp.Discord", "/app/com.discordapp.DiscordCanary",
                 "/snap.discord", "/.flatpak/dev.vencord.Vesktop/xdg-run"):
        for i in range(10):
            yield "%s%s/discord-ipc-%d" % (base, tail, i)


class Discord:
    def __init__(self, client_id):
        self.client_id = client_id
        self.sock = None
        self.ready = False
        self.buf = b""
        self.last_send = 0.0
        self.sent = None
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


# ══ The loop ══════════════════════════════════════════════════════════════════

def load_client_id():
    """`cs2PresenceClientId` from discord-rpc.json (or the keyring), or Valve's real CS2 app id.

    Unlike claude-presence's key this one has a working default, because the CS2
    application already exists and is registered — there is nothing for a fresh
    install to set up. The key is here only for someone who wants their own app
    (custom art, a different name)."""
    try:
        with open(CONFIG_PATH) as fh:
            cfg = json.load(fh)
    except (OSError, ValueError):
        cfg = {}
    return (secretstore.resolve(cfg, "cs2PresenceClientId", "discord-cs2-presence-client-id")
            or DEFAULT_CLIENT_ID)


def load_gsi_config():
    """{"port", "token"} from the installer's file. Defaults when it isn't there."""
    try:
        with open(GSI_CONFIG_PATH) as fh:
            cfg = json.load(fh)
    except (OSError, ValueError):
        return DEFAULT_PORT, ""
    port = cfg.get("port")
    try:
        port = int(port)
    except (TypeError, ValueError):
        port = DEFAULT_PORT
    return port, str(cfg.get("token") or "")


class Runner:
    def __init__(self):
        # Same "must be right, not merely present" note as claude-presence: the daemon
        # is detached and publishes at least one card before the shell writes options.
        self.opts = {"showScore": True, "showKd": True, "showMode": True,
                     "largeImage": "", "appName": "Counter-Strike 2",
                     "port": 0}                 # 0 ⇒ take the installer's / default port
        self.client_id = load_client_id()
        self.discord = Discord(self.client_id)
        self.wake_r, self.wake_w = os.pipe()
        os.set_blocking(self.wake_r, False)
        self.gsi = GsiListener(self.wake_w)
        self.sel = selectors.DefaultSelector()

        self.gsi_port, self.gsi_token = load_gsi_config()
        self.gsi_config_mtime = None
        self.last_poll = 0.0
        self.last_connect_try = 0.0
        self.options_mtime = None

        self.state = None                       # normalise() output, carried forward
        self.since = 0                           # unix seconds the current map started
        self.kd = (None, None)                   # last real (kills, deaths) this map
        self.activity = None
        self.published = None

    # ── Options, as a file (detached) ────────────────────────────────────────
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
        if isinstance(incoming, dict):
            self._merge_options(incoming)

    def poll_gsi_config(self):
        """Re-read cs2-gsi.json when it changes — so running install-cs2-gsi.sh AFTER
        the daemon started (the common order) takes effect without a restart. CS2 still
        needs its own restart to re-read the .cfg; that's the game's, not ours."""
        try:
            mtime = os.stat(GSI_CONFIG_PATH).st_mtime
        except OSError:
            return
        if mtime == self.gsi_config_mtime:
            return
        self.gsi_config_mtime = mtime
        self.gsi_port, self.gsi_token = load_gsi_config()

    def _merge_options(self, incoming):
        for k in ("showScore", "showKd", "showMode", "largeImage", "appName", "port"):
            if k in incoming:
                self.opts[k] = incoming[k]
        self.reload_client_id()
        self.refresh(force=True)

    def reload_client_id(self):
        new = load_client_id()
        if new == self.client_id:
            return
        self.discord.close()
        self.client_id = new
        self.discord = Discord(new)
        self.last_connect_try = 0.0

    def effective_port(self):
        try:
            override = int(self.opts.get("port") or 0)
        except (TypeError, ValueError):
            override = 0
        return override or self.gsi_port or DEFAULT_PORT

    # ── stdin: the QML side changing its mind (attached mode) ────────────────
    def handle_command(self, line):
        try:
            cmd = json.loads(line)
        except ValueError:
            return
        c = cmd.get("c")
        if c == "options":
            self._merge_options(cmd)
        elif c == "reloadClientId":
            self.reload_client_id()
            self.emit_state()
        elif c == "refresh":
            self.refresh(force=True)

    # ── State out ───────────────────────────────────────────────────────────
    def stage(self):
        if self.discord.error.startswith("4006"):
            return "unauthorized"
        if self.gsi.error:
            return "port-unavailable"
        if not self.discord.ready:
            return "no-discord"
        return ""

    def emit_state(self):
        st = self.state or {}
        in_match = bool(st) and not st.get("menu")
        emit({
            "stage": self.stage(),
            "connected": self.discord.ready,
            "inMatch": in_match,
            "inMenu": bool(st) and bool(st.get("menu")),
            "map": pretty_map(st["map"]) if in_match else "",
            "mode": pretty_mode(st["mode"]) if in_match else "",
            "ct": st.get("ct") if in_match else None,
            "t": st.get("t") if in_match else None,
            "kills": st.get("kills") if in_match else None,
            "deaths": st.get("deaths") if in_match else None,
            "details": (self.activity or {}).get("details", ""),
            "state": (self.activity or {}).get("state", ""),
            "port": self.effective_port(),
            "error": self.discord.error,
        })

    # ── Recompute what should be on screen ──────────────────────────────────
    def refresh(self, force=False):
        payload, age = self.gsi.latest()
        st = normalise(payload) if (payload is not None and age <= GSI_STALE_SECONDS) \
            else None

        if st and not st.get("menu"):
            # A new map (or the first one) resets the elapsed clock and the K/D carry.
            if not self.state or self.state.get("menu") or \
                    self.state.get("map") != st.get("map"):
                self.since = int(time.time())
                self.kd = (None, None)
            if st["kills"] is not None and st["deaths"] is not None:
                self.kd = (st["kills"], st["deaths"])
            else:
                st["kills"], st["deaths"] = self.kd
        else:
            self.since = 0
            self.kd = (None, None)

        activity = build_activity(st, self.opts,
                                  self.since if st and not st.get("menu") else 0)

        if not force and st == self.state and activity == self.activity:
            return
        self.state, self.activity = st, activity

        snapshot = json.dumps([activity, self.stage()], sort_keys=True)
        if snapshot != self.published:
            self.published = snapshot
            self.emit_state()

    def run(self):
        # Detached, stdin is /dev/null and the options file is the command channel. Run
        # by hand it's a pipe (tests) or a tty. A regular file or /dev/null makes epoll
        # raise EPERM on register — discord-rpc.py's stdin_pollable() documents this —
        # so a failed registration just means "no stdin commands", which is right for
        # every case that hits it.
        if not OPTIONS_FILE:
            try:
                self.sel.register(sys.stdin, selectors.EVENT_READ, "stdin")
            except (OSError, ValueError):
                pass
        self.sel.register(self.wake_r, selectors.EVENT_READ, "gsi")

        self.gsi.rebind(self.effective_port(), self.gsi_token)
        self.emit_state()
        registered = None

        while True:
            now = time.time()

            if not self.discord.sock and \
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

            if now - self.last_poll >= TICK:
                self.last_poll = now
                self.poll_options_file()
                self.poll_gsi_config()
                self.gsi.rebind(self.effective_port(), self.gsi_token)
                self.refresh()

            pending = self.discord.apply(self.activity)
            timeout = TICK
            if pending is not None:
                timeout = min(timeout, max(0.05, pending))

            for key, _ in self.sel.select(timeout):
                what = key.data
                if what == "stdin":
                    line = sys.stdin.readline()
                    if not line:
                        return
                    self.handle_command(line.strip())
                elif what == "gsi":
                    try:
                        os.read(self.wake_r, 65536)
                    except OSError:
                        pass
                    self.refresh()
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


def parse_args(argv):
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
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))

    runner = Runner()
    try:
        runner.run()
    except (KeyboardInterrupt, SystemExit):
        pass
    finally:
        runner.gsi.stop()
        if runner.discord.sock and runner.discord.ready:
            runner.discord._send_frame(OP_FRAME, {
                "cmd": "SET_ACTIVITY", "nonce": str(uuid.uuid4()),
                "args": {"pid": os.getpid(), "activity": None}})
            time.sleep(0.2)
            runner.discord.close()


if __name__ == "__main__":
    main()
