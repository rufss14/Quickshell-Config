#!/usr/bin/env python3
"""Receive playback anchors from the Spicetify extension; print them as JSON lines.

    spotify-bridge.py [--port N] [--host 127.0.0.1]

Quickshell runs this as a long-lived Process and reads stdout with a SplitParser — the
same shape scripts/lyrics.py already uses, one JSON object per line.

── Why a listener at all ─────────────────────────────────────────────────────
A Spicetify extension is JavaScript inside Spotify's renderer. It has `fetch`; it has no
filesystem and no way to spawn anything. An HTTP hop is the only way out of there.
Quickshell's own SocketServer is unix-domain only (it takes a `path`, not a host/port),
which `fetch` cannot address — hence this process, rather than the shell listening directly.

── It receives ANCHORS, not a position stream ────────────────────────────────
The extension posts on songchange / seek / play / pause — roughly five times a song. The
shell interpolates between anchors off its own monotonic clock. Streaming a position
30×/second over HTTP to save a subtraction would be a strange trade, and it is the same
event-driven-over-polling rule the rest of this config follows.

── Loopback only ─────────────────────────────────────────────────────────────
This accepts unauthenticated JSON and hands it to the shell. It binds 127.0.0.1 and
additionally refuses any peer that is not loopback, so it is not reachable off the
machine even if the bind address is overridden by mistake.
"""

import sys, os, json, argparse, threading, time, ctypes, signal, hashlib, base64
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, parse_qs


def die_with_parent():
    """Ask the kernel to kill us when Quickshell dies.

    Without this the listener OUTLIVES a shell reload. It only discovers its parent is
    gone when it next writes to stdout — and it only writes when a POST arrives — so an
    idle listener sits holding the port indefinitely. The replacement shell then cannot
    bind, reports `bind failed`, and the bridge comes up dead with no lyrics and no
    playhead. Measured exactly that after `pkill -9 quickshell`, which orphans children
    rather than letting them clean up.

    PR_SET_PDEATHSIG (1) is the Linux answer and needs no supervision from either side.
    Best-effort: on anything without it we simply keep the old behaviour.
    """
    try:
        ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM, 0, 0, 0)
    except Exception:
        pass

DEFAULT_PORT = 47821          # arbitrary, high, and unregistered; override with --port
MAX_BODY     = 64 * 1024      # an anchor is a few hundred bytes; anything larger is wrong

_write_lock = threading.Lock()

# ── Restyle: the one message that goes the OTHER way ─────────────────────────
# The wave (services/Contagion.qml) recolours Spotify by rewriting its theme files
# (spicetify refresh) and then has to make the RUNNING app re-read them. The extension
# can't be reached from outside the renderer, so it holds a GET /events open here and
# this process answers it when reload-theme.sh POSTs /restyle. The extension swaps the
# stylesheets and POSTs back `restyled` once they're loaded and painted — the moment
# the wave has been waiting for, measured inside Spotify rather than guessed.
#
# One sequence number, not a queue: a restyle re-reads whatever is on disk NOW, so two
# requests the extension missed are worth exactly one. A request stays PENDING until
# the extension acknowledges it (its `restyled` report), and every poll that comes in
# while one is pending is answered at once — that covers the gap between polls. It
# used to count as delivered the moment ANY poll was answered, and a poll held by a
# Spotify that had just been restarted (its connection still open here; nothing
# notices a client that dies mid-wait) took the request and the live one waited out
# its hold. A pending request expires after PENDING_S, so a report that never comes
# can't keep the extension repainting.
EVENT_HOLD_S = float(os.environ.get("QS_SPOTIFY_BRIDGE_HOLD") or 25)   # the extension tells a timeout from an event by this; env for the test only
PENDING_S    = 10
_events      = threading.Condition()
_restyle_seq = 0              # requests made
_restyle_at  = float("-inf")  # monotonic time of the newest request
_acked_seq   = 0              # the newest one the extension has said it painted
_waiters     = 0              # polls held open right now
_last_poll   = float("-inf")  # monotonic time the last poll ended (the gap between polls)


