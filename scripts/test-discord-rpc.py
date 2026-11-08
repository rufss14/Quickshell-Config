#!/usr/bin/env python3
"""Mock Discord RPC server — exercises discord-rpc.py end to end, locally.

Pre-seeds a token cache so the OAuth/HTTPS path is skipped, then plays the part of
Discord: handshake, command replies, and a scripted sequence of voice events.
Asserts that the helper's stdout snapshots track reality.
"""
import os, sys, json, socket, struct, subprocess, threading, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # derived, not literal: this config is published
tmp = tempfile.mkdtemp(prefix="discord-mock-")
run_dir, cfg_dir, cache_dir = (os.path.join(tmp, d) for d in ("run", "cfg", "cache"))
for d in (run_dir, os.path.join(cfg_dir, "quicktest"), os.path.join(cache_dir, "quicktest")):
    os.makedirs(d, exist_ok=True)

with open(os.path.join(cfg_dir, "quicktest", "discord-rpc.json"), "w") as f:
    json.dump({"clientId": "123", "clientSecret": "shh", "redirectUri": "http://localhost"}, f)
with open(os.path.join(cache_dir, "quicktest", "discord-token.json"), "w") as f:
    json.dump({"access_token": "tok", "expires_at": time.time() + 99999}, f)

SOCK = os.path.join(run_dir, "discord-ipc-0")
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(SOCK)
srv.listen(1)

USER_A = {"id": "111", "username": "alice", "discriminator": "0", "avatar": "abc"}
USER_B = {"id": "222", "username": "bob", "discriminator": "0", "avatar": None}
CHANNEL = {"id": "chan1", "guild_id": "g1", "name": "General", "type": 2,
           "voice_states": [
               {"nick": "Alice", "mute": False, "volume": 100,
                "voice_state": {"mute": False, "deaf": False, "self_mute": False,
                                "self_deaf": False}, "user": USER_A},
               {"nick": None, "mute": False, "volume": 80, "pan": {"left": 1, "right": 0.5},
                "voice_state": {"mute": False, "deaf": False, "self_mute": True,
                                "self_deaf": False}, "user": USER_B}]}
VOICE_SETTINGS = {"input": {"volume": 78.0, "device_id": "default",
                            "available_devices": [{"id": "default", "name": "Default"},
                                                  {"id": "usb-mic", "name": "USB Mic"}, {"name": "no id"}]},
                  "output": {"volume": 120.0, "device_id": "default",
                             "available_devices": [{"id": "default", "name": "Default"}]},
                  "mute": False, "deaf": False, "noise_suppression": True,
                  "echo_cancellation": False, "automatic_gain_control": True,
                  "mode": {"type": "VOICE_ACTIVITY"}}

received = []          # commands the helper sent us
lock = threading.Lock()


def send(conn, op, payload):
    body = json.dumps(payload).encode()
    conn.sendall(struct.pack("<II", op, len(body)) + body)


def reader(conn):
    buf = b""
    while True:
        try:
            chunk = conn.recv(65536)
        except OSError:
            return
        if not chunk:
            return
        buf += chunk
        while len(buf) >= 8:
            op, length = struct.unpack("<II", buf[:8])
            if len(buf) < 8 + length:
                break
            msg = json.loads(buf[8:8 + length].decode())
            buf = buf[8 + length:]

            if op == 0:                                    # HANDSHAKE
                send(conn, 1, {"cmd": "DISPATCH", "evt": "READY",
                               "data": {"v": 1, "user": {"id": "me"}}})
                continue

            cmd, nonce = msg.get("cmd"), msg.get("nonce")
            with lock:
                received.append(msg)

            reply = {}
            if cmd == "GET_VOICE_SETTINGS":
                reply = VOICE_SETTINGS
            elif cmd == "GET_SELECTED_VOICE_CHANNEL":
                reply = CHANNEL
            elif cmd == "GET_GUILD":
                reply = {"id": "g1", "name": "Gaming Lounge"}
            elif cmd == "SET_USER_VOICE_SETTINGS":
                # Discord answers with the person's settings as it now holds them.
                reply = dict({"volume": 100, "mute": False, "pan": {"left": 1, "right": 1}},
                             **(msg.get("args") or {}))
            send(conn, 1, {"cmd": cmd, "data": reply, "evt": None, "nonce": nonce})


env = dict(os.environ, XDG_RUNTIME_DIR=run_dir, XDG_CONFIG_HOME=cfg_dir,
           XDG_CACHE_HOME=cache_dir, XDG_STATE_HOME=os.path.join(cfg_dir, "..", "state"))
proc = subprocess.Popen([sys.executable, os.path.join(ROOT, "scripts/discord-rpc.py")],
                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE, env=env, text=True, bufsize=1)

