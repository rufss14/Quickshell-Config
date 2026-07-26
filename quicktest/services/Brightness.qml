pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// ── Brightness ────────────────────────────────────────────────────────────────
// Every display the machine can dim, and the plumbing to dim it.
//
// Two entirely separate backends:
//   ddc — external monitors over I2C (ddcutil). Slow: 100-300ms per call.
//   bcl — internal panels via the kernel backlight (brightnessctl). Near-instant.
//
// This was extracted VERBATIM from BrightnessPanel. It is the most carefully
// reasoned code in the shell and I have deliberately not "improved" it — the
// coalescing queue below is subtle and correct, and the comments explain why.
// The only behavioural change is WHERE it lives:
//
//   Before: the panel owned all of this and ran `Component.onCompleted: startProbe()`.
//           Since panels are now created on open and destroyed on close, that
//           meant a full `ddcutil detect` — which takes on the order of a second
//           and spawns a pipeline of subprocesses — EVERY TIME you opened the
//           panel.
//   Now:    the service outlives the panel, so the probe runs at most ONCE per
//           shell session, on first use. It is still lazy: a user who never opens
//           the brightness panel never pays for ddcutil at all.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // Each entry: { name, label, port, type, bus, brightness, dragging,
    //               controllable, matchMfg, matchModel, matchSerial }
    property alias monitors: monitorModel
    ListModel { id: monitorModel }

    readonly property int  count:   monitorModel.count
    property bool probing: false

    // Laptop panels must never go fully dark — most internal displays are
    // indistinguishable from "off" at 0%, which makes recovery awkward: you can't
    // see the slider to drag it back up. External/DDC monitors keep their full
    // native range; they don't have this problem, and some hardware maps low VCP
    // values to genuinely useful dim levels.
    readonly property int laptopMinBrightness: 5

    function minFor(type)        { return type === "bcl" ? root.laptopMinBrightness : 0 }
    function clampFor(type, val) { return Math.max(root.minFor(type), Math.min(100, Math.round(val))) }

    // Last value actually sent to each backend, by monitor index. Lets _sendSet
    // skip re-sending a value that's already applied (e.g. repeated wheel ticks
    // once you're already pinned at 0 or 100).
    property var _lastApplied: ({})

    // ── Lazy probe ────────────────────────────────────────────────────────────
    // Call this when something first needs the display list. Runs once.
    property bool _probed: false
    function ensureProbed() {
        if (root._probed) return
        root._probed = true
        root.startProbe()
    }

    function startProbe() {
        monitorModel.clear()
        root._lastApplied  = ({})
        root._syncTick     = 0
        ddcSetProc.pendingByIndex = ({})
        ddcSetProc.activeIndex    = -1
        bclSetProc.pendingByIndex = ({})
        bclSetProc.activeIndex    = -1
        root._hyprMonitors     = []
        root._probeDataReady   = false
        hyprMonitorsProc.ready = false
        root.probing = true

        ddcDetect.running = false
        ddcDetect.running = true
        // Runs in PARALLEL with the ddc/backlight chain — see _tryFinishProbe(),
        // which waits for whichever lands last.
        hyprMonitorsProc.running = false
        hyprMonitorsProc.running = true
    }

    // ── Probe: DDC monitors ───────────────────────────────────────────────────
    Process {
        id: ddcDetect
        running: false
        command: ["sh", "-c",
            "ddcutil detect 2>/dev/null | awk '" +
            "function emit(    cmd,val) {" +
            "  if (bus == \"\") return;" +
            "  lbl = (mdl != \"\") ? mdl : mfg;" +
            "  if (lbl == \"\") lbl = \"Display\";" +
            "  cmd = \"ddcutil getvcp 10 --bus \" bus \" 2>/dev/null | grep -oP \\\"current value =\\\\s*\\\\K[0-9]+\\\"\";" +
            "  cmd | getline val; close(cmd);" +
            "  if (val != \"\") print \"OK|\" bus \"|\" lbl \"|\" port \"|\" val \"|\" mfg \"|\" mdl \"|\" ser;" +
            "  else             print \"RO|\" bus \"|\" lbl \"|\" port \"|0|\" mfg \"|\" mdl \"|\" ser;" +
            "}" +
            "/^Display [0-9]/     { emit(); bus=\"\"; mfg=\"\"; mdl=\"\"; port=\"\"; ser=\"\" }" +
            "/I2C bus:/           { match($0, /i2c-([0-9]+)/, a); bus = a[1] }" +
            "/Mfg id:/            { sub(/.*Mfg id:[ \\t]*/,\"\"); split($0,w,/[ \\t]+/); mfg = w[1] }" +
            "/Model:/             { sub(/.*Model:[ \\t]*/,\"\"); sub(/[ \\t]*$/,\"\"); mdl = $0 }" +
            "/Serial number:/     { sub(/.*Serial number:[ \\t]*/,\"\"); sub(/[ \\t]*$/,\"\"); ser = $0 }" +
            "/Display interface:/ { match($0, /(DisplayPort|HDMI|DVI|VGA)/, p); port = p[1] }" +
            "END                  { emit() }'"
        ]
        stdout: StdioCollector { id: ddcOut }

        onExited: function() {
            const lines = ddcOut.text.trim().split("\n")
            for (let i = 0; i < lines.length; i++) {
                const parts = lines[i].split("|")
                if (parts.length !== 8) continue
                if (parts[0] !== "OK" && parts[0] !== "RO") continue

                const ok  = parts[0] === "OK"
                const val = parseInt(parts[4])

                monitorModel.append({
                    name:         "i2c-" + parts[1].trim(),
                    label:        parts[2].trim() || ("Display " + (monitorModel.count + 1)),
                    // Generic interface family from ddcutil (DisplayPort/HDMI/…).
                    // Overwritten with the real connector name if hyprctl matches.
                    port:         parts[3].trim(),
                    type:         "ddc",
                    bus:          parts[1].trim(),
                    brightness:   (ok && !isNaN(val)) ? root.clampFor("ddc", val) : 0,
                    dragging:     false,
                    controllable: ok ? 1 : 0,
                    // EDID fields, kept ONLY for matching against hyprctl. Never shown.
                    matchMfg:     parts[5].trim(),
                    matchModel:   parts[6].trim(),
                    matchSerial:  parts[7].trim()
                })
            }
            bclList.running = true
        }
    }

    // ── Probe: kernel backlight devices ───────────────────────────────────────
    Process {
        id: bclList
        running: false
        command: ["sh", "-c",
            "brightnessctl --list 2>/dev/null | grep -E \"^'\" | while IFS= read -r line; do " +
            "  dev=$(echo \"$line\" | grep -oP \"(?<=')[^']+\"); " +
            "  label=$(echo \"$line\" | grep -oP \"\\([^)]+\\)\" | head -1 | tr -d '()'); " +
            "  val=$(brightnessctl --device \"$dev\" g 2>/dev/null); " +
            "  max=$(brightnessctl --device \"$dev\" m 2>/dev/null); " +
            "  [ -n \"$max\" ] && [ \"$max\" -gt 0 ] && echo \"BCL|$dev|${label:-$dev}|$((val * 100 / max))\"; " +
            "done"
        ]
        stdout: StdioCollector { id: bclOut }

        onExited: function() {
            const lines = bclOut.text.trim().split("\n")
            for (let i = 0; i < lines.length; i++) {
                const parts = lines[i].split("|")
                if (parts.length !== 4 || parts[0] !== "BCL") continue

                const val = parseInt(parts[3])
                monitorModel.append({
                    name:         parts[1].trim(),
                    label:        parts[2].trim() || parts[1].trim(),
                    port:         "Backlight",   // replaced by the eDP-N connector if matched
                    type:         "bcl",
                    bus:          "",
                    brightness:   isNaN(val) ? 50 : root.clampFor("bcl", val),
                    dragging:     false,
                    controllable: 1,
                    matchMfg:     "",
                    matchModel:   "",
                    matchSerial:  ""
                })
            }

            if (monitorModel.count === 0) {
                monitorModel.append({
                    name: "backlight", label: "Display", port: "Backlight",
                    type: "bcl", bus: "", brightness: 50,
                    dragging: false, controllable: 1,
                    matchMfg: "", matchModel: "", matchSerial: ""
                })
                bclFallback.running = true
            } else {
                root._probeDataReady = true
                root._tryFinishProbe()
            }
        }
    }

    Process {
        id: bclFallback
        running: false
        command: ["sh", "-c", "val=$(brightnessctl g); max=$(brightnessctl m); echo $((val * 100 / max))"]
        stdout: StdioCollector { id: bclFallbackOut }

        onExited: function() {
            const v = parseInt(bclFallbackOut.text.trim())
            if (!isNaN(v) && monitorModel.count > 0)
                monitorModel.setProperty(0, "brightness", root.clampFor("bcl", v))
            root._probeDataReady = true
            root._tryFinishProbe()
        }
    }

    // ── Probe: Hyprland connector names ───────────────────────────────────────
    // ddcutil and brightnessctl have no idea which physical connector a panel is
    // plugged into — that only exists in the compositor.
    Process {
        id: hyprMonitorsProc
        running: false
        command: ["hyprctl", "monitors", "-j"]
        property bool ready: false
        stdout: StdioCollector { id: hyprOut }

        onExited: function() {
            root._hyprMonitors = []
            try {
                const parsed = JSON.parse(hyprOut.text)
                if (Array.isArray(parsed)) root._hyprMonitors = parsed
            } catch (e) {
                // Not under Hyprland, hyprctl missing, or bad output. Fall back
                // silently to the generic ddcutil interface labels.
            }
            hyprMonitorsProc.ready = true
            root._tryFinishProbe()
        }
    }

    property var  _hyprMonitors:   []
    property bool _probeDataReady: false

    // Waits for BOTH the display list and the connector query, in whatever order
    // they land, then matches connectors and does the final sort.
    function _tryFinishProbe() {
        if (!root._probeDataReady || !hyprMonitorsProc.ready) return
        root._assignConnectors()
        root.sortMonitors()
        root.probing = false
    }

    // Matches each display to its hyprctl connector ("DP-1", "eDP-1", …) so the UI
    // can name the actual port rather than a generic family.
    //   internal → first free eDP-*
    //   external → EDID serial (exact), then mfg/model substring, then positional
    //              (so a badge still shows rather than falling back to generic)
    function _assignConnectors() {
        function norm(s) { return (s || "").toString().trim().toLowerCase() }

        const hyprList = root._hyprMonitors.slice()
        const used = ({})

        for (let i = 0; i < monitorModel.count; i++) {
            if (monitorModel.get(i).type !== "bcl") continue
            for (let j = 0; j < hyprList.length; j++) {
                const hm = hyprList[j]
                if (used[hm.name]) continue
                if (norm(hm.name).indexOf("edp") === 0) {
                    monitorModel.setProperty(i, "port", hm.name)
                    used[hm.name] = true
                    break
                }
            }
        }

        const remaining = hyprList.filter(hm => !used[hm.name] && norm(hm.name).indexOf("edp") !== 0)

        for (let i = 0; i < monitorModel.count; i++) {
            const m = monitorModel.get(i)
            if (m.type !== "ddc") continue

            let matched = null

            if (m.matchSerial) {
                for (let k = 0; k < remaining.length; k++) {
                    if (norm(remaining[k].serial) === norm(m.matchSerial)) {
                        matched = remaining[k]
                        remaining.splice(k, 1)
                        break
                    }
                }
            }

            if (!matched && (m.matchModel || m.matchMfg)) {
                for (let k = 0; k < remaining.length; k++) {
                    const hay = norm(remaining[k].model) + " " + norm(remaining[k].make)
                              + " " + norm(remaining[k].description)
                    if ((m.matchModel && hay.indexOf(norm(m.matchModel)) !== -1)
                     || (m.matchMfg   && hay.indexOf(norm(m.matchMfg))   !== -1)) {
                        matched = remaining[k]
                        remaining.splice(k, 1)
                        break
                    }
                }
            }

            if (!matched && remaining.length > 0) matched = remaining.shift()

            if (matched) monitorModel.setProperty(i, "port", matched.name)
        }
    }

    // Controllable displays first; read-only ones pinned to the bottom.
    //
    // Reorders IN PLACE with move() rather than clear()+re-append. `get(i)` returns
    // a LIVE view bound to that model index, not a copy — once clear() runs, every
    // previously-fetched object is invalidated and every role reads back undefined.
    // That is what caused an earlier regression (monitors silently vanishing with
    // "name is undefined"). move() never touches role data, so every field survives.
    //
    // Stable partition: scan left to right, sliding each controllable entry down to
    // the next open front slot. Relative order within each group is preserved.
    function sortMonitors() {
        let insertPos = 0
        for (let i = 0; i < monitorModel.count; i++) {
            if (monitorModel.get(i).controllable) {
                if (i !== insertPos) monitorModel.move(i, insertPos, 1)
                insertPos++
            }
        }
    }

    // ══ Backend command queues ════════════════════════════════════════════════
    // ddcutil (I2C, 100-300ms/call) and brightnessctl (near-instant) are separate
    // backends, so each gets its own Process and neither can block or cancel the
    // other. Within a backend, at most ONE command is ever in flight: while it's
    // running, further requests are coalesced into `pendingByIndex` (keyed by
    // monitor, latest value wins) rather than dispatched.
    //
    // This is what makes live dragging safe. Mouse-move events fire far faster than
    // an I2C round-trip, so one command per pixel would flood ddcutil — and the old
    // pattern of restarting a single shared Process would KILL whatever command was
    // already in flight, sometimes for a different monitor entirely. Coalescing
    // means the backend is always racing toward the most recent value as fast as it
    // physically can, with no overlap and no cross-monitor cancellation. On a fast
    // backend this reads as truly live; on slow DDC hardware it degrades to "as
    // fast as the display can keep up", which is the best any UI can do without
    // lying about the hardware's latency.
    Process {
        id: ddcSetProc
        running: false
        property var pendingByIndex: ({})
        property int activeIndex: -1
        onExited: function() {
            ddcSetProc.activeIndex = -1
            root._syncTick++
            root._flushNext(ddcSetProc)
        }
    }

    Process {
        id: bclSetProc
        running: false
        property var pendingByIndex: ({})
        property int activeIndex: -1
        onExited: function() {
            bclSetProc.activeIndex = -1
            root._syncTick++
            root._flushNext(bclSetProc)
        }
    }

    function _procFor(type) { return type === "ddc" ? ddcSetProc : bclSetProc }

    // THE entry point for every UI interaction (press, drag, wheel, release). Safe
    // to call as often as you like: the model updates immediately so the slider
    // stays responsive, while backend dispatch is coalesced internally.
    function requestBrightness(index, val) {
        const m = monitorModel.get(index)
        if (!m || !m.controllable) return
        const clamped = root.clampFor(m.type, val)
        monitorModel.setProperty(index, "brightness", clamped)
        root._sendSet(index, m.type, clamped)
    }

    function _sendSet(index, type, val) {
        if (root._lastApplied[index] === val) return
        const proc = root._procFor(type)
        if (proc.running) {
            proc.pendingByIndex[index] = val
            root._syncTick++          // so isSyncing() bindings see the new queued value
            return
        }
        root._runSet(proc, index, val)
    }

    function _runSet(proc, index, val) {
        const m = monitorModel.get(index)
        if (!m) return

        root._lastApplied[index] = val
        proc.activeIndex = index

        proc.command = (m.type === "ddc")
            // --noverify skips setvcp's default post-write getvcp readback, and
            // --skip-ddc-checks skips the per-call DDC sanity check. Both are
            // documented ddcutil options, and both are safe HERE specifically
            // because the probe already confirmed this bus talks DDC/CI before the
            // monitor was ever added to the model. Together they roughly halve
            // real-world latency (~350ms → ~150-200ms for a typical setvcp).
            //
            // We deliberately do NOT pin --sleep-multiplier: ddcutil's own
            // --enable-dynamic-sleep (on by default) tunes it adaptively per
            // monitor from cached stats, and hardcoding an aggressive value is a
            // documented source of flaky writes on weaker DDC/CI implementations.
            ? ["ddcutil", "--noverify", "--skip-ddc-checks", "setvcp", "10", val.toString(), "--bus", m.bus]
            : ["brightnessctl", "--device", m.name, "set", val.toString() + "%"]

        proc.running = false
        proc.running = true
        root._syncTick++
    }

    function _flushNext(proc) {
        const keys = Object.keys(proc.pendingByIndex)
        if (keys.length === 0) return
        const idx = parseInt(keys[0])
        const val = proc.pendingByIndex[idx]
        delete proc.pendingByIndex[idx]
        root._runSet(proc, idx, val)
    }

    // True while this monitor has a command in flight OR coalesced and waiting —
    // i.e. the hardware hasn't caught up to what the slider is showing. Drives the
    // per-card "syncing" dot, so the UI is honest about backend latency instead of
    // pretending every change lands instantly.
    property int _syncTick: 0    // bumped on every state change, so bindings re-evaluate
    function isSyncing(index) {
        const tick = root._syncTick        // establishes the binding dependency
        const m = monitorModel.get(index)
        if (!m || !m.controllable) return false
        const proc = root._procFor(m.type)
        return proc.activeIndex === index || (index in proc.pendingByIndex)
    }
}
