pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── IslandWindow ──────────────────────────────────────────────────────────────
// The focused window as an island page: on the left the loud card (the app, its title, and the ten
// workspaces as one strip: the lit one is where it is, a click sends it elsewhere); on the right what
// you can do to it, a card each (float, fullscreen, pin, centre, focus, close: close asks twice).
// The window is the focused one on the island's own screen.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property int sideW: Tokens.spacingXl * 14 + Tokens.spacingSm
    readonly property string monitorName: UiState.islandScreenFor("window") !== "" ? UiState.islandScreenFor("window")
                                        : (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")
    readonly property var win: ActiveWindow.byMonitor[root.monitorName] ?? null
    readonly property bool floating: !!(root.win && root.win.floating)

    ArmLatch {
        id: closeLatch
        onConfirmed: if (root.win) ActiveWindow.close(root.win.address)
    }

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        IslandPlate {
            id: app
            Layout.fillWidth: false
            Layout.preferredWidth: root.sideW
            Layout.fillHeight: true
            hero: root.win !== null
            order: 0
            clip: true

            PanelEmpty {
                anchors.centerIn: parent
                width: parent.width - Tokens.spacingLg * 2
                visible: root.win === null
                quiet: true
                symbol: "select_all"
                shape: "squircle"
                title: Translation.tr("No window")
                text: Translation.tr("This workspace is empty. Focus a window and its controls show up here.")
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingLg
                visible: root.win !== null
                spacing: Tokens.spacingXs

                StyledText {
                    text: Translation.tr("Window").toUpperCase()
                    variant: "caption"
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                    color: app.inkDim
                }
                Item {
                    Layout.topMargin: Tokens.spacingSm
                    Layout.preferredWidth: Tokens.iconXl * 2 + Tokens.spacingSm
                    Layout.preferredHeight: Layout.preferredWidth
                    IslandBadge {
                        anchors.fill: parent
                        size: parent.width
                        filled: true
                        shape: "squircle"
                        symbol: root.win && root.win.icon ? "" : "select_all"
                    }
                    // Synchronous: the icon provider must not be read off the image thread.
                    Image {
                        anchors.centerIn: parent
                        visible: !!(root.win && root.win.icon)
                        width: Math.round(parent.width * 0.56)
                        height: width
                        source: root.win && root.win.icon ? root.win.icon : ""
                        sourceSize: Qt.size(128, 128)
                        asynchronous: false
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacingSm
                    text: root.win ? (root.win.name || root.win.appId || Translation.tr("Window")) : ""
                    variant: "headline"
                    font.weight: Font.DemiBold
                    color: app.ink
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.win ? root.win.title : ""
                    variant: "caption"
                    color: app.inkDim
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }

                Item { Layout.fillHeight: true }

                StyledText {
                    text: Translation.tr("Workspace")
                    variant: "caption"
                    color: app.inkDim
                }
                Grid {
                    id: spaces
                    Layout.fillWidth: true
                    columns: 5
                    spacing: Tokens.spacingXs
                    readonly property real cell: (spaces.width - spaces.spacing * 4) / 5

                    Repeater {
                        model: 10
                        delegate: Rectangle {
                            id: ws
                            required property int index
                            readonly property int num: ws.index + 1
                            readonly property bool here: !!root.win && root.win.workspace === ws.num

                            width: spaces.cell
                            height: Tokens.iconXl
                            radius: height / 2
                            color: ws.here ? root.palette.primary
                                           : root.palette.alpha(app.ink, wsHover.hovered ? 0.18 : 0.08)
                            Behavior on color { ColorAnimation { duration: Motion.respond } }

                            StyledText {
                                anchors.centerIn: parent
                                text: ws.num
                                variant: "caption"
                                font.weight: ws.here ? Font.DemiBold : Font.Medium
                                font.features: ({ tnum: 1 })
                                color: ws.here ? root.palette.fgOnPrimary : app.ink
                            }
                            HelpTip { text: ws.here ? "" : Translation.tr("Send to workspace %1").arg(ws.num) }
                            HoverHandler { id: wsHover; cursorShape: ws.here ? Qt.ArrowCursor : Qt.PointingHandCursor }
                            TapHandler {
                                enabled: !ws.here && root.win !== null
                                onTapped: ActiveWindow.toWorkspace(root.win.address, ws.num)
                            }
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: Translation.tr("Workspace %1").arg(ws.num)
                            Accessible.checked: ws.here
                            Accessible.onPressAction: if (!ws.here && root.win) ActiveWindow.toWorkspace(root.win.address, ws.num)
                        }
                    }
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 3
            columnSpacing: Tokens.spacingMd
            rowSpacing: Tokens.spacingMd
            uniformCellWidths: true
            uniformCellHeights: true

            IslandTile {
                Layout.fillWidth: true; Layout.fillHeight: true
                order: 1
                enabled: root.win !== null
                symbol: "open_with"
                label: root.floating ? Translation.tr("Tile") : Translation.tr("Float")
                on: root.floating
                onClicked: ActiveWindow.toggleFloating(root.win.address)
            }
            IslandTile {
                Layout.fillWidth: true; Layout.fillHeight: true
                order: 2
                enabled: root.win !== null
                symbol: "fullscreen"
                label: Translation.tr("Fullscreen")
                on: !!(root.win && root.win.fullscreen)
                onClicked: ActiveWindow.toggleFullscreen(root.win.address)
            }
            IslandTile {
                Layout.fillWidth: true; Layout.fillHeight: true
                order: 3
                enabled: root.floating
                help: root.floating ? "" : Translation.tr("Pin is for floating windows")
                symbol: "push_pin"
                label: root.win && root.win.pinned ? Translation.tr("Unpin") : Translation.tr("Pin")
                on: !!(root.win && root.win.pinned)
                onClicked: ActiveWindow.togglePin(root.win.address)
            }
            IslandTile {
                Layout.fillWidth: true; Layout.fillHeight: true
                order: 4
                enabled: root.floating
                help: root.floating ? "" : Translation.tr("Centre is for floating windows")
                symbol: "center_focus_strong"
                label: Translation.tr("Centre")
                onClicked: ActiveWindow.center(root.win.address)
            }
            IslandTile {
                Layout.fillWidth: true; Layout.fillHeight: true
                order: 5
                enabled: root.win !== null
                symbol: "my_location"
                label: Translation.tr("Focus")
                onClicked: ActiveWindow.focus(root.win.address)
            }
            IslandTile {
                Layout.fillWidth: true; Layout.fillHeight: true
                order: 6
                enabled: root.win !== null
                danger: true
                symbol: "close"
                label: closeLatch.armed ? Translation.tr("Sure?") : Translation.tr("Close")
                on: closeLatch.armed
                onClicked: closeLatch.trigger()
            }
        }
    }
}
