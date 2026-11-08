pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/calendar.js" as Cal

// ── CalendarWidget ────────────────────────────────────────────────────────────
// The month, with today marked.
//
// ── Small is not a shrunken month ─────────────────────────────────────────────
// At 168px a 7×6 grid is unreadable, so the small size answers a different question —
// "what is today" — the date, and the week around it. Squeezing the grid in would have
// produced a tile that is technically a calendar and practically a smudge.
//
// The week starts on the locale's first day, not on a hardcoded Monday: Qt.locale()
// already knows, and getting this wrong silently shifts every column by one.
Item {
    id: root

    required property var opts
    required property string size
    // Declared but unused here: the host passes the same property set to every widget
    // type, and an initial property with no matching declaration is an error.
    property int widgetId: -1
    property bool active: true
    // Set by the host from the widget's stored accent role. Defaults to the palette's
    // primary so a widget rendered outside the layer (a settings preview) still looks
    // right without the caller having to know about accents.
    property color accent: Colors.of(QsWindow.window).primary

    readonly property bool grid: root.size !== "small"

    // Binds to the shared clock; minute resolution is all that's needed to notice a
    // date change at midnight.
    readonly property date now: Clock.now

    // ── Which month is shown ──────────────────────────────────────────────────
    // A tap looks ahead one month and a second tap comes back. Two states rather than an
    // endless forward walk: "what is coming up" is the actual question a desktop
    // calendar gets asked, and any tile you can page indefinitely needs a way home that
    // a single tap cannot give you.
    //
    // NOT persisted, deliberately. It is a glance, not a setting — a tile still showing
    // next month a reboot later is a tile lying about the date.
    property int monthOffset: 0

    // The month actually DRAWN. It trails `monthOffset` by half a fade: the grid fades
    // out, this catches up at the midpoint, and the new month fades in (SwapFade). Bound
    // straight to monthOffset, the numbers would change before the old ones had left.
    property int viewOffset: 0

    // ── Pointing at a day ─────────────────────────────────────────────────────
    // `hoverDay` follows the pointer; `pickDay` is a day you clicked, which stays until
    // you click it again or change month. The readout shows the hovered day if there is
    // one and the picked day otherwise, so you can look without committing.
    property int hoverDay: 0
    property int pickDay: 0
    readonly property int focusDay: root.hoverDay > 0 ? root.hoverDay : root.pickDay
    onMonthOffsetChanged: { root.pickDay = 0; root.hoverDay = 0 }

    function tileTap() {
        // Small pages by WEEK, on the same two-state rule as the month: ahead, and home.
        if (!root.grid) { root.weekOffset = root.weekOffset === 0 ? 1 : 0; return }
        root.monthOffset = root.monthOffset === 0 ? 1 : 0
    }

    readonly property int today:     root.now.getDate()
    // The month being DRAWN, which is not necessarily the month it is.
    readonly property date shown:
        new Date(root.now.getFullYear(), root.now.getMonth() + root.viewOffset, 1)
    readonly property int month:     root.shown.getMonth()
    readonly property int year:      root.shown.getFullYear()
    readonly property int firstDow:  Qt.locale().firstDayOfWeek
    readonly property int daysInMonth: new Date(root.year, root.month + 1, 0).getDate()

    // How many blank cells lead the month, once the locale's first weekday is taken
    // into account. The +7 %7 keeps it positive when the locale starts on Sunday and
    // the month starts on Monday.
    readonly property int lead:
        (new Date(root.year, root.month, 1).getDay() - root.firstDow + 7) % 7

    // ── Days with something on them ───────────────────────────────────────────
    // Any countdown tile whose target date lands in the month being drawn gets a
    // dot under its cell — the desktop's own "you have something on this day",
    // without a calendar service. Keyed by day-of-month for an O(1) cell lookup; the
    // value is the countdown's label, which the readout shows when you point at the day.
    readonly property var markedDays: {
        const out = ({})
        for (const w of DesktopWidgets.shown) {
            if (w.type !== "countdown") continue
            const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec((w.opts ?? {}).date ?? "")
            if (!m) continue
            if (Number(m[1]) === root.year && Number(m[2]) - 1 === root.month)
                out[Number(m[3])] = (w.opts ?? {}).label || "Countdown"
        }
        return out
    }

    // What the header says about the day being pointed at: how far away it is and which
    // week it is in, plus the countdown that lands on it, if one does.
    readonly property string dayInfo: {
        if (root.focusDay <= 0) return ""
        const d = new Date(root.year, root.month, root.focusDay)
        const when = Cal.relative(Cal.daysBetween(root.now, d)) + "  ·  W" + Cal.isoWeek(d)
        const mark = root.markedDays[root.focusDay]
        if (!mark) return when
        return (mark.length > 14 ? mark.slice(0, 13) + "…" : mark) + "  ·  " + when
    }

    // The weekday column under the pointer, to light its initial.
    readonly property int hoverCol: root.hoverDay > 0 ? (root.hoverDay + root.lead - 1) % 7 : -1

    // The tile's own hover, for the header chip. A HoverHandler takes no press.
    HoverHandler { id: tileHover }

    // ── Small: today, and the week around it ──────────────────────────────────
    // The date is the answer to "what day is it"; the strip under it answers "and this
    // week?" — seven days from the locale's first weekday, today on a pill that GLIDES to
    // the next day at midnight, a dot under any day a countdown tile lands on. Point at a
    // day and the label up top says how far away it is. A tap looks ahead a week, a second
    // tap comes back (the month grid's rule, one size down).
    property int weekOffset: 0
    // The week actually DRAWN, trailing `weekOffset` by half a fade (as `viewOffset` does
    // for the month).
    property int viewWeek: 0
    onWeekOffsetChanged: root.stripHover = -1

    property int stripHover: -1

    readonly property date weekStart: {
        const t = root.now
        const back = (t.getDay() - root.firstDow + 7) % 7
        return new Date(t.getFullYear(), t.getMonth(), t.getDate() - back + root.viewWeek * 7)
    }
    readonly property var weekDays: {
        const out = []
        for (let i = 0; i < 7; i++)
            out.push(new Date(root.weekStart.getFullYear(), root.weekStart.getMonth(), root.weekStart.getDate() + i))
        return out
    }
    // Which cell is today, or -1 when the week shown is not this one.
    readonly property int todayCell: {
        const k = Cal.daysBetween(root.weekStart, root.now)
        return k >= 0 && k < 7 ? k : -1
    }

    // The countdown, if any, that lands on `d` (recurring ones included).
    function labelOn(d) {
        for (const w of DesktopWidgets.shown) {
            if (w.type !== "countdown") continue
            const o = w.opts ?? {}
            const t = Cal.nextDate(o.date, o.recurring === true, d)
            if (t && t.getFullYear() === d.getFullYear() && t.getMonth() === d.getMonth()
                  && t.getDate() === d.getDate())
                return o.label || "Countdown"
        }
        return ""
    }
    readonly property var weekMarks: root.weekDays.map(d => root.labelOn(d))
    // Your own events (the clock panel's calendar, calendar.ics) on each day of the week.
    // Read straight from the service: it loads the file as soon as it exists, so this
    // costs no network and no refcount.
    readonly property var weekEvents:
        root.weekDays.map(d => Calendar.eventsOn(d.getFullYear(), d.getMonth(), d.getDate()))

    // What the label above the date says: the day pointed at, else the weekday.
    readonly property string pointed: {
        if (root.stripHover < 0) return ""
        const d = root.weekDays[root.stripHover]
        const when = Cal.relative(Cal.daysBetween(root.now, d)).toUpperCase()
        const bits = []
        const evs = root.weekEvents[root.stripHover]
        if (evs.length === 1) bits.push(evs[0].summary || "Event")
        else if (evs.length > 1) bits.push(evs.length + " events")
        const mark = root.weekMarks[root.stripHover]
        if (mark) bits.push(mark)
        bits.push(when)
        return bits.join("  ·  ").toUpperCase()
    }

    ColumnLayout {
        anchors.fill: parent
        visible: !root.grid
        spacing: Tokens.spacingSm

        // ── The hero (Material 3 Expressive, 2026-10-30) ──────────────────────
        // Today's date INSIDE a tonal cookie, in the block face — the tile's one emphasised
        // thing — with the weekday, the month and the ISO week beside it. Pointing at a day
        // on the strip swaps those for the readout (how far away, what's on it).
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingMd

            Item {
                Layout.fillHeight: true
                Layout.preferredWidth: height
                Layout.maximumWidth: parent.width * 0.58

                MorphShape {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height)
                    height: width
                    spec: Motion.springSpatialFast
                    // A sun on next week (the strip has moved on), a cookie on this week.
                    shape: Config.barShape ? "squircle" : root.weekOffset !== 0 ? "sunny" : "cookie9"
                    fillColor: Colors.of(QsWindow.window).primaryContainer

                    // The date rolls over at midnight a digit at a time.
                    RollText {
                        anchors.centerIn: parent
                        text: String(root.today)
                        family: Tokens.fontBlock
                        weight: Font.ExtraBold
                        pixelSize: Math.round(parent.width * 0.42)
                        color: Colors.of(QsWindow.window).fgOnPrimaryContainer
                    }
                }
            }

            // The weekday, month and week — trading places with the readout for a pointed day.
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    opacity: root.stripHover < 0 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.weekOffset !== 0 ? "Next week"
                            : Qt.formatDateTime(root.now, "dddd")
                        variant: "label"
                        font.weight: Font.Bold
                        color: root.accent
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Qt.formatDateTime(root.now, "MMMM")
                        variant: "caption"
                        emphasis: "muted"
                        elide: Text.ElideRight
                    }
                    TilePill {
                        Layout.topMargin: Tokens.spacingXs
                        // The middle of the week: a week that starts on Sunday would otherwise report the
                        // ISO week of the Sunday, which belongs to the one before.
                        text: "W" + Cal.isoWeek(root.weekDays[3])
                    }
                }
                StyledText {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.pointed
                    variant: "caption"
                    color: root.accent
                    font.bold: true
                    wrapMode: Text.WordWrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    opacity: root.stripHover < 0 ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                }
            }
        }

        // ── The week ──────────────────────────────────────────────────────────
        Item {
            id: strip
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: Tokens.iconXl + Tokens.spacingSm
            readonly property real cellW: width / 7

            SwapFade {
                target: cells
                key: String(root.weekOffset)
                shownKey: String(root.viewWeek)
                onSwapped: root.viewWeek = root.weekOffset
            }

            // Under the pointer. One wash that slides between days, not a wash per day,
            // so moving along the strip reads as one thing following you.
            // Follows on the stiffest effects spring: no overshoot, ~0.1 s behind the hand.
            Rectangle {
                width: strip.cellW
                height: strip.height
                x: hoverX.value
                radius: Tokens.corner(Config.barShape, Tokens.radiusSm)
                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, Tokens.stateHover)
                opacity: root.stripHover < 0 ? 0 : 1
                SpringValue {
                    id: hoverX
                    spec: Motion.springEffectsFast
                    epsilon: 0.1
                    target: Math.max(0, root.stripHover) * strip.cellW
                }
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
            }

            // Today. One pill that moves, springing, when the day changes — and STRETCHES
            // while it travels (Material 3 Expressive's moving indicator): its width grows
            // with its speed and snaps back as it lands, so a day passing reads as the pill
            // being pulled across, not slid. Centred on where it is, so the stretch is even.
            Rectangle {
                readonly property real stretch: Math.min(strip.cellW * 0.6, Math.abs(todayX.velocity) * 0.04)
                width: strip.cellW + stretch
                height: strip.height
                x: todayX.value - stretch / 2
                radius: Tokens.corner(Config.barShape, Tokens.radiusSm)
                color: root.accent
                opacity: root.todayCell < 0 ? 0 : 1
                SpringValue {
                    id: todayX
                    spec: Motion.springSpatial
                    epsilon: 0.1
                    target: Math.max(0, root.todayCell) * strip.cellW
                }
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }
            }

            Row {
                id: cells
                anchors.fill: parent

                Repeater {
                    model: 7
                    Item {
                        id: day
                        required property int index
                        readonly property int dow: (root.firstDow + day.index) % 7
                        readonly property bool isToday: day.index === root.todayCell
                        readonly property bool weekend: day.dow === 0 || day.dow === 6
                        width: strip.cellW
                        height: strip.height

                        Column {
                            anchors.centerIn: parent
                            spacing: 0
                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Qt.locale().dayName(day.dow, Locale.NarrowFormat)
                                font.pixelSize: Tokens.fontCaption - 2
                                color: day.isToday ? Colors.of(QsWindow.window).fgOnPrimary
                                                   : Colors.of(QsWindow.window).fgDim
                            }
                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.weekDays[day.index].getDate()
                                variant: "caption"
                                font.bold: day.isToday
                                color: day.isToday ? Colors.of(QsWindow.window).fgOnPrimary
                                     : day.weekend ? Colors.of(QsWindow.window).fgDim
                                                   : Colors.of(QsWindow.window).fgMuted
                            }
                        }

                        // Something is on this day: an event in your calendar, or a countdown.
                        // One dot however many — the strip says THAT there is something,
                        // the label above says what.
                        Rectangle {
                            visible: !!root.weekMarks[day.index] || root.weekEvents[day.index].length > 0
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 2
                            width: 3; height: 3; radius: 1.5
                            antialiasing: true
                            color: day.isToday ? Colors.of(QsWindow.window).fgOnPrimary : root.accent
                        }
                    }
                }
            }

            // Hover only: a HoverHandler takes no press, so a tap anywhere on the strip
            // still reaches the tile and looks ahead a week.
            HoverHandler {
                id: stripPointer
                onHoveredChanged: if (!hovered) root.stripHover = -1
                onPointChanged: if (hovered)
                    root.stripHover = Math.max(0, Math.min(6, Math.floor(point.position.x / strip.cellW)))
            }
        }
    }

    // ── Medium / large: the month ─────────────────────────────────────────────
    // The hero (Material 3 Expressive, 2026-10-30): today in a tonal cookie, as on the
    // small tile — beside the month at medium, above it at large with today's events.
    // Today is what a glance at a calendar asks first; the grid answers the rest.
    readonly property var todayEvents: Calendar.eventsOn(root.now.getFullYear(), root.now.getMonth(), root.now.getDate())
    readonly property string todayLine: {
        const bits = []
        if (root.todayEvents.length === 1) bits.push(root.todayEvents[0].summary || "1 event")
        else if (root.todayEvents.length > 1) bits.push(root.todayEvents.length + " events")
        const mark = root.labelOn(root.now)
        if (mark) bits.push(mark)
        return bits.length > 0 ? bits.join("  ·  ") : "Nothing on today"
    }

    GridLayout {
        anchors.fill: parent
        visible: root.grid
        columns: root.size === "large" ? 1 : 2
        columnSpacing: Tokens.spacingLg
        rowSpacing: Tokens.spacingMd

        GridLayout {
            Layout.fillHeight: root.size !== "large"
            Layout.fillWidth: root.size === "large"
            Layout.preferredWidth: root.size === "large" ? -1 : Tokens.iconXl * 3 + Tokens.spacingLg
            columns: root.size === "large" ? 2 : 1
            columnSpacing: Tokens.spacingMd
            rowSpacing: Tokens.spacingXs

            Item {
                Layout.fillWidth: root.size !== "large"
                Layout.preferredWidth: root.size === "large" ? Tokens.iconXl * 3 : -1
                Layout.preferredHeight: root.size === "large" ? Tokens.iconXl * 3 : width
                Layout.alignment: Qt.AlignHCenter
                MorphShape {
                    anchors.centerIn: parent
                    width: Math.min(parent.width, parent.height)
                    height: width
                    spec: Motion.springSpatialFast
                    shape: Config.barShape ? "squircle" : "cookie9"
                    fillColor: Colors.of(QsWindow.window).primaryContainer
                    RollText {
                        anchors.centerIn: parent
                        text: String(root.today)
                        family: Tokens.fontBlock
                        weight: Font.ExtraBold
                        pixelSize: Math.round(parent.width * 0.42)
                        color: Colors.of(QsWindow.window).fgOnPrimaryContainer
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: root.size === "large" ? Text.AlignLeft : Text.AlignHCenter
                    text: Qt.formatDateTime(root.now, root.size === "large" ? "dddd" : "ddd")
                    variant: root.size === "large" ? "title" : "label"
                    font.weight: Font.Bold
                    color: root.accent
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: root.size === "large" ? Text.AlignLeft : Text.AlignHCenter
                    text: Qt.formatDateTime(root.now, "d MMMM")
                    variant: "caption"
                    emphasis: "muted"
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacingXs
                    visible: root.size === "large"
                    text: root.todayLine
                    variant: "caption"
                    emphasis: root.todayEvents.length > 0 ? "normal" : "dim"
                    elide: Text.ElideRight
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingSm

            WidgetHeader {
                glyph:  "󰃭"
                title:  Qt.formatDateTime(root.shown, "MMMM yyyy")
                accent: root.accent

                // The day under the pointer. Fades rather than popping in and out.
                TilePill {
                    readonly property bool marked: root.focusDay > 0 && !!root.markedDays[root.focusDay]
                    tone: marked ? "accent" : "neutral"
                    icon: marked ? "celebration" : "event"
                    accent: root.accent
                    text: root.dayInfo
                    opacity: root.focusDay > 0 ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                }
                // Next month, and back to this one. The same two-state tap the tile itself
                // has, with something to point at.
                TileChip {
                    awake: tileHover.hovered
                    accent: root.accent
                    icon: root.monthOffset === 0 ? "chevron_right" : "today"
                    onActivated: root.tileTap()
                }
            }

            // Weekday initials, rotated to the locale's first day.
            RowLayout {
                Layout.fillHeight: false
                Layout.fillWidth: true
                spacing: 0
                Repeater {
                    model: 7
                    StyledText {
                        required property int index
                        readonly property int dow: (root.firstDow + index) % 7
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: Qt.locale().dayName(dow, Locale.NarrowFormat)
                        variant: "caption"
                        emphasis: index === root.hoverCol ? "normal"
                                : (dow === 0 || dow === 6) ? "muted" : "dim"
                    }
                }
            }

            // The month changes through a fade, not a cut (see `viewOffset`).
            SwapFade {
                target: monthGrid
                key: String(root.monthOffset)
                shownKey: String(root.viewOffset)
                onSwapped: root.viewOffset = root.monthOffset
            }

            Grid {
                id: monthGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 7
                // Six rows always. A month that needs only five would otherwise make the
                // grid taller per row and the tile would visibly re-breathe month to month.
                rows: 6

                Repeater {
                    model: 42
                    Item {
                        id: cell
                        required property int index
                        width:  parent.width / 7
                        height: parent.height / 6

                        readonly property int day: index - root.lead + 1
                        readonly property bool real: day >= 1 && day <= root.daysInMonth
                        // Only in the CURRENT month. Without the offset check, paging
                        // forward lights up the same date number in a month that has no
                        // today in it at all.
                        readonly property bool isToday:
                            real && day === root.today && root.viewOffset === 0

                        readonly property int dow: (root.firstDow + (index % 7)) % 7
                        readonly property bool weekend: dow === 0 || dow === 6
                        readonly property bool marked: real && (!!root.markedDays[day] || Calendar.countOn(root.year, root.month, day) > 0)
                        readonly property bool picked: real && day === root.pickDay

                        // Weekend columns sit on a barely-there wash, so the working
                        // week reads as a block without a full grid of rules.
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 0.5
                            visible: parent.weekend && !parent.isToday
                            radius: Tokens.radiusXs - 2
                            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.045)
                        }

                        // The pointer's wash, under everything else in the cell.
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 0.5
                            radius: Tokens.radiusXs - 2
                            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.10)
                            opacity: (cell.real && cellMouse.containsMouse && !cell.isToday) ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                        }

                        // A soft rectangle, not a circle: cells here are much wider than they
                        // are tall (~46x23 at medium), so a circle sized by the smaller
                        // dimension reads as a smudge floating in the middle of the cell.
                        // `radiusSm` is the shell's row corner. It springs in when a cell
                        // becomes today (midnight, or paging back to this month) and out when
                        // it stops being.
                        Rectangle {
                            anchors.centerIn: parent
                            width:  Math.min(parent.width - 2, parent.height + 12)
                            height: Math.max(14, parent.height - 3)
                            radius: Tokens.corner(Config.barShape, Tokens.radiusSm)
                            color: root.accent
                            scale: parent.isToday ? 1 : 0
                            visible: scale > 0.01
                            Behavior on scale {
                                NumberAnimation {
                                    duration: Motion.spatial
                                    easing.bezierCurve: Motion.spring
                                    easing.type: Easing.BezierSpline
                                }
                            }
                        }

                        StyledText {
                            anchors.centerIn: parent
                            visible: parent.real
                            text: parent.day
                            variant: "caption"
                            color: parent.isToday ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fgMuted
                            font.bold: parent.isToday
                        }

                        // The day you clicked: a ring that springs in around it.
                        Rectangle {
                            anchors.centerIn: parent
                            width:  Math.min(parent.width - 2, parent.height + 12)
                            height: Math.max(14, parent.height - 3)
                            radius: Tokens.corner(Config.barShape, Tokens.radiusSm)
                            color: "transparent"
                            border.width: Tokens.borderWidth
                            border.color: root.accent
                            opacity: cell.picked ? 1 : 0
                            scale: cell.picked ? 1 : 0.7
                            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                            Behavior on scale {
                                NumberAnimation {
                                    duration: Motion.spatial
                                    easing.bezierCurve: Motion.spring
                                    easing.type: Easing.BezierSpline
                                }
                            }
                        }

                        // Takes its own press, so clicking a day picks it and does not also
                        // page the month. Everywhere else on the tile still pages.
                        MouseArea {
                            id: cellMouse
                            anchors.fill: parent
                            enabled: cell.real
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onContainsMouseChanged: {
                                if (containsMouse) root.hoverDay = cell.day
                                else if (root.hoverDay === cell.day) root.hoverDay = 0
                            }
                            onClicked: root.pickDay = root.pickDay === cell.day ? 0 : cell.day
                        }

                        // A dot for a day a countdown tile is pointing at. Last, so it
                        // draws over the today pill rather than under it.
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            width: 3; height: 3; radius: 1.5
                            antialiasing: true
                            visible: parent.marked
                            color: parent.isToday ? Colors.of(QsWindow.window).fgOnPrimary : root.accent
                        }
                    }
                }
            }
        }
    }
}
