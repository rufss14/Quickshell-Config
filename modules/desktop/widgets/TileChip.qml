import QtQuick
import Quickshell
import "../../../config"
import "../../../components"

// ── TileChip ──────────────────────────────────────────────────────────────────
// A small icon button on a desktop tile: "check again", "next month", "refresh". It takes
// its own press, so the tile's tap (open the panel, page the month) does not also fire.
//
// It rests dim and wakes with the tile — `awake` is the tile's hover, passed in by the
// widget — so the controls are there without being furniture on a desktop you mostly
// just look at. `spin()` turns the icon once, for a tap whose result is not visible
// straight away (a refresh that takes a second).
//
// `icon` is a Material Symbols name (services/icons.js), not a Nerd Font glyph.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: chip

    property string icon: ""
    property bool awake: false
    // A small accent dot on the corner — "there is something here" (unread news).
    property bool dot: false
    property color accent: Colors.of(QsWindow.window).primary
    // The one main action of a tile (a timer's play): filled in the accent, like Material's
    // filled icon button. The rest stay tonal.
    property bool filled: false
    // The chip's side. The default is the header-chip size; a tile's main controls ask for more.
    property real box: Tokens.iconXl - Tokens.spacingSm
    signal activated()

    function spin() { turn.restart() }

    implicitWidth:  chip.box
    implicitHeight: chip.box
    // ── Material 3 Expressive: a tonal icon button ────────────────────────────
    // A solid fill one tone above the tile (`surfaceHigh` on the tile's `surfaceContainer`)
    // and Material's state layer over it — 8% on hover, a 10% wave from the press point —
    // instead of a fill that brightens by hand. Pressed, the corners square up (radiusSm →
    // radiusXs) and the chip dips, both on the fast spatial spring, so a tap is a little
    // squash that springs back: the expressive shape morph at chip size.
    readonly property real _rest: Tokens.corner(Config.barShape, Tokens.radiusSm)
    SpringValue {
        id: shape
        spec: Motion.springSpatialFast
        epsilon: 0.05
        target: mouse.pressed ? Tokens.corner(Config.barShape, Tokens.radiusXs) : chip._rest
    }
    SpringValue {
        id: dip
        spec: Motion.springSpatialFast
        epsilon: 0.0005
        target: mouse.pressed ? 0.88 : 1
    }
    radius: shape.value
    color: chip.filled ? chip.accent : Colors.of(QsWindow.window).surfaceHigh
    opacity: !chip.enabled ? 0.35 : chip.awake ? 1 : 0.4
    scale: dip.value

    Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

    StateLayer {
        id: feel
        anchors.fill: parent
        radius: chip.radius
        hovered: mouse.containsMouse
        layerColor: chip.filled ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fg
    }

    MaterialIcon {
        anchors.centerIn: parent
        name: chip.icon
        font.pixelSize: Math.round(chip.box * 0.55)
        color: chip.filled ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fg
        RotationAnimation on rotation {
            id: turn
            running: false
            from: 0; to: 360
            duration: Motion.slow
            easing.type: Motion.travel
        }
    }

    Rectangle {
        visible: chip.dot
        width: Tokens.spacingMd - Tokens.spacingXs; height: width; radius: width / 2
        anchors.top: parent.top; anchors.right: parent.right
        color: chip.accent
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: function (e) { feel.press(e.x, e.y) }
        onReleased: feel.release()
        onCanceled: feel.release()
        onClicked: { chip.spin(); chip.activated() }
    }
}
