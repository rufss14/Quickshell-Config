pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import "../config"
import "sysstats.js" as Stats

// ── SysStats ──────────────────────────────────────────────────────────────────
// What the system stats button and its panel (modules/bar/SideStats,
// modules/panels/StatsPanel) need beyond SysInfo's counters: which metrics there
// are, one readout per metric, the disk's fill, the sustained-load alarms, and the
// system monitor a middle-click opens. They show these and call functions;
// everything that runs a process or keeps time is here. Parsing and the alarm's
// rules are sysstats.js (bun scripts/test-sysstats.js). Nothing is sampled for
// them unless something holds a StatsSampler.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ══ Which metrics ═════════════════════════════════════════════════════════
    // Config.sidebarStatsMetrics, in its order, less any this machine has nothing
    // to read for (sysstats.js statsMetrics: GPU on NVIDIA, no swap, no battery, no
    // peripherals found).
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: root.battery?.isLaptopBattery ?? false
    readonly property var unavailable: ({
        gpu:     !SysInfo.hasGpu,
        swap:    !(SysInfo.swapTotal > 0),
        battery: !root.hasBattery,
        devices: DeviceBatteries.devices.length === 0
    })
    readonly property var metrics: Stats.statsMetrics(Config.sidebarStatsMetrics, root.unavailable)

    // ══ One readout per metric ════════════════════════════════════════════════
    // One place turns a metric name into everything the button and the panel show
    // (it was the stats pill's, and its rings and hover card read it the same way):
    //   ratio    0..1 for the ring / the button's bar
    //   inner    0..1 for a second, inner arc (the part's temperature, or the
    //            network's upload when split), or undefined for none
    //   short    the value in two or three characters      glyph, label   its icon, part
    //   name     the actual hardware ("AMD Radeon RX 6700 XT"), "" if unknown
    //   value    the headline
    //   rows     the facts, each an icon and its text: [{ glyph, text, warn? }]
    //   history  0..1 samples for a trace ([] = none), capacity, cadence
    //   page     the settings page that shows it in depth
    //   meters   charge bars: [{ glyph, text, level, limit, warn }] (optional)
    //   glyphScale  the icon's size against the others' (optional, 1): a glyph that
    //            fills its whole box (the mouse) reads bigger than the rest
    //   logo     a brand mark's file drawn in the glyph's place (optional, "")
    function pct(v) { return Math.round(v * 100) + "%" }
    function gb(v) { return v.toFixed(1) }
    function row(glyph, text) { return { glyph: glyph, text: text } }
    // A temperature's inner arc: 0..100°C, the desktop widget's scale — room for
    // the arc to travel, the number beside it is the truth.
    function tempArc(has, c) {
        return has && Config.sidebarStatsTempArcs ? Math.max(0, Math.min(1, c / 100)) : undefined
    }
    function duration(secs) {
        const h = Math.floor(secs / 3600), m = Math.round((secs % 3600) / 60)
        return h > 0 ? h + "h " + m + "m" : m + "m"
    }
    function readout(key) {
        const thermo = "\u{F050F}", chip = "\u{F061A}", mem = "\u{F035B}"   // thermometer, chip, memory
        switch (key) {
        case "cpu": return {
            glyph: "\u{F0EE0}", label: "CPU", ratio: SysInfo.cpu,          // 󰻠 cpu-64-bit
            name: root.cpuName,
            inner: root.tempArc(SysInfo.hasCpuTemp, SysInfo.cpuTemp),
            short: String(Math.round(SysInfo.cpu * 100)),
            value: root.pct(SysInfo.cpu) + " load",
            rows: [SysInfo.hasCpuTemp ? root.row(thermo, SysInfo.cpuTemp + "°C") : null,
                   SysInfo.cores.length > 0 ? root.row(chip, SysInfo.cores.length + " threads") : null]
                  .filter(r => r !== null),
            history: SysInfo.history, capacity: SysInfo.historyLength, cadence: SysInfo.interval,
            page: "AboutPage.qml" }
        case "gpu": return {
            glyph: "\u{F08AE}", label: "GPU", ratio: SysInfo.gpu,          // 󰢮 expansion-card
            name: root.gpuName,
            inner: root.tempArc(SysInfo.hasGpuTemp, SysInfo.gpuTemp),
            short: String(Math.round(SysInfo.gpu * 100)),
            value: root.pct(SysInfo.gpu) + " busy",
            rows: [SysInfo.hasGpuTemp ? root.row(thermo, SysInfo.gpuTemp + "°C") : null,
                   SysInfo.vramTotal > 0
                   ? root.row(mem, "VRAM " + root.gb(SysInfo.vramUsed) + " / " + root.gb(SysInfo.vramTotal) + " GB")
                   : null].filter(r => r !== null),
            history: SysInfo.gpuHistory, capacity: SysInfo.historyLength, cadence: SysInfo.interval,
            page: "AboutPage.qml" }
        case "ram": return {
            glyph: mem, label: "Memory", ratio: SysInfo.memFraction,       // 󰍛 memory
            name: SysInfo.memTotal > 0 ? root.gb(SysInfo.memTotal) + " GB" : "",
            short: String(Math.round(SysInfo.memFraction * 100)),
            value: root.gb(SysInfo.memUsed) + " / " + root.gb(SysInfo.memTotal) + " GB",
            rows: [root.row("\u{F03F0}", root.pct(SysInfo.memFraction) + " in use"),   // 󰏰 percent
                   SysInfo.swapTotal > 0
                   ? root.row("\u{F0FB4}", "Swap " + root.gb(SysInfo.swapUsed) + " / " + root.gb(SysInfo.swapTotal) + " GB")
                   : null].filter(r => r !== null),
            history: SysInfo.memHistory, capacity: SysInfo.historyLength, cadence: SysInfo.interval,
            page: "AboutPage.qml" }
        case "swap": return {
            glyph: "\u{F0FB4}", label: "Swap", ratio: SysInfo.swapFraction, // 󰾴 file-swap
            name: "",
            short: String(Math.round(SysInfo.swapFraction * 100)),
            value: root.gb(SysInfo.swapUsed) + " / " + root.gb(SysInfo.swapTotal) + " GB",
            rows: [root.row("\u{F03F0}", root.pct(SysInfo.swapFraction) + " in use"),
                   root.row(mem, "Pages moved out of RAM")],
            history: [], page: "AboutPage.qml" }
        case "disk": return {
            glyph: "\u{F02CA}", label: "Disk", ratio: root.diskFraction,   // 󰋊 harddisk
            name: root.diskModel(root.homeDisk),
            short: String(Math.round(root.diskFraction * 100)),
            value: root.diskTotal > 0
                   ? NetStats.bytes(root.diskUsed) + " / " + NetStats.bytes(root.diskTotal) : "…",
            rows: [root.row("\u{F03F0}", root.pct(root.diskFraction) + " full"),
                   root.row("\u{F10B5}", root.diskPath)],                   // 󱂵 folder-home
            history: [], page: "StoragePage.qml" }
        case "diskio": return {
            glyph: "\u{F0CFF}", label: "Disk activity", ratio: SysInfo.diskUtil, // 󰳿 database-sync
            name: root.diskModel(SysInfo.diskBusiest),
            short: String(Math.round(SysInfo.diskUtil * 100)),
            value: root.pct(SysInfo.diskUtil) + " busy",
            rows: [root.row("\u{F01DA}", "Read "  + NetStats.rate(SysInfo.diskRead)),   // 󰇚 download
                   root.row("\u{F0552}", "Write " + NetStats.rate(SysInfo.diskWrite))], // 󰕒 upload
            history: SysInfo.diskHistory, capacity: SysInfo.historyLength, cadence: SysInfo.interval,
            page: "StoragePage.qml" }
        case "battery": {
            const b = root.battery
            const p = b ? b.percentage : 0
            const charging = b && (b.state === UPowerDeviceState.Charging
                                   || b.state === UPowerDeviceState.PendingCharge)
            const secs = !b ? 0 : charging ? b.timeToFull : b.timeToEmpty
            return {
                glyph: charging ? "\u{F0084}" : "\u{F0079}",              // 󰂄 / 󰁹 battery
                label: "Battery", ratio: p, short: String(Math.round(p * 100)),
                name: b ? (b.model || "") : "",
                value: root.pct(p),
                rows: [charging ? root.row("\u{F140B}", "Charging") : null,      // 󱐋 lightning-bolt
                       secs > 0 ? root.row("\u{F0150}", root.duration(secs) + (charging ? " to full" : " left")) : null]
                      .filter(r => r !== null),
                history: [], page: "BatteryPage.qml" }
        }
        case "devices": {
            // The headline is the LOWEST charge — the one that'll die first; there's
            // a bar for every device. One device: the header names it ("Mouse —
            // Razer Viper Ultimate"), the bar stands alone and its details follow.
            // Several: a named bar each, details left out for room.
            const list = DeviceBatteries.devices
            const d = DeviceBatteries.lowest
            const p = d ? d.level : 0
            const one = list.length === 1
            return {
                glyph: Stats.kindGlyph(d ? d.kind : ""), glyphScale: 0.7,
                logo: DeviceBatteries.logoFor(d),
                label: one ? Stats.kindLabel(d.kind) : "Devices",
                ratio: p, short: String(Math.round(p * 100)),
                name: one ? d.name : "",
                value: !d ? "…"
                     : (one ? "" : d.name + " ") + root.pct(p) + (d.charging ? ", charging" : ""),
                meters: list.map(x => ({
                    glyph: Stats.kindGlyph(x.kind),
                    text: one ? "" : x.name + "  " + root.pct(x.level) + (x.charging ? " · charging" : ""),
                    level: x.level,
                    limit: x.lowAt ?? DeviceBatteries.lowThreshold,
                    warn: Stats.deviceLow(x, x.lowAt ?? DeviceBatteries.lowThreshold)
                })),
                rows: one ? Stats.deviceRows(d) : [],
                history: [], page: "BluetoothPage.qml" }
        }
        default: {
            const mbps = Config.sidebarStatsNetCeiling
            const split = Config.sidebarStatsNetSplit
            return {
                glyph: "\u{F04E2}", label: "Network",                      // 󰓢 swap-vertical
                name: NetStats.iface,
                ratio:  split ? Stats.netRatio(NetStats.rxRate, 0, mbps)
                              : Stats.netRatio(NetStats.rxRate, NetStats.txRate, mbps),
                inner:  split ? Stats.netRatio(0, NetStats.txRate, mbps) : undefined,
                short:  Stats.compactRate(Math.max(NetStats.rxRate, NetStats.txRate)),
                value:  NetStats.rate(Math.max(NetStats.rxRate, NetStats.txRate)),
                rows: [root.row("\u{F01DA}", "Down " + NetStats.rate(NetStats.rxRate)
                                              + (split ? " · outer arc" : "")),
                       root.row("\u{F0552}", "Up " + NetStats.rate(NetStats.txRate)
                                              + (split ? " · inner arc" : "")),
                       root.row("\u{F04C5}", "Scale " + mbps + " Mbit/s")],        // 󰓅 speedometer
                history: NetStats.rxHistory.map((v, i) =>
                             Stats.netRatio(v, NetStats.txHistory[i] ?? 0, mbps)),
                capacity: NetStats.rateHistoryLength, cadence: NetStats.rateInterval,
                page: "NetworkPage.qml" }
        }
        }
    }
    // Over its threshold, for its ring or its temperature (see Alerts).
    function isAlerting(key) {
        return root.alerting[key] === true || root.alerting[key + "temp"] === true
    }

    // ══ Hardware names ══════════════════════════════════════════════════════
    // What the panel calls each part ("GPU — AMD Radeon RX 6700 XT"). One run of
    // scripts/hw-names.sh the first time the service exists; names don't change
    // while the machine is up. "" where a name couldn't be found — the panel then
    // shows the part alone.
    readonly property string cpuName: root._cpuName
    readonly property string gpuName: root._gpuName
    readonly property string homeDisk: root._homeDisk
    function diskModel(disk) { return root._diskModels[disk] ?? "" }
    property string _cpuName: ""
    property string _gpuName: ""
    property string _homeDisk: ""
    property var _diskModels: ({})

    Process {
        id: hwProc
        running: true
        // Through bash, so a missing executable bit (a copy, a fresh clone) can't
        // turn every name blank — the Storage/AboutPage rule.
        command: ["bash", Quickshell.shellPath("scripts/hw-names.sh")]
        stdout: StdioCollector {
            onStreamFinished: {
                const vk = [], models = {}
                let cpu = "", pci = "", home = ""
                for (const line of text.split("\n")) {
                    const eq = line.indexOf("=")
                    if (eq < 0) continue
                    const k = line.slice(0, eq), v = line.slice(eq + 1)
                    if (k === "CPU") cpu = v
                    else if (k === "VK") vk.push(v)
                    else if (k === "PCI") pci = v
                    else if (k === "HOMEDISK") home = v
                    else if (k.startsWith("MODEL_")) models[k.slice(6)] = v.trim()
                }
                root._cpuName = Stats.cleanCpuName(cpu)
                root._gpuName = Stats.gpuName(vk, pci)
                root._homeDisk = home
                root._diskModels = models
            }
        }
    }

    // ══ Disk usage ════════════════════════════════════════════════════════════
    // The filesystem your home is on — where your files fill a disk. df once a
    // minute while something holds it (StatsSampler); disks don't fill faster.
    readonly property real diskTotal: root._diskTotal     // bytes
    readonly property real diskUsed:  root._diskUsed
    readonly property real diskFraction: root._diskTotal > 0 ? root._diskUsed / root._diskTotal : 0
    readonly property string diskPath: Quickshell.env("HOME") || "/"
    property real _diskTotal: 0
    property real _diskUsed: 0
    property int _diskRefs: 0
    function acquireDisk() { root._diskRefs++ }
    function releaseDisk() { root._diskRefs = Math.max(0, root._diskRefs - 1) }

    Timer {
        running: root._diskRefs > 0
        interval: 60000
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!dfProc.running) dfProc.running = true
    }

    Process {
        id: dfProc
        command: ["df", "-B1", "--output=size,used", root.diskPath]
        stdout: StdioCollector {
            onStreamFinished: {
                const d = Stats.parseDf(text)
                if (!d) return
                root._diskTotal = d.total
                root._diskUsed  = d.used
            }
        }
    }

    // ══ Busiest processes ═════════════════════════════════════════════════════
    // What is using the machine, grouped by name (scripts/top-procs.py: two /proc reads half a second
    // apart; `python3 scripts/test-top-procs.py`). Sampled every few seconds only while something holds
    // it: the stats panel, while it is open.
    readonly property var topCpu: root._top.cpu ?? []     // [{ name, cpu (% of one core), mb, procs }]
    readonly property var topMem: root._top.mem ?? []
    property var _top: ({})
    property int _topRefs: 0
    function acquireTop() { root._topRefs++ }
    function releaseTop() { root._topRefs = Math.max(0, root._topRefs - 1) }

    Timer {
        running: root._topRefs > 0
        interval: 3000
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!topProc.running) topProc.running = true
    }

    Process {
        id: topProc
        command: ["python3", Quickshell.shellPath("scripts/top-procs.py"), "5"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const o = JSON.parse(text)
                    if (o && o.ok) root._top = o
                } catch (e) {
                    // A cut-off line (the shell reloading mid-run): keep the last reading.
                }
            }
        }
    }

    // ══ Alerts ════════════════════════════════════════════════════════════════
    // A metric that has sat over its threshold for `alertSustain` is flagged in the
    // panel, and (if asked) says so once, as a notification. Watched for as long as
    // alerts are on with the stats on the sidebar, even while it's sunk into the
    // frame — which is exactly when you'd want telling.
    readonly property int alertSustain: 10000
    readonly property bool watching: Config.sidebarStats && Config.sidebarStatsAlerts
    readonly property var alerting: root._alerting
    property var _alerting: ({})
    property var _alertState: ({})
    property bool _sysHeld: false

    onWatchingChanged: root._syncWatch()
    Component.onCompleted: root._syncWatch()
    Component.onDestruction: if (root._sysHeld) SysInfo.release()
    function _syncWatch() {
        if (root.watching === root._sysHeld) return
        if (root.watching) SysInfo.acquire()
        else {
            SysInfo.release()
            root._alertState = ({})
            root._alerting = ({})
        }
        root._sysHeld = root.watching
    }

    // One step per CPU sample (SysInfo replaces `history` once a second).
    Connections {
        target: SysInfo
        enabled: root.watching
        function onHistoryChanged() { root._evaluate() }
    }

    function _evaluate() {
        const now  = Date.now()
        const load = Config.sidebarStatsAlertLoad / 100
        const temp = Config.sidebarStatsAlertTemp
        const checks = [
            { key: "cpu",  value: SysInfo.cpu,         on: load, off: load - 0.05, what: "CPU load" },
            { key: "ram",  value: SysInfo.memFraction, on: load, off: load - 0.05, what: "Memory use" }
        ]
        if (SysInfo.hasCpuTemp)
            checks.push({ key: "cputemp", value: SysInfo.cpuTemp, on: temp, off: temp - 5, what: "CPU temperature" })
        if (SysInfo.hasGpuTemp)
            checks.push({ key: "gputemp", value: SysInfo.gpuTemp, on: temp, off: temp - 5, what: "GPU temperature" })

        const state = Object.assign({}, root._alertState)
        const lit = {}
        for (const c of checks) {
            const s = Stats.alertStep(state[c.key], c.value, c.on, c.off, now, root.alertSustain)
            state[c.key] = s
            lit[c.key] = s.on
            if (s.fired && Config.sidebarStatsAlertNotify)
                root._notify(c.what + " is high",
                             c.what + " has stayed above "
                             + (c.key.endsWith("temp") ? temp + "°C" : Config.sidebarStatsAlertLoad + "%")
                             + " for " + Math.round(root.alertSustain / 1000) + " seconds.")
        }
        root._alertState = state
        // Replaced only when something changed, so the rings aren't re-evaluated
        // every second for nothing.
        if (JSON.stringify(lit) !== JSON.stringify(root._alerting)) root._alerting = lit
    }

    function _notify(title, body) {
        notifyProc.command = ["notify-send", "--app-name=Quickshell", "--urgency=normal",
                              "--icon=utilities-system-monitor", title, body]
        notifyProc.running = false
        notifyProc.running = true
    }
    Process { id: notifyProc }

    // ══ The system monitor ════════════════════════════════════════════════════
    // What a middle-click on the button opens in the terminal. "" = the first of btop,
    // htop and top that's installed (top ships with procps, so there is always one).
    readonly property string monitorCommand:
        Config.sidebarStatsMonitor !== "" ? Config.sidebarStatsMonitor : root._foundMonitor
    property string _foundMonitor: "top"

    Process {
        id: monitorProbe
        running: true
        command: ["sh", "-c", "for t in btop htop top; do command -v \"$t\" >/dev/null && { echo \"$t\"; exit 0; }; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                if (t !== "") root._foundMonitor = t
            }
        }
    }

    function openMonitor() {
        if (root.monitorCommand !== "") Terminal.run(root.monitorCommand)
    }
}
