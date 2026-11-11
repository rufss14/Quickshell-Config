pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Effects
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import "../../config"
import "../../components"

// ── SideTray ──────────────────────────────────────────────────────────────────
// The bar's system tray (widgets/TrayPill), turned onto the sidebar: one cell per tray
// icon, down the edge, the app's own icon (or a silhouette in the accent with
// Config.colorizeIcons, the pill's rule), the pill's pulsing dot on one that wants you.
// With nothing in the tray it takes no cells (SideRail.cellsFor), as the pill hides itself.
//
//   click    activate           middle   secondary activate
//   right    its menu, beside this cell (BarContextMenu `beside`, the sidebar's edge)
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool vertical: true
    // The tray's menu (Bar.qml's BarContextMenu, through SideGroupHost).
    property var contextMenu: null
    property string moduleId: "tray"

    readonly property int count: SystemTray.items.values.length
    readonly property color accent: Config.moduleAccent("tray", Colors.of(QsWindow.window).primary)

    implicitWidth:  root.vertical ? Config.sidebarCell : Config.sidebarRun(Math.max(1, root.count))
    implicitHeight: root.vertical ? Config.sidebarRun(Math.max(1, root.count)) : Config.sidebarCell

    Grid {
        columns: root.vertical ? 1 : Math.max(1, root.count)
        spacing: Config.sidebarCellGap

        Repeater {
            model: SystemTray.items

            Item {
                id: entry
                required property var modelData
                readonly property var sni: entry.modelData

                width:  Config.sidebarCell
                height: Config.sidebarCell

                CellFeedback {
                    id: feedback
                    anchors.fill: parent
                    hovered: hit.containsMouse
                    accent: root.accent
                    pointerX: hit.mouseX
                    pointerY: hit.mouseY
                }

                IconImage {
                    id: appIcon
                    anchors.centerIn: parent
                    implicitSize: Config.sidebarGlyphPx
                    source:  entry.sni?.icon ?? ""
                    visible: source !== ""
                    scale: feedback.lift

                    layer.enabled: Config.colorizeIcons
                    layer.effect: MultiEffect {
                        colorization:      1.0
                        colorizationColor: root.accent
                    }
                }
                // No icon: the pill's placeholder square.
                Rectangle {
                    anchors.centerIn: parent
                    width:   Config.sidebarGlyphPx
                    height:  Config.sidebarGlyphPx
                    visible: !appIcon.visible
                    radius:  Tokens.corner(Config.barShape, Tokens.radiusXs)
                    color:   Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).info, 0.28)
                }

                // NeedsAttention (status 2): the pill's pulsing dot, on the icon's corner.
                Rectangle {
                    visible: entry.sni?.status === 2
                    width:  Tokens.spacingXs + Tokens.borderWidth
                    height: width
                    radius: width / 2
                    color:  root.accent
                    x: appIcon.x + appIcon.width - width
                    y: appIcon.y + appIcon.height - height

                    SequentialAnimation on opacity {
                        running: entry.sni?.status === 2
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.2; duration: Motion.pulse; easing.type: Motion.ambient }
                        NumberAnimation { to: 1.0; duration: Motion.pulse; easing.type: Motion.ambient }
                    }
                }

                MouseArea {
                    id: hit
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    onPressed:  function (m) { feedback.press(m.x, m.y) }
                    onReleased: feedback.release()
                    onCanceled: feedback.release()
                    onClicked: function (m) {
                        if (m.button === Qt.MiddleButton)     entry.sni?.secondaryActivate()
                        else if (m.button === Qt.RightButton) root.contextMenu?.open(entry.sni?.menu, entry, Config.dockPosition)
                        else                                  entry.sni?.activate()
                    }
                }
            }
        }
    }
}