# ── Playing something by name (the overview's AI: "play Bohemian Rhapsody") ───
# Spotify plays it ITSELF: the extension searches through the app's own plumbing (Spicetify's GraphQL
# searchDesktop — the client's own search, nothing rate-limited) and calls Player.playUri. The shell
# only has to get the words to the extension, and the renderer can't READ anything from here: every
# request it makes is a no-cors POST (the one shape measured to leave it), so replies are opaque.
#
# What it CAN read is a stylesheet's effect. POST /play queues the request and wakes the extension's
# long poll; the extension then loads /mailbox.css, which sets `#qs-mailbox::after { content: "<base64
# JSON>" }`, and reads it back with getComputedStyle — computed style is readable whatever origin the
# sheet came from. It answers with a {"type": "played"|"play-failed", "seq"} POST, and /play, which has
# waited for that (PLAY_WAIT_S), returns it. No answer (an older extension, Spotify closed) → 504, and
# scripts/music-play.py falls back to a web search, then to Spotify's search page.
#
# (2026-10-24 first tried the client's access token from here against api.spotify.com: 429 Too Many
# Requests, every time — Spotify throttles its desktop token outside the app. Removed.)
PLAY_KINDS  = ("track", "album", "playlist", "artist")
PLAY_WAIT_S = 8
_play       = None             # {"seq", "query", "kind", "at"} — the newest request; one at a time
_play_seq   = 0
_play_done  = {}               # seq → the extension's report


def _play_pending():
    """Call with _events held."""
    return (_play is not None and _play["seq"] not in _play_done
            and time.monotonic() - _play["at"] < PENDING_S)


def queue_play(query, kind):
    """→ (status, body). Waits for the extension's report."""
    global _play, _play_seq
    if not listening():
        return 503, {"ok": False, "error": "spotify-not-listening"}
    with _events:
        _play_seq += 1
        seq = _play_seq
        _play = {"seq": seq, "query": query, "kind": kind, "at": time.monotonic()}
        _events.notify_all()
        _events.wait_for(lambda: seq in _play_done, timeout=PLAY_WAIT_S)
        got = _play_done.pop(seq, None)
    if got is None:
        return 504, {"ok": False, "error": "spotify-no-answer"}
    ok = got.get("type") == "played"
    err = "" if ok else (got.get("error") or "nothing found")
    # 404 only for a search that ran and found nothing; anything else is the extension saying WHY (502).
    return (200 if ok else 404 if err == "nothing found" else 502), {
        "ok": ok, "uri": got.get("uri", ""), "title": got.get("title", ""), "error": err}


def play_report(msg):
    with _events:
        try:
            _play_done[int(msg.get("seq") or 0)] = msg
        except (TypeError, ValueError):
            return
        _events.notify_all()


def mailbox_css():
    """The mail, as a stylesheet the extension reads back through computed style."""
    with _events:
        mail = {}
        if _restyle_pending():
            mail["restyle"] = _restyle_seq
        if _play_pending():
            mail["play"] = {"seq": _play["seq"], "query": _play["query"], "kind": _play["kind"]}
    b64 = base64.b64encode(json.dumps(mail).encode("utf-8")).decode("ascii")
    return ('#qs-mailbox::after{content:"%s"}\n' % b64).encode("ascii")


def _restyle_pending():
    """Call with _events held."""
    return _restyle_seq > _acked_seq and time.monotonic() - _restyle_at < PENDING_S


def _pending():
    """Call with _events held: anything for the extension — a restyle, or something to play."""
    return _restyle_pending() or _play_pending()


def acknowledge():
    """The extension painted: everything asked for up to now is done."""
    global _acked_seq
    with _events:
        _acked_seq = _restyle_seq


def listening():
    """Is an extension attached? A poll is open, or one ended moments ago and its
    successor is on the way."""
    with _events:
        return _waiters > 0 or (time.monotonic() - _last_poll) < 5


def emit(obj):
    """One compact JSON object per line, flushed. The lock matters because
    ThreadingHTTPServer will happily run two handlers at once and a torn line would
    desync the shell's SplitParser for good."""
    with _write_lock:
        try:
            sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
            sys.stdout.flush()
        except (BrokenPipeError, ValueError):
            # Quickshell went away (reload, restart). Nothing to recover — the shell owns
            # this process' lifetime and will start a fresh one.
            os._exit(0)


