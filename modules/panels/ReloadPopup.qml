import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── ReloadPopup ───────────────────────────────────────────────────────────────
// The reload card in a window of its own. The card itself is components/ReloadCard; in the
// normal case it is drawn by the blob inside the bar's window (modules/bar/BarReloadHost),
// coming out from under the bar. This window takes over exactly when that cannot: while
// something is FULLSCREEN on this monitor (Hyprland hides the bar, a Top layer surface, under
// a fullscreen window), and when the blob plugin is not built. Exactly one host is live at a
// time, the rule BarToastHost and NotificationOverlay keep for the notification deck.
//
// It starts where the bar's edge is (Config.belowBar) so it never covers the bar, and holds no
// keyboard focus: the shell is in the middle of being edited and must never steal the editor's
// keys. Only the card takes the mouse; the rest of the strip is the desktop's.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: win

    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "quickshell-reload"
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors.top:   true
    anchors.left:  true
    anchors.right: true
    implicitHeight: Config.belowBar + card.height + Tokens.spacingXxl
    color: "transparent"

    mask: Region { item: card }

    readonly property string monName: Hyprland.monitorFor(win.screen)?.name ?? ""

    // The exact inverse of BarReloadHost's condition: never both, never neither.
    readonly property bool live: !Morph.available || Fullscreen.byMonitor[win.monName] === true

    visible: card.shown

    SurfaceShadow { surface: card }
    ReloadCard {
        id: card
        screen: win.screen
        live: win.live
        welded: false
        maxWidth: win.width - Tokens.spacingXxl * 2
        anchors.horizontalCenter: parent.horizontalCenter
        y: Config.belowBar + Tokens.spacingMd - (1 - card.reveal) * (card.height + Tokens.spacingMd)
        opacity: card.reveal * Tokens.surfaceOpacity
    }
}
