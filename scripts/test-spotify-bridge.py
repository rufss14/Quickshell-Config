#!/usr/bin/env python3
"""The bridge's restyle channel (shell → bridge → extension → bridge → shell).

    python3 scripts/test-spotify-bridge.py

Starts a PRIVATE spotify-bridge.py on a free loopback port — never 47821, so the live
bridge is untouched — and plays the extension's part over plain HTTP.
"""
import json, os, socket, subprocess, sys, threading, time, urllib.request, urllib.parse, urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
passed = failed = 0


def check(name, ok):
    global passed, failed
    if ok:
        passed += 1
    else:
        failed += 1
        print("FAIL", name)


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


port = free_port()
base = "http://127.0.0.1:%d" % port
# A stand-in for cava: 32 bars of a known shape, forever, a frame every 20ms. The real one
# needs a sound server; what is under test is the stream, not the analysis.
import stat, tempfile
fake = os.path.join(tempfile.mkdtemp(), "fakecava")
with open(fake, "w") as f:
    f.write("#!/bin/sh\nwhile :; do echo '" + ";".join(str(i * 30) for i in range(32)) + ";'; sleep 0.02; done\n")
os.chmod(fake, os.stat(fake).st_mode | stat.S_IXUSR)
env = dict(os.environ, QS_SPOTIFY_BRIDGE_HOLD="1.5", QS_CAVA=fake)
proc = subprocess.Popen([sys.executable, os.path.join(HERE, "spotify-bridge.py"), "--port", str(port)],
                        stdout=subprocess.PIPE, text=True, env=env)
lines = []
threading.Thread(target=lambda: [lines.append(json.loads(l)) for l in proc.stdout], daemon=True).start()


def get(path):
    with urllib.request.urlopen(base + path, timeout=10) as r:
        return r.status, r.read().decode()


def post(path, body=b""):
    req = urllib.request.Request(base + path, data=body, method="POST")
    with urllib.request.urlopen(req, timeout=10) as r:
        return r.status, json.loads(r.read().decode() or "{}")


