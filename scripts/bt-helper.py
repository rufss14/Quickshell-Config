#!/usr/bin/env python3
"""
bt-helper.py — the BlueZ D-Bus pieces Quickshell.Bluetooth doesn't expose.

services/BtBridge.qml runs this for the shell's lifetime (while there's an
adapter) and talks JSON lines: events out on stdout, commands in on stdin.
Diagnostics go to stderr and never carry a PIN, a passkey or a file's content.

── Why a helper ────────────────────────────────────────────────────────────────
Quickshell.Bluetooth covers adapters and devices well, but three things live
outside it, and all three need a D-Bus connection QML can't make:

  · the PAIRING AGENT (org.bluez.Agent1). Without one registered, BlueZ has nobody
    to ask "does 482913 match?", so any device that wants a PIN or a numeric
    comparison — phones, many keyboards — sits in "pairing" and then fails. This
    registers one and forwards each question to the shell, which asks the person.
  · RSSI. BlueZ publishes it on Device1 while discovering; Quickshell doesn't
    expose it. Pushed by PropertiesChanged, coalesced here to at most one update
    per device per FLUSH_MS, because a scan delivers several per second per device.
  · OBEX Object Push (sending a file). That's obexd, on the SESSION bus, from the
    optional bluez-obex package — `obex` in the hello says whether it's there.

All event-driven: a GLib main loop with signal receivers and a stdin watch. No
polling, no timers except the per-prompt timeout and the RSSI flush.

── Protocol ────────────────────────────────────────────────────────────────────
out  {"t":"hello","agent":bool,"obex":bool}
     {"t":"agent","on":bool,"error":str}          registered / released / failed
     {"t":"prompt","id":n,"kind":K,"address":A,…}  K: pin | passkey | confirm |
                                                    authorize | service |
                                                    display-pin | display-passkey
         confirm/display-passkey carry "passkey" ("012345"); display-pin "pin";
         display-passkey "entered" (digits typed so far); service "service".
     {"t":"prompt-end","id":n}                     answered, cancelled or expired
     {"t":"dev","address":A,"rssi":int|null,"opp":bool}   (fields only when known)
     {"t":"obex","available":bool}
     {"t":"transfer","id":n,"address":A,"name":str,"size":int,"sent":int,
                     "status":"connecting|queued|active|complete|error","error":str}
     {"t":"fatal","error":str}                     then exit 3 — don't restart
in   {"c":"answer","id":n,"ok":bool,"value":str}   value: the PIN / passkey typed
     {"c":"agent","on":bool}
     {"c":"send","id":n,"address":A,"path":str}
     {"c":"cancel","id":n}                         a transfer

── When this breaks ────────────────────────────────────────────────────────────
  · "agent" never turns on: another agent may hold the default (blueman-applet).
    Registering alongside it works; RequestDefaultAgent is what lets ours answer
    pairings the PHONE starts. `busctl tree org.bluez` / bluetoothd's journal say
    which agent BlueZ asked.
  · Sends fail with org.freedesktop.DBus.Error.ServiceUnknown: bluez-obex isn't
    installed, or its user unit can't start (`systemctl --user status obex`).
  · A transfer stuck in "queued": the phone hasn't accepted the incoming file yet.

    python3 scripts/test-bt-helper.py   — fully mocked, touches no bus
"""

import ctypes
import json
import os
import re
import signal
import sys

AGENT_PATH = "/org/quicktest/btagent"
# KeyboardDisplay: we can both SHOW a passkey and TYPE one, so BlueZ picks the
# strongest association model the other side supports.
CAPABILITY = "KeyboardDisplay"
PROMPT_TIMEOUT_S = 60          # BlueZ gives up on its own too; this frees ours
FLUSH_MS = 500
OPP_UUID = "00001105-0000-1000-8000-00805f9b34fb"

BLUEZ = "org.bluez"
OBEX = "org.bluez.obex"
PROPS = "org.freedesktop.DBus.Properties"


def die_with_parent():
    """Exit when Quickshell does. qs sets no PDEATHSIG and a `pkill -TERM` of it
    runs no cleanup, so without this a reload orphans the helper — and an orphan
    keeps its agent registered as BlueZ's default. Same as spotify-bridge.py."""
    try:
        ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM, 0, 0, 0)
    except Exception:
        pass


