pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// ── SysInfo ───────────────────────────────────────────────────────────────────
// Live CPU and memory load, sampled from /proc.
//
// ── Refcounted, and that is the whole design ──────────────────────────────────
// This exists for one page in the settings card. A Timer left running would sample
// /proc once a second forever, for a readout nobody is looking at — exactly what the
// brief means by "anything doing work on every frame that doesn't need to". So the
// timer runs only while someone holds a reference, the same pattern Hypr and Cava use.
// AboutPage acquires on construction and releases on destruction; the card's Loader
// tears the page down when you flip to Bar, so the sampling stops there too.
//
// ── FileView, not `cat` ───────────────────────────────────────────────────────
// Two file reads a second, in-process. The obvious build shells out to `cat /proc/stat`
// or a bash one-liner, which is two process spawns a second for eight numbers. FileView
// reads them directly.
//
// `watchChanges` is deliberately OFF here, unlike everywhere else this shell uses
// FileView. /proc/stat changes continuously — an inotify watch on it would fire far
// faster than anything could usefully render, and the point is to sample on OUR clock,
// not on the kernel's.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property int _refs: 0
    function acquire() { root._refs++ }
    function release() { root._refs = Math.max(0, root._refs - 1) }

    readonly property bool active: root._refs > 0

    // ── CPU ───────────────────────────────────────────────────────────────────
    readonly property real cpu: root._cpu          // 0..1, aggregate
    readonly property var  cores: root._cores      // [0..1], one per core

    // ── Temperatures ──────────────────────────────────────────────────────────
    // °C, or -1 for "this machine doesn't report it".
    //
    // ── Found by NAME, never by index ─────────────────────────────────────────
    // /sys/class/hwmon/hwmonN is enumerated in driver-probe order, which is a race:
    // hwmon1 is k10temp on this boot and could be the Wi-Fi card on the next. Anything
    // that hardcodes an index reads a plausible number off the wrong chip and never
    // errors. So the probe reads each `name` file and matches on that.
    //
    // temp1_input is the headline sensor on both drivers here (k10temp → Tctl,
    // amdgpu → edge). The GPU also exposes junction and mem; edge is the one that
    // corresponds to what every other tool calls "GPU temp".
    readonly property int cpuTemp: root._cpuTemp
    readonly property int gpuTemp: root._gpuTemp
    readonly property bool hasCpuTemp: root._cpuTemp > 0
    readonly property bool hasGpuTemp: root._gpuTemp > 0

    property int _cpuTemp: -1
    property int _gpuTemp: -1
    property string _cpuTempPath: ""
    property string _gpuTempPath: ""

    Process {
        id: tempProbe
        running: true
        // One shell, both sensors. The name list is the usual suspects: k10temp is AMD
        // Zen, coretemp is Intel, zenpower is the out-of-tree AMD driver some people run.
        command: ["bash", "-c",
                  "for d in /sys/class/hwmon/hwmon*; do "
                + "  n=$(cat \"$d/name\" 2>/dev/null); "
                + "  case \"$n\" in "
                + "    k10temp|coretemp|zenpower) [ -r \"$d/temp1_input\" ] && printf 'CPU=%s\\n' \"$d/temp1_input\";; "
                + "    amdgpu|nvidia|i915|xe)     [ -r \"$d/temp1_input\" ] && printf 'GPU=%s\\n' \"$d/temp1_input\";; "
                + "  esac; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of text.split("\n")) {
                    const eq = line.indexOf("=")
                    if (eq < 0) continue
                    const key = line.substring(0, eq)
                    const val = line.substring(eq + 1).trim()
                    if (key === "CPU" && root._cpuTempPath === "") root._cpuTempPath = val
                    if (key === "GPU" && root._gpuTempPath === "") root._gpuTempPath = val
                }
            }
        }
    }

    FileView {
        id: cpuTempFile
        path: root._cpuTempPath
        preload: true
        printErrors: false
        onLoaded: {
            // millidegrees
            const v = parseInt(cpuTempFile.text().trim(), 10)
            root._cpuTemp = isNaN(v) ? -1 : Math.round(v / 1000)
        }
    }

    FileView {
        id: gpuTempFile
        path: root._gpuTempPath
        preload: true
        printErrors: false
        onLoaded: {
            const v = parseInt(gpuTempFile.text().trim(), 10)
            root._gpuTemp = isNaN(v) ? -1 : Math.round(v / 1000)
        }
    }

    // Recent aggregate load, oldest first — the sparkline's data. Fixed length, so the
    // chart's x-axis is "the last `historyLength` samples" and never rescales.
    readonly property var history: root._history
    readonly property int historyLength: 60

    // How often the sample above is taken. Public because the charts need it: a gliding
    // Sparkline slides by exactly one slot per interval, so it has to know the cadence
    // it's drawing. It was a bare literal on the Timer, which meant the chart couldn't
    // ask.
    readonly property int interval: 1000

    // ── Appending a sample ────────────────────────────────────────────────────
    // Was written out twice, once for CPU and once for GPU, with the same trim and the
    // same "replaced, not pushed" comment on each. One copy.
    //
    // Keeps historyLength+1: the surplus oldest sample sits off the left edge of a
    // gliding chart and covers the gap that opens as the trace slides. `historyLength`
    // stays the number of samples you can SEE — the charts pass it as their capacity.
    // Same rule as NetStats._append.
    function _append(arr, v) {
        const cap  = root.historyLength + 1
        const next = arr.concat([v])
        return next.length > cap ? next.slice(next.length - cap) : next
    }

    property real _cpu: 0
    property var  _cores: []
    property var  _history: []

    // Previous jiffy counters. CPU load is a DELTA — /proc/stat reports cumulative time
    // since boot, so a single read tells you the average since power-on (a number that
    // barely moves and looks broken). Two reads and a subtraction give load *now*.
    property var _prevTotal: []
    property var _prevBusy:  []

    // ── Memory ────────────────────────────────────────────────────────────────
    readonly property real memUsed:  root._memUsed      // GB
    readonly property real memTotal: root._memTotal     // GB
    readonly property real memFraction: root._memTotal > 0 ? root._memUsed / root._memTotal : 0

    property real _memUsed:  0
    property real _memTotal: 0

    // ── GPU ───────────────────────────────────────────────────────────────────
    // amdgpu (and i915) publish live utilisation in sysfs. `hasGpu` is false when
    // nothing does — NVIDIA's proprietary stack has no sysfs equivalent and needs
    // nvidia-smi, which is a subprocess per sample and not worth it here. The About
    // page hides the whole tile rather than showing a gauge pinned at zero.
    readonly property bool hasGpu: root._gpuPath !== ""
    readonly property real gpu: root._gpu             // 0..1
    readonly property var  gpuHistory: root._gpuHistory

    readonly property real vramUsed:  root._vramUsed   // GB
    readonly property real vramTotal: root._vramTotal  // GB
    readonly property real vramFraction: root._vramTotal > 0 ? root._vramUsed / root._vramTotal : 0

    property string _gpuPath: ""
    property real _gpu: 0
    property var  _gpuHistory: []
    property real _vramUsed:  0
    property real _vramTotal: 0

    // ── Finding the card ──────────────────────────────────────────────────────
    // The card NUMBER is machine-specific: this box's real GPU is card1, because card0
    // is a display-only node. Hardcoding a path would work here and silently show
    // nothing on any other machine — so it's discovered once, at first use, with one
    // process. Not per sample: everything after this is FileView.
    Process {
        id: gpuProbe
        // First card exposing gpu_busy_percent wins. A node without it isn't a GPU we
        // can measure, whatever else it claims to be.
        command: ["bash", "-c",
                  "for d in /sys/class/drm/card*/device; do "
                + "[ -r \"$d/gpu_busy_percent\" ] && { printf '%s' \"$d\"; exit 0; }; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                root._gpuPath = text.trim()
                if (root._gpuPath !== "") {
                    // Total VRAM is constant — read once, not every tick.
                    vramTotalFile.reload()
                }
            }
        }
    }

    // Probed on first acquire rather than at startup: this shell launches on login and
    // most sessions never open the About page, so the probe shouldn't run then.
    property bool _probed: false
    function _probe() {
        if (root._probed) return
        root._probed = true
        gpuProbe.running = true
    }

    Timer {
        running: root.active
        interval: root.interval
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            root._probe()
            statFile.reload()
            memFile.reload()
            if (root._cpuTempPath !== "") cpuTempFile.reload()
            if (root._gpuTempPath !== "") gpuTempFile.reload()
            if (root._gpuPath !== "") {
                gpuBusyFile.reload()
                vramUsedFile.reload()
            }
        }
    }

    // Reset on release so the next open starts clean rather than splicing a fresh
    // sample onto a delta from minutes ago — which would render as one giant spike.
    onActiveChanged: {
        if (root.active) return
        root._prevTotal  = []
        root._prevBusy   = []
        root._history    = []
        root._gpuHistory = []
    }

    FileView {
        id: statFile
        path: "/proc/stat"
        // preload is REQUIRED — FileView is lazy, and without it onLoaded never fires
        // and every readout sits at zero. Both other FileViews in this shell carry the
        // same note for the same reason.
        preload: true

        onLoaded: {
            const lines = statFile.text().split("\n")
            const totals = []
            const busies = []

            for (const line of lines) {
                if (!line.startsWith("cpu")) break     // the cpu* lines lead the file
                const parts = line.trim().split(/\s+/)
                // parts[0] is "cpu" (aggregate) or "cpuN". Fields are jiffies:
                // user nice system idle iowait irq softirq steal guest guest_nice
                const n = parts.slice(1).map(Number)
                if (n.length < 5) continue

                const total = n.reduce((a, b) => a + b, 0)
                // idle + iowait is time the CPU did nothing. Everything else is work.
                // iowait belongs in idle: the core is stalled on disk, not computing —
                // counting it as busy is how a machine reads 100% while doing nothing.
                const busy = total - (n[3] + n[4])
                totals.push(total)
                busies.push(busy)
            }

            if (root._prevTotal.length === totals.length && totals.length > 0) {
                const next = []
                for (let i = 0; i < totals.length; i++) {
                    const dt = totals[i] - root._prevTotal[i]
                    const db = busies[i]  - root._prevBusy[i]
                    // dt can be 0 if the clock hasn't ticked between reads. Dividing
                    // would give NaN and paint the whole chart blank.
                    next.push(dt > 0 ? Math.max(0, Math.min(1, db / dt)) : 0)
                }
                root._cpu   = next[0]
                root._cores = next.slice(1)

                // Replaced, not pushed: a mutation wouldn't fire the change signal and
                // the sparkline would never repaint. Same rule as Config.layout.
                root._history = root._append(root._history, next[0])
            }

            root._prevTotal = totals
            root._prevBusy  = busies
        }
    }

    FileView {
        id: memFile
        path: "/proc/meminfo"
        preload: true

        onLoaded: {
            const text = memFile.text()
            const total = root._field(text, "MemTotal")
            const avail = root._field(text, "MemAvailable")
            if (total <= 0) return

            // MemAvailable, not MemFree. MemFree excludes the page cache, so it reports
            // a healthy Linux box as ~95% full — the cache is reclaimable and is not
            // "used" in any sense a person means. This is the number `free -h` calls
            // "available".
            root._memTotal = total / 1048576          // kB → GB
            root._memUsed  = (total - avail) / 1048576
        }
    }

    // ── GPU sysfs reads ───────────────────────────────────────────────────────
    // Three one-line files. `path` is bound to the discovered directory, so these stay
    // inert (empty path ⇒ nothing to load) until the probe finds a card.
    FileView {
        id: gpuBusyFile
        path: root._gpuPath === "" ? "" : root._gpuPath + "/gpu_busy_percent"
        preload: true
        // A card can vanish (eGPU unplugged, driver reload). That's not worth a console
        // warning once a second.
        printErrors: false

        onLoaded: {
            const v = Number(gpuBusyFile.text().trim())
            if (isNaN(v)) return
            root._gpu = Math.max(0, Math.min(1, v / 100))

            // Replaced, not pushed — a mutation wouldn't fire the change signal and the
            // sparkline would never repaint.
            root._gpuHistory = root._append(root._gpuHistory, root._gpu)
        }
    }

    FileView {
        id: vramUsedFile
        path: root._gpuPath === "" ? "" : root._gpuPath + "/mem_info_vram_used"
        preload: true
        printErrors: false
        onLoaded: {
            const v = Number(vramUsedFile.text().trim())
            // Bytes here, unlike /proc/meminfo's kB. Getting this wrong is a factor of
            // 1024 and renders as a plausible-looking wrong number.
            if (!isNaN(v)) root._vramUsed = v / 1073741824
        }
    }

    FileView {
        id: vramTotalFile
        path: root._gpuPath === "" ? "" : root._gpuPath + "/mem_info_vram_total"
        preload: true
        printErrors: false
        onLoaded: {
            const v = Number(vramTotalFile.text().trim())
            if (!isNaN(v)) root._vramTotal = v / 1073741824
        }
    }

    function _field(text, key) {
        const m = text.match(new RegExp("^" + key + ":\\s+(\\d+)", "m"))
        return m ? Number(m[1]) : 0
    }
}