# ── Spectrum: the cover's ring of level bars ──────────────────────────────────
# The media panel's cookie cover has a ring of bars driven by the shell's `cava`. Spotify's
# page can run no process and see no audio, so the bridge — which is already the shell's one
# hop out of that renderer — runs the SAME cava (same config values as services/CavaStream.qml)
# and streams its frames to whoever asks: `GET /spectrum` is a text/event-stream of
# `data: v,v,v…` lines (32 values, 0..1). Nothing runs until the first listener connects and
# cava is stopped when the last one leaves, so an idle bridge costs nothing.
#
# It analyses Spotify's own PipeWire node (named "spotify"), as the panel does for its player, so
# a game or a video playing alongside does not move the bars. QS_CAVA_SOURCE overrides it ("" =
# cava's default input).
SPECTRUM_BARS = 32
SPECTRUM_FPS  = 30
CAVA_BIN      = os.environ.get("QS_CAVA") or "cava"   # env for the test only
CAVA_SOURCE   = os.environ.get("QS_CAVA_SOURCE", "spotify")
_spec_cond    = threading.Condition()
_spec_subs    = 0
_spec_proc    = None
_spec_seq     = 0
_spec_frame   = ""
_spec_error   = ""


def _cava_config():
    """The same values CavaStream writes, mono, 0..1000. A fixed per-user path in the
    runtime dir (0700) — rewritten, never accumulated — for the reasons CavaStream gives."""
    d = os.environ.get("XDG_RUNTIME_DIR") or os.environ.get("XDG_CACHE_HOME") \
        or os.path.join(os.path.expanduser("~"), ".cache")
    os.makedirs(d, exist_ok=True)
    # Not cava-qs-spotify.ini: that is the shell's own name for ITS cava on this node
    # (CavaStream derives it from the source), and each rewrites and deletes its file.
    path = os.path.join(d, "cava-qs-bridge.ini")
    old = os.umask(0o077)
    try:
        head = ("[general]\nbars=%d\nframerate=%d\n"
                "sensitivity=200\nautosens=1\nnoise_reduction=0.2\n" % (SPECTRUM_BARS, SPECTRUM_FPS))
        src = "[input]\nmethod=pipewire\nsource=%s\n" % CAVA_SOURCE if CAVA_SOURCE else ""
        out = ("[output]\nmethod=raw\ndata_format=ascii\nascii_max_range=1000\n"
               "raw_target=/dev/stdout\nbar_delimiter=59\nframe_delimiter=10\nchannels=mono\n")
        with open(path, "w") as f:
            f.write(head + src + out)
    finally:
        os.umask(old)
    return path


def parse_frame(line, n=SPECTRUM_BARS):
    """cava's `a;b;c;` → 'a,b,c' as 0..1 with three decimals, or None for a short or empty
    line. A torn frame (cava killed mid-write) must not reach a listener as a short ring."""
    vals = []
    for part in line.strip().split(";"):
        part = part.strip()
        if not part:
            continue
        try:
            vals.append(max(0.0, min(1.0, int(part) / 1000.0)))
        except ValueError:
            return None
    if len(vals) < n:
        return None
    return ",".join("%.3f" % v for v in vals[:n])


def _spec_reader(proc):
    global _spec_seq, _spec_frame
    for line in proc.stdout:
        frame = parse_frame(line)
        if frame is None:
            continue
        with _spec_cond:
            _spec_frame = frame
            _spec_seq += 1
            _spec_cond.notify_all()


def _die_with_bridge():
    """The child half of die_with_parent(): cava must not outlive the bridge."""
    try:
        ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM, 0, 0, 0)
    except Exception:
        pass


def spectrum_acquire():
    """Count a listener in, starting cava for the first. Returns an error string, or ''."""
    global _spec_subs, _spec_proc, _spec_error
    import subprocess
    with _spec_cond:
        if _spec_proc is None or _spec_proc.poll() is not None:
            try:
                _spec_proc = subprocess.Popen([CAVA_BIN, "-p", _cava_config()],
                                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                              text=True, preexec_fn=_die_with_bridge)
            except OSError as e:
                _spec_error = "cava unavailable: %s" % e
                return _spec_error
            _spec_error = ""
            threading.Thread(target=_spec_reader, args=(_spec_proc,), daemon=True).start()
        _spec_subs += 1
    return ""


def spectrum_release():
    global _spec_subs, _spec_proc, _spec_frame
    with _spec_cond:
        _spec_subs = max(0, _spec_subs - 1)
        if _spec_subs == 0 and _spec_proc is not None:
            try:
                _spec_proc.terminate()
            except OSError:
                pass
            _spec_proc = None
            _spec_frame = ""


