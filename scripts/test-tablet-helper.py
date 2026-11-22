#!/usr/bin/env python3
"""
test-tablet-helper.py: tests for scripts/tablet-helper.py's logic.

    python3 scripts/test-tablet-helper.py

Safe: it imports the helper as a module and drives its pure parts (the capabilities bitmap, discovery
over a fake sysfs tree, the event decoder, the pen's report). No /dev/input node is opened, no process
is spawned. The capability strings are the real ones from a Wacom Intuos S (CTL-4100).
"""

import importlib.util
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("tablet_helper", os.path.join(HERE, "tablet-helper.py"))
th = importlib.util.module_from_spec(spec)
spec.loader.exec_module(th)

passed = failed = 0


def check(name, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print("FAIL %s\n  got:  %r\n  want: %r" % (name, got, want))


PEN_KEY, PEN_ABS = "1e01 0 0 0 0 0", "10003000003"
PAD_KEY, PAD_ABS = "800 f 0 0 0 0", "10000000003"

# ── The bitmap ────────────────────────────────────────────────────────────────
check("ioctl number of EVIOCGABS(ABS_X)", th._ioc_read(0x40, 24), 0x80184540)
check("bitmap: BTN_TOOL_PEN set", th.has_bit(th.parse_caps(PEN_KEY), th.BTN_TOOL_PEN), True)
check("bitmap: BTN_TOUCH set", th.has_bit(th.parse_caps(PEN_KEY), th.BTN_TOUCH), True)
check("bitmap: BTN_TOOL_RUBBER not set (this pen has no eraser)", th.has_bit(th.parse_caps(PEN_KEY), th.BTN_TOOL_RUBBER), False)
check("bitmap: pen abs has pressure", th.has_bit(th.parse_caps(PEN_ABS), th.ABS_PRESSURE), True)
check("bitmap: pen abs has no tilt", th.has_bit(th.parse_caps(PEN_ABS), th.ABS_TILT_X), False)
check("bitmap: garbage is empty", th.parse_caps("zz 1"), 0)
check("bitmap: nothing is empty", th.parse_caps(""), 0)
check("pad keys of the Intuos S", th.pad_codes(th.parse_caps(PAD_KEY)), [256, 257, 258, 259])
check("a pen has no pad keys", th.pad_codes(th.parse_caps(PEN_KEY)), [])
check("eight pad keys", len(th.pad_codes(th.parse_caps("800 ff 0 0 0 0"))), 8)

# ── Classification ────────────────────────────────────────────────────────────
check("pen", th.classify(th.parse_caps(PEN_KEY), th.parse_caps(PEN_ABS)), "pen")
check("pad", th.classify(th.parse_caps(PAD_KEY), th.parse_caps(PAD_ABS)), "pad")
check("a keyboard is neither", th.classify(th.parse_caps("ffffffffffffffff fffffffffffffffe 0 0"), 0), None)
check("a tool with no pressure is not a pen", th.classify(th.parse_caps(PEN_KEY), th.parse_caps("3")), None)
check("a gamepad looks like a pad (the pen pairing drops it)", th.classify(th.parse_caps("1000000000000 0 0 0 0"), 0), "pad")

# ── Names and the node check ──────────────────────────────────────────────────
check("hyprland name", th.hypr_name("Wacom Intuos S Pen"), "wacom-intuos-s-pen")
check("node ok", th.valid_node("/dev/input/event25"), True)
check("node: trailing newline", th.valid_node("/dev/input/event25\n"), False)
check("node: elsewhere", th.valid_node("/etc/shadow"), False)
check("node: climbing out", th.valid_node("/dev/input/event1/../../x"), False)
check("node: not a string", th.valid_node(None), False)
check("udev properties", th.parse_udev("ID_MODEL=Intuos_S\nID_INPUT_WIDTH_MM=152\nnoise"), {"ID_MODEL": "Intuos_S", "ID_INPUT_WIDTH_MM": "152"})

# ── Discovery over a fake sysfs ───────────────────────────────────────────────

def node(root, n, name, key, absb, phys, uniq=""):
    d = os.path.join(root, n, "device")
    os.makedirs(os.path.join(d, "capabilities"))
    for rel, text in (("name", name), ("phys", phys), ("uniq", uniq),
                      ("capabilities/key", key), ("capabilities/abs", absb)):
        with open(os.path.join(d, rel), "w") as f:
            f.write(text + "\n")


def udev(n):
    return "ID_MODEL=Intuos_S\nID_INPUT_WIDTH_MM=152\nID_INPUT_HEIGHT_MM=95\n" if n.endswith("event25") else \
           "ID_INPUT_WIDTH_MM=300\nID_INPUT_HEIGHT_MM=200\n"


with tempfile.TemporaryDirectory() as root:
    node(root, "event25", "Wacom Intuos S Pen", PEN_KEY, PEN_ABS, "usb-0000:01:00.0-2/input0", "1DH")
    node(root, "event26", "Wacom Intuos S Pad", PAD_KEY, PAD_ABS, "usb-0000:01:00.0-2/input0", "1DH")
    node(root, "event3", "Keyboard", "ffffffffffffffff fffffffffffffffe 0 0", "0", "usb-1/input0")
    node(root, "event7", "Some Gamepad", "1000000000000 0 0 0 0", "0", "usb-9/input0")
    t = th.discover(root, udev, lambda n: not n.endswith("event26"))
    check("one tablet", len(t), 1)
    check("tablet: names", (t[0]["name"], t[0]["hypr"], t[0]["model"]), ("Wacom Intuos S Pen", "wacom-intuos-s-pen", "Intuos S"))
    check("tablet: nodes", (t[0]["pen"], t[0]["pad"]), ("/dev/input/event25", "/dev/input/event26"))
    check("tablet: size", (t[0]["widthMm"], t[0]["heightMm"]), (152.0, 95.0))
    check("tablet: keys", t[0]["keys"], 4)
    check("tablet: one unreadable node means no access", t[0]["access"], False)
    t2 = th.discover(root, udev, lambda n: True)
    check("tablet: access when every node reads", t2[0]["access"], True)

with tempfile.TemporaryDirectory() as root:
    node(root, "event4", "Pen A", PEN_KEY, PEN_ABS, "usb-1/input0", "A")
    node(root, "event5", "Pad A", PAD_KEY, PAD_ABS, "usb-1/input0", "A")
    node(root, "event8", "Pen B", PEN_KEY, PEN_ABS, "usb-2/input0", "B")
    t = th.discover(root, lambda n: "", lambda n: True)
    check("two tablets", [x["name"] for x in t], ["Pen A", "Pen B"])
    check("each keeps its own pad", [x["pad"] for x in t], ["/dev/input/event5", ""])
    check("a pen alone has no keys", [x["keys"] for x in t], [4, 0])
    check("no udev data means size 0 (the shell drops it)", [x["widthMm"] for x in t], [0.0, 0.0])

check("a missing sysfs is no tablets", th.discover("/nonexistent-" + str(os.getpid()), udev, lambda n: True), [])

# ── The decoder ───────────────────────────────────────────────────────────────

def ev(t, c, v):
    return th.EVENT.pack(0, 0, t, c, v)


check("event size", th.EVENT.size, 24)
blob = ev(3, 0, 100) + ev(3, 1, 200) + ev(0, 0, 0)
d = th.Decoder()
check("whole events", d.feed(blob), [(3, 0, 100), (3, 1, 200), (0, 0, 0)])
d = th.Decoder()
got = d.feed(blob[:30]) + d.feed(blob[30:31]) + d.feed(blob[31:])
check("events split across reads", got, [(3, 0, 100), (3, 1, 200), (0, 0, 0)])
d = th.Decoder()
check("a negative value", d.feed(ev(3, 0x1A, -20)), [(3, 0x1A, -20)])
check("nothing in, nothing out", th.Decoder().feed(b""), [])

# ── The pen ───────────────────────────────────────────────────────────────────
RANGES = {th.ABS_X: (0, 15200), th.ABS_Y: (0, 9500), th.ABS_PRESSURE: (0, 4095), th.ABS_DISTANCE: (0, 31)}


def feed(pen, *events):
    done = False
    for e in events:
        done = pen.apply(*e) or done
    return done


p = th.Pen(RANGES)
check("no report before SYN_REPORT", feed(p, (3, 0, 7600), (3, 1, 4750), (1, th.BTN_TOOL_PEN, 1)), False)
check("report on SYN_REPORT", feed(p, (0, 0, 0)), True)
r = p.report()
check("position is 0..1", (r["x"], r["y"]), (0.5, 0.5))
check("in proximity, not touching", (r["in"], r["touch"], r["tool"]), (True, False, "pen"))
check("no tilt without the axes", "tx" in r, False)
feed(p, (3, th.ABS_PRESSURE, 2048), (1, th.BTN_TOUCH, 1), (1, th.BTN_STYLUS, 1), (0, 0, 0))
r = p.report()
check("pressure", r["p"], round(2048 / 4095, 4))
check("touch and the first button", (r["touch"], r["b1"], r["b2"]), (True, True, False))
feed(p, (1, th.BTN_STYLUS, 0), (1, th.BTN_STYLUS2, 1), (1, th.BTN_TOUCH, 0), (0, 0, 0))
r = p.report()
check("buttons release", (r["touch"], r["b1"], r["b2"]), (False, False, True))
feed(p, (1, th.BTN_TOOL_PEN, 0), (0, 0, 0))
check("leaving proximity", p.report()["in"], False)
feed(p, (3, 0, 99999), (3, 1, -5), (0, 0, 0))
r = p.report()
check("out of range is clamped", (r["x"], r["y"]), (1.0, 0.0))
feed(p, (1, th.BTN_TOOL_RUBBER, 1), (0, 0, 0))
check("the eraser end", (p.report()["tool"], p.report()["in"]), ("eraser", True))

p = th.Pen(RANGES)
feed(p, (1, th.BTN_TOUCH, 1), (0, 0, 0))
check("SYN_DROPPED discards the report that follows", feed(p, (0, th.SYN_DROPPED, 0), (3, 0, 5), (0, 0, 0)), False)
check("and the state it left", p.report()["touch"], False)
check("the next report is fine", feed(p, (3, 0, 7600), (0, 0, 0)), True)

TILT = dict(RANGES)
TILT[th.ABS_TILT_X] = (-64, 63)
TILT[th.ABS_TILT_Y] = (-64, 63)
p = th.Pen(TILT)
feed(p, (3, th.ABS_TILT_X, -32), (3, th.ABS_TILT_Y, 63), (0, 0, 0))
r = p.report()
check("tilt is -1..1 around the middle", (r["tx"], r["ty"]), (-0.5, 0.9844))
check("a missing axis range does not divide by zero", th.Pen({}).report()["x"], 0.0)

# ── stdin ─────────────────────────────────────────────────────────────────────
check("watch on", th.parse_command('{"cmd":"watch","on":true}'), ("watch", True))
check("watch off", th.parse_command('{"cmd":"watch","on":false}'), ("watch", False))
check("watch needs a real bool", th.parse_command('{"cmd":"watch","on":1}'), None)
check("unknown command", th.parse_command('{"cmd":"grab"}'), None)
check("not an object", th.parse_command("[1]"), None)
check("not JSON", th.parse_command("watch"), None)

print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
