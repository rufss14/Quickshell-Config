import Quickshell
import QtQuick

// ── PanelHost ─────────────────────────────────────────────────────────────────
// What is left of the per-screen panel host: the Cava background, and nothing
// else.
//
// Every panel that used to live here has moved into Bar's own window
// (modules/bar/BarPanelDock.qml) — the LEFT and RIGHT groups first, and now the
// CENTRE one (system updates) as well. They all moved for the same reason: the
// `Quicktest.Blobs` metaball shader can only fuse shapes that share one Qt Quick
// scene graph, and two layer-shell surfaces are composited independently by
// Hyprland, so a panel in its own window can never melt into the bar.
//
// The centre slot's move cost one thing worth writing down: it used to be an
// Overlay-layer window, and Bar's is Top. A notification toast or the OSD can now
// draw over the update panel. Everything else about it — the request/mirror
// lifecycle, the exclusive keyboard grab for the sudo prompt, the fixed container
// with a self-sizing panel inside it — moved across intact.
//
// This file is one child away from being deletable: if CavaBG is ever given its
// own Variants in shell.qml, PanelHost goes with it.
// ─────────────────────────────────────────────────────────────────────────────
Scope {
    id: root

    required property var screen

    CavaBG { screen: root.screen }
}