# ── Canvas: the looping clip, in a format this Spotify can actually show ────────
# Spotify's Canvas clips are H.264 MP4, and Spotify's Linux build links an ffmpeg WITHOUT the
# proprietary codecs into libcef.so — `canPlayType('video/mp4; codecs="avc1…"')` is "" there, and
# there is no separate libffmpeg.so to swap. So no Canvas ever plays, whatever the theme does.
# The theme asks for a clip HERE instead (`GET /canvas?src=<the clip's canvaz URL>`, as a CSS
# background); this downloads it once, re-encodes it into an animated AVIF (AV1, which that same
# Chromium decodes), caches it, and serves it. Measured on a 7.4s 720×1280 clip: 1.4s and 383KB
# at 480px wide (an animated WebP was 3.0s and 1.9MB). WebP stays as the fallback for an ffmpeg
# with no SVT-AV1.
#
# `src` comes from the page, so it is a trust boundary: only https://canvaz.scdn.co/….mp4 is
# fetched (no other host, port, userinfo or scheme — this must never become a way to make the
# machine fetch arbitrary URLs), the download is capped, and ffmpeg is given a local file only.
CANVAS_HOST  = "canvaz.scdn.co"
CANVAS_MAX   = 32 * 1024 * 1024           # a clip is ~1MB; anything near this is not a clip
CANVAS_KEEP  = 300                        # cached clips kept, newest-used first
CANVAS_RETRY = 600                        # seconds before a clip that failed is tried again
FFMPEG_BIN   = os.environ.get("QS_FFMPEG") or "ffmpeg"   # env for the test only
CANVAS_DIR   = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache"),
                            "quickshell-spotify-canvas")
# (encoder, extension, content type, ffmpeg output arguments), best first.
CANVAS_ENCODERS = (
    ("libsvtav1", "avif", "image/avif",
     ["-c:v", "libsvtav1", "-crf", "40", "-preset", "10", "-pix_fmt", "yuv420p", "-loop", "0", "-f", "avif"]),
    ("libwebp_anim", "webp", "image/webp",
     ["-c:v", "libwebp_anim", "-lossless", "0", "-q:v", "55", "-loop", "0", "-f", "webp"]),
)
_canvas_lock   = threading.Lock()
_canvas_busy   = {}                       # key → Lock, so one clip is fetched once however often it's asked
_canvas_failed = {}                       # key → monotonic time it failed


def canvas_source(src):
    """The clip URL if it is one of Spotify's Canvas clips, else None. Normalised: no query,
    no fragment, so one clip has one cache key."""
    if not isinstance(src, str) or len(src) > 512:
        return None
    try:
        u = urlsplit(src)
        port = u.port
    except ValueError:
        return None
    if u.scheme != "https" or u.hostname != CANVAS_HOST or port is not None \
            or u.username is not None or u.password is not None or u.netloc != CANVAS_HOST:
        return None
    if not u.path.startswith("/") or not u.path.endswith(".mp4") or ".." in u.path or "\\" in u.path:
        return None
    return "https://%s%s" % (CANVAS_HOST, u.path)


def _canvas_cached(key):
    for _, ext, ctype, _ in CANVAS_ENCODERS:
        path = os.path.join(CANVAS_DIR, key + "." + ext)
        if os.path.exists(path):
            return path, ctype
    return None, None


def _canvas_prune():
    try:
        files = [os.path.join(CANVAS_DIR, f) for f in os.listdir(CANVAS_DIR) if not f.startswith(".")]
        files.sort(key=lambda p: os.path.getmtime(p), reverse=True)
        for p in files[CANVAS_KEEP:]:
            os.remove(p)
    except OSError:
        pass


