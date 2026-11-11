pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/desktopwidgets.js" as Rules

// ── HabitsWidget ──────────────────────────────────────────────────────────────
// A habit tracker: each habit is a row with the last seven days as marks you tick, and
// its streak. Stored in the tile's own record like reminders (`opts.habits`, mutated only
// through DesktopWidgets.addHabit/toggleHabit/removeHabit); the day maths — local dates,
// streaks that survive a daylight-saving change — is desktopwidgets.js, tested.
//
// ── Material 3 Expressive ─────────────────────────────────────────────────────
// A day you did it is a filled cookie in the accent; today, not yet done, is an outlined
// ring waiting for you, one step bigger than the rest; a missed day is a quiet dot. A tick
// MORPHS dot → cookie on a spring, so marking a day is a small event. A streak of two or
// more shows as a bolt pill.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    required property var opts
    required property string size
    required property int widgetId
    property bool active: true
    property color accent: Colors.of(QsWindow.window).primary

    readonly property var habits: root.opts.habits ?? []
    // Local today, re-read as the clock turns (Clock ticks on the minute), so the row of
    // days moves on at midnight on its own.
    readonly property string today: Rules.isoDay(Clock.now)
    readonly property var week: Rules.lastDays(root.today, 7)
    readonly property int doneToday: root.habits.filter(h => (h.days ?? []).indexOf(root.today) >= 0).length

    readonly property real dot: Tokens.iconMd + Tokens.spacingXs

    function letterOf(iso) {
        const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso)
        if (!m) return ""
        return Qt.locale().dayName(new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])).getDay(),
                                   Locale.NarrowFormat)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingSm

        WidgetHeader {
            icon:   "calendar_month"
            shape:  "sunny"
            title:  root.habits.length === 0 ? "Habits"
                  : root.doneToday === root.habits.length ? "All done today"
                  : root.doneToday + " of " + root.habits.length + " today"
            accent: root.accent
            RadialGauge {
                visible: root.habits.length > 0
                implicitWidth: Tokens.iconLg + Tokens.spacingXs
                implicitHeight: implicitWidth
                thickness: 3
                accent: root.accent
                value: root.habits.length > 0 ? root.doneToday / root.habits.length : 0
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.habits.length === 0
            text: Translation.tr("Nothing to track yet.\nType a habit below.")
            variant: "caption"
            emphasis: "dim"
            wrapMode: Text.WordWrap
            verticalAlignment: Text.AlignVCenter
        }

        // The week's initials, over the columns of marks.
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.habits.length > 0
            spacing: 0
            Item { Layout.fillWidth: true }
            Repeater {
                model: root.week
                StyledText {
                    required property string modelData
                    required property int index
                    Layout.preferredWidth: root.dot
                    horizontalAlignment: Text.AlignHCenter
                    text: root.letterOf(modelData)
                    font.pixelSize: Tokens.fontCaption - 2
                    font.weight: index === 6 ? Font.Bold : Font.Normal
                    color: index === 6 ? root.accent : Colors.of(QsWindow.window).fgDim
                }
            }
            Item { implicitWidth: Tokens.spacingMd }
        }

        ListView {
            id: list
            visible: root.habits.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Tokens.spacingXs
            boundsBehavior: Flickable.StopAtBounds
            model: root.habits

            delegate: TileRow {
                id: row
                required property var modelData
                // Carried on the row: the store is replaced on every tick.
                readonly property int widgetId: root.widgetId
                readonly property int streak: Rules.streak(row.modelData.days ?? [], root.today)
                width: list.width
                interactive: false

                // Remove, on hover only.
                MaterialIcon {
                    visible: row.hovered || delMouse.containsMouse
                    name: "close"
                    variant: "caption"
                    color: delMouse.containsMouse ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgDim
                    MouseArea {
                        id: delMouse
                        anchors.fill: parent
                        anchors.margins: -3
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: DesktopWidgets.removeHabit(row.widgetId, row.modelData.id)
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: row.modelData.name
                    variant: "label"
                    font.weight: Font.DemiBold
                    color: Colors.of(QsWindow.window).fg
                    elide: Text.ElideRight
                }
                TilePill {
                    visible: row.streak >= 2
                    icon: "bolt"
                    text: String(row.streak)
                    tone: "accent"
                    accent: root.accent
                }

                Row {
                    spacing: 0
                    Repeater {
                        model: root.week
                        Item {
                            id: day
                            required property string modelData
                            required property int index
                            readonly property bool done: (row.modelData.days ?? []).indexOf(day.modelData) >= 0
                            readonly property bool isToday: day.index === 6
                            width: root.dot
                            height: root.dot

                            SpringValue {
                                id: press
                                spec: Motion.springSpatialFast
                                epsilon: 0.0005
                                target: dayMouse.pressed ? 0.8 : dayMouse.containsMouse ? 1.12 : 1
                            }
                            MorphShape {
                                anchors.centerIn: parent
                                property real side: day.done || day.isToday ? root.dot - Tokens.spacingXs
                                                                                     : root.dot * 0.42
                                width: side
                                height: side
                                scale: press.value
                                spec: Motion.springSpatialFast
                                shape: day.done && !Config.barShape ? "cookie7" : "circle"
                                fillColor: day.done ? root.accent
                                         : day.isToday ? "transparent"
                                         : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.18)
                                strokeColor: !day.done && day.isToday ? root.accent : "transparent"
                                strokeWidth: 1.5
                                Behavior on side { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                            }
                            MouseArea {
                                id: dayMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: DesktopWidgets.toggleHabit(row.widgetId, row.modelData.id, day.modelData)
                            }
                        }
                    }
                }
            }
        }

        // ── Add ───────────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: addRow.implicitHeight + Tokens.spacingSm * 2
            radius: Tokens.corner(Config.barShape, Tokens.radiusSm)
            color: Colors.of(QsWindow.window).surfaceHigh
            border.width: Tokens.borderWidth
            border.color: entry.activeFocus ? Colors.of(QsWindow.window).outlineFocus : "transparent"
            Behavior on border.color { ColorAnimation { duration: Motion.respond } }

            RowLayout {
                id: addRow
                anchors.fill: parent
                anchors.leftMargin: Tokens.spacingMd
                anchors.rightMargin: Tokens.spacingXs
                spacing: Tokens.spacingSm

                TextInput {
                    id: entry
                    Layout.fillWidth: true
                    font.family: Tokens.fontFamily
                    font.pixelSize: Tokens.fontLabel
                    color: Colors.of(QsWindow.window).fg
                    selectionColor: Colors.of(QsWindow.window).alpha(root.accent, 0.35)
                    selectByMouse: true
                    clip: true
                    onAccepted: {
                        DesktopWidgets.addHabit(root.widgetId, entry.text)
                        entry.text = ""
                    }
                    // Escape hands the keyboard back rather than leaving the desktop holding it.
                    Keys.onEscapePressed: { entry.text = ""; entry.focus = false }

                    StyledText {
                        anchors.fill: parent
                        visible: entry.text === "" && !entry.activeFocus
                        text: Translation.tr("Add a habit")
                        variant: "label"
                        emphasis: "dim"
                    }
                }
                TileChip {
                    filled: entry.text.trim() !== ""
                    awake: true
                    accent: root.accent
                    icon: "add"
                    onActivated: {
                        DesktopWidgets.addHabit(root.widgetId, entry.text)
                        entry.text = ""
                    }
                }
            }
        }
    }
}
