pragma ComponentBehavior: Bound
import QtQuick
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
Item {
    id: root

    required property var opts
    required property string size
    required property int widgetId
    property bool active: true
    property color accent: Colors.primary

    readonly property var items: root.opts.items ?? []
    readonly property int doneCount: root.items.filter(i => i.done).length

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingXs

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacingSm

            StyledText {
                Layout.fillWidth: true
                text: {
                    const left = root.items.length - root.doneCount
                    if (root.items.length === 0) return "Reminders"
                    if (left === 0) return "All done"
                    return left + (left === 1 ? " to do" : " to do")
                }
                variant: "caption"
                font.bold: true
                color: Colors.fg
                elide: Text.ElideRight
            }

            // Only offered when it would do something.
            StyledText {
                visible: root.doneCount > 0
                text: "󰃢"
                variant: "caption"
                color: clearMouse.containsMouse ? Colors.danger : Colors.fgDim
                MouseArea {
                    id: clearMouse
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: DesktopWidgets.clearDone(root.widgetId)
                }
            }
        }

        // Empty state — the box was blank but for a header, which reads as broken
        // rather than as empty.
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

        // ── The list ──────────────────────────────────────────────────────────
        ListView {
            visible: root.items.length > 0
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 1
            boundsBehavior: Flickable.StopAtBounds
            model: root.items

            // An Item wrapping the RowLayout, NOT a bare RowLayout: the row needs a
            // full-area MouseArea behind its controls, and anchoring a child inside a
            // layout is undefined behaviour (the layout owns its children's geometry).
            // The Item gives the MouseArea something to fill that no layout manages.
            delegate: Item {
                id: rowItem
                required property var modelData
                width: list.width
                implicitHeight: rowLine.implicitHeight

                // Behind the row's own controls, so ticking and deleting keep their
                // targets while the rest of the row toggles.
                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: DesktopWidgets.toggleReminder(rowItem.widgetId,
                                                             rowItem.modelData.id)
                }

                readonly property int widgetId: root.widgetId

                RowLayout {
                    id: rowLine
                    anchors.fill: parent
                    spacing: Tokens.spacingSm

                // Drawn rather than a glyph pair: a checkbox has to read as a control at
                // 14px, and a filled rounded square with a tick is legible where two
                // similar glyphs are not.
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 14
                    implicitHeight: 14
                    radius: Tokens.radiusXs - 1
                    color: rowItem.modelData.done ? root.accent : "transparent"
                    border.width: Tokens.borderWidth
                    border.color: rowItem.modelData.done
                                  ? root.accent : Colors.alpha(Colors.fg, 0.4)

                    StyledText {
                        anchors.centerIn: parent
                        visible: rowItem.modelData.done
                        text: "󰄬"
                        font.pixelSize: 10
                        color: Colors.fgOnPrimary
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: rowItem.modelData.text
                    variant: "caption"
                    color: rowItem.modelData.done ? Colors.fgDim : Colors.fg
                    font.strikeout: rowItem.modelData.done
                    elide: Text.ElideRight
                }

                StyledText {
                    visible: rowMouse.containsMouse || delMouse.containsMouse
                    text: "󰅖"
                    variant: "caption"
                    color: delMouse.containsMouse ? Colors.danger : Colors.fgDim
                    MouseArea {
                        id: delMouse
                        anchors.fill: parent
                        anchors.margins: -3
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: DesktopWidgets.removeReminder(rowItem.widgetId,
                                                                 rowItem.modelData.id)
                    }
                }

                }
            }
        }

        // ── Add ───────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacingSm

            StyledText {
                text: "󰐕"
                variant: "caption"
                color: Colors.fgDim
            }

            TextInput {
                id: entry
                Layout.fillWidth: true
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontCaption
                color: Colors.fg
                selectionColor: Colors.alpha(root.accent, 0.35)
                selectByMouse: true
                clip: true

                // Enter adds and clears, so a list can be filled without touching the
                // mouse between items.
                onAccepted: {
                    DesktopWidgets.addReminder(root.widgetId, entry.text)
                    entry.text = ""
                }
                Keys.onEscapePressed: { entry.text = ""; entry.focus = false }

                StyledText {
                    anchors.fill: parent
                    visible: entry.text === "" && !entry.activeFocus
                    text: "Add a reminder"
                    variant: "caption"
                    emphasis: "dim"
                }
            }
        }
    }
}
