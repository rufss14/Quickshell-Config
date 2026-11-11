pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── TasksPanel ────────────────────────────────────────────────────────────────
// The to-do list, beside the sidebar's checklist button (SidePanelDock) or under the bar's (BarPanelDock).
// In the shell's Material 3 Expressive panel shape:
//
//   Header  (Settings › Modules › To-do hides it) the title and what is open
//   Hero    how much is left, a bar of how far through the list you are, and Clear done (asks twice)
//   Field   add one (Enter)
//   List    a tonal row each: click to tick or untick, ✕ on hover to remove
//
// The rules and the file are services/Tasks; this shows the list and calls it.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The room the slot has (the docks set it); the list scrolls past it.
    property real maxHeight: Infinity

    readonly property int pad: Tokens.spacingXl
    implicitWidth: Tokens.sideCardUnit * 8
    implicitHeight: Math.min(root.maxHeight, col.implicitHeight + root.pad * 2)

    readonly property color accent: Colors.of(QsWindow.window).primary
    readonly property int total: Tasks.items.length
    readonly property bool allDone: root.total > 0 && Tasks.openCount === 0

    // What the list may take: what's left under the header, hero and field, never more
    // than six card units (a long list scrolls rather than stretching the panel).
    readonly property real listRoom: Math.max(Tokens.sideCardUnit * 2, Math.min(Tokens.sideCardUnit * 6,
        root.maxHeight - root.pad * 2 - (head.visible ? head.implicitHeight + col.spacing : 0)
        - (hero.visible ? hero.implicitHeight + col.spacing : 0) - field.implicitHeight - col.spacing))

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
        spacing: Tokens.spacingSm

        PanelHeader {
            id: head
            Layout.fillHeight: false
            visible: Config.panelHeader("tasks")
            symbol:    "checklist"
            title:     Translation.tr("To-do")
            titleTail: Translation.tr("list")
            accent:    root.accent
            subtitle:  root.total === 0 ? Translation.tr("Nothing yet")
                     : root.allDone     ? Translation.tr("All done")
                     : Translation.tr("%1 open").arg(Tasks.openCount)
        }

        PanelHero {
            id: hero
            visible: root.total > 0
            compact: true
            symbol: root.allDone ? "task_alt" : "checklist"
            shape: root.allDone ? "sunny" : "cookie7"
            active: true
            turning: false
            accent: root.accent
            title: root.allDone ? Translation.tr("All done")
                 : Tasks.openCount === 1 ? Translation.tr("1 task left") : Translation.tr("%1 tasks left").arg(Tasks.openCount)
            line: Translation.tr("%1 of %2 finished").arg(Tasks.doneCount).arg(root.total)

            PanelButton {
                visible: Tasks.doneCount > 0
                capsule: true
                symbol:  "delete"
                label:   clearLatch.armed ? Translation.tr("Clear done?") : Translation.tr("Clear done")
                variant: clearLatch.armed ? "primary" : "normal"
                accent:  root.accent
                onActivated: clearLatch.trigger()
            }

            footer: Meter {
                Layout.fillWidth: true
                value: root.total > 0 ? Tasks.doneCount / root.total : 0
                accent: hero.ink
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

        PanelEmpty {
            visible: Tasks.ready && root.total === 0
            symbol: "checklist"
            shape: "cookie7"
            title: Translation.tr("Nothing to do")
            text: Translation.tr("Type a task above and press Enter. It is kept on this computer.")
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Math.min(list.contentHeight, root.listRoom)
            visible: root.total > 0
            clip: true
            interactive: list.contentHeight > list.height
            boundsBehavior: Flickable.StopAtBounds
            spacing: Tokens.spacingXs
            model: Tasks.items

            delegate: Item {
                id: row
                required property var modelData
                width: ListView.view.width
                implicitHeight: Math.max(tick.height, label.implicitHeight) + Tokens.spacingMd * 2
                height: implicitHeight

                HoverHandler { id: hover }

                Rectangle {
                    anchors.fill: parent
                    radius: Tokens.radiusCard
                    color: Colors.of(QsWindow.window).section
                    opacity: row.modelData.done ? 0.6 : 1
                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: Colors.of(QsWindow.window).fg
                        opacity: hover.hovered ? Tokens.stateHover : 0
                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                    }
                }

                MaterialIcon {
                    id: tick
                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.spacingMd
                    anchors.verticalCenter: parent.verticalCenter
                    name: row.modelData.done ? "check_circle" : "radio_button_unchecked"
                    fill: row.modelData.done ? 1 : 0
                    font.pixelSize: Tokens.iconLg
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
                    Accessible.role: Accessible.CheckBox
                    Accessible.name: row.modelData.text
                    Accessible.checked: row.modelData.done
                    Accessible.onPressAction: Tasks.toggle(row.modelData.id)
                }

                MaterialIcon {
                    id: gone
                    anchors.right: parent.right
                    anchors.rightMargin: Tokens.spacingMd
                    anchors.verticalCenter: parent.verticalCenter
                    name: "close"
                    font.pixelSize: Tokens.iconMd
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