def canvas_file(url):
    """(path, content type, error) for a validated clip URL — from the cache, or fetched and
    encoded now (a few seconds; the page shows the cover meanwhile)."""
    import subprocess, tempfile, urllib.request
    key = hashlib.sha1(url.encode()).hexdigest()[:24]
    with _canvas_lock:
        if time.monotonic() - _canvas_failed.get(key, float("-inf")) < CANVAS_RETRY:
            return None, None, "failed recently"
        busy = _canvas_busy.setdefault(key, threading.Lock())
    with busy:
        path, ctype = _canvas_cached(key)
        if path:
            try:
                os.utime(path)                    # newest-used, for the prune
            except OSError:
                pass
            return path, ctype, ""
        os.makedirs(CANVAS_DIR, exist_ok=True)
        tmp = tempfile.mkdtemp(prefix=".", dir=CANVAS_DIR)
        err = ""
        try:
            src = os.path.join(tmp, "clip.mp4")
            with urllib.request.urlopen(url, timeout=15) as r, open(src, "wb") as f:
                got = 0
                while True:
                    chunk = r.read(65536)
                    if not chunk:
                        break
                    got += len(chunk)
                    if got > CANVAS_MAX:
                        raise ValueError("clip larger than %d bytes" % CANVAS_MAX)
                    f.write(chunk)
            for _, ext, ctype, args in CANVAS_ENCODERS:
                out = os.path.join(tmp, "out." + ext)
                cmd = [FFMPEG_BIN, "-v", "error", "-y", "-i", src, "-an", "-vf", "scale=480:-2"] + args + [out]
                try:
                    p = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                                       timeout=90, preexec_fn=_die_with_bridge)
                except (OSError, subprocess.TimeoutExpired) as e:
                    err = "ffmpeg: %s" % e
                    if isinstance(e, OSError):
                        break                     # no ffmpeg at all: no encoder will do better
                    continue
                if p.returncode == 0 and os.path.getsize(out) > 0:
                    final = os.path.join(CANVAS_DIR, key + "." + ext)
                    os.replace(out, final)
                    _canvas_prune()
                    return final, ctype, ""
                err = "ffmpeg: " + p.stderr.decode("utf-8", "replace").strip()[-200:]
        except Exception as e:                    # the download: network, HTTP status, size
            err = "%s: %s" % (type(e).__name__, e)
        finally:
            import shutil
            shutil.rmtree(tmp, ignore_errors=True)
        with _canvas_lock:
            _canvas_failed[key] = time.monotonic()
        return None, None, err or "no encoder"


