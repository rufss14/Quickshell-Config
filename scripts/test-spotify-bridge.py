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
    finally:
        ur.urlopen = real_open

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
