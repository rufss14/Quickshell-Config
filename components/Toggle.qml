import QtQuick
import Quickshell
import "../config"
import "../services"

// ── Toggle ────────────────────────────────────────────────────────────────────
// A switch. On = a FILLED accent track with a check; off = an outlined track with a
// cross.
//
// `primary` would be wrong here: a switch shows STATE, not an invitation to act,
// so it takes `focus` — the same role as the slider fill and the "this is open"
// outline.
//
// ── Why the thumb carries a glyph ─────────────────────────────────────────────
// This used to be a plain track and a plain dot, distinguished by fill alone: the
// accent at 80% when on, `fg` at 15% when off. That is a real legibility problem on
// this palette specifically, and the reason is documented one file over in
// docs/settings-style.md §1 — a wallpaper-extracted accent can land anywhere,
// including on a desaturated grey barely distinguishable from the off track. A page
// of eleven toggles (LockPage) then has no state you can read at a glance.
//
// The glyph settles it without depending on the palette at all: ✓ and ✕ differ in
// SHAPE, so the control survives an accent that happens to be grey, a light theme,
// and being looked at by someone who cannot separate the two hues. The fill still
// does the work when it can; the glyph is what makes it never the only signal.
//
// ── The colour inversion is deliberate ────────────────────────────────────────
// On:  a filled accent track, a DARK thumb, and the check drawn in the accent.
// Off: a hollow track, a LIGHT thumb, and the cross drawn dark.
// So the thumb flips contrast with the track it sits on, which is what keeps it
// visible in both states. `fgOnPrimary` is the role for "drawn on an accent fill",
// and it is what the dark thumb and the dark cross both use.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root
    // Screen readers (AT-SPI): what this is and what pressing it does. Keyboard focus
    // order is not wired yet — see docs/standards.md, Accessibility.
    // SettingRow fills accessibleName from its label when the caller doesn't.
    property string accessibleName: ""
    Accessible.role: Accessible.CheckBox
    Accessible.name: root.accessibleName
    Accessible.checkable: true
    Accessible.checked: root.checked
    Accessible.onPressAction: root.toggled()
    Accessible.onToggleAction: root.toggled()

    property bool  checked: false
    property color accent:  Colors.of(QsWindow.window).primary

    signal toggled()

    // 52×30, up from 44×24. Sized so the thumb has room for a glyph that is still
    // legible at this type scale — at the old 18px thumb a check rendered as a
    // smudge, which is worse than no glyph because it reads as dirt on the screen.
    // Material 3's switch: a 52×32 capsule (2026-11-09, M3E; was 52×30 with a soft-rectangle track).
    implicitWidth:  52
    implicitHeight: 32
    radius: height / 2

    color: root.checked ? Colors.of(QsWindow.window).alpha(root.accent, toggleHover.containsMouse ? 1.0 : 0.92)
                        : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, toggleHover.containsMouse ? 0.16 : 0.10)

    // A filled track needs no outline — the fill IS the edge. A hollow one is drawn
    // entirely by its border, so it gets the heavier chrome weight.
    border.width: root.checked ? 0 : Tokens.borderChrome
    border.color: Colors.of(QsWindow.window).outline

    Behavior on color        { ColorAnimation { duration: Motion.fast } }
    Behavior on border.color { ColorAnimation { duration: Motion.fast } }

    // Dips under the finger and springs back. A switch is the most-pressed control
    // in settings, and the press is the only moment it can acknowledge you before
    // the state it controls catches up.
    scale: toggleHover.pressed ? 0.94 : 1.0
    Behavior on scale {
        NumberAnimation {
            duration: Motion.respond
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.spring
        }
    }

    Rectangle {
        id: thumb

        // Grows on the way in. A thumb that only slides reads as a dot moving; one
        // that also swells reads as a switch engaging, which is the whole point of
        // the gesture.
        // 20 off, 24 on and 28 under the finger (Material 3's 16/24/28, the off one kept at 20 so its cross
        // stays legible). The press grows it on the same spring as the rest.
        readonly property int size: toggleHover.pressed ? 28 : (root.checked ? 24 : 20)

        // ── Squash and stretch ────────────────────────────────────────────────
        // The thumb smears in the direction of travel and settles back — the oldest
        // trick in animation, and the reason this reads as a physical object being
        // thrown rather than a dot being repositioned. It works out for free from the
        // x formula below: unchecked, x is pinned to the left, so extra width grows
        // rightward; checked, x is derived from the right edge, so it grows leftward.
        // Either way the trailing edge is what stretches.
        property real stretch: 1.0
        // A smear for a state change only: pressing grows the thumb, and that is not a throw.
        Connections { target: root; function onCheckedChanged() { stretchAnim.restart() } }

        SequentialAnimation {
            id: stretchAnim
            NumberAnimation {
                target: thumb; property: "stretch"; to: 1.45
                duration: Motion.respond; easing.type: Motion.respondCurve
            }
            NumberAnimation {
                target: thumb; property: "stretch"; to: 1.0
                duration: Motion.standard
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring
            }
        }

        width:  Math.round(thumb.size * thumb.stretch)
        height: thumb.size
        radius: height / 2

        color: root.checked ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fgMuted

        anchors.verticalCenter: parent.verticalCenter
        // Equal air on every side, whatever size the thumb is at.
        readonly property real inset: (root.height - thumb.height) / 2
        x: root.checked ? parent.width - width - thumb.inset : thumb.inset

        // Spring, not travel: the thumb runs past its stop and settles back, which is
        // what a physical switch does. `Motion.spring`'s 1.21 control point IS the
        // overshoot — see Motion.qml. The swell rides the same curve so the grow and
        // the slide land together rather than finishing a frame apart.
        Behavior on width  { NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring } }
        Behavior on height { NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring } }
        Behavior on x      { NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring } }
        Behavior on color  { ColorAnimation  { duration: Motion.fast } }

        // The state layer: a halo behind the thumb, 8% under the pointer and 10% pressed (Tokens.state*). It is
        // the on-track's ink on, the text colour off, so it reads on either.
        Rectangle {
            z: -1
            anchors.centerIn: parent
            width: 40
            height: 40
            radius: 20
            color: Colors.of(QsWindow.window).alpha(root.checked ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fg,
                                                    toggleHover.pressed ? Tokens.statePress
                                                    : toggleHover.containsMouse ? Tokens.stateHover : 0)
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        // Both glyphs are always instantiated and cross-fade. Swapping `text` on one
        // Text would snap between them, and a switch is the one control where the
        // transition is what confirms the click landed.
        MaterialIcon {
            anchors.centerIn: parent
            glyph:    "󰄬"
            color:   root.accent
            variant: "caption"
            opacity: root.checked ? 1 : 0
            scale:   root.checked ? 1 : 0.6
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            Behavior on scale   { NumberAnimation { duration: Motion.respond; easing.type: Motion.overshoot } }
        }

        MaterialIcon {
            anchors.centerIn: parent
            glyph:    "󰅖"
            color:   Colors.of(QsWindow.window).fgOnPrimary
            variant: "caption"
            opacity: root.checked ? 0 : 1
            scale:   root.checked ? 0.6 : 1
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            Behavior on scale   { NumberAnimation { duration: Motion.respond; easing.type: Motion.overshoot } }
        }
    }

    MouseArea {
        id: toggleHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // `checked` is still the state being left, so the sound is its opposite.
        onClicked: { Sfx.play(root.checked ? "off" : "on"); root.toggled() }
    }
}
