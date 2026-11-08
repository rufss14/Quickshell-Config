import QtQuick
import Quickshell
import "../config"

// ── ValueSlider ───────────────────────────────────────────────────────────────
// Rail, fill, handle. Used for volume, mic gain, per-app levels, brightness.
//
// Four hand-rolled versions of this existed (bar volume pill, equalizer master,
// equalizer per-app rows, brightness), each with its own rail height, handle
// size, and drag math — and only some of them clamped the handle so it couldn't
// hang off the end of its own track.
//
// The track uses the `focus` accent, not `primary`: a slider's fill is showing
// you *where you are*, not offering something to press. That's the same reason
// the handle brightens on hover rather than filling.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    // Screen readers (AT-SPI): what this is and what pressing it does. Keyboard focus
    // order is not wired yet — see docs/standards.md, Accessibility.
    property string accessibleName: ""
    Accessible.role: Accessible.Slider
    Accessible.name: root.accessibleName

    property real value:   0.0     // 0..maximum
    property real maximum: 1.0     // >1 allows overamplification (PipeWire streams)
    // NOTE: no `property bool enabled` here. Item already has one, and
    // redeclaring it shadows the property QML uses to gate input. Item.enabled
    // also propagates to child MouseAreas, so the drag area disables itself.

    // Draw a tick at this value — used to mark 100% (unity gain) on a slider that
    // can be pushed past it, so boosting an app is a deliberate act rather than
    // something you slide into without noticing. 0 = no notch.
    property real notchAt: 0

    // Rail thickness. 3 is the hairline the bar pill and brightness use; the audio
    // mixer asks for a fat fader. The handle and notch scale off this so a thick
    // rail doesn't end up with a pinhead knob.
    property int thickness: 3

    // The accent can be overridden per-row (the mixer tints a boosted stream to
    // warn, and a muted one to grey it out). Defaults to the focus role, because
    // a slider shows you WHERE YOU ARE — it isn't a control you press.
    property color accent: enabled ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgFaint

    // Emitted continuously while dragging. The consumer writes straight to the
    // service — with PipeWire that's a property assignment, so there is no
    // reason to debounce and no reason to wait for release.
    signal moved(real value)

    // +1 up, -1 down. The consumer decides the step size — a wheel tick means
    // 5% of brightness but 5% of *volume* is a different number, and the slider
    // has no business knowing which.
    signal scrolled(int delta)
    // True where the slider sits in a scrolling page (settings): only Ctrl+wheel moves it, so
    // a wheel passing over it scrolls the page instead of nudging the value (2026-10-31, the
    // user: scrolling "change values on slider accidentally").
    property bool wheelNeedsModifier: false

    // Exposed so a consumer can distinguish "the user is dragging this right now"
    // from "the value happened to change". BrightnessPanel needs it: a DDC monitor
    // takes ~300ms to respond, so it suppresses the fill's easing while you drag
    // (which would otherwise lag your cursor) and forces one final send on release,
    // in case the last in-drag value was coalesced away.
    readonly property alias pressed: drag.pressed

    implicitHeight: Tokens.pillHeight
    implicitWidth:  120

    readonly property real _fraction: Math.max(0, Math.min(1, value / maximum))
    readonly property color _accent: root.accent

    Rectangle {
        id: rail
        anchors.verticalCenter: parent.verticalCenter
        width:  parent.width
        height: root.thickness
        radius: height / 2
        color:  Colors.of(QsWindow.window).alpha(root._accent, 0.22)

        Rectangle {
            visible: root.notchAt > 0 && root.notchAt < root.maximum
            x: rail.width * (root.notchAt / root.maximum) - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width:  1
            height: root.thickness + 4
            radius: 1
            color:  Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.38)
        }
    }

    Rectangle {
        id: fill
        anchors.left:   rail.left
        anchors.top:    rail.top
        anchors.bottom: rail.bottom
        radius: rail.radius
        color:  root._accent
        // Never narrower than its own rounding, or the fill degenerates into a
        // lopsided dot at low values.
        width:  Math.max(rail.radius * 2, rail.width * root._fraction)

        // `track`, not the UI motion scale. This follows a LIVE value — the one
        // under the user's cursor. At UI timings (150ms) the fill visibly trails
        // the pointer, which reads as the slider being broken rather than smooth.
        // Just enough to take the stairstep off, never enough to be felt.
        //
        // And ZERO while actually dragging: the fill should be pinned to the
        // cursor, not easing toward it. Any easing at all here is felt as lag,
        // because the user has a hard reference for where it should be — their
        // own hand.
        Behavior on width {
            NumberAnimation {
                duration: root.pressed ? 0 : Motion.track
                easing.type: Motion.trackCurve
            }
        }
    }

    Rectangle {
        id: handle
        anchors.verticalCenter: rail.verticalCenter
        readonly property int _rest: Math.max(9, root.thickness + 2)
        width:  drag.containsMouse || drag.pressed ? _rest + 3 : _rest
        height: width
        radius: width / 2
        color:  root._accent

        // Clamped so the handle stays fully on the track at both extremes
        // instead of overhanging the ends.
        x: Math.max(0, Math.min(root.width - width, root.width * root._fraction - width / 2))

        // x follows the live value → track timing (see the fill above).
        // width/color are hover feedback, not value-following → respond timing.
        Behavior on x {
            NumberAnimation {
                duration: root.pressed ? 0 : Motion.track
                easing.type: Motion.trackCurve
            }
        }
        Behavior on width { NumberAnimation { duration: Motion.respond } }
        Behavior on color { ColorAnimation  { duration: Motion.respond } }
    }

    MouseArea {
        id: drag
        anchors.fill: parent
        // The rail is 3px tall — an exactly-rail-sized hit target would be
        // nearly unclickable. Extend it to the full control height.
        anchors.topMargin:    -Tokens.spacingMd
        anchors.bottomMargin: -Tokens.spacingMd
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        function commit(x) {
            root.moved(Math.max(0, Math.min(1, x / root.width)) * root.maximum)
        }
        onPressed:         function(m) { commit(m.x) }
        onPositionChanged: function(m) { if (pressed) commit(m.x) }
        onWheel: function(w) {
            // In a scrolling page a plain wheel is for the page (Scrollbar's note).
            if (root.wheelNeedsModifier && !(w.modifiers & Qt.ControlModifier)) { w.accepted = false; return }
            root.scrolled(w.angleDelta.y > 0 ? 1 : -1)
        }
    }
}
