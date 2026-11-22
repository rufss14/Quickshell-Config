pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/alarms.js" as AL
import "../../services/timers.js" as TM

// ── IslandTimer ───────────────────────────────────────────────────────────────
// The timer as a dashboard on an island (2026-11-15, the user: "be like a dashboard instead of lots of tabs"): the
// four faces the sidebar's TimerPanel puts on a switch are all on one page, each a card.
//
//   left    the loud card: the countdown (the time, Ends 14:32, the bar, the usual lengths, Start / Pause, a
//           minute or five more, stop, and the exact length as h · m · s while idle). A ringing alarm or a
//           finished countdown takes the card over with Snooze / Dismiss, whatever else is going on.
//   right   Stopwatch beside Focus (the Pomodoro rounds, which run on the countdown: the loud card shows the
//           round while they do), and under both the alarms: the next one, each with its switch, repeat and
//           remove under the pointer, and a new one (the time, the days, Add).
//
// Everything real is services/Timers (+ timers.js, alarms.js); this shows it and calls it. The sidebar and the
// islands-off column keep TimerPanel.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property int sideW: Tokens.spacingXl * 14 + Tokens.spacingSm

    // ── The countdown ─────────────────────────────────────────────────────────
    readonly property bool live: Timers.timerRunning || Timers.timerPaused
    readonly property bool ringing: Timers.ringing !== null
    readonly property int remain: Timers.timerRemain
    readonly property string countText: root.live || Timers.timerDone ? Timers.clockString(root.remain)
                                                                      : Timers.clockString(Timers.timerTotal)
    readonly property string countLine: Timers.timerPaused ? Translation.tr("Paused")
        : Timers.timerRunning ? (Timers.pomoOn ? Translation.tr("%1 · round %2 of %3").arg(Translation.tr(Timers.pomoLabel)).arg(Timers.pomoSession).arg(Timers.pomoEvery)
                                               : Translation.tr("Ends %1").arg(TM.endsAt(Date.now(), root.remain)))
        : Timers.timerDone ? Translation.tr("Time's up")
        : Translation.tr("Pick a length or set one")
    function primary() {
        if (Timers.timerRunning)     Timers.pauseTimer()
        else if (Timers.timerPaused) Timers.resumeTimer()
        else                         Timers.startTimer()
    }

    // ── Alarms ────────────────────────────────────────────────────────────────
    property int newH: 7
    property int newM: 0
    property int newDays: 0
    function inText(ms) {
        const m = Math.max(0, Math.round(ms / 60000))
        if (m < 1) return Translation.tr("in under a minute")
        const h = Math.floor(m / 60)
        return h > 0 ? Translation.tr("in %1 h %2 min").arg(h).arg(m % 60) : Translation.tr("in %1 min").arg(m)
    }
    readonly property var nextAlarm: {
        let best = null
        for (const a of Timers.alarms) {
            const t = (a.snoozeAt || 0) > 0 ? a.snoozeAt : (a.enabled ? a.at : 0)
            if (t > 0 && (best === null || t < best.at)) best = { at: t, a: a }
        }
        return best
    }

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        // ══ The countdown, loud ═══════════════════════════════════════════════
        IslandPlate {
            id: hero
            Layout.fillWidth: false
            Layout.preferredWidth: root.sideW
            Layout.minimumWidth: root.sideW
            Layout.fillHeight: true
            hero: true
            order: 0
            radius: Tokens.radiusXl

            // ── Something wants you ────────────────────────────────────────────
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingLg
                spacing: Tokens.spacingSm
                visible: root.ringing || Timers.timerDone

                IslandBadge {
                    filled: true
                    size: Tokens.iconXl * 2
                    symbol: root.ringing ? "notifications_active" : "alarm"
                    shape: "burst"
                }
                Item { Layout.fillHeight: true }
                StyledText {
                    Layout.fillWidth: true
                    text: root.ringing ? Timers.pad(Timers.ringing.h) + ":" + Timers.pad(Timers.ringing.m) : Translation.tr("Time's up")
                    font.pixelSize: Tokens.fontDisplay * 2
                    font.weight: Font.Bold
                    font.features: ({ tnum: 1 })
                    color: hero.ink
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.ringing ? Translation.tr("Alarm") : Translation.tr("The countdown has finished")
                    variant: "caption"
                    color: hero.inkDim
                }
                Item { Layout.fillHeight: true }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    ChipButton {
                        visible: root.ringing
                        symbol: "snooze"
                        label: Translation.tr("5 min")
                        tonal: true
                        tint: hero.ink
                        Accessible.name: Translation.tr("Snooze for 5 minutes")
                        onActivated: Timers.snoozeAlarm(5)
                    }
                    ChipButton {
                        visible: !root.ringing
                        symbol: "restart_alt"
                        label: Translation.tr("Again")
                        tonal: true
                        tint: hero.ink
                        onActivated: Timers.startTimer()
                    }
                    Item { Layout.fillWidth: true }
                    ChipButton {
                        solid: true
                        symbol: "close"
                        label: Translation.tr("Dismiss")
                        onActivated: root.ringing ? Timers.dismissAlarm() : Timers.stopTimer()
                    }
                }
            }

            // ── The countdown ──────────────────────────────────────────────────
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingLg
                spacing: Tokens.spacingSm
                visible: !root.ringing && !Timers.timerDone

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd
                    IslandBadge {
                        filled: true
                        symbol: Timers.pomoOn ? "timer" : "hourglass_bottom"
                        shape: Timers.timerRunning ? "cookie9" : Timers.timerPaused ? "squircle" : "circle"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Timers.pomoOn ? Translation.tr("Focus") : Translation.tr("Countdown")
                        variant: "title"
                        font.weight: Font.DemiBold
                        color: hero.ink
                    }
                    ChipButton {
                        visible: root.live
                        symbol: "stop"
                        tint: hero.ink
                        Accessible.name: Translation.tr("Stop")
                        onActivated: Timers.stopTimer()
                    }
                }

                Item { Layout.fillHeight: true; Layout.fillWidth: true }

                StyledText {
                    Layout.fillWidth: true
                    text: root.countText
                    font.pixelSize: Tokens.fontDisplay * 2
                    font.weight: Font.Bold
                    font.features: ({ tnum: 1 })
                    color: hero.ink
                    fontSizeMode: Text.HorizontalFit
                    minimumPixelSize: Tokens.fontDisplay
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.countLine
                    variant: "caption"
                    color: hero.inkDim
                    elide: Text.ElideRight
                }
                Meter {
                    Layout.fillWidth: true
                    visible: root.live
                    value: Timers.timerSpan > 0 ? Math.min(1, root.remain / Timers.timerSpan) : 0
                    accent: hero.ink
                }
                // The exact length, while idle: hours and minutes (seconds stay as they were set).
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: !root.live
                    spacing: Tokens.spacingXs
                    Repeater {
                        model: [{ unit: 0, to: 23, tag: " h" }, { unit: 1, to: 59, tag: " min" }]
                        delegate: NumberStepper {
                            required property var modelData
                            from: 0; to: modelData.to; step: 1
                            compact: true
                            numberWidth: Tokens.iconXl + Tokens.spacingLg
                            value: [Timers.setH, Timers.setM, Timers.setS][modelData.unit]
                            readout: String(value) + modelData.tag
                            onCommit: function (v) { Timers.bumpSet(modelData.unit, v - Timers.readSet(modelData.unit)) }
                        }
                    }
                }

                Item { Layout.fillHeight: true; Layout.fillWidth: true }

                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingXs
                    Repeater {
                        model: root.live ? [1, 5] : [1, 5, 10, 15, 25, 60]
                        delegate: ChipButton {
                            required property int modelData
                            tonal: true
                            tint: hero.ink
                            label: root.live ? "+" + modelData : Translation.tr("%1 min").arg(modelData)
                            Accessible.name: root.live ? Translation.tr("%1 minutes more").arg(modelData) : Translation.tr("Start %1 minutes").arg(modelData)
                            onActivated: root.live ? Timers.extendTimer(modelData * 60) : Timers.startTimerFor(modelData * 60)
                        }
                    }
                }
                ChipButton {
                    Layout.fillWidth: true
                    solid: true
                    symbol: Timers.timerRunning ? "pause" : "play_arrow"
                    label: Timers.timerRunning ? Translation.tr("Pause") : Timers.timerPaused ? Translation.tr("Resume") : Translation.tr("Start")
                    enabled: root.live || Timers.timerTotal > 0
                    onActivated: root.primary()
                }
            }
        }

        // ══ Right: stopwatch and focus, then alarms ═══════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingMd

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: Tokens.spacingXl * 9
                spacing: Tokens.spacingMd

                // ── Stopwatch ──────────────────────────────────────────────────
                IslandPlate {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    order: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.spacingMd
                        spacing: Tokens.spacingXs

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingSm
                            IslandBadge {
                                size: Tokens.iconXl
                                symbol: "timer"
                                shape: Timers.swRunning ? "clover" : "circle"
                                filled: Timers.swRunning
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Stopwatch")
                                variant: "label"
                                font.weight: Font.DemiBold
                            }
                        }
                        Item { Layout.fillHeight: true }
                        Row {
                            Layout.fillHeight: false
                            StyledText {
                                id: swMain
                                text: Timers.clockString(Math.floor(Timers.swElapsed / 1000))
                                font.pixelSize: Tokens.fontDisplay
                                font.weight: Font.Bold
                                font.features: ({ tnum: 1 })
                            }
                            StyledText {
                                anchors.baseline: swMain.baseline
                                text: "." + Timers.pad(Math.floor((Timers.swElapsed % 1000) / 10))
                                variant: "label"
                                emphasis: "muted"
                                font.features: ({ tnum: 1 })
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            readonly property var ex: TM.lapExtremes(Timers.laps)
                            text: Timers.laps.length === 0 ? (Timers.swRunning ? Translation.tr("Running") : Timers.swElapsed > 0 ? Translation.tr("Paused") : Translation.tr("Press start"))
                                : Timers.laps.length === 1 ? Translation.tr("1 lap")
                                : Translation.tr("%1 laps · best %2").arg(Timers.laps.length).arg(Timers.lapString(TM.lapSplits(Timers.laps)[ex.best] ?? 0))
                            variant: "caption"
                            emphasis: "muted"
                            elide: Text.ElideRight
                        }
                        Item { Layout.fillHeight: true }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingXs
                            ChipButton {
                                solid: true
                                symbol: Timers.swRunning ? "pause" : "play_arrow"
                                Accessible.name: Timers.swRunning ? Translation.tr("Pause") : Translation.tr("Start")
                                onActivated: Timers.swRunning ? Timers.pauseStopwatch() : Timers.startStopwatch()
                            }
                            ChipButton {
                                symbol: "flag"
                                tonal: true
                                enabled: Timers.swRunning
                                Accessible.name: Translation.tr("Lap")
                                onActivated: Timers.lap()
                            }
                            ChipButton {
                                symbol: "restart_alt"
                                tonal: true
                                enabled: !Timers.swRunning && Timers.swElapsed > 0
                                Accessible.name: Translation.tr("Reset")
                                onActivated: Timers.resetStopwatch()
                            }
                            Item { Layout.fillWidth: true }
                            ChipButton {
                                visible: Timers.laps.length > 0
                                symbol: "content_copy"
                                tonal: true
                                Accessible.name: Translation.tr("Copy the laps")
                                onActivated: Clipboard.copyText(TM.lapsText(Timers.laps, Timers.lapString))
                            }
                        }
                    }
                }

                // ── Focus ──────────────────────────────────────────────────────
                IslandPlate {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    order: 2

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.spacingMd
                        spacing: Tokens.spacingXs

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingSm
                            IslandBadge {
                                size: Tokens.iconXl
                                symbol: Timers.pomoOn && Timers.pomoPhase !== "focus" ? "coffee" : "timer"
                                shape: Timers.pomoOn ? "sunny" : "circle"
                                filled: Timers.pomoOn
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Focus rounds")
                                variant: "label"
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                        }
                        Item { Layout.fillHeight: true }
                        StyledText {
                            Layout.fillWidth: true
                            text: Timers.pomoOn ? Translation.tr(Timers.pomoLabel) : Translation.tr("%1 min").arg(Timers.pomoFocus)
                            font.pixelSize: Tokens.fontDisplay
                            font.weight: Font.Bold
                            elide: Text.ElideRight
                        }
                        // The rounds before a long break: done, the one on now, still to come.
                        Row {
                            spacing: Tokens.spacingXs
                            Repeater {
                                model: Timers.pomoEvery
                                delegate: Rectangle {
                                    id: dot
                                    required property int index
                                    readonly property bool done: dot.index < (Timers.pomoOn ? Timers.pomoCycle % Timers.pomoEvery : 0)
                                    readonly property bool now: Timers.pomoOn && Timers.pomoPhase === "focus" && dot.index === Timers.pomoCycle % Timers.pomoEvery
                                    width: dot.now ? Tokens.spacingXl : Tokens.spacingMd
                                    height: Tokens.spacingMd
                                    radius: height / 2
                                    color: dot.done || dot.now ? root.palette.primary : root.palette.alpha(root.palette.fg, 0.16)
                                    Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.overshoot } }
                                }
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("%1 min, break %2, long %3 every %4").arg(Timers.pomoFocus).arg(Timers.pomoShort).arg(Timers.pomoLong).arg(Timers.pomoEvery)
                            variant: "micro"
                            emphasis: "muted"
                            elide: Text.ElideRight
                        }
                        Item { Layout.fillHeight: true }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingXs
                            ChipButton {
                                visible: !Timers.pomoOn
                                solid: true
                                symbol: "play_arrow"
                                label: Translation.tr("Start")
                                onActivated: Timers.startPomodoro()
                            }
                            ChipButton {
                                visible: Timers.pomoOn
                                symbol: "skip_next"
                                tonal: true
                                label: Translation.tr("Skip")
                                onActivated: Timers.pomoSkip()
                            }
                            ChipButton {
                                visible: Timers.pomoOn
                                symbol: "stop"
                                tonal: true
                                Accessible.name: Translation.tr("Stop the rounds")
                                onActivated: Timers.stopTimer()
                            }
                            Item { Layout.fillWidth: true }
                            NumberStepper {
                                visible: !Timers.pomoOn
                                from: 5; to: 120; step: 5
                                compact: true
                                numberWidth: Tokens.iconXl
                                value: Timers.pomoFocus
                                readout: String(value) + "m"
                                onCommit: function (v) { Timers.setPomo("focus", v) }
                            }
                        }
                    }
                }
            }

            // ── Alarms ─────────────────────────────────────────────────────────
            // The alarms as cards in a row (the time, the days as seven dots, on = loud and rounder; repeat and
            // remove under the pointer), and a new one as one row along the foot: the time, how it repeats (one
            // chip that cycles Once, Weekdays, Every day, Weekends), Add.
            IslandPlate {
                Layout.fillWidth: true
                Layout.fillHeight: true
                order: 3

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingMd
                    spacing: Tokens.spacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm
                        IslandBadge {
                            size: Tokens.iconXl
                            symbol: "alarm"
                            shape: root.nextAlarm ? "cookie12" : "circle"
                            filled: root.nextAlarm !== null
                        }
                        StyledText {
                            text: Translation.tr("Alarms")
                            variant: "label"
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.nextAlarm ? Translation.tr("Next %1, %2").arg(Timers.pad(root.nextAlarm.a.h) + ":" + Timers.pad(root.nextAlarm.a.m)).arg(root.inText(root.nextAlarm.at - Date.now()))
                                : Timers.alarms.length > 0 ? Translation.tr("All off") : ""
                            variant: "caption"
                            emphasis: "muted"
                            elide: Text.ElideRight
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        // None yet: say so where the cards would be.
                        Column {
                            anchors.centerIn: parent
                            visible: Timers.alarms.length === 0
                            spacing: Tokens.spacingXs
                            MorphShape {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Tokens.iconXl * 1.5
                                height: width
                                shape: "cookie9"
                                turns: false
                                fillColor: root.palette.plate
                                MaterialIcon {
                                    anchors.centerIn: parent
                                    name: "alarm_add"
                                    color: root.palette.fgMuted
                                }
                            }
                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Translation.tr("No alarms. Set one below.")
                                variant: "caption"
                                emphasis: "muted"
                            }
                        }

                        ListView {
                            id: alarmList
                            anchors.fill: parent
                            visible: Timers.alarms.length > 0
                            clip: true
                            orientation: ListView.Horizontal
                            spacing: Tokens.spacingSm
                            boundsBehavior: Flickable.StopAtBounds
                            model: ScriptModel { values: Timers.alarms; objectProp: "id" }

                            delegate: Rectangle {
                                id: card
                                required property var modelData
                                readonly property bool on: card.modelData.enabled
                                readonly property int days: card.modelData.days || 0
                                readonly property color ink: card.on ? root.palette.fgOnPrimaryContainer : root.palette.fgMuted
                                width: Tokens.spacingXl * 8
                                height: ListView.view.height
                                radius: card.on ? Tokens.radiusXl : Tokens.radiusCard
                                color: card.on ? root.palette.primaryContainer : root.palette.plate
                                Behavior on color { ColorAnimation { duration: Motion.standard } }
                                Behavior on radius { NumberAnimation { duration: Motion.standard; easing.type: Motion.overshoot } }

                                HoverHandler { id: cardHover }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Timers.toggleAlarm(card.modelData.id)
                                    Accessible.role: Accessible.CheckBox
                                    Accessible.name: Translation.tr("Alarm %1").arg(Timers.pad(card.modelData.h) + ":" + Timers.pad(card.modelData.m))
                                    Accessible.checked: card.on
                                }
                                Column {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: Tokens.spacingMd
                                    spacing: Tokens.spacingXs
                                    StyledText {
                                        text: Timers.pad(card.modelData.h) + ":" + Timers.pad(card.modelData.m)
                                        font.pixelSize: Tokens.fontDisplay
                                        font.weight: Font.Bold
                                        font.features: ({ tnum: 1 })
                                        color: card.ink
                                    }
                                    // The week as seven dots, Monday first: lit on the days it rings.
                                    Row {
                                        spacing: Tokens.spacingXs
                                        Repeater {
                                            model: [1, 2, 3, 4, 5, 6, 0]
                                            delegate: Rectangle {
                                                required property int modelData
                                                readonly property bool lit: ((card.days >> modelData) & 1) === 1
                                                width: Tokens.spacingSm + Tokens.spacingXs
                                                height: width
                                                radius: width / 2
                                                color: lit ? (card.on ? root.palette.primary : root.palette.fgMuted)
                                                           : root.palette.alpha(card.ink, 0.18)
                                            }
                                        }
                                    }
                                    StyledText {
                                        width: parent.width
                                        text: (card.modelData.snoozeAt || 0) > 0 ? Translation.tr("Snoozed") : AL.repeatLabel(card.days)
                                        variant: "micro"
                                        color: root.palette.alpha(card.ink, 0.8)
                                        elide: Text.ElideRight
                                    }
                                }
                                Row {
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: Tokens.spacingXs
                                    opacity: cardHover.hovered ? 1 : 0
                                    visible: opacity > 0.01
                                    Behavior on opacity { NumberAnimation { duration: Motion.respond; easing.type: Motion.respondCurve } }
                                    CardTool {
                                        symbol: "repeat"
                                        tint: card.ink
                                        name: Translation.tr("Repeat: %1").arg(AL.repeatLabel(AL.nextPreset(card.days)))
                                        onActivated: Timers.setAlarmDays(card.modelData.id, AL.nextPreset(card.days))
                                    }
                                    CardTool {
                                        symbol: "close"
                                        tint: card.ink
                                        name: Translation.tr("Remove")
                                        onActivated: Timers.removeAlarm(card.modelData.id)
                                    }
                                }
                            }
                        }
                    }

                    // ── A new one ──────────────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.preferredHeight: addRow.implicitHeight + Tokens.spacingXs * 2
                        radius: height / 2
                        color: root.palette.plate

                        RowLayout {
                            id: addRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Tokens.spacingMd
                            anchors.rightMargin: Tokens.spacingXs
                            spacing: Tokens.spacingXs
                            MaterialIcon {
                                name: "alarm_add"
                                color: root.palette.fgMuted
                            }
                            NumberStepper {
                                from: 0; to: 23; step: 1
                                compact: true
                                numberWidth: Tokens.iconXl
                                value: root.newH
                                readout: Timers.pad(value)
                                onCommit: function (v) { root.newH = v }
                            }
                            StyledText { text: ":"; variant: "title" }
                            NumberStepper {
                                from: 0; to: 55; step: 5
                                compact: true
                                numberWidth: Tokens.iconXl
                                value: root.newM
                                readout: Timers.pad(value)
                                onCommit: function (v) { root.newM = v }
                            }
                            ChipButton {
                                symbol: "repeat"
                                label: AL.repeatLabel(root.newDays)
                                labelVariant: "caption"
                                on: root.newDays !== 0
                                Accessible.name: Translation.tr("Repeats: %1").arg(AL.repeatLabel(root.newDays))
                                onActivated: root.newDays = AL.nextPreset(root.newDays)
                            }
                            Item { Layout.fillWidth: true }
                            ChipButton {
                                solid: true
                                symbol: "add"
                                label: Translation.tr("Add")
                                onActivated: { Timers.addAlarm(root.newH, root.newM, root.newDays); root.newDays = 0 }
                            }
                        }
                    }
                }
            }
        }
    }
}
