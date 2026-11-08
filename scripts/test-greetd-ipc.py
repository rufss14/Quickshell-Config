#!/usr/bin/env python3
"""Exercise greetd-ipc.py against a FAKE greetd. Safe to run at any time.

    python3 scripts/test-greetd-ipc.py

Stands up a unix socket that speaks greetd's wire protocol, points GREETD_SOCK at
it, and drives the real greetd-ipc.py through every path the greeter can take:
successful login, wrong password, a broken PAM stack, informational prompts, a
missing socket, and a greetd that hangs up mid-conversation.

── Why this is the test that matters ─────────────────────────────────────────
The component under test is the one standing between you and your machine. Testing
it against the REAL greetd means either being at the login screen (where a failure
is a lockout) or running a second greetd (which wants the seat). Neither is a thing
to do casually, so the protocol is verified here instead — the framing, the
request/response pairing and the event mapping are all wire-level facts that a fake
greetd can assert on exactly as well as a real one.

What this canNOT prove is that greetd accepts our session command, or that PAM on
this machine behaves as expected. That is what the staged rollout is for.
"""

import json
import os
import socket
import struct
import subprocess
import sys
import tempfile
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
CLIENT = os.path.join(HERE, "greetd-ipc.py")
HEADER = struct.Struct("=I")

PASSWORD = "hunter2-not-a-real-password"

failures = []


def check(name, got, want):
    if got == want:
        print("  ok   %s" % name)
    else:
        print("  FAIL %s\n         got:  %r\n         want: %r" % (name, got, want))
        failures.append(name)


class FakeGreetd(threading.Thread):
    """A greetd that follows `script`: a list of (expected_request, response)."""

    def __init__(self, path, script, hangup_after=None):
        super().__init__(daemon=True)
        self.path = path
        self.script = script
        self.hangup_after = hangup_after
        self.seen = []
        self.srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.srv.bind(path)
        self.srv.listen(1)

    def run(self):
        conn, _ = self.srv.accept()
        try:
            for i, (_, response) in enumerate(self.script):
                head = self._exact(conn, HEADER.size)
                if head is None:
                    return
                (n,) = HEADER.unpack(head)
                self.seen.append(json.loads(self._exact(conn, n).decode()))

                if self.hangup_after is not None and i == self.hangup_after:
                    conn.close()
                    return

                body = json.dumps(response).encode()
                conn.sendall(HEADER.pack(len(body)) + body)
        except OSError:
            pass
        finally:
            try:
                conn.close()
            except OSError:
                pass

    @staticmethod
    def _exact(conn, n):
        buf = b""
        while len(buf) < n:
            chunk = conn.recv(n - len(buf))
            if not chunk:
                return None
            buf += chunk
        return buf


def run_client(script, commands, hangup_after=None, set_sock=True):
    """Drive greetd-ipc.py; return (events, requests the fake greetd received)."""
    tmp = tempfile.mkdtemp(prefix="greetd-test-")
    path = os.path.join(tmp, "sock")

    server = None
    if set_sock:
        server = FakeGreetd(path, script, hangup_after)
        server.start()

    env = dict(os.environ)
    if set_sock:
        env["GREETD_SOCK"] = path
    else:
        env.pop("GREETD_SOCK", None)

    proc = subprocess.run(
        [sys.executable, CLIENT],
        input="".join(json.dumps(c) + "\n" for c in commands),
        capture_output=True, text=True, env=env, timeout=15,
    )

    if server:
        server.join(timeout=5)

    events = [json.loads(l) for l in proc.stdout.splitlines() if l.strip()]
    return events, (server.seen if server else []), proc


def test_successful_login():
    print("\n── a login that works ──")
    events, seen, _ = run_client(
        script=[
            (None, {"type": "auth_message", "auth_message_type": "secret",
                    "auth_message": "Password: "}),
            (None, {"type": "success"}),
            (None, {"type": "success"}),
        ],
        commands=[
            {"c": "auth", "user": "rufss"},
            {"c": "reply", "response": PASSWORD},
            {"c": "start", "cmd": ["/usr/bin/start-hyprland"], "env": []},
        ],
    )

    check("ready first", events[0], {"e": "ready"})
    check("password prompt relayed",
          events[1], {"e": "prompt", "kind": "secret", "text": "Password: "})
    check("auth accepted", events[2], {"e": "ok"})
    check("session started", events[3], {"e": "ok"})

    check("create_session carried the username",
          seen[0], {"type": "create_session", "username": "rufss"})
    check("password went to greetd verbatim",
          seen[1], {"type": "post_auth_message_response", "response": PASSWORD})
    check("start_session carried the command",
          seen[2], {"type": "start_session",
                    "cmd": ["/usr/bin/start-hyprland"], "env": []})


def test_password_never_leaks():
    print("\n── the password never comes back out ──")
    events, _, proc = run_client(
        script=[
            (None, {"type": "auth_message", "auth_message_type": "secret",
                    "auth_message": "Password: "}),
            (None, {"type": "error", "error_type": "auth_error",
                    "description": "Authentication failure"}),
        ],
        commands=[
            {"c": "auth", "user": "rufss"},
            {"c": "reply", "response": PASSWORD},
        ],
    )
    blob = json.dumps(events) + proc.stderr
    check("absent from every event and from stderr", PASSWORD in blob, False)


