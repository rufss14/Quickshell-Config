#!/usr/bin/env python3
"""
test-bt-helper.py — tests for scripts/bt-helper.py's logic.

    python3 scripts/test-bt-helper.py

Fully mocked and safe: it imports the helper as a module and drives its pure
functions and the Prompts class with fake callbacks and timers. Nothing touches
D-Bus, BlueZ or obexd, and no agent is registered.
"""

import importlib.util
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("bt_helper", os.path.join(HERE, "bt-helper.py"))
bt = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bt)

passed = failed = 0


def check(name, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print("FAIL %s\n  got:  %r\n  want: %r" % (name, got, want))


# ── Addresses and paths ───────────────────────────────────────────────────────
check("address ok", bt.valid_address("F8:5C:7E:8A:11:95"), True)
check("address lower ok", bt.valid_address("f8:5c:7e:8a:11:95"), True)
check("address trailing junk", bt.valid_address("F8:5C:7E:8A:11:95\n"), False)
check("address not str", bt.valid_address(12), False)
check("path → address", bt.address_from_path("/org/bluez/hci0/dev_F8_5C_7E_8A_11_95"), "F8:5C:7E:8A:11:95")
check("path lower → upper", bt.address_from_path("/org/bluez/hci1/dev_f8_5c_7e_8a_11_95"), "F8:5C:7E:8A:11:95")
check("adapter path → ''", bt.address_from_path("/org/bluez/hci0"), "")
check("service path → ''", bt.address_from_path("/org/bluez/hci0/dev_F8_5C_7E_8A_11_95/sep1"), "")
check("None path", bt.address_from_path(None), "")

# ── PIN / passkey validation (the answers come from a text field) ─────────────
check("pin ok", bt.clean_pin("0000"), "0000")
check("pin alnum", bt.clean_pin("Ab12"), "Ab12")
check("pin empty", bt.clean_pin(""), None)
check("pin too long", bt.clean_pin("1" * 17), None)
check("pin space", bt.clean_pin("12 34"), None)
check("pin control", bt.clean_pin("12\n"), None)
check("pin non-ascii", bt.clean_pin("12é"), None)
check("pin not str", bt.clean_pin(1234), None)
check("passkey ok", bt.clean_passkey("482913"), 482913)
check("passkey leading zeros", bt.clean_passkey("000042"), 42)
check("passkey int", bt.clean_passkey(7), 7)
check("passkey trimmed", bt.clean_passkey(" 123 "), 123)
check("passkey 7 digits", bt.clean_passkey("1234567"), None)
check("passkey letters", bt.clean_passkey("12a4"), None)
check("passkey negative", bt.clean_passkey("-1"), None)
check("passkey bool", bt.clean_passkey(True), None)
check("fmt passkey pads", bt.fmt_passkey(42), "000042")
check("fmt passkey wraps", bt.fmt_passkey(1000042), "000042")

# ── Services and OPP ──────────────────────────────────────────────────────────
check("service a2dp", bt.service_name("0000110b-0000-1000-8000-00805f9b34fb"), "audio")
check("service hid", bt.service_name("00001124-0000-1000-8000-00805F9B34FB"), "input")
check("service unknown", bt.service_name("deadbeef-0000"), "a service")
check("opp yes", bt.has_opp(["0000110b-0000-1000-8000-00805f9b34fb", bt.OPP_UUID.upper()]), True)
check("opp no", bt.has_opp(["0000110b-0000-1000-8000-00805f9b34fb"]), False)
check("opp none", bt.has_opp(None), False)

# ── Files to send ─────────────────────────────────────────────────────────────
with tempfile.TemporaryDirectory() as d:
    f = os.path.join(d, "shot.png")
    open(f, "wb").write(b"x")
    link = os.path.join(d, "link.png")
    os.symlink(f, link)
    check("send path ok", bt.valid_send_path(f), os.path.realpath(f))
    check("send path symlink resolved", bt.valid_send_path(link), os.path.realpath(f))
    check("send path dir", bt.valid_send_path(d), None)
    check("send path relative", bt.valid_send_path("shot.png"), None)
    check("send path missing", bt.valid_send_path(os.path.join(d, "nope")), None)
    check("send path NUL", bt.valid_send_path(f + "\0x"), None)
    check("send path not str", bt.valid_send_path(None), None)

# ── Commands (the stdin trust boundary) ───────────────────────────────────────
P = lambda o: bt.parse_command(json.dumps(o))
check("cmd answer", P({"c": "answer", "id": 3, "ok": True, "value": "1234"}),
      {"c": "answer", "id": 3, "ok": True, "value": "1234"})
check("cmd answer default value", P({"c": "answer", "id": 3, "ok": False}),
      {"c": "answer", "id": 3, "ok": False, "value": ""})
check("cmd answer bool id", P({"c": "answer", "id": True, "ok": True}), None)
check("cmd answer string ok", P({"c": "answer", "id": 1, "ok": "yes"}), None)
check("cmd answer huge value", P({"c": "answer", "id": 1, "ok": True, "value": "x" * 65}), None)
check("cmd agent", P({"c": "agent", "on": False}), {"c": "agent", "on": False})
check("cmd agent bad", P({"c": "agent", "on": 1}), None)
check("cmd send", P({"c": "send", "id": 9, "address": "f8:5c:7e:8a:11:95", "path": "/tmp/a"}),
      {"c": "send", "id": 9, "address": "F8:5C:7E:8A:11:95", "path": "/tmp/a"})
check("cmd send bad address", P({"c": "send", "id": 9, "address": "x", "path": "/tmp/a"}), None)
check("cmd send no path", P({"c": "send", "id": 9, "address": "F8:5C:7E:8A:11:95"}), None)
check("cmd cancel", P({"c": "cancel", "id": 2}), {"c": "cancel", "id": 2})
check("cmd unknown", P({"c": "rm", "id": 2}), None)
check("cmd not object", bt.parse_command("[1,2]"), None)
check("cmd not json", bt.parse_command("{"), None)
check("cmd negative id", P({"c": "cancel", "id": -1}), None)

# ── Coalescer ─────────────────────────────────────────────────────────────────
c = bt.Coalescer()
check("coalesce first dirty schedules", c.update("A", {"rssi": -50}), True)
check("coalesce second does not", c.update("A", {"rssi": -60}), False)
check("coalesce other device does not", c.update("B", {"opp": True}), False)
c.update("A", {"opp": False})
check("coalesce drains latest merged", sorted(c.drain(), key=lambda d: d["address"]),
      [{"address": "A", "rssi": -60, "opp": False}, {"address": "B", "opp": True}])
check("coalesce empty after drain", c.drain(), [])
check("coalesce schedules again after drain", c.update("A", {"rssi": -1}), True)


# ── Prompts ───────────────────────────────────────────────────────────────────
class Fake:
    def __init__(self):
        self.out, self.timers, self.cancelled, self.replies = [], {}, [], []
        self.n = 0

    def emit(self, o):
        self.out.append(o)

    def schedule(self, s, fn):
        self.n += 1
        self.timers[self.n] = fn
        return self.n

    def unschedule(self, h):
        self.cancelled.append(h)
        self.timers.pop(h, None)

    def ok(self, *a):
        self.replies.append(("ok",) + a)

    def err(self, e):
        self.replies.append(("err", e))


def fresh():
    f = Fake()
    return f, bt.Prompts(f.emit, f.schedule, f.unschedule, rejected=lambda: "REJECTED")


f, p = fresh()
pid = p.ask("confirm", "AA:BB:CC:DD:EE:FF", f.ok, f.err, passkey="482913")
check("confirm emitted", f.out[-1],
      {"t": "prompt", "id": pid, "kind": "confirm", "address": "AA:BB:CC:DD:EE:FF", "passkey": "482913"})
check("confirm accepted", (p.answer(pid, True), f.replies, f.out[-1], f.cancelled),
      (True, [("ok",)], {"t": "prompt-end", "id": pid}, [1]))
check("answering twice is a no-op", p.answer(pid, True), False)

f, p = fresh()
pid = p.ask("confirm", "AA", f.ok, f.err)
p.answer(pid, False)
check("confirm rejected", f.replies, [("err", "REJECTED")])

f, p = fresh()
pid = p.ask("pin", "AA", f.ok, f.err)
p.answer(pid, True, "0000")
check("pin answered", f.replies, [("ok", "0000")])

f, p = fresh()
pid = p.ask("pin", "AA", f.ok, f.err)
p.answer(pid, True, "12 34")
check("invalid pin rejects instead of sending junk", f.replies, [("err", "REJECTED")])

f, p = fresh()
pid = p.ask("passkey", "AA", f.ok, f.err)
p.answer(pid, True, "004213")
check("passkey answered as int", f.replies, [("ok", 4213)])

f, p = fresh()
pid = p.ask("service", "AA", f.ok, f.err, service="audio")
f.timers[1]()                          # the timeout fires
check("expiry rejects and ends", (f.replies, f.out[-1], pid in p.pending),
      ([("err", "REJECTED")], {"t": "prompt-end", "id": pid}, False))

f, p = fresh()
a = p.ask("confirm", "AA", f.ok, f.err)
b = p.ask("authorize", "BB", f.ok, f.err)
p.cancel_all()
check("BlueZ cancel ends all without replying",
      (f.replies, [o for o in f.out if o["t"] == "prompt-end"], p.pending),
      ([], [{"t": "prompt-end", "id": a}, {"t": "prompt-end", "id": b}], {}))

f, p = fresh()
d1 = p.ask("display-passkey", "AA", passkey="123456", entered=0)
d2 = p.ask("display-passkey", "AA", passkey="123456", entered=3)
check("display prompt updated in place", (d1 == d2, f.out[-1]["entered"], len(p.pending)), (True, 3, 1))
check("display prompt can't be 'answered'", p.answer(d1, True), False)

f, p = fresh()
d = p.ask("display-pin", "AA", pin="0000")
c2 = p.ask("confirm", "AA", f.ok, f.err)
p.end_for("AA")
check("end_for closes only display prompts", (d in p.pending, c2 in p.pending), (False, True))

f, p = fresh()
d = p.ask("display-pin", "AA", pin="0000")
f.timers[1]()
check("display expiry replies to nobody", (f.replies, d in p.pending), ([], False))

print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
