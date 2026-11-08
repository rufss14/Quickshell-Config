pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import QtQuick.Shapes
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/weather.js" as W
import "../../services/ics.js" as Ics
import "../../services/holidays.js" as H
import "../../services/dayfacts.js" as Facts
import "../../services/dayplan.js" as Plan
import "../../services/quickadd.js" as Quick
import "../../services/alarms.js" as AL
import "../../services/worldclock.js" as Z

// ClockClocksView — ClockPanel's clocks page, moved into its own file (2026-11-08). Reads and writes
// the panel's state through `panel` (was `root`).
// ══ CLOCKS ════════════════════════════════════════════════════════
// The world on the left as a meeting planner, the alarms on the right under a big clock. Each is
// as tall as the month card, so the three pages are one height. Neither does work of its own:
// WorldClock reads the offsets, Timers owns the alarms and the timer (the same ones the sidebar's
// timer panel has).
//
// ── The planner ───────────────────────────────────────────────────
// A row is a little analog face, the city and how far ahead it is, a 24-hour RIBBON (night dim,
// daylight warm, office hours — 09 to 17 there — in the accent) and the time. The ribbons share
// one axis, YOUR hours, so a morning that is office hours in two places lines up in both. Drag
// across any ribbon and every row, face and clock turns to that moment ("what is it there when
// it is 03:00 here?"); Now comes back.
Item {
    id: clocksView
    // The panel that owns the state and the actions (ClockPanel.qml's root).
    required property var panel
    // Reached into by the panel (keys, the editor, clearing fields).
    property alias alarmField: alarmField
    property alias zoneField: zoneField

    anchors.left:  parent.left
    anchors.right: parent.right
    anchors.top:   parent.top
    implicitHeight: clocksRow.implicitHeight

    readonly property bool on: panel.view === "clocks"
    opacity: on ? 1 : 0
    visible: opacity > 0
    transform: Translate {
        x: clocksView.on ? 0 : Tokens.spacingXl
        Behavior on x { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
    }
    Behavior on opacity { NumberAnimation { duration: Motion.standard } }

    RowLayout {
        id: clocksRow
        anchors.left:  parent.left
        anchors.right: parent.right
        anchors.top:   parent.top
        spacing: Tokens.spacingMd

        // ── The world ─────────────────────────────────────────────
        Rectangle {
            id: worldCard
            Layout.fillWidth: true
            Layout.preferredWidth: 3
            Layout.fillHeight: true
            Layout.preferredHeight: panel.pageBoxH
            radius: Tokens.radiusCard
            color: Colors.of(QsWindow.window).section
            opacity: 0
            ViewEnter { target: worldCard; active: panel.clocksOn; delay: panel.lead; rise: Tokens.spacingMd }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingMd
                spacing: Tokens.spacingSm

                // The title, what moment the rows show, the search, and the way back to now —
                // one row, at a fixed height so the Now chip arriving moves nothing.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: Tokens.iconXl + Tokens.spacingMd
                    spacing: Tokens.spacingSm

                    MaterialIcon {
                        name: "public"
                        fill: 1
                        font.pixelSize: Tokens.iconMd
                        color: panel.accent
                    }
                    StyledText {
                        text: Translation.tr("World")
                        variant: "label"
                        font.weight: Font.DemiBold
                    }
                    // What the rows are showing: how many places, or — while you drag — the moment, here.
                    StyledText {
                        text: panel.planMs > 0 ? Qt.formatDateTime(new Date(panel.planMs), "ddd HH:mm") + " here"
                            : WorldClock.zones.length > 0 ? WorldClock.zones.length + 1 : ""
                        variant: "caption"
                        font.bold: panel.planMs > 0
                        color: panel.planMs > 0 ? panel.accent : Colors.of(QsWindow.window).fgDim
                        Behavior on color { ColorAnimation { duration: Motion.standard } }
                    }

                    // Typing lists matching cities; Enter (or a click) adds one.
                    InputField {
                        id: zoneField
                        Layout.fillWidth: true
                        implicitHeight: Tokens.iconXl + Tokens.spacingMd
                        cornerRadius: implicitHeight / 2
                        icon: "search"
                        placeholder: Translation.tr("Add a city…")
                        onEdited: (value) => { panel.zoneQuery = value; panel.zoneError = ""; if (value.trim() !== "") WorldClock.ensureList() }
                        onAccepted: { if (panel.zoneMatches.length > 0) panel.addZone(panel.zoneMatches[0]) }
                        onKeyPressed: (event) => {
                            if (event.key !== Qt.Key_Escape) return
                            zoneField.clear(); panel.zoneQuery = ""; zoneField.blur(); event.accepted = true
                        }
                    }
                    ChipTray {
                        groupShown: panel.planMs > 0
                        ChipButton {
                            symbol: "history"
                            label:  Translation.tr("Now")
                            on:     true
                            tint:   panel.accent
                            onActivated: panel.planMs = -1
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: Tokens.iconXl * 2
                    Layout.minimumHeight: Tokens.iconXl * 2

                    // ── The clocks ────────────────────────────────
                    Flickable {
                        id: zoneList
                        anchors.fill: parent
                        clip: true
                        contentHeight: zoneColumn.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.VerticalFlick
                        opacity: panel.zoneQuery.trim() === "" ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                        Column {
                            id: zoneColumn
                            width: zoneList.width - Tokens.spacingMd
                            spacing: 0

                            // Where the ribbon sits in a row: after the face and the name, before the time.
                            readonly property real faceW: Tokens.iconXl
                            readonly property real nameW: Tokens.iconXl * 3
                            readonly property real timeW: Tokens.iconXl * 2
                            readonly property real ribbonX: faceW + nameW + Tokens.spacingMd * 2
                            readonly property real ribbonW: Math.max(Tokens.iconXl, width - ribbonX - timeW - Tokens.spacingSm)

                            // Here: the machine's own clock, always first.
                            Item {
                                id: hereRow
                                width: zoneColumn.width
                                height: Tokens.iconXl + Tokens.spacingLg
                                readonly property var rd: WorldClock.here(panel.planMs)

                                PopIn { id: herePop; active: panel.clocksOn; index: 0; delay: panel.lead + Motion.respond }
                                opacity: herePop.opacity
                                scale:   herePop.scale

                                ClockFace {
                                    id: hereFace
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: zoneColumn.faceW; height: width
                                    accent: panel.accent
                                    hours: hereRow.rd.h; minutes: hereRow.rd.m
                                    tone: hereRow.rd.day ? "day" : "night"
                                }
                                ColumnLayout {
                                    x: zoneColumn.faceW + Tokens.spacingMd
                                    width: zoneColumn.nameW
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: WorldClock.localZone !== "" ? Z.cityName(WorldClock.localZone) : "Here"
                                        variant: "label"
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Translation.tr("Here")
                                        variant: "caption"
                                        color: panel.accent
                                    }
                                }
                                ClockRibbon {
                                    x: zoneColumn.ribbonX
                                    width: zoneColumn.ribbonW
                                    anchors.verticalCenter: parent.verticalCenter
                                    off: hereRow.rd.off
                                    winStart: panel.winStart
                                    accent: panel.accent
                                }
                                RollText {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Clock.pad(hereRow.rd.h) + ":" + Clock.pad(hereRow.rd.m)
                                    family:    Tokens.fontBlock
                                    pixelSize: Tokens.fontTitle
                                    weight:    Font.Bold
                                }
                            }

                            Repeater {
                                model: panel.clocksSeen ? WorldClock.zones : []

                                delegate: Item {
                                    id: zr
                                    required property int index
                                    required property string modelData
                                    readonly property var rd: WorldClock.reading(zr.modelData, panel.planMs)

                                    width: zoneColumn.width
                                    height: Tokens.iconXl + Tokens.spacingLg

                                    PopIn { id: zrPop; active: panel.clocksOn; index: zr.index + 1; delay: panel.lead + Motion.respond }
                                    opacity: zrPop.opacity
                                    scale:   zrPop.scale

                                    HoverHandler {
                                        id: zrHover
                                    }

                                    // The face turns to the time there, and tints with its day or night.
                                    ClockFace {
                                        id: zrFace
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: zoneColumn.faceW; height: width
                                        accent: panel.accent
                                        hours: zr.rd.known ? zr.rd.h : 0
                                        minutes: zr.rd.known ? zr.rd.m : 0
                                        tone: !zr.rd.known ? "" : zr.rd.day ? "day" : "night"
                                    }
                                    ColumnLayout {
                                        x: zoneColumn.faceW + Tokens.spacingMd
                                        width: zoneColumn.nameW
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 0
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: Z.cityName(zr.modelData)
                                            variant: "label"
                                            elide: Text.ElideRight
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: !zr.rd.known ? "Reading…"
                                                : Z.dayWord(zr.rd.dayShift) + "  ·  " + zr.rd.diff
                                            variant: "caption"
                                            // Another day than yours reads warmer — it is a different date there.
                                            color: zr.rd.known && zr.rd.dayShift !== 0 ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).fgDim
                                            elide: Text.ElideRight
                                        }
                                    }
                                    ClockRibbon {
                                        x: zoneColumn.ribbonX
                                        width: zoneColumn.ribbonW
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: zr.rd.known
                                        off: zr.rd.known ? zr.rd.off : 0
                                        winStart: panel.winStart
                                        accent: panel.accent
                                    }
                                    RollText {
                                        id: zrTime
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: zr.rd.known ? Clock.pad(zr.rd.h) + ":" + Clock.pad(zr.rd.m) : "--:--"
                                        family:    Tokens.fontBlock
                                        pixelSize: Tokens.fontTitle
                                        weight:    Font.Bold
                                        opacity: zrTray.pop > 0.01 ? 1 - zrTray.pop : 1
                                    }
                                    // On hover the time makes way for remove.
                                    HoverTray {
                                        id: zrTray
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        shown: zrHover.hovered
                                        ChipButton {
                                            symbol: "close"
                                            tint:   Colors.of(QsWindow.window).danger
                                            onActivated: WorldClock.remove(zr.modelData)
                                        }
                                    }
                                }
                            }
                        }

                        // ── The planning cursor, over every ribbon ────────
                        // Drag (or click) anywhere on a ribbon: the line goes there, and every row follows.
                        // Idle it sits at now, thin; held, it is the accent with a knob.
                        Item {
                            id: planLayer
                            x: zoneColumn.ribbonX
                            y: 0
                            width: zoneColumn.ribbonW
                            height: zoneColumn.implicitHeight
                            z: 5

                            Rectangle {
                                id: cursorLine
                                readonly property bool planning: panel.planMs > 0
                                x: panel.planFrac * planLayer.width - width / 2
                                y: 0
                                width: planning ? Tokens.borderWidth * 2 : Tokens.borderWidth
                                height: planLayer.height
                                radius: width / 2
                                color: panel.accent
                                opacity: planning ? 1 : 0.45
                                Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                                Behavior on x {
                                    enabled: !scrub.pressed
                                    SpringAnimation { spring: 5.5; damping: 0.38; epsilon: 0.1 }
                                }
                            }
                            Rectangle {
                                // The knob on the line, where you hold.
                                x: cursorLine.x + cursorLine.width / 2 - width / 2
                                y: Tokens.spacingXs
                                width:  scrub.pressed ? Tokens.iconSm : Tokens.spacingMd
                                height: width
                                radius: width / 2
                                color: panel.accent
                                opacity: cursorLine.planning ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                                Behavior on width { SpringAnimation { spring: 6; damping: 0.34; epsilon: 0.1 } }
                            }

                            MouseArea {
                                id: scrub
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.SizeHorCursor
                                function setFrom(mx) { panel.planMs = Z.pointAt(panel.winStart, mx / planLayer.width) }
                                onPressed:         (mouse) => scrub.setFrom(mouse.x)
                                onPositionChanged: (mouse) => { if (pressed) scrub.setFrom(mouse.x) }
                            }
                        }
                    }
                    Scrollbar { flickable: zoneList }

                    // ── The search results ────────────────────────
                    Column {
                        id: zoneResults
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        spacing: 0
                        opacity: panel.zoneQuery.trim() !== "" ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                        Repeater {
                            model: panel.zoneMatches

                            delegate: Item {
                                id: zm
                                required property int index
                                required property string modelData
                                width: zoneResults.width
                                height: Tokens.iconXl + Tokens.spacingMd

                                PopIn { id: zmPop; active: zoneResults.visible; index: zm.index }
                                opacity: zmPop.opacity
                                scale:   zmPop.scale

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Tokens.radiusSm
                                    color: Colors.of(QsWindow.window).alpha(panel.accent, 0.12)
                                    // The first one is what Enter adds.
                                    opacity: zmHover.hovered || zm.index === 0 ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                }
                                HoverHandler { id: zmHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler   { onTapped: panel.addZone(zm.modelData) }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Tokens.spacingMd
                                    anchors.rightMargin: Tokens.spacingMd
                                    spacing: Tokens.spacingSm
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: false
                                        spacing: 0
                                        StyledText { Layout.fillWidth: true; text: Z.cityName(zm.modelData); variant: "label"; elide: Text.ElideRight }
                                        StyledText { Layout.fillWidth: true; text: Z.regionName(zm.modelData); variant: "caption"; emphasis: "dim"; elide: Text.ElideRight }
                                    }
                                    MaterialIcon { name: "add"; font.pixelSize: Tokens.iconMd; color: panel.accent }
                                }
                            }
                        }

                        // Nothing to show: still reading the list, or nothing matches.
                        StyledText {
                            visible: panel.zoneMatches.length === 0
                            width: zoneResults.width
                            topPadding: Tokens.spacingMd
                            horizontalAlignment: Text.AlignHCenter
                            text: WorldClock.listing ? "Looking…"
                                : WorldClock.allZones.length === 0 ? "Couldn't read the list of time zones"
                                : "No city called that"
                            variant: "caption"
                            emphasis: "dim"
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: panel.zoneError
                    variant: "caption"
                    color: Colors.of(QsWindow.window).danger
                    elide: Text.ElideRight
                }
            }
        }

        // ── The clock, the next alarm, the alarms ─────────────────
        Rectangle {
            id: alarmCard
            Layout.fillWidth: true
            Layout.preferredWidth: 2
            Layout.fillHeight: true
            Layout.preferredHeight: panel.pageBoxH
            radius: Tokens.radiusCard
            color: Colors.of(QsWindow.window).section
            opacity: 0
            ViewEnter { target: alarmCard; active: panel.clocksOn; delay: panel.lead + Motion.respond; rise: Tokens.spacingMd }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingMd
                spacing: Tokens.spacingSm

                // ── The face, and what is coming ──────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd

                    // Your time, as a cookie: seconds ticking, tinted by day or night, and — while
                    // the timer runs — a ring sweeping round the rim.
                    ClockFace {
                        id: bigFace
                        Layout.preferredWidth:  Tokens.iconXl * 3
                        Layout.preferredHeight: Layout.preferredWidth
                        Layout.alignment: Qt.AlignVCenter
                        scalloped: true
                        showSeconds: true
                        accent: panel.accent
                        hours: panel.now.getHours(); minutes: panel.now.getMinutes(); seconds: panel.now.getSeconds()
                        tone: WorldClock.here(-1).day ? "day" : "night"
                        ring: Timers.timerDone ? 1
                            : (Timers.timerRunning || Timers.timerPaused) && Timers.timerSpan > 0 ? 1 - Timers.timerRemain / Timers.timerSpan
                            : -1
                        ringColor: Timers.timerDone ? Colors.of(QsWindow.window).warning : panel.accent
                        // The ring follows the seconds counting down, smoothly between them.
                        Behavior on ring {
                            NumberAnimation { duration: Motion.pulse * 2; easing.type: Easing.Linear }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.alignment: Qt.AlignVCenter
                        spacing: Tokens.spacingXs

                        StyledText {
                            text: "NEXT ALARM"
                            variant: "micro"
                            font.bold: true
                            font.letterSpacing: Tokens.borderWidth
                            color: panel.nextAlarm ? panel.accent : Colors.of(QsWindow.window).fgMuted
                        }
                        RollText {
                            text: panel.nextAlarm ? W.duration(Math.max(0, panel.nextAlarm.at - panel.nowMs) / 1000) : "—"
                            family:    Tokens.fontBlock
                            pixelSize: Tokens.fontHeadline
                            weight:    Font.Bold
                            color: panel.nextAlarm ? Colors.of(QsWindow.window).fg : Colors.of(QsWindow.window).fgDim
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: panel.nextAlarm
                                ? Qt.formatDateTime(new Date(panel.nextAlarm.at), "ddd HH:mm") + "  ·  " + AL.repeatLabel(panel.nextAlarm.days || 0)
                                : Timers.alarms.length > 0 ? "All off" : "None set"
                            variant: "caption"
                            emphasis: "dim"
                            elide: Text.ElideRight
                        }

                        // ── The timer ─────────────────────────────
                        // Quick lengths when idle; the countdown and a way out when it runs.
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Tokens.iconXl + Tokens.spacingMd

                            ChipTray {
                                id: timerPresets
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                groupShown: !Timers.timerRunning && !Timers.timerPaused && !Timers.timerDone
                                opacity: groupShown ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                                ChipButton { label: "5m";  tint: panel.accent; onActivated: Timers.startTimerFor(5 * 60) }
                                ChipButton { label: "10m"; tint: panel.accent; onActivated: Timers.startTimerFor(10 * 60) }
                                ChipButton { label: "25m"; tint: panel.accent; onActivated: Timers.startTimerFor(25 * 60) }
                            }
                            RowLayout {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: Tokens.spacingSm
                                visible: Timers.timerRunning || Timers.timerPaused || Timers.timerDone
                                opacity: visible ? 1 : 0

                                MaterialIcon {
                                    name: "timer"
                                    fill: 1
                                    font.pixelSize: Tokens.iconMd
                                    color: Timers.timerDone ? Colors.of(QsWindow.window).warning : panel.accent
                                }
                                RollText {
                                    text: Timers.timerDone ? "Time's up" : Timers.clockString(Timers.timerRemain)
                                    family:    Tokens.fontBlock
                                    pixelSize: Tokens.fontTitle
                                    weight:    Font.Bold
                                    color: Timers.timerDone ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).fg
                                }
                                Item { Layout.fillWidth: true }
                                ChipTray {
                                    ChipButton {
                                        symbol: Timers.timerDone ? "check" : "close"
                                        tint:   panel.accent
                                        onActivated: Timers.stopTimer()
                                    }
                                }
                            }
                        }
                    }
                }

                // ── The alarms ────────────────────────────────────
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: Tokens.iconXl * 2
                    Layout.minimumHeight: Tokens.iconXl * 2

                    Flickable {
                        id: alarmList
                        anchors.fill: parent
                        clip: true
                        contentHeight: alarmColumn.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: alarmColumn
                            width: alarmList.width - Tokens.spacingMd
                            spacing: 0

                            Repeater {
                                model: panel.clocksSeen ? panel.alarmIds : []

                                delegate: Item {
                                    id: al
                                    required property int index
                                    required property string modelData
                                    readonly property var a: Timers.alarms.find(x => x.id === al.modelData)
                                                             ?? ({ id: al.modelData, h: 0, m: 0, enabled: false, at: 0, days: 0 })
                                    readonly property bool on: al.a.enabled

                                    width: alarmColumn.width
                                    height: Tokens.iconXl + Tokens.spacingSm

                                    PopIn { id: alPop; active: panel.clocksOn; index: al.index; delay: panel.lead + Motion.respond }
                                    opacity: alPop.opacity
                                    scale:   alPop.scale

                                    RollText {
                                        id: alTime
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Clock.pad(al.a.h) + ":" + Clock.pad(al.a.m)
                                        family:    Tokens.fontBlock
                                        pixelSize: Tokens.fontTitle
                                        weight:    Font.Bold
                                        color: al.on ? Colors.of(QsWindow.window).fg : Colors.of(QsWindow.window).fgDim
                                    }

                                    // The weekdays it repeats on: tap one to flip it. None lit is once.
                                    Row {
                                        anchors.left: alTime.right
                                        anchors.leftMargin: Tokens.spacingMd
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Tokens.borderWidth * 2
                                        opacity: al.on ? 1 : 0.5
                                        Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                                        Repeater {
                                            // Monday first; the bit for each is Date.getDay()'s (Sunday 0).
                                            model: [{ l: "M", d: 1 }, { l: "T", d: 2 }, { l: "W", d: 3 }, { l: "T", d: 4 },
                                                    { l: "F", d: 5 }, { l: "S", d: 6 }, { l: "S", d: 0 }]

                                            delegate: Item {
                                                id: dd
                                                required property var modelData
                                                readonly property bool lit: ((al.a.days || 0) >> dd.modelData.d) & 1
                                                width: Tokens.iconMd + 1
                                                height: width

                                                // Fills and springs when it is switched on.
                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: width / 2
                                                    color: dd.lit ? panel.accent : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, ddHover.hovered ? 0.16 : 0.07)
                                                    scale: dd.lit ? 1 : 0.88
                                                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                                                    Behavior on scale {
                                                        NumberAnimation {
                                                            duration: Motion.spatial
                                                            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring
                                                        }
                                                    }
                                                }
                                                StyledText {
                                                    anchors.centerIn: parent
                                                    text: dd.modelData.l
                                                    variant: "micro"
                                                    font.bold: dd.lit
                                                    color: dd.lit ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fgMuted
                                                }
                                                HoverHandler { id: ddHover; cursorShape: Qt.PointingHandCursor }
                                                TapHandler {
                                                    onTapped: Timers.setAlarmDays(al.a.id, (al.a.days || 0) ^ (1 << dd.modelData.d))
                                                }
                                            }
                                        }
                                    }

                                    // Remove: a small cross that warms to danger under the pointer.
                                    MaterialIcon {
                                        id: alRemove
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: "close"
                                        font.pixelSize: Tokens.iconSm
                                        color: rmHover.hovered ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgDim
                                        scale: rmHover.hovered ? 1.2 : 1
                                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                                        Behavior on scale {
                                            NumberAnimation {
                                                duration: Motion.spatial
                                                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring
                                            }
                                        }
                                        HoverHandler { id: rmHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler   { onTapped: Timers.removeAlarm(al.a.id) }
                                    }
                                    Toggle {
                                        anchors.right: alRemove.left
                                        anchors.rightMargin: Tokens.spacingMd
                                        anchors.verticalCenter: parent.verticalCenter
                                        checked: al.on
                                        accent:  panel.accent
                                        onToggled: Timers.toggleAlarm(al.a.id)
                                    }
                                }
                            }

                            StyledText {
                                visible: Timers.alarms.length === 0
                                width: alarmColumn.width
                                topPadding: Tokens.spacingMd
                                horizontalAlignment: Text.AlignHCenter
                                text: Translation.tr("No alarms yet — add one below")
                                variant: "caption"
                                emphasis: "dim"
                            }
                        }
                    }
                    Scrollbar { flickable: alarmList }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: panel.alarmError
                    variant: "caption"
                    color: Colors.of(QsWindow.window).danger
                    elide: Text.ElideRight
                }

                // ── New alarm ─────────────────────────────────────
                // A time, the days it starts with (a chip steps through the presets; the dots on
                // the alarm itself then fine-tune), and add.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm

                    InputField {
                        id: alarmField
                        Layout.fillWidth: true
                        implicitHeight: Tokens.iconXl + Tokens.spacingMd
                        cornerRadius: implicitHeight / 2
                        icon: "alarm"
                        mono: true
                        placeholder: "07:30"
                        invalid: panel.alarmError !== ""
                        onEdited: (value) => { panel.alarmText = value; panel.alarmError = "" }
                        onAccepted: panel.addAlarm()
                        onKeyPressed: (event) => { if (event.key === Qt.Key_Escape) { alarmField.blur(); event.accepted = true } }
                    }
                    ChipTray {
                        ChipButton {
                            symbol: "repeat"
                            label:  AL.repeatLabel(panel.alarmDays)
                            tint:   panel.accent
                            onActivated: panel.alarmDays = AL.nextPreset(panel.alarmDays)
                        }
                        ChipButton {
                            symbol:  "check"
                            on:      panel.alarmText.trim() !== ""
                            tint:    panel.accent
                            enabled: panel.alarmText.trim() !== ""
                            onActivated: panel.addAlarm()
                        }
                    }
                }
            }
        }
    }
}
