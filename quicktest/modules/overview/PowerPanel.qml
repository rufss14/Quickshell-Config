import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../config"
import "../../components"
import "../../state"

// ── PowerPanel ────────────────────────────────────────────────────────────────
// Top-left of the overview: the session actions, always visible. No button, no
// popover, no toggle — the overlay is already a deliberate thing you opened, so
// making you click twice to reach "lock" bought nothing.
//
// ── Why every action still needs confirming ───────────────────────────────────
// Picking an action ARMS it; a second, differently-placed click fires it. Colour
// cannot carry the warning here: on this pywal palette `danger` and `primary` are
// BOTH ramp1 — the same colour, literally — so a "red" shut-down button is
// indistinguishable from a friendly accented one. The glyph, the spelled-out
// consequence, and the two-step are what actually stop a misclick ending the session.
// ─────────────────────────────────────────────────────────────────────────────
Surface {
    id: root

    elevation: Tokens.elevationCard

    implicitWidth:  260
    implicitHeight: list.implicitHeight + Tokens.spacingLg * 2

    property string armed: ""

    Process { id: runner }

    function run(cmd) {
        runner.command = cmd
        runner.running = true
    }

    readonly property var actions: [
        {
            key: "lock", glyph: "󰌾", label: "Lock",
            detail: "Lock the screen",
            tint: Colors.info, cmd: ["loginctl", "lock-session"]
        },
        {
            key: "logout", glyph: "󰍃", label: "Log out",
            detail: "End the Hyprland session",
            tint: Colors.focus, cmd: ["hyprctl", "dispatch", "exit"]
        },
        {
            key: "reboot", glyph: "󰜉", label: "Restart",
            detail: "Reboot the machine",
            tint: Colors.warning, cmd: ["systemctl", "reboot"]
        },
        {
            key: "shutdown", glyph: "󰐥", label: "Shut down",
            detail: "Power off the machine",
            tint: Colors.danger, cmd: ["systemctl", "poweroff"]
        }
    ]

    ColumnLayout {
        id: list

        anchors.left:  parent.left
        anchors.right: parent.right
        anchors.top:   parent.top
        anchors.margins: Tokens.spacingLg
        spacing: Tokens.spacingXs

        Repeater {
            model: root.actions

            Item {
                id: row
                required property var modelData

                readonly property bool isArmed: root.armed === row.modelData.key

                Layout.fillWidth: true
                implicitHeight: 44

                Rectangle {
                    anchors.fill: parent
                    radius: Tokens.radiusSm
                    color: row.isArmed      ? Colors.mix(Colors.surfaceContainer, row.modelData.tint, 0.22)
                         : rowHover.hovered ? Colors.surfaceHigh
                         : "transparent"
                    border.width: row.isArmed ? Tokens.borderWidth : 0
                    border.color: row.modelData.tint

                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                }

                HoverHandler { id: rowHover }

                // Arming click. Disabled once armed, so the Confirm button is the ONLY
                // thing that can fire it — you cannot arm and fire by double-clicking
                // the same spot.
                MouseArea {
                    anchors.fill: parent
                    enabled: !row.isArmed
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.armed = row.modelData.key
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin:  Tokens.spacingMd
                    anchors.rightMargin: Tokens.spacingSm
                    spacing: Tokens.spacingMd

                    StyledText {
                        text: row.modelData.glyph
                        color: row.modelData.tint
                        variant: "title"
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            text: row.modelData.label
                            variant: "label"
                            font.bold: true
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: !row.isArmed
                            text: row.modelData.detail
                            variant: "caption"
                            emphasis: "dim"
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: row.isArmed
                            text: "Sure?"
                            variant: "caption"
                            color: row.modelData.tint
                        }
                    }

                    PanelButton {
                        visible: row.isArmed
                        variant: "ghost"
                        implicitWidth:  24
                        implicitHeight: 24
                        glyph: "󰅖"                          // back out
                        onActivated: root.armed = ""
                    }

                    PanelButton {
                        visible: row.isArmed
                        variant: "primary"
                        accent:  row.modelData.tint
                        label:   "Confirm"
                        onActivated: {
                            UiState.overviewOpen = false
                            root.run(row.modelData.cmd)
                        }
                    }
                }
            }
        }
    }
}
