import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"
import "../services"

// ── MonthGrid ─────────────────────────────────────────────────────────────────
// One month: a prev/next header, Monday-first weekday names, and 42 day cells.
// Today is a filled accent chip, the picked day a ring, a day with events carries a
// dot, a holiday is tinted and names itself on hover.
//
// Presentation only. It doesn't know where events or holidays come from — the
// caller hands in `countFor` / `holidayFor` — so the clock panel and the overview's
// calendar can share it without either owning the other's data.
//
// ── Motion ────────────────────────────────────────────────────────────────────
// Paging slides the days in from the side you're heading towards, so "next" reads
// as travel rather than a redraw. The scroll wheel pages too, accumulated to whole
// notches so a trackpad's stream of small deltas doesn't flick through a year. The
// picked-day ring springs in rather than appearing.
//
// ── The neighbours, the weekend, and one ring ─────────────────────────────────
// Three touches borrowed in spirit from Caelestia's calendar (behaviour only; this is this
// shell's own code):
//   · `showAdjacent`: the days of the months either side fill the first and last rows,
//     dimmed, instead of leaving blank cells. They are real days — clicking one picks it
//     (`picked` carries ITS year / month / day) and its dots and holiday show.
//   · `weekendTint`: Saturday and Sunday (names and numbers) lean toward the accent, so a
//     week reads at a glance.
//   · The picked-day ring is ONE ring that springs from cell to cell, not a ring that
//     appears on each. When the pick is on another page it fades out here and in there.
//
// ── Always six rows ───────────────────────────────────────────────────────────
// A month starting on Sunday needs six week-rows where one starting on Monday needs
// five. A grid that breathed as you paged would resize whatever holds it (the
// overview rescales its whole workspace grid off the bottom row's height), so the
// height is fixed at 42 cells, every month.
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root

    // The month on show. Owned here — the header pages it — and seeded from the
    // clock once (`new Date()` isn't reactive, so this isn't a binding to break).
    property int year:  new Date().getFullYear()
    property int month: new Date().getMonth()

    property int   cellSize: Tokens.iconXl + Tokens.spacingSm
    property int   cellGap:  Tokens.spacingXs
    property color accent:   Colors.of(QsWindow.window).primary

    // Local-midnight ms of the picked day, or -1.
    property double selected: -1

    // function(y, m, d) → int / string. m is 0-based. Null means "none".
    property var countFor:   null
    property var holidayFor: null
    // function(y, m, d) → [color, …]: one dot per source that day, in its colour, at
    // most three. Wins over countFor's single accent dot when set.
    property var dotsFor:    null
    // function(y, m, d) → { name, kind } | null — a special date. kind is "national",
    // "regional" or "observance" (services/holidays.js), and decides how loudly the
    // day is marked. Wins over holidayFor when set.
    property var specialFor: null

    // The neighbouring months' days in the first / last row, dimmed.
    property bool showAdjacent: true
    // Saturday and Sunday lean toward the accent.
    property bool weekendTint: true

    // The header (month title, prev/next) and wheel paging. Off when something else
    // owns the month — a scroller that gives each month its own page.
    property bool navigation: true

    signal picked(int y, int m, int d)

    readonly property date now: Clock.now
    readonly property bool offMonth: root.month !== root.now.getMonth()
                                  || root.year  !== root.now.getFullYear()

    // -1 = came from the left (paged back), +1 = from the right.
    property int _dir: 0

    function prevMonth() { root._dir = -1; if (root.month === 0)  { root.month = 11; root.year-- } else root.month-- }
    function nextMonth() { root._dir = 1;  if (root.month === 11) { root.month = 0;  root.year++ } else root.month++ }
    function goToday() {
        const ty = root.now.getFullYear(), tm = root.now.getMonth()
        root._dir = (ty * 12 + tm) > (root.year * 12 + root.month) ? 1 : -1
        root.year = ty
        root.month = tm
    }

    onMonthChanged: slide.restart()

    readonly property int gridW: root.cellSize * 7 + root.cellGap * 6
    readonly property int gridH: root.cellSize * 6 + root.cellGap * 5

    // Always 42 of { y, m, d, adj }: `adj` marks a day of the month before or after, and with
    // showAdjacent off those are { d: 0 } blanks.
    readonly property var cells: {
        // Monday-first: JS getDay() is Sunday-0, so rotate.
        const offset = (new Date(root.year, root.month, 1).getDay() + 6) % 7
        const out = []
        for (let i = 0; i < 42; i++) {
            const dt = new Date(root.year, root.month, 1 - offset + i)
            const adj = dt.getMonth() !== root.month
            out.push(adj && !root.showAdjacent ? { y: 0, m: 0, d: 0, adj: true }
                                               : { y: dt.getFullYear(), m: dt.getMonth(), d: dt.getDate(), adj: adj })
        }
        return out
    }

    // Where the picked day sits in `cells` (this month's own days only), or -1.
    readonly property int selectedIndex: {
        if (root.selected < 0) return -1
        for (let i = 0; i < 42; i++) {
            const c = root.cells[i]
            if (!c.adj && c.d > 0 && new Date(c.y, c.m, c.d).getTime() === root.selected) return i
        }
        return -1
    }

    spacing: Tokens.spacingSm

    property real _wheel: 0
    WheelHandler {
        enabled: root.navigation
        onWheel: (event) => {
            root._wheel += event.angleDelta.y
            if (Math.abs(root._wheel) < 120) return
            if (root._wheel > 0) root.prevMonth(); else root.nextMonth()
            root._wheel = 0
        }
    }

    ParallelAnimation {
        id: slide
        NumberAnimation {
            target: daysShift; property: "x"
            from: root._dir * root.cellSize; to: 0
            duration: Motion.spatial
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel
        }
        NumberAnimation { target: days;  property: "opacity"; from: 0; to: 1; duration: Motion.spatial }
        NumberAnimation { target: title; property: "opacity"; from: 0; to: 1; duration: Motion.standard }
    }

    // ── Header ────────────────────────────────────────────────────────────────
    RowLayout {
        Layout.preferredWidth: root.gridW
        Layout.fillWidth: false
        Layout.fillHeight: false
        visible: root.navigation
        spacing: Tokens.spacingSm

        PanelButton {
            variant: "ghost"
            accent:  root.accent
            symbol:  "chevron_left"
            onActivated: root.prevMonth()
        }
        StyledText {
            id: title
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Qt.locale().standaloneMonthName(root.month) + " " + root.year
            variant: "label"
            font.weight: Font.DemiBold
        }
        PanelButton {
            variant: "ghost"
            accent:  root.accent
            symbol:  "chevron_right"
            onActivated: root.nextMonth()
        }
    }

    // ── Weekday names ─────────────────────────────────────────────────────────
    Row {
        Layout.preferredWidth: root.gridW
        spacing: root.cellGap

        Repeater {
            // 2024-01-01 was a Monday, so day offset i is the i-th weekday from Monday.
            model: 7
            StyledText {
                required property int index
                width: root.cellSize
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(new Date(2024, 0, 1 + index), "ddd").slice(0, 2)
                variant: "micro"
                color: root.weekendTint && index >= 5 ? root.weekendColor : Colors.of(QsWindow.window).fgDim
                font.bold: true
            }
        }
    }

    readonly property color weekendColor: Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).fg, root.accent, 0.55)

    // ── Days ──────────────────────────────────────────────────────────────────
    // The cells sit in a Grid; the ring is a sibling of it (a child of the Grid would be laid
    // out as a 43rd cell), placed by arithmetic on the same cell and gap.
    Item {
        id: days
        Layout.preferredWidth:  root.gridW
        Layout.preferredHeight: root.gridH
        transform: Translate { id: daysShift }

        // ── The picked day's ring ─────────────────────────────────────────────
        // One ring that travels, on a spring. It only animates while it is already showing:
        // when the pick arrives from another page (or there was none) it appears where it
        // belongs, fading in, rather than flying in from wherever it last was.
        Rectangle {
            id: pick
            z: 1
            readonly property int at: root.selectedIndex
            readonly property bool shown: pick.at >= 0
            width:  root.cellSize
            height: root.cellSize
            radius: width / 2
            color: "transparent"
            border.width: Tokens.borderWidth * 2
            border.color: root.accent
            x: (Math.max(0, pick.at) % 7) * (root.cellSize + root.cellGap)
            y: Math.floor(Math.max(0, pick.at) / 7) * (root.cellSize + root.cellGap)
            opacity: pick.shown ? 1 : 0
            scale:   pick.shown ? 1 : 0.6
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: Motion.standard } }
            Behavior on scale {
                NumberAnimation {
                    duration: Motion.spatial
                    easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring
                }
            }
            Behavior on x {
                enabled: pick.opacity > 0.5
                SpringAnimation { spring: 5.5; damping: 0.34; epsilon: 0.1 }
            }
            Behavior on y {
                enabled: pick.opacity > 0.5
                SpringAnimation { spring: 5.5; damping: 0.34; epsilon: 0.1 }
            }
        }

        Grid {
            id: grid
            columns: 7
            spacing: root.cellGap

            Repeater {
                model: root.cells

                Item {
                    id: day
                    required property int index
                    required property var modelData

                    readonly property int d: modelData.d
                    readonly property bool adj: modelData.adj
                    readonly property bool weekend: day.index % 7 >= 5
                    readonly property bool isToday: d > 0 && !adj && d === root.now.getDate() && !root.offMonth
                    readonly property var special: d > 0 && root.specialFor ? root.specialFor(modelData.y, modelData.m, d) : null
                    readonly property string holiday: day.special ? day.special.name
                                                    : d > 0 && root.holidayFor ? root.holidayFor(modelData.y, modelData.m, d) : ""
                    // How loudly the day is marked: a national holiday in full warning, a
                    // regional one softer, an observance in info. A bare holidayFor name
                    // (no kind) reads as national.
                    readonly property color specialTint:
                          !day.special || day.special.kind === "national" ? Colors.of(QsWindow.window).warning
                        : day.special.kind === "regional"                 ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).warning, Colors.of(QsWindow.window).fgMuted, 0.45)
                        :                                                   Colors.of(QsWindow.window).info
                    readonly property int count: d > 0 && root.countFor ? root.countFor(modelData.y, modelData.m, d) : 0
                    readonly property var dots: d > 0 && root.dotsFor ? root.dotsFor(modelData.y, modelData.m, d) : []

                    width:  root.cellSize
                    height: root.cellSize
                    // A neighbour's day recedes — but not so far a dot or a holiday is lost.
                    opacity: day.adj ? 0.38 : 1

                    Rectangle {
                        anchors.centerIn: parent
                        width:  root.cellSize - Tokens.spacingSm
                        height: width
                        radius: width / 2
                        visible: day.d > 0
                        color: day.isToday      ? root.accent
                             : dayHover.hovered ? Colors.of(QsWindow.window).stateHoverBg
                             : "transparent"
                        Behavior on color { ColorAnimation { duration: Motion.respond } }

                        StyledText {
                            anchors.centerIn: parent
                            text: day.d > 0 ? day.d : ""
                            // Larger cells get the reading size rather than a caption
                            // floating in the middle of a big chip.
                            variant: root.cellSize >= Tokens.iconXl + Tokens.spacingMd ? "label" : "caption"
                            font.bold: day.isToday || (day.holiday !== "" && (!day.special || day.special.kind === "national"))
                            color: day.isToday          ? Colors.of(QsWindow.window).fgOnPrimary
                                 : day.holiday !== ""   ? day.specialTint
                                 : root.weekendTint && day.weekend ? root.weekendColor
                                 : Colors.of(QsWindow.window).fg
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Tokens.spacingXs
                            spacing: Tokens.borderWidth

                            Repeater {
                                model: day.dots.length ? day.dots : (day.count > 0 ? [root.accent] : [])

                                Rectangle {
                                    required property var modelData
                                    width:  Tokens.spacingXs + Tokens.borderWidth
                                    height: width
                                    radius: width / 2
                                    // On today's filled chip every dot turns to the chip's
                                    // foreground — a source colour there could vanish into it.
                                    color: day.isToday ? Colors.of(QsWindow.window).fgOnPrimary : modelData
                                }
                            }
                        }
                    }

                    HoverHandler {
                        id: dayHover
                        enabled: day.d > 0
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        enabled: day.d > 0
                        onTapped: root.picked(day.modelData.y, day.modelData.m, day.d)
                    }

                    // A holiday you can't name is just an oddly-coloured number.
                    Rectangle {
                        visible: day.holiday !== "" && dayHover.hovered
                        anchors.bottom: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        z: 50
                        width:  holidayName.implicitWidth + Tokens.spacingMd * 2
                        height: holidayName.implicitHeight + Tokens.spacingSm * 2
                        radius: Tokens.radiusXs
                        color: Colors.of(QsWindow.window).surfaceHigh
                        border.width: Tokens.borderWidth
                        border.color: Colors.of(QsWindow.window).outlineNested

                        StyledText {
                            id: holidayName
                            anchors.centerIn: parent
                            text: day.holiday
                                + (day.special && day.special.kind === "regional"   ? "  ·  regional"
                                 : day.special && day.special.kind === "observance" ? "  ·  observance" : "")
                            variant: "caption"
                            color: day.specialTint
                        }
                    }
                }
            }
        }
    }
}
