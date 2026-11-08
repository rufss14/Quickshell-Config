pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import QtQuick

// ── Net ───────────────────────────────────────────────────────────────────────
// The shell's single network authority, backed by the native Networking service
// (NetworkManager over D-Bus).
//
// NAME: this is `Net`, not `Network`, because Quickshell.Networking already
// exports a type called `Network` (the base type of WifiNetwork). A singleton
// named `Network` is shadowed by it in any file that imports the module, and
// silently resolves to the wrong thing. Don't "fix" this back.
// The same trap bit `Palette` — QtQuick exports one — which is why the color
// singleton is `Colors`.
//
// This replaces every `nmcli` subprocess in the shell. Before: WifiButton ran a
// `sh -c` pipeline every 8s, WifiPanel ran a rescan-and-parse pipeline every
// 15s (plus `nmcli con show` and an `ip addr` pipeline behind it), and the bar
// builds both its layouts, so those pollers existed twice over. State was up to
// 8s stale, and connecting meant scraping human-readable error text out of
// nmcli's stderr with a regex.
//
// NetworkManager pushes state changes. Nothing here polls.
//
// ── Scanning is refcounted ────────────────────────────────────────────────────
// Continuously scanning for access points costs real radio time and is only
// worth paying for while a user is actually looking at a network list. The
// scanner is therefore off by default; a panel calls acquireScan() when it
// opens and releaseScan() when it closes. The bar's wifi indicator does NOT
// scan — the *connected* network is known without scanning, which is all the
// indicator ever needed.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── Device ────────────────────────────────────────────────────────────────
    readonly property var wifiDevice: Networking.devices.values.find(
        d => d.type === DeviceType.Wifi) ?? null

    readonly property bool hasWifi:     wifiDevice !== null
    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property bool wifiBlocked: !Networking.wifiHardwareEnabled   // rfkill

    // Local IP of the wifi device — the panel shows this, blurred until asked.
    readonly property string address: wifiDevice?.address ?? ""

    // ── Wired ─────────────────────────────────────────────────────────────────
    // No scan, no list, no password — a cable is either plugged in or it isn't, and
    // NetworkManager auto-connects it. This is only ever a status readout.
    readonly property var wiredDevice: Networking.devices.values.find(
        d => d.type === DeviceType.Wired) ?? null

    readonly property bool   hasWired:      wiredDevice !== null
    readonly property bool   wiredConnected: wiredDevice?.connected ?? false
    readonly property string wiredAddress:  wiredDevice?.address ?? ""

    // `hasLink` is the PHY layer — a cable is physically plugged in and negotiated —
    // and can be true while `connected` is still false (DHCP in flight, or the
    // profile isn't set to autoconnect). Distinct facts; collapsing them into one
    // reads "unplugged" for a cable that's actually just still negotiating.
    readonly property bool hasLink:        wiredDevice?.hasLink ?? false
    // Mbps, 0 until the link is up. WiredDevice-only — Quickshell has no equivalent
    // for wifi (see NetStats' own docstring on why link speed isn't shown there).
    readonly property int  wiredLinkSpeed: wiredDevice?.linkSpeed ?? 0

    readonly property bool online: Networking.connectivity === NetworkConnectivity.Full

    // ── Networks ──────────────────────────────────────────────────────────────
    // Strongest first, with the connected network pinned to the top. Sorting
    // here rather than in the panel means the bar indicator and the panel can
    // never disagree about which access point is "the" one.
    readonly property var networks: {
        if (!wifiDevice) return []
        const list = wifiDevice.networks.values.slice()
        list.sort((a, b) => {
            if (a.connected !== b.connected) return a.connected ? -1 : 1
            return (b.signalStrength ?? 0) - (a.signalStrength ?? 0)
        })
        return list
    }

    readonly property var active: networks.find(n => n.connected) ?? null

    readonly property string ssid:      active?.name ?? ""
    readonly property bool   connected: active !== null

    // signalStrength is normalized 0..1 by the backend. The UI thinks in
    // percent, so convert once, here, instead of at every call site.
    readonly property int strength: active ? Math.round((active.signalStrength ?? 0) * 100) : -1

    // ── Scanning ──────────────────────────────────────────────────────────────
    property int _scanRefs: 0

    function acquireScan() {
        root._scanRefs++
        if (root.wifiDevice) root.wifiDevice.scannerEnabled = true
    }
    function releaseScan() {
        root._scanRefs = Math.max(0, root._scanRefs - 1)
        if (root._scanRefs === 0 && root.wifiDevice)
            root.wifiDevice.scannerEnabled = false
    }

    // If the device appears after a panel already asked to scan (e.g. a USB
    // adapter plugged in while the panel is open), honor the outstanding
    // request instead of silently never scanning.
    onWifiDeviceChanged: {
        if (wifiDevice) wifiDevice.scannerEnabled = root._scanRefs > 0
    }

    readonly property bool scanning: wifiDevice?.scannerEnabled ?? false

    // ── Control ───────────────────────────────────────────────────────────────
    function setWifiEnabled(on) { Networking.wifiEnabled = on }
    function toggleWifi()       { Networking.wifiEnabled = !Networking.wifiEnabled }

    // A "known" network already has saved credentials, so connect() is enough.
    // An unknown secured one needs the passphrase. Callers that don't want to
    // reason about that can just call this and check `needsPassword` first.
    //
    // `Open` is an unsecured network and `Owe` is opportunistic wireless
    // encryption — encrypted, but with no passphrase to ask the user for. Both
    // connect without a prompt.
    function needsPassword(network) {
        if (!network) return false
        if (network.known) return false
        return network.security !== WifiSecurityType.Open
            && network.security !== WifiSecurityType.Owe
    }

    // Whether to draw a lock next to a network in the list.
    function isSecured(network) {
        if (!network) return false
        return network.security !== WifiSecurityType.Open
            && network.security !== WifiSecurityType.Owe
    }

    function connect(network, psk) {
        if (!network) return
        if (psk !== undefined && psk !== "") network.connectWithPsk(psk)
        else                                 network.connect()
    }

    // A hidden network isn't in the scan list, so there's no Network object to call
    // connect() on, and Quickshell.Networking can't create one by name.
    // scripts/wifi-hidden.py does it over D-Bus with the passphrase on its STDIN —
    // never argv, where every local user can read it (it used to be an `nmcli … password
    // <psk>` from the panel). A failure lands in lastError like any other.
    property string _hiddenRequest: ""
    function connectHidden(ssid, psk) {
        if (!ssid) return
        root.lastError = ""
        root._hiddenRequest = JSON.stringify({ ssid: ssid, psk: psk || "" })
        hiddenProc.stdinEnabled = true   // re-armed before every start: docs/gotchas-system.md
        hiddenProc.running = false
        hiddenProc.running = true
    }

    property Process _hiddenProc: Process {
        id: hiddenProc
        property string out: ""
        command: ["python3", Quickshell.shellPath("scripts/wifi-hidden.py")]
        stdinEnabled: true
        stdout: SplitParser { onRead: function (line) { hiddenProc.out += line } }
        onStarted: {
            hiddenProc.out = ""
            write(root._hiddenRequest + "\n")
            root._hiddenRequest = ""      // the secret doesn't outlive the write
            stdinEnabled = false
        }
        onExited: {
            let d = null
            try { d = JSON.parse(hiddenProc.out) } catch (e) {}
            if (!d) root.lastError = "Couldn't connect to the hidden network"
            else if (!d.ok) root.lastError = (d.error || "Couldn't connect") + " — hidden network"
        }
    }

    function disconnect() { if (root.active) root.active.disconnect() }
    function forget(network) { if (network) network.forget() }

    // ── Connection progress / failure ─────────────────────────────────────────
    // The network currently negotiating, if any. NetworkManager exposes this as
    // per-network `stateChanging`, so there is nothing to track by hand — the old
    // panel kept its own `connectingSsid` string and cleared it when an nmcli
    // process exited, which meant it could get stuck set if the process died.
    readonly property var connecting: networks.find(n => n.stateChanging) ?? null

    // Last failure, as a human-readable string. The old panel scraped this out of
    // nmcli's stderr with `l.match(/error|fail/i)` — a regex over human-readable
    // CLI output, in whatever language the user's locale happened to be. This is
    // a typed enum from NetworkManager.
    property string lastError: ""
    function clearError() { root.lastError = "" }

    Instantiator {
        model: root.networks
        delegate: Connections {
            required property var modelData
            target: modelData
            function onConnectionFailed(reason) {
                root.lastError = ConnectionFailReason.toString(reason)
                    + " — " + (modelData.name || "network")
            }
        }
    }

    // ── Presentation helpers ──────────────────────────────────────────────────
    // Security as a short label ("WPA2", "Open"). Derived from the typed enum
    // rather than from a scraped nmcli SECURITY column.
    function securityLabel(network) {
        if (!network) return ""
        switch (network.security) {
            case WifiSecurityType.Open:          return "Open"
            case WifiSecurityType.Owe:           return "OWE"
            case WifiSecurityType.StaticWep:
            case WifiSecurityType.DynamicWep:    return "WEP"
            case WifiSecurityType.Leap:          return "LEAP"
            case WifiSecurityType.WpaPsk:        return "WPA"
            case WifiSecurityType.Wpa2Psk:       return "WPA2"
            case WifiSecurityType.Sae:           return "WPA3"
            case WifiSecurityType.WpaEap:
            case WifiSecurityType.Wpa2Eap:       return "Enterprise"
            case WifiSecurityType.Wpa3SuiteB192: return "WPA3-Suite-B"
            default:                             return "Secured"
        }
    }

    // A network's signal as a percentage. signalStrength is normalized 0..1 by
    // the backend; the UI thinks in percent, so convert once, here.
    function strengthOf(network) {
        return network ? Math.round((network.signalStrength ?? 0) * 100) : 0
    }

    // Signal → bar count and glyph. Shared so the bar pill and the panel list
    // can't drift apart on where "3 bars" starts.
    function bars(strengthPercent) {
        if (strengthPercent < 20) return 1
        if (strengthPercent < 45) return 2
        if (strengthPercent < 65) return 3
        return 4
    }

    // Wired link speed as a short label ("1 Gbps", "100 Mbps"). "" until the link
    // is actually up — shared so the popup and the settings page can't format the
    // same Mbps figure two different ways.
    function wiredSpeedLabel() {
        if (root.wiredLinkSpeed <= 0) return ""
        if (root.wiredLinkSpeed % 1000 === 0) return (root.wiredLinkSpeed / 1000) + " Gbps"
        if (root.wiredLinkSpeed >= 1000)      return (root.wiredLinkSpeed / 1000).toFixed(1) + " Gbps"
        return root.wiredLinkSpeed + " Mbps"
    }

    // The wired status in one word — the three real states a cable can be in.
    // "Connecting" isn't a guess: `hasLink` (PHY layer, negotiated) can be true
    // while `connected` (has an IP) is still false, and that gap is exactly DHCP
    // in flight or a profile that isn't set to autoconnect.
    function wiredStateLabel() {
        if (root.wiredConnected) return "Connected"
        if (root.hasLink)        return "Connecting…"
        return "Unplugged"
    }

    function glyph() {
        // Wired wins the shared glyph: it's the higher-priority route whenever both
        // are up, and there's no "signal strength" to show for a cable anyway.
        if (root.wiredConnected) return "󰈀"
        if (!root.wifiEnabled) return "󰤭"
        if (!root.connected)   return "󰤫"
        switch (root.bars(root.strength)) {
            case 1:  return "󰤟"
            case 2:  return "󰤢"
            case 3:  return "󰤥"
            default: return "󰤨"
        }
    }

    // The wifi (non-wired) states from glyph(), resolving a Material Symbols icon
    // URL instead of a Nerd Font codepoint — matching Settings/Overview/Wallpaper/
    // Bell. No wired branch: wired went through an SVG (Fluent, then Material)
    // and was asked back to the plain glyph — WifiPill checks Net.wiredConnected
    // itself and calls glyph() for that case instead of this one. Resolved here
    // rather than left as a bare name so the caller doesn't need to know which
    // folder a given state's icon lives in.
    function iconPath() {
        if (!root.wifiEnabled) return Icons.asset("wifioff")
        if (!root.connected)   return Icons.asset("wifiwarning")
        switch (root.bars(root.strength)) {
            case 1:  return Icons.asset("wifi1")
            case 2:  return Icons.asset("wifi2")
            case 3:  return Icons.asset("wifi3")
            default: return Icons.asset("wifi4")
        }
    }
}