# ── An opt-in request trace, for "Spotify says it sent it; nothing arrived" ─────
# Spotify's console is off, so this side is the only witness. While the flag file
# exists, one line per request goes to the trace file: method, path, size, the fetch
# metadata headers and the reply code — never a body (the lyrics travel in them).
#   touch "$XDG_RUNTIME_DIR/quickshell-spotify-bridge.trace"   (rm to stop)
#   tail -F "$XDG_RUNTIME_DIR/quickshell-spotify-bridge.trace.log"
_RUN_DIR    = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
TRACE_FLAG  = os.path.join(_RUN_DIR, "quickshell-spotify-bridge.trace")
TRACE_FILE  = TRACE_FLAG + ".log"
_TRACE_HDRS = ("Content-Type", "Content-Length", "Origin", "Sec-Fetch-Mode", "Sec-Fetch-Site",
               "Access-Control-Request-Method", "Access-Control-Request-Private-Network",
               "Access-Control-Request-Local-Network")


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def send_response(self, code, message=None):
        if os.path.exists(TRACE_FLAG):
            try:
                hdrs = " ".join("%s=%s" % (h, self.headers.get(h)) for h in _TRACE_HDRS
                                if self.headers.get(h) is not None)
                with _write_lock, open(TRACE_FILE, "a") as f:
                    f.write("%s %s %s -> %d %s\n" % (time.strftime("%H:%M:%S"), self.command,
                                                     self.path[:40], code, hdrs[:300]))
            except OSError:
                pass
        super().send_response(code, message)

    # ── Silence ───────────────────────────────────────────────────────────────
    # BaseHTTPRequestHandler logs every request to stderr. Quickshell surfaces a
    # Process' stderr in its own log, so leaving this on writes a line per anchor into
    # the shell log forever.
    def log_message(self, *a):
        pass

    def _loopback(self):
        return self.client_address[0] in ("127.0.0.1", "::1", "::ffff:127.0.0.1")

    def _cors(self):
        # Fire-and-forget from the extension uses mode:"no-cors", which needs none of
        # this — but sending it means a response is readable if the extension ever wants
        # to check one, and it costs three headers.
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        # Chromium's private/local-network preflight for a cors request to loopback.
        self.send_header("Access-Control-Allow-Private-Network", "true")

    def _finish(self, code, body=b""):
        self.send_response(code)
        self._cors()
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_OPTIONS(self):
        self._finish(204)

    def do_GET(self):
        if self.path.split("?")[0] == "/events":
            self._poll()
            return
        if self.path.split("?")[0] == "/spectrum":
            self._spectrum()
            return
        if self.path.split("?")[0] == "/canvas":
            self._canvas()
            return
        if self.path.split("?")[0] == "/mailbox.css":
            if not self._loopback():
                self._finish(403)
                return
            body = mailbox_css()
            self.send_response(200)
            self._cors()
            self.send_header("Content-Type", "text/css")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)
            return
        # A liveness probe, so "is the bridge up?" is answerable without a track change.
        # `listening` is what reload-theme.sh --probe asks: can Spotify be restyled live?
        body = {"ok": True, "service": "quickshell-spotify-bridge", "listening": listening()}
        self._finish(200, json.dumps(body, separators=(",", ":")).encode())

    def _canvas(self):
        """A Canvas clip as an animated image (see canvas_file). The page loads it as a CSS
        background — a plain image request — so the body is the image and errors are bare codes."""
        if not self._loopback():
            self._finish(403)
            return
        src = (parse_qs(urlsplit(self.path).query).get("src") or [""])[0]
        url = canvas_source(src)
        if not url:
            self._finish(400)
            return
        path, ctype, err = canvas_file(url)
        if not path:
            emit({"type": "canvas-error", "error": err[:200], "recvAt": _now_ms()})
            self._finish(502)
            return
        try:
            with open(path, "rb") as f:
                body = f.read()
        except OSError:
            self._finish(500)
            return
        self.send_response(200)
        self._cors()
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        # The same src is the same clip for good; let the page's image cache keep it.
        self.send_header("Cache-Control", "max-age=604800, immutable")
        self.end_headers()
        self.wfile.write(body)

    def _spectrum(self):
        """Stream cava frames until the listener goes away. One thread per listener (this is a
        ThreadingHTTPServer); the frame itself is shared."""
        global _spec_seq
        if not self._loopback():
            self._finish(403)
            return
        err = spectrum_acquire()
        if err:
            self._finish(503, json.dumps({"error": err}).encode())
            return
        try:
            self.send_response(200)
            self._cors()
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-store")
            # No Content-Length and no keep-alive: the body ends when the socket does.
            self.send_header("Connection", "close")
            self.end_headers()
            self.close_connection = True
            seen = -1
            while True:
                with _spec_cond:
                    _spec_cond.wait_for(lambda: _spec_seq != seen, timeout=5)
                    frame, seen = _spec_frame, _spec_seq
                # A comment line when cava is quiet keeps a dead socket from lingering.
                self.wfile.write(("data: %s\n\n" % frame if frame else ": idle\n\n").encode())
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            spectrum_release()

    def _poll(self):
        """The extension's long poll: 200 at once while anything is pending (a restyle, a play),
        204 after EVENT_HOLD_S with nothing."""
        global _waiters, _last_poll
        if not self._loopback():
            self._finish(403)
            return
        with _events:
            _waiters += 1
            try:
                _events.wait_for(_pending, timeout=EVENT_HOLD_S)
                # Woken for anything (a restyle, or mail to read): answer now. The extension reads
                # /mailbox.css to learn which (the reply itself is opaque to it).
                seq = (_restyle_seq or 1) if _pending() else 0
            finally:
                _waiters -= 1
                _last_poll = time.monotonic()
        if seq:
            self._finish(200, b'{"restyle":%d}' % seq)
        else:
            self._finish(204)

    def _restyle(self):
        global _restyle_seq, _restyle_at
        with _events:
            _restyle_seq += 1
            _restyle_at = time.monotonic()
            seq = _restyle_seq
            _events.notify_all()
        on = listening()
        # Told to the shell too: with nobody listening, nothing will come back, and the
        # wave must not wait for it.
        emit({"type": "restyle", "seq": seq, "listening": on, "recvAt": _now_ms()})
        self._finish(200, json.dumps({"seq": seq, "listening": on}).encode())

    def do_POST(self):
        if not self._loopback():
            self._finish(403)
            return

        if self.path.split("?")[0] == "/restyle":
            self._restyle()
            return

        if self.path.split("?")[0] == "/play":
            try:
                n = min(int(self.headers.get("Content-Length") or 0), MAX_BODY)
                req = json.loads(self.rfile.read(n).decode("utf-8", "replace")) if n > 0 else {}
            except (ValueError, OSError):
                req = None
            query = str((req or {}).get("query") or "").strip()[:120]
            kind = str((req or {}).get("kind") or "track")
            if not query or kind not in PLAY_KINDS:
                self._finish(400)
                return
            code, body = queue_play(query, kind)
            emit({"type": "played" if body.get("ok") else "play-failed", "title": body.get("title", ""),
                  "error": body.get("error", ""), "recvAt": _now_ms()})
            self._finish(code, json.dumps(body).encode())
            return

        # The extension's poll, as a no-cors POST: the one shape Spotify's renderer is
        # measured to deliver here (its anchors). A cors GET from that origin never
        # arrived — Chromium's local-network rules — so `listening` stayed false. The
        # body means nothing; it's read so the connection stays in step.
        if self.path.split("?")[0] == "/events":
            try:
                n = min(int(self.headers.get("Content-Length") or 0), MAX_BODY)
            except ValueError:
                n = 0
            if n > 0:
                self.rfile.read(n)
            self._poll()
            return

        try:
            n = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            self._finish(400)
            return

        if n <= 0 or n > MAX_BODY:
            self._finish(400)
            return

        try:
            raw = self.rfile.read(n)
            msg = json.loads(raw.decode("utf-8", "replace"))
        except Exception:
            # Malformed input is the extension's problem, never this process' problem.
            # Answering 400 and staying up is the whole contract: if this dies, the shell
            # loses its playhead until the next reload.
            self._finish(400)
            return

        if not isinstance(msg, dict):
            self._finish(400)
            return

        # `recvAt` is stamped HERE, not trusted from the sender. The shell needs to know
        # how stale an anchor is, and the renderer's clock is not ours to reason about.
        #
        # SpotifyBridge.qml anchors the playhead off THIS value now, not off Date.now() at
        # the moment it happens to process the stdout line. Those two differ by however
        # long the line sat waiting for the QML event loop to get to it — a blob shader
        # compile, another Process spawning, a GC pause — and that lag is exactly the kind
        # of jitter no fixed offset can correct because it isn't constant. Wall-clock, not
        # monotonic: the shell's `Date.now()` is wall-clock too, and the two are only
        # directly comparable if this one is as well.
        msg["recvAt"] = _now_ms()
        if msg.get("type") in ("played", "play-failed"):
            play_report(msg)
        if msg.get("type") == "restyled":
            acknowledge()
        emit(msg)
        self._finish(200, b'{"ok":true}')


