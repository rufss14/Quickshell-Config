pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/clockfmt.js" as ClockFmt
// ── OverviewChips ─────────────────────────────────────────────────────────────
// Live chips in the overview's header, each there only while it has something to say
// (2026-10-20, the user's pick): a running timer counting down, the reminders that are
// due — each gives way to the panel that owns it (the sidebar's timer, the clock panel) —
// Undo for the last window move while there is one, and Sessions, always, which opens its card under the header (OverviewSessions). In
// the Now Playing panel's round-chip pill (ChipTray), gone when there's nothing to say.
// (The notifications have the header's Workspaces | Notifications tabs.) Holds the
// seconds clock only while a timer is counting.
// ─────────────────────────────────────────────────────────────────────────────
ChipTray {
    id: root

    property var screen: null
    property bool live: false
    // Sessions: always here; opens the overview's Sessions card (Overview `sessionsOpen`).
    property bool sessionsOpen: false
    signal sessionsAsked()
    signal undoAsked()

    readonly property bool timing: Timers.timerRunning && !Timers.timerPaused
    readonly property bool showTimer: root.live && (Timers.timerRunning || Timers.timerPaused)
    property bool _held: false
    function _sync() {
        const want = root.live && root.timing
        if (want === root._held) return
        if (want) Clock.acquireSeconds(); else Clock.releaseSeconds()
        root._held = want
    }
    onTimingChanged: root._sync()
    onLiveChanged: root._sync()
    Component.onCompleted: root._sync()
    Component.onDestruction: if (root._held) Clock.releaseSeconds()
    readonly property int timerLeft: root.timing
        ? Math.max(0, Math.ceil((Timers.timerEnd - Clock.now.getTime()) / 1000)) : Timers.timerRemain

    function leaveTo(fn) { UiState.overviewOpen = false; fn() }

    ChipButton {
        visible: root.showTimer
        symbol: "timer"
        label: ClockFmt.clock(root.timerLeft)
        on: root.timing
        onActivated: root.leaveTo(() => UiState.openSidePanel("timer", "timer", root.screen))
    }
    ChipButton {
        visible: root.live && Reminders.overdueCount > 0
        symbol: "alarm"
        label: Reminders.overdueCount === 1 ? Translation.tr("1 due") : Translation.tr("%1 due").arg(Reminders.overdueCount)
        on: true
        tint: Colors.of(QsWindow.window).danger
        onActivated: root.leaveTo(() => UiState.openPanel("clock"))
    }
    // The last move (a drag, a send, a swap), until it is undone or the overview closes (Hypr.undoMove).
    ChipButton {
        visible: root.live && Hypr.canUndoMove
        symbol: "undo"
        label: Translation.tr("Undo")
        onActivated: root.undoAsked()
    }
    ChipButton {
        visible: root.live
        symbol: "bookmarks"
        label: WorkspaceSessions.restoring !== "" ? Translation.tr("Restoring…") : ""
        on: root.sessionsOpen
        onActivated: root.sessionsAsked()
    }
}
