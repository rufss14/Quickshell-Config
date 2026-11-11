import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── SideTimer ─────────────────────────────────────────────────────────────────
// The countdown, the stopwatch and alarms as a sidebar button: a glyph at rest, a
// ring while one runs — the countdown's time LEFT, or the stopwatch's current minute
// going round — and everything in a panel beside it (TimerPanel, in SidePanelDock).
// A finished countdown — or an alarm that is RINGING — holds a full ring in the danger colour and nudges
// its glyph until it's dismissed. A paused countdown keeps its ring, in the warning colour. A focus cycle
// is just a countdown, so its ring (and the time on hover) work the same. Hovering while one runs swaps the glyph for the time
// (SideClips' rule: never the time at rest).
//
//   click   the panel, beside this button (again: shut it)
//   middle  silence a ringing alarm / dismiss a finished countdown; otherwise act on the panel's
//           current face (countdown: start at the set length / stop, or resume a paused one;
//           focus: start / pause / resume; stopwatch: run / pause; alarms: nothing)
//   right   Settings › Sidebar
//
// All of it is services/Timers (persisted, wall-clock anchored); this only looks.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool vertical: true
    property var screen: null

    readonly property bool ownsPanel: UiState.sidePanelScreen
        ? UiState.sidePanelScreen === root.screen : root.screen === Quickshell.screens[0]
    readonly property bool open: UiState.sidePanel === "timer" && root.ownsPanel

    // Which one the ring shows: a countdown running or finished wins over the stopwatch.
    readonly property bool countdown: Timers.timerRunning || Timers.timerDone || Timers.timerPaused
    readonly property bool stopwatch: !root.countdown && Timers.swRunning
    // Something is asking for you: a countdown that finished, an alarm that is ringing.
    readonly property bool alert: Timers.timerDone || Timers.ringing !== null
    readonly property bool counting: root.countdown || root.stopwatch || root.alert

    // Per second, never per tick: Timers updates swElapsed every 50ms.
    readonly property int swSecs: Math.floor(Timers.swElapsed / 1000)
    readonly property real fill: root.alert ? 1
        : root.countdown ? (Timers.timerSpan > 0 ? Math.min(1, Timers.timerRemain / Timers.timerSpan) : 0)
        : root.stopwatch ? (root.swSecs % 60) / 60
        : 0

    readonly property real ringSize: Config.sidebarCell - Tokens.spacingXs * 2
    readonly property int innerGlyphPx: Math.round(root.ringSize / 2)

    function middle() {
        if (Timers.ringing)                Timers.dismissAlarm()
        else if (Timers.timerDone)         Timers.stopTimer()
        else if (Timers.mode === "timer")
            Timers.timerRunning ? Timers.stopTimer() : Timers.timerPaused ? Timers.resumeTimer() : Timers.startTimer()
        else if (Timers.mode === "focus")
            Timers.timerRunning ? Timers.pauseTimer() : Timers.timerPaused ? Timers.resumeTimer() : Timers.startPomodoro()
        else if (Timers.mode === "stopwatch")
            Timers.swRunning ? Timers.pauseStopwatch() : Timers.startStopwatch()
    }

    implicitWidth:  Config.sidebarCell
    implicitHeight: Config.sidebarCell

    // Finished or ringing: a peek beside it (modules/panels/EventPeek), to dismiss or snooze.
    SidePeek { id: peek; from: "timer"; screen: root.screen }
    onAlertChanged: if (root.alert && Config.peekTimer) peek.fire("timer")

    // At rest: a plain cell, like every other glyph on the edge.
    SideCell {
        id: cell
        glyph: Timers.mode === "alarm" ? "\u{F0020}" : "\u{F051B}"     // 󰀠 alarm / 󰔛 timer
        active: root.open
        hoverKind: "timer"
        opacity: root.counting ? 0 : 1
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
        onClicked:       UiState.toggleSidePanel("timer", "timer", root.screen)
        onMiddleClicked: root.middle()
        onRightClicked:  UiState.openSettingsTo("SidebarPage.qml")
    }

    // Running: the ring, with the glyph (or, hovered, the time) inside.
    Item {
        anchors.fill: parent
        opacity: root.counting ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }

        CellFeedback {
            id: feedback
            anchors.fill: parent
            hovered: mouse.containsMouse
        }

        RadialGauge {
            id: gauge
            anchors.centerIn: parent
            width:  root.ringSize
            height: gauge.width
            thickness: Math.max(Tokens.spacingXs, Math.round(gauge.width / 11))
            // Material 3 Expressive's wavy indicator, as the desktop tiles wear it.
            wavy: true
            accent: root.alert ? Colors.of(QsWindow.window).danger
                  : Timers.timerPaused ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).focus
            value: root.fill
            sampleInterval: 1000
            glide: true

            readonly property bool number: mouse.containsMouse && !root.alert

            // The state as a shape inside the ring (LiveShape): a cookie while a countdown or
            // focus runs, a sunny while the stopwatch does, a squircle in the warning tone while
            // paused, a burst in the danger tone while it rings. The ring is the motion, so no
            // beat; the glyph is already half the ring, so it doesn't shrink onto it.
            LiveShape {
                id: live
                anchors.centerIn: parent
                width:  gauge.width - gauge.thickness * 2 - Tokens.spacingXs * 2
                height: width
                shape: !root.counting ? ""
                     : root.alert ? "burst"
                     : Timers.timerPaused ? "squircle"
                     : root.countdown ? "cookie9"
                     : "sunny"
                // On the hero's chip (primaryContainer already) the running shape is filled `primary`.
                tone: root.alert ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).danger, 0.22)
                    : Timers.timerPaused ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).warning, 0.22)
                    : Config.moduleHero("timer") ? Colors.of(QsWindow.window).primary
                    : Colors.of(QsWindow.window).primaryContainer
                opacity: gauge.number ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
            }

            MaterialIcon {
                id: inner
                anchors.centerIn: parent
                glyph: root.alert ? "\u{F009E}"                                 // 󰂞 bell-ring
                    : root.countdown   ? "\u{F051F}"                           // 󰔟 timer-sand
                    :                    "\u{F051B}"                           // 󰔛 timer (a stopwatch)
                font.pixelSize: root.innerGlyphPx
                color: root.alert ? Colors.of(QsWindow.window).danger
                     : Timers.timerPaused ? Colors.of(QsWindow.window).warning
                     : Config.moduleHero("timer") ? Colors.of(QsWindow.window).fgOnPrimary
                     : Colors.of(QsWindow.window).fgOnPrimaryContainer
                opacity: gauge.number ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                Behavior on color { ColorAnimation { duration: Motion.respond } }

                // Finished: a nudge on Motion.pulse (a channel — it has to keep saying
                // "done" with animations off).
                SequentialAnimation on rotation {
                    running: root.alert && root.counting
                    loops: Animation.Infinite
                    alwaysRunToEnd: true
                    NumberAnimation { to: 14;  duration: Motion.pulse / 4; easing.type: Motion.ambient }
                    NumberAnimation { to: -14; duration: Motion.pulse / 2; easing.type: Motion.ambient }
                    NumberAnimation { to: 0;   duration: Motion.pulse / 4; easing.type: Motion.ambient }
                    PauseAnimation  { duration: Motion.pulse * 2 }
                }
            }
            StyledText {
                anchors.fill: parent
                anchors.margins: gauge.thickness + Tokens.spacingXs
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.countdown ? Timers.clockString(Timers.timerRemain)
                                     : Timers.clockString(root.swSecs)
                font.bold: true
                font.pixelSize: Math.round(height * 0.55)
                fontSizeMode: Text.Fit
                minimumPixelSize: Tokens.fontMicro
                opacity: gauge.number ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
            }
        }

        // Running, the cell's own chip (the at-rest SideCell's is under this overlay).
        SideHover {
            hovered: mouse.containsMouse && root.counting
            from:    "timer"
            arg:     "timer"
            screen:  root.screen
            enabled: !root.open
        }

        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onPressed: function (m) { feedback.press(m.x, m.y) }
            onReleased: feedback.release()
            onCanceled: feedback.release()
            onClicked: function (m) {
                if (m.button === Qt.RightButton)       UiState.openSettingsTo("SidebarPage.qml")
                else if (m.button === Qt.MiddleButton) root.middle()
                else UiState.toggleSidePanel("timer", "timer", root.screen)
            }
        }
    }
}
