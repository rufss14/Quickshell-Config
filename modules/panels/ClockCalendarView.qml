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

// ClockCalendarView — ClockPanel's calendar page, moved into its own file (2026-11-08). Reads and writes
// the panel's state through `panel` (was `root`).
// ══ CALENDAR ══════════════════════════════════════════════════════
// The month on the left, always; on the right the agenda — reminders and the days
// ahead in ONE list, with the quick-add at its foot — or, while an event is being
// written, the editor. The month stays where it is while editing, so the date is
// chosen by clicking it. The page is as tall as the month, and nothing is stacked
// on top of anything else.
Item {
    id: calendarView
    // The panel that owns the state and the actions (ClockPanel.qml's root).
    required property var panel
    // Reached into by the panel (keys, the editor, clearing fields).
    property alias monthPager: monthPager
    property alias reminderField: reminderField
    property alias reminderTimeField: reminderTimeField
    property alias deleteLatch: deleteLatch
    property alias titleField: titleField
    property alias startField: startField
    property alias endField: endField
    property alias locationField: locationField

    anchors.left:  parent.left
    anchors.right: parent.right
    anchors.top:   parent.top
    implicitHeight: monthView.implicitHeight

    readonly property bool on: panel.view === "calendar"
    opacity: on ? 1 : 0
    visible: opacity > 0
    transform: Translate {
        x: calendarView.on ? 0 : panel.view === "weather" ? Tokens.spacingXl : -Tokens.spacingXl
        Behavior on x { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
    }
    Behavior on opacity { NumberAnimation { duration: Motion.standard } }

    RowLayout {
        id: monthView
        anchors.left:  parent.left
        anchors.right: parent.right
        anchors.top:   parent.top
        spacing: Tokens.spacingMd

        readonly property bool shown:   panel.calendarOn
        readonly property bool editing: panel.calView === "edit"
        // The month card's height; the side card is at least that, and more only if
        // the editor (or a very large font) needs it.
        readonly property real monthH: monthPager.pageH + Tokens.spacingMd * 2

        // ── The month, a page each, scrolling downwards ───────────
        // Four years of pages, centred on this month. The wheel and the arrows move
        // exactly one month on the house curve; a drag snaps to a page. Pages fade
        // and sink a little as they leave the view, so the one arriving reads as the
        // one that matters.
        Rectangle {
            id: monthCard
            Layout.fillWidth: false
            Layout.fillHeight: true
            Layout.preferredWidth: monthPager.gridW + Tokens.spacingMd * 2
            Layout.preferredHeight: monthView.monthH
            radius: Tokens.radiusCard
            color: Colors.of(QsWindow.window).section
            opacity: 0
            ViewEnter { target: monthCard; active: monthView.shown; delay: panel.lead; rise: Tokens.spacingMd }

            Item {
                id: monthPager
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.spacingMd
                height: monthPager.pageH
                clip: true

                readonly property int span: 24
                readonly property date base: { Clock.dayStamp; return new Date() }
                readonly property int cell: Tokens.iconXl + Tokens.spacingXs
                readonly property int gap: Tokens.spacingXs
                readonly property int gridW: monthPager.cell * 7 + monthPager.gap * 6
                // The month's name sits level with the arrows, so a page is as tall as the tray.
                readonly property int head: Tokens.iconXl + Tokens.spacingMd
                // Measured, so the page follows the font scale. MonthGrid lays out as
                // [weekday names, spacing, six rows]; the sum is its height without
                // building 42 cells to read it back.
                readonly property real pageH: monthPager.head + Tokens.spacingSm
                    + dayNameProbe.implicitHeight + Tokens.spacingSm
                    + (monthPager.cell * 6 + monthPager.gap * 5) + Tokens.spacingSm

                // Before the page is visited there are no pages, and "today" is where it starts.
                readonly property int index: Math.max(0, Math.min(monthPager.span * 2,
                    Math.round(months.contentY / Math.max(1, months.height))))
                property int target: monthPager.span
                readonly property bool atToday: !months.placed
                                             || (monthPager.index === monthPager.span
                                                 && !scroll.running && !months.moving)

                function scrollTo(i) {
                    if (!months.placed) return
                    monthPager.target = Math.max(0, Math.min(monthPager.span * 2, i))
                    const y = monthPager.target * months.height
                    if (!Config.motionEnabled) {
                        scroll.stop()
                        months.contentY = y
                        return
                    }
                    scroll.to = y
                    scroll.restart()
                }
                // From where it's HEADED while a scroll is still running, so three
                // quick notches travel three months rather than restarting on one.
                function step(n) { monthPager.scrollTo((scroll.running ? monthPager.target : monthPager.index) + n) }
                function goToday() { monthPager.scrollTo(monthPager.span) }
                // The page holding a day (local-midnight ms).
                function goToDay(ms) {
                    const d = new Date(ms), b = monthPager.base
                    monthPager.scrollTo(monthPager.span + (d.getFullYear() - b.getFullYear()) * 12 + d.getMonth() - b.getMonth())
                }

                StyledText { id: dayNameProbe; visible: false; text: "Mo"; variant: "micro"; font.bold: true }

                NumberAnimation {
                    id: scroll
                    target: months
                    property: "contentY"
                    duration: Motion.spatial
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.emphasizedDecel
                }

                ListView {
                    id: months
                    anchors.fill: parent
                    // Built on the first visit (see `calendarSeen`).
                    model: panel.calendarSeen ? monthPager.span * 2 + 1 : 0
                    snapMode: ListView.SnapOneItem
                    boundsBehavior: Flickable.StopAtBounds
                    // A page each side of the one in view: the others are not visible anyway
                    // (they fade as they leave).
                    cacheBuffer: months.height
                    onMovementStarted: scroll.stop()

                    // Land on this month once there are pages and a height to land with.
                    property bool placed: false
                    function place() {
                        if (months.placed || months.height <= 0 || months.count === 0) return
                        months.positionViewAtIndex(monthPager.span, ListView.Beginning)
                        months.placed = true
                    }
                    onHeightChanged: months.place()
                    onCountChanged: months.place()

                    delegate: Item {
                        id: page
                        required property int index
                        readonly property date first: new Date(monthPager.base.getFullYear(),
                                                               monthPager.base.getMonth() + page.index - monthPager.span, 1)
                        // How far this page sits from the one in view, in pages.
                        readonly property real offset: (page.y - months.contentY) / Math.max(1, months.height)
                        readonly property bool isThisMonth: page.index === monthPager.span

                        width:  months.width
                        height: months.height
                        opacity: 1 - Math.min(1, Math.abs(page.offset)) * 0.9
                        scale:   1 - Math.min(1, Math.abs(page.offset)) * 0.06

                        Component.onCompleted: Calendar.ensureHolidays(page.first.getFullYear())

                        Column {
                            anchors.left: parent.left
                            spacing: Tokens.spacingSm

                            // Left-aligned, leaving the top-right corner to the arrows. Click the name
                            // to come back to now.
                            Row {
                                height: monthPager.head
                                spacing: Tokens.spacingSm

                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler   { onTapped: panel.backToNow() }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Qt.locale().standaloneMonthName(page.first.getMonth())
                                    variant: "title"
                                    font.weight: Font.DemiBold
                                    color: page.isThisMonth ? panel.accent : Colors.of(QsWindow.window).fg
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: page.first.getFullYear()
                                    variant: "title"
                                    emphasis: "dim"
                                }
                            }

                            MonthGrid {
                                navigation: false
                                year:  page.first.getFullYear()
                                month: page.first.getMonth()
                                cellSize:   monthPager.cell
                                cellGap:    monthPager.gap
                                accent:     panel.accent
                                // While an event is being written the ring marks ITS day.
                                selected:   monthView.editing ? panel.draftDay : panel.pickedDay
                                dotsFor:    (y, m, d) => Calendar.sourcesOn(y, m, d).map(src => panel.sourceColor(src))
                                specialFor: (y, m, d) => Calendar.specialOn(y, m, d)[0] ?? null
                                onPicked:   (y, m, d) => {
                                    if (monthView.editing) panel.setDraftDay(y, m, d)
                                    else panel.pickDay(y, m, d)
                                    // A neighbour's day: its own month comes into view.
                                    if (m !== page.first.getMonth()) monthPager.goToDay(new Date(y, m, d).getTime())
                                }
                            }
                        }
                    }
                }

                // ── The mouse wheel ───────────────────────────────────
                // Over the pages, taking ONLY the wheel: no buttons are
                // accepted, so presses and hovers reach the days beneath. A
                // handler inside the ListView lost the wheel to the list's own
                // pixel scrolling. One month per notch, accumulated so a
                // trackpad's stream of small deltas doesn't race through a year.
                // The middle button takes you back to now (Caelestia's calendar does the
                // same); the other buttons are left for the days beneath.
                MouseArea {
                    anchors.fill: parent
                    z: 1
                    acceptedButtons: Qt.MiddleButton
                    onClicked: panel.backToNow()
                    property real acc: 0
                    onWheel: (wheel) => {
                        acc += wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
                        if (Math.abs(acc) < 120) return
                        monthPager.step(acc > 0 ? -1 : 1)
                        acc = 0
                    }
                }

                // A month up or down, for anyone without a wheel.
                ChipTray {
                    anchors.right: parent.right
                    anchors.top:   parent.top
                    z: 2

                    ChipButton {
                        symbol:  "keyboard_arrow_up"
                        tint:    panel.accent
                        enabled: monthPager.index > 0
                        onActivated: monthPager.step(-1)
                    }
                    ChipButton {
                        symbol:  "keyboard_arrow_down"
                        tint:    panel.accent
                        enabled: monthPager.index < monthPager.span * 2
                        onActivated: monthPager.step(1)
                    }
                }
            }
        }

        // ── The agenda — or the editor ────────────────────────────
        Rectangle {
            id: sideCard
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: Math.max(monthView.monthH,
                                             agendaCol.implicitHeight + Tokens.spacingMd * 2,
                                             monthView.editing ? editCol.implicitHeight + Tokens.spacingMd * 2 : 0)
            radius: Tokens.radiusCard
            color: Colors.of(QsWindow.window).section
            opacity: 0
            ViewEnter { target: sideCard; active: monthView.shown; delay: panel.lead + Motion.respond; rise: Tokens.spacingMd }

            // ── Agenda ────────────────────────────────────────────
            Item {
                id: agendaView
                anchors.fill: parent
                anchors.margins: Tokens.spacingMd
                opacity: monthView.editing ? 0 : 1
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                ColumnLayout {
                    id: agendaCol
                    anchors.fill: parent
                    spacing: Tokens.spacingSm
                    opacity: 0
                    ViewEnter { target: agendaCol; active: monthView.shown && !monthView.editing; delay: panel.lead + Motion.respond; rise: Tokens.spacingSm }

                    // ── The time, the date, add ───────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingMd

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: 0

                            FontMetrics { id: calBigMetrics;   font.family: Tokens.fontBlock; font.pixelSize: Tokens.fontDisplay; font.weight: Font.Bold }
                            FontMetrics { id: calSmallMetrics; font.family: Tokens.fontBlock; font.pixelSize: Tokens.fontTitle }

                            Row {
                                RollText {
                                    text: Qt.formatDateTime(panel.now, "HH:mm")
                                    family:    Tokens.fontBlock
                                    pixelSize: Tokens.fontDisplay
                                    weight:    Font.Bold
                                }
                                RollText {
                                    // Shares the big digits' baseline.
                                    y: calBigMetrics.ascent - calSmallMetrics.ascent
                                    text: ":" + Qt.formatDateTime(panel.now, "ss")
                                    family:    Tokens.fontBlock
                                    pixelSize: Tokens.fontTitle
                                    color:     panel.accent
                                }
                            }
                            // The date, the ISO week, and the moon — what the two facts rows
                            // used to say, on the one line.
                            Row {
                                spacing: Tokens.spacingSm
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Qt.formatDate(panel.now, "ddd, d MMM") + "  ·  Week " + panel.dayFacts.week
                                    variant: "caption"
                                    emphasis: "dim"
                                }
                                ClockMoon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width:  Tokens.iconSm
                                    height: Tokens.iconSm
                                    phase: panel.dayFacts.moon.phase
                                    southern: Weather.hasLocation && Weather.lat < 0
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Math.round(panel.dayFacts.moon.illumination * 100) + "%"
                                    variant: "caption"
                                    emphasis: "dim"
                                }
                            }
                        }

                        ChipTray {
                            Layout.alignment: Qt.AlignTop
                            ChipButton {
                                symbol:  "add"
                                tint:    panel.accent
                                enabled: Calendar.localWritable
                                onActivated: panel.openEditor("", panel.agendaFrom)
                            }
                        }
                    }

                    // ── The day, on a strip ───────────────────────────────
                    // 00 → 24 across; each timed event a bar (a second lane when they overlap),
                    // a line where now is. A bar of your own opens its editor.
                    RowLayout {
                        id: strip
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingMd

                        readonly property int laneH: Tokens.spacingMd
                        readonly property int pad: Tokens.spacingXs
                        readonly property int lanes: Plan.laneCount(panel.dayStrip)

                        StyledText {
                            Layout.preferredWidth: Math.max(stripMetrics.advanceWidth, stripMetricsB.advanceWidth)
                            text: panel.stripLabel
                            variant: "caption"
                            emphasis: "dim"
                            elide: Text.ElideRight

                            TextMetrics {
                                id: stripMetrics
                                font.pixelSize: Tokens.fontCaption
                                text: "10 events · from 00:00"
                            }
                            TextMetrics {
                                id: stripMetricsB
                                font.pixelSize: Tokens.fontCaption
                                text: Translation.tr("Nothing timed today")
                            }
                        }

                        Item {
                            id: track
                            Layout.fillWidth: true
                            // Grows a lane on a spring when a second row is needed.
                            property real h: strip.lanes * strip.laneH + (strip.lanes - 1) * strip.pad + strip.pad * 2
                            Behavior on h {
                                NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring }
                            }
                            Layout.preferredHeight: track.h

                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
                            }
                            // 06, 12 and 18 — enough to read a bar's hour without labels.
                            Repeater {
                                model: [0.25, 0.5, 0.75]
                                Rectangle {
                                    required property real modelData
                                    x: modelData * track.width
                                    y: strip.pad
                                    width: Tokens.borderWidth
                                    height: track.height - strip.pad * 2
                                    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.10)
                                }
                            }

                            Repeater {
                                model: panel.dayStrip

                                delegate: Rectangle {
                                    id: bar
                                    required property int index
                                    required property var modelData
                                    readonly property bool past: panel.nowFrac >= 0 && bar.modelData.end <= panel.nowFrac

                                    PopIn { id: barIn; active: monthView.shown && !monthView.editing; index: bar.index; delay: panel.lead + Motion.respond * 2 }

                                    x: bar.modelData.start * track.width
                                    y: strip.pad + bar.modelData.lane * (strip.laneH + strip.pad)
                                    width: Math.max(Tokens.spacingSm, (bar.modelData.end - bar.modelData.start) * track.width) * Math.min(1, barIn.arrive)
                                    height: strip.laneH
                                    radius: height / 2
                                    color: panel.sourceColor(bar.modelData.source)
                                    opacity: (bar.past ? 0.45 : 1) * barIn.opacity

                                    HoverHandler {
                                        id: barHover
                                        enabled: Calendar.localEvent(bar.modelData.uid) !== null
                                        cursorShape: Qt.PointingHandCursor
                                    }
                                    TapHandler {
                                        enabled: Calendar.localEvent(bar.modelData.uid) !== null
                                        onTapped: panel.openEditor(bar.modelData.uid, 0)
                                    }
                                }
                            }

                            // Now: a line, with a bead on top that leans over the track.
                            Rectangle {
                                visible: panel.nowFrac >= 0
                                x: panel.nowFrac * track.width - width / 2
                                y: -Tokens.borderWidth
                                width: Tokens.borderWidth * 2
                                height: track.height + Tokens.borderWidth * 2
                                radius: width / 2
                                color: panel.accent
                                Behavior on x { NumberAnimation { duration: Motion.spatial } }
                            }
                        }
                    }

                    // ── Next up ───────────────────────────────────────────
                    // The next timed event, in the accent — only when there is one.
                    ClockPill {
                        id: nextPill
                        Layout.fillWidth: false
                        Layout.maximumWidth: agendaCol.width
                        visible: panel.nextUp !== null
                        fill: Colors.of(QsWindow.window).alpha(panel.accent, 0.14)
                        popActive: monthView.shown && !monthView.editing
                        popIndex: 1; popDelay: panel.lead + Motion.respond

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: panel.nextUp && panel.nextUp.live ? "play_arrow" : "schedule"
                            fill: 1
                            font.pixelSize: Tokens.iconSm
                            color: panel.accent
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, agendaCol.width - Tokens.iconXl * 3)
                            text: panel.nextUp ? (panel.nextUp.summary !== "" ? panel.nextUp.summary : "(untitled)") : ""
                            variant: "caption"
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: panel.nextUp ? panel.nextUp.when : ""
                            variant: "caption"
                            color: panel.accent
                        }
                    }

                    // ── Reminders, then the days ahead ────────────────────
                    // A plain Item between the layout and the Flickable: the Scrollbar
                    // anchors itself to the Flickable's parent, and a layout would
                    // fight those anchors.
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: Tokens.iconXl * 2
                        Layout.minimumHeight: Tokens.iconXl * 2

                        Flickable {
                            id: agendaList
                            anchors.fill: parent
                            clip: true
                            contentHeight: agendaColumn.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds

                            Column {
                                id: agendaColumn
                                width: agendaList.width - Tokens.spacingMd
                                spacing: Tokens.spacingSm

                                // ── Reminders ─────────────────────────
                                Column {
                                    id: remBlock
                                    width: agendaColumn.width
                                    visible: Reminders.sorted.length > 0
                                    spacing: 0

                                    Row {
                                        spacing: Tokens.spacingSm
                                        // Rings — a short shake, then rest — while anything is overdue.
                                        MaterialIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            name: Reminders.overdueCount > 0 ? "notifications_active" : "notifications"
                                            fill: 1
                                            font.pixelSize: Tokens.iconSm
                                            color: Reminders.overdueCount > 0 ? Colors.of(QsWindow.window).danger : panel.accent
                                            SequentialAnimation on rotation {
                                                running: Reminders.overdueCount > 0 && Config.motionEnabled && monthView.shown
                                                loops: Animation.Infinite
                                                NumberAnimation { to: 14;  duration: Motion.fast }
                                                NumberAnimation { to: -14; duration: Motion.fast }
                                                NumberAnimation { to: 0;   duration: Motion.fast }
                                                PauseAnimation  { duration: Motion.slow * 4 }
                                            }
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Translation.tr("Reminders")
                                            variant: "caption"
                                            font.bold: true
                                            color: Colors.of(QsWindow.window).fgMuted
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: Reminders.openCount > 0
                                            text: Reminders.openCount
                                            variant: "caption"
                                            emphasis: "dim"
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: Reminders.overdueCount > 0
                                            text: "·  " + Reminders.overdueCount + " overdue"
                                            variant: "caption"
                                            color: Colors.of(QsWindow.window).danger
                                        }
                                    }

                                    Repeater {
                                        // Empty until the page has been visited: see the header.
                                        model: panel.calendarSeen ? Reminders.sorted.slice(0, panel.maxReminders) : []

                                        delegate: Item {
                                            id: rem
                                            required property int index
                                            required property var modelData
                                            readonly property bool overdue: {
                                                Clock.minutes
                                                return !modelData.done && modelData.due > 0 && modelData.due <= Date.now()
                                            }

                                            // Rows that exist when the page arrives cascade in; one made
                                            // later (a reminder just added) is simply there.
                                            property bool late: false
                                            Component.onCompleted: rem.late = panel.calSettled
                                            PopIn { id: remPop; active: panel.calendarOn && !rem.late; index: rem.index; delay: panel.lead + Motion.respond * 2 }
                                            opacity: rem.late ? 1 : remPop.opacity
                                            scale:   rem.late ? 1 : remPop.scale

                                            width: remBlock.width
                                            height: Tokens.iconXl + Tokens.spacingSm

                                            HoverHandler {
                                                id: remHover
                                            }

                                            // The tick: fills and springs when it's done.
                                            MaterialIcon {
                                                id: tick
                                                anchors.left: parent.left
                                                anchors.verticalCenter: parent.verticalCenter
                                                name: rem.modelData.done ? "check_circle" : "radio_button_unchecked"
                                                fill: rem.modelData.done ? 1 : 0
                                                font.pixelSize: Tokens.iconMd
                                                color: rem.modelData.done ? Colors.of(QsWindow.window).success
                                                     : rem.overdue        ? Colors.of(QsWindow.window).danger
                                                     :                      panel.accent
                                                scale: tickHover.hovered ? 1.2 : 1
                                                Behavior on scale {
                                                    NumberAnimation {
                                                        duration: Motion.spatial
                                                        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring
                                                    }
                                                }
                                                Behavior on color { ColorAnimation { duration: Motion.standard } }

                                                HoverHandler { id: tickHover; cursorShape: Qt.PointingHandCursor }
                                                TapHandler   { onTapped: Reminders.toggle(rem.modelData.id) }
                                            }

                                            // One line: the words, and when. The text gives way to the tray as it springs in.
                                            RowLayout {
                                                anchors.left: tick.right
                                                anchors.leftMargin: Tokens.spacingSm
                                                anchors.right: parent.right
                                                anchors.rightMargin: remTray.width * remTray.pop + (remTray.pop > 0.01 ? Tokens.spacingSm : 0)
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: Tokens.spacingSm
                                                opacity: rem.modelData.done ? 0.5 : 1
                                                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: rem.modelData.text
                                                    variant: "label"
                                                    font.strikeout: rem.modelData.done
                                                    elide: Text.ElideRight
                                                }
                                                StyledText {
                                                    visible: text !== "" && !rem.modelData.done
                                                    text: Reminders.dueLabel(rem.modelData)
                                                    variant: "caption"
                                                    color: rem.overdue ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgDim
                                                }
                                            }

                                            // On hover: snooze a timed one fifteen minutes, or remove.
                                            HoverTray {
                                                id: remTray
                                                anchors.right: parent.right
                                                anchors.verticalCenter: parent.verticalCenter
                                                shown: remHover.hovered

                                                ChipButton {
                                                    visible: !rem.modelData.done && rem.modelData.due > 0
                                                    symbol:  "snooze"
                                                    tint:    panel.accent
                                                    onActivated: Reminders.snooze(rem.modelData.id, 15)
                                                }
                                                ChipButton {
                                                    symbol:  "close"
                                                    tint:    Colors.of(QsWindow.window).danger
                                                    onActivated: Reminders.remove(rem.modelData.id)
                                                }
                                            }
                                        }
                                    }

                                    StyledText {
                                        visible: Reminders.sorted.length > panel.maxReminders
                                        text: "+ " + (Reminders.sorted.length - panel.maxReminders) + " more"
                                        variant: "caption"
                                        emphasis: "dim"
                                    }
                                }

                                // ── The days ahead ────────────────────
                                Repeater {
                                    model: panel.calendarSeen ? panel.agenda : []

                                    // A new set of days — picking a day rebuilds this — cascades in.
                                    delegate: Column {
                                        id: agDay
                                        required property int index
                                        required property var modelData
                                        readonly property bool isToday: modelData.day === panel.todayMs

                                        width: agendaColumn.width
                                        spacing: Tokens.spacingXs

                                        PopIn { id: agPop; active: panel.calendarOn; index: agDay.index; delay: panel.lead + Motion.respond * 2 }
                                        opacity: agPop.opacity
                                        scale:   agPop.scale

                                        StyledText {
                                            text: panel.dayTitle(agDay.modelData.day)
                                            variant: "caption"
                                            font.bold: true
                                            color: agDay.isToday ? panel.accent : Colors.of(QsWindow.window).fgMuted
                                        }

                                        StyledText {
                                            visible: agDay.modelData.items.length === 0 && agDay.modelData.specials.length === 0
                                            text: Translation.tr("Nothing planned")
                                            variant: "caption"
                                            emphasis: "dim"
                                        }

                                        // ── Special dates ─────────────
                                        Repeater {
                                            model: agDay.modelData.specials

                                            delegate: RowLayout {
                                                id: sp
                                                required property var modelData
                                                width: agDay.width
                                                spacing: Tokens.spacingSm

                                                MaterialIcon {
                                                    Layout.alignment: Qt.AlignTop
                                                    name: panel.specialIcon(sp.modelData.kind)
                                                    fill: 1
                                                    font.pixelSize: Tokens.iconSm
                                                    color: panel.specialTint(sp.modelData.kind)
                                                }
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: false
                                                    spacing: 0

                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: sp.modelData.name
                                                        variant: "label"
                                                        color: sp.modelData.kind === "national" ? Colors.of(QsWindow.window).fg : Colors.of(QsWindow.window).fgMuted
                                                        elide: Text.ElideRight
                                                    }
                                                    StyledText {
                                                        Layout.fillWidth: true
                                                        text: H.kindLabel(sp.modelData.kind)
                                                            + (sp.modelData.english !== "" ? "  ·  " + sp.modelData.english : "")
                                                        variant: "caption"
                                                        emphasis: "dim"
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                            }
                                        }

                                        // ── Your events ───────────────
                                        Repeater {
                                            model: agDay.modelData.items

                                            delegate: Item {
                                                id: ev
                                                required property var modelData
                                                readonly property bool past: {
                                                    Clock.minutes
                                                    return modelData.end <= Date.now() && modelData.end > modelData.start
                                                }
                                                // Yours open the editor; a subscribed calendar's are read-only.
                                                readonly property bool mine: modelData.source === "local"

                                                width: agDay.width
                                                height: evRow.implicitHeight + Tokens.spacingXs * 2

                                                // A wash under the pointer: this row opens the editor.
                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: Tokens.radiusXs
                                                    color: Colors.of(QsWindow.window).alpha(panel.accent, 0.10)
                                                    opacity: ev.mine && evHover.hovered ? 1 : 0
                                                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                                }

                                                RowLayout {
                                                    id: evRow
                                                    anchors.left:  parent.left
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.leftMargin: Tokens.spacingXs
                                                    anchors.rightMargin: Tokens.spacingXs
                                                    spacing: Tokens.spacingSm
                                                    opacity: ev.past ? 0.5 : 1

                                                    MaterialIcon {
                                                        Layout.alignment: Qt.AlignTop
                                                        name: ev.modelData.recurring ? "repeat" : "event"
                                                        fill: 1
                                                        font.pixelSize: Tokens.iconSm
                                                        color: panel.sourceColor(ev.modelData.source)
                                                    }
                                                    ColumnLayout {
                                                        Layout.fillWidth: true
                                                        Layout.fillHeight: false
                                                        spacing: 0

                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            text: ev.modelData.summary !== "" ? ev.modelData.summary : "(untitled)"
                                                            variant: "label"
                                                            color: ev.mine && evHover.hovered ? panel.accent : Colors.of(QsWindow.window).fg
                                                            elide: Text.ElideRight
                                                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                                                        }
                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            text: {
                                                                const o = ev.modelData
                                                                const bits = []
                                                                if (o.allDay) bits.push("All day")
                                                                else {
                                                                    const s = new Date(o.start), e = new Date(o.end)
                                                                    bits.push(Qt.formatTime(s, "HH:mm") + (o.end > o.start
                                                                        ? "–" + (s.toDateString() === e.toDateString()
                                                                                 ? Qt.formatTime(e, "HH:mm") : Qt.formatDateTime(e, "ddd HH:mm"))
                                                                        : ""))
                                                                }
                                                                if (o.location !== "") bits.push(o.location)
                                                                if (!ev.mine && Calendar.feedName(o.source) !== "") bits.push(Calendar.feedName(o.source))
                                                                return bits.join("  ·  ")
                                                            }
                                                            variant: "caption"
                                                            emphasis: "dim"
                                                            elide: Text.ElideRight
                                                        }
                                                    }
                                                    MaterialIcon {
                                                        opacity: ev.mine && evHover.hovered ? 1 : 0
                                                        name: "edit"
                                                        font.pixelSize: Tokens.iconSm
                                                        color: panel.accent
                                                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                                    }
                                                }

                                                HoverHandler { id: evHover; cursorShape: ev.mine ? Qt.PointingHandCursor : Qt.ArrowCursor }
                                                TapHandler   { enabled: ev.mine; onTapped: panel.openEditor(ev.modelData.uid, 0) }
                                            }
                                        }
                                    }
                                }

                                // ── The footnotes: the next special date, and why there are none ──
                                RowLayout {
                                    width: agendaColumn.width
                                    visible: panel.nextSpecialText !== ""
                                    spacing: Tokens.spacingSm

                                    MaterialIcon {
                                        name: "celebration"
                                        fill: 1
                                        font.pixelSize: Tokens.iconSm
                                        color: Colors.of(QsWindow.window).warning
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: panel.nextSpecialText
                                        variant: "caption"
                                        emphasis: "dim"
                                        elide: Text.ElideRight
                                    }
                                }
                                StyledText {
                                    width: agendaColumn.width
                                    visible: Calendar.country === ""
                                    text: Translation.tr("Set a weather location to see its country's holidays.")
                                    variant: "caption"
                                    emphasis: "dim"
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        Scrollbar { flickable: agendaList }
                    }

                    // Only when there is something to say; it costs the list a line while it does:
                    // that it was added, what the line is understood as, or what is wrong.
                    StyledText {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: panel.reminderError !== "" ? panel.reminderError
                            : panel.quickFlash !== ""    ? panel.quickFlash
                            : panel.quickPreview !== ""  ? panel.quickPreview
                            : Calendar.error
                        variant: "caption"
                        elide: Text.ElideRight
                        color: panel.reminderError !== "" ? Colors.of(QsWindow.window).danger
                             : panel.quickFlash !== ""    ? Verdict.tint(true)
                             : panel.quickPreview !== ""  ? panel.accent
                             :                             Colors.of(QsWindow.window).warning
                    }

                    // ── Quick add ─────────────────────────────────────────
                    // The words, and when — one chip that steps through the choices, and
                    // a time box only for "At…" (on the agenda's day: the picked day, or today).
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm

                        InputField {
                            id: reminderField
                            Layout.fillWidth: true
                            implicitHeight: Tokens.iconXl + Tokens.spacingMd
                            cornerRadius: implicitHeight / 2
                            icon: "add"
                            placeholder: Translation.tr("Add… e.g. dentist tomorrow 9am")
                            invalid: panel.reminderError !== ""
                            onEdited: (value) => { panel.reminderText = value; panel.reminderError = ""; panel.quickFlash = "" }
                            onAccepted: panel.submitQuick()
                            onKeyPressed: (event) => { if (event.key === Qt.Key_Escape) { reminderField.blur(); event.accepted = true } }
                        }
                        InputField {
                            id: reminderTimeField
                            visible: panel.reminderWhen === "at" && !panel.quickParsed
                            Layout.preferredWidth: Tokens.iconXl * 2 + Tokens.spacingLg
                            implicitHeight: Tokens.iconXl + Tokens.spacingMd
                            cornerRadius: implicitHeight / 2
                            mono: true
                            placeholder: "18:30"
                            invalid: panel.reminderTime.trim() !== "" && Ics.parseTime(panel.reminderTime) === null
                            onEdited: (value) => { panel.reminderTime = value; panel.reminderError = "" }
                            onAccepted: panel.addReminder()
                            onKeyPressed: (event) => { if (event.key === Qt.Key_Escape) { reminderTimeField.blur(); event.accepted = true } }
                        }
                        ChipTray {
                            // A line that names a moment is an event or a reminder, your pick;
                            // one that doesn't is a reminder, timed by this chip.
                            ChipButton {
                                visible: panel.quickParsed
                                symbol:  panel.quickAs === "event" ? "event" : "notifications"
                                label:   panel.quickAs === "event" ? "Event" : "Reminder"
                                tint:    panel.accent
                                enabled: panel.quick.repeat === ""
                                onActivated: panel.quickKind = panel.quickKind === "event" ? "reminder" : "event"
                            }
                            ChipButton {
                                visible: !panel.quickParsed
                                symbol:  "schedule"
                                label:   panel.whenLabel
                                tint:    panel.accent
                                onActivated: panel.cycleWhen()
                            }
                            // Lit once there is something to add.
                            ChipButton {
                                symbol:  "check"
                                on:      panel.reminderText.trim() !== ""
                                tint:    panel.accent
                                enabled: panel.reminderText.trim() !== ""
                                onActivated: panel.submitQuick()
                            }
                        }
                    }
                }
            }

            // ── Editor ────────────────────────────────────────────
            Item {
                id: editView
                anchors.fill: parent
                anchors.margins: Tokens.spacingMd
                opacity: monthView.editing ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                ArmLatch {
                    id: deleteLatch
                    onConfirmed: panel.deleteDraft()
                }

                ColumnLayout {
                    id: editCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: Tokens.spacingSm
                    opacity: 0
                    ViewEnter { target: editCol; active: monthView.shown && monthView.editing; rise: Tokens.spacingSm }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm

                        ChipTray {
                            ChipButton {
                                symbol: "arrow_back"
                                tint:   panel.accent
                                onActivated: panel.calView = "month"
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: panel.draftUid !== "" ? "Edit event" : "New event"
                            variant: "label"
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            text: Translation.tr("All day")
                            variant: "caption"
                            emphasis: "dim"
                        }
                        Toggle {
                            checked: panel.draftAllDay
                            accent:  panel.accent
                            onToggled: panel.draftAllDay = !panel.draftAllDay
                        }
                    }

                    InputField {
                        id: titleField
                        Layout.fillWidth: true
                        implicitHeight: Tokens.iconXl + Tokens.spacingMd
                        cornerRadius: implicitHeight / 2
                        icon: "event"
                        placeholder: Translation.tr("Title")
                        onEdited: (value) => { panel.draftSummary = value; panel.draftError = "" }
                        onAccepted: panel.saveDraft()
                        onKeyPressed: (event) => { if (event.key === Qt.Key_Escape) { panel.calView = "month"; event.accepted = true } }
                    }

                    // ── When ──────────────────────────────────────────
                    // The day is the one ringed on the month: click another to move it.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm

                        ClockPill {
                            fill: Colors.of(QsWindow.window).alpha(panel.accent, 0.14)
                            popActive: monthView.shown && monthView.editing
                            popDelay: Motion.respond

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "event"
                                fill: 1
                                font.pixelSize: Tokens.iconSm
                                color: panel.accent
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Qt.formatDate(new Date(panel.draftDay), "ddd, d MMM yyyy")
                                variant: "caption"
                                font.weight: Font.DemiBold
                            }
                        }
                        InputField {
                            id: startField
                            visible: !panel.draftAllDay
                            Layout.fillWidth: true
                            implicitHeight: Tokens.iconXl + Tokens.spacingMd
                            cornerRadius: implicitHeight / 2
                            mono: true
                            placeholder: "09:00"
                            invalid: panel.draftStart.trim() !== "" && Ics.parseTime(panel.draftStart) === null
                            onEdited: (value) => { panel.draftStart = value; panel.draftError = "" }
                            onAccepted: panel.saveDraft()
                            onKeyPressed: (event) => { if (event.key === Qt.Key_Escape) { panel.calView = "month"; event.accepted = true } }
                        }
                        StyledText { visible: !panel.draftAllDay; text: "–"; variant: "caption"; emphasis: "dim" }
                        InputField {
                            id: endField
                            visible: !panel.draftAllDay
                            Layout.fillWidth: true
                            implicitHeight: Tokens.iconXl + Tokens.spacingMd
                            cornerRadius: implicitHeight / 2
                            mono: true
                            placeholder: "10:00"
                            invalid: panel.draftEnd.trim() !== "" && Ics.parseTime(panel.draftEnd) === null
                            onEdited: (value) => { panel.draftEnd = value; panel.draftError = "" }
                            onAccepted: panel.saveDraft()
                            onKeyPressed: (event) => { if (event.key === Qt.Key_Escape) { panel.calView = "month"; event.accepted = true } }
                        }
                        Item { Layout.fillWidth: true; visible: panel.draftAllDay }
                    }

                    InputField {
                        id: locationField
                        Layout.fillWidth: true
                        implicitHeight: Tokens.iconXl + Tokens.spacingMd
                        cornerRadius: implicitHeight / 2
                        icon: "location_on"
                        placeholder: Translation.tr("Location (optional)")
                        onEdited: (value) => panel.draftLocation = value
                        onAccepted: panel.saveDraft()
                        onKeyPressed: (event) => { if (event.key === Qt.Key_Escape) { panel.calView = "month"; event.accepted = true } }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm

                        MaterialIcon {
                            Layout.alignment: Qt.AlignTop
                            name: "repeat"
                            variant: "label"
                            color: Colors.of(QsWindow.window).fgDim
                        }
                        ChipRow {
                            accent:  panel.accent
                            current: panel.draftRepeat
                            model: [
                                { value: "",        label: "Never"   },
                                { value: "DAILY",   label: "Daily"   },
                                { value: "WEEKLY",  label: "Weekly"  },
                                { value: "MONTHLY", label: "Monthly" },
                                { value: "YEARLY",  label: "Yearly"  }
                            ]
                            onPicked: (value) => panel.draftRepeat = value
                        }
                    }

                    // ── Actions ───────────────────────────────────────
                    // The message shares the row with the buttons, so an error costs no height.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm

                        ChipTray {
                            groupShown: panel.draftUid !== ""
                            ChipButton {
                                symbol: "delete"
                                label:  deleteLatch.armed ? "Delete?" : ""
                                on:     deleteLatch.armed
                                tint:   Colors.of(QsWindow.window).danger
                                onActivated: deleteLatch.trigger()
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: panel.draftError !== "" ? panel.draftError
                                : !Calendar.localWritable ? Calendar.localError
                                : panel.draftUid !== "" && panel.draftRepeat !== "" ? "Changes apply to every repeat."
                                : ""
                            variant: "caption"
                            color: panel.draftError !== "" || !Calendar.localWritable
                                   ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgDim
                            elide: Text.ElideRight
                        }
                        ChipTray {
                            ChipButton {
                                symbol:  "check"
                                label:   Translation.tr("Save")
                                on:      true
                                tint:    panel.accent
                                enabled: Calendar.localWritable
                                onActivated: panel.saveDraft()
                            }
                        }
                    }
                }
            }
        }
    }
}