def test_wrong_password():
    print("\n── a wrong password ──")
    events, _, _ = run_client(
        script=[
            (None, {"type": "auth_message", "auth_message_type": "secret",
                    "auth_message": "Password: "}),
            (None, {"type": "error", "error_type": "auth_error",
                    "description": "Authentication failure"}),
        ],
        commands=[
            {"c": "auth", "user": "rufss"},
            {"c": "reply", "response": "wrong"},
        ],
    )
    check("reported as an AUTH error, not a broken stack",
          events[2], {"e": "error", "kind": "auth", "text": "Authentication failure"})


def test_broken_stack():
    print("\n── a broken PAM stack ──")
    events, _, _ = run_client(
        script=[(None, {"type": "error", "error_type": "error",
                        "description": "PAM: no such service"})],
        commands=[{"c": "auth", "user": "rufss"}],
    )
    check("distinguished from a wrong password",
          events[1], {"e": "error", "kind": "other", "text": "PAM: no such service"})


def test_info_prompt():
    print("\n── an informational message (fingerprint stacks emit these) ──")
    events, seen, _ = run_client(
        script=[
            (None, {"type": "auth_message", "auth_message_type": "info",
                    "auth_message": "Touch the sensor"}),
            (None, {"type": "success"}),
        ],
        commands=[
            {"c": "auth", "user": "rufss"},
            {"c": "reply"},                       # no `response` key at all
        ],
    )
    check("relayed with its kind intact so the UI can tell it apart",
          events[1], {"e": "prompt", "kind": "info", "text": "Touch the sensor"})
    # An info message asked nothing. Acknowledging it must not put an empty answer
    # into the PAM conversation — the field is omitted, not sent as "".
    check("acknowledged with no `response` field",
          seen[1], {"type": "post_auth_message_response"})


def test_retry_after_failure():
    print("\n── a typo, then the right password (the sequence Greet.qml drives) ──")
    events, seen, _ = run_client(
        script=[
            (None, {"type": "auth_message", "auth_message_type": "secret",
                    "auth_message": "Password: "}),
            (None, {"type": "error", "error_type": "auth_error",
                    "description": "Authentication failure"}),
            (None, {"type": "success"}),          # the cancel
            (None, {"type": "auth_message", "auth_message_type": "secret",
                    "auth_message": "Password: "}),
            (None, {"type": "success"}),          # auth accepted
            (None, {"type": "success"}),          # session started
        ],
        commands=[
            {"c": "auth",  "user": "rufss"},
            {"c": "reply", "response": "wrong"},
            {"c": "cancel"},
            {"c": "auth",  "user": "rufss"},
            {"c": "reply", "response": PASSWORD},
            {"c": "start", "cmd": ["/usr/bin/start-hyprland"], "env": []},
        ],
    )

    # The point of the test. greetd leaves the failed session half-open, and a second
    # create_session on top of it is refused — so a greeter that does not cancel reads
    # as having locked you out permanently after one typo. This asserts the cancel is
    # actually on the wire, in the right place.
    check("the failed session is cancelled before retrying",
          seen[2], {"type": "cancel_session"})
    check("the retry is a fresh create_session",
          seen[3], {"type": "create_session", "username": "rufss"})

    # Six requests, six replies, in order. Greet.qml pairs `ok` with what it was a
    # reply TO by queue position alone, so a protocol that ever answered out of order
    # would take "the cancel worked" for "the password was right".
    check("one reply per request, in order",
          [e["e"] for e in events],
          ["ready", "prompt", "error", "ok", "prompt", "ok", "ok"])


def test_no_socket():
    print("\n── run outside greetd (how it gets developed) ──")
    events, _, proc = run_client(script=[], commands=[], set_sock=False)
    check("says why instead of offering a dead password box",
          events[0]["e"], "fatal")
    check("exits 0 — not running under greetd is a state, not a crash",
          proc.returncode, 0)


def test_hangup():
    print("\n── greetd hangs up mid-conversation ──")
    events, _, _ = run_client(
        script=[
            (None, {"type": "auth_message", "auth_message_type": "secret",
                    "auth_message": "Password: "}),
            (None, {"type": "success"}),
        ],
        commands=[
            {"c": "auth", "user": "rufss"},
            {"c": "reply", "response": PASSWORD},
        ],
        hangup_after=1,
    )
    check("reported as fatal rather than hanging", events[-1]["e"], "fatal")


def main():
    print("greetd-ipc.py — against a fake greetd, no real login touched")
    test_successful_login()
    test_password_never_leaks()
    test_wrong_password()
    test_broken_stack()
    test_info_prompt()
    test_retry_after_failure()
    test_no_socket()
    test_hangup()

    print()
    if failures:
        print("%d FAILED: %s" % (len(failures), ", ".join(failures)))
        return 1
    print("all passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
