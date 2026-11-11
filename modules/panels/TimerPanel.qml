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
// button (SidePanelDock). In the shell's Material 3 Expressive panel shape: one `PanelHero` per face
// (the time as its headline, the one big button on its right, the small controls in its footer) and
// tonal `PanelRow`s for what is listed (laps, alarms).
//
// Four faces on a SegmentSwitch — Timers.mode, persisted, so it reopens where you left it, and the
// button's middle-click acts on the same face.
//
//   Timer      the length as a headline, the usual lengths under it (one tap starts one), "Exact time"
//              for h · m · s; while running: pause / resume, stop, +1 / +5 min, "Ends 14:32"
//   Stopwatch  time and hundredths, lap / reset / copy, a row per lap with the fastest one lit
//   Alarms     the next one as the hero, a row per alarm (tap to switch it, repeat days, delete), a new one
//   Focus      a Pomodoro cycle on the same hero: focus, short break, a long one every N sessions
//
// Something ringing or finished is a second hero on top, on whatever face you are looking at.
// Everything real is services/Timers (state, ticking, notifications, persistence) and services/timers.js
// (the cycle and the lap maths, tested: `bun scripts/test-timers.js`); this shows it and calls it.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The room the slot has (SidePanelDock sets it); the laps and alarms scroll past it.
    property real maxHeight: Infinity

    readonly property int pad: Tokens.spacingXl
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

    // The panel's one accent: the shell's; the danger colour while something wants you; a break is calm.
    readonly property color accent: root.ringing || root.finished ? Colors.of(QsWindow.window).danger
        : root.mode === "focus" && Timers.pomoOn && Timers.pomoPhase !== "focus" ? Colors.of(QsWindow.window).success
        : Colors.of(QsWindow.window).primary

    // What a list (laps, alarms) may take: what the slot leaves under the header, the switch and a hero
    // — never more than four card units.
    readonly property real listRoom: Math.max(Tokens.sideCardUnit * 1.5, Math.min(Tokens.sideCardUnit * 4,
        root.maxHeight - root.pad * 2 - (head.visible ? head.implicitHeight : 0) - tabs.implicitHeight
        - Tokens.sideCardUnit * 3 - col.spacing * 4))

    // A new alarm's time, and the days it repeats on (a weekday bitmask, alarms.js; 0 = once).
    property int newH: 7
    property int newM: 0
    property int newDays: 0
    property bool tuneOpen: false
    onModeChanged: root.tuneOpen = false

    // ── What the countdown hero says ──────────────────────────────────────────
    readonly property int remain: Timers.timerRemain
    readonly property bool idleTimer: root.mode === "timer" && !root.active && !Timers.timerDone
    readonly property bool idleFocus: root.mode === "focus" && !Timers.pomoOn
    readonly property string countText: root.active || Timers.timerDone ? Timers.clockString(root.remain)
        : root.mode === "focus" ? Timers.clockString(Timers.pomoFocus * 60) : Timers.clockString(Timers.timerTotal)
    // Running or paused: what is left of this run. Idle: a full bar would claim a run, so none.
    readonly property real countValue: root.active && Timers.timerSpan > 0 ? Math.min(1, root.remain / Timers.timerSpan) : 0
    readonly property string countLine: Timers.timerPaused ? Translation.tr("Paused")
        : Timers.timerRunning ? (Timers.pomoOn ? Timers.pomoLabel + " · " + Translation.tr("session %1 of %2").arg(Timers.pomoSession).arg(Timers.pomoEvery)
                                               : Translation.tr("Ends %1").arg(TM.endsAt(Date.now(), root.remain)))
        : Timers.timerDone ? Translation.tr("Time's up")
        : root.mode === "focus" ? Translation.tr("Work in focused rounds") : Translation.tr("Pick a length or start this one")

    function primary() {
        if (Timers.timerRunning)          Timers.pauseTimer()
        else if (Timers.timerPaused)      Timers.resumeTimer()
        else if (root.mode === "focus")   Timers.startPomodoro()
        else                              Timers.startTimer()
    }

    readonly property string subtitle: root.ringing ? Translation.tr("Alarm") + " " + Timers.pad(Timers.ringing.h) + ":" + Timers.pad(Timers.ringing.m)
        : root.mode === "timer"
        ? (Timers.timerDone ? Translation.tr("Finished") : Timers.timerPaused ? Translation.tr("Paused") : Timers.timerRunning ? Translation.tr("Running") : Translation.tr("Ready"))
        : root.mode === "stopwatch"
        ? (Timers.swRunning ? Translation.tr("Running") : Timers.swElapsed > 0 ? Translation.tr("Paused") : Translation.tr("Ready"))
        : root.mode === "focus"
        ? (Timers.pomoOn ? Timers.pomoLabel : Translation.tr("Ready"))
        : (Timers.alarms.length === 0 ? Translation.tr("No alarms")
           : Translation.tr("%1 of %2 on").arg(Timers.alarms.filter(a => a.enabled).length).arg(Timers.alarms.length))

    // "in 7 h 12 min" — how far off a moment is.
    function inText(ms) {
        const m = Math.max(0, Math.round(ms / 60000))
        if (m < 1) return Translation.tr("in under a minute")
        const h = Math.floor(m / 60)
        return Translation.tr("in %1").arg((h > 0 ? h + " h " : "") + (m % 60) + " min")
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
        spacing: Tokens.spacingSm

        PanelHeader {
            id: head
            Layout.fillHeight: false
            visible: Config.panelHeader("timer")
            symbol:    root.mode === "alarm" ? "alarm" : root.mode === "stopwatch" ? "timer" : "hourglass_bottom"
            title:     root.mode === "alarm" ? Translation.tr("Alarm") : root.mode === "stopwatch" ? Translation.tr("Stop") : root.mode === "focus" ? Translation.tr("Focus") : Translation.tr("Count")
            titleTail: root.mode === "alarm" ? Translation.tr("clock") : root.mode === "stopwatch" ? Translation.tr("watch") : root.mode === "focus" ? Translation.tr("timer") : Translation.tr("down")
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
        // Whatever face you are on — an alarm that rings while you look at the stopwatch is still ringing.
        PanelHero {
            id: alert
            visible: root.ringing || root.finished
            active: true
            warn: true
            compact: true
            symbol: "alarm"
            title: root.ringing ? Translation.tr("Alarm") + " " + Timers.pad(Timers.ringing.h) + ":" + Timers.pad(Timers.ringing.m)
                                : Translation.tr("Timer finished")
            line: root.ringing ? Translation.tr("Ringing until you dismiss it") : root.countText

            PanelButton {
                visible: root.ringing
                capsule: true
                symbol: "snooze"
                label: Translation.tr("Snooze 5m")
                onActivated: Timers.snoozeAlarm(5)
            }
            PanelButton {
                visible: !root.ringing
                capsule: true
                symbol: "restart_alt"
                label: Translation.tr("Again")
                onActivated: Timers.startTimer()
            }
            PanelButton {
                capsule: true
                variant: "primary"
                symbol: "check"
                label: Translation.tr("Dismiss")
                onActivated: root.ringing ? Timers.dismissAlarm() : Timers.stopTimer()
            }
        }

        SegmentSwitch {
            id: tabs
            Layout.fillWidth: true
            Layout.fillHeight: false
            accent: root.accent
            current: root.mode
            model: [
                { value: "timer",     label: Translation.tr("Timer"),  icon: "hourglass_bottom" },
                { value: "stopwatch", label: Translation.tr("Watch"),  icon: "timer" },
                { value: "alarm",     label: Translation.tr("Alarms"), icon: "alarm" },
                { value: "focus",     label: Translation.tr("Focus"),  icon: "bolt" }
            ]
            onPicked: function (value) { Timers.mode = value }
        }

        // ══ Timer and Focus ═══════════════════════════════════════════════════
        PanelHero {
            id: cd
            visible: root.countdownFace
            active: root.active || Timers.pomoOn
            turning: Timers.timerRunning
            accent: root.accent
            shape: root.mode === "focus" ? "cookie7" : "cookie9"
            symbol: root.mode === "focus" ? "bolt" : "hourglass_bottom"
            titleVariant: "display"
            title: root.countText
            line: root.countLine

            PanelButton {
                visible: root.idleTimer || root.idleFocus
                symbol: "tune"
                label: root.tuneOpen ? Translation.tr("Done") : ""
                variant: root.tuneOpen ? "primary" : "ghost"
                capsule: true
                accent: root.accent
                onActivated: root.tuneOpen = !root.tuneOpen
            }
            PanelButton {
                capsule: true
                variant: "primary"
                accent: root.accent
                symbol: Timers.timerRunning ? "pause" : "play_arrow"
                symbolFill: 1
                label: Timers.timerRunning ? Translation.tr("Pause") : Timers.timerPaused ? Translation.tr("Resume") : Translation.tr("Start")
                enabled: root.mode === "focus" || Timers.timerTotal > 0 || root.active || Timers.timerDone
                onActivated: root.primary()
            }

            footer: ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                Meter {
                    Layout.fillWidth: true
                    visible: root.active
                    value: root.countValue
                    accent: cd.ink
                }

                // The focus round as dots: sessions done, the one you are in, the ones to come.
                Row {
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
                            color: dot.done || dot.now ? cd.ink : Colors.of(QsWindow.window).alpha(cd.ink, 0.22)
                            scale: dot.now ? 1.3 : 1
                            Behavior on scale { NumberAnimation { duration: Motion.standard; easing.type: Motion.overshoot } }
                            Behavior on color { ColorAnimation { duration: Motion.standard } }
                        }
                    }
                }

                // The usual lengths: one tap starts one.
                ChipTray {
                    visible: root.idleTimer
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

                // What you may do to a run.
                ChipTray {
                    visible: root.active || Timers.pomoOn
                    ChipButton {
                        symbol: "stop"
                        label: Translation.tr("Stop")
                        tint: root.accent
                        onActivated: Timers.stopTimer()
                    }
                    ChipButton {
                        visible: root.mode === "focus" && Timers.pomoOn
                        symbol: "skip_next"
                        label: Translation.tr("Skip")
                        tint: root.accent
                        onActivated: Timers.pomoSkip()
                    }
                    ChipButton {
                        visible: root.active
                        label: "+1m"
                        tint: root.accent
                        onActivated: Timers.extendTimer(60)
                    }
                    ChipButton {
                        visible: root.active
                        label: "+5m"
                        tint: root.accent
                        onActivated: Timers.extendTimer(300)
                    }
                }
            }
        }

        // The exact length: h · m · s for the timer, minutes for the focus cycle.
        Rectangle {
            id: tuneBox
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.countdownFace && root.tuneOpen && (root.idleTimer || root.idleFocus)
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
                        model: [{ key: "focus", tag: Translation.tr("Focus"), min: 1, max: 120, step: 5, get: () => Timers.pomoFocus },
                                { key: "short", tag: Translation.tr("Break"), min: 1, max: 60,  step: 1, get: () => Timers.pomoShort },
                                { key: "long",  tag: Translation.tr("Long"),  min: 1, max: 90,  step: 5, get: () => Timers.pomoLong },
                                { key: "every", tag: Translation.tr("Every"), min: 2, max: 8,   step: 1, get: () => Timers.pomoEvery }]
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

        // ══ Stopwatch ═════════════════════════════════════════════════════════
        PanelHero {
            id: sw
            visible: root.mode === "stopwatch"
            active: Timers.swRunning
            turning: Timers.swRunning
            accent: root.accent
            shape: "cookie11"
            symbol: "timer"
            titleVariant: "display"
            // Seconds as the headline's clock, hundredths after it (text is cheap at the 50 ms tick).
            title: Timers.clockString(Math.floor(Timers.swElapsed / 1000)) + "." + Timers.pad(Math.floor((Timers.swElapsed % 1000) / 10))
            line: Timers.swRunning ? Translation.tr("Running") : Timers.swElapsed > 0 ? Translation.tr("Paused") : Translation.tr("Press start")

            PanelButton {
                capsule: true
                variant: "primary"
                accent: root.accent
                symbol: Timers.swRunning ? "pause" : "play_arrow"
                symbolFill: 1
                label: Timers.swRunning ? Translation.tr("Pause") : Timers.swElapsed > 0 ? Translation.tr("Resume") : Translation.tr("Start")
                onActivated: Timers.swRunning ? Timers.pauseStopwatch() : Timers.startStopwatch()
            }

            footer: ChipTray {
                ChipButton {
                    enabled: Timers.swRunning
                    symbol: "flag"
                    label: Translation.tr("Lap")
                    tint: root.accent
                    onActivated: Timers.lap()
                }
                ChipButton {
                    enabled: !Timers.swRunning && Timers.swElapsed > 0
                    symbol: "restart_alt"
                    label: Translation.tr("Reset")
                    tint: root.accent
                    onActivated: Timers.resetStopwatch()
                }
                ChipButton {
                    visible: Timers.laps.length > 0
                    symbol: "content_copy"
                    label: Translation.tr("Copy")
                    tint: root.accent
                    onActivated: Clipboard.copyText(TM.lapsText(Timers.laps, Timers.lapString))
                }
            }
        }

        // The laps: newest first; the fastest is lit and the slowest marked once there are two.
        ListView {
            id: lapList
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Math.min(lapList.contentHeight, root.listRoom)
            visible: root.mode === "stopwatch" && Timers.laps.length > 0
            clip: true
            interactive: lapList.contentHeight > lapList.height
            boundsBehavior: Flickable.StopAtBounds
            spacing: Tokens.spacingXs

            readonly property var extremes: TM.lapExtremes(Timers.laps)
            readonly property var splits: TM.lapSplits(Timers.laps)
            // The laps with an identity, so a new one is ADDED to the list rather than rebuilding every row.
            readonly property var lapRows: Timers.laps.map((t, i) => ({ id: "L" + (Timers.laps.length - i), index: i, t: t }))

            model: ScriptModel { values: lapList.lapRows; objectProp: "id" }
            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.standard }
            }
            displaced: Transition { NumberAnimation { properties: "y"; duration: Motion.spatial; easing.type: Motion.travel } }

            delegate: PanelRow {
                id: lapRow
                required property var modelData
                readonly property int idx: lapRow.modelData.index
                width: lapList.width
                height: lapRow.implicitHeight
                pad: Tokens.spacingMd
                badge: false
                accent: root.accent
                active: lapList.extremes.best === lapRow.idx && Timers.laps.length > 1
                title: Translation.tr("Lap") + " " + (Timers.laps.length - lapRow.idx)
                // The split since the lap before it.
                subtitle: "+" + Timers.lapString(lapList.splits[lapRow.idx] ?? lapRow.modelData.t)

                MaterialIcon {
                    visible: lapList.extremes.worst === lapRow.idx && Timers.laps.length > 1
                    name: "hourglass_empty"
                    variant: "caption"
                    color: Colors.of(QsWindow.window).danger
                }
                StyledText {
                    text: Timers.lapString(lapRow.modelData.t)
                    variant: "label"
                    font.family: Tokens.fontMono
                    color: lapRow.ink
                }
            }
        }

        // ══ Alarms ════════════════════════════════════════════════════════════
        PanelHero {
            id: next
            visible: root.mode === "alarm"
            active: root.nextAlarm !== null
            turning: false
            accent: root.accent
            shape: "sunny"
            symbol: "alarm"
            offSymbol: "alarm_off"
            titleVariant: "display"
            title: root.nextAlarm ? Qt.formatDateTime(new Date(root.nextAlarm.at), "HH:mm") : Translation.tr("No alarm")
            line: root.nextAlarm ? Qt.formatDateTime(new Date(root.nextAlarm.at), "dddd") + " · " + root.inText(root.nextAlarm.at - root.nowMs)
                : Timers.alarms.length > 0 ? Translation.tr("All alarms are off") : Translation.tr("Set one below")
        }

        ListView {
            id: alarmList
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Math.min(alarmList.contentHeight, root.listRoom)
            visible: root.mode === "alarm" && Timers.alarms.length > 0
            clip: true
            interactive: alarmList.contentHeight > alarmList.height
            boundsBehavior: Flickable.StopAtBounds
            spacing: Tokens.spacingXs

            model: ScriptModel { values: Timers.alarms; objectProp: "id" }
            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.standard }
            }
            remove: Transition {
                NumberAnimation { property: "opacity"; to: 0; duration: Motion.exit }
            }
            displaced: Transition { NumberAnimation { properties: "y"; duration: Motion.spatial; easing.type: Motion.travel } }

            // The whole row switches the alarm on or off; the chips beside it change how it repeats and remove it.
            delegate: PanelRow {
                id: alarmRow
                required property var modelData
                readonly property bool snoozed: (alarmRow.modelData.snoozeAt || 0) > 0
                width: alarmList.width
                height: alarmRow.implicitHeight
                accent: root.accent
                symbol: "alarm"
                active: alarmRow.modelData.enabled
                clickable: true
                title: Timers.pad(alarmRow.modelData.h) + ":" + Timers.pad(alarmRow.modelData.m)
                subtitle: alarmRow.snoozed ? Translation.tr("Snoozed until %1").arg(Qt.formatTime(new Date(alarmRow.modelData.snoozeAt), "hh:mm"))
                                           : AL.repeatLabel(alarmRow.modelData.days || 0)
                onActivated: Timers.toggleAlarm(alarmRow.modelData.id)

                ChipTray {
                    ChipButton {
                        symbol: "repeat"
                        tint: root.accent
                        // Once → Weekdays → Every day → Weekends.
                        onActivated: Timers.setAlarmDays(alarmRow.modelData.id, AL.nextPreset(alarmRow.modelData.days || 0))
                    }
                    ChipButton {
                        symbol: "delete"
                        tint: Colors.of(QsWindow.window).danger
                        onActivated: Timers.removeAlarm(alarmRow.modelData.id)
                    }
                }
            }
        }

        // A new one: the time, the days it repeats on, Add.
        PanelRow {
            id: newAlarm
            visible: root.mode === "alarm"
            accent: root.accent
            symbol: "alarm_add"
            title: Translation.tr("New alarm")
            subtitle: AL.repeatLabel(root.newDays)

            PanelButton {
                capsule: true
                variant: "primary"
                accent: root.accent
                symbol: "add"
                label: Translation.tr("Add")
                onActivated: { Timers.addAlarm(root.newH, root.newM, root.newDays); root.newDays = 0 }
            }

            below: [
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
                }
            ]
        }
    }
}
