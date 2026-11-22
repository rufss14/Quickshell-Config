#!/usr/bin/env python3
"""
tablet-helper.py: reads a drawing tablet's pen and express keys for services/Tablet.qml.

    tablet-helper.py --probe
        One JSON line on stdout: every tablet found, with its size, its express-key count and whether
        this user may read its nodes. Needs no permission (sysfs and `udevadm info`).

    tablet-helper.py --pen /dev/input/eventN [--pad /dev/input/eventM]
        Runs until stdin closes or the parent dies. JSON lines on stdout, one object each:

            {"t":"hello","x":[0,15200],"y":[0,9500],"p":4095,"d":31,"tilt":false,"keys":4}
            {"t":"pad","key":0,"down":true}            an express key (0-based, in key-code order)
            {"t":"pen","in":true,"tool":"pen","x":0.5,"y":0.5,"p":0.2,"d":0,"touch":true,"b1":false,"b2":false}
                                                        x, y, p, d are 0..1; tx, ty (-1..1) only with tilt
            {"t":"rate","hz":199}                       reports per second, once a second
            {"t":"fatal","reason":"access"|"missing"}   exit 3, do not restart
            {"t":"gone"}                                exit 4, the device left: probe again

        stdin, one JSON object per line:  {"cmd":"watch","on":true|false}

The pen node is open only while `watch` is on, so an idle shell costs nothing here; the express keys are
always read (they are rare). Nodes are opened read-only and NEVER grabbed: the compositor keeps
handling the tablet exactly as before, this only listens.

Pure parts (the bitmap, discovery, the decoder, the report) are pinned by scripts/test-tablet-helper.py.
No python-evdev: the kernel's struct is 24 bytes and two ioctls are all it takes.
"""

import ctypes
import fcntl
import json
import os
import re
import select
import signal
import struct
import subprocess
import sys
import time

SYSDIR = "/sys/class/input"

EV_SYN, EV_KEY, EV_ABS = 0, 1, 3
SYN_REPORT, SYN_DROPPED = 0, 3
ABS_X, ABS_Y, ABS_PRESSURE, ABS_DISTANCE, ABS_TILT_X, ABS_TILT_Y = 0x00, 0x01, 0x18, 0x19, 0x1A, 0x1B
BTN_TOOL_PEN, BTN_TOOL_RUBBER, BTN_TOUCH, BTN_STYLUS, BTN_STYLUS2 = 0x140, 0x141, 0x14A, 0x14B, 0x14C

# A pad's keys are BTN_0..BTN_9 and BTN_A..BTN_THUMBR; a pen reports 0x140 and up. services/tablet.js
# PAD_RANGES holds the same two ranges.
PAD_RANGES = ((0x100, 0x110), (0x130, 0x13F))

EVENT = struct.Struct("llHHi")          # struct input_event: timeval, type, code, value
WATCH_INTERVAL = 1.0 / 60               # a pen report is at most this often
RATE_WINDOW = 1.0

EXIT_FATAL = 3
EXIT_GONE = 4

_NODE = re.compile(r"/dev/input/event[0-9]{1,5}")


def die_with_parent():
    """Exit when Quickshell does. qs sets no PDEATHSIG and a reload runs no cleanup, so without this the
    helper would outlive it with the pen's node open. Best-effort."""
    try:
        ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM, 0, 0, 0)
    except Exception:
        pass


def emit(obj, out=None):
    out = out or sys.stdout
    out.write(json.dumps(obj, separators=(",", ":")) + "\n")
    out.flush()


def log(*a):
    print("tablet-helper:", *a, file=sys.stderr, flush=True)


# ══ Pure helpers: scripts/test-tablet-helper.py pins these ═══════════════════════════════

def valid_node(path):
    return isinstance(path, str) and bool(_NODE.fullmatch(path))      # fullmatch: `$` allows a trailing \n


