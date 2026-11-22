import QtQuick
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services/spacer.js" as Spacer

// ── SpacerPill ────────────────────────────────────────────────────────────────
// Nothing, with a width: room between two modules. The width is Config.spacerSize(), plus
// the width of the module it follows ("grow"), or that size less it ("fill"); services/spacer.js.
//
// `slots` is the bar's map of module id to its slot Item (Bar.moduleSlots); reading the
// slot's own width keeps this live while the followed module animates its. A hidden module
// (an empty tray, a desktop's battery) counts as 0 wide. What it may follow is Config's rule.
//
// It draws nothing, except while `guide` is on (arranging the bar, a library tile): then it
// shows as a module, a glyph in a pill at least as wide as any icon pill, so it can be seen,
// picked up and dropped. `chip` adds the nested pill the group draws behind every other module
// (the real bar; a library tile shows the bare widget, as the other tiles do).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property var slots: ({})
    property bool guide: false
    property bool chip: false

    readonly property var target: Config.spacerFollow() !== "" ? (root.slots[Config.spacerFollow()] ?? null) : null
    readonly property real followWidth: root.target && root.target.visible
                                        ? Math.max(0, root.target.width - root.target.gapBefore) : 0

    implicitWidth: Math.ceil(Spacer.length(Config.spacerSize(), root.followWidth, Config.spacerFill(),
                                           root.guide ? Tokens.pillHeight + Tokens.spacingSm * 2 : 0))
    implicitHeight: Tokens.pillHeight

    // The group's inner pill, as it stands round any other module (BarGroup).
    Surface {
        visible: root.guide && root.chip
        anchors.fill: parent
        anchors.topMargin: -Tokens.spacingXs
        anchors.bottomMargin: -Tokens.spacingXs
        elevation:    Tokens.elevationNested
        squareMode:   Config.barShape
        cornerRadius: Config.barRoundness
        borderWidth:  0
        castsShadow:  false
        fillOpacity:  Tokens.barOpacity
        itemOpacity:  Config.screenFrame && !Colors.of(QsWindow.window).veiled ? Tokens.surfaceOpacity : 1.0
        color: Colors.of(QsWindow.window).veiled ? Colors.of(QsWindow.window).wash
             : !Config.screenFrame ? Colors.of(QsWindow.window).frameFill
             : Colors.of(QsWindow.window).fade(Colors.of(QsWindow.window).surfaceFor(Tokens.elevationNested), Tokens.barOpacity)
    }

    MaterialIcon {
        visible: root.guide
        anchors.centerIn: parent
        name: "swap_horiz"
        color: Colors.of(QsWindow.window).stateIdleFg
        font.pixelSize: Tokens.iconMd
    }
}
