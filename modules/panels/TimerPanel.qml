pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/alarms.js" as AL
import "../../services/timers.js" as TM

// ── TimerPanel ────────────────────────────────────────────────────────────────
// The countdown, the stopwatch, alarms and a focus (Pomodoro) cycle, beside the sidebar's timer
// button (SidePanelDock). Four faces on a SegmentSwitch — Timers.mode, persisted, so it reopens where
// you left it, and the button's middle-click acts on the same face.
//
// ── The face is a cookie (2026-10-18, round 2) ────────────────────────────────
// The first revamp put a gauge ring in a card, and it read as a rearranged form. This one is built from
// the shell's own shape. `components/TimerDial` is a scalloped COOKIE that is the time left — it shrinks as
// the time goes, turns, breathes, has a star orbiting its rim once a minute, rolls its digits, sends a
// ring off the rim every minute (every second in the last ten), and when time is up throws a burst of small
// cookies and shakes until you dismiss it. When a timer is idle you TURN the cookie to set its minutes
// (a bump at each one); a tap starts it. Everything else moves too: faces slide in the direction of the tab
// you picked, the banner unrolls, laps drop into their list, the controls fade in as they become possible.
//
//   Timer      turn the dial / pick a length; pause, resume, +1 / +5 min, "Ends 14:32"
//   Stopwatch  a cookie that grows over each minute (and pops back at the next), hundredths beside the
//              digits, best / worst laps marked, laps copyable
//   Alarms     a scalloped clock face that shows the time you are setting, a small one on each alarm, repeat
//              days, "Next 07:30 · in 7 h 12 min", and a ringing alarm's banner with Snooze / Dismiss
//   Focus      a Pomodoro cycle on the same cookie: focus, short break, a long one every N sessions
// Everything real is services/Timers (state, ticking, notifications, persistence) and services/timers.js (the
// cycle and the lap maths, tested: `bun scripts/test-timers.js`); this shows it and calls it.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The room the slot has (SidePanelDock sets it); the laps and alarms scroll past it.
    property real maxHeight: Infinity

    readonly property int pad: Tokens.spacingLg
    implicitWidth: Tokens.sideCardUnit * 8
    implicitHeight: Math.min(root.maxHeight, col.implicitHeight + root.pad * 2)

    readonly property string mode: Timers.mode
    readonly property bool countdownFace: root.mode === "timer" || root.mode === "focus"
    readonly property bool ringing: Timers.ringing !== null
    // Finished and nobody has dismissed it (a focus cycle never "finishes": it moves on).
    readonly property bool finished: Timers.timerDone && !Timers.pomoOn
    // Something that has a countdown on screen now.
    readonly property bool active: Timers.timerRunning || Timers.timerPaused
    readonly property real nowMs: Clock.now.getTime()

    // The panel's one accent: focus; the danger colour while something wants you; a break is calm.
    readonly property color accent: root.ringing || root.finished ? Colors.of(QsWindow.window).danger
        : root.mode === "focus" && Timers.pomoOn && Timers.pomoPhase !== "focus" ? Colors.of(QsWindow.window).success
        : Colors.of(QsWindow.window).focus

    // What a list (laps, alarms) may take: what the slot leaves under the header, the switch and
    // about five card units of dial and controls — never more than four units.
    readonly property real listRoom: Math.max(Tokens.sideCardUnit * 1.5, Math.min(Tokens.sideCardUnit * 4,
        root.maxHeight - root.pad * 2 - head.implicitHeight - tabs.implicitHeight
        - Tokens.sideCardUnit * 7 - col.spacing * 4))

    // A new alarm's time, and the days it repeats on (a weekday bitmask, alarms.js; 0 = once).
    property int newH: 7
    property int newM: 0
    property int newDays: 0
    property bool tuneOpen: false

    // ── Which way the faces slide ─────────────────────────────────────────────
    readonly property var order: ["timer", "stopwatch", "alarm", "focus"]
    property int _lastIdx: 0
    property int slide: 1
    onModeChanged: {
        const i = root.order.indexOf(root.mode)
        root.slide = i >= root._lastIdx ? 1 : -1
        root._lastIdx = i
        root.tuneOpen = false
        // Timer ↔ Focus share one cookie: a ping says "it changed", where the petals would only snap.
        if (root.countdownFace) cdDial.ping()
    }

    // ── What the countdown cookie says ────────────────────────────────────────
    readonly property int remain: Timers.timerRemain
    readonly property bool urgentNow: Timers.timerRunning && root.remain > 0 && root.remain <= 10 && Timers.timerSpan > 10
    readonly property bool dialIdleTimer: root.mode === "timer" && !root.active && !Timers.timerDone
    readonly property string dialText: root.active || Timers.timerDone ? Timers.clockString(root.remain)
        : root.mode === "focus" ? Timers.clockString(Timers.pomoFocus * 60) : Timers.clockString(Timers.timerTotal)
    // Running or paused: what is left of this run. Idle timer: where the dial is turned to (an hour all the way
    // round). Idle focus: a full cookie. Done: a coin.
    readonly property real dialValue: root.active ? (Timers.timerSpan > 0 ? Math.min(1, root.remain / Timers.timerSpan) : 0)
        : Timers.timerDone ? 0
        : root.mode === "focus" ? 1 : Math.min(1, Timers.timerTotal / 3600)
    readonly property string dialCaption: Timers.timerPaused ? "Paused"
        : Timers.timerRunning ? (Timers.pomoOn ? Timers.pomoLabel + " · " + TM.endsAt(Date.now(), root.remain).toLowerCase()
                                               : TM.endsAt(Date.now(), root.remain))
        : Timers.timerDone ? "Time's up"
        : root.mode === "focus" ? "Tap to start focusing" : "Turn to set · tap to start"

    function primary() {
        if (Timers.timerRunning)          Timers.pauseTimer()
        else if (Timers.timerPaused)      Timers.resumeTimer()
        else if (root.mode === "focus")   Timers.startPomodoro()
        else                              Timers.startTimer()
    }

    Connections {
        target: Timers
        // A minute turns over: a ring leaves the rim. The last ten seconds: every second, with a bump.
        function onTimerRemainChanged() {
            if (!Timers.timerRunning) return
            const r = Timers.timerRemain
            if (r > 0 && r <= 10 && Timers.timerSpan > 10) { cdDial.ping(); cdDial.bump() }
            else if (r > 0 && r % 60 === 0) cdDial.ping()
        }
        function onTimerRunningChanged() { if (Timers.timerRunning) cdDial.ping() }
        function onLapsChanged() { if (Timers.laps.length > 0) watchDial.ping() }
    }

    readonly property string subtitle: root.ringing ? "Alarm " + Timers.pad(Timers.ringing.h) + ":" + Timers.pad(Timers.ringing.m)
        : root.mode === "timer"
        ? (Timers.timerDone ? "Finished" : Timers.timerPaused ? "Paused" : Timers.timerRunning ? "Running" : "Turn the cookie, then tap it")
        : root.mode === "stopwatch"
        ? (Timers.swRunning ? "Running" : Timers.swElapsed > 0 ? "Paused" : "Ready")
        : root.mode === "focus"
        ? (Timers.pomoOn ? Timers.pomoLabel + " · session " + Timers.pomoSession + " of " + Timers.pomoEvery
                         : "Work in focused rounds")
        : (Timers.alarms.length === 0 ? "No alarms"
           : Timers.alarms.filter(a => a.enabled).length + " of " + Timers.alarms.length + " on")

    // "in 7 h 12 min" — how far off a moment is.
    function inText(ms) {
        const m = Math.max(0, Math.round(ms / 60000))
        if (m < 1) return "in under a minute"
        const h = Math.floor(m / 60)
        return "in " + (h > 0 ? h + " h " : "") + (m % 60) + " min"
    }
    // The alarm that will ring next (a snooze counts): { at, a } or null.
    readonly property var nextAlarm: {
        let best = null
        for (const a of Timers.alarms) {
            const t = (a.snoozeAt || 0) > 0 ? a.snoozeAt : (a.enabled ? a.at : 0)
            if (t > 0 && (best === null || t < best.at)) best = { at: t, a: a }
        }
        return best
    }

    ColumnLayout {
        id: col
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.pad
        spacing: Tokens.spacingMd

        PanelHeader {
            id: head
            Layout.fillHeight: false
            glyph: root.mode === "alarm" ? "\u{F0020}" : root.mode === "stopwatch" ? "\u{F051B}" : "\u{F051F}"
            title:     root.mode === "alarm" ? "Alarm" : root.mode === "stopwatch" ? "Stop" : root.mode === "focus" ? "Focus" : "Count"
            titleTail: root.mode === "alarm" ? "clock" : root.mode === "stopwatch" ? "watch" : root.mode === "focus" ? "timer" : "down"
            accent:    root.accent
            subtitle:  root.subtitle

            ChipTray {
                ChipButton {
                    symbol: "settings"
                    tint: root.accent
                    onActivated: UiState.openSettingsTo("SidebarPage.qml")
                }
            }
        }

        // ── Something wants you: a ringing alarm, a finished countdown ────────
        // Unrolls from nothing and rolls back up. Whatever face you are on — an alarm that rings while you
        // look at the stopwatch is still ringing.
        Item {
            id: bannerHost
            Layout.fillWidth: true
            Layout.fillHeight: false
            readonly property bool shown: root.ringing || root.finished
            implicitHeight: bannerHost.shown ? banner.implicitHeight : 0
            Behavior on implicitHeight { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
            opacity: bannerHost.shown ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.standard } }
            visible: opacity > 0.01 || implicitHeight > 0.5
            clip: true

            Rectangle {
                id: banner
                width: parent.width
                implicitHeight: bannerCol.implicitHeight + Tokens.spacingMd * 2
                radius: Tokens.radiusCard
                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).danger, 0.14)

                ColumnLayout {
                    id: bannerCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.spacingMd
                    spacing: Tokens.spacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm
                        // The bell rings: a nudge on Motion.pulse (a channel — it keeps saying "ringing" with
                        // animations off).
                        MaterialIcon {
                            id: bell
                            name: "alarm"
                            fill: 1
                            color: Colors.of(QsWindow.window).danger
                            SequentialAnimation on rotation {
                                running: bannerHost.shown
                                loops: Animation.Infinite
                                alwaysRunToEnd: true
                                NumberAnimation { to: 16;  duration: Motion.pulse / 4; easing.type: Motion.ambient }
                                NumberAnimation { to: -16; duration: Motion.pulse / 2; easing.type: Motion.ambient }
                                NumberAnimation { to: 0;   duration: Motion.pulse / 4; easing.type: Motion.ambient }
                                PauseAnimation  { duration: Motion.pulse * 2 }
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            variant: "label"
                            font.weight: Font.DemiBold
                            color: Colors.of(QsWindow.window).danger
                            text: root.ringing ? "Alarm  " + Timers.pad(Timers.ringing.h) + ":" + Timers.pad(Timers.ringing.m)
                                               : "Timer finished"
                        }
                    }
                    ChipTray {
                        Layout.alignment: Qt.AlignLeft
                        ChipButton {
                            visible: root.ringing
                            label: Translation.tr("Snooze 5m")
                            symbol: "schedule"
                            tint: Colors.of(QsWindow.window).danger
                            onActivated: Timers.snoozeAlarm(5)
                        }
                        ChipButton {
                            visible: root.ringing
                            label: "10m"
                            tint: Colors.of(QsWindow.window).danger
                            onActivated: Timers.snoozeAlarm(10)
                        }
                        ChipButton {
                            visible: !root.ringing
                            label: Translation.tr("Again")
                            symbol: "restart_alt"
                            tint: Colors.of(QsWindow.window).danger
                            onActivated: Timers.startTimer()
                        }
                        ChipButton {
                            label: Translation.tr("Dismiss")
                            symbol: "check"
                            on: true
                            tint: Colors.of(QsWindow.window).danger
                            onActivated: root.ringing ? Timers.dismissAlarm() : Timers.stopTimer()
                        }
                    }
                }
            }
        }

        SegmentSwitch {
            id: tabs
            Layout.fillWidth: true
            Layout.fillHeight: false
            accent: root.accent
            current: root.mode
            model: [
                { value: "timer",     label: "Timer",  icon: "hourglass_bottom" },
                { value: "stopwatch", label: "Watch",  icon: "timer" },
                { value: "alarm",     label: "Alarms", icon: "alarm" },
                { value: "focus",     label: "Focus",  icon: "bolt" }
            ]
            onPicked: function (value) { Timers.mode = value }
        }

        // ══ The stage: faces that slide past one another ══════════════════════
        // All four sit in one box (no layout between them, or a crossfade would stack them); the box is as tall
        // as the face you are on. Incoming slides in from the side you moved towards, the outgoing leaves the
        // other way.
        Item {
            id: stage
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: root.mode === "stopwatch" ? watchFace.implicitHeight
                          : root.mode === "alarm"     ? alarmFace.implicitHeight
                          :                             timerFace.implicitHeight

            // ══ Timer and Focus: the cookie ═══════════════════════════════════
            ColumnLayout {
                id: timerFace
                width: stage.width
                spacing: Tokens.spacingMd
                property real shown: root.countdownFace ? 1 : 0
                Behavior on shown { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                opacity: timerFace.shown
                // Not `visible`: a hidden layout's height is stale for a frame when it comes back. Input is off instead.
                enabled: timerFace.shown > 0.5
                transform: Translate { x: (root.countdownFace ? 1 : -1) * (1 - timerFace.shown) * root.slide * Tokens.spacingXl * 2 }

                TimerDial {
                    id: cdDial
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: Tokens.sideCardUnit * 4.1
                    Layout.preferredHeight: Tokens.sideCardUnit * 4.1
                    text: root.dialText
                    caption: root.dialCaption
                    value: root.dialValue
                    orbit: root.active ? Math.max(0, Timers.timerSpan - root.remain) / 60 : 0
                    accent: root.accent
                    running: Timers.timerRunning
                    paused: Timers.timerPaused
                    done: root.finished
                    urgent: root.urgentNow
                    points: root.mode === "focus" ? 7 : 9
                    interactive: root.dialIdleTimer
                    live: timerFace.shown > 0.01
                    onTapped: root.primary()
                    // Whole minutes: sixty to a turn. All the way round is an hour.
                    onTurned: function (f) { Timers.setTimerLength(Math.round(f * 60) * 60) }
                }

                // The focus round as dots: sessions done, the one you are in, the ones to come.
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.mode === "focus"
                    spacing: Tokens.spacingSm
                    Repeater {
                        model: Timers.pomoEvery
                        delegate: Rectangle {
                            id: dot
                            required property int index
                            readonly property bool done: dot.index < (Timers.pomoOn ? Timers.pomoCycle % Timers.pomoEvery : 0)
                            readonly property bool now: Timers.pomoOn && Timers.pomoPhase === "focus"
                                                        && dot.index === Timers.pomoCycle % Timers.pomoEvery
                            width: Tokens.spacingMd
                            height: width
                            radius: width / 2
                            color: dot.done || dot.now ? root.accent : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.16)
                            scale: dot.now ? 1.3 : 1
                            Behavior on scale { SpringAnimation { spring: 5; damping: 0.4; epsilon: 0.005 } }
                            Behavior on color { ColorAnimation { duration: Motion.standard } }
                        }
                    }
                }

                // The thing you do, with what you may do to it either side: they fade in when they can matter.
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd

                    ChipTray {
                        opacity: root.active || Timers.pomoOn ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                        ChipButton {
                            symbol: "stop"
                            tint: root.accent
                            onActivated: Timers.stopTimer()
                        }
                        ChipButton {
                            visible: root.mode === "focus" && Timers.pomoOn
                            symbol: "skip_next"
                            tint: root.accent
                            onActivated: Timers.pomoSkip()
                        }
                    }
                    CookieButton {
                        Layout.preferredWidth: Tokens.iconXl * 2.3
                        Layout.preferredHeight: Tokens.iconXl * 2.3
                        name: Timers.timerRunning ? "pause" : "play_arrow"
                        primary: true
                        tint: root.accent
                        enabled: root.mode === "focus" || Timers.timerTotal > 0 || root.active || Timers.timerDone
                        onActivated: root.primary()
                    }
                    ChipTray {
                        opacity: root.active ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                        ChipButton {
                            label: "+1m"
                            tint: root.accent
                            onActivated: Timers.extendTimer(60)
                        }
                        ChipButton {
                            label: "+5m"
                            tint: root.accent
                            onActivated: Timers.extendTimer(300)
                        }
                    }
                }

                // The usual lengths (one tap starts one), and a way to tune the exact one.
                ChipTray {
                    Layout.alignment: Qt.AlignHCenter
                    opacity: root.dialIdleTimer ? 1 : 0
                    visible: opacity > 0.01 && root.mode === "timer"
                    Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                    Repeater {
                        model: [1, 5, 10, 15, 25, 60]
                        delegate: ChipButton {
                            required property int modelData
                            label: modelData < 60 ? modelData + "m" : "1h"
                            tint: root.accent
                            onActivated: Timers.startTimerFor(modelData * 60)
                        }
                    }
                }
                ChipTray {
                    Layout.alignment: Qt.AlignHCenter
                    opacity: (root.dialIdleTimer || (root.mode === "focus" && !Timers.pomoOn)) ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                    ChipButton {
                        symbol: "tune"
                        label: root.tuneOpen ? "Done" : (root.mode === "focus" ? "Lengths" : "Exact time")
                        on: root.tuneOpen
                        tint: root.accent
                        onActivated: root.tuneOpen = !root.tuneOpen
                    }
                }

                // The exact length: h · m · s for the timer, minutes for the focus cycle. Unrolls.
                Item {
                    id: tuneHost
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    readonly property bool shown: root.tuneOpen && (root.dialIdleTimer || (root.mode === "focus" && !Timers.pomoOn))
                    implicitHeight: tuneHost.shown ? tuneBox.implicitHeight : 0
                    Behavior on implicitHeight { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                    opacity: tuneHost.shown ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                    visible: opacity > 0.01 || implicitHeight > 0.5
                    clip: true

                    Rectangle {
                        id: tuneBox
                        width: parent.width
                        implicitHeight: tuneInner.implicitHeight + Tokens.spacingMd * 2
                        radius: Tokens.radiusCard
                        color: Colors.of(QsWindow.window).section

                        Item {
                            id: tuneInner
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Tokens.spacingMd
                            implicitHeight: Math.max(hms.implicitHeight, minutes.implicitHeight)

                            RowLayout {
                                id: hms
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: root.mode === "timer"
                                spacing: Tokens.spacingSm
                                Repeater {
                                    model: [{ unit: 0, to: 23, tag: "h" }, { unit: 1, to: 59, tag: "m" }, { unit: 2, to: 59, tag: "s" }]
                                    RowLayout {
                                        id: unitRow
                                        required property var modelData
                                        spacing: Tokens.spacingXs
                                        NumberStepper {
                                            from: 0; to: unitRow.modelData.to; step: 1
                                            numberWidth: Tokens.sideCardUnit / 2
                                            value: [Timers.setH, Timers.setM, Timers.setS][unitRow.modelData.unit]
                                            onCommit: function (v) {
                                                Timers.bumpSet(unitRow.modelData.unit, v - Timers.readSet(unitRow.modelData.unit))
                                            }
                                        }
                                        StyledText { text: unitRow.modelData.tag; variant: "caption"; emphasis: "dim" }
                                    }
                                }
                            }
                            GridLayout {
                                id: minutes
                                anchors.left: parent.left
                                anchors.right: parent.right
                                visible: root.mode === "focus"
                                columns: 4
                                columnSpacing: Tokens.spacingSm
                                Repeater {
                                    model: [{ key: "focus", tag: "Focus", min: 1, max: 120, step: 5, get: () => Timers.pomoFocus },
                                            { key: "short", tag: "Break", min: 1, max: 60,  step: 1, get: () => Timers.pomoShort },
                                            { key: "long",  tag: "Long",  min: 1, max: 90,  step: 5, get: () => Timers.pomoLong },
                                            { key: "every", tag: "Every", min: 2, max: 8,   step: 1, get: () => Timers.pomoEvery }]
                                    ColumnLayout {
                                        id: tuneCol
                                        required property var modelData
                                        Layout.alignment: Qt.AlignHCenter
                                        spacing: Tokens.spacingXs
                                        NumberStepper {
                                            Layout.alignment: Qt.AlignHCenter
                                            from: tuneCol.modelData.min; to: tuneCol.modelData.max; step: tuneCol.modelData.step
                                            compact: true
                                            numberWidth: Tokens.sideCardUnit / 2.4
                                            value: tuneCol.modelData.get()
                                            onCommit: function (v) { Timers.setPomo(tuneCol.modelData.key, v) }
                                        }
                                        StyledText {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: tuneCol.modelData.tag
                                            variant: "micro"
                                            emphasis: "dim"
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ══ Stopwatch: a cookie that grows ════════════════════════════════
            ColumnLayout {
                id: watchFace
                width: stage.width
                spacing: Tokens.spacingMd
                property real shown: root.mode === "stopwatch" ? 1 : 0
                Behavior on shown { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                opacity: watchFace.shown
                // Not `visible`: a hidden layout's height is stale for a frame when it comes back. Input is off instead.
                enabled: watchFace.shown > 0.5
                transform: Translate { x: (root.mode === "stopwatch" ? 1 : -1) * (1 - watchFace.shown) * root.slide * Tokens.spacingXl * 2 }

                // Per second, never per tick: Timers updates swElapsed every 50ms, and a cookie re-cut at that
                // rate would never be still. The hundredths are text, which is cheap.
                readonly property int secs: Math.floor(Timers.swElapsed / 1000)
                readonly property var extremes: TM.lapExtremes(Timers.laps)
                readonly property var splits: TM.lapSplits(Timers.laps)
                // The laps with an identity, so a new one is ADDED to the list (and drops in) rather than
                // rebuilding every row.
                readonly property var lapRows: Timers.laps.map((t, i) => ({ id: "L" + (Timers.laps.length - i), index: i, t: t }))

                TimerDial {
                    id: watchDial
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: Tokens.sideCardUnit * 4.1
                    Layout.preferredHeight: Tokens.sideCardUnit * 4.1
                    text: Timers.clockString(watchFace.secs)
                    fine: Timers.pad(Math.floor((Timers.swElapsed % 1000) / 10))
                    caption: Timers.swRunning ? "Running" : Timers.swElapsed > 0 ? "Paused" : "Tap to start"
                    // Grows over each minute and pops back at the next: you can see a minute fill.
                    value: (watchFace.secs % 60) / 60
                    orbit: watchFace.secs / 60
                    accent: root.accent
                    running: Timers.swRunning
                    paused: !Timers.swRunning && Timers.swElapsed > 0
                    points: 11
                    live: watchFace.shown > 0.01
                    onTapped: Timers.swRunning ? Timers.pauseStopwatch() : Timers.startStopwatch()
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd
                    ChipTray {
                        opacity: !Timers.swRunning && Timers.swElapsed > 0 ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                        ChipButton {
                            symbol: "restart_alt"
                            label: Translation.tr("Reset")
                            tint: root.accent
                            onActivated: Timers.resetStopwatch()
                        }
                    }
                    CookieButton {
                        Layout.preferredWidth: Tokens.iconXl * 2.3
                        Layout.preferredHeight: Tokens.iconXl * 2.3
                        name: Timers.swRunning ? "pause" : "play_arrow"
                        primary: true
                        tint: root.accent
                        onActivated: Timers.swRunning ? Timers.pauseStopwatch() : Timers.startStopwatch()
                    }
                    ChipTray {
                        opacity: Timers.swRunning || Timers.laps.length > 0 ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                        ChipButton {
                            visible: Timers.swRunning
                            symbol: "flag"
                            label: Translation.tr("Lap")
                            tint: root.accent
                            onActivated: Timers.lap()
                        }
                        ChipButton {
                            visible: Timers.laps.length > 0
                            symbol: "content_copy"
                            tint: root.accent
                            onActivated: Clipboard.copyText(TM.lapsText(Timers.laps, Timers.lapString))
                        }
                    }
                }

                // The laps: newest first; each drops in; the fastest and slowest are marked once there are two.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: Timers.laps.length > 0
                    implicitHeight: Math.min(lapList.contentHeight, root.listRoom) + Tokens.spacingMd * 2
                    radius: Tokens.radiusCard
                    color: Colors.of(QsWindow.window).section

                    ListView {
                        id: lapList
                        anchors.fill: parent
                        anchors.margins: Tokens.spacingMd
                        clip: true
                        interactive: contentHeight > height
                        spacing: Tokens.spacingXs
                        model: ScriptModel { values: watchFace.lapRows; objectProp: "id" }
                        add: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.standard }
                                NumberAnimation { property: "scale"; from: 0.8; to: 1; duration: Motion.spatial; easing.type: Motion.overshoot }
                            }
                        }
                        displaced: Transition { NumberAnimation { properties: "y"; duration: Motion.spatial; easing.type: Motion.travel } }
                        delegate: RowLayout {
                            id: lapRow
                            required property var modelData
                            readonly property int idx: lapRow.modelData.index
                            readonly property bool best: watchFace.extremes.best === lapRow.idx
                            readonly property bool worst: watchFace.extremes.worst === lapRow.idx
                            width: lapList.width
                            spacing: Tokens.spacingSm
                            StyledText {
                                text: "Lap " + (Timers.laps.length - lapRow.idx)
                                variant: "label"
                                emphasis: "muted"
                            }
                            MaterialIcon {
                                visible: lapRow.best || lapRow.worst
                                name: lapRow.best ? "bolt" : "hourglass_empty"
                                variant: "caption"
                                color: lapRow.best ? Colors.of(QsWindow.window).success : Colors.of(QsWindow.window).danger
                            }
                            Item { Layout.fillWidth: true }
                            StyledText {
                                // The split since the lap before it.
                                text: "+" + Timers.lapString(watchFace.splits[lapRow.idx] ?? lapRow.modelData.t)
                                variant: "label"
                                font.family: Tokens.fontMono
                                color: lapRow.best ? Colors.of(QsWindow.window).success
                                     : lapRow.worst ? Colors.of(QsWindow.window).danger
                                     : Colors.of(QsWindow.window).fgDim
                            }
                            StyledText {
                                text: Timers.lapString(lapRow.modelData.t)
                                variant: "label"
                                font.family: Tokens.fontMono
                            }
                        }
                    }
                }
            }

            // ══ Alarms ════════════════════════════════════════════════════════
            ColumnLayout {
                id: alarmFace
                width: stage.width
                spacing: Tokens.spacingMd
                property real shown: root.mode === "alarm" ? 1 : 0
                Behavior on shown { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                opacity: alarmFace.shown
                // Not `visible`: a hidden layout's height is stale for a frame when it comes back. Input is off instead.
                enabled: alarmFace.shown > 0.5
                transform: Translate { x: (root.mode === "alarm" ? 1 : -1) * (1 - alarmFace.shown) * root.slide * Tokens.spacingXl * 2 }

                // The next one, and how long: the first thing you want to know.
                StyledText {
                    Layout.fillWidth: true
                    text: root.nextAlarm
                          ? "Next  " + Qt.formatDateTime(new Date(root.nextAlarm.at), "ddd HH:mm") + "  ·  " + root.inText(root.nextAlarm.at - root.nowMs)
                          : Timers.alarms.length > 0 ? "All alarms are off" : "No alarms — set one below"
                    variant: "label"
                    font.weight: Font.DemiBold
                    color: root.nextAlarm ? root.accent : Colors.of(QsWindow.window).fgDim
                    elide: Text.ElideRight
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: Timers.alarms.length > 0
                    implicitHeight: Math.min(alarmList.contentHeight, root.listRoom) + Tokens.spacingSm * 2
                    radius: Tokens.radiusCard
                    color: Colors.of(QsWindow.window).section

                    ListView {
                        id: alarmList
                        anchors.fill: parent
                        anchors.margins: Tokens.spacingSm
                        clip: true
                        interactive: contentHeight > height
                        spacing: Tokens.spacingXs
                        model: ScriptModel {
                            values: Timers.alarms
                            objectProp: "id"
                        }
                        add: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.standard }
                                NumberAnimation { property: "scale"; from: 0.85; to: 1; duration: Motion.spatial; easing.type: Motion.overshoot }
                            }
                        }
                        remove: Transition {
                            ParallelAnimation {
                                NumberAnimation { property: "opacity"; to: 0; duration: Motion.exit }
                                NumberAnimation { property: "scale"; to: 0.85; duration: Motion.exit }
                            }
                        }
                        displaced: Transition { NumberAnimation { properties: "y"; duration: Motion.spatial; easing.type: Motion.travel } }
                        delegate: RowLayout {
                            id: alarmRow
                            required property var modelData
                            width: alarmList.width
                            spacing: Tokens.spacingMd

                            // Its own small clock, hands and all: dimmed when it is off.
                            ClockFace {
                                Layout.leftMargin: Tokens.spacingSm
                                Layout.preferredWidth: Tokens.iconXl + Tokens.spacingSm
                                Layout.preferredHeight: Layout.preferredWidth
                                hours: alarmRow.modelData.h
                                minutes: alarmRow.modelData.m
                                accent: root.accent
                                tone: alarmRow.modelData.h >= 6 && alarmRow.modelData.h < 18 ? "day" : "night"
                                opacity: alarmRow.modelData.enabled ? 1 : 0.4
                                Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    text: Timers.pad(alarmRow.modelData.h) + ":" + Timers.pad(alarmRow.modelData.m)
                                    variant: "title"
                                    font.family: Tokens.fontMono
                                    font.weight: Font.DemiBold
                                    emphasis: alarmRow.modelData.enabled ? "normal" : "dim"
                                }
                                // How it repeats — a click goes to the next of Once / Weekdays / Every day / Weekends.
                                // A snoozed alarm says when it will ring again.
                                StyledText {
                                    text: (alarmRow.modelData.snoozeAt || 0) > 0
                                          ? "Snoozed until " + Qt.formatTime(new Date(alarmRow.modelData.snoozeAt), "hh:mm")
                                          : AL.repeatLabel(alarmRow.modelData.days || 0)
                                    variant: "caption"
                                    color: alarmRow.modelData.enabled || (alarmRow.modelData.snoozeAt || 0) > 0 ? root.accent : Colors.of(QsWindow.window).fgDim
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -Tokens.spacingXs
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Timers.setAlarmDays(alarmRow.modelData.id, AL.nextPreset(alarmRow.modelData.days || 0))
                                    }
                                }
                            }
                            Toggle {
                                checked: alarmRow.modelData.enabled
                                onToggled: Timers.toggleAlarm(alarmRow.modelData.id)
                            }
                            ChipTray {
                                ChipButton {
                                    symbol: "delete"
                                    tint: Colors.of(QsWindow.window).danger
                                    onActivated: Timers.removeAlarm(alarmRow.modelData.id)
                                }
                            }
                        }
                    }
                }

                // A new one: a scalloped clock that shows the time you are setting (its hands glide as you change
                // it), the time, the days, Add.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    implicitHeight: newRow.implicitHeight + Tokens.spacingMd * 2
                    radius: Tokens.radiusCard
                    color: Colors.of(QsWindow.window).section

                    RowLayout {
                        id: newRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.spacingMd
                        spacing: Tokens.spacingMd

                        ClockFace {
                            Layout.preferredWidth: Tokens.sideCardUnit * 2
                            Layout.preferredHeight: Tokens.sideCardUnit * 2
                            Layout.alignment: Qt.AlignVCenter
                            scalloped: true
                            hours: root.newH
                            minutes: root.newM
                            accent: root.accent
                            tone: root.newH >= 6 && root.newH < 18 ? "day" : "night"
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingSm

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                spacing: Tokens.spacingXs
                                NumberStepper {
                                    from: 0; to: 23; step: 1
                                    compact: true
                                    numberWidth: Tokens.sideCardUnit / 2.4
                                    value: root.newH
                                    onCommit: function (v) { root.newH = v }
                                }
                                StyledText { text: ":"; variant: "title" }
                                NumberStepper {
                                    from: 0; to: 55; step: 5
                                    compact: true
                                    numberWidth: Tokens.sideCardUnit / 2.4
                                    value: root.newM
                                    onCommit: function (v) { root.newM = v }
                                }
                                Item { Layout.fillWidth: true }
                                ChipTray {
                                    ChipButton {
                                        symbol: "alarm_add"
                                        label: Translation.tr("Add")
                                        on: true
                                        tint: root.accent
                                        onActivated: { Timers.addAlarm(root.newH, root.newM, root.newDays); root.newDays = 0 }
                                    }
                                }
                            }
                            // Which days it repeats on; none means once. Monday first.
                            ChipTray {
                                Repeater {
                                    model: [{ d: 1, t: "M" }, { d: 2, t: "T" }, { d: 3, t: "W" }, { d: 4, t: "T" },
                                            { d: 5, t: "F" }, { d: 6, t: "S" }, { d: 0, t: "S" }]
                                    delegate: ChipButton {
                                        required property var modelData
                                        label: modelData.t
                                        on: ((root.newDays >> modelData.d) & 1) === 1
                                        tint: root.accent
                                        onActivated: root.newDays = root.newDays ^ (1 << modelData.d)
                                    }
                                }
                            }
                            StyledText {
                                text: AL.repeatLabel(root.newDays)
                                variant: "micro"
                                emphasis: "dim"
                            }
                        }
                    }
                }
            }
        }
    }
}