def _now_ms():
    return int(time.time() * 1000)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--port", type=int,
                   default=int(os.environ.get("QS_SPOTIFY_BRIDGE_PORT", DEFAULT_PORT)))
    p.add_argument("--host", default="127.0.0.1")
    # For scripts/spotify-bridge-run.sh's detached mode ONLY. die_with_parent() is what
    # makes an ordinary run safe — without it a listener outlives its shell and blocks
    # the next one from binding (see that function's docstring). A standalone instance
    # is deliberately meant to outlive its immediate parent (a launcher script that
    # backgrounds it and exits in milliseconds), so it has to skip the one thing that
    # would otherwise kill it the instant that launcher does.
    p.add_argument("--standalone", action="store_true")
    a = p.parse_args()

    # allow_reuse_address so a shell reload doesn't hit "address already in use" against
    # the TIME_WAIT left by the previous instance.
    if not a.standalone:
        die_with_parent()

    ThreadingHTTPServer.allow_reuse_address = True
    ThreadingHTTPServer.daemon_threads = True

    # ── Retry the bind ────────────────────────────────────────────────────────
    # allow_reuse_address covers a socket in TIME_WAIT; it does NOT cover a previous
    # listener still alive and holding the port. During a reload the old shell's child may
    # take a moment to go away — PR_SET_PDEATHSIG above makes that reliable, but the two
    # processes still overlap briefly. Failing instantly there means the bridge is dead for
    # the whole session over a race measured in milliseconds.
    srv = None
    last = None
    for attempt in range(10):
        try:
            srv = ThreadingHTTPServer((a.host, a.port), Handler)
            break
        except OSError as e:
            last = e
            time.sleep(0.3)

    if srv is None:
        # Reported as a normal message on stdout rather than a traceback on stderr: the
        # shell parses stdout and can say "bridge unavailable" instead of going quiet.
        emit({"type": "error",
              "error": "bind failed after retries: %s" % last,
              "port": a.port})
        return 0

    emit({"type": "ready", "port": a.port})

    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