try:
    for _ in range(50):
        if any(l.get("type") == "ready" for l in lines):
            break
        time.sleep(0.1)
    check("ready", any(l.get("type") == "ready" for l in lines))

    # Nobody polling: not listening, and a restyle says so (to the caller AND the shell).
    st, body = get("/")
    check("liveness ok", st == 200 and json.loads(body)["ok"] is True)
    check("not listening at start", json.loads(body)["listening"] is False)
    st, r = post("/restyle")
    check("restyle answered", st == 200 and r["seq"] == 1)
    check("restyle says nobody listened", r["listening"] is False)
    time.sleep(0.2)
    told = [l for l in lines if l.get("type") == "restyle"]
    check("shell told of the restyle", len(told) == 1 and told[0]["listening"] is False)

    def ack():
        post("/", json.dumps({"type": "restyled", "sheets": 2, "loaded": 2, "ms": 40}).encode())

    # A poll arriving AFTER a request it didn't see is answered at once (the gap)…
    t0 = time.monotonic()
    st, body = get("/events")
    check("missed restyle delivered at once", st == 200 and json.loads(body)["restyle"] == 1
          and time.monotonic() - t0 < 1)
    # …and again, until the extension says it painted: answering a poll is not delivery.
    st, _ = get("/events")
    check("still pending until acknowledged", st == 200)
    ack()

    # Nothing new: the poll is held, then 204.
    t0 = time.monotonic()
    st, body = get("/events")
    held = time.monotonic() - t0
    check("idle poll is 204 once acknowledged", st == 204)
    check("idle poll was held", 1.2 < held < 3)

    # A poll held open is woken by a restyle, and that restyle reports listening.
    got = {}
    def poll():
        got["t0"] = time.monotonic()
        got["res"] = get("/events")
        got["t1"] = time.monotonic()
    th = threading.Thread(target=poll)
    th.start()
    time.sleep(0.3)
    check("listening while a poll is open", json.loads(get("/")[1])["listening"] is True)
    st, r = post("/restyle")
    th.join(5)
    check("listening restyle", r["seq"] == 2 and r["listening"] is True)
    check("held poll woken", got["res"][0] == 200 and json.loads(got["res"][1])["restyle"] == 2)
    check("woken promptly", got["t1"] - got["t0"] < 1.2)
    ack()

    # A DEAD waiter (a restarted Spotify's poll, still held here) can't swallow a
    # request: both held polls are answered, and it stays pending for the live one.
    dead, live = {}, {}
    def hold(into):
        into["res"] = get("/events")
    a = threading.Thread(target=hold, args=(dead,)); a.start()
    time.sleep(0.2)
    post("/restyle")
    a.join(5)
    st, body = get("/events")
    check("a request answered to a dead poll is still there for the live one",
          dead["res"][0] == 200 and st == 200 and json.loads(body)["restyle"] == 3)
    ack()

    # Two requests while nobody polled are worth one restyle, and an ack covers both.
    post("/restyle"); post("/restyle")
    st, body = get("/events")
    check("coalesced to newest", st == 200 and json.loads(body)["restyle"] == 5)
    ack()
    st, _ = get("/events")
    check("and only once", st == 204)

    # The poll as the extension really sends it: a no-cors POST with a text body.
    got = {}
    def poll_post():
        t0 = time.monotonic()
        got["res"] = post("/events", b"poll")
        got["took"] = time.monotonic() - t0
    th = threading.Thread(target=poll_post)
    th.start()
    time.sleep(0.3)
    check("POST poll counts as listening", json.loads(get("/")[1])["listening"] is True)
    post("/restyle")
    th.join(5)
    check("POST poll woken by a restyle", got["res"][0] == 200 and got["res"][1]["restyle"] == 6
          and got["took"] < 1.2)

    # The extension's report comes through to the shell like any other message.
    ack()
    time.sleep(0.2)
    rep = [l for l in lines if l.get("type") == "restyled"]
    check("report reaches the shell", len(rep) >= 1 and rep[-1]["loaded"] == 2 and "recvAt" in rep[-1])


    # ── /queue-op: the media page changes Spotify's queue ───────────────────────
    import importlib.util as _iu
    _spec = _iu.spec_from_file_location("bridge_q", os.path.join(HERE, "spotify-bridge.py"))
    qb = _iu.module_from_spec(_spec)
    _spec.loader.exec_module(qb)
    C = qb.clean_queue_op
    check("queue op: a reorder is kept", C({"op": "reorder", "uid": "a", "uri": "spotify:track:x", "anchorUid": "b", "where": "before"})
          == {"op": "reorder", "uid": "a", "uri": "spotify:track:x", "anchorUid": "b", "anchorUri": "", "where": "before"})
    check("queue op: a remove is kept", C({"op": "remove", "uid": "a"}) == {"op": "remove", "uid": "a", "uri": ""})
    check("queue op: an unknown op is refused", C({"op": "clear", "uid": "a"}) is None)
    check("queue op: a like names its track and a bool",
          C({"op": "like", "uri": "spotify:track:" + "a" * 22, "value": True}) == {"op": "like", "uid": "", "uri": "spotify:track:" + "a" * 22, "value": True})
    check("queue op: play starts the DJ and nothing else",
          C({"op": "play", "uri": "spotify:playlist:37i9dQZF1EYkqdzj48dyYq"}) == {"op": "play", "uid": "", "uri": "spotify:playlist:37i9dQZF1EYkqdzj48dyYq"}
          and C({"op": "play", "uri": "spotify:playlist:other"}) is None)
    check("queue op: a jam takes start, end or leave",
          C({"op": "jam", "value": "start"}) == {"op": "jam", "uid": "", "uri": "", "value": "start"}
          and C({"op": "jam", "value": "leave"}) is not None and C({"op": "jam", "value": "host"}) is None)
    check("queue op: open takes an album, artist, playlist or search only",
          C({"op": "open", "uri": "spotify:album:" + "a" * 22})["uri"] == "spotify:album:" + "a" * 22
          and C({"op": "open", "uri": "spotify:search:tyler%20the%20creator"}) is not None
          and C({"op": "open", "uri": "spotify:track:" + "a" * 22}) is None
          and C({"op": "open", "uri": "spotify:search:x\x01y"}) is None)
    check("queue op: Jam settings take a known setting",
          C({"op": "jamset", "what": "queueOnly", "value": False})["what"] == "queueOnly"
          and C({"op": "jamset", "what": "volume", "value": True})["value"] is True
          and C({"op": "jamset", "what": "remove", "member": "abc"})["member"] == "abc"
          and C({"op": "jamset", "what": "queueOnly", "value": "yes"}) is None
          and C({"op": "jamset", "what": "delete", "member": "abc"}) is None
          and C({"op": "jamset", "what": "remove", "member": ""}) is None)
    check("queue op: a lyrics retry names a track",
          C({"op": "lyrics", "uri": "spotify:track:" + "a" * 22}) is not None and C({"op": "lyrics", "uri": "spotify:album:" + "a" * 22}) is None)
    check("queue op: a like on something that is not a track is refused", C({"op": "like", "uri": "spotify:album:x", "value": True}) is None)
    check("queue op: a like without a bool is refused", C({"op": "like", "uri": "spotify:track:" + "a" * 22, "value": "yes"}) is None)
    check("queue op: no id is refused", C({"op": "remove"}) is None)
    check("queue op: a reorder needs an anchor and a side",
          C({"op": "reorder", "uid": "a"}) is None and C({"op": "reorder", "uid": "a", "anchorUid": "b", "where": "under"}) is None)
    check("queue op: an id that is not a string, or too long, is refused",
          C({"op": "remove", "uid": 5}) is None and C({"op": "remove", "uid": "x" * 65}) is None)
    check("queue op: extra fields are dropped", "evil" not in C({"op": "remove", "uid": "a", "evil": 1}))

    def post_raw(path, body):
        req = urllib.request.Request(base + path, data=body, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                return r.status, json.loads(r.read().decode() or "{}")
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read().decode() or "{}") if e.length else {}
    st, _ = post_raw("/queue-op", b"{not json")
    check("queue op: junk is a 400", st == 400)
    st, _ = post_raw("/queue-op", json.dumps({"op": "nuke", "uid": "a"}).encode())
    check("queue op: a bad op is a 400", st == 400)

    # Nobody polling: the extension is not there.
    time.sleep(5.2)   # let the last poll's "listening" window pass
    st, r = post_raw("/queue-op", json.dumps({"op": "remove", "uid": "a"}).encode())
    check("queue op: no extension is a 503", st == 503 and r.get("error") == "spotify-not-listening")

    # An extension that answers: a poll woken by the request, the mailbox, the report.
    out = {}
    def ask():
        out["res"] = post_raw("/queue-op", json.dumps({"op": "reorder", "uid": "a", "uri": "spotify:track:x",
                                                       "anchorUid": "b", "where": "after"}).encode())
    held = {}
    def hold_poll():
        held["res"] = get("/events")
    hp = threading.Thread(target=hold_poll); hp.start()
    time.sleep(0.3)
    ta = threading.Thread(target=ask); ta.start()
    hp.join(5)
    check("queue op: the held poll is woken", held["res"][0] == 200)
    st, css = get("/mailbox.css")
    import base64 as _b64, re as _re
    mail = json.loads(_b64.b64decode(_re.search(r'content:"([^"]*)"', css).group(1)))
    qop = mail.get("queueop") or {}
    check("queue op: it is in the mailbox", qop.get("op") == "reorder" and qop.get("uid") == "a"
          and qop.get("anchorUid") == "b" and qop.get("where") == "after" and "at" not in qop)
    post("/", json.dumps({"type": "queue-done", "seq": qop.get("seq"), "ok": True}).encode())
    ta.join(8)
    check("queue op: the caller gets the report", out["res"][0] == 200 and out["res"][1]["ok"] is True)
    time.sleep(0.2)
    check("queue op: the shell is told", any(l.get("type") == "queue-op" and l.get("ok") is True for l in lines))
    st, css = get("/mailbox.css")
    mail = json.loads(_b64.b64decode(_re.search(r'content:"([^"]*)"', css).group(1)))
    check("queue op: done means out of the mailbox", "queueop" not in mail)

    # A refusal from the extension is passed on, as a 502 with its reason.
    out = {}
    hp = threading.Thread(target=hold_poll); hp.start()
    time.sleep(0.3)
    ta = threading.Thread(target=ask); ta.start()
    hp.join(5)
    st, css = get("/mailbox.css")
    mail = json.loads(_b64.b64decode(_re.search(r'content:"([^"]*)"', css).group(1)))
    post("/", json.dumps({"type": "queue-done", "seq": mail["queueop"]["seq"], "ok": False, "error": "no such track"}).encode())
    ta.join(8)
    check("queue op: a refusal is a 502 with the reason", out["res"][0] == 502 and out["res"][1]["error"] == "no such track")

    # The queue snapshot passes through to the shell like an anchor.
    post("/", json.dumps({"type": "queue", "rev": "3", "next": []}).encode())
    time.sleep(0.2)
    check("queue snapshot reaches the shell", any(l.get("type") == "queue" and l.get("rev") == "3" for l in lines))

    # ── /spectrum: cava's frames, to whoever is listening ────────────────────
    import importlib.util
    spec = importlib.util.spec_from_file_location("bridge", os.path.join(HERE, "spotify-bridge.py"))
    bridge = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(bridge)
    check("frame parses to 32 values", bridge.parse_frame(";".join(["500"] * 32) + ";").count(",") == 31)
    check("frame clamps to 0..1", bridge.parse_frame(";".join(["5000"] * 32) + ";").split(",")[0] == "1.000")
    check("short frame refused", bridge.parse_frame("1;2;3;") is None)
    check("garbage frame refused", bridge.parse_frame(";".join(["x"] * 32)) is None)

    got = []
    with urllib.request.urlopen(base + "/spectrum", timeout=10) as r:
        check("spectrum is an event stream", r.headers.get("Content-Type") == "text/event-stream")
        check("spectrum is readable cross-origin", r.headers.get("Access-Control-Allow-Origin") == "*")
        while len(got) < 3:
            line = r.readline().decode().strip()
            if line.startswith("data: "):
                got.append(line[6:].split(","))
    check("three frames came", len(got) == 3)
    check("each is 32 bars", all(len(g) == 32 for g in got))
    check("the shape survives", got[0][0] == "0.000" and got[0][31] == "0.930")
    time.sleep(0.5)
    n = subprocess.run(["pgrep", "-f", fake], capture_output=True, text=True).stdout.split()
    check("cava stops when the last listener leaves", n == [])

    # ── /canvas: Spotify's clip, re-encoded into something its Chromium can show ──
    good = "https://canvaz.scdn.co/upload/licensor/7JGw/video/9f5e.cnvs.mp4"
    # ── Who may talk to it ─────────────────────────────────────────────────
    T = bridge.trusted_request
    check("trust: curl / scripts (no Origin)", T("127.0.0.1:47821", None))
    check("trust: localhost and [::1]", T("localhost:1", None) and T("[::1]:1", None))
    check("trust: Spotify's renderer", T("127.0.0.1:1", "https://xpui.app.spotify.com"))
    check("refuse: a web page", not T("127.0.0.1:1", "https://evil.example"))
    check("refuse: lookalike host", not T("127.0.0.1:1", "https://evilspotify.com"))
    check("refuse: http spotify", not T("127.0.0.1:1", "http://xpui.app.spotify.com"))
    check("refuse: sandboxed iframe", not T("127.0.0.1:1", "null"))
    check("refuse: DNS rebinding (Host)", not T("evil.example:47821", None))
    check("refuse: no Host", not T(None, None))
    def refused(method, path, origin=None, host=None):
        req = urllib.request.Request(base + path, data=b"{}" if method == "POST" else None, method=method)
        if origin: req.add_header("Origin", origin)
        if host: req.add_header("Host", host)
        try:
            urllib.request.urlopen(req, timeout=10)
            return False
        except urllib.error.HTTPError as e:
            return e.code == 403
    check("live: web page POST /play refused", refused("POST", "/play", origin="https://evil.example"))
    check("live: web page GET /events refused", refused("GET", "/events", origin="https://evil.example"))
    check("live: rebound GET refused", refused("GET", "/", host="evil.example:%d" % port))
    check("live: plain GET still answers", get("/")[0] == 200)
    check("canvas: a canvaz clip is accepted", bridge.canvas_source(good) == good)
    check("canvas: query and fragment dropped", bridge.canvas_source(good + "?a=1#b") == good)
    for bad in ["http://canvaz.scdn.co/a.mp4", "https://canvaz.scdn.co.evil.com/a.mp4",
                "https://evil.com/canvaz.scdn.co/a.mp4", "https://canvaz.scdn.co:8443/a.mp4",
                "https://user@canvaz.scdn.co/a.mp4", "https://canvaz.scdn.co/a.mp4.exe",
                "https://canvaz.scdn.co/../etc/a.mp4", "file:///etc/passwd", "", None,
                "https://canvaz.scdn.co/" + "a" * 600 + ".mp4", "https://127.0.0.1/a.mp4"]:
        check("canvas: refused %r" % (bad if not bad or len(bad) < 60 else bad[:40] + "…"),
              bridge.canvas_source(bad) is None)
    try:
        get("/canvas?src=" + urllib.parse.quote("https://evil.com/a.mp4"))
        check("canvas: a foreign src is a 400", False)
    except urllib.error.HTTPError as e:
        check("canvas: a foreign src is a 400", e.code == 400)

    # canvas_file, in-process: a fake download and a fake ffmpeg that logs its calls and
    # writes its output (the real encode is measured, not tested — it needs the network).
    import io, urllib.request as ur
    tmpd = tempfile.mkdtemp()
    bridge.CANVAS_DIR = os.path.join(tmpd, "cache")
    calls = os.path.join(tmpd, "calls")
    ff = os.path.join(tmpd, "fakeffmpeg")
    with open(ff, "w") as f:
        f.write('#!/bin/sh\necho "$*" >> "%s"\n'
                'case "$*" in *libsvtav1*) [ -n "$NO_AV1" ] && exit 1;; esac\n'
                'for a; do out="$a"; done; printf x > "$out"\n' % calls)
    os.chmod(ff, 0o755)
    bridge.FFMPEG_BIN = ff
    payload = {"size": 1000}
    class FakeResp(io.BytesIO):
        def __enter__(self): return self
        def __exit__(self, *a): return False
    real_open = ur.urlopen
    ur.urlopen = lambda url, timeout=0: FakeResp(b"m" * payload["size"])
    try:
        ncalls = lambda: len(open(calls).read().splitlines()) if os.path.exists(calls) else 0
        p, ctype, err = bridge.canvas_file(good)
        check("canvas: encoded to AVIF", p and p.endswith(".avif") and ctype == "image/avif" and not err)
        check("canvas: ffmpeg given the local file, not the URL",
              "http" not in open(calls).read() and "clip.mp4" in open(calls).read())
        n = ncalls()
        p2, _, _ = bridge.canvas_file(good)
        check("canvas: second ask is the cache", p2 == p and ncalls() == n)
        check("canvas: no temp dirs left", [x for x in os.listdir(bridge.CANVAS_DIR) if x.startswith(".")] == [])
        os.environ["NO_AV1"] = "1"
        p3, ctype3, _ = bridge.canvas_file(good.replace("9f5e", "aaaa"))
        check("canvas: no AV1 encoder falls back to WebP", p3 and p3.endswith(".webp") and ctype3 == "image/webp")
        del os.environ["NO_AV1"]
        payload["size"] = bridge.CANVAS_MAX + 1
        big = good.replace("9f5e", "bbbb")
        p4, _, err4 = bridge.canvas_file(big)
        check("canvas: an oversized download is refused", p4 is None and "larger" in err4)
        n = ncalls()
        p5, _, err5 = bridge.canvas_file(big)
        check("canvas: a failure is not retried at once", p5 is None and err5 == "failed recently" and ncalls() == n)

        # The raw clip for the shell's own player: never blocks, announces itself, no ffmpeg.
        payload["size"] = 2000
        sent = []
        real_emit = bridge.emit
        bridge.emit = sent.append
        try:
            vid = good.replace("9f5e", "cccc")
            n = ncalls()
            first = bridge.canvas_video_start(vid)
            for _ in range(100):
                if any(m.get("type") == "canvas-ready" for m in sent): break
                time.sleep(0.05)
            ready = [m for m in sent if m.get("type") == "canvas-ready"]
            check("video: first ask returns at once with no path", first == "")
            check("video: the fetch announces itself", len(ready) == 1 and ready[0]["canvas"] == vid
                  and ready[0]["canvasPath"] == bridge.canvas_video_path(vid))
            check("video: the clip is the untouched download", os.path.getsize(ready[0]["canvasPath"]) == 2000)
            check("video: no ffmpeg, no temp dirs", ncalls() == n
                  and [x for x in os.listdir(bridge.CANVAS_DIR) if x.startswith(".")] == [])
            check("video: second ask is the cache path", bridge.canvas_video_start(vid) == ready[0]["canvasPath"]
                  and len(sent) == 1)
            payload["size"] = bridge.CANVAS_MAX + 1
            sent.clear()
            bad = good.replace("9f5e", "dddd")
            bridge.canvas_video_start(bad)
            for _ in range(100):
                if sent: break
                time.sleep(0.05)
            check("video: an oversized clip is an error, not a file",
                  sent and sent[0]["type"] == "canvas-error" and not os.path.exists(bridge.canvas_video_path(bad)))
            time.sleep(0.2)
            check("video: a failure is not retried at once", bridge.canvas_video_start(bad) == "" and len(sent) == 1)
        finally:
            bridge.emit = real_emit
    finally:
        ur.urlopen = real_open

    # An anchor's `canvas` is a trust boundary: only a canvaz URL is carried on, and what is
    # carried is the cache's path, never a URL the shell could follow.
    def anchor_out(canvas):
        n = len(lines)
        post("/", json.dumps({"type": "anchor", "trackUri": "spotify:track:x", "canvas": canvas}).encode())
        for _ in range(50):
            if len(lines) > n: break
            time.sleep(0.05)
        return lines[-1]
    out = anchor_out("https://evil.example/a.mp4")
    check("anchor: a foreign canvas is dropped", out.get("canvas") == "" and out.get("canvasPath") == "")
    out = anchor_out(None)
    check("anchor: no canvas is empty strings", out.get("canvas") == "" and out.get("canvasPath") == "")

    # An empty POST to / is still refused (the anchor contract is unchanged).
    try:
        post("/")
        check("empty anchor refused", False)
    except urllib.error.HTTPError as e:
        check("empty anchor refused", e.code == 400)
finally:
    proc.terminate()
    proc.wait(5)

print("%d passed" % passed + (", %d FAILED" % failed if failed else ""))
sys.exit(1 if failed else 0)
