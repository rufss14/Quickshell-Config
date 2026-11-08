pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── RemindersWidget ───────────────────────────────────────────────────────────
// A checklist that survives reboots.
//
// Distinct from the Timers service on purpose: a timer is a moment that fires, a
// reminder here is an item you tick off. They share nothing but the word, and folding
// them together would have meant one service answering two unrelated questions.
//
// Done items stay, greyed and struck through, until cleared — crossing something off
// and seeing it stay crossed off is most of the point. "Clear done" is the broom.
//
// ── Material 3 Expressive (2026-10-30) ────────────────────────────────────────
// The header carries the list's progress as a small ring (done of total) beside the
// count, and the broom as a chip. Each item is a tonal row; its box is a SHAPE — an
// empty ring while open, morphing into a filled cookie with a tick when you check it —
// so ticking something off is a small physical event, not a colour flip.
Item {
    id: root

    required property var opts
    required property string size
    required property int widgetId
    property bool active: true
    property color accent: Colors.of(QsWindow.window).primary

    readonly property var items: root.opts.items ?? []
    readonly property int doneCount: root.items.filter(i => i.done).length

    HoverHandler { id: tileHover }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingSm

        WidgetHeader {
            icon:   "checklist"
            shape:  "clover"
            accent: root.accent
            title: {
                const left = root.items.length - root.doneCount
                if (root.items.length === 0) return "Reminders"
                if (left === 0) return "All done"
                return left + " to do"
            }
            RadialGauge {
                visible: root.items.length > 0
                implicitWidth: Tokens.iconLg + Tokens.spacingXs
                implicitHeight: implicitWidth
                thickness: 3
                accent: root.accent
                value: root.items.length > 0 ? root.doneCount / root.items.length : 0
            }
            TileChip {
                visible: root.doneCount > 0
                icon: "cleaning_services"
                awake: tileHover.hovered
                onActivated: DesktopWidgets.clearDone(root.widgetId)
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.items.length === 0
            text: "Nothing yet.\nType below to add one."
            variant: "caption"
            emphasis: "dim"
            wrapMode: Text.WordWrap
            verticalAlignment: Text.AlignVCenter
        }

        ListView {
            id: list
            visible: root.items.length > 0
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Tokens.spacingXs
            boundsBehavior: Flickable.StopAtBounds
            model: root.items

            delegate: TileRow {
                id: rowItem
                required property var modelData
                // Carried on the row: the store is replaced on a toggle, and the handlers
                // must still know which widget they belong to.
                readonly property int widgetId: root.widgetId
                width: list.width
                onTapped: DesktopWidgets.toggleReminder(rowItem.widgetId, rowItem.modelData.id)

                // The box: a ring while open, a filled cookie with a tick once done.
                Item {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Tokens.iconMd + Tokens.spacingXs
                    implicitHeight: implicitWidth
                    MorphShape {
                        anchors.fill: parent
                        spec: Motion.springSpatialFast
                        shape: rowItem.modelData.done && !Config.barShape ? "cookie9" : "circle"
                        fillColor: rowItem.modelData.done ? root.accent : "transparent"
                        strokeColor: rowItem.modelData.done ? "transparent"
                                   : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.45)
                        strokeWidth: 1.5
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "check"
                        font.pixelSize: Tokens.iconSm - 2
                        color: Colors.of(QsWindow.window).fgOnPrimary
                        SpringValue {
                            id: tick
                            spec: Motion.springSpatialFast
                            epsilon: 0.002
                            target: rowItem.modelData.done ? 1 : 0
                        }
                        scale: tick.value
                        visible: tick.value > 0.01
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: rowItem.modelData.text
                    variant: "label"
                    color: rowItem.modelData.done ? Colors.of(QsWindow.window).fgDim : Colors.of(QsWindow.window).fg
                    font.strikeout: rowItem.modelData.done
                    elide: Text.ElideRight
                }
                // Delete, on hover only — a cross on every row is a list of invitations to lose things.
                MaterialIcon {
                    visible: rowItem.hovered || delMouse.containsMouse
                    name: "close"
                    variant: "caption"
                    color: delMouse.containsMouse ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgDim
                    MouseArea {
                        id: delMouse
                        anchors.fill: parent
                        anchors.margins: -3
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: DesktopWidgets.removeReminder(rowItem.widgetId, rowItem.modelData.id)
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
                        DesktopWidgets.addReminder(root.widgetId, entry.text)
                        entry.text = ""
                    }
                    Keys.onEscapePressed: { entry.text = ""; entry.focus = false }

                    StyledText {
                        anchors.fill: parent
                        visible: entry.text === "" && !entry.activeFocus
                        text: Translation.tr("Add a reminder")
                        variant: "label"
                        emphasis: "dim"
                    }
                }
                // Filled once there is something to add: the one action the field has.
                TileChip {
                    filled: entry.text.trim() !== ""
                    awake: true
                    accent: root.accent
                    icon: "add"
                    onActivated: {
                        DesktopWidgets.addReminder(root.widgetId, entry.text)
                        entry.text = ""
                    }
                }
            }
        }
    }
}
