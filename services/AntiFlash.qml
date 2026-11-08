pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "../config"
import "antiflash.js" as A

// ── AntiFlash ─────────────────────────────────────────────────────────────────
// Anti-flashbang: when what you're looking at turns very bright — a white page at
// night, a flash in a game — the screen dims, and brightens again when it goes dark.
//
// ── Measure in the shell, dim in the compositor ───────────────────────────────
// The FOCUSED monitor is sampled (modules/bar/BrightnessProbe, inside that screen's
// bar window: a still screencopy, shrunk on the GPU to 64×36, averaged in a Canvas —
// no process, no file). Hyprland's screencopy skips the screen shader
// (`blockScreenShader`), so the probe always sees the UNDIMMED picture: no feedback
// loop, and screenshots and recordings are never dimmed either.
//
// The dimming is a Hyprland SCREEN SHADER with the gain BAKED IN — one file per
// level, written to the cache and applied by `hyprctl eval` (hl.config's
// decoration.screen_shader). A uniform it could read per frame would be smoother,
// but the only per-frame uniform (`time`) requires damage tracking OFF, which costs
// the GPU far more than this saves. A shader that measured brightness ITSELF would
// redraw only damaged regions with a fresh gain and leave seams; a changed
// screen_shader damages every monitor whole (PropRefresher), so one gain is one look.
// Darks dim less than brights (the shader's curve), so a dark UI stays readable.
//
// Changes ease in steps (`steps` levels, Motion.fast apart) rather than snapping;
// with animations off, one step. Off — or gain back at 1 — the shader is REMOVED,
// not left at ×1: any screen shader costs a pass per frame and blocks direct scanout.
//
// ── When it samples ───────────────────────────────────────────────────────────
// Once a second while on (a page changing inside a browser sends nothing), and soon
// after anything Hyprland says changed what's on screen (focus, workspace, a window
// opening, fullscreen). A Hyprland config reload resets the option, so it's applied
// again on `configreloaded` (Cursor's rule).
//
// Diagnose: `qs ipc -c ~/.config/quicktest call antiflash status`.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property bool enabled: Config.antiFlash
    // Only at night: Night light's own window (its schedule, sun or fixed times).
    readonly property bool active: root.enabled && (!Config.antiFlashNightOnly || NightLight.inNightWindow)

    // Which monitor the probe runs on: the focused one.
    readonly property string probeScreen: Hyprland.focusedMonitor?.name ?? ""

    // The last reading (0..1 mean luminance, -1 none yet) and the gain it asked for.
    property real brightness: -1
    property real target: 1
    // What the screen is showing now.
    property real gain: 1
    property string lastError: ""

    // Asked of the probe: sample soon (an event), beyond its once-a-second beat.
    signal sampleSoon()

    // ── From a reading to a gain (antiflash.js, tested) ──────────────────────────
    function report(mean) {
        if (!root.active) return
        root.brightness = mean
        const next = A.decide(mean, root.target, Config.antiFlashThreshold, Config.antiFlashFloor)
        if (next === root.target) return
        root.target = next
        root._ease()
    }

    onActiveChanged: {
        if (root.active) { if (!origProc.done) origProc.running = true; root.sampleSoon(); return }
        root.brightness = -1
        root.target = 1
        root._ease()
    }

    // ── Easing in steps ───────────────────────────────────────────────────────
    readonly property int steps: Motion.fast > 0 ? 4 : 1
    property var _queue: []
    function _ease() {
        root._queue = A.ramp(root.gain, root.target, root.steps)
        if (!stepTimer.running) stepTimer.start()
    }
    Timer {
        id: stepTimer
        interval: Math.max(16, Motion.fast)
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (root._queue.length === 0 || applyProc.running) {
                if (root._queue.length === 0) stepTimer.stop()
                return
            }
            const next = root._queue[0]
            root._queue = root._queue.slice(1)
            root._apply(next)
        }
    }

    // ── Applying ──────────────────────────────────────────────────────────────
    readonly property string dir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache"))
                                  + "/quickshell-quicktest/antiflash"
    // Two names, alternated: Hyprland compares the option's VALUE, so rewriting one
    // file under the same path would read as "unchanged" (Cursor's two-name trick).
    property bool _flip: false

    function _apply(g) {
        root.gain = g
        // The path is ours (the cache dir); refuse one that could break the Lua string.
        if (/["\\\n]/.test(root.dir)) { root.lastError = "Cache path can't be quoted for Hyprland"; return }
        if (g >= 0.999) {
            // Back to whatever the config had (usually nothing).
            const orig = /["\\\n]/.test(root._original) ? "" : root._original
            applyProc.command = ["hyprctl", "eval", 'hl.config({ decoration = { screen_shader = "' + orig + '" } })']
        } else {
            root._flip = !root._flip
            const path = root.dir + "/antiflash-" + (root._flip ? "a" : "b") + ".frag"
            applyProc.command = ["sh", "-c",
                'mkdir -p "$1" && printf "%s" "$2" > "$3.tmp" && mv "$3.tmp" "$3" && exec hyprctl eval "$4"',
                "sh", root.dir, A.shader(g), path,
                'hl.config({ decoration = { screen_shader = "' + path + '" } })']
        }
        applyProc.running = true
    }
    // A screen shader of your own (hypr config): read once, put back when this lets go.
    property string _original: ""
    Process {
        id: origProc
        property bool done: false
        command: ["hyprctl", "getoption", "decoration:screen_shader", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                origProc.done = true
                try {
                    const v = String(JSON.parse(text).str ?? "")
                    root._original = (v === "[[EMPTY]]" || v.indexOf("/quickshell-quicktest/antiflash/") >= 0) ? "" : v
                } catch (e) { root._original = "" }
            }
        }
    }
    Process {
        id: applyProc
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                // hyprctl eval answers "ok" or the Lua error.
                root.lastError = (t === "" || t === "ok") ? "" : t
                if (root.lastError !== "") console.warn("AntiFlash:", root.lastError)
            }
        }
    }

    // A Hyprland reload puts the config's own screen_shader back.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const n = event.name
            if (n === "configreloaded") { if (root.gain < 0.999) reapply.restart(); return }
            if (root.active && (n === "activewindowv2" || n === "workspacev2" || n === "openwindow"
                                || n === "fullscreen" || n === "focusedmonv2"))
                root.sampleSoon()
        }
    }
    Timer { id: reapply; interval: 200; onTriggered: root._apply(root.gain) }

    IpcHandler {
        target: "antiflash"
        function toggle(): void { Config.antiFlash = !Config.antiFlash }
        function status(): string {
            return "enabled=" + root.enabled + " active=" + root.active + " screen=" + root.probeScreen
                 + " brightness=" + root.brightness.toFixed(2) + " target=" + root.target
                 + " gain=" + root.gain + (root.lastError !== "" ? " error=" + root.lastError : "")
        }
    }
}
