pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import QtQuick
import "../config"
import "bt.js" as B

// ── Bt ────────────────────────────────────────────────────────────────────────
// The shared Bluetooth derivations: which adapter we're talking to, which devices
// are ours, and how to render one.
//
// ── Why this exists now, and didn't before ────────────────────────────────────
// BluetoothPage said it plainly: "there is deliberately no service wrapper — unlike
// Audio (which exists to filter the PipeWire registry) there is no logic to
// centralise, and a wrapper would just be a second name for the same objects. If a
// bar module ever wants Bluetooth, the shared bits get extracted then."
//
// A bar module now wants Bluetooth, so this is that moment, and the judgement holds
// up: what's below is only the parts with actual LOGIC in them. Nothing here wraps a
// BlueZ object for the sake of renaming it — the page and the panel both still talk
// to `adapter.enabled`, `device.connect()` and `device.trusted` directly, because
// those are already the right API and a passthrough property would just be a second
// place for them to rot.
//
// What genuinely could not be duplicated:
//   · deviceGlyph — a cmap-verified icon table. Two copies means one of them is
//     wrong the first time a glyph is corrected.
//   · batteryLevel — carries an UNVERIFIED assumption (see below). An assumption
//     recorded in one place is a note; recorded in two, it's a bug waiting for the
//     copies to disagree.
//   · known — "paired OR bonded", sorted connected-first. The subtle bit is the OR.
//   · adapter — the "" = follow-the-default resolution.
//
// ── Why it is named Bt and not Bluetooth ─────────────────────────────────────
// `Quickshell.Bluetooth` already exports a singleton called `Bluetooth`, and every
// file here imports it. A second `Bluetooth` would shadow it, and which one won
// would depend on import order. Same shape as `Net` sitting in front of
// NetworkManager.
//
// ── Costs nothing to keep alive ──────────────────────────────────────────────
// Pure bindings over a model BlueZ already pushes, plus one Connections per device
// for the activity feed. No timers, no polling, no subprocesses — so the bar pill
// referencing this (which makes it permanent) adds no idle cost. Discovery is the
// one expensive operation: it lives here only as a reference count
// (acquireScan/releaseScan), so it runs exactly while a surface showing Nearby is
// open and never on its own.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── Adapter selection ─────────────────────────────────────────────────────
    // Config.btAdapter: "" = follow whatever BlueZ calls the default, or a DBUS PATH
    // to pin one.
    //
    // The path, never an index: adapters come and go (a dongle is unplugged) and an
    // index would silently start pointing at a different controller. Resolving from
    // the path means a vanished adapter falls back to the default by itself, with no
    // assignment anywhere to break.
    //
    // It is a persisted preference, not a property here or on the page: a local one
    // was destroyed every time you navigated off BluetoothPage (settings pages live
    // behind a Loader), and one on this singleton still reset on every reload — a
    // pinned adapter silently reverted to the default. Config keeps it, so the bar
    // panel and the page can't be talking to two different controllers.

    readonly property var adapters: Bluetooth.adapters.values

    readonly property var adapter: {
        const list = root.adapters
        if (Config.btAdapter !== "")
            for (let i = 0; i < list.length; i++)
                if (list[i].dbusPath === Config.btAdapter) return list[i]
        return Bluetooth.defaultAdapter
    }

    // Is there Bluetooth on this machine at all. The gate for the bar pill and for
    // the settings page's presence in the rail — one expression, so the pill and the
    // page can never disagree about whether this machine has an adapter.
    readonly property bool available: root.adapters.length > 0

    readonly property bool powered: root.adapter
        && root.adapter.state === BluetoothAdapterState.Enabled

    // ── Device lists ──────────────────────────────────────────────────────────
    // Reads of dev.paired / dev.connected inside these bindings register as QML
    // dependencies, so a device pairing or connecting re-sorts the lists on its own.
    //
    // "Known" is paired OR bonded rather than paired alone: BlueZ keeps the two flags
    // subtly distinct (bonding is the stored key), and a device with either is one
    // you own, not one to re-pair.
    readonly property var known: {
        const out = []
        if (!root.adapter) return out
        const list = root.adapter.devices.values
        for (let i = 0; i < list.length; i++) {
            const d = list[i]
            if (d.paired || d.bonded) out.push(d)
        }
        out.sort((a, b) => (b.connected - a.connected)
                        || (a.name || a.address).localeCompare(b.name || b.address))
        return out
    }

    // Devices in radio range that aren't ours AND have identified themselves — a
    // real name (`deviceName`, BlueZ's `Name`) or a class/appearance `icon`.
    //
    // The bare-MAC case isn't sunk to the bottom any more, it's dropped. A scan
    // sweeps up passing BLE beacons that broadcast nothing but a random address —
    // a phone's Apple advertisement, a neighbour's TV — and none of them can be
    // paired from this list. Kept visible (even sunk) they were the ONLY thing to
    // click when the device you actually wanted wasn't in pairing mode, with a
    // live Pair button that could only ever fail: connect, bond-timeout,
    // disconnect, repeat. `deviceName` is the honest signal — BlueZ leaves `Name`
    // absent for a nameless device and only `Alias` falls back to the address
    // (dash-formatted, so it isn't even `=== address`). `pairing` keeps an
    // in-flight attempt on screen even if its name hasn't arrived yet.
    //
    // The settings page and the panel's Nearby tab both render this. It lives
    // beside `known` because the two are one decision — the predicate is
    // the same fact read both ways, and splitting them across two files is how they
    // end up disagreeing about what "ours" means.
    //
    // Closest first (BtBridge's RSSI, in BARS — bt.js compareNearby says why not
    // dBm), then by name. Consumers wrap it in a ScriptModel: this re-sorts on every
    // RSSI flush during a scan, and a bare array as a Repeater model would rebuild
    // every row each time.
    readonly property var nearby: {
        const out = []
        if (!root.adapter) return out
        const list = root.adapter.devices.values
        for (let i = 0; i < list.length; i++) {
            const d = list[i]
            if (d.paired || d.bonded) continue
            if (!d.pairing && !d.deviceName && !d.icon) continue
            out.push(d)
        }
        const bars = BtBridge.rssi                      // dependency: re-sort on a flush
        out.sort((a, b) => B.compareNearby(
            { name: a.name || a.address, bars: B.signalBars(bars[a.address]) },
            { name: b.name || b.address, bars: B.signalBars(bars[b.address]) }))
        return out
    }

    // A device on the current adapter by MAC, or null — for the helper's events,
    // which only know addresses.
    function deviceFor(address) {
        if (!root.adapter || !address) return null
        const a = String(address).toUpperCase()
        const list = root.adapter.devices.values
        for (let i = 0; i < list.length; i++)
            if (list[i].address.toUpperCase() === a) return list[i]
        return null
    }

    // Rename: BlueZ's Alias (Quickshell's writable `name`). "" hands the device its
    // own name back. Validated in bt.js cleanAlias; false = refused, nothing written.
    function rename(dev, text) {
        const clean = B.cleanAlias(text)
        if (!dev || clean === null) return false
        if (clean !== dev.name) dev.name = clean
        return true
    }

    // ── Discovery, reference-counted ──────────────────────────────────────────
    // Two surfaces scan now — the settings page's Nearby section and the panel's
    // Nearby tab — so neither may write `discovering` directly: the panel closing
    // would stop a scan the page is still showing. Each holder acquires; the radio
    // scans while anyone holds. Scanning keeps the radio probing, so it is never
    // started without a holder and stops with the last one.
    property int _scanHolds: 0
    readonly property bool scanning: root.adapter ? root.adapter.discovering : false

    function acquireScan() { root._scanHolds++; root._applyScan() }
    function releaseScan() { root._scanHolds = Math.max(0, root._scanHolds - 1); root._applyScan() }

    function _applyScan() {
        if (!root.adapter) return
        const want = root._scanHolds > 0 && root.powered
        if (root.adapter.discovering !== want) root.adapter.discovering = want
    }
    // The radio coming on (or a different adapter being picked) while someone is
    // holding a scan should start it — the hold was taken before there was anything
    // to scan with.
    onPoweredChanged: root._applyScan()
    onAdapterChanged: root._applyScan()

    // ── Actions with an order to them ─────────────────────────────────────────
    // Trusted BEFORE pairing, the bluetoothctl order: otherwise a paired device
    // still asks permission on every reconnect, which reads as "keeps
    // disconnecting". And pairing alone leaves a device paired but idle — the
    // person pressed Pair because they want to USE it — so a pairing started here
    // connects once it lands (see onPairedChanged below).
    property var _connectAfterPair: ({})

    function pair(dev) {
        if (!dev) return
        if (dev.pairing) { dev.cancelPair(); return }
        const next = Object.assign({}, root._connectAfterPair)
        next[dev.address] = true
        root._connectAfterPair = next
        dev.trusted = true
        dev.pair()
    }

    function toggleConnection(dev) {
        if (!dev) return
        if (dev.connected) dev.disconnect()
        else               dev.connect()
    }

    function _dropPending(address) {
        if (!(address in root._connectAfterPair)) return
        const next = Object.assign({}, root._connectAfterPair)
        delete next[address]
        root._connectAfterPair = next
    }

    // ── Activity feed ─────────────────────────────────────────────────────────
    // Pairing failures surface ONLY as terminal warnings from Quickshell — a pair
    // attempt that times out leaves every surface looking as if nothing happened. A
    // pairing that ENDS without the paired flag is detectable, so the feed says so
    // the moment it happens. It answers "did that click do anything".
    //
    // Lived on the settings page until the panel learned to pair too; there it was
    // destroyed with the page (settings pages sit behind a Loader), so a failure
    // from the panel had nowhere to be reported. One Connections per device, all
    // event-driven — keeping it alive with the service costs nothing idle.
    readonly property int eventsKept: 5
    property var events: []                  // [{ t, ms, text, kind }] newest first

    function logEvent(text, kind) {
        const now = new Date()
        root.events = [{
            t:  Qt.formatTime(now, "HH:mm:ss"),
            ms: now.getTime(),
            text: text,
            kind: kind
        }].concat(root.events).slice(0, root.eventsKept)
    }

    function clearEvents() { root.events = [] }

    // Instantiator rather than a Repeater because there is nothing visual to parent.
    Instantiator {
        model: root.adapter ? root.adapter.devices : null
        delegate: Connections {
            id: watcher
            required property var modelData
            target: watcher.modelData

            function onPairingChanged() {
                const d = watcher.modelData
                const who = d.name || d.address
                if (d.pairing) {
                    root.logEvent("Pairing with " + who + "…", "info")
                } else if (!d.paired) {
                    root._dropPending(d.address)
                    let msg = "Pairing with " + who
                            + " failed — check it's in pairing mode and in range."
                    if ((d.icon || "").includes("phone"))
                        msg += " Phones also ask for a confirmation this shell can't"
                             + " show; try starting the pairing from the phone."
                    root.logEvent(msg, "fail")
                }
            }
            function onPairedChanged() {
                const d = watcher.modelData
                root.logEvent((d.name || d.address)
                    + (d.paired ? " paired" : " unpaired"), d.paired ? "ok" : "info")
                if (d.paired && (d.address in root._connectAfterPair)) {
                    root._dropPending(d.address)
                    d.connect()
                }
            }
            function onConnectedChanged() {
                const d = watcher.modelData
                root.logEvent((d.name || d.address)
                    + (d.connected ? " connected" : " disconnected"),
                    d.connected ? "ok" : "info")
                root._announce(d)
                if (d.connected) root._checkBattery(d)
            }
            function onBatteryChanged() { root._checkBattery(watcher.modelData) }
        }
    }

    // ── Connect / disconnect OSD ──────────────────────────────────────────────
    // A speaker that drops out is otherwise silent — the music just moves to the
    // laptop speakers. Glyph, "<name> connected", and its battery as the meter
    // when it reports one (no meter otherwise; a full bar would claim 100%).
    function _announce(d) {
        if (!Config.btConnectOsd) return
        const batt = d.connected && root.hasBattery(d)
        Osd.announce("bluetooth", root.deviceGlyph(d),
                     (d.name || d.address) + (d.connected ? " connected" : " disconnected"),
                     batt ? Math.round(root.batteryLevel(d) * 100) + "%" : "",
                     batt ? root.batteryLevel(d) : -1,
                     !d.connected)
    }

    // ── Low battery ───────────────────────────────────────────────────────────
    // At Config.btBatteryLow and again at half of it, once each per discharge —
    // bt.js batteryAlert holds the hysteresis (and is tested). Clamped here: the
    // threshold comes from a hand-editable config.json.
    property var _battWarned: ({})           // address → threshold already warned at
    readonly property real _battLow:
        Math.max(Config.btBatteryLowMin, Math.min(Config.btBatteryLowMax, Config.btBatteryLow)) / 100

    function _checkBattery(d) {
        if (!Config.btBatteryWarn || !d || !d.connected || !root.hasBattery(d)) return
        const level = root.batteryLevel(d)
        const r = B.batteryAlert(level, root._battWarned[d.address] ?? 1, root._battLow)
        if (r.last !== (root._battWarned[d.address] ?? 1)) {
            const next = Object.assign({}, root._battWarned)
            next[d.address] = r.last
            root._battWarned = next
        }
        if (r.alert === "") return
        const pct = Math.round(level * 100)
        root._notify(r.alert === "critical" ? "critical" : "normal",
                     (d.name || d.address) + " battery " + (r.alert === "critical" ? "critical" : "low"),
                     pct + "% left" + (r.alert === "critical" ? " — charge it soon" : ""))
    }

    property Process _notifyProc: Process {}
    function _notify(urgency, title, body) {
        root._notifyProc.command = ["notify-send", "--app-name=Quickshell", "--urgency=" + urgency,
                                    "--icon=battery-caution", title, body]
        root._notifyProc.running = false
        root._notifyProc.running = true
    }

    readonly property int connectedCount: {
        let n = 0
        for (const d of root.known) if (d.connected) n++
        return n
    }

    // The first connected device, for surfaces with room to name exactly one — the
    // bar pill's label. `known` is sorted connected-first, so this is its head.
    readonly property var primary: root.connectedCount > 0 ? root.known[0] : null

    // The connected device with the least charge that reports one — the bar pill's
    // ring. null when nothing connected reports a battery.
    readonly property var lowestBattery: {
        let best = null
        for (const d of root.known) {
            if (!d.connected || !root.hasBattery(d)) continue
            if (best === null || root.batteryLevel(d) < root.batteryLevel(best)) best = d
        }
        return best
    }

    // ── Rendering a device ────────────────────────────────────────────────────
    // `icon` is a freedesktop icon name ("audio-headset", "input-mouse", …). Substring
    // matches because BlueZ has several variants per family. Every glyph below is
    // cmap-verified against the shipped font, not assumed.
    function deviceGlyph(dev) {
        const i = dev?.icon || ""
        if (i.includes("headset") || i.includes("headphone")) return "󰋋"
        if (i.includes("mouse"))    return "󰍽"
        if (i.includes("keyboard")) return "󰌌"
        if (i.includes("phone"))    return "󰄜"
        if (i.includes("gaming") || i.includes("joypad")) return "󰊖"
        if (i.includes("computer")) return "󰌢"
        if (i.includes("watch"))    return "󰖗"
        if (i.includes("display") || i.includes("tv")) return "󰠹"
        if (i.includes("audio"))    return "󰓃"
        return "󰂯"
    }

    function stateCaption(dev) {
        if (!dev) return ""
        if (dev.pairing) return "Pairing…"
        switch (dev.state) {
        case BluetoothDeviceState.Connecting:    return "Connecting…"
        case BluetoothDeviceState.Disconnecting: return "Disconnecting…"
        case BluetoothDeviceState.Connected:     return "Connected"
        default: return "Paired"
        }
    }

    // `battery` has not been exercised against a real device on this machine (nothing
    // with battery reporting is paired yet), so the scale — 0..1 vs 0..100 — is
    // unverified. Normalising covers both rather than betting on one.
    function batteryLevel(dev) {
        const b = dev?.battery ?? 0
        return Math.max(0, Math.min(1, b > 1 ? b / 100 : b))
    }

    // Whether to draw a battery reading at all — `batteryAvailable`, nothing more.
    //
    // The tempting extra condition is `&& battery > 0`, to suppress a device that
    // advertises the property but hasn't been read yet. It is NOT here, because it
    // cannot be distinguished from the case that matters most: a genuinely flat
    // device reading 0% is exactly when you want to see the number. Nothing paired to
    // this machine reports battery, so which of the two actually occurs is untested —
    // and between an occasional spurious 0% and hiding a dead headset, the spurious
    // 0% is the one that doesn't mislead.
    function hasBattery(dev) {
        return dev?.batteryAvailable ?? false
    }

    // The adapter-level glyph: connected, on, or off. Shared by the pill and both
    // headers so the icon means the same thing everywhere it appears.
    readonly property string glyph:
          !root.powered            ? "󰂲"
        : root.connectedCount > 0  ? "󰂱"
        :                            "󰂯"

    // Same three states as glyph, resolving a Material Symbols icon instead —
    // matching Settings/Overview/Wallpaper/Bell, asked for after the Fluent
    // rune read as blobby at bar-icon size.
    readonly property url iconPath:
          !root.powered            ? Icons.asset("bluetoothoff")
        : root.connectedCount > 0  ? Icons.asset("bluetoothconnected")
        :                            Icons.asset("bluetooth")
}
