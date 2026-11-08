import QtQuick
import Quickshell
import "../config"

// ── ChipButton ────────────────────────────────────────────────────────────────
// A round icon button for a ChipTray (a pill, once it has a label). Off, it is just an icon
// on the tray; on, it is a filled disc of its `tint` with the icon filled in (the FILL axis,
// animated) — an on state you can read at a glance, not by comparing two near greys.
//
// ── Moves like the rest of the redesigned panels ──────────────────────────────
// The disc leans toward the pointer and dips on a press on SPRINGS (overshoot, settle), as
// CookieButton does; a wash lights under the pointer when it is off. Disabled, it dims.
//
// ── `solid`: the circle is the colour, always ─────────────────────────────────
// Normally the disc is how you can tell it is ON. A chip that wants a colour of its own at
// all times (the media header's visualiser: palette colour 12) sets `solid`: the disc is
// always there in its tint, brighter on, softer off, and the icon says on/off by its fill.
// It is the CIRCLE that wears the colour — the icon stays the contrast colour on it.
//
// ── The icon is chosen for the fill ───────────────────────────────────────────
// `tint` is whatever the caller asks for (the panel's accent, or a palette colour), and an
// icon that is a fixed colour will vanish into some of them. So the icon on a filled disc is
// the palette's dark `base` on a light tint and its light text on a dark one, decided from
// the tint's lightness.
//
// ── With a label it is a pill ─────────────────────────────────────────────────
// `label` puts text after the icon and the chip widens to fit; the disc is the whole pill.
// `iconAngle` turns the icon alone (a refresh arrow spinning while it scans).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    // Screen readers (AT-SPI): what this is and what pressing it does. Keyboard focus
    // order is not wired yet — see docs/standards.md, Accessibility.
    Accessible.role: Accessible.Button
    Accessible.name: root.label !== "" ? root.label : root.symbol
    Accessible.checked: root.on
    Accessible.onPressAction: root.activated()

    // A Material Symbols name.
    property string symbol: ""
    property string label:  ""
    // An SVG drawn as a stencil in the icon's colour (TintedIcon), for a mark no font has — Quickshell's gear on
    // the update panel's shell-update chip. Wins over `symbol`.
    property url    iconSource: ""
    // The label's size in the type scale ("label" by default; a chip whose text IS the content — the clock panel's
    // °C / °F — asks for "title").
    property string labelVariant: "label"
    // How heavy the label is. Medium by default; a chip whose whole job is a short code (the karaoke mods: HD, HR,
    // TH) asks for more, so two letters stay legible at the chip's size.
    property int    labelWeight: Font.Medium
    property bool   on:     false
    property bool   solid:  false
    // Whether the icon fills in (the FILL axis) when the chip is on. Most do; a glyph whose filled
    // form turns to a blob — the `palette` one loses its paint dots — keeps its outline.
    property bool   fillIcon: true
    // A small disc of this colour before the label, so a chip can SHOW what it will do (the colours
    // panel's harmony chips each carry the accent they would give). Transparent = none.
    property color  dot: "transparent"
    property color  tint:   Colors.of(QsWindow.window).primary
    property real   iconAngle: 0

    // Held down right now — for a chip that acts while it is held (the colours panel's Peek).
    readonly property alias pressed: tap.pressed

    signal activated()

    readonly property int _h: Tokens.iconXl + Tokens.spacingXs
    implicitHeight: root._h
    readonly property bool _hasDot: root.dot.a > 0
    readonly property real _dotW:   root._hasDot ? Tokens.iconSm - 2 + Tokens.spacingXs : 0
    implicitWidth:  root.label === "" ? root._h
                  : root.symbol === "" ? Tokens.spacingLg * 2 + root._dotW + text.implicitWidth
                  : Tokens.spacingMd + glyph.implicitWidth + Tokens.spacingXs + root._dotW + text.implicitWidth + Tokens.spacingLg

    opacity: root.enabled ? 1.0 : 0.35
    Behavior on opacity { NumberAnimation { duration: Motion.respond } }

    readonly property bool _hot: hover.hovered && root.enabled
    readonly property bool _filled: root.on || root.solid
    readonly property color _onIcon: root.tint.hslLightness > 0.5
        ? Colors.of(QsWindow.window).base : Colors.of(QsWindow.window).fg

    // M3E springs (SpringValue), not Qt's SpringAnimation: that steps at 16 ms and stair-steps on a 165 Hz screen.
    SpringValue {
        id: leanSpring
        target: tap.pressed ? 0.88 : (root._hot ? 1.07 : 1.0)
        spec: Motion.springSpatialFast
        epsilon: 0.001
    }
    SpringValue {
        id: discSpring
        target: root._filled ? 1 : 0.4
        spec: Motion.springSpatial
        epsilon: 0.002
    }
    scale: leanSpring.value

    // The hover wash, while not filled.
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
        opacity: !root._filled && root._hot ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
    }

    // The disc (the whole pill, with a label). It grows from the middle rather than fading,
    // so switching on reads as the chip filling. `solid` keeps it up: full when on, softer off.
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.tint
        scale:   discSpring.value
        opacity: root.on ? 1 : (root.solid ? 0.55 : 0)
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
        Behavior on color   { ColorAnimation  { duration: Motion.standard } }
    }

    Row {
        anchors.centerIn: parent
        spacing: Tokens.spacingXs

        Loader {
            anchors.verticalCenter: parent.verticalCenter
            active:  root.iconSource.toString() !== ""
            visible: active
            rotation: root.iconAngle
            sourceComponent: TintedIcon {
                source: root.iconSource
                size:   Tokens.iconLg - 2
                color:  root._filled ? root._onIcon
                      : root._hot    ? Colors.of(QsWindow.window).fg
                      :                Colors.of(QsWindow.window).fgMuted
            }
        }
        MaterialIcon {
            id: glyph
            anchors.verticalCenter: parent.verticalCenter
            visible: root.iconSource.toString() === ""
            name:  root.symbol
            fill:  root.on && root.fillIcon ? 1 : 0
            rotation: root.iconAngle
            font.pixelSize: Tokens.iconLg
            // On a filled disc: the contrast colour. A `solid` chip that is OFF sits on a softer
            // disc, where it is the contrast colour too — the circle is the colour, not the icon.
            color: root._filled ? root._onIcon
                 : root._hot    ? Colors.of(QsWindow.window).fg
                 :                Colors.of(QsWindow.window).fgMuted
            Behavior on fill  { NumberAnimation { duration: Motion.standard } }
            Behavior on color { ColorAnimation  { duration: Motion.standard } }
        }
        // What the chip would give, as a disc — outlined, so it holds on the chip's own disc.
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: root._hasDot
            width:  Tokens.iconSm - 2
            height: width
            radius: width / 2
            color:  root.dot
            border.width: Tokens.borderWidth
            border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.35)
            Behavior on color { ColorAnimation { duration: Motion.track } }
        }
        StyledText {
            id: text
            anchors.verticalCenter: parent.verticalCenter
            visible: root.label !== ""
            text: root.label
            variant: root.labelVariant
            font.weight: root.labelWeight
            color: root._filled ? root._onIcon
                 : root._hot    ? Colors.of(QsWindow.window).fg
                 :                Colors.of(QsWindow.window).fgMuted
            Behavior on color { ColorAnimation { duration: Motion.standard } }
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        id: tap
        enabled: root.enabled
        onTapped: root.activated()
    }
}
