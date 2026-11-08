import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"

// ── A small card that opens under the panel's header ──────────────────────────
// For a few controls that don't earn a place in the header's row: the parallax switches, the library's
// sort / filter / shuffle. It opens from its top-right corner on a spring (a touch of overshoot, as
// Material 3 Expressive menus do) and fades on the faster effects spring; closed, it is not visible.
// One at a time is the panel's rule (`WallpaperPanel.popover`); a click anywhere else closes it.
//
// Children go in the column. `offsetY` is where its top edge sits in the panel. The panel is a fixed pin
// (BarPanelDock), so the card never grows past it: taller content scrolls inside the card, not off the
// bottom of the panel where it was clipped.
Rectangle {
    id: pop

    property bool open: false
    property int  popWidth: 240
    property real offsetY: 0

    default property alias content: col.data

    SpringValue { id: grow; target: pop.open ? 1 : 0; spec: Motion.springSpatialFast; epsilon: 0.002 }
    SpringValue { id: fade; target: pop.open ? 1 : 0; spec: Motion.springEffectsFast }

    z: 20
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: pop.offsetY
    anchors.rightMargin: Tokens.spacingLg
    width: pop.popWidth
    implicitHeight: col.implicitHeight + Tokens.spacingMd * 2
    height: Math.min(pop.implicitHeight, Math.max(0, pop.parent.height - pop.offsetY - Tokens.spacingMd))
    radius: Tokens.radiusCard
    color: Colors.of(QsWindow.window).surfaceHigh
    border.width: Tokens.borderWidth
    border.color: Colors.of(QsWindow.window).outline
    opacity: Math.min(1, Math.max(0, fade.value))
    visible: pop.open || fade.value > 0.005
    scale: 0.9 + 0.1 * Math.max(0, grow.value)
    transformOrigin: Item.TopRight

    Flickable {
        id: fl
        anchors.fill: parent
        anchors.margins: Tokens.spacingMd
        contentWidth: width
        contentHeight: col.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ColumnLayout {
            id: col
            width: fl.width
            spacing: Tokens.spacingSm
        }
    }
    Scrollbar { flickable: fl }
}
