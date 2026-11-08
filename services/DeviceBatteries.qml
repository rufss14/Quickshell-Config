pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import "sysstats.js" as Stats

// ── DeviceBatteries ───────────────────────────────────────────────────────────
// The charge of everything battery-powered that isn't the laptop: Bluetooth and
// wireless peripherals, for the stats pill's "devices" ring. One list, lowest
// charge first ({ key, name, kind, level 0..1, charging } — sysstats.js
// `mergeDevices`, tested), from two sources:
//
//   UPower      every peripheral with a kernel power_supply or a BlueZ Battery1:
//               Bluetooth mice/keyboards/headsets/controllers, Logitech's
//               receivers, DualSense… Pushed over D-Bus, so it costs nothing.
//   OpenRazer   Razer devices, which mainline Linux can't read at all (their
//               dongles expose no power_supply, so UPower never sees them). Asked
//               once a minute through scripts/razer-batteries.py, only while
//               something holds `acquire()`; `[]` when OpenRazer isn't installed.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property var devices: Stats.mergeDevices([root.upowerDevices, root._razer])
    readonly property var lowest: root.devices.length > 0 ? root.devices[0] : null
    // At or under this, not charging: the card says so in the danger colour.
    readonly property real lowThreshold: 0.15

    // ══ UPower ════════════════════════════════════════════════════════════════
    // Its peripherals, as plain objects. Reading each device's properties here is
    // what re-evaluates this when a charge moves.
    readonly property var upowerDevices: {
        const out = []
        for (const d of UPower.devices.values) {
            if (!d || d.isLaptopBattery) continue
            const kind = root._kinds[d.type]
            if (kind === undefined) continue            // line power, UPS, the laptop's own…
            if (!d.isPresent && !(d.percentage > 0)) continue
            out.push({
                key: "upower:" + d.nativePath,
                name: d.model || "",
                kind: kind,
                level: Math.max(0, Math.min(1, d.percentage)),
                charging: d.state === UPowerDeviceState.Charging
                          || d.state === UPowerDeviceState.PendingCharge
            })
        }
        return out
    }
    // UPower's device types that are peripherals → sysstats.js kinds ("" = a
    // plain battery glyph). Anything absent here isn't listed.
    readonly property var _kinds: {
        const k = {}
        k[UPowerDeviceType.Mouse]            = "mouse"
        k[UPowerDeviceType.Touchpad]         = "mouse"
        k[UPowerDeviceType.Keyboard]         = "keyboard"
        k[UPowerDeviceType.Headset]          = "headset"
        k[UPowerDeviceType.Headphones]       = "headphones"
        k[UPowerDeviceType.Speakers]         = "speaker"
        k[UPowerDeviceType.OtherAudio]       = "speaker"
        k[UPowerDeviceType.GamingInput]      = "gamepad"
        k[UPowerDeviceType.Phone]            = "phone"
        k[UPowerDeviceType.Tablet]           = "tablet"
        k[UPowerDeviceType.Pen]              = "pen"
        k[UPowerDeviceType.Wearable]         = "watch"
        k[UPowerDeviceType.BluetoothGeneric] = "bluetooth"
        k[UPowerDeviceType.RemoteControl]    = ""
        k[UPowerDeviceType.Toy]              = ""
        k[UPowerDeviceType.Camera]           = ""
        k[UPowerDeviceType.MediaPlayer]      = ""
        return k
    }

    // ══ Brand marks ═══════════════════════════════════════════════════════════
    // A Razer device is drawn as Razer's snake (the user's call), lifted out of an
    // app icon in the INSTALLED icon theme by scripts/theme-logo.py — a brand's logo
    // is never shipped in this published repo. Once, when a Razer device first shows
    // up; "" (the plain kind glyph) when no theme has one.
    function logoFor(d) { return d && String(d.key).startsWith("razer:") ? root._razerLogo : "" }
    property string _razerLogo: ""
    readonly property string _logoFile:
        (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache"))
        + "/quickshell-quicktest/logos/razer.svg"
    readonly property bool razerPresent: root._razer.length > 0
    onRazerPresentChanged: if (root.razerPresent && root._razerLogo === "" && !logoProc.running) logoProc.running = true

    Process {
        id: logoProc
        // Papirus names it after the Razer tools it themes; the first one found wins.
        command: ["python3", Quickshell.shellPath("scripts/theme-logo.py"), root._logoFile,
                  "razercommander", "xyz.z3ntu.razergenie", "polychromatic", "openrazer"]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = text.trim()
                if (path !== "") root._razerLogo = "file://" + path
            }
        }
    }

    // ══ OpenRazer ═════════════════════════════════════════════════════════════
    property var _razer: []
    property int _refs: 0
    function acquire() { root._refs++ }
    function release() { root._refs = Math.max(0, root._refs - 1) }

    Timer {
        running: root._refs > 0
        interval: 60000
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!razerProc.running) razerProc.running = true
    }

    Process {
        id: razerProc
        // Through python3, so a missing executable bit can't silence it.
        command: ["python3", Quickshell.shellPath("scripts/razer-batteries.py")]
        stdout: StdioCollector {
            onStreamFinished: root._razer = Stats.parseRazer(text)
        }
    }
}
