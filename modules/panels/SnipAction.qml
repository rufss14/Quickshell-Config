import QtQuick
import Quickshell
import "../../config"
import "../../components"

// ── SnipAction ────────────────────────────────────────────────────────────────
// One button of the snip toolbar, Material 3 Expressive's button-group idea: every action is
// a round icon tile, and the ONE that Enter would do (`active`) is the filled, expanded one —
// it grows on the spatial spring to show its name and the ⏎ keycap, while the others make room.
// Clicking another does it and becomes the new active one (Snip.pickAction), so the filled
// button always tells the truth about what Enter does.
//
// A press squares the corners (pill → radiusSm) and dips the tile on the fast spring, as
// TileChip does. A tile that can't run (`blocked` is the reason, "" when fine) is dimmed and
// ignores clicks; the toolbar's hint line says why.
//
// The keycap on the expanded button is ⏎ by default (the snip toolbar: Enter does it). The
// annotator's tools show their own key instead: `capText: "P"`, `capSymbol: ""`.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string symbol: ""
    property string label: ""
    property string key: ""
    // An icon the font only has one way round: turned (an up arrow as a north-east one) or mirrored
    // (undo as redo). Spares the font a name each.
    property real symbolAngle: 0
    property bool symbolFlip: false
    property string capSymbol: "keyboard_return"
    property string capText: ""
    property bool active: false
    property string blocked: ""
    // Revealed one after another as the toolbar arrives (0 → 1), set by the toolbar.
    property real reveal: 1
    signal activated()

    readonly property bool hovered: mouse.containsMouse
    readonly property color _fg: root.active ? Colors.of(QsWindow.window).fgOnPrimary
                                             : Colors.of(QsWindow.window).fg

    readonly property real tile: Tokens.iconXl + Tokens.spacingLg
    // What the expanded button needs: pad, icon, gap, name, gap, ⏎ keycap, pad. Measured from
    // items that always exist, so the width never depends on how far it has grown.
    readonly property real wide: Tokens.spacingLg * 2 + Tokens.iconLg + Tokens.spacingSm
                                 + title.implicitWidth + Tokens.spacingSm + enterCap.implicitWidth

    SpringValue {
        id: grow
        spec: Motion.springSpatial
        epsilon: 0.05
        target: root.active ? root.wide : root.tile
    }
    SpringValue {
        id: shape
        spec: Motion.springSpatialFast
        epsilon: 0.05
        target: Tokens.corner(Config.barShape, mouse.pressed ? Tokens.radiusSm : root.tile / 2)
    }
    SpringValue {
        id: dip
        spec: Motion.springSpatialFast
        epsilon: 0.0005
        target: mouse.pressed ? 0.92 : 1
    }

    // 0 = a tile, 1 = fully expanded.
    readonly property real open: Math.max(0, Math.min(1, (grow.value - root.tile) / Math.max(1, root.wide - root.tile)))

    implicitWidth: grow.value
    implicitHeight: root.tile
    width: implicitWidth
    height: implicitHeight
    opacity: root.reveal * (root.blocked !== "" ? 0.38 : 1)
    scale: dip.value
    transform: Translate { y: (1 - root.reveal) * Tokens.spacingSm }

    Rectangle {
        id: plate
        anchors.fill: parent
        radius: shape.value
        color: Colors.of(QsWindow.window).primary
        opacity: root.open
        visible: opacity > 0.01
    }

    StateLayer {
        id: feel
        anchors.fill: parent
        radius: plate.radius
        hovered: mouse.containsMouse && root.blocked === ""
        layerColor: root._fg
    }

    MaterialIcon {
        id: glyph
        name: root.symbol
        font.pixelSize: Tokens.iconLg
        color: root._fg
        fill: root.active ? 1 : 0
        rotation: root.symbolAngle
        transform: Scale { origin.x: glyph.width / 2; xScale: root.symbolFlip ? -1 : 1 }
        // Centred as a tile, tucked to the left once it has a name beside it.
        x: (root.width - width) / 2 * (1 - root.open) + Tokens.spacingLg * root.open
        anchors.verticalCenter: parent.verticalCenter
    }
    StyledText {
        id: title
        text: root.label
        variant: "label"
        font.weight: Font.Medium
        color: root._fg
        x: glyph.x + glyph.width + Tokens.spacingSm
        anchors.verticalCenter: parent.verticalCenter
        opacity: root.open * root.open
    }
    SnipKeyCap {
        id: enterCap
        symbol: root.capSymbol
        text: root.capText
        visible: root.capSymbol !== "" || root.capText !== ""
        onFilled: true
        x: title.x + title.implicitWidth + Tokens.spacingSm
        anchors.verticalCenter: parent.verticalCenter
        opacity: root.open * root.open
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.blocked === ""
        cursorShape: root.blocked === "" ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPressed: function (e) { feel.press(e.x, e.y) }
        onReleased: feel.release()
        onCanceled: feel.release()
        onClicked: root.activated()
    }
}
