import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── WorkspaceMap ──────────────────────────────────────────────────────────────
// The grid's page as ONE row of ten small cells — a map, where WorkspaceChips is a keypad: where the thing
// is now is filled (`here`, inert), a workspace with windows on it is tonal, an empty one is quiet, so you
// see where to send it and what is already there before you click. A tap answers with `picked(ws)`.
// One line tall (the inspector's "send it to…" was two rows of five and set the island's width).
// ─────────────────────────────────────────────────────────────────────────────
Row {
    id: root

    property int firstWorkspace: 1
    // The workspaces it is on now (filled, inert).
    property var here: []
    property color accent: Colors.of(QsWindow.window).primary

    signal picked(int ws)

    spacing: Tokens.spacingXs - 1

    Repeater {
        model: 10
        delegate: Item {
            id: cell
            required property int index
            readonly property int ws: root.firstWorkspace + cell.index
            readonly property bool isHere: root.here.indexOf(cell.ws) >= 0
            readonly property bool busy: (Hypr.countByWorkspace[cell.ws] ?? 0) > 0
            readonly property bool hot: hover.hovered && !cell.isHere
            width: 25
            height: 22

            SpringValue {
                id: lean
                target: tap.pressed ? 0.9 : cell.hot ? 1.1 : 1
                spec: Motion.springSpatialFast
                epsilon: 0.001
            }
            scale: lean.value

            Rectangle {
                anchors.fill: parent
                radius: Tokens.radiusXs + 2
                color: cell.isHere ? root.accent
                     : cell.hot    ? Colors.of(QsWindow.window).alpha(root.accent, 0.5)
                     : cell.busy   ? Colors.of(QsWindow.window).primaryContainer
                     :               Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
                Behavior on color { ColorAnimation { duration: Motion.respond } }
            }
            StyledText {
                anchors.centerIn: parent
                text: String(cell.ws)
                variant: "caption"
                font.weight: cell.isHere ? Font.Bold : Font.Medium
                color: cell.isHere ? (root.accent.hslLightness > 0.5 ? Colors.of(QsWindow.window).base : Colors.of(QsWindow.window).fg)
                     : cell.busy   ? Colors.of(QsWindow.window).fgOnPrimaryContainer
                     :               Colors.of(QsWindow.window).fgMuted
            }
            HoverHandler { id: hover; cursorShape: cell.isHere ? Qt.ArrowCursor : Qt.PointingHandCursor }
            TapHandler { id: tap; enabled: !cell.isHere; onTapped: root.picked(cell.ws) }
        }
    }
}