# ══ Pure helpers — scripts/test-bt-helper.py pins these ═════════════════════════

_ADDR = re.compile(r"([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}")
_DEV_PATH = re.compile(r"/dev_((?:[0-9A-Fa-f]{2}_){5}[0-9A-Fa-f]{2})$")


def valid_address(s):
    return isinstance(s, str) and bool(_ADDR.fullmatch(s))   # fullmatch: `$` allows a trailing \n


def address_from_path(path):
    m = _DEV_PATH.search(str(path or ""))
    return m.group(1).replace("_", ":").upper() if m else ""


def clean_pin(value):
    """A legacy PIN: 1–16 printable ASCII characters. None = refuse."""
    if not isinstance(value, str):
        return None
    if not 1 <= len(value) <= 16:
        return None
    if any(not (0x20 < ord(ch) < 0x7F) for ch in value):
        return None
    return value


def clean_passkey(value):
    """A passkey: up to six digits, 0–999999. None = refuse."""
    s = str(value).strip() if isinstance(value, (str, int)) and not isinstance(value, bool) else ""
    if not re.fullmatch(r"\d{1,6}", s):
        return None
    return int(s)


def fmt_passkey(n):
    return "%06d" % (int(n) % 1000000)


_SERVICES = {
    "0000110a": "audio source", "0000110b": "audio", "0000110d": "audio",
    "0000110e": "media controls", "0000110c": "media controls",
    "0000111e": "calls", "0000111f": "calls", "00001108": "calls", "00001112": "calls",
    "00001124": "input", "00001812": "input",
    "00001105": "file transfer", "00001106": "file transfer",
    "00001115": "network", "00001116": "network",
    "0000112f": "phonebook", "00001132": "messages",
}


def service_name(uuid):
    return _SERVICES.get(str(uuid or "").lower()[:8], "a service")


def has_opp(uuids):
    return OPP_UUID in [str(u).lower() for u in (uuids or [])]


def valid_send_path(path):
    """The file to send: absolute, a regular readable file. Resolved, so a symlink
    is judged by what it points at. None = refuse."""
    if not isinstance(path, str) or not path.startswith("/") or "\0" in path:
        return None
    real = os.path.realpath(path)
    if not os.path.isfile(real) or not os.access(real, os.R_OK):
        return None
    return real


def _int_id(v):
    return isinstance(v, int) and not isinstance(v, bool) and 0 <= v < 2 ** 31


def parse_command(line):
    """A stdin line → a validated command dict, or None. This is the trust
    boundary: anything malformed is dropped rather than half-applied."""
    try:
        msg = json.loads(line)
    except (ValueError, TypeError):
        return None
    if not isinstance(msg, dict):
        return None
    c = msg.get("c")
    if c == "answer":
        if not _int_id(msg.get("id")) or not isinstance(msg.get("ok"), bool):
            return None
        value = msg.get("value", "")
        if not isinstance(value, str) or len(value) > 64:
            return None
        return {"c": "answer", "id": msg["id"], "ok": msg["ok"], "value": value}
    if c == "agent":
        return {"c": "agent", "on": msg.get("on")} if isinstance(msg.get("on"), bool) else None
    if c == "send":
        if not _int_id(msg.get("id")) or not valid_address(msg.get("address")):
            return None
        if not isinstance(msg.get("path"), str):
            return None
        return {"c": "send", "id": msg["id"], "address": msg["address"].upper(), "path": msg["path"]}
    if c == "cancel":
        return {"c": "cancel", "id": msg["id"]} if _int_id(msg.get("id")) else None
    return None


class Coalescer:
    """Latest fields per address, drained in one batch. `update` returns True the
    first time something becomes dirty, i.e. when the caller should schedule a
    flush."""

    def __init__(self):
        self._pending = {}

    def update(self, address, fields):
        was_empty = not self._pending
        self._pending.setdefault(address, {}).update(fields)
        return was_empty

    def drain(self):
        out = [dict(address=a, **f) for a, f in self._pending.items()]
        self._pending = {}
        return out


