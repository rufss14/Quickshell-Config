import QtQuick
import "../../../config"
import "../../../components"
import "../../../services"

// ── QuickTimer ────────────────────────────────────────────────────────────────
// The timer pill's card. Nothing running: three lengths to start at once, and a focus cycle. Running:
// pause or resume, +5 minutes, stop. All of it `Timers`; the countdown is its.
// ─────────────────────────────────────────────────────────────────────────────
QuickFrame {
    id: root

    readonly property bool counting: Timers.timerRunning || Timers.timerPaused

    symbol: "timer"
    shape: "sunny"
    title: Translation.tr("Timer")
    value: ModuleGlance.value("timer")

    trailing: ChipButton {
        visible: root.counting
        symbol: Timers.timerPaused ? "play_arrow" : "pause"
        tint: root.palette.primary
        solid: true
        onActivated: Timers.timerPaused ? Timers.resumeTimer() : Timers.pauseTimer()
    }

    Row {
        visible: !root.counting
        spacing: Tokens.spacingSm
        ChipButton { symbol: "timer"; label: Translation.tr("5 min"); tint: root.palette.primary; onActivated: Timers.startTimerFor(300) }
        ChipButton { symbol: "timer"; label: Translation.tr("15 min"); tint: root.palette.primary; onActivated: Timers.startTimerFor(900) }
        ChipButton { symbol: "timer"; label: Translation.tr("25 min"); tint: root.palette.primary; onActivated: Timers.startTimerFor(1500) }
    }

    OptionCard {
        visible: !root.counting
        width: parent.width
        symbol: "sunny"
        label: Translation.tr("Focus cycle")
        detail: Translation.tr("%1 min on, then a break").arg(Timers.pomoFocus)
        shape: "sunny"
        on: Timers.pomoOn
        onActivated: Timers.startPomodoro()
    }

    Row {
        visible: root.counting
        spacing: Tokens.spacingSm
        ChipButton { symbol: "add"; label: Translation.tr("5 min"); tint: root.palette.primary; onActivated: Timers.extendTimer(300) }
        ChipButton { symbol: "stop"; label: Translation.tr("Stop"); tint: root.palette.primary; onActivated: Timers.stopTimer() }
    }
}
