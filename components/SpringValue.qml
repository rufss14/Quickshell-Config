import QtQuick
import "../config"
import "spring.js" as Spring

// ── SpringValue ───────────────────────────────────────────────────────────────
// A number that follows `target` on a physical spring (Material 3 Expressive's motion).
// Bind what moves to `value`:
//
//     SpringValue { id: grow; target: hovered ? 6 : 0; spec: Motion.springSpatial }
//     width: base + grow.value
//
// Not a Behavior, because QML can't define an Animation type of its own, and a Behavior
// with SpringAnimation inside steps at 16 ms (spring.js has the measurement): this runs a
// FrameAnimation only while it moves and lands exactly on the spring at every frame.
//
// A new target in mid-flight KEEPS the velocity — the point of a spring. `kick(v)` adds
// velocity (a drag let go at speed carries into its snap), `jump(x)` puts it somewhere
// with no motion. Animations off (Motion.springTime 0): `value` simply equals `target`.
// ─────────────────────────────────────────────────────────────────────────────
QtObject {
    id: root

    property real target: 0
    // { stiffness, damping } — one of the Motion.spring* presets.
    property var spec: Motion.springSpatial
    // Close enough to call it arrived, in the value's own units: 0.01 suits pixels, a
    // scale or a 0..1 mix wants less.
    property real epsilon: 0.005

    // Read these. `value` is written only here.
    property real value: 0
    property real velocity: 0
    readonly property bool moving: root._tick.running

    property bool _ready: false
    property bool _jumped: false

    onTargetChanged: root._go()
    // Starts AT its target, unless a jump() got there first: an owner's own
    // Component.onCompleted may run before or after this one (Qt doesn't promise an order).
    Component.onCompleted: {
        if (!root._jumped) root.value = root.target
        root._ready = true
    }

    function jump(x) {
        root._tick.stop()
        root._jumped = true
        root.velocity = 0
        root.value = x
        root._go()
    }

    function kick(v) {
        root.velocity += v
        root._go()
    }

    function _go() {
        if (!root._ready) return
        if (Motion.springTime <= 0) {
            root._tick.stop()
            root.velocity = 0
            root.value = root.target
            return
        }
        if (!Spring.settled({ x: root.value, v: root.velocity }, root.target, root.epsilon))
            root._tick.start()
    }

    property FrameAnimation _tick: FrameAnimation {
        onTriggered: {
            // Capped, so a stall (a hidden window, a suspend) resumes mid-move rather than
            // finishing it unseen in one frame.
            const dt = Math.min(0.1, Math.max(0, root._tick.frameTime))
            const s = Spring.step({ x: root.value, v: root.velocity }, root.target,
                                  Spring.scaled(root.spec, Motion.springTime), dt)
            if (Motion.springTime <= 0 || Spring.settled(s, root.target, root.epsilon)) {
                root.value = root.target
                root.velocity = 0
                root._tick.stop()
                return
            }
            root.value = s.x
            root.velocity = s.v
        }
    }
}
