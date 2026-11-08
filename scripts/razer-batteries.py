#!/usr/bin/env python3
"""razer-batteries.py — Razer peripherals' charge, from OpenRazer, as JSON.

Mainline Linux can't read a Razer device's battery (no power_supply, so UPower
never lists it); OpenRazer's daemon can, over the session bus. services/
DeviceBatteries runs this on a slow poll and merges the answer with UPower's
peripherals. Tidying and validation are sysstats.js `parseRazer`, where they're
tested; this only asks.

Prints one JSON array, `[]` when OpenRazer isn't there (not installed, daemon not
running, no devices) — a missing optional tool is not an error:

    [{"serial": "…", "name": "Razer Viper Ultimate (Wireless)",
      "type": "mouse", "battery": 84.3, "charging": false,
      "dpi": [800, 800], "pollRate": 500, "firmware": "v1.6",
      "idleTime": 300, "lowBattery": 30}, …]

The last five are the hover card's details and are null where the device doesn't
have the capability (a headset has no DPI).

Devices without a battery (a wired keyboard) don't answer getBattery and are
left out. The D-Bus API is OpenRazer's documented one: razer.devices.getDevices,
then per /org/razer/device/<serial> razer.device.misc.getDeviceName/-Type and
razer.device.power.getBattery/isCharging.
"""
import json
import subprocess
import sys

TIMEOUT = 3


def call(path, iface, method):
    """One busctl call on the session bus; its decoded `data`, or None."""
    try:
        out = subprocess.run(
            ["busctl", "--user", "--json=short", "call", "org.razer", path, iface, method],
            capture_output=True, text=True, timeout=TIMEOUT)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if out.returncode != 0:
        return None
    try:
        data = json.loads(out.stdout).get("data")
    except (ValueError, AttributeError):
        return None
    return data[0] if isinstance(data, list) and len(data) == 1 else data


def main():
    serials = call("/org/razer", "razer.devices", "getDevices")
    devices = []
    for serial in serials if isinstance(serials, list) else []:
        if not isinstance(serial, str) or not serial:
            continue
        path = "/org/razer/device/" + serial
        battery = call(path, "razer.device.power", "getBattery")
        if not isinstance(battery, (int, float)):
            continue
        devices.append({
            "serial": serial,
            "name": call(path, "razer.device.misc", "getDeviceName") or "",
            "type": call(path, "razer.device.misc", "getDeviceType") or "",
            "battery": battery,
            "charging": call(path, "razer.device.power", "isCharging") is True,
            "dpi": call(path, "razer.device.dpi", "getDPI"),
            "pollRate": call(path, "razer.device.misc", "getPollRate"),
            "firmware": call(path, "razer.device.misc", "getFirmware"),
            "idleTime": call(path, "razer.device.power", "getIdleTime"),
            "lowBattery": call(path, "razer.device.power", "getLowBatteryThreshold"),
        })
    json.dump(devices, sys.stdout)
    print()


if __name__ == "__main__":
    main()
