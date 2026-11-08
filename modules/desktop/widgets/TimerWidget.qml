pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/clockfmt.js" as ClockFmt

// ── TimerWidget ───────────────────────────────────────────────────────────────
// The countdown and stopwatch from the overview's timer card, on the desktop.
//
// Backed by the Timers service, which anchors everything to absolute epoch timestamps
// rather than accumulating ticks — so a timer survives a reload, and one that would
// have finished while the machine was off comes back FINISHED rather than resuming.
// This tile is a view over that; it owns no timing of its own.
//
// ── Material 3 Expressive (2026-10-30) ────────────────────────────────────────
// The face is the timer panel's own TimerDial — the time left as a cookie that shrinks,
// turns while it runs and bursts when it ends — not a second drawing of it. Idle, you
// TURN it to set the length (an hour all the way round) and tap it to start, exactly as
// in the panel. Medium adds the quick lengths and the controls beside it; small keeps the
// two you can't reach by tapping the dial (reset, timer ⇄ stopwatch) in the corner, on
// hover.
Item {
    id: root

    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.of(QsWindow.window).primary

    readonly property bool stopwatch: root.opts.stopwatch === true

    // ── The numbers, as the panel reads them ──────────────────────────────────
    readonly property bool runActive: Timers.timerRunning || Timers.timerPaused
    readonly property int  remain: Timers.timerRemain
    readonly property bool finished: Timers.timerDone && !Timers.pomoOn
    readonly property bool idle: !root.stopwatch && !root.runActive && !Timers.timerDone
    readonly property bool running: root.stopwatch ? Timers.swRunning : Timers.timerRunning
    readonly property bool paused: root.stopwatch ? (!Timers.swRunning && Timers.swElapsed > 0) : Timers.timerPaused

    readonly property string dialText: root.stopwatch ? ClockFmt.clock(Timers.swElapsed / 1000)
        : (root.runActive || Timers.timerDone) ? Timers.clockString(root.remain)
        : Timers.clockString(Timers.timerTotal)
    // Running or paused: what is left of this run. Idle: where the dial is turned to.
    // Done: a coin. A stopwatch is always a full cookie, its orbit the minutes.
    readonly property real dialValue: root.stopwatch ? 1
        : root.runActive ? (Timers.timerSpan > 0 ? Math.min(1, root.remain / Timers.timerSpan) : 0)
        : Timers.timerDone ? 0 : Math.min(1, Timers.timerTotal / 3600)
    readonly property string dialCaption: root.size === "small" ? ""
        : root.paused ? "Paused"
        : root.finished ? "Time's up"
        : root.idle ? "Turn to set" : ""

    function primary() {
        if (root.stopwatch) {
            if (Timers.swRunning) Timers.pauseStopwatch()
            else                  Timers.startStopwatch()
        } else if (Timers.timerRunning) Timers.pauseTimer()
        else if (Timers.timerPaused)    Timers.resumeTimer()
        else                            Timers.startTimer()
    }
    function reset() {
        if (root.stopwatch) Timers.resetStopwatch()
        else                Timers.stopTimer()
    }
    function swapMode() {
        if (root.widgetId >= 0) DesktopWidgets.setOpt(root.widgetId, "stopwatch", !root.stopwatch)
    }

    HoverHandler { id: tileHover }

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacingLg

        TimerDial {
            Layout.preferredWidth: parent.height
            Layout.fillHeight: true
            Layout.alignment: root.size === "small" ? Qt.AlignHCenter : Qt.AlignLeft
            Layout.fillWidth: root.size === "small"
            text: root.dialText
            caption: root.dialCaption
            value: root.dialValue
            orbit: root.stopwatch ? Timers.swElapsed / 60000
                 : root.runActive ? Math.max(0, Timers.timerSpan - root.remain) / 60 : 0
            accent: root.finished ? Colors.of(QsWindow.window).danger : root.accent
            running: root.running
            paused: root.paused
            done: root.finished
            urgent: Timers.timerRunning && root.remain > 0 && root.remain <= 10 && Timers.timerSpan > 10
            interactive: root.idle
            live: root.active
            onTapped: root.primary()
            // Whole minutes: sixty to a turn. All the way round is an hour.
            onTurned: function (f) { Timers.setTimerLength(Math.round(f * 60) * 60) }
        }

        // ── Medium: what it is, quick lengths, the controls ───────────────────
        ColumnLayout {
            visible: root.size !== "small"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingSm

            StyledText {
                Layout.fillWidth: true
                text: root.stopwatch
                      ? "Stopwatch" + (Timers.laps.length > 0 ? " · " + Timers.laps.length
                                       + (Timers.laps.length === 1 ? " lap" : " laps") : "")
                      : "Timer"
                variant: "title"
                font.weight: Font.Bold
                color: Colors.of(QsWindow.window).fg
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.stopwatch && Timers.laps.length > 0
                text: "Last lap " + Timers.lapString(Timers.laps[0])
                variant: "caption"
                emphasis: "dim"
            }

            // Quick lengths, while a timer is idle: each starts at once.
            Flow {
                Layout.fillWidth: true
                visible: root.idle
                spacing: Tokens.spacingXs
                Repeater {
                    model: [1, 5, 10, 25]
                    TileRow {
                        id: preset
                        required property int modelData
                        implicitWidth: presetText.implicitWidth + Tokens.spacingMd * 2
                        onTapped: Timers.startTimerFor(preset.modelData * 60)
                        StyledText {
                            id: presetText
                            text: preset.modelData + "m"
                            variant: "caption"
                            font.weight: Font.DemiBold
                            color: Colors.of(QsWindow.window).fg
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                TileChip {
                    filled: true
                    awake: true
                    box: Tokens.iconXl + Tokens.spacingMd
                    accent: root.accent
                    icon: root.running ? "pause" : "play_arrow"
                    onActivated: root.primary()
                }
                TileChip {
                    awake: true
                    box: Tokens.iconXl + Tokens.spacingSm
                    icon: "restart_alt"
                    onActivated: root.reset()
                }
                TileChip {
                    visible: root.stopwatch
                    enabled: Timers.swRunning
                    awake: true
                    box: Tokens.iconXl + Tokens.spacingSm
                    icon: "flag"
                    onActivated: Timers.lap()
                }
                TileChip {
                    awake: true
                    box: Tokens.iconXl + Tokens.spacingSm
                    icon: "swap_horiz"
                    onActivated: root.swapMode()
                }
            }
        }
    }

    // ── Small: reset and the mode switch, in the corner, on hover ─────────────
    Row {
        anchors.top: parent.top
        anchors.right: parent.right
        visible: root.size === "small"
        spacing: Tokens.spacingXs
        TileChip { icon: "restart_alt"; awake: tileHover.hovered; onActivated: root.reset() }
        TileChip { icon: "swap_horiz"; awake: tileHover.hovered; onActivated: root.swapMode() }
    }
}
