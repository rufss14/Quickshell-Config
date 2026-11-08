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

// DockFocusRing — DockIconStrip's inline `FocusRing`, moved into its own file (2026-11-08).
// Where the keyboard is, while it's on the dock.
Rectangle {
    // The DockIconStrip this belongs to (its state and its actions; was `root`).
    required property var strip
    anchors.fill: parent
    radius: strip.cellRadius
    color: "transparent"
    border.width: Tokens.borderChrome
    border.color: Colors.of(QsWindow.window).focus
}