def parse_caps(text):
    """sysfs capabilities/key or /abs ("800 f 0 0 0 0": 64-bit words, the highest first) as one int."""
    bits = 0
    for word in str(text or "").split():
        try:
            bits = (bits << 64) | int(word, 16)
        except ValueError:
            return 0
    return bits


def has_bit(bits, code):
    return bool((bits >> code) & 1)


def pad_codes(key_bits):
    return [c for lo, hi in PAD_RANGES for c in range(lo, hi) if has_bit(key_bits, c)]


def hypr_name(kernel_name):
    """Hyprland's own spelling of a device name (hyprctl devices): lower case, spaces to a dash."""
    return str(kernel_name or "").replace(" ", "-").replace("\n", "-").lower()


def classify(key_bits, abs_bits):
    """'pen', 'pad' or None. A pen reports a tool and an absolute position with pressure; a pad has keys
    from the BTN_0 range and no tool."""
    if has_bit(key_bits, BTN_TOOL_PEN) and has_bit(abs_bits, ABS_X) and has_bit(abs_bits, ABS_Y) \
            and has_bit(abs_bits, ABS_PRESSURE):
        return "pen"
    if not has_bit(key_bits, BTN_TOOL_PEN) and pad_codes(key_bits):
        return "pad"
    return None


def parse_udev(text):
    """`udevadm info -q property` as a dict."""
    out = {}
    for line in str(text or "").splitlines():
        k, sep, v = line.partition("=")
        if sep:
            out[k] = v
    return out


def _num(v):
    try:
        return max(0.0, float(v))
    except (TypeError, ValueError):
        return 0.0


def discover(sysdir, udev_fn, access_fn):
    """Every tablet under `sysdir` (a sysfs input class): the pen node, its pad node if it has one, its
    size in mm and the number of express keys. Nodes are grouped by their physical port and serial.
    `udev_fn(node)` returns `udevadm info -q property` text, `access_fn(node)` whether it can be read."""
    groups = {}
    try:
        names = sorted(n for n in os.listdir(sysdir) if re.fullmatch(r"event[0-9]+", n))
    except OSError:
        return []

    def read(*parts):
        try:
            with open(os.path.join(sysdir, *parts)) as f:
                return f.read().strip()
        except OSError:
            return ""

    for n in names:
        dev = os.path.join(n, "device")
        key = parse_caps(read(dev, "capabilities", "key"))
        absb = parse_caps(read(dev, "capabilities", "abs"))
        kind = classify(key, absb)
        if kind is None:
            continue
        ident = (read(dev, "phys").split("/")[0], read(dev, "uniq"))
        g = groups.setdefault(ident, {})
        if kind not in g:
            g[kind] = {"node": "/dev/input/" + n, "name": read(dev, "name"), "keys": len(pad_codes(key))}

    tablets = []
    for ident in sorted(groups):
        g = groups[ident]
        if "pen" not in g:
            continue
        props = parse_udev(udev_fn(g["pen"]["node"]))
        pen, pad = g["pen"], g.get("pad")
        nodes = [pen["node"]] + ([pad["node"]] if pad else [])
        tablets.append({
            "name": pen["name"],
            "hypr": hypr_name(pen["name"]),
            "model": props.get("ID_MODEL", "").replace("_", " "),
            "pen": pen["node"],
            "pad": pad["node"] if pad else "",
            "widthMm": _num(props.get("ID_INPUT_WIDTH_MM")),
            "heightMm": _num(props.get("ID_INPUT_HEIGHT_MM")),
            "keys": pad["keys"] if pad else 0,
            "access": all(access_fn(x) for x in nodes),
        })
    return tablets


class Decoder:
    """Bytes from an evdev node to (type, code, value), across reads that end mid-event."""

    def __init__(self):
        self._rest = b""

    def feed(self, data):
        buf = self._rest + data
        n = len(buf) // EVENT.size
        self._rest = buf[n * EVENT.size:]
        return [EVENT.unpack_from(buf, i * EVENT.size)[2:] for i in range(n)]


