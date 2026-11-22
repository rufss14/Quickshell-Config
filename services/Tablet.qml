pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "../config"
import "tablet.js" as T
import "inactivity.js" as Ia

// ── Tablet ────────────────────────────────────────────────────────────────────
// A drawing tablet (a Wacom, a Huion…) on the shell: where its pen lands on the screen, how hard it has to
// press, what its express keys do, and a live view of the pen. The Tablet page on the bottom-left island
// and Settings › Tablet show and set; the rules are services/tablet.js (pure, `bun scripts/test-tablet.js`).
//
// ── Two halves, and why ───────────────────────────────────────────────────────
// The compositor already knows how to be a tablet driver: Hyprland maps the pen onto an output, takes a
// part of the tablet, turns it, and limits the pressure range. So the SETTINGS go in through
// `hyprctl eval` (an `hl.config` call, the one kind of runtime eval this shell has run safely: CursorEffects,
// HyprLayout) and no daemon or virtual device sits between the pen and the compositor. What Hyprland does
// not do is TELL anyone what the pen is doing, so the LIVE half (the pen's position and pressure, the
// express keys) is scripts/tablet-helper.py, which reads the evdev nodes read-only and never grabs them.
//
// ── Access ────────────────────────────────────────────────────────────────────
// The nodes are root:input. `scripts/tablet-access.sh --install` writes one udev rule (the `uaccess` tag on
// tablets only), once, as root. Until then the settings half works in full, and the live half says why it
// is off (`liveBlocker()`), in the shape of NightLight.blocker(): the control is disabled with a reason.
//
// ── Global, not per device ────────────────────────────────────────────────────
// `input.tablet.*` is one set of values for every tablet. Profiles are kept per tablet (by its Hyprland name)
// and the first tablet found is the one this follows; a second tablet gets the same values. A per-device
// `hl.device` is not used: nothing here has run it through eval, and a runtime `hl.bind` is known to crash
// Hyprland.
//
// ── Inert ─────────────────────────────────────────────────────────────────────
// Off (the default) runs nothing. On, a profile that is still the stock one is not sent until the user
// changes something, so turning the switch on alone does not touch the compositor.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property bool enabled: Config.tabletOn
    readonly property string scriptPath: Quickshell.shellPath("scripts/tablet-helper.py")
    readonly property string accessPath: Quickshell.shellPath("scripts/tablet-access.sh")

    // ══ Which tablet ═════════════════════════════════════════════════════════
    property var tablets: []
    property bool probed: false
    property bool udevMissing: false
    // "installed" | "absent" | "" (not asked yet): is the udev rule in place.
    property string rule: ""
    readonly property var device: root.tablets.length > 0 ? root.tablets[0] : null
    readonly property bool present: root.device !== null
    readonly property string key: root.present ? root.device.hypr : ""

    function reprobe() { if (root.enabled && !probeProc.running) probeProc.running = true }

    Process {
        id: probeProc
        command: ["python3", root.scriptPath, "--probe"]
        stdout: StdioCollector {
            onStreamFinished: {
                const r = T.parseProbe(text)
                root.tablets = r.tablets
                root.udevMissing = r.reason === "udevadm"
                root.probed = true
                // Access granted since the helper was refused: it may try again.
                if (root.helperFatal === "access" && root.present && root.device.access) root.helperFatal = ""
                if (!ruleProc.running) ruleProc.running = true
            }
        }
    }

    Process {
        id: ruleProc
        command: ["bash", root.accessPath, "--status"]
        stdout: StdioCollector { onStreamFinished: root.rule = text.trim() }
    }

    Process {
        id: wtypeProc
        command: ["bash", "-c", "command -v wtype >/dev/null 2>&1 && echo yes || echo no"]
        stdout: StdioCollector { onStreamFinished: root.hasWtype = text.trim() === "yes" }
    }
    property bool hasWtype: false

    // "" when the live pen can work, otherwise the reason. Plain properties only.
    function liveBlocker() {
        if (root.udevMissing) return "Needs udevadm, which comes with systemd"
        if (!root.present) return "No tablet found"
        if (!root.device.access) return "Needs permission to read the tablet"
        if (root.helperFatal === "missing") return "The tablet's input node is gone"
        if (root.helperError !== "") return root.helperError
        return ""
    }

    // "" or why an express key cannot send a chord.
    function chordBlocker() { return root.hasWtype ? "" : "Needs wtype" }

    // ══ The saved profiles ═══════════════════════════════════════════════════
    property var _doc: T.emptyState()
    readonly property bool ready: store.ready

    readonly property var profiles: root.present ? T.deviceState(root._doc, root.key, root.device).profiles : []
    readonly property var profile: root.present ? T.activeProfile(root._doc, root.key, root.device) : null
    readonly property var keys: root.present ? T.deviceState(root._doc, root.key, root.device).keys : []

    function _set(next) {
        if (!store.ready || next === root._doc) return
        root._doc = next
        store.value = next
    }

    function _patch(p) { if (root.present) root._set(T.setProfile(root._doc, root.key, root.device, p)) }

    // What the active profile maps the tablet onto, in pixels: its output, or the box around every output.
    readonly property var targetSize: T.targetSize(
        Quickshell.screens.map(sc => ({ name: sc.name, x: sc.x, y: sc.y, width: sc.width, height: sc.height })),
        root.profile ? root.profile.output : "")

    function setArea(a)         { root._patch({ area: a }) }
    function fullArea()         { if (root.present) root._patch({ area: T.fullArea(root.device) }) }
    function setPressure(lo, hi) { root._patch({ pressure: { min: lo, max: hi } }) }
    function setRelative(on)    { root._patch({ relative: on }) }

    // The area that fills the screen, around where the current one is.
    function fitToScreen() {
        if (!root.present) return
        const t = root.targetSize
        root._patch({ area: T.fitRatio(root.profile.area, root.device, T.areaRatio(t.w, t.h, root.profile.rotation)) })
    }
    // Where the pen lands, how it is turned, and whether the area keeps the screen's shape: any of the three
    // changes what shape the area has to be, so a locked area is fitted again.
    function setOutput(name)    { root._patch({ output: name }); root._refit() }
    function setRotation(deg)   { root._patch({ rotation: deg }); root._refit() }
    function setLockRatio(on)   { root._patch({ lockRatio: on }); root._refit() }
    function _refit()           { if (root.present && root.profile.lockRatio) root.fitToScreen() }

    // A new width for the area; the height follows while the shape is locked to the screen's.
    function resizeArea(width) {
        if (!root.present) return
        const t = root.targetSize
        const ratio = root.profile.lockRatio ? T.areaRatio(t.w, t.h, root.profile.rotation) : 0
        root._patch({ area: T.resizeKeeping(root.profile.area, root.device, width, ratio) })
    }
    // Back to the stock values; the profile keeps its name.
    function resetProfile() {
        if (!root.present) return
        const d = T.defaultProfile(root.device)
        root._patch({ output: d.output, area: d.area, lockRatio: d.lockRatio, rotation: d.rotation, relative: d.relative, pressure: d.pressure })
    }

    function select(name)        { if (root.present) root._set(T.selectProfile(root._doc, root.key, root.device, name)) }
    function cycle(dir)          { if (root.present) root._set(T.cycleProfile(root._doc, root.key, root.device, dir)) }
    function addProfile(name)    { if (root.present) root._set(T.addProfile(root._doc, root.key, root.device, name, true)) }
    function copyProfile(name)   { if (root.present) root._set(T.addProfile(root._doc, root.key, root.device, name, false)) }
    function renameProfile(from, to) { if (root.present) root._set(T.renameProfile(root._doc, root.key, root.device, from, to)) }
    function removeProfile(name) { if (root.present) root._set(T.removeProfile(root._doc, root.key, root.device, name)) }
    function setKey(i, binding)  { if (root.present) root._set(T.setKey(root._doc, root.key, root.device, i, binding)) }

    JsonStore {
        id: store
        path: Quickshell.statePath("tablet.json")
        onLoaded: root._doc = T.normalise(store.value)
    }

    // ══ Into Hyprland ════════════════════════════════════════════════════════
    // A config reload resets runtime values to the config file, and this shell triggers one on every palette
    // change, so the profile goes in again on Hyprland's own `configreloaded` event.
    readonly property string _stock: root.present ? T.lua(T.defaultProfile(root.device), root.device) : ""
    readonly property string lua: root.present ? T.lua(root.profile, root.device) : ""
    readonly property string _want: root.enabled ? root.lua : root._stock

    property bool _applied: false      // did THIS session send anything
    property bool _again: false
    property string lastError: ""

    on_WantChanged: root.queue()
    function queue() { debounce.restart() }

    Timer {
        id: debounce
        interval: 300
        onTriggered: root._apply()
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded" && root._applied) root.queue()
        }
    }

    function _apply() {
        if (!root.present || root._want === "") return
        if (!root.enabled && !root._applied) return
        // Still the stock profile and nothing sent yet: nothing to undo, nothing to say.
        if (root.enabled && !root._applied && root._want === root._stock) return
        if (evalProc.running) { root._again = true; return }
        root._applied = root.enabled          // an "off" push is the last one
        evalProc.command = ["hyprctl", "eval", root._want]
        evalProc.running = true
    }

    Process {
        id: evalProc
        stdout: StdioCollector { id: evalOut }
        stderr: StdioCollector { id: evalErr }
        onExited: function (code) {
            const msg = (evalOut.text + evalErr.text).trim()
            // hyprctl answers "ok" and prints a Lua error otherwise; the exit code alone is not trusted.
            root.lastError = (code !== 0 || /error|fail/i.test(msg))
                ? (msg.split("\n").pop() || ("failed (" + code + ")")) : ""
            if (root.lastError !== "") console.warn("Tablet: hyprctl eval failed -", root.lastError)
            if (root._again) { root._again = false; root._apply() }
        }
    }

    // ══ Granting access ══════════════════════════════════════════════════════
    // The one root step. pkexec shows the shell's own polkit dialog; afterwards the tablet is probed again,
    // which is when `access` turns true and the helper starts.
    property bool accessBusy: false
    property string accessError: ""

    function grantAccess()  { root._access("--install") }
    function removeAccess() { root._access("--remove") }
    function _access(flag) {
        if (root.accessBusy) return
        root.accessBusy = true
        root.accessError = ""
        accessProc.command = ["bash", root.accessPath, flag]
        accessProc.running = true
    }
    Process {
        id: accessProc
        stderr: StdioCollector { id: accessErr }
        onExited: function (code) {
            root.accessBusy = false
            if (code !== 0) {
                const said = accessErr.text.trim().split("\n").pop()
                // pkexec exits 126 when the dialog is dismissed and 127 when it is not authorised.
                root.accessError = (code === 126 || code === 127) ? "The request was cancelled" : (said || "It did not finish")
            }
            root.reprobe()
        }
    }

    // ══ The live half ════════════════════════════════════════════════════════
    // Express keys are always read while the helper runs; the pen only while somebody is looking
    // (`acquireLive` / `releaseLive`, paired, like Clock.acquireSeconds), so an idle shell does nothing
    // per pen report.
    property int _watchers: 0
    function acquireLive() { root._watchers += 1 }
    function releaseLive() { root._watchers = Math.max(0, root._watchers - 1) }
    on_WatchersChanged: root._sendWatch()

    // The latest pen report (see the header of tablet-helper.py), null when nothing is being watched.
    property var pen: null
    property int rate: 0
    property var padDown: []
    property var info: null            // the helper's hello: ranges and key count
    property string helperFatal: ""    // "access" | "missing": do not restart
    property string helperError: ""    // died too often

    signal padKey(int index, bool down)

    readonly property bool helperWanted: root.enabled && root.present && root.device.access && root.helperFatal === ""
        && root.helperError === ""
    property bool _cycling: false
    Timer { id: cycleTimer; interval: 300; onTriggered: root._cycling = false }

    // It can die: a device pulled out, a read error. Started again a few times a minute at most.
    property var _deaths: []
    function _died() {
        const now = Date.now()
        root._deaths = root._deaths.filter(t => now - t < 60000).concat([now])
        if (root._deaths.length > 3) { root.helperError = "The tablet keeps disconnecting"; return }
        root._cycling = true
        cycleTimer.restart()
    }

    function _sendWatch() {
        if (!helper.running) return
        helper.write(JSON.stringify({ cmd: "watch", on: root._watchers > 0 }) + "\n")
        if (root._watchers === 0) { root.pen = null; root.rate = 0 }
    }

    Process {
        id: helper
        // The control channel; nothing here turns it off.
        stdinEnabled: true
        running: root.helperWanted && !root._cycling
        command: ["python3", root.scriptPath, "--pen", root.present ? root.device.pen : ""].concat(
            root.present && root.device.pad !== "" ? ["--pad", root.device.pad] : [])
        stdout: SplitParser { onRead: function (line) { root._onLine(line) } }
        stderr: SplitParser { onRead: function (line) { console.log("Tablet:", line) } }
        onRunningChanged: {
            if (running) {
                root.helperError = ""
                root._sendWatch()
                return
            }
            root.pen = null
            root.rate = 0
            root.padDown = []
            root.info = null
        }
        onExited: function (code) {
            if (!root.helperWanted) return
            if (code === 3) return                                  // `fatal` said why
            if (code === 4) root.reprobe()                          // the device left: look again
            root._died()
        }
    }

    function _onLine(line) {
        let o
        try { o = JSON.parse(line) } catch (e) { return }
        if (o === null || typeof o !== "object") return
        switch (o.t) {
        case "hello":
            root.info = o
            root.padDown = new Array(o.keys || 0).fill(false)
            break
        case "pad": {
            if (typeof o.key !== "number" || o.key < 0 || o.key >= root.padDown.length) break
            const next = root.padDown.slice()
            next[o.key] = o.down === true
            root.padDown = next
            root.padKey(o.key, o.down === true)
            if (o.down === true) root.runKey(o.key)
            break
        }
        case "pen":
            if (root._watchers > 0) root.pen = o
            break
        case "rate":
            if (root._watchers > 0) root.rate = o.hz | 0
            break
        case "fatal":
            root.helperFatal = o.reason === "access" ? "access" : "missing"
            break
        case "gone":
            break
        }
    }

    // ══ What an express key does ═════════════════════════════════════════════
    property string keyNote: ""

    function runKey(i) {
        const b = root.keys[i]
        if (!b || b.kind === "none") return
        root.keyNote = ""
        if (b.kind === "chord") {
            const argv = T.chordArgv(b.value)
            if (!argv) return
            if (!root.hasWtype) { root.keyNote = root.chordBlocker(); return }
            Quickshell.execDetached(argv)
        } else if (b.kind === "command") {
            const argv = Ia.parseCommand(b.value)
            if (!argv || argv.length === 0) { root.keyNote = "That command could not be read"; return }
            Quickshell.execDetached(argv)
        } else if (b.kind === "profile") {
            if (b.value === "next" || b.value === "prev") root.cycle(b.value)
            else root.select(b.value)
        }
    }

    // ══ Lifecycle ════════════════════════════════════════════════════════════
    onEnabledChanged: {
        if (root.enabled) { root.helperFatal = ""; root.helperError = ""; root._deaths = []; root.reprobe(); wtypeProc.running = true }
        root.queue()
    }
    Component.onCompleted: { if (root.enabled) { root.reprobe(); wtypeProc.running = true } }

    // On a reload a tablet may have been plugged in; the dock page also asks when it opens.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded" && root.enabled && !root.present) root.reprobe()
        }
    }

    // `qs ipc -c ~/.config/quicktest call tablet status`: read-only.
    IpcHandler {
        target: "tablet"
        function status(): string {
            return "enabled=" + root.enabled + " probed=" + root.probed + " present=" + root.present
                 + " device=" + (root.present ? root.device.name : "none")
                 + " size=" + (root.present ? root.device.widthMm + "x" + root.device.heightMm : "-")
                 + " access=" + (root.present ? root.device.access : false) + " rule=" + (root.rule || "?")
                 + " helper=" + helper.running + " fatal=" + (root.helperFatal || "none")
                 + " applied=" + root._applied + " lastError=" + (root.lastError || "none")
                 + " profile=" + (root.profile ? root.profile.name : "-")
        }
    }
}
