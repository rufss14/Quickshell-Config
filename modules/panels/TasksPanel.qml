pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── TasksPanel ────────────────────────────────────────────────────────────────
// The to-do list, beside the sidebar's checklist button (SidePanelDock) or under the
// bar's (BarPanelDock). A field to add one, the open tasks, the finished ones below.
//
// The panel recipe: PanelHeader with an ActionGroup, tokens throughout, the shared
// InputField and ArmLatch. The rules and the file are services/Tasks — this shows
// the list and calls it.
//
//   Enter       add what's in the field
//   click ring  tick / untick
//   ✕ (hover)   remove one
//   bin         clear everything finished (asks first — two clicks)
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The room the slot has (the docks set it); the list scrolls past it.
    property real maxHeight: Infinity

    readonly property int pad: Tokens.spacingLg
    implicitWidth: Tokens.sideCardUnit * 7
    implicitHeight: Math.min(root.maxHeight, col.implicitHeight + root.pad * 2)

    readonly property color accent: Colors.of(QsWindow.window).primary

    // What the list may take: what's left under the header and the field, never more
    // than six card units (a long list scrolls rather than stretching the panel).
    readonly property real listRoom: Math.max(Tokens.sideCardUnit * 2, Math.min(Tokens.sideCardUnit * 6,
        root.maxHeight - root.pad * 2 - head.implicitHeight - field.implicitHeight - col.spacing * 2))

    ArmLatch {
        id: clearLatch
        onConfirmed: Tasks.clearDone()
    }

    ColumnLayout {
        id: col
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.pad
        spacing: Tokens.spacingMd

        PanelHeader {
            id: head
            Layout.fillHeight: false
            symbol:    "checklist"
            title:     Translation.tr("To-do")
            titleTail: Translation.tr("list")
            accent:    root.accent
            subtitle:  Tasks.items.length === 0 ? Translation.tr("Nothing yet")
                     : Tasks.openCount === 0    ? Translation.tr("All done")
                     : Translation.tr("%1 open").arg(Tasks.openCount)

            ActionGroup {
                groupShown: Tasks.doneCount > 0
                PanelButton {
                    symbol:  "delete"
                    label:   clearLatch.armed ? Translation.tr("Clear done?") : ""
                    variant: clearLatch.armed ? "primary" : "ghost"
                    accent:  root.accent
                    onActivated: clearLatch.trigger()
                }
            }
        }

        InputField {
            id: field
            Layout.fillWidth: true
            icon: "add"
            placeholder: Tasks.ready ? Translation.tr("Add a task") : Translation.tr("Loading…")
            enabled: Tasks.ready
            onAccepted: function (v) {
                Tasks.add(v)
                field.clear()
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Math.min(list.contentHeight, root.listRoom)
            visible: Tasks.items.length > 0
            clip: true
            interactive: list.contentHeight > list.height
            boundsBehavior: Flickable.StopAtBounds
            spacing: Tokens.spacingXs
            model: Tasks.items

            delegate: Item {
                id: row
                required property var modelData
                width: ListView.view.width
                implicitHeight: Math.max(tick.height, label.implicitHeight) + Tokens.spacingSm * 2
                height: implicitHeight

                HoverHandler { id: hover }

                Rectangle {
                    anchors.fill: parent
                    radius: Tokens.radiusSm
                    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, hover.hovered ? 0.06 : 0)
                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                }

                MaterialIcon {
                    id: tick
                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.spacingSm
                    anchors.verticalCenter: parent.verticalCenter
                    name: row.modelData.done ? "check_circle" : "radio_button_unchecked"
                    fill: row.modelData.done ? 1 : 0
                    font.pixelSize: Tokens.iconMd
                    color: row.modelData.done ? root.accent : Colors.of(QsWindow.window).fgMuted
                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                }

                StyledText {
                    id: label
                    anchors.left: tick.right
                    anchors.leftMargin: Tokens.spacingMd
                    anchors.right: gone.left
                    anchors.rightMargin: Tokens.spacingSm
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.text
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    font.strikeout: row.modelData.done
                    emphasis: row.modelData.done ? "dim" : "normal"
                }

                // The whole row ticks it; the ✕ sits above this.
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Tasks.toggle(row.modelData.id)
                }

                MaterialIcon {
                    id: gone
                    anchors.right: parent.right
                    anchors.rightMargin: Tokens.spacingSm
                    anchors.verticalCenter: parent.verticalCenter
                    name: "close"
                    font.pixelSize: Tokens.iconSm
                    color: goneHover.hovered ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgDim
                    opacity: hover.hovered ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                    HoverHandler { id: goneHover }
                    TapHandler { enabled: hover.hovered; onTapped: Tasks.remove(row.modelData.id) }
                }
            }
        }
    }
}