conn, _ = srv.accept()
threading.Thread(target=reader, args=(conn,), daemon=True).start()

snapshots = []
def collect():
    for line in proc.stdout:
        try:
            obj = json.loads(line)
        except ValueError:
            continue
        if obj.get("t") == "state":
            snapshots.append(obj)
threading.Thread(target=collect, daemon=True).start()


def wait(pred, what, timeout=5):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if snapshots and pred(snapshots[-1]):
            return snapshots[-1]
        time.sleep(0.02)
    print("FAIL: %s" % what)
    print("  last snapshot: %s" % (snapshots[-1] if snapshots else None))
    print("  stderr: %s" % proc.stderr.read() if proc.poll() else "")
    sys.exit(1)


def ok(msg):
    print("  ok  %s" % msg)


print("── setup ──")
s = wait(lambda s: s["inCall"] and len(s["users"]) == 2, "joined channel with 2 users")
assert s["channel"]["name"] == "General", s["channel"]
ok("in call, channel name resolved")
s = wait(lambda s: s["channel"]["guild"] == "Gaming Lounge", "guild name resolved async")
ok("guild name resolved via async GET_GUILD")
assert s["inputVolume"] == 78 and s["outputVolume"] == 120, s
ok("voice settings applied (input 78, output 120)")
names = [u["name"] for u in s["users"]]
assert names == ["Alice", "bob"], names
ok("participants sorted, nick preferred over username: %s" % names)
assert s["users"][1]["avatar"].startswith("https://cdn.discordapp.com/embed/avatars/"), s["users"][1]
ok("default avatar for user with no avatar set")
assert s["users"][1]["pan"] == -0.5 and s["users"][0]["pan"] == 0, s["users"]
ok("pan {left 1, right 0.5} → balance -0.5; none → 0")
assert s["processing"] == {"noise": True, "echo": False, "agc": True}, s["processing"]
assert s["inputMode"] == "VOICE_ACTIVITY" and s["inputDevice"] == "default", s
assert [d["id"] for d in s["inputDevices"]] == ["default", "usb-mic"], s["inputDevices"]
ok("processing, input mode and devices (an id-less device dropped)")

with lock:
    subs = {(m.get("cmd"), m.get("evt")) for m in received if m.get("cmd") in ("SUBSCRIBE",)}
for evt in ("VOICE_SETTINGS_UPDATE", "VOICE_CHANNEL_SELECT", "VOICE_CONNECTION_STATUS",
            "SPEAKING_START", "VOICE_STATE_UPDATE"):
    assert ("SUBSCRIBE", evt) in subs, (evt, subs)
ok("subscribed to global + per-channel events")

print("── events ──")
send(conn, 1, {"cmd": "DISPATCH", "evt": "SPEAKING_START",
               "data": {"user_id": "111", "channel_id": "chan1"}})
s = wait(lambda s: any(u["id"] == "111" and u["speaking"] for u in s["users"]), "speaking")
ok("SPEAKING_START tracked")

send(conn, 1, {"cmd": "DISPATCH", "evt": "VOICE_CONNECTION_STATUS",
               "data": {"state": "VOICE_CONNECTED", "average_ping": 32.4}})
s = wait(lambda s: s["status"] == "VOICE_CONNECTED" and s["ping"] == 32, "connection status")
ok("VOICE_CONNECTION_STATUS → status + ping")

send(conn, 1, {"cmd": "DISPATCH", "evt": "VOICE_SETTINGS_UPDATE",
               "data": {"mute": True, "deaf": False}})
s = wait(lambda s: s["mute"], "mute event")
ok("VOICE_SETTINGS_UPDATE → mute")

send(conn, 1, {"cmd": "DISPATCH", "evt": "VOICE_STATE_DELETE",
               "data": {"user": USER_B, "voice_state": {}}})
s = wait(lambda s: len(s["users"]) == 1, "user left")
ok("VOICE_STATE_DELETE removes participant")

# THE regression this rewrite exists for: a channel switch arrives as an event, and
# the handler re-reads the channel. With the old blocking command() that was a
# BlockingIOError on a non-blocking socket and the helper died right here.
print("── channel switch (the async regression) ──")
CHANNEL["name"] = "Gaming"
CHANNEL["id"] = "chan2"
send(conn, 1, {"cmd": "DISPATCH", "evt": "VOICE_CHANNEL_SELECT",
               "data": {"channel_id": "chan2", "guild_id": "g1"}})
s = wait(lambda s: s["channel"] and s["channel"]["name"] == "Gaming", "channel switch")
ok("VOICE_CHANNEL_SELECT re-read the channel without blocking")
assert proc.poll() is None, "helper died"
ok("helper still alive")

