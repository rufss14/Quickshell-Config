import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../components"
import "../../state"

// ── CheatsheetPopup ───────────────────────────────────────────────────────────
// The window the keybind cheatsheet lives in. Same shape the launcher used to have
// before it moved into the bar (BarPanelDock's centre slot): its
// own PanelWindow rather than a PanelHost surface, because it is not bar furniture
// and two surfaces sharing a namespace fight over keyboard focus.
//
//     qs ipc -c ~/.config/quicktest call cheatsheet toggle
//
// ── Exclusive keyboard focus, and why it has to be ────────────────────────────
// The sheet has a search field, and it is opened from a keybind — i.e. from outside
// this surface. `OnDemand` only grants focus on a click INTO the surface, so the
// field would silently ignore typing and `Keys.onEscapePressed` would never fire.
// Exclusive is dropped the moment it closes: holding it across anything long-running
// locks the rest of the desktop out of the keyboard.
//
// ── The content is Loader-gated ───────────────────────────────────────────────
// CheatsheetPanel acquires HyprConfig (which reads and then WATCHES three .lua files)
// while it is shown. Building it eagerly per screen would mean that parse running at
// login on every monitor for a window nobody has opened. No open sheet, no panel.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: win

    // `screen` is PanelWindow's own property, assigned by shell.qml — not
    // redeclared (a `required property var screen` shadowed it; see ScreenOwner).

    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "quickshell-cheatsheet"
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: win.owns && UiState.cheatsheetOpen
                                 ? WlrKeyboardFocus.Exclusive
                                 : WlrKeyboardFocus.None

    // One screen shows it — the active one, falling back to the first, exactly as the
    // launcher resolves it. A cheatsheet on every monitor at once is four copies of the
    // same list and four keyboard grabs competing.
    // The monitor you were on when it opened — see ScreenOwner.
    readonly property bool owns: screenOwner.owns
    ScreenOwner {
        id: screenOwner
        screen: win.screen
        open: UiState.cheatsheetOpen
    }

    anchors.top:    true
    anchors.left:   true
    anchors.right:  true
    anchors.bottom: true

    color: "transparent"
    visible: UiState.cheatsheetOpen && win.owns

    // ── Backdrop ──────────────────────────────────────────────────────────────
    // Dimmed, because the sheet is a full-screen modal thing you read — unlike the
    // launcher, which is a small card you type into over a desktop you still want to
    // see. Clicking it dismisses, which is the gesture people try first.
    Rectangle {
        anchors.fill: parent
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.55)
        opacity: UiState.cheatsheetOpen ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.surfaceDuration(UiState.cheatsheetOpen)
                easing.type: Motion.surfaceEasing(UiState.cheatsheetOpen)
            }
        }

        TapHandler { onTapped: UiState.cheatsheetOpen = false }
    }

    // This card clips its content, which would clip away the shadow Surface draws
    // as its own child — so it is an explicit sibling here. See SurfaceShadow.qml.
    SurfaceShadow { surface: card }
    Surface {
        id: card
        anchors.centerIn: parent

        // Bounded rather than proportional-only: on an ultrawide a full-width sheet
        // puts the combo and its description at opposite ends of the desk.
        width:  Math.min(880, win.width  - Tokens.spacingXxl * 2)
        height: Math.min(720, win.height - Tokens.spacingXxl * 2)

        elevation: Tokens.elevationCard
        clip: true

        opacity: UiState.cheatsheetOpen ? Tokens.surfaceOpacity : 0.0
        scale:   UiState.cheatsheetOpen ? 1.0 : 0.97
        transformOrigin: Item.Center

        Behavior on opacity {
            NumberAnimation {
                duration: Motion.surfaceDuration(UiState.cheatsheetOpen)
                easing.type: Motion.surfaceEasing(UiState.cheatsheetOpen)
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Motion.surfaceDuration(UiState.cheatsheetOpen)
                easing.type: Motion.surfaceEasing(UiState.cheatsheetOpen)
            }
        }

        Loader {
            id: sheetLoader
            anchors.fill: parent
            // THE line that keeps this free while closed — no open sheet, no HyprConfig
            // parse and no file watches.
            active: win.owns && UiState.cheatsheetOpen

            sourceComponent: CheatsheetPanel {
                shown: UiState.cheatsheetOpen
                onCloseRequested: UiState.cheatsheetOpen = false
            }
        }
    }

    Connections {
        target: UiState
        function onCheatsheetOpenChanged() {
            if (!UiState.cheatsheetOpen || !win.owns) return
            // callLater so the Wayland keyboard grab has settled before the field asks
            // for focus — the same ordering the launcher needs, for the same reason.
            Qt.callLater(function() {
                if (sheetLoader.item) sheetLoader.item.focusSearch()
            })
        }
    }
}
