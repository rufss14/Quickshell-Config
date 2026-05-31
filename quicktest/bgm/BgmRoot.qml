import Quickshell
import Quickshell.Wayland
import QtQuick
import "../overlay/modules" as OV
import "../theming" as T

// ── BgmRoot ───────────────────────────────────────────────────────────────────
// Owns the BGM popup PanelWindow and wires it into the Panels singleton.
// Place this file at /quicktest/bgm/BgmRoot.qml.
//
// Register in shell.qml alongside OverlayRoot:
//
//   import "bgm"
//   ...
//   Variants {
//       model: Quickshell.screens
//       delegate: BgmRoot {
//           required property var modelData
//           screen: modelData
//       }
//   }
//
// Add to Panels singleton (e.g. Panels.qml):
//   property bool bgmOpen: false
//
// Add BgmButton to statusbar/modules — see BgmButton.qml.
// ─────────────────────────────────────────────────────────────────────────────
QtObject {
    id: root

    property var screen  // passed from shell.qml Variants delegate

    // ── Geometry constants ────────────────────────────────────────────────────
    readonly property int topMargin:  T.Theme.barHeight + 2
    readonly property int edgeMargin: T.Theme.barMargin + 8

    readonly property int bgmW: 535
    readonly property int bgmH: 340

    // BGM panel sits in the top-left column, below the wallpaper row.
    // It follows the same pattern as WallpaperPanel — anchored to top-left.
    readonly property real bgmLeft: edgeMargin
    readonly property real bgmTop: {
        if (Panels.wallpaperOpen)
            return topMargin + 340 + 8   // pushed down when wallpaper is open
        return topMargin
    }

    // ── Popup window ─────────────────────────────────────────────────────────
    property var bgmPopup: PanelWindow {
        id: bgmWin
        screen:                      root.screen
        WlrLayershell.layer:         WlrLayer.Overlay
        WlrLayershell.namespace:     "quickshell-bgm-popup"
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: Panels.bgmOpen
            ? WlrKeyboardFocus.OnDemand
            : WlrKeyboardFocus.None

        anchors.top:  true
        anchors.left: true
        margins.top:  root.bgmTop
        margins.left: root.bgmLeft

        // Animate vertical position when wallpaper panel opens/closes
        Behavior on margins.top {
            NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutCubic }
        }

        implicitWidth:  root.bgmW
        implicitHeight: root.bgmH
        color: "transparent"
        visible: Panels.activeScreen === root.screen
            && (Panels.bgmOpen || bgmCard.opacity > 0.005)

        // ESC to close
        Item {
            id: bgmWinFocusItem
            Keys.onEscapePressed: Panels.bgmOpen = false
            Connections {
                target: Panels
                function onBgmOpenChanged() {
                    if (Panels.bgmOpen) bgmWinFocusItem.forceActiveFocus()
                }
            }
        }

        Rectangle {
            id: bgmCard
            anchors.fill: parent
            radius:       T.Theme.pillRadius + 4
            color:        T.Theme.bg
            border.color: T.Theme.barBorder
            border.width: 1
            opacity: Panels.bgmOpen ? 1.0 : 0.0
            scale:   Panels.bgmOpen ? 1.0 : 0.96
            transformOrigin: Item.TopLeft

            Behavior on opacity { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutBack  } }

            OV.BgmPanel {
                id: bgmContent
                anchors.fill: parent
            }
        }
    }

    // ── Register with Panels singleton ────────────────────────────────────────
    Component.onCompleted: {
        Panels.bgmPanel = bgmPopup
        console.log("[BgmRoot] BGM panel registered successfully")
    }
}