with lock:
    unsubs = {(m.get("cmd"), m.get("evt"), (m.get("args") or {}).get("channel_id"))
              for m in received if m.get("cmd") == "UNSUBSCRIBE"}
assert ("UNSUBSCRIBE", "SPEAKING_START", "chan1") in unsubs, unsubs
ok("unsubscribed old channel's per-channel events")

print("── commands in ──")
before = len(received)
proc.stdin.write(json.dumps({"c": "mute", "v": True}) + "\n")
proc.stdin.write(json.dumps({"c": "outputVolume", "v": 150}) + "\n")
proc.stdin.write(json.dumps({"c": "userVolume", "id": "111", "v": 200}) + "\n")
proc.stdin.write(json.dumps({"c": "disconnect"}) + "\n")
proc.stdin.write("not json at all\n")
proc.stdin.flush()
time.sleep(0.6)
with lock:
    new = received[before:]
by_cmd = {m["cmd"]: m.get("args") for m in new}
assert by_cmd.get("SET_VOICE_SETTINGS") is not None, new
assert by_cmd["SET_USER_VOICE_SETTINGS"] == {"user_id": "111", "volume": 200}, by_cmd
assert by_cmd["SELECT_VOICE_CHANNEL"] == {"channel_id": None, "force": True}, by_cmd
ok("mute / outputVolume / userVolume / disconnect all mapped correctly")
s = wait(lambda s: any(u["id"] == "111" and u["volume"] == 200 for u in s["users"]),
         "user volume from the reply")
ok("SET_USER_VOICE_SETTINGS reply → that person's volume")

proc.stdin.write(json.dumps({"c": "userMute", "id": "111", "v": True}) + "\n")
proc.stdin.flush()
s = wait(lambda s: any(u["id"] == "111" and u["mute"] for u in s["users"]), "user mute")
with lock:
    sets = [m.get("args") for m in received if m.get("cmd") == "SET_USER_VOICE_SETTINGS"]
assert {"user_id": "111", "mute": True} in sets, sets
ok("userMute → SET_USER_VOICE_SETTINGS {mute}, reply → that person's mute")
assert proc.poll() is None
ok("malformed stdin line ignored, helper alive")

before = len(received)
for c in ({"c": "processing", "key": "echo", "v": True},
          {"c": "processing", "key": "rm -rf", "v": True},       # not a known switch
          {"c": "inputMode", "v": "PUSH_TO_TALK"},
          {"c": "inputMode", "v": "SOMETHING_ELSE"},
          {"c": "inputDevice", "v": "usb-mic"},
          {"c": "inputDevice", "v": "not-listed"},
          {"c": "userPan", "id": "111", "v": 0.25}):
    proc.stdin.write(json.dumps(c) + "\n")
proc.stdin.flush()
s = wait(lambda s: any(u["id"] == "111" and u["pan"] == 0.25 for u in s["users"]), "user pan")
with lock:
    sent = [(m["cmd"], m.get("args")) for m in received[before:]]
voice = [a for c, a in sent if c == "SET_VOICE_SETTINGS"]
assert voice == [{"echo_cancellation": True}, {"mode": {"type": "PUSH_TO_TALK"}},
                 {"input": {"device_id": "usb-mic"}}], voice
ok("processing / inputMode / inputDevice mapped; unknown key, mode and device refused")
assert ("SET_USER_VOICE_SETTINGS", {"user_id": "111", "pan": {"left": 0.75, "right": 1.0}}) in sent, sent
ok("userPan 0.25 → pan {left 0.75, right 1}, reply → balance 0.25")

print("── leaving the call ──")
send(conn, 1, {"cmd": "DISPATCH", "evt": "VOICE_CHANNEL_SELECT",
               "data": {"channel_id": None, "guild_id": None}})
# Server replies null for GET_SELECTED_VOICE_CHANNEL now.
CHANNEL.clear()
s = wait(lambda s: not s["inCall"], "left call")
assert s["users"] == [], s
ok("leaving clears channel and participants")

print("── Discord quits ──")
# Real Discord takes its socket FILE with it when it exits. Leaving `srv` listening
# would let the helper reconnect into a backlog nobody accepts, which is a different
# scenario (a hung Discord) and takes a handshake timeout to notice.
conn.shutdown(socket.SHUT_RDWR)   # close() can't send FIN while a thread blocks in recv()
conn.close()
srv.close()
os.unlink(SOCK)
s = wait(lambda s: not s["connected"], "disconnected", timeout=10)
ok("socket close → connected false, reconnect loop entered")
assert proc.poll() is None
ok("helper survived Discord quitting")

proc.stdin.close()
proc.wait(timeout=5)
ok("stdin EOF → clean exit (rc=%s)" % proc.returncode)
print("\nALL PASSED")
