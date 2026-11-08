pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// ── NetStats ──────────────────────────────────────────────────────────────────
// The active link's live numbers: throughput and the addressing facts NetworkManager
// doesn't hand out, plus signal in dBm when that link happens to be wireless.
//
// ── Why this exists beside Net ────────────────────────────────────────────────
// Net is NetworkManager, typed, over D-Bus — the right source for anything NM knows.
// It just doesn't know much: `WifiNetwork` exposes `signalStrength` and `security`,
// and that is the whole of it. No dBm, no gateway, no DNS, no byte counters. Those
// are kernel facts, and the kernel publishes them in /proc and /sys.
//
// So: Net answers "what network am I on and how do I join another", this answers
// "what is that link actually doing right now". Neither belongs inside the other.
//
// ── FileView, not `iw` or `ip` ────────────────────────────────────────────────
// Every number here comes from a file read in-process. That is not an accident of
// taste: the panel this feeds used to be seven `nmcli` subprocesses and a rescan
// timer that ran whether or not anyone was looking, and it was rewritten precisely
// to stop doing that. Adding `iw dev … link` on a 1s poll would put the subprocesses
// straight back, one sample at a time.
//
// ── Refcounted, and that is the whole design ──────────────────────────────────
// Copied from SysInfo, for the same reason: a Timer left running samples six files a
// second, forever, for a readout nobody is looking at. The settings page acquires on
// open and releases on close; nothing samples in between.
//
// ── What the kernel will NOT tell us ──────────────────────────────────────────
// Deliberately absent rather than guessed:
//   • frequency / band (2.4 / 5 / 6 GHz) — nl80211 only. `iw` isn't installed, and
//     Quickshell's WifiNetwork has no frequency property.
//   • link speed / bitrate — /sys/class/net/<if>/speed returns EINVAL on wireless
//     (it's a wired-only file). Quickshell has `linkSpeed`, but on WiredDevice —
//     that's why it's `Net.wiredLinkSpeed`, not a NetStats property.
//   • noise / SNR — /proc/net/wireless reports -256, which is its "not supported"
//     sentinel on this hardware, not a reading.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property int _refs: 0
    function acquire() { root._refs++ }
    function release() { root._refs = Math.max(0, root._refs - 1) }

    readonly property bool active: root._refs > 0

    // ── The interface ─────────────────────────────────────────────────────────
    // The default route's own device (see the route FileView below) — kernel truth,
    // and it doesn't care whether that device is wireless or wired.
    //
    // This used to be read out of /proc/net/wireless instead: "that file only ever
    // lists wireless devices, so its first row IS the answer" — which quietly assumed
    // wifi was always the connection in use. On ethernet that file has no rows at
    // all, so `_iface` never left "", and everything keyed off it — throughput,
    // MAC, MTU, gateway, the desktop widget's own label — went blank the moment a
    // cable, not the radio, was carrying the connection. /proc/net/wireless is now
    // only consulted to answer "does the ACTIVE interface happen to be wireless",
    // which is what the signal-level reading actually needs.
    readonly property string iface: root._iface
    property string _iface: ""

    // ── Signal ────────────────────────────────────────────────────────────────
    // dBm. Roughly: -30 excellent, -67 good, -70 usable, -80 poor, -90 unusable.
    readonly property int  level: root._level
    readonly property bool hasLevel: root._iface !== "" && root._level < 0

    // The kernel's own 0..70 link-quality figure. Kept because it's what the driver
    // actually reports, where Net.strength is NetworkManager's normalised percentage.
    readonly property int link: root._link

    property int _level: 0
    property int _link:  0

    // Oldest first, fixed length — the sparkline's x-axis is "the last
    // `levelHistoryLength` samples" and never rescales.
    readonly property var levelHistory: root._levelHistory
    readonly property int levelHistoryLength: 60
    property var _levelHistory: []

    // ── Throughput ────────────────────────────────────────────────────────────
    // Bytes per second, from the interface's cumulative counters. A DELTA, like CPU
    // jiffies: rx_bytes is "since the link came up", so a single read is an average
    // over hours — a number that barely moves and looks broken.
    //
    // Sampled 4× faster than the signal, and that asymmetry is measured rather than
    // assumed: reading the byte counters ten times at 200ms apart returns ten
    // different numbers, so the resolution is really there to be had. Reading
    // /proc/net/wireless at the same cadence returns the SAME dBm ten times — the
    // driver only refreshes it about once a second, so a faster poll there would
    // draw duplicate points and call it detail.
    readonly property real rxRate: root._rxRate
    readonly property real txRate: root._txRate
    readonly property var  rxHistory: root._rxHistory
    readonly property var  txHistory: root._txHistory

    // ── Cumulative totals ─────────────────────────────────────────────────────
    // The raw counter values, not a delta — bytes carried since the interface came
    // up (a boot, or NetworkManager bringing the link up on connect). We already read
    // these files for the rate; the delta throws the absolute away, so surfacing it is
    // free. Honest label is "since the connection came up", NOT "this open" — the
    // kernel counts from the link, not from when you opened the page.
    readonly property real rxTotal: root._rxTotal
    readonly property real txTotal: root._txTotal
    property real _rxTotal: 0
    property real _txTotal: 0

    // 240 samples at 250ms — the same 60s window as the signal, at 4× the vertices.
    readonly property int rateHistoryLength: 240

    property real _rxRate: 0
    property real _txRate: 0
    property var  _rxHistory: []
    property var  _txHistory: []

    property real _prevRx: -1
    property real _prevTx: -1

    // ── Addressing ────────────────────────────────────────────────────────────
    readonly property string gateway: root._gateway
    readonly property var    dns:     root._dns       // [string]
    readonly property string mac:     root._mac
    readonly property int    mtu:     root._mtu

    property string _gateway: ""
    property var    _dns: []
    property string _mac: ""
    property int    _mtu: 0

    // ── Two cadences ──────────────────────────────────────────────────────────
    // Split because the sources refresh at different speeds (see Throughput above).
    // Polling everything at 250ms would quadruple the file reads to redraw numbers
    // that hadn't changed; polling everything at 1s throws away throughput detail
    // the kernel is genuinely offering.
    readonly property int levelInterval: 1000
    readonly property int rateInterval:  250

    // The slow one: signal, addressing, hardware facts. None of these move faster
    // than the driver's ~1s refresh, and MTU/MAC essentially never move at all.
    Timer {
        running: root.active
        interval: root.levelInterval
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            // Route first: it's what decides `_iface` now, and the wireless lookup
            // right after it needs that decision already made.
            routeFile.reload()
            wirelessFile.reload()
            resolvFile.reload()
            if (root._iface === "") return
            macFile.reload()
            mtuFile.reload()
        }
    }

    // The fast one: two counter files, nothing else.
    Timer {
        running: root.active && root._iface !== ""
        interval: root.rateInterval
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            rxFile.reload()
            txFile.reload()
        }
    }

    // Reset on release so the next open starts clean rather than splicing a fresh
    // sample onto a delta from minutes ago — which renders as one giant spike.
    onActiveChanged: {
        if (root.active) return
        root._levelHistory = []
        root._rxHistory = []
        root._txHistory = []
        root._prevRx = -1
        root._prevTx = -1
        root._rxRate = 0
        root._txRate = 0
    }

    // Switching interface resets the deltas too: subtracting wlan0's counter from
    // wlan1's is meaningless, and the difference between two unrelated cumulative
    // totals draws as one enormous spike.
    onIfaceChanged: {
        root._prevRx = -1
        root._prevTx = -1
        root._rxHistory = []
        root._txHistory = []
        root._levelHistory = []
    }

    // Replace, never push: appending to an array in place doesn't fire the change
    // signal, so the sparkline would never repaint. Same rule as Config.layout.
    //
    // Keeps limit+1, not limit. The extra one is for Sparkline's glide: as the trace
    // slides left, the oldest visible sample walks off the left edge, and without one
    // more behind it a gap opens and closes there every interval. `limit` remains the
    // number of samples you can SEE — the surplus is scaffolding, and the charts pass
    // `limit` as their capacity.
    function _append(arr, v, limit) {
        const cap = limit + 1
        const next = arr.concat([v])
        return next.length > cap ? next.slice(next.length - cap) : next
    }

    // ── /proc/net/wireless ────────────────────────────────────────────────────
    //   Inter-| sta-|   Quality        |   Discarded packets       | Missed | WE
    //    face | tus | link level noise |  nwid crypt frag retry misc | beacon | 22
    //   wlp5s0: 0000   55.  -55.  -256     0     0    0     0   18        0
    //
    // Two header lines, then one row per wireless interface. The numbers carry a
    // trailing '.' (it's a fixed-point field the kernel prints with a stray dot);
    // parseFloat eats it, parseInt would too, but Number("55.") is 55 and Number("")
    // is 0 — so parse deliberately, not with a cast.
    //
    // Looked up by `_iface` now rather than setting it: this file only ever lists
    // wireless devices, so on ethernet the loop below simply never matches anything,
    // which is exactly the "no signal level to show" case `hasLevel` already existed
    // for.
    FileView {
        id: wirelessFile
        path: "/proc/net/wireless"
        // preload is REQUIRED — FileView is lazy, and without it onLoaded never fires
        // and every readout sits at zero. Every FileView in this shell carries this
        // note for the same reason.
        preload: true
        printErrors: false

        onLoaded: {
            const lines = wirelessFile.text().split("\n")
            for (let i = 2; i < lines.length; i++) {
                const line = lines[i].trim()
                if (line === "" || line.indexOf(":") === -1) continue

                const iface = line.substring(0, line.indexOf(":")).trim()
                if (iface !== root._iface) continue     // not the active interface
                const rest  = line.substring(line.indexOf(":") + 1).trim().split(/\s+/)
                if (rest.length < 4) continue

                root._link  = Math.round(parseFloat(rest[1]))
                root._level = Math.round(parseFloat(rest[2]))
                if (root.active)
                    root._levelHistory = root._append(root._levelHistory, root._level,
                                                     root.levelHistoryLength)
                return
            }
            // Active interface isn't wireless (or there's no default route at all) —
            // nothing to show. `hasLevel` keys off `_level < 0`, so 0 reads as absent.
            root._level = 0
            root._link  = 0
        }
    }

    // ── Throughput counters ───────────────────────────────────────────────────
    FileView {
        id: rxFile
        path: root._iface !== "" ? "/sys/class/net/" + root._iface + "/statistics/rx_bytes" : ""
        preload: true
        printErrors: false
        onLoaded: {
            const v = parseFloat(rxFile.text().trim())
            if (isNaN(v)) return
            root._rxTotal = v
            // -1 is "no previous sample": the first read after an open has nothing to
            // subtract from, and treating it as a delta would draw the entire session's
            // traffic as one spike in the first pixel.
            if (root._prevRx >= 0)
                root._rxRate = Math.max(0, (v - root._prevRx) / (root.rateInterval / 1000))
            root._prevRx = v
            if (root.active)
                root._rxHistory = root._append(root._rxHistory, root._rxRate,
                                              root.rateHistoryLength)
        }
    }

    FileView {
        id: txFile
        path: root._iface !== "" ? "/sys/class/net/" + root._iface + "/statistics/tx_bytes" : ""
        preload: true
        printErrors: false
        onLoaded: {
            const v = parseFloat(txFile.text().trim())
            if (isNaN(v)) return
            root._txTotal = v
            if (root._prevTx >= 0)
                root._txRate = Math.max(0, (v - root._prevTx) / (root.rateInterval / 1000))
            root._prevTx = v
            if (root.active)
                root._txHistory = root._append(root._txHistory, root._txRate,
                                              root.rateHistoryLength)
        }
    }

    // ── Gateway, from /proc/net/route ─────────────────────────────────────────
    //   Iface  Destination  Gateway   Flags ...
    //   wlp5s0 00000000     0101A8C0  0003  ...
    //
    // Destination 00000000 is the default route. The addresses are little-endian hex
    // words, so the octets are stored backwards — 0101A8C0 reads as 192.168.1.1, right
    // to left. Getting that the wrong way round yields a plausible-looking 1.1.168.192,
    // which is exactly the kind of wrong that ships.
    function _hexToIp(hex) {
        const n = parseInt(hex, 16)
        if (isNaN(n)) return ""
        return [n & 255, (n >> 8) & 255, (n >> 16) & 255, (n >> 24) & 255].join(".")
    }

    FileView {
        id: routeFile
        path: "/proc/net/route"
        preload: true
        printErrors: false
        onLoaded: {
            const lines = routeFile.text().split("\n")
            for (let i = 1; i < lines.length; i++) {
                const p = lines[i].trim().split(/\s+/)
                if (p.length < 3) continue
                if (p[1] !== "00000000") continue        // not the default route
                // This row's device IS the active interface — see the docstring on
                // `iface` above for why that's decided here now, not in the wireless
                // file below.
                root._iface   = p[0]
                root._gateway = root._hexToIp(p[2])
                return
            }
            root._iface   = ""
            root._gateway = ""
        }
    }

    // ── DNS, from /etc/resolv.conf ────────────────────────────────────────────
    // The resolver's own view. On a systemd-resolved box this is usually the single
    // stub 127.0.0.53 rather than the real upstreams — which is the truth about what
    // this machine resolves against, so it's shown as-is rather than chased further.
    FileView {
        id: resolvFile
        path: "/etc/resolv.conf"
        preload: true
        printErrors: false
        onLoaded: {
            const out = []
            for (const line of resolvFile.text().split("\n")) {
                const t = line.trim()
                if (t.startsWith("#") || t.startsWith(";")) continue
                const p = t.split(/\s+/)
                if (p.length >= 2 && p[0] === "nameserver") out.push(p[1])
            }
            root._dns = out
        }
    }

    FileView {
        id: macFile
        path: root._iface !== "" ? "/sys/class/net/" + root._iface + "/address" : ""
        preload: true
        printErrors: false
        onLoaded: root._mac = macFile.text().trim()
    }

    FileView {
        id: mtuFile
        path: root._iface !== "" ? "/sys/class/net/" + root._iface + "/mtu" : ""
        preload: true
        printErrors: false
        onLoaded: {
            const v = parseInt(mtuFile.text().trim(), 10)
            root._mtu = isNaN(v) ? 0 : v
        }
    }

    // ── Formatting ────────────────────────────────────────────────────────────
    // Bytes/sec to something readable. Binary units, because that's what the counters
    // are: these are the kernel's byte totals, not a marketing figure.
    function rate(bytesPerSec) {
        const b = bytesPerSec || 0
        if (b < 1024)          return Math.round(b) + " B/s"
        if (b < 1024 * 1024)   return (b / 1024).toFixed(b < 10240 ? 1 : 0) + " KB/s"
        return (b / (1024 * 1024)).toFixed(1) + " MB/s"
    }

    // A total, not a rate — no "/s". Same binary units for the same reason: these are
    // the kernel's byte counters, so KiB/MiB/GiB is what they actually count in, printed
    // with the familiar short suffixes.
    function bytes(n) {
        const b = n || 0
        if (b < 1024)                return Math.round(b) + " B"
        if (b < 1024 * 1024)         return (b / 1024).toFixed(1) + " KB"
        if (b < 1024 * 1024 * 1024)  return (b / (1024 * 1024)).toFixed(1) + " MB"
        return (b / (1024 * 1024 * 1024)).toFixed(2) + " GB"
    }

    // ── rateIn: same number, a unit that holds still ──────────────────────────
    // rate() picks its unit from the value, which is right for a one-off readout and
    // wrong for a live one. Measured on this machine, an IDLE link swings between
    // 316 B/s and 5.4 KB/s inside six seconds — normal background chatter (ARP, mDNS,
    // NTP), but it crosses the 1024 boundary constantly, so rate() flips "B/s"→"KB/s"
    // and back several times a second while the digits churn underneath. The readout
    // ends up illegible precisely when nothing is happening.
    //
    // So the unit is chosen from a REFERENCE value that changes slowly — the chart's
    // peak — and the current value is then printed in that unit whatever it is. The
    // number moves; the unit doesn't. Costs a "0.0 MB/s" at idle after a big transfer,
    // which is honest: the axis it's being read against is in MB/s.
    function _unitOf(bytesPerSec) {
        const b = bytesPerSec || 0
        if (b < 1024)        return 0
        if (b < 1024 * 1024) return 1
        return 2
    }

    function rateIn(bytesPerSec, reference) {
        const v = bytesPerSec || 0
        switch (root._unitOf(reference)) {
            case 0:  return Math.round(v) + " B/s"
            case 1:  return (v / 1024).toFixed(1) + " KB/s"
            default: return (v / (1024 * 1024)).toFixed(1) + " MB/s"
        }
    }

    // dBm to a plain-language band. The thresholds are the usual 802.11 rules of thumb:
    // -67 is the floor for anything real-time, -70 is where throughput starts to fall
    // apart, past -80 it barely associates.
    function quality(dbm) {
        if (dbm >= -50) return "Excellent"
        if (dbm >= -60) return "Very good"
        if (dbm >= -67) return "Good"
        if (dbm >= -75) return "Fair"
        return "Weak"
    }
}
