import QtQuick
import "../config"

// ── SwapFade ──────────────────────────────────────────────────────────────────
// Swaps what an item shows through a fade: the old content eases out (up and away),
// the new eases in from below. Non-visual, like ArmLatch — it animates `target`, it
// doesn't draw.
//
// ── The held copy is the CALLER's ─────────────────────────────────────────────
// Bind `target`'s content to a local copy of the data, not straight to the service,
// or it changes before the fade-out has begun (a surface that fades out must keep its
// own copy). This component only says WHEN to update that copy:
//
//     SwapFade {
//         target:   row
//         key:      root.winKey                        // identity of what should show
//         shownKey: root.shown ? root.shown.address : ""   // identity of what DOES
//         onSwapped: root.shown = root.win             // midpoint, target at opacity 0
//     }
//
// `key` is an IDENTITY, not the content: a different window, track, icon. Anything that
// merely updates within the same identity (a terminal rewriting its title every second)
// should update the held copy directly, and never reach here — each one running a fade
// would never settle.
//
// Events arriving mid-swap are ignored, and when it ends it goes round once more if
// `key` has moved on, so it can't strand `target` on something that is no longer
// current. Motion off: every duration is 0, so the swap is a plain cut.
//
// Owns target.transform (a Translate for the slide) — don't give it another.
// ─────────────────────────────────────────────────────────────────────────────
QtObject {
    id: root

    property Item target: null
    property string key: ""
    property string shownKey: ""

    // How far the content travels, in px, and how small it gets at the midpoint (1 = it
    // doesn't scale; a pop, like the tray's, is ~0.7 with travel 0).
    property real travel: Tokens.spacingXs
    property real dip: 1

    readonly property bool running: anim.running
    signal swapped()

    property Translate _shift: Translate {}
    onTargetChanged: if (root.target) root.target.transform = root._shift
    // Not only the handler above: whether a change handler sees the INITIAL assignment
    // depends on creation order, and a missed one means no slide, with no warning.
    Component.onCompleted: { root._ready = true; if (root.target) root.target.transform = root._shift }

    // Not before creation finishes: the initial `key` is not a change, and the caller
    // fills its held copy in its own onCompleted (after this one — children first).
    property bool _ready: false
    onKeyChanged: if (root._ready && root.key !== root.shownKey && !anim.running) anim.start()

    property SequentialAnimation _anim: SequentialAnimation {
        id: anim
        ParallelAnimation {
            NumberAnimation { target: root.target; property: "opacity"; to: 0; duration: Motion.fast; easing.type: Motion.exitCurve }
            NumberAnimation { target: root._shift; property: "y"; to: -root.travel; duration: Motion.fast; easing.type: Motion.exitCurve }
            NumberAnimation { target: root.target; property: "scale"; to: root.dip; duration: Motion.fast; easing.type: Motion.exitCurve }
        }
        ScriptAction { script: { root.swapped(); root._shift.y = root.travel } }
        ParallelAnimation {
            NumberAnimation { target: root.target; property: "opacity"; to: 1; duration: Motion.fast; easing.type: Motion.enter }
            NumberAnimation { target: root._shift; property: "y"; to: 0; duration: Motion.fast; easing.type: Motion.enter }
            NumberAnimation { target: root.target; property: "scale"; to: 1; duration: Motion.fast; easing.type: Motion.enter }
        }
        onFinished: if (root.key !== root.shownKey) anim.start()
    }
}
