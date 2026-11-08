#!/usr/bin/env python3
"""Connect to a hidden Wi-Fi network, with the passphrase off the command line.

    echo '{"ssid": "Home", "psk": "secret"}' | scripts/wifi-hidden.py

Reads one JSON object on stdin, prints one on stdout: {"ok": true} or
{"ok": false, "error": "..."}. Exit 0 either way when the answer is printed; 2 for
bad input.

Why this exists: services/Net.qml talks to NetworkManager through Quickshell.Networking,
which can't create a connection for a network that isn't in the scan list — and a
hidden network never is. The old route was `nmcli dev wifi connect <ssid> password
<psk> hidden yes` from the panel, which puts the passphrase in argv, readable by every
local user from /proc/<pid>/cmdline for as long as nmcli runs. The same rule as
discord-credentials.py and ai-credentials.py: a secret never passes through argv. So
the secret arrives on stdin, and goes to NetworkManager over D-Bus
(AddAndActivateConnection), never through another process's arguments.

Needs python-dbus (a core dependency). The settings builder and the validation are
pure functions, tested by scripts/test-wifi-hidden.py without D-Bus.
"""
import json
import sys

NM = "org.freedesktop.NetworkManager"
NM_PATH = "/org/freedesktop/NetworkManager"
DEVICE_TYPE_WIFI = 2


def validate(ssid, psk):
    """→ "" when usable, else why not. Limits are 802.11's and WPA's own."""
    if not isinstance(ssid, str) or not isinstance(psk, str):
        return "ssid and psk must be strings"
    n = len(ssid.encode("utf-8"))
    if n < 1 or n > 32:
        return "a network name is 1 to 32 bytes"
    if psk:
        hex64 = len(psk) == 64 and all(c in "0123456789abcdefABCDEF" for c in psk)
        if not hex64 and not (8 <= len(psk) <= 63):
            return "a WPA passphrase is 8 to 63 characters (or 64 hex digits)"
    return ""


def settings(ssid, psk):
    """NetworkManager connection settings as plain Python (the D-Bus layer wraps types).
    No psk = an open network."""
    s = {
        "connection": {"type": "802-11-wireless", "id": ssid},
        "802-11-wireless": {"ssid": list(ssid.encode("utf-8")), "hidden": True, "mode": "infrastructure"},
    }
    if psk:
        s["802-11-wireless"]["security"] = "802-11-wireless-security"
        s["802-11-wireless-security"] = {"key-mgmt": "wpa-psk", "psk": psk}
    return s


def _connect(ssid, psk):
    import dbus  # here, so the pure functions above import without it

    bus = dbus.SystemBus()
    nm = dbus.Interface(bus.get_object(NM, NM_PATH), NM)
    wifi = None
    for path in nm.GetDevices():
        props = dbus.Interface(bus.get_object(NM, path), "org.freedesktop.DBus.Properties")
        if int(props.Get(NM + ".Device", "DeviceType")) == DEVICE_TYPE_WIFI:
            wifi = path
            break
    if wifi is None:
        return "no Wi-Fi device"
    raw = settings(ssid, psk)
    wrapped = dbus.Dictionary({
        group: dbus.Dictionary({
            k: (dbus.Array([dbus.Byte(b) for b in v], signature="y") if k == "ssid" else v)
            for k, v in values.items()
        }, signature="sv")
        for group, values in raw.items()
    }, signature="sa{sv}")
    nm.AddAndActivateConnection(wrapped, wifi, dbus.ObjectPath("/"))
    return ""


def main():
    try:
        req = json.loads(sys.stdin.readline() or "{}")
    except ValueError:
        print(json.dumps({"ok": False, "error": "bad request"}))
        return 2
    ssid, psk = req.get("ssid", ""), req.get("psk", "")
    why = validate(ssid, psk)
    if why:
        print(json.dumps({"ok": False, "error": why}))
        return 2
    try:
        err = _connect(ssid, psk)
    except ImportError:
        err = "python-dbus is not installed"
    except Exception as e:  # D-Bus errors carry NetworkManager's own message
        err = getattr(e, "get_dbus_message", lambda: str(e))() or str(e)
    print(json.dumps({"ok": not err, "error": err} if err else {"ok": True}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
