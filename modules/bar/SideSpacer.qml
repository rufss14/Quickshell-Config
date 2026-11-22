import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../state"

// ── SideSpacer ────────────────────────────────────────────────────────────────
// The spacer module's sidebar form: nothing, along `length` (SideRail.smallLengths works it
// out from the module's settings, SideGroupHost hands it over). It has no inner pill, so the
// region's pill is split round it and it reads as a gap.
//
// Arranging the sidebar, and in a library tile (`preview`), it shows as a module: a glyph in
// a cell, on its own inner pill while arranging, as every other module does. The rail lifts
// it to one cell then, so it can be picked up.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool vertical: true
    property string moduleId: "spacer"
    // Its length along the edge, from the rail; 0 until it is told.
    property real length: 0
    // A library tile: shown as a module, with no pill behind it.
    property bool preview: false

    readonly property bool editing: root.preview || UiState.sidebarArrange
    readonly property real along: root.editing ? Math.max(root.length, Config.sidebarCell) : root.length

    implicitWidth:  root.vertical ? Config.sidebarCell : root.along
    implicitHeight: root.vertical ? root.along : Config.sidebarCell

    // The pill the region would have drawn under any other module (SideRegionPills).
    SidePill {
        visible: UiState.sidebarArrange
        anchors.centerIn: parent
        width:  root.vertical ? Config.sidebarPillCross : root.width + Tokens.spacingSm * 2
        height: root.vertical ? root.height + Tokens.spacingSm * 2 : Config.sidebarPillCross
        role: "inner"
    }

    MaterialIcon {
        visible: root.editing
        anchors.centerIn: parent
        name: root.vertical ? "swap_vert" : "swap_horiz"
        color: Colors.of(QsWindow.window).stateIdleFg
        font.pixelSize: Config.sidebarGlyphPx
    }
}
