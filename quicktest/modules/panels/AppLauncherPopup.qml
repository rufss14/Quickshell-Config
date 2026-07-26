import "../../state"
import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../components"

// ── AppLauncherPopup ──────────────────────────────────────────────────────────
// Follows the exact same pattern as every other panel in OverlayRoot:
//   • No full-screen backdrop or dim overlay
//   • PanelWindow anchored top+left, sized to the card
//   • Card animates opacity + scale from Item.Top
//   • Keyboard focus via WlrKeyboardFocus.Exclusive, focus forwarded with
//     Qt.callLater so the Wayland grab settles before TextInput gets focus
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: win

    required property var screen

    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "quickshell-launcher"
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: UiState.launcherOpen
                                 ? WlrKeyboardFocus.Exclusive
                                 : WlrKeyboardFocus.None

    // Pin top-left, centre horizontally via margins.left
    anchors.top:  true
    anchors.left: true
    margins.top:  Config.barThickness + 2

    readonly property int screenW: win.screen ? win.screen.width : 1920
    readonly property int cardW:   Math.min(480, screenW - 80)
    margins.left: Math.round((screenW - cardW) / 2)

    implicitWidth:  cardW
    // Fixed at the maximum the panel can ever reach so the compositor window
    // never resizes during animation — a Wayland resize round-trip every frame
    // is the primary jitter source. Visual height is controlled by card.height
    // below; the extra transparent area outside the card is click-through.
    implicitHeight: panel.maxTotalH

    color: "transparent"
    visible: UiState.launcherOpen
             && (UiState.activeScreen === win.screen
                 || (UiState.activeScreen === null && Quickshell.screens[0] === win.screen))

    // A Surface, like every other card in the shell — it used to be a bare Rectangle
    // naming its own radius, fill and border, and its own 320ms InOutQuart / 200ms
    // OutCubic timings, none of which matched anything else.
    //
    // ── elevationCard, NOT elevationPopup ─────────────────────────────────────
    // Elevation picks the fill: card → `surface` (the wallpaper's background), popup →
    // `surfaceHigh` (a lifted grey). I reached for popup because the launcher floats —
    // but "floating" isn't the question the ladder answers. It asks what is BEHIND you.
    //
    // The overview's cards sit on a dimmed, blurred backdrop, so they have to lift off it
    // to be legible. The launcher sits on the bare desktop, where `surface` IS the right
    // answer — it's the pywal background, and it reads as part of the shell rather than as
    // a grey box pasted over the wallpaper.
    Surface {
        id: card
        anchors.top:   parent.top
        anchors.left:  parent.left
        anchors.right: parent.right

        elevation: Tokens.elevationCard
        focused: cardHover.hovered
        clip: true

        // Height animates HERE — purely inside the already-sized window, so no compositor
        // round-trip happens per frame. On the spatial curve: the card is growing across a
        // real distance as results arrive, and `standard` reads as a snap.
        height: panel.animH
        Behavior on height {
            NumberAnimation {
                duration: Motion.spatial
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.emphasizedDecel
            }
        }

        opacity: UiState.launcherOpen ? Tokens.surfaceOpacity : 0.0
        scale:   UiState.launcherOpen ? 1.0 : 0.97
        transformOrigin: Item.Top

        Behavior on opacity {
            NumberAnimation {
                duration: Motion.surfaceDuration(UiState.launcherOpen)
                easing.type: Motion.surfaceEasing(UiState.launcherOpen)
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Motion.surfaceDuration(UiState.launcherOpen)
                easing.type: Motion.surfaceEasing(UiState.launcherOpen)
            }
        }

        HoverHandler { id: cardHover }

        AppLauncherPanel {
            id: panel
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.top:    parent.top
            anchors.bottom: parent.bottom
            // panel.height == card.height (animated) at all times.
            // Children use parent.height directly to track the animation.
            onCloseRequested: UiState.launcherOpen = false
        }
    }

    Connections {
        target: UiState
        function onLauncherOpenChanged() {
            if (UiState.launcherOpen) {
                Qt.callLater(function() { panel.focusSearch() })
            } else {
                // Clear search immediately on close so animH snaps to collapsed
                // height before the opacity fade starts — prevents the card from
                // briefly appearing full-height on next open.
                panel.resetSearch()
            }
        }
    }
}
