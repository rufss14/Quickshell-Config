pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../../config"
import "../../../components"

// ── CalendarWidget ────────────────────────────────────────────────────────────
// The month, with today marked.
//
// ── Small is not a shrunken month ─────────────────────────────────────────────
// At 168px a 7×6 grid is unreadable, so the small size answers a different question —
// "what is today" — with the weekday and date only. Squeezing the grid in would have
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
    property color accent: Colors.primary

    readonly property bool grid: root.size !== "small"

    property date now: new Date()
    // Only has to be right to the day, so this ticks at a leisurely rate and exists
    // purely so a machine left on overnight rolls over to the new date.
    Timer {
        interval: 60000
        repeat: true
        running: root.active && root.grid
        onTriggered: root.now = new Date()
    }

    // ── Which month is shown ──────────────────────────────────────────────────
    // A tap looks ahead one month and a second tap comes back. Two states rather than an
    // endless forward walk: "what is coming up" is the actual question a desktop
    // calendar gets asked, and any tile you can page indefinitely needs a way home that
    // a single tap cannot give you.
    //
    // NOT persisted, deliberately. It is a glance, not a setting — a tile still showing
    // next month a reboot later is a tile lying about the date.
    property int monthOffset: 0

    function tileTap() {
        // Small shows today and nothing else; there is no month to page.
        if (!root.grid) return
        root.monthOffset = root.monthOffset === 0 ? 1 : 0
    }

    readonly property int today:     root.now.getDate()
    // The month being DRAWN, which is not necessarily the month it is.
    readonly property date shown:
        new Date(root.now.getFullYear(), root.now.getMonth() + root.monthOffset, 1)
    readonly property int month:     root.shown.getMonth()
    readonly property int year:      root.shown.getFullYear()
    readonly property int firstDow:  Qt.locale().firstDayOfWeek
    readonly property int daysInMonth: new Date(root.year, root.month + 1, 0).getDate()

    // How many blank cells lead the month, once the locale's first weekday is taken
    // into account. The +7 %7 keeps it positive when the locale starts on Sunday and
    // the month starts on Monday.
    readonly property int lead:
        (new Date(root.year, root.month, 1).getDay() - root.firstDow + 7) % 7

    // ── Small: today only ─────────────────────────────────────────────────────
    ColumnLayout {
        anchors.centerIn: parent
        visible: !root.grid
        spacing: 0

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDateTime(root.now, "ddd").toUpperCase()
            variant: "caption"
            color: root.accent
            font.bold: true
            font.letterSpacing: 2
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: root.today
            font.pixelSize: 62
            font.weight: Font.Bold
            color: Colors.fg
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDateTime(root.now, "MMMM")
            variant: "caption"
            emphasis: "muted"
        }
    }

    // ── Medium / large: the month ─────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        visible: root.grid
        spacing: Tokens.spacingSm

        StyledText {
            Layout.fillWidth: true
            text: Qt.formatDateTime(root.shown, "MMMM yyyy")
            variant: "body"
            font.bold: true
            color: Colors.fg
            elide: Text.ElideRight
        }

        // Weekday initials, rotated to the locale's first day.
        RowLayout {
            Layout.fillWidth: true
            spacing: 0
            Repeater {
                model: 7
                StyledText {
                    required property int index
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.locale().dayName((root.firstDow + index) % 7, Locale.NarrowFormat)
                    variant: "caption"
                    emphasis: "dim"
                }
            }
        }

        Grid {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 7
            // Six rows always. A month that needs only five would otherwise make the
            // grid taller per row and the tile would visibly re-breathe month to month.
            rows: 6

            Repeater {
                model: 42
                Item {
                    required property int index
                    width:  parent.width / 7
                    height: parent.height / 6

                    readonly property int day: index - root.lead + 1
                    readonly property bool real: day >= 1 && day <= root.daysInMonth
                    // Only in the CURRENT month. Without the offset check, paging
                    // forward lights up the same date number in a month that has no
                    // today in it at all.
                    readonly property bool isToday:
                        real && day === root.today && root.monthOffset === 0

                    // A PILL, not a circle. Cells here are much wider than they are
                    // tall (~46x23 at medium), so a circle sized by the smaller
                    // dimension reads as a smudge floating in the middle of the cell
                    // rather than as a deliberate highlight — visible the moment this
                    // was actually rendered rather than reasoned about.
                    Rectangle {
                        anchors.centerIn: parent
                        width:  Math.min(parent.width - 2, parent.height + 12)
                        height: Math.max(14, parent.height - 3)
                        radius: Tokens.radiusFull
                        visible: parent.isToday
                        color: root.accent
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: parent.real
                        text: parent.day
                        variant: "caption"
                        color: parent.isToday ? Colors.fgOnPrimary : Colors.fgMuted
                        font.bold: parent.isToday
                    }
                }
            }
        }
    }
}