class Pen:
    """The pen as the events describe it. `apply` returns True when a report is complete."""

    def __init__(self, ranges):
        self.ranges = ranges            # {axis: (min, max)}
        self.axes = {}
        self.keys = set()
        self.dropped = False

    def apply(self, etype, code, value):
        if etype == EV_ABS:
            self.axes[code] = value
        elif etype == EV_KEY:
            (self.keys.add if value else self.keys.discard)(code)
        elif etype == EV_SYN:
            if code == SYN_DROPPED:
                self.dropped = True
            elif code == SYN_REPORT:
                if self.dropped:
                    self.dropped = False
                    self.keys.clear()
                    return False
                return True
        return False

    def _unit(self, axis, symmetric=False):
        lo, hi = self.ranges.get(axis, (0, 0))
        v = self.axes.get(axis, 0)
        if symmetric:
            span = max(abs(lo), abs(hi))
            return max(-1.0, min(1.0, v / span)) if span else 0.0
        return max(0.0, min(1.0, (v - lo) / (hi - lo))) if hi > lo else 0.0

    def report(self):
        eraser = BTN_TOOL_RUBBER in self.keys
        out = {
            "t": "pen",
            "in": BTN_TOOL_PEN in self.keys or eraser,
            "tool": "eraser" if eraser else "pen",
            "x": round(self._unit(ABS_X), 4),
            "y": round(self._unit(ABS_Y), 4),
            "p": round(self._unit(ABS_PRESSURE), 4),
            "d": round(self._unit(ABS_DISTANCE), 4),
            "touch": BTN_TOUCH in self.keys,
            "b1": BTN_STYLUS in self.keys,
            "b2": BTN_STYLUS2 in self.keys,
        }
        if ABS_TILT_X in self.ranges:
            out["tx"] = round(self._unit(ABS_TILT_X, True), 4)
            out["ty"] = round(self._unit(ABS_TILT_Y, True), 4)
        return out


def parse_command(line):
    """A stdin line as ("watch", bool), or None for anything else."""
    try:
        o = json.loads(line)
    except ValueError:
        return None
    if isinstance(o, dict) and o.get("cmd") == "watch" and isinstance(o.get("on"), bool):
        return ("watch", o["on"])
    return None


# ══ The device: the only part that touches /dev/input ═══════════════════════════════════

def _ioc_read(nr, size):
    return (2 << 30) | (size << 16) | (ord("E") << 8) | nr


def absinfo(fd, axis):
    """(minimum, maximum) of an absolute axis, or None when the device does not have it."""
    buf = bytearray(24)                  # struct input_absinfo: value, minimum, maximum, fuzz, flat, resolution
    try:
        fcntl.ioctl(fd, _ioc_read(0x40 + axis, 24), buf, True)
    except OSError:
        return None
    _, lo, hi, _, _, _ = struct.unpack("6i", bytes(buf))
    return (lo, hi)


def open_node(path):
    try:
        return os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    except PermissionError:
        emit({"t": "fatal", "reason": "access"})
        sys.exit(EXIT_FATAL)
    except OSError:
        emit({"t": "fatal", "reason": "missing"})
        sys.exit(EXIT_FATAL)


