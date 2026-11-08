pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

// ── NightLight ────────────────────────────────────────────────────────────────
// Warms the display after dark.
//
// ── Two backends, and the choice is detected, not assumed ─────────────────────
//   · hyprsunset — Hyprland's own (extra/hyprsunset). Preferred when present: it
//     talks to the compositor that is actually running.
//   · gammastep  — the wlroots-generic one, via wlr-gamma-control.
//
// Which one exists is PROBED once, not guessed from the desktop: this config is
// published and neither is a dependency of the shell. When neither is installed the
// control is disabled with a reason — `blocker()`, the same contract as
// Discord.pressBlocker() and WallpaperEngine.blocker() — rather than failing on click.
//
// ── The backend runs PERSISTENTLY, and that is not a style choice ─────────────
// Both tools set gamma through wlr-gamma-control-unstable-v1, where the adjustment
// belongs to the CLIENT: when the client disconnects, the compositor restores the
// original ramps. So "set it and exit" cannot work — the warmth would revert the
// instant the process ended. The process is held open for exactly as long as the
// warmth should be on screen, and turning night light off is killing it.
//
// This is also why `_backendDied` exists. If the process exits while we still expect
// it to be running, the screen has silently gone back to normal, and the shell must
// say so rather than showing an "on" toggle over an unchanged display.
//
// ── The shell owns the schedule ───────────────────────────────────────────────
// Both tools can run their own sunset/sunrise schedule (gammastep -l, hyprsunset's
// config). We deliberately don't use that: the shell already knows where you are
// (Weather), already has one wall clock (Clock), and a schedule living in the tool
// would be a second source of truth that the settings page could not show or change.
// The backend is told one temperature and nothing else.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── Which backend ─────────────────────────────────────────────────────────
    // "" until the probe finishes; "hyprsunset" | "gammastep" | "none" after.
    readonly property string backend: root._backend
    property string _backend: ""
    readonly property bool probed: root._probed
    property bool _probed: false

    readonly property bool available: root._backend === "hyprsunset"
                                   || root._backend === "gammastep"

    // Same contract as Discord.pressBlocker(): "" when the control is usable, otherwise
    // the reason to show instead of letting someone click a thing that cannot work.
    function blocker() {
        if (!root._probed) return "Checking for a night-light tool…"
        if (!root.available)
            return "Needs hyprsunset or gammastep — neither is installed"
        if (root._backendDied)
            return "The night-light process stopped unexpectedly"
        return ""
    }

    // Re-run the backend probe. Exists for the setup page, whose whole workflow is
    // "go install this in a terminal, come back" — without it the answer stays
    // frozen at whatever was true when the shell started and the only way to see
    // your own `pacman -S hyprsunset` is a full reload.
    function reprobe() {
        root._probed = false
        probe.running = false
        probe.running = true
    }

    Process {
        id: probe
        running: true
        // First one found wins, hyprsunset first. `command -v` rather than a path
        // guess: neither tool has a canonical install location worth hardcoding.
        command: ["bash", "-c",
                  "command -v hyprsunset >/dev/null 2>&1 && { echo hyprsunset; exit 0; }; "
                + "command -v gammastep >/dev/null 2>&1 && { echo gammastep; exit 0; }; "
                + "echo none"]
        stdout: StdioCollector {
            onStreamFinished: {
                root._backend = text.trim() || "none"
                root._probed  = true
            }
        }
    }

    // ── Should it be warm right now? ──────────────────────────────────────────
    // The manual switch, or the schedule when following one. `Config.nightLight` stays
    // the master switch either way: auto mode decides WHEN within "enabled", it does
    // not turn the feature on behind your back.
    readonly property bool shouldBeOn:
        Config.nightLight && (!Config.nightLightAuto || root.inNightWindow)

    // The active temperature, or 6500 (neutral) when it should be off. Clamped, because
    // a temperature outside the tools' accepted range is an error exit, not a no-op.
    readonly property int temperature:
        Math.max(Config.nightLightTempMin,
                 Math.min(Config.nightLightTempMax, Config.nightLightTemp))

    // ── The schedule ──────────────────────────────────────────────────────────
    // Sunset→sunrise from the weather service when we have it and the user wants it,
    // fixed clock times otherwise.
    readonly property var _sunDay: Weather.days.length > 0 ? Weather.days[0] : null
    readonly property bool haveSun:
        Config.nightLightFollowSun && root._sunDay !== null
        && (root._sunDay.sunrise || "") !== "" && (root._sunDay.sunset || "") !== ""

    // Minutes past midnight, local. The sun times arrive as local ISO timestamps
    // ("2026-08-01T20:41"), so the time-of-day is the part after the T.
    function _minutesOfIso(iso) {
        const t = String(iso).split("T")[1] || ""
        const p = t.split(":")
        if (p.length < 2) return -1
        const h = parseInt(p[0]), m = parseInt(p[1])
        return (isNaN(h) || isNaN(m)) ? -1 : h * 60 + m
    }
    function _minutesOfClock(hhmm) {
        const p = String(hhmm).split(":")
        if (p.length < 2) return -1
        const h = parseInt(p[0]), m = parseInt(p[1])
        return (isNaN(h) || isNaN(m)) ? -1 : h * 60 + m
    }

    readonly property int startMin: root.haveSun
        ? root._minutesOfIso(root._sunDay.sunset)
        : root._minutesOfClock(Config.nightLightFrom)
    readonly property int endMin: root.haveSun
        ? root._minutesOfIso(root._sunDay.sunrise)
        : root._minutesOfClock(Config.nightLightTo)

    // Bound to the shared Clock (minute resolution — a night-light schedule does not
    // need seconds) rather than a Timer of its own. See services/Clock.qml.
    readonly property int nowMin: Clock.hours * 60 + Clock.minutes

    readonly property bool inNightWindow: {
        const s = root.startMin, e = root.endMin, n = root.nowMin
        // An unparseable time must not silently mean "always on".
        if (s < 0 || e < 0) return false
        // The window normally CROSSES MIDNIGHT (20:00 → 07:00), so the test is an OR,
        // not the `s <= n && n < e` you'd write for an ordinary range — that form is
        // false for every minute of a wrapping window and the schedule would never
        // fire at all.
        return s <= e ? (n >= s && n < e) : (n >= s || n < e)
    }

    // ── Driving the backend ───────────────────────────────────────────────────
    property bool _backendDied: false

    readonly property bool running: warmth.running

    // Rebuilt whenever the temperature changes. Assigning `command` while running has
    // no effect, so a temperature change restarts the process — see _apply().
    function _command() {
        if (root._backend === "hyprsunset")
            // hyprsunset runs in the foreground holding the adjustment, which is the
            // shape this needs. NOTE: not verified against a running binary — it is not
            // installed on the development machine — so if this is wrong it will show as
            // the process dying immediately, which blocker() reports.
            return ["hyprsunset", "-t", "" + root.temperature]
        if (root._backend === "gammastep")
            // -P resets existing ramps first so re-applying is clean rather than
            // compounding; -O is manual mode with no location or schedule of its own,
            // which is what leaves the schedule to us. -m wayland is left to
            // gammastep's own detection: forcing a method is how this breaks on a
            // compositor it would have handled.
            return ["gammastep", "-P", "-O", "" + root.temperature]
        return []
    }

    Process {
        id: warmth
        running: false
        onExited: function(code) {
            // Expected when WE stopped it. Unexpected means the screen has reverted and
            // the toggle is now lying, so it is recorded and surfaced.
            if (root._stopping) { root._stopping = false; return }
            if (root.shouldBeOn && root.available) root._backendDied = true
        }
    }
    property bool _stopping: false

    function _stop() {
        if (!warmth.running) return
        root._stopping = true
        warmth.running = false
    }

    function _apply() {
        if (!root._probed || !root.available) return

        if (!root.shouldBeOn) {
            root._stop()
            root._backendDied = false
            return
        }

        const cmd = root._command()
        if (cmd.length === 0) return

        // Always a stop-then-start, never an assignment to a live process: `command` is
        // read when the process starts, so changing the temperature on a running one
        // would update the property and change nothing on screen.
        root._stop()
        root._backendDied = false
        warmth.command = cmd
        warmth.running = true
    }

    onShouldBeOnChanged:  root._apply()
    onTemperatureChanged: root._apply()
    onProbedChanged:      root._apply()

    // ── Convenience for the UI ────────────────────────────────────────────────
    function toggle() { Config.nightLight = !Config.nightLight }

    // What the pill and the settings page say about why it is or isn't warm — the
    // schedule is the part that is otherwise invisible.
    readonly property string statusText: {
        if (!root.available) return "Unavailable"
        if (!Config.nightLight) return "Off"
        if (!Config.nightLightAuto) return root.temperature + "K"
        if (root.inNightWindow) return root.temperature + "K · until " + root.endText
        return "Waiting for " + root.startText
    }

    function _fmt(mins) {
        if (mins < 0) return "—"
        const h = Math.floor(mins / 60) % 24, m = mins % 60
        return Clock.pad(h) + ":" + Clock.pad(m)
    }
    readonly property string startText: root._fmt(root.startMin)
    readonly property string endText:   root._fmt(root.endMin)
}
