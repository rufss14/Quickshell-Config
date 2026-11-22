import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/island.js" as Rules

// ── IslandMonth ───────────────────────────────────────────────────────────────
// The Today tab's month: six weeks from the locale's first weekday (always six, so paging never changes the
// card's height), today on a disc in the accent, a dot under a day that has an event on your calendar,
// neighbouring months' days dimmed. Chevrons or the wheel page by month; the month name pops back to this one. The grid
// is Rules.monthCells (tested); nothing here reads the network (Calendar's own events, already in memory).
// Under the grid, the next thing today when there is one (Rules.agenda).
// ─────────────────────────────────────────────────────────────────────────────
IslandPlate {
    id: root

    // Months from this one; back to 0 whenever the tab is built.
    property int offset: 0

    readonly property date now: Clock.now
    readonly property date shown: new Date(root.now.getFullYear(), root.now.getMonth() + root.offset, 1)
    readonly property var cells: Rules.monthCells(root.shown.getFullYear(), root.shown.getMonth(),
                                                  Qt.locale().firstDayOfWeek,
                                                  { y: root.now.getFullYear(), m: root.now.getMonth(), d: root.now.getDate() })
    readonly property var heads: Rules.weekdays(Qt.locale().firstDayOfWeek)

    // What is left of today, soonest first (all-day entries lead); the whole list's length is for "+ N more".
    readonly property var allToday: Rules.agenda(Calendar.eventsOn(root.now.getFullYear(), root.now.getMonth(), root.now.getDate()),
                                                 root.now.getTime(), 99)
    readonly property var next: root.allToday.length > 0 ? root.allToday[0] : null
    readonly property int more: Math.max(0, root.allToday.length - 1)

    radius: Tokens.radiusCard

    // The month being drawn, held through its own fade so the title does not change before the grid does.
    property real swap: 1
    NumberAnimation on swap {
        id: swapAnim
        running: false
        from: 0
        to: 1
        duration: Motion.standard
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.emphasizedDecel
    }
    // Which way the month moved, so the grid arrives from that side.
    property int dir: 1
    property int _prev: 0
    onOffsetChanged: { root.dir = root.offset > root._prev ? 1 : -1; root._prev = root.offset; swapAnim.restart() }

    // A wheel over the month pages it (and so does not flip the island's page).
    WheelHandler {
        id: monthWheel
        property real acc: 0
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function (e) {
            monthWheel.acc += e.angleDelta.y
            if (Math.abs(monthWheel.acc) < 120) return
            root.offset += monthWheel.acc > 0 ? -1 : 1
            monthWheel.acc = 0
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingMd
        spacing: 0

        // ── Title and paging ──────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingXs

            ChipButton {
                symbol: "chevron_left"
                Accessible.name: Translation.tr("Previous month")
                onActivated: root.offset--
            }
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: titleText.implicitHeight
                StyledText {
                    id: titleText
                    anchors.centerIn: parent
                    text: Qt.locale().monthName(root.shown.getMonth(), Locale.LongFormat) + " " + root.shown.getFullYear()
                    variant: "title"
                    font.weight: Font.DemiBold
                    color: root.palette.primary
                    opacity: root.swap
            transform: Translate { x: (1 - root.swap) * root.dir * Tokens.spacingXxl }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: root.offset !== 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.offset = 0
                    Accessible.role: Accessible.Button
                    Accessible.name: Translation.tr("This month")
                    Accessible.onPressAction: root.offset = 0
                }
            }
            ChipButton {
                symbol: "chevron_right"
                Accessible.name: Translation.tr("Next month")
                onActivated: root.offset++
            }
        }

        // ── The weekdays ──────────────────────────────────────────────────────
        Row {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Repeater {
                model: root.heads
                StyledText {
                    required property int modelData
                    width: grid.cellW
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.locale().dayName(modelData, Locale.ShortFormat)
                    variant: "label"
                    font.weight: Font.DemiBold
                    color: (modelData === 0 || modelData === 6) ? root.palette.ramp4 : root.palette.fgMuted
                }
            }
        }

        // ── The weeks ─────────────────────────────────────────────────────────
        // Cells are placed by hand, not in a Grid: a Grid's implicit height follows its cells, which follow
        // its height, which the layout takes from that implicit height.
        Item {
            id: grid
            Layout.fillWidth: true
            Layout.fillHeight: true
            readonly property real cellW: width / 7
            readonly property real cellH: height / 6
            opacity: root.swap
            transform: Translate { x: (1 - root.swap) * root.dir * Tokens.spacingXxl }

            Repeater {
                model: root.cells
                Item {
                    id: cell
                    required property var modelData
                    required property int index
                    x: (cell.index % 7) * grid.cellW
                    y: Math.floor(cell.index / 7) * grid.cellH
                    width: grid.cellW
                    height: grid.cellH

                    readonly property int events: Calendar.countOn(modelData.y, modelData.m, modelData.d)
                    readonly property real side: Math.min(width, height) - 1

                    MorphShape {
                        anchors.centerIn: parent
                        width: cell.side
                        height: cell.side
                        visible: cell.modelData.today
                        shape: "cookie9"
                        turns: false
                        fillColor: root.palette.primary
                    }
                    StyledText {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: cell.events > 0 && !cell.modelData.today ? -1 : 0
                        text: cell.modelData.d
                        variant: "label"
                        font.weight: cell.modelData.today ? Font.Bold : Font.Normal
                        font.features: ({ tnum: 1 })
                        color: cell.modelData.today ? root.palette.fgOnPrimary
                             : cell.modelData.off !== 0 ? root.palette.fgFaint
                             : cell.modelData.weekend ? root.palette.ramp4 : root.palette.fg
                    }
                    // Something is on that day.
                    Rectangle {
                        visible: cell.events > 0 && !cell.modelData.today
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: Tokens.spacingXs / 2
                        width: Tokens.spacingXs
                        height: width
                        radius: width / 2
                        color: cell.modelData.off !== 0 ? root.palette.fgFaint : root.palette.primary
                    }
                }
            }
        }

        // ── What is next today ────────────────────────────────────────────────
        // One line, only when there is something: the soonest entry that has not ended (an all-day one first).
        RowLayout {
            visible: root.next !== null
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm

            Rectangle {
                Layout.preferredWidth: Tokens.spacingXs
                Layout.preferredHeight: Tokens.iconMd
                radius: width / 2
                color: root.next && root.next.live ? root.palette.primary : root.palette.alpha(root.palette.primary, 0.4)
            }
            StyledText {
                Layout.fillWidth: true
                text: root.next ? (root.next.summary || Translation.tr("Event")) : ""
                variant: "label"
                elide: Text.ElideRight
            }
            StyledText {
                text: !root.next ? "" : root.next.allDay ? Translation.tr("All day")
                    : Qt.formatTime(new Date(root.next.start), Qt.locale().timeFormat(Locale.ShortFormat))
                variant: "caption"
                emphasis: "dim"
                font.features: ({ tnum: 1 })
            }
            StyledText {
                visible: root.more > 0
                text: "+" + root.more
                variant: "caption"
                emphasis: "dim"
            }
        }
    }
}