# ══ Prompts — the agent's questions, independent of D-Bus ══════════════════════

ANSWERED = ("pin", "passkey", "confirm", "authorize", "service")


class Prompts:
    """Pending agent questions. `ask` parks BlueZ's reply callbacks under an id and
    emits the question; `answer` validates what came back and replies. `schedule`
    and `unschedule` are injected (GLib in the helper, a fake in the tests)."""

    def __init__(self, emit, schedule, unschedule, rejected):
        self.emit = emit
        self.schedule = schedule
        self.unschedule = unschedule
        self.rejected = rejected          # () -> the exception BlueZ wants on refusal
        self.pending = {}                 # id -> {kind, address, ok, err, timer}
        self.next_id = 1

    def ask(self, kind, address, ok=None, err=None, **extra):
        # A display prompt for the same device is UPDATED in place (DisplayPasskey
        # is called again for every digit typed on the remote keyboard).
        if kind.startswith("display-"):
            for pid, p in self.pending.items():
                if p["kind"] == kind and p["address"] == address:
                    self.emit(dict(t="prompt", id=pid, kind=kind, address=address, **extra))
                    return pid
        pid = self.next_id
        self.next_id += 1
        timer = self.schedule(PROMPT_TIMEOUT_S, lambda: self.expire(pid))
        self.pending[pid] = {"kind": kind, "address": address, "ok": ok, "err": err, "timer": timer}
        self.emit(dict(t="prompt", id=pid, kind=kind, address=address, **extra))
        return pid

    def _close(self, pid):
        p = self.pending.pop(pid, None)
        if p is None:
            return None
        if p["timer"] is not None:
            self.unschedule(p["timer"])
        self.emit({"t": "prompt-end", "id": pid})
        return p

    def answer(self, pid, ok, value=""):
        p = self._close(pid)
        if p is None or p["kind"] not in ANSWERED:
            return False
        if not ok:
            p["err"](self.rejected())
            return True
        if p["kind"] == "pin":
            pin = clean_pin(value)
            p["ok"](pin) if pin is not None else p["err"](self.rejected())
        elif p["kind"] == "passkey":
            key = clean_passkey(value)
            p["ok"](key) if key is not None else p["err"](self.rejected())
        else:
            p["ok"]()
        return True

    def expire(self, pid):
        p = self._close(pid)
        if p is not None and p["kind"] in ANSWERED:
            p["err"](self.rejected())
        return False                      # one-shot for GLib

    def cancel_all(self):
        """BlueZ's Cancel(): it has already given up, so nobody is replied to."""
        for pid in list(self.pending):
            self._close(pid)

    def end_for(self, address):
        """Pairing with `address` finished — its display prompts have nothing left
        to show."""
        for pid, p in list(self.pending.items()):
            if p["address"] == address and p["kind"].startswith("display-"):
                self._close(pid)


# ══ The D-Bus side ═════════════════════════════════════════════════════════════

def emit(obj):
    try:
        sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
        sys.stdout.flush()
    except BrokenPipeError:
        os._exit(0)


def log(*a):
    print("bt-helper:", *a, file=sys.stderr, flush=True)


def dbus_error_text(e):
    get = getattr(e, "get_dbus_message", None)
    msg = get() if callable(get) else None
    return msg or str(e) or e.__class__.__name__


