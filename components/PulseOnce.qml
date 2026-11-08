import QtQuick
import "../config"

// ── PulseOnce ─────────────────────────────────────────────────────────────────
// One pop on `target`: it swells to `peak` and settles back. Call `fire()` when a
// status icon's state changes in a way worth noticing (charging started, the link
// dropped) — a single acknowledgement, never a loop. A bar that is always on screen
// pays for every infinite animation on it, every frame (Motion.settle's reason), and
// a looping pulse also reads as "something needs you", which a state change doesn't.
//
// Non-visual, like ArmLatch. Owns target.scale — don't give it another driver (SwapFade
// uses scale too, so the two belong on different items). Motion off: every duration is
// 0, so it is back at 1 straight away, which is the right end state.
// ─────────────────────────────────────────────────────────────────────────────
QtObject {
    id: root

    property Item target: null
    property real peak: 1.2

    function fire() { anim.restart() }

    property SequentialAnimation _anim: SequentialAnimation {
        id: anim
        NumberAnimation { target: root.target; property: "scale"; to: root.peak; duration: Motion.fast; easing.type: Motion.enter }
        NumberAnimation { target: root.target; property: "scale"; to: 1; duration: Motion.standard; easing.type: Motion.travel }
    }
}
