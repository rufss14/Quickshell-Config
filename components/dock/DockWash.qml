pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Pipewire
import "../../config"
import "../../services"
import "../../state"
import "../../services/dock.js" as DockJs
import "../../services/workspaces.js" as Wsp
import ".."
import "."

// DockWash — DockIconStrip's inline `Wash`, moved into its own file (2026-11-08).
// The press/hover wash every button shares — the house StateLayer, driven by
// the button's own MouseArea (it has no handler of its own; see StateLayer).
CellFeedback {
    // The DockIconStrip this belongs to (its state and its actions; was `root`).
    required property var strip
    anchors.fill: parent
    radius: strip.cellRadius
    barLadder: strip.flat
    accent: strip.flat ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fg
}
