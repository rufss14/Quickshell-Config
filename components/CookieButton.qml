import QtQuick
import Quickshell
import "../config"

// ── CookieButton ──────────────────────────────────────────────────────────────
// A scalloped "cookie" button — a rounded N-pointed star (Material-3-Expressive),
// the shape a few popular shells use for media/session controls. `primary` fills
// it with `tint`; otherwise it is outlined and its fill tints on hover.
//
// ── Alive, not tweened ────────────────────────────────────────────────────────
// It moves on a SPRING, not an eased curve. Point at it and the cookie winds, leans in and
// its petals deepen — and because a spring overshoots and settles, it reads as a thing with
// weight rather than a property being interpolated; let go mid-turn and it carries on
// from where it was instead of restarting. Press and it winds the other way and dips.
//
// What else it does, each for a reason:
//   • `checked`   a toggle that is ON (shuffle, loop): the fill comes up, the outline
//                 firms, the icon fills in (the FILL axis, animated) — an on state you can
//                 read without comparing colours.
//   • `spinning`  turns slowly for as long as it is true (the play button, while a track
//                 plays), and when it stops it settles onto the nearest petal-aligned angle
//                 rather than freezing wherever it happened to be.
//   • a ring      a thin cookie-shaped ripple leaves the button when it is pressed and
//                 fades, so a tap is acknowledged even when nothing else on screen changes.
//   • a swap      when the icon changes (play ↔ pause) it squashes to a speck, changes,
//                 and comes back, rather than cutting.
//
// ── The icon never rotates ────────────────────────────────────────────────────
// Only the cookie BODY turns; the icon sits still on top of it. An earlier version turned the
// whole button and counter-rotated the icon to keep it upright — fine for a hover wind that
// lasts a moment, but for the play button, which spins for as long as music plays, it meant a
// glyph being re-rotated and re-rasterised every frame, which shows as a faint shimmer and
// wobble on the icon. Not rotating it at all is both simpler and crisp.
//
// `restTilt` is a fixed tilt the wind adds onto — give a left/right pair opposite
// values and they read as mirror images of each other.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string glyph:       ""
    // A Material Symbols name ("play_arrow"); wins over `glyph` (MaterialIcon's own rule).
    property string name:        ""
    property color  tint:        Colors.of(QsWindow.window).focus
    property color  glyphOnFill: Colors.of(QsWindow.window).fgOnPrimary   // glyph colour while `primary`
    property bool   primary:     false
    // A toggle that is on. Ignored while `primary` (that is always filled).
    property bool   checked:     false
    // Turns slowly while true.
    property bool   spinning:    false
    property int    points:      9
    property real   restTilt:    0
    property real   petalDepth:  0.13

    signal activated()

    opacity: root.enabled ? 1.0 : 0.32
    Behavior on opacity { NumberAnimation { duration: Motion.respond } }

    readonly property bool _hot: hover.hovered && root.enabled
    readonly property bool _lit: root.primary || root.checked

    // ── The springs ───────────────────────────────────────────────────────────
    // `wind`: 0 at rest, +1 pointed at, −1 pressed. `lean`: the size it wants to be. Both
    // are springs with a little give — overshoot, then settle.
    property real wind: tap.pressed ? -1 : (root._hot ? 1 : 0)
    Behavior on wind { SpringAnimation { spring: 4.5; damping: 0.30; epsilon: 0.005 } }

    property real lean: tap.pressed ? 0.88 : (root._hot ? 1.07 : 1.0)
    Behavior on lean { SpringAnimation { spring: 6.0; damping: 0.34; epsilon: 0.002 } }

    // ── The slow turn ─────────────────────────────────────────────────────────
    // Advanced by hand each frame while `spinning` (a whole turn in 14s). When it stops,
    // `spin` is moved to the nearest multiple of one petal (360 ÷ points), which the Behavior
    // below eases — and which looks exactly like the angle it was at, because the shape repeats
    // every petal. So it comes to rest upright and symmetric instead of at a random tilt.
    // The Behavior is off while turning, or it would smooth every frame's step into a lag.
    property real spin: 0
    FrameAnimation {
        running: root.spinning && root.visible
        onTriggered: root.spin += frameTime * (360 / 14)
    }
    Behavior on spin {
        enabled: !root.spinning
        NumberAnimation { duration: Motion.slow; easing.type: Motion.overshoot }
    }
    onSpinningChanged: {
        if (root.spinning) return
        const petal = 360 / Math.max(1, root.points)
        root.spin = Math.round(root.spin / petal) * petal
    }

    scale: root.lean

    // ── The body: the only thing that turns ───────────────────────────────────
    Item {
        id: shapeBox
        anchors.fill: parent
        rotation: root.restTilt + (root.wind > 0 ? 14 * root.wind : 11 * root.wind) + root.spin

        // The silhouette itself lives in Scallop — one definition of the shape, shared
        // with every card's ScallopChip, so the button and the chip cannot drift apart.
        Scallop {
            id: body
            anchors.fill: parent
            points:     root.points
            petalDepth: root.petalDepth + 0.07 * Math.max(0, root.wind) + (root._lit ? 0.02 : 0)
            fillColor:  root.primary ? root.tint
                      : root.checked ? Colors.of(QsWindow.window).alpha(root.tint, root._hot ? 0.42 : 0.34)
                      : root._hot    ? Colors.of(QsWindow.window).alpha(root.tint, 0.20)
                      :                Colors.of(QsWindow.window).alpha(root.tint, 0.07)
            strokeColor: root.primary ? "transparent"
                       : Colors.of(QsWindow.window).alpha(root.tint, root.checked ? 0.85 : (root._hot ? 0.60 : 0.32))

            Behavior on fillColor   { ColorAnimation { duration: Motion.standard } }
            Behavior on strokeColor { ColorAnimation { duration: Motion.standard } }
        }

        // The ring a tap leaves behind.
        Scallop {
            id: ring
            anchors.fill: parent
            points: root.points
            petalDepth: root.petalDepth
            strokeColor: Colors.of(QsWindow.window).alpha(root.tint, 0.7)
            strokeWidth: 2
            opacity: 0
            visible: opacity > 0.01
            transformOrigin: Item.Center
        }
    }
    ParallelAnimation {
        id: pulse
        NumberAnimation { target: ring; property: "scale";   from: 1.0; to: 1.55; duration: Motion.slow; easing.type: Motion.expressive }
        NumberAnimation { target: ring; property: "opacity"; from: 0.7; to: 0.0;  duration: Motion.slow; easing.type: Motion.exitCurve }
    }

    // ── The icon, swapped through a squash ────────────────────────────────────
    // `_name`/`_glyph` are what is DRAWN; they take the new values at the bottom of the
    // squash, so the change happens while the icon is a speck instead of cutting in full
    // size. Set directly once on creation: a button that has just appeared does not need
    // to animate into its own icon.
    property string _name: ""
    property string _glyph: ""
    // Change handlers fire for values given at instantiation too; only a change AFTER the
    // button exists is a swap worth animating.
    property bool _ready: false
    Component.onCompleted: { root._name = root.name; root._glyph = root.glyph; root._ready = true }
    onNameChanged:  if (root._ready) swap.restart()
    onGlyphChanged: if (root._ready) swap.restart()

    SequentialAnimation {
        id: swap
        NumberAnimation { target: iconBox; property: "scale"; to: 0.15
                          duration: Motion.respond; easing.type: Motion.exitCurve }
        ScriptAction { script: { root._name = root.name; root._glyph = root.glyph } }
        NumberAnimation { target: iconBox; property: "scale"; to: 1.0
                          duration: Motion.standard; easing.type: Motion.overshoot }
    }

    Item {
        id: iconBox
        anchors.centerIn: parent
        width:  parent.width
        height: parent.height

        MaterialIcon {
            anchors.centerIn: parent
            name:  root._name
            glyph: root._glyph
            fill:  root._lit ? 1 : 0
            color: root.primary ? root.glyphOnFill : root.tint
            font.pixelSize: Math.round(Math.min(root.width, root.height) * 0.46)
            Behavior on fill  { NumberAnimation { duration: Motion.standard } }
            Behavior on color { ColorAnimation  { duration: Motion.standard } }
        }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        id: tap
        enabled: root.enabled
        onPressedChanged: if (pressed) pulse.restart()
        onTapped: root.activated()
    }
}
