import QtQuick
import Quickshell
import Quickshell.Hyprland

// ── ScreenOwner ───────────────────────────────────────────────────────────────
// Which screen shows a one-screen overlay (the OSD, the cheatsheet, the welcome
// card, the screenshot toast and its annotator): the monitor you're on WHEN IT
// OPENS. Non-visual, like ArmLatch — each overlay keeps its own look and binds
// its visibility to `owns`.
//
// ── Why captured, not live ────────────────────────────────────────────────────
// Focus follows the mouse here, so the focused monitor changes whenever the
// pointer crosses a screen edge. Bound live, an open cheatsheet would vanish
// from one screen and reappear on the other mid-read. Captured on the rising
// edge of `open` (and never cleared), it stays put for its whole life — fade-out
// included, the same "a fading surface keeps its own copy" rule as everywhere.
//
// ── What it replaced ──────────────────────────────────────────────────────────
// `UiState.activeScreen` — the screen of the last BAR interaction — which is
// stale for anything a keypress opens. It only looked right because each overlay
// also redeclared `screen` (shadowing PanelWindow's own), so the surface never
// learned its output and Hyprland put it on the focused monitor by accident.
// ─────────────────────────────────────────────────────────────────────────────
QtObject {
    id: root

    // The overlay's own screen (a ShellScreen) and whether it's open.
    property var  screen: null
    property bool open: false

    property string _owner: ""

    function _capture() {
        root._owner = Hyprland.focusedMonitor?.name ?? ""
    }

    onOpenChanged: if (root.open) root._capture()
    Component.onCompleted: if (root.open) root._capture()

    // Nothing captured yet (Hyprland hadn't named a focused monitor): the first
    // screen, so an overlay open at startup still appears somewhere.
    readonly property bool owns: root._owner !== ""
        ? root._owner === (root.screen?.name ?? "")
        : root.screen === Quickshell.screens[0]
}
