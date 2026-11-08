import QtQuick
import Quickshell
import "../../config"
import "../../components"

// ── WorkspaceChips ────────────────────────────────────────────────────────────
// The grid's page as numbered chips — ten, two rows of five like the grid itself, or one row
// (`columns`). Where the thing already is, is filled (`here`) and cannot be pressed; the rest
// answer a tap with `picked(ws)`. One copy for the inspector's "send it to…" and "swap with…"
// and the selection's "send them to…" (they were three copies of the same chip).
// ─────────────────────────────────────────────────────────────────────────────
Grid {
    id: root

    property int firstWorkspace: 1
    // The workspaces it is on now (filled, inert).
    property var here: []
    property color accent: Colors.of(QsWindow.window).primary

    signal picked(int ws)

    columns: 5
    spacing: Tokens.spacingXs

    Repeater {
        model: 10
        delegate: Rectangle {
            id: chip
            required property int index
            readonly property int ws: root.firstWorkspace + chip.index
            readonly property bool isHere: root.here.indexOf(chip.ws) >= 0
            readonly property bool hot: hover.hovered && !chip.isHere
            width: 30
            height: 30
            radius: height / 2
            color: chip.isHere ? root.accent
                 : chip.hot    ? Colors.of(QsWindow.window).alpha(root.accent, 0.22)
                 :               Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
            Behavior on color { ColorAnimation { duration: Motion.respond } }
            SpringValue {
                id: lean
                target: tap.pressed ? 0.88 : chip.hot ? 1.08 : 1
                spec: Motion.springSpatialFast
                epsilon: 0.001
            }
            scale: lean.value
            StyledText {
                anchors.centerIn: parent
                text: String(chip.ws)
                variant: "caption"
                font.weight: Font.DemiBold
                // ChipButton's rule for a glyph on a filled accent.
                color: !chip.isHere ? Colors.of(QsWindow.window).fg
                     : root.accent.hslLightness > 0.5 ? Colors.of(QsWindow.window).base : Colors.of(QsWindow.window).fg
            }
            HoverHandler { id: hover; cursorShape: chip.isHere ? Qt.ArrowCursor : Qt.PointingHandCursor }
            TapHandler { id: tap; enabled: !chip.isHere; onTapped: root.picked(chip.ws) }
        }
    }
}
