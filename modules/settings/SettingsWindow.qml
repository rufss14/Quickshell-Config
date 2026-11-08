import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../state"
import "../../services"

// ── SettingsWindow ────────────────────────────────────────────────────────────
// Settings as a floating window — an xdg-toplevel, like every other app.
//
// ── Why a FloatingWindow ────────────────────────────────────────────────────
// It was tried as a WlrLayer overlay (the modal-panel look) and reverted: the
// overlay sat ABOVE the bar, so its card swallowed the clicks the Bar page's
// arrange mode needs on the real bar, and a module dragged off the bar onto the
// settings tray stopped routing between the two surfaces. A toplevel sits BELOW
// every layer surface, so the bar and frame stay on top and interactive. The
// tiler is handled by a `float` + `center` window rule in hypr/rules.lua.
//
// The window is transparent and the card fills it edge to edge, so the rounded
// card IS the window's shape — Hyprland composites the alpha, rounds the same
// corners and casts the window shadow around it. No dim, no scrim.
//
// ── Always launches at the same size ────────────────────────────────────────
// The window is created once and its `visible` is toggled — so on the second
// open the compositor would reopen it at whatever size it was last dragged to.
// So the size is RESET to the opening dimensions each time, while the window is
// still hidden (no resize flash), and only then shown.
//
// ── visible is ASSIGNED both ways, never bound ──────────────────────────────
// `visible: UiState.settingsWindowOpen` breaks: a killactive keybind assigns
// `visible = false` directly, destroying the binding — after which nothing can
// reopen it. So the state is mirrored by assignment in both directions.
//
// ── It stays open across an in-process reload ───────────────────────────────
// Quickshell.reload() (the bar's ReloadPill) tears down and rebuilds the QML
// scene, which used to take this window with it. shell.qml's `reloadCarry` hands
// `UiState.settingsWindowOpen` to the new generation EARLY ENOUGH that `visible`
// is already true when this window reloads — which is the condition
// ProxyWindowBase::onReload checks before adopting its previous toplevel. So the
// surface is reused and never unmaps: no flicker, no re-centring by
// hypr/rules.lua, same size and position.
//
// The ordering is the whole trick and it is not obvious — shell.qml documents it.
// A full process restart (ALT+Q) still closes this; nothing in-process can help
// there.
// ─────────────────────────────────────────────────────────────────────────────
FloatingWindow {
    id: win

    title: Translation.tr("Settings")

    // The opening size — re-applied on every open (see the header). Resizable
    // during a session down to where the rail + a capped column stop fitting.
    readonly property int openWidth: 1200
    readonly property int openHeight: 740

    implicitWidth:  openWidth
    implicitHeight: openHeight
    minimumSize: Qt.size(840, 560)

    color: "transparent"

    // Shown only in WINDOW mode — SettingsPanelHost (in Bar's window) takes over
    // while Config.settingsPanel is on.
    readonly property bool want: UiState.settingsWindowOpen && !Config.settingsPanel

    visible: false
    function _sync() {
        // `settingsWindowResuming` is an in-process reload handing the window back
        // (shell.qml's reloadCarry), NOT an open. The window adopts the surface it
        // already had, which still carries the size the user left it at — so the
        // reset below would be the one visible thing that gave the reload away.
        if (win.want && !win.visible && !UiState.settingsWindowResuming) {
            // Reset while hidden so it maps at the opening size, not the last
            // size it was dragged to. `implicitWidth`/`implicitHeight` hold the
            // STORED intent, not the live geometry — Quickshell only re-applies
            // a resize when the written value differs from that stored one, and
            // a drag never updates it. So priming from the actual current size
            // first is required, or writing the already-stored 1200×740 back is
            // a silent no-op and the window stays at its dragged size.
            win.implicitWidth  = win.width
            win.implicitHeight = win.height
            win.implicitWidth  = win.openWidth
            win.implicitHeight = win.openHeight
        }
        win.visible = win.want
    }
    Connections {
        target: UiState
        function onSettingsWindowOpenChanged() { win._sync() }
    }
    Connections {
        target: Config
        function onSettingsPanelChanged() { win._sync() }
    }
    // A killactive keybind unmaps the window directly — mirror that back. Skipped
    // when the panel is taking over (a mode switch, not a close).
    onVisibleChanged: if (!win.visible && !Config.settingsPanel) UiState.settingsWindowOpen = false

    Loader {
        anchors.fill: parent
        // Nothing is built until the window is shown — the pages shell out
        // (specs.sh, localectl) the moment they construct.
        active: win.visible
        onLoaded: if (item) item.forceActiveFocus()

        sourceComponent: SettingsCard {
            closable: true
            onCloseRequested: UiState.settingsWindowOpen = false

            // Keys attaches to an Item; a window is not one, but this card
            // (a Surface, i.e. a Rectangle) is. The Loader forceActiveFocus()es
            // it on load so Escape works before any click; TextInput does not
            // consume Escape, so a focused field does not swallow it.
            focus: true
            Keys.onEscapePressed: function(e) {
                UiState.settingsWindowOpen = false
                e.accepted = true
            }
        }
    }

    // ── The wave (components/Infection.qml) ───────────────────────────────────
    // The settings window takes a wallpaper/colour change on the same front as the
    // rest of the shell. A toplevel can't know where the compositor put it; the
    // window rule centres it on open, so that is where the front is timed from.
    Infection {
        host: win.contentItem
        screen: win.screen
        hostVisible: win.visible
        windowX: ((win.screen ? win.screen.width  : win.width)  - win.width)  / 2
        windowY: ((win.screen ? win.screen.height : win.height) - win.height) / 2
    }
}
