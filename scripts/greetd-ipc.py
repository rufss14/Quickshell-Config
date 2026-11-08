#!/usr/bin/env python3
"""Speak greetd's login protocol for the QML greeter.

    python3 greetd-ipc.py

Reads commands on stdin and writes events on stdout, one JSON object per line.
Runs until greetd starts a session (at which point this process is replaced along
with the rest of the greeter) or until stdin closes.

── Why this exists as a process at all ───────────────────────────────────────
greetd's IPC is BINARY FRAMED — a native-endian u32 length followed by a JSON body,
over the unix socket named by $GREETD_SOCK. Quickshell's `Socket` is line/text
oriented and cannot express a length-prefixed frame, so QML cannot speak this
protocol no matter how it is coaxed. Exactly the same reason scripts/discord-rpc.py
exists, and this file deliberately mirrors its shape: framing happens here, and
everything above it gets to think in JSON lines.

── Why the greeter cannot just use PAM like the lock screen does ─────────────
modules/lock/LockScreen.qml authenticates with Quickshell's PamContext, directly.
A greeter cannot: it runs as the unprivileged `greeter` user, before any session
exists, and has no business holding a PAM handle for someone else's account. greetd
is the thing with that privilege. So the greeter ASKS greetd, and greetd runs the
PAM conversation on its behalf and hands back the prompts. Same conversation shape
(prompt → response → success/failure), completely different mechanism.

── The protocol, as specified ────────────────────────────────────────────────
Requests (we send):
    {"type": "create_session", "username": "…"}
    {"type": "post_auth_message_response", "response": "…"}   # response optional
    {"type": "start_session", "cmd": [...], "env": [...]}
    {"type": "cancel_session"}

Responses (greetd sends, exactly one per request):
    {"type": "success"}
    {"type": "error", "error_type": "auth_error"|"error", "description": "…"}
    {"type": "auth_message", "auth_message_type": "visible"|"secret"|"info"|"error",
     "auth_message": "Password: "}

It is STRICTLY request/response — one reply per request, in order, no unsolicited
events. That is why this file has no read thread and no nonce table, and why it is
so much shorter than the Discord one: there is nothing to correlate.

── The password ──────────────────────────────────────────────────────────────
Arrives on STDIN and is never an argument, never logged, never echoed back in an
event. Same rule scripts/discord-credentials.py is built around, for the same
reason: argv is world-readable in `ps` to every process on the machine. The only
place it exists here is one local variable, handed straight to the socket.
"""

import json
import os
import socket
import struct
import sys

# greetd's own docs say native-endian u32. "=I" is exactly that (standard size, no
# alignment padding); "I" alone would be native-endian too but is free to pad, which
# on a length prefix is a difference that would silently desynchronise the stream.
_HEADER = struct.Struct("=I")


def emit(**event):
    """One event, one line, flushed. QML reads these with SplitParser."""
    sys.stdout.write(json.dumps(event) + "\n")
    sys.stdout.flush()


class Greetd:
    def __init__(self, sock):
        self.sock = sock

    def request(self, payload):
        """Send one request, return its one response."""
        body = json.dumps(payload).encode("utf-8")
        self.sock.sendall(_HEADER.pack(len(body)) + body)
        return self._read()

    def _read(self):
        head = self._exact(_HEADER.size)
        (length,) = _HEADER.unpack(head)
        return json.loads(self._exact(length).decode("utf-8"))

    def _exact(self, n):
        """recv() is free to return short reads; a framed protocol is not."""
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise ConnectionError("greetd closed the connection")
            buf += chunk
        return buf


def report(response):
    """Turn one greetd response into one event for QML."""
    kind = response.get("type")

    if kind == "auth_message":
        # `secret` is the only one that must be masked. `info` and `error` are
        # informational and carry no response — the caller decides whether to answer
        # by looking at this, exactly as the lock screen checks responseRequired
        # before answering PAM.
        mtype = response.get("auth_message_type", "secret")
        emit(e="prompt", kind=mtype, text=response.get("auth_message", ""))

    elif kind == "success":
        emit(e="ok")

    elif kind == "error":
        # auth_error is a wrong password; error is a broken stack. Different reactions
        # from a person, so they stay distinguishable rather than collapsing into
        # "login failed".
        etype = response.get("error_type", "error")
        emit(e="error",
             kind="auth" if etype == "auth_error" else "other",
             text=response.get("description", ""))

    else:
        emit(e="error", kind="other", text="unrecognised response: %s" % kind)


def main():
    path = os.environ.get("GREETD_SOCK", "")
    if not path:
        # Not a crash: this is what running the greeter OUTSIDE greetd looks like,
        # which is exactly how it gets developed and tested. The UI shows the reason
        # rather than presenting a password box that cannot possibly work.
        emit(e="fatal", text="GREETD_SOCK is not set — not running under greetd")
        return 0

    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(path)
    except OSError as exc:
        emit(e="fatal", text="cannot connect to greetd: %s" % exc)
        return 0

    g = Greetd(sock)
    emit(e="ready")

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        try:
            msg = json.loads(line)
        except ValueError:
            emit(e="error", kind="other", text="bad command from the shell")
            continue

        cmd = msg.get("c")

        try:
            if cmd == "auth":
                report(g.request({"type": "create_session",
                                  "username": msg.get("user", "")}))

            elif cmd == "reply":
                # The password. Straight from stdin into the socket; it is not stored,
                # not logged, and not echoed back in the event that follows.
                #
                # `response` is OMITTED, not sent empty, when the command carries none.
                # Every auth_message needs a reply — including the `info` and `error`
                # ones, which carry no question — and greetd hands whatever we send
                # straight to PAM. An absent response is "there was nothing to answer";
                # an empty string is a real, empty answer. On a stack that treats those
                # differently (anything with a fingerprint or a message module in it),
                # sending "" to an informational message answers a question that was
                # never asked.
                reply = {"type": "post_auth_message_response"}
                if "response" in msg:
                    reply["response"] = msg["response"]
                report(g.request(reply))

            elif cmd == "start":
                resp = g.request({"type": "start_session",
                                  "cmd": msg.get("cmd", []),
                                  "env": msg.get("env", [])})
                report(resp)
                # A successful start_session means greetd is about to replace the
                # greeter. Nothing after this matters, and staying in the loop would
                # just hold the socket open across the handover.
                if resp.get("type") == "success":
                    return 0

            elif cmd == "cancel":
                report(g.request({"type": "cancel_session"}))

            else:
                emit(e="error", kind="other", text="unknown command: %s" % cmd)

        except (OSError, ValueError) as exc:
            emit(e="fatal", text="greetd connection lost: %s" % exc)
            return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
