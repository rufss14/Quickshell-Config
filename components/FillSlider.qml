import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Widgets
import "../config"
import "fillslider.js" as Geo

// ── FillSlider ────────────────────────────────────────────────────────────────
// The OSD's slider (volume, mic, brightness), in Material 3 Expressive's form: a tall
// rounded track, split into [fill][gap][handle][gap][rest] — never one bar with a knob
// on it — and under it a shape badge that carries the icon, and turns into the number
// while the value is moving. ValueSlider is the hairline horizontal one for panels,
// ThickSlider the horizontal fat one; this is the vertical one.
//
// ── The parts ─────────────────────────────────────────────────────────────────
// The fill is the primary tone and its top edge ripples while the level moves (a sine
// that grows on a spring, travels, and settles flat — so a resting slider is static
// geometry and redraws nothing). The handle is a bar that stands a gap clear of the fill
// and thins while held. Both ends keep a stub of track (`capH`), so a full or empty
// slider still shows the track's round end instead of a handle on the edge. The badge is
// a MorphShape: it takes `shape` and goes to a plain circle while muted.
//
// ── The fill is clipped to the track, not drawn rounded ───────────────────────
// A fill shorter than the track's own radius cannot be a rounded rectangle and still
// follow the round end; clipping a plain shape to the track does it for free. The
// geometry (fillslider.js) is tested: `bun scripts/test-fillslider.js`.
//
// ── The badge is the readout ──────────────────────────────────────────────────
// It shows the ICON at rest (what this is), and the PERCENTAGE while the value moves or
// is held (what it is now) — so one object answers both questions and the OSD needs no
// label. "Moving" is pressed, or a beat after the value last changed (a key press changes
// it with nothing under the pointer, and should still read out).
//
// ── Pinned to the pointer while dragging ──────────────────────────────────────
// The value comes from a service that may answer a few frames late (PipeWire, a DDC
// monitor). While pressed the slider follows the POINTER, not the service, with no easing
// at all — the user has a hard reference for where it should be (their hand), and any lag
// is felt as the slider being broken. On release it eases to whatever the service settled on.
//
// Size: `width` is the track's width AND the badge's diameter; `height` is the whole
// control, so the track is what is left under the badge and its gap.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    // Screen readers (AT-SPI): what this is and what pressing it does. Keyboard focus
    // order is not wired yet — see docs/standards.md, Accessibility.
    property string accessibleName: ""
    Accessible.role: Accessible.Slider
    Accessible.name: root.accessibleName

    property real   value: 0            // 0..1, from the service
    property string glyph: ""           // drawn in the badge at rest
    // The badge's shape while it is not muted; a muted one is a circle.
    property string shape: "cookie9"
    // Muted is the absence of the active colour, not a colour of its own — a red bar
    // would read as an error rather than as a state you chose.
    property bool   muted: false

    // Emitted continuously while dragging, 0..1.
    signal moved(real value)
    // +1 up, -1 down; the consumer decides the step.
    signal scrolled(int delta)

    readonly property alias pressed: area.pressed
    readonly property alias hovered: area.containsMouse

    // ── Geometry, off tokens ──────────────────────────────────────────────────
    readonly property real badgeGap: Tokens.spacingMd
    readonly property real trackH:   Math.max(1, root.height - root.width - root.badgeGap)
    readonly property real capH:     Tokens.spacingMd
    readonly property real gapPx:    Tokens.spacingSm + Tokens.spacingXs
    readonly property real handleH:  handleSpring.value
    readonly property real innerR:   Tokens.spacingSm

    // The level on screen: the pointer's while held, else a spring toward the service's.
    readonly property real _target: Math.max(0, Math.min(1, root.value))
    property real _drag: 0
    SpringValue { id: pos; target: root._target; spec: Motion.springEffects; epsilon: 0.001 }
    readonly property real _shown: Math.max(0, Math.min(1, area.pressed ? root._drag : pos.value))

    readonly property var _L: Geo.layout(root.trackH, root._shown, root.capH, root.gapPx, root.handleH)

    // The handle thins while held.
    SpringValue {
        id: handleSpring
        target: area.pressed ? Tokens.spacingSm : Tokens.spacingSm + Tokens.spacingXs
        spec: Motion.springSpatialFast
        epsilon: 0.01
    }

    // ── The ripple ────────────────────────────────────────────────────────────
    // The number is up while pressed and for a beat after the value last moved, and the
    // fill's edge ripples for exactly as long.
    property bool _recent: false
    readonly property bool _readout: area.pressed || root._recent
    onValueChanged: { root._recent = true; hold.restart() }

    Timer {
        id: hold
        interval: 600
        onTriggered: root._recent = false
    }

    SpringValue {
        id: amp
        target: root._readout && Config.motionEnabled ? Tokens.spacingXs : 0
        spec: Motion.springSpatial
        epsilon: 0.01
    }

    property real _phase: 0
    property real _since: 0
    FrameAnimation {
        running: amp.value > 0.02
        onTriggered: {
            // The path is rebuilt on each step, and a ripple travelling at this pace needs
            // no more than 30 of them a second (WaveSlider's measurement).
            root._since += frameTime
            if (root._since < 0.033) return
            root._phase += root._since * 5
            root._since = 0
        }
    }

    readonly property var _fillPath: {
        const flat = Geo.outline(root.width, root.trackH, root._L.fillTop, amp.value, root._phase, root.innerR)
        const out = new Array(flat.length / 2)
        for (let i = 0; i < out.length; i++) out[i] = Qt.point(flat[2 * i], flat[2 * i + 1])
        return out
    }

    // Not readonly: a Behavior writes the property it animates.
    property color _tone: root.muted ? Colors.of(QsWindow.window).fgDim
                                              : Colors.of(QsWindow.window).primary
    Behavior on _tone { ColorAnimation { duration: Motion.respond } }

    // ── The track ─────────────────────────────────────────────────────────────
    ClippingRectangle {
        id: track
        width: root.width
        height: root.trackH
        radius: root.width / 2
        color: "transparent"

        // The rest: what is left above the handle. Round at the top (the track's end),
        // small-cornered where it faces the handle.
        Rectangle {
            width: root.width
            height: Math.max(0, root._L.restH)
            topLeftRadius: track.radius
            topRightRadius: track.radius
            bottomLeftRadius: root.innerR
            bottomRightRadius: root.innerR
            color: Colors.of(QsWindow.window).surfaceContainer
        }

        Shape {
            width: root.width
            height: root.trackH
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: root._tone
                strokeWidth: -1
                PathPolyline { path: root._fillPath }
            }
        }

        Rectangle {
            x: Tokens.spacingSm
            y: root._L.handleTop
            width: root.width - Tokens.spacingSm * 2
            height: root.handleH
            radius: height / 2
            color: root._tone
        }
    }

    // ── The badge ─────────────────────────────────────────────────────────────
    MorphShape {
        id: badge
        y: root.trackH + root.badgeGap
        width: root.width
        height: root.width
        shape: root.muted ? "circle" : root.shape
        fillColor: root.muted ? Colors.of(QsWindow.window).surfaceContainer
                              : Colors.of(QsWindow.window).primaryContainer
        Behavior on fillColor { ColorAnimation { duration: Motion.respond } }

        // The icon and the number swap with a squash — down to a speck, change, back up —
        // rather than a cross-fade, so it reads as the badge changing its mind.
        Item {
            id: face
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            // What the face is currently showing; flips at the bottom of the squash.
            property bool number: false

            Connections {
                target: root
                function on_ReadoutChanged() { squash.restart() }
            }

            SequentialAnimation {
                id: squash
                NumberAnimation { target: face; property: "scale"; to: 0.3
                                  duration: Motion.respond; easing.type: Motion.exitCurve }
                ScriptAction { script: face.number = root._readout }
                NumberAnimation { target: face; property: "scale"; to: 1
                                  duration: Motion.standard; easing.type: Motion.enter }
            }

            MaterialIcon {
                anchors.centerIn: parent
                glyph: root.glyph
                variant: "body"
                sizeScale: 1.2
                color: root.muted ? Colors.of(QsWindow.window).fgMuted
                                  : Colors.of(QsWindow.window).fgOnPrimaryContainer
                visible: !face.number
            }

            StyledText {
                anchors.centerIn: parent
                text: Math.round(root._shown * 100)
                variant: "label"
                font.weight: Font.DemiBold
                color: root.muted ? Colors.of(QsWindow.window).fgMuted
                                  : Colors.of(QsWindow.window).fgOnPrimaryContainer
                visible: face.number
            }
        }
    }

    MouseArea {
        id: area
        width: root.width
        height: root.trackH
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        function commit(y) {
            root._drag = Geo.levelAt(y, root.trackH, root.capH, root.gapPx, root.handleH)
            // The spring keeps up with the hand, so letting go does not snap back.
            pos.jump(root._drag)
            root.moved(root._drag)
        }
        onPressed:         function(m) { commit(m.y) }
        onPositionChanged: function(m) { if (pressed) commit(m.y) }
    }

    WheelHandler {
        onWheel: event => root.scrolled(event.angleDelta.y > 0 ? 1 : -1)
    }
}