def udev_props(node):
    try:
        return subprocess.run(["udevadm", "info", "-q", "property", "-n", node],
                              capture_output=True, text=True, timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def probe():
    udev = any(os.access(os.path.join(p, "udevadm"), os.X_OK) for p in os.environ.get("PATH", "").split(":") if p)
    tablets = discover(SYSDIR, udev_props, lambda n: os.access(n, os.R_OK)) if udev else []
    emit({"udev": udev, "tablets": tablets})


def run(pen_path, pad_path):
    if not valid_node(pen_path) or (pad_path and not valid_node(pad_path)):
        emit({"t": "fatal", "reason": "missing"})
        return EXIT_FATAL

    # The pen is opened once to learn its ranges and closed again until someone watches.
    fd = open_node(pen_path)
    ranges = {a: r for a in (ABS_X, ABS_Y, ABS_PRESSURE, ABS_DISTANCE, ABS_TILT_X, ABS_TILT_Y)
              if (r := absinfo(fd, a)) is not None}
    os.close(fd)
    pad_fd = open_node(pad_path) if pad_path else None
    pad_keys = []
    if pad_path:
        caps = ""
        try:
            with open(os.path.join(SYSDIR, os.path.basename(pad_path), "device", "capabilities", "key")) as f:
                caps = f.read()
        except OSError:
            pass
        pad_keys = pad_codes(parse_caps(caps))
    emit({"t": "hello", "x": list(ranges.get(ABS_X, (0, 0))), "y": list(ranges.get(ABS_Y, (0, 0))),
          "p": ranges.get(ABS_PRESSURE, (0, 0))[1], "d": ranges.get(ABS_DISTANCE, (0, 0))[1],
          "tilt": ABS_TILT_X in ranges, "keys": len(pad_keys)})

    pen = Pen(ranges)
    pen_dec, pad_dec = Decoder(), Decoder()
    pen_fd = None
    stdin_buf = b""
    dirty = False
    last_emit = 0.0
    reports, window_at = 0, 0.0
    os.set_blocking(0, False)

    while True:
        fds = [0] + ([pen_fd] if pen_fd is not None else []) + ([pad_fd] if pad_fd is not None else [])
        timeout = None
        if pen_fd is not None:
            now = time.monotonic()
            timeout = min(max(0.0, last_emit + WATCH_INTERVAL - now) if dirty else RATE_WINDOW,
                          max(0.0, window_at + RATE_WINDOW - now))
        ready, _, _ = select.select(fds, [], [], timeout)

        for r in ready:
            try:
                data = os.read(r, 4096)
            except BlockingIOError:
                continue
            except OSError:
                emit({"t": "gone"})
                return EXIT_GONE
            if r == 0:
                if not data:
                    return 0
                stdin_buf += data
                while b"\n" in stdin_buf:
                    line, stdin_buf = stdin_buf.split(b"\n", 1)
                    cmd = parse_command(line.decode("utf-8", "replace"))
                    if cmd and cmd[1] and pen_fd is None:
                        pen_fd = open_node(pen_path)
                        pen = Pen(ranges)
                        pen_dec = Decoder()
                        dirty, reports, window_at = False, 0, time.monotonic()
                    elif cmd and not cmd[1] and pen_fd is not None:
                        os.close(pen_fd)
                        pen_fd = None
            elif r == pad_fd:
                if not data:
                    emit({"t": "gone"})
                    return EXIT_GONE
                for etype, code, value in pad_dec.feed(data):
                    if etype == EV_KEY and code in pad_keys and value in (0, 1):
                        emit({"t": "pad", "key": pad_keys.index(code), "down": value == 1})
            else:
                if not data:
                    emit({"t": "gone"})
                    return EXIT_GONE
                for etype, code, value in pen_dec.feed(data):
                    if pen.apply(etype, code, value):
                        dirty = True
                        reports += 1

        now = time.monotonic()
        if pen_fd is not None:
            if dirty and now - last_emit >= WATCH_INTERVAL:
                emit(pen.report())
                dirty, last_emit = False, now
            if now - window_at >= RATE_WINDOW:
                emit({"t": "rate", "hz": int(round(reports / (now - window_at)))})
                reports, window_at = 0, now


def main(argv):
    die_with_parent()
    if "--probe" in argv:
        probe()
        return 0
    pen = pad = ""
    i = 1
    while i < len(argv):
        if argv[i] == "--pen" and i + 1 < len(argv):
            pen = argv[i + 1]
            i += 1
        elif argv[i] == "--pad" and i + 1 < len(argv):
            pad = argv[i + 1]
            i += 1
        i += 1
    if not pen:
        log("usage: tablet-helper.py --probe | --pen NODE [--pad NODE]")
        return 2
    return run(pen, pad)


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except KeyboardInterrupt:
        sys.exit(0)
    except BrokenPipeError:
        sys.exit(0)
