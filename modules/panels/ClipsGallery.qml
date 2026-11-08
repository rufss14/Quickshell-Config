import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── ClipsGallery ──────────────────────────────────────────────────────────────
// The window the clip library lives in (ClipsGalleryPanel). CheatsheetPopup's
// shape: its own PanelWindow and its own layer-shell namespace (two surfaces
// sharing one fight over keyboard focus), one screen — the monitor focused when it
// opened (ScreenOwner) — and a dimmed backdrop that dismisses on click.
//
//     qs ipc -c ~/.config/quicktest call clips gallery
//
// ── Exclusive keyboard focus ──────────────────────────────────────────────────
// It is opened from the sidebar pill or a keybind — another surface — and it has
// text fields (search, rename). OnDemand would only grant focus on a click INTO
// it. Exclusive is dropped the moment it closes.
//
// ── Lazy, but it keeps its content while it fades ─────────────────────────────
// The panel is behind a Loader: closed, it costs nothing — no grid, no
// thumbnails decoded. Unlike the cheatsheet, the Loader stays active until the
// card has faded all the way out, so the card doesn't blank for the whole
// fade-out (CLAUDE.md: a surface that fades out keeps what it shows).
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: win

    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "quickshell-clips"
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: win.owns && UiState.clipsGalleryOpen
                                 ? WlrKeyboardFocus.Exclusive
                                 : WlrKeyboardFocus.None

    readonly property bool owns: screenOwner.owns
    ScreenOwner {
        id: screenOwner
        screen: win.screen
        open: UiState.clipsGalleryOpen
    }

    readonly property bool open: UiState.clipsGalleryOpen && win.owns
    // Still on screen while the card fades out.
    readonly property bool present: win.open || card.opacity > 0.01

    anchors.top:    true
    anchors.left:   true
    anchors.right:  true
    anchors.bottom: true

    color: "transparent"
    visible: win.owns && win.present

    Rectangle {
        anchors.fill: parent
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.55)
        opacity: win.open ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.surfaceDuration(win.open)
                easing.type: Motion.surfaceEasing(win.open)
            }
        }
        // Click away to close — but only AWAY. A TapHandler blocks nothing, so a tap on a control inside
        // the card reaches this too whenever that control is itself a TapHandler (ChipButton,
        // CookieButton and SegmentSwitch are; the PanelButtons the library used to wear were
        // MouseAreas, which stop the press). Without the test, every chip closed the library.
        TapHandler {
            onTapped: function (eventPoint) {
                const p = card.mapFromItem(parent, eventPoint.position)
                if (p.x < 0 || p.y < 0 || p.x > card.width || p.y > card.height)
                    UiState.clipsGalleryOpen = false
            }
        }
    }

    SurfaceShadow { surface: card }
    Surface {
        id: card
        anchors.centerIn: parent

        // Bounded, as the cheatsheet is: a full-width grid on an ultrawide puts
        // the selected clip's pane a desk away from its tile.
        width:  Math.min(1180, win.width  - Tokens.spacingXxl * 2)
        height: Math.min(780,  win.height - Tokens.spacingXxl * 2)

        elevation: Tokens.elevationCard
        clip: true

        opacity: win.open ? Tokens.surfaceOpacity : 0.0
        scale:   win.open ? 1.0 : 0.97
        transformOrigin: Item.Center

        Behavior on opacity {
            NumberAnimation {
                duration: Motion.surfaceDuration(win.open)
                easing.type: Motion.surfaceEasing(win.open)
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Motion.surfaceDuration(win.open)
                easing.type: Motion.surfaceEasing(win.open)
            }
        }

        Loader {
            id: panelLoader
            anchors.fill: parent
            active: win.owns && win.present
            focus: true
            sourceComponent: ClipsGalleryPanel {
                focus: true
                onCloseRequested: UiState.clipsGalleryOpen = false
            }
        }
    }

    Connections {
        target: UiState
        function onClipsGalleryOpenChanged() {
            if (!UiState.clipsGalleryOpen || !win.owns) return
            // After the keyboard grab settles (the cheatsheet's ordering).
            Qt.callLater(function () {
                if (panelLoader.item) panelLoader.item.focusSearch()
            })
        }
    }
}