def main(argv):
    die_with_parent()
    try:
        import dbus
        import dbus.service
        from dbus.mainloop.glib import DBusGMainLoop
        from gi.repository import GLib
    except ImportError as e:
        emit({"t": "fatal", "error": "python-dbus / python-gobject missing (%s)" % e.name})
        return 3

    DBusGMainLoop(set_as_default=True)
    loop = GLib.MainLoop()

    try:
        sysbus = dbus.SystemBus()
    except dbus.DBusException as e:
        emit({"t": "fatal", "error": "no system bus: " + dbus_error_text(e)})
        return 3
    try:
        sesbus = dbus.SessionBus()
    except dbus.DBusException:
        sesbus = None                     # no OBEX without a session bus; the rest works

    class Rejected(dbus.DBusException):
        _dbus_error_name = "org.bluez.Error.Rejected"

    prompts = Prompts(
        emit,
        schedule=lambda s, fn: GLib.timeout_add_seconds(s, fn),
        unschedule=GLib.source_remove,
        rejected=lambda: Rejected("Rejected by user"),
    )
    state = {"want_agent": "--no-agent" not in argv, "agent_on": False}

    # ── The agent object ─────────────────────────────────────────────────────
    class Agent(dbus.service.Object):
        IFACE = "org.bluez.Agent1"

        @dbus.service.method(IFACE, in_signature="", out_signature="")
        def Release(self):
            state["agent_on"] = False
            emit({"t": "agent", "on": False, "error": ""})

        @dbus.service.method(IFACE, in_signature="o", out_signature="s",
                             async_callbacks=("ok", "err"))
        def RequestPinCode(self, device, ok, err):
            prompts.ask("pin", address_from_path(device), ok, err)

        @dbus.service.method(IFACE, in_signature="os", out_signature="")
        def DisplayPinCode(self, device, pincode):
            prompts.ask("display-pin", address_from_path(device), pin=str(pincode))

        @dbus.service.method(IFACE, in_signature="o", out_signature="u",
                             async_callbacks=("ok", "err"))
        def RequestPasskey(self, device, ok, err):
            prompts.ask("passkey", address_from_path(device),
                        lambda k: ok(dbus.UInt32(k)), err)

        @dbus.service.method(IFACE, in_signature="ouq", out_signature="")
        def DisplayPasskey(self, device, passkey, entered):
            prompts.ask("display-passkey", address_from_path(device),
                        passkey=fmt_passkey(passkey), entered=int(entered))

        @dbus.service.method(IFACE, in_signature="ou", out_signature="",
                             async_callbacks=("ok", "err"))
        def RequestConfirmation(self, device, passkey, ok, err):
            prompts.ask("confirm", address_from_path(device), ok, err,
                        passkey=fmt_passkey(passkey))

        @dbus.service.method(IFACE, in_signature="o", out_signature="",
                             async_callbacks=("ok", "err"))
        def RequestAuthorization(self, device, ok, err):
            prompts.ask("authorize", address_from_path(device), ok, err)

        @dbus.service.method(IFACE, in_signature="os", out_signature="",
                             async_callbacks=("ok", "err"))
        def AuthorizeService(self, device, uuid, ok, err):
            prompts.ask("service", address_from_path(device), ok, err,
                        service=service_name(uuid))

        @dbus.service.method(IFACE, in_signature="", out_signature="")
        def Cancel(self):
            prompts.cancel_all()

    Agent(sysbus, AGENT_PATH)

    def agent_manager():
        return dbus.Interface(sysbus.get_object(BLUEZ, "/org/bluez"), "org.bluez.AgentManager1")

    def register_agent():
        try:
            mgr = agent_manager()
            try:
                mgr.RegisterAgent(AGENT_PATH, CAPABILITY)
            except dbus.DBusException as e:
                if e.get_dbus_name() != "org.bluez.Error.AlreadyExists":
                    raise
            mgr.RequestDefaultAgent(AGENT_PATH)
            state["agent_on"] = True
            emit({"t": "agent", "on": True, "error": ""})
        except dbus.DBusException as e:
            state["agent_on"] = False
            emit({"t": "agent", "on": False, "error": dbus_error_text(e)})
            log("agent registration failed:", dbus_error_text(e))

    def unregister_agent():
        if not state["agent_on"]:
            return
        state["agent_on"] = False
        try:
            agent_manager().UnregisterAgent(AGENT_PATH)
        except dbus.DBusException:
            pass
        prompts.cancel_all()
        emit({"t": "agent", "on": False, "error": ""})

    # ── Device properties: RSSI, file-transfer support, end of pairing ───────
    coalesce = Coalescer()

    def flush():
        for d in coalesce.drain():
            emit(dict(t="dev", **d))
        return False

    def note(address, fields):
        if address and fields and coalesce.update(address, fields):
            GLib.timeout_add(FLUSH_MS, flush)

    def device_fields(props, invalidated=()):
        f = {}
        if "RSSI" in props:
            f["rssi"] = int(props["RSSI"])
        elif "RSSI" in invalidated:
            f["rssi"] = None
        if "UUIDs" in props:
            f["opp"] = has_opp(props["UUIDs"])
        return f

    def on_props(iface, changed, invalidated, path=None):
        if iface != "org.bluez.Device1":
            return
        address = address_from_path(path)
        note(address, device_fields(changed, invalidated))
        if "Paired" in changed:
            prompts.end_for(address)

    def on_added(path, ifaces):
        if "org.bluez.Device1" in ifaces:
            note(address_from_path(path), device_fields(ifaces["org.bluez.Device1"]))

    def on_removed(path, ifaces):
        if "org.bluez.Device1" in ifaces:
            note(address_from_path(path), {"rssi": None})

    def load_devices():
        def got(objs):
            for path, ifaces in objs.items():
                on_added(path, ifaces)
        om = dbus.Interface(sysbus.get_object(BLUEZ, "/"), "org.freedesktop.DBus.ObjectManager")
        om.GetManagedObjects(reply_handler=got,
                             error_handler=lambda e: log("GetManagedObjects:", dbus_error_text(e)))

    # arg0-filtered: the match rule is then evaluated by the bus daemon, so the
    # helper isn't woken for every other interface's property changes.
    sysbus.add_signal_receiver(on_props, signal_name="PropertiesChanged", dbus_interface=PROPS,
                               bus_name=BLUEZ, path_keyword="path", arg0="org.bluez.Device1")
    sysbus.add_signal_receiver(on_added, signal_name="InterfacesAdded",
                               dbus_interface="org.freedesktop.DBus.ObjectManager", bus_name=BLUEZ)
    sysbus.add_signal_receiver(on_removed, signal_name="InterfacesRemoved",
                               dbus_interface="org.freedesktop.DBus.ObjectManager", bus_name=BLUEZ)

    # bluetoothd restarting (or starting after us) re-registers the agent.
    def on_bluez_owner(owner):
        if owner:
            if state["want_agent"]:
                register_agent()
            load_devices()
        else:
            state["agent_on"] = False
            prompts.cancel_all()
            emit({"t": "agent", "on": False, "error": "bluetoothd is not running"})

    sysbus.watch_name_owner(BLUEZ, on_bluez_owner)

    # ── OBEX: sending files ───────────────────────────────────────────────────
    transfers = {}                        # our id -> record
    by_path = {}                          # transfer object path -> our id

    def obex_available():
        if sesbus is None:
            return False
        try:
            return (OBEX in sesbus.list_activatable_names()
                    or bool(sesbus.name_has_owner(OBEX)))
        except dbus.DBusException:
            return False

    def publish(rec):
        emit({"t": "transfer", "id": rec["id"], "address": rec["address"], "name": rec["name"],
              "size": rec["size"], "sent": rec["sent"], "status": rec["status"],
              "error": rec["error"]})

    def remove_session(rec):
        if rec.get("session"):
            client = dbus.Interface(sesbus.get_object(OBEX, "/org/bluez/obex"), "org.bluez.obex.Client1")
            client.RemoveSession(rec["session"], reply_handler=lambda: None,
                                 error_handler=lambda e: None)
            rec["session"] = None

    def finish(rec, status, error=""):
        rec["status"] = status
        rec["error"] = error
        publish(rec)
        remove_session(rec)
        by_path.pop(rec.get("transfer") or "", None)
        transfers.pop(rec["id"], None)

    def send(tid, address, path):
        real = valid_send_path(path)
        rec = {"id": tid, "address": address, "name": os.path.basename(path or ""),
               "size": 0, "sent": 0, "status": "connecting", "error": "",
               "session": None, "transfer": None, "cancelled": False}
        if real is None:
            finish(rec, "error", "Not a readable file")
            return
        if not obex_available():
            finish(rec, "error", "File sending needs bluez-obex")
            return
        rec["size"] = os.path.getsize(real)
        transfers[tid] = rec
        publish(rec)

        def started(tpath, props):
            rec["transfer"] = str(tpath)
            by_path[rec["transfer"]] = tid
            rec["status"] = str(props.get("Status", "queued"))
            rec["size"] = int(props.get("Size", rec["size"]))
            publish(rec)

        def session_ready(spath):
            rec["session"] = str(spath)
            if rec["cancelled"]:
                finish(rec, "error", "Cancelled")
                return
            push = dbus.Interface(sesbus.get_object(OBEX, spath), "org.bluez.obex.ObjectPush1")
            push.SendFile(real, reply_handler=started,
                          error_handler=lambda e: finish(rec, "error", dbus_error_text(e)))

        client = dbus.Interface(sesbus.get_object(OBEX, "/org/bluez/obex"), "org.bluez.obex.Client1")
        # The phone may take a while to answer the connection — hence the timeout.
        client.CreateSession(address, {"Target": "opp"}, reply_handler=session_ready,
                             error_handler=lambda e: finish(rec, "error", dbus_error_text(e)),
                             timeout=90)

    def cancel(tid):
        rec = transfers.get(tid)
        if rec is None:
            return
        rec["cancelled"] = True
        if rec["transfer"]:
            t = dbus.Interface(sesbus.get_object(OBEX, rec["transfer"]), "org.bluez.obex.Transfer1")
            t.Cancel(reply_handler=lambda: None,
                     error_handler=lambda e: finish(rec, "error", "Cancelled"))
        else:
            # session_ready() finishes it
            rec["status"] = "error"
            rec["error"] = "Cancelled"
            publish(rec)

    def on_obex_props(iface, changed, invalidated, path=None):
        if iface != "org.bluez.obex.Transfer1":
            return
        tid = by_path.get(str(path))
        rec = transfers.get(tid) if tid is not None else None
        if rec is None:
            return
        if "Transferred" in changed:
            rec["sent"] = int(changed["Transferred"])
        status = str(changed.get("Status", rec["status"]))
        if status in ("complete", "error"):
            if status == "complete":
                rec["sent"] = rec["size"]
            finish(rec, status, "" if status == "complete"
                   else "Cancelled" if rec["cancelled"]
                   else "The other device refused or the link dropped")
        else:
            rec["status"] = status
            publish(rec)

    if sesbus is not None:
        sesbus.add_signal_receiver(on_obex_props, signal_name="PropertiesChanged",
                                   dbus_interface=PROPS, bus_name=OBEX, path_keyword="path",
                                   arg0="org.bluez.obex.Transfer1")

    # ── stdin ─────────────────────────────────────────────────────────────────
    buf = bytearray()

    def on_stdin(fd, cond):
        if cond & GLib.IO_IN:
            chunk = os.read(fd, 65536)
            if chunk:
                buf.extend(chunk)
                while b"\n" in buf:
                    i = buf.index(b"\n")
                    line = bytes(buf[:i]).decode("utf-8", "replace")
                    del buf[:i + 1]
                    handle(parse_command(line))
                return True
        loop.quit()                       # EOF / hangup: the shell is gone
        return False

    def handle(cmd):
        if cmd is None:
            log("dropped a malformed command")
            return
        c = cmd["c"]
        if c == "answer":
            prompts.answer(cmd["id"], cmd["ok"], cmd["value"])
        elif c == "agent":
            state["want_agent"] = cmd["on"]
            register_agent() if cmd["on"] else unregister_agent()
        elif c == "send":
            send(cmd["id"], cmd["address"], cmd["path"])
        elif c == "cancel":
            cancel(cmd["id"])

    # GLibUnix on PyGObject ≥ 3.52; GLib's own spellings (deprecated there) before.
    try:
        from gi.repository import GLibUnix as _U
        fd_add, signal_add = _U.fd_add_full, _U.signal_add
    except ImportError:
        fd_add, signal_add = GLib.unix_fd_add_full, GLib.unix_signal_add

    fd_add(GLib.PRIORITY_DEFAULT, sys.stdin.fileno(),
           GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, on_stdin)

    def on_term():
        unregister_agent()
        loop.quit()
        return False

    signal_add(GLib.PRIORITY_HIGH, signal.SIGTERM, on_term)
    signal_add(GLib.PRIORITY_HIGH, signal.SIGINT, on_term)

    emit({"t": "hello", "agent": state["want_agent"], "obex": obex_available()})
    emit({"t": "obex", "available": obex_available()})
    loop.run()
    unregister_agent()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
