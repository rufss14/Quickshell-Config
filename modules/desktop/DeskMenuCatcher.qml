import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../state"

// ── DeskMenuCatcher ───────────────────────────────────────────────────────────
// Hears a right-click on the empty desktop and asks for the desktop menu (DeskMenu) at the
// pointer. One full-screen window per screen on the Bottom layer: above the wallpaper (and
// Wallpaper Engine's Background layer), under every window and every bar.
//
// ── Declared before WidgetLayer, and always mapped ────────────────────────────
// Same-layer surfaces stack by MAP ORDER, and the desktop widgets live on this layer too. This is
// mapped at launch, ahead of them, so they sit on top of it and take their own clicks; it is
// never unmapped (that would map it again AFTER them and bury every widget). `Config.deskMenu`
// off empties its input region instead, so it passes every click through and costs a transparent
// surface.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: root

    required property var modelData
    screen: root.modelData

    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "quickshell-deskmenu-catcher"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: -1

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    mask: Config.deskMenu ? null : off

    Region { id: off }

    MouseArea {
        anchors.fill: parent
        enabled: Config.deskMenu
        acceptedButtons: Qt.RightButton
        onClicked: mouse => UiState.openDeskMenu(root.modelData?.name ?? "", mouse.x, mouse.y)
    }
}
