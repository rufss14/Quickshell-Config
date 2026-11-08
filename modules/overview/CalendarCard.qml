import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── CalendarCard ──────────────────────────────────────────────────────────────
// Bottom-left of the overview: the month, and nothing else.
//
// Notes are gone — the store, the per-day dots, the editor, the whole right-hand
// column. The month now gets all of that space, which is what it wanted: the day
// cells are large enough to actually read and click. (The old notes lived in
// `~/quickshell-salvage/overview-legacy/ClockPanel.qml` if they're ever wanted back;
// any previously-saved notes are orphaned, not deleted.)
//
// ── The height is FIXED, and deliberately ─────────────────────────────────────
// This card used to resize as you paged through months, because a month starting on
// a Sunday needs six week-rows where one starting on a Monday needs five, and the
// "jump to today" hint only existed when you were off-month.
//
// That is worse than it sounds: the overlay derives the workspace grid's free band —
// and therefore the grid's SCALE — from the height of the bottom-row cards. A card
// that breathed made the entire grid rescale in sympathy.
//
// So: always 42 cells (six rows, whatever the month) and the "today" button reserves
// its space rather than appearing. Nothing here resizes, ever.
// ─────────────────────────────────────────────────────────────────────────────
Surface {
    id: root

    elevation: Tokens.elevationCard

    // ── Fixed geometry ────────────────────────────────────────────────────────
    readonly property int cellSize: 40
    readonly property int cellGap:  3

    readonly property int gridW: cellSize * 7 + cellGap * 6
    readonly property int gridH: cellSize * 6 + cellGap * 5

    readonly property int headerH:  30
    readonly property int weekdayH: 18

    implicitWidth:  gridW + Tokens.spacingXl * 2
    implicitHeight: headerH + weekdayH + gridH
                  + Tokens.spacingMd * 2 + Tokens.spacingXl * 2

    // ── Date ──────────────────────────────────────────────────────────────────
    // Binds to the shared clock; its minute-aligned ticks keep the date current.
    readonly property date now: Clock.now
    readonly property int todayD: now.getDate()
    readonly property int todayM: now.getMonth()
    readonly property int todayY: now.getFullYear()

    property int calMonth: todayM
    property int calYear:  todayY

    // This card is built with the overview rather than loaded on demand, so a gated
    // update was needed to avoid ticking for the whole shell lifetime. The shared clock
    // is always running, but this card only needs minute resolution — a midnight
    // rollover is the only thing it watches for.
    // `active` rather than UiState.overviewOpen directly: the lockscreen draws this card
    // too, and there the overview is by definition closed — the date would freeze at
    // whenever the overlay last shut, which on a machine left locked overnight means a
    // calendar showing yesterday. Defaults to the overlay's state, so the overview passes
    // nothing and behaves exactly as before.
    property bool active: UiState.overviewOpen

    readonly property var monthNames: [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]
    readonly property var dayNames: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    function daysInMonth(y, m)     { return new Date(y, m + 1, 0).getDate() }
    // Monday-first: JS getDay() is Sunday-0, so rotate.
    function firstDayOfMonth(y, m) { return (new Date(y, m, 1).getDay() + 6) % 7 }

    // ALWAYS 42 cells — six rows, every month. See the header.
    readonly property var cells: {
        const out = []
        const offset = root.firstDayOfMonth(root.calYear, root.calMonth)
        for (let i = 0; i < offset; i++) out.push(0)
        const days = root.daysInMonth(root.calYear, root.calMonth)
        for (let d = 1; d <= days; d++) out.push(d)
        while (out.length < 42) out.push(0)
        return out
    }

    readonly property bool offMonth: calMonth !== todayM || calYear !== todayY

    function keyFor(day) { return root.calYear + "-" + (root.calMonth + 1) + "-" + day }

    function prevMonth() { if (calMonth === 0)  { calMonth = 11; calYear-- } else calMonth-- }
    function nextMonth() { if (calMonth === 11) { calMonth = 0;  calYear++ } else calMonth++ }
    function goToday()   { calMonth = todayM; calYear = todayY }

    // ── Holidays ──────────────────────────────────────────────────────────────
    // Country from the system locale. No geolocation request is made — the original
    // phoned home to ip-api.com on every open. An empty code disables holidays.
    readonly property string countryCode: {
        const parts = Qt.locale().name.split("_")   // e.g. "en_GB"
        return parts.length > 1 ? parts[1] : ""
    }
    property var holidays: ({})

    function holidayFor(day) {
        return day > 0 ? (root.holidays[root.keyFor(day)] || "") : ""
    }

    function fetchHolidays(year) {
        if (countryCode === "") return

        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status !== 200) {
                // Quiet, but NOT silent: the original swallowed every failure with
                // `catch(e) {}`, so a broken feed looked exactly like a year with no
                // holidays.
                console.warn("CalendarCard: holiday fetch failed for", year, "— status", xhr.status)
                return
            }
            try {
                const list = JSON.parse(xhr.responseText)
                const merged = Object.assign({}, root.holidays)
                for (let i = 0; i < list.length; i++) {
                    const p = list[i].date.split("-")
                    merged[parseInt(p[0]) + "-" + parseInt(p[1]) + "-" + parseInt(p[2])] =
                        list[i].localName || list[i].name
                }
                root.holidays = merged
            } catch (e) {
                console.warn("CalendarCard: could not parse holidays —", e)
            }
        }
        xhr.open("GET", "https://date.nager.at/api/v3/PublicHolidays/" + year + "/" + countryCode)
        xhr.send()
    }

    Component.onCompleted: {
        fetchHolidays(todayY)
        fetchHolidays(todayY + 1)
    }
    onCalYearChanged: if (calYear !== todayY && calYear !== todayY + 1) fetchHolidays(calYear)

    // ══════════════════════════════════════════════════════════════════════════
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingXl
        spacing: Tokens.spacingMd

        // ── Header ────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.headerH
            spacing: Tokens.spacingSm

            PanelButton {
                variant: "ghost"
                implicitHeight: 26
                implicitWidth:  26
                glyph: "󰅁"
                onActivated: root.prevMonth()
            }

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.monthNames[root.calMonth] + " " + root.calYear
                variant: "title"
                font.bold: true
            }

            // Always present, merely invisible when you're already on this month — if
            // it came and went, the header would reflow and the card would twitch as
            // you paged.
            PanelButton {
                variant: "ghost"
                implicitHeight: 26
                implicitWidth:  26
                glyph: "󰃰"
                accent: Colors.of(QsWindow.window).primary
                glyphTint: Colors.of(QsWindow.window).focus
                opacity: root.offMonth ? 1 : 0
                enabled: root.offMonth
                onActivated: root.goToday()
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
            }

            PanelButton {
                variant: "ghost"
                implicitHeight: 26
                implicitWidth:  26
                glyph: "󰅂"
                onActivated: root.nextMonth()
            }
        }

        // ── Weekday headings ──────────────────────────────────────────────────
        Row {
            Layout.preferredWidth:  root.gridW
            Layout.preferredHeight: root.weekdayH
            spacing: root.cellGap

            Repeater {
                model: root.dayNames

                StyledText {
                    required property var modelData
                    width: root.cellSize
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    variant: "caption"
                    emphasis: "dim"
                    font.bold: true
                }
            }
        }

        // ── The days ──────────────────────────────────────────────────────────
        Grid {
            Layout.preferredWidth:  root.gridW
            Layout.preferredHeight: root.gridH
            columns: 7
            spacing: root.cellGap

            Repeater {
                model: root.cells

                Item {
                    id: day
                    required property var modelData

                    readonly property int d: modelData
                    readonly property bool isToday:
                        d === root.todayD && root.calMonth === root.todayM
                                          && root.calYear  === root.todayY
                    readonly property bool isHoliday: root.holidayFor(d) !== ""

                    width:  root.cellSize
                    height: root.cellSize

                    Rectangle {
                        anchors.centerIn: parent
                        width:  root.cellSize - 2
                        height: width
                        radius: width / 2
                        visible: day.d > 0

                        // Today is a filled `primary` chip — the anchor point you scan
                        // for. Hover is a wash. They must not read the same.
                        color: day.isToday      ? Colors.of(QsWindow.window).primary
                             : dayHover.hovered ? Colors.of(QsWindow.window).stateHoverBg
                             : "transparent"

                        Behavior on color { ColorAnimation { duration: Motion.respond } }

                        StyledText {
                            anchors.centerIn: parent
                            text: day.d > 0 ? day.d : ""
                            variant: "label"
                            font.bold: day.isToday
                            color: day.isToday   ? Colors.of(QsWindow.window).fgOnPrimary
                                 : day.isHoliday ? Colors.of(QsWindow.window).warning
                                 : Colors.of(QsWindow.window).fg
                        }
                    }

                    HoverHandler { id: dayHover }

                    // The holiday's name, on hover. It has nowhere else to live now
                    // that there's no detail column — and a holiday you can't name is
                    // just an oddly-coloured number.
                    Rectangle {
                        visible: day.isHoliday && dayHover.hovered
                        anchors.bottom: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        z: 50

                        width:  holidayName.implicitWidth + Tokens.spacingMd * 2
                        height: 22
                        radius: Tokens.radiusXs
                        color: Colors.of(QsWindow.window).surfaceHigh
                        border.width: Tokens.borderWidth
                        border.color: Colors.of(QsWindow.window).outlineNested

                        StyledText {
                            id: holidayName
                            anchors.centerIn: parent
                            text: root.holidayFor(day.d)
                            variant: "caption"
                            color: Colors.of(QsWindow.window).warning
                        }
                    }
                }
            }
        }
    }
}
