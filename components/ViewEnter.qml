import QtQuick
import "../config"

// ── ViewEnter ─────────────────────────────────────────────────────────────────
// A view arriving: when `active` turns true, `target` rises `rise` px into place while it
// fades up — a panel's tab switch (Palette | Presets | Album) reads as the next page coming
// in, not as one block of content being swapped for another. Non-visual, like SwapFade and
// PulseOnce: it animates `target`, it doesn't draw.
//
//     ViewEnter { target: workbench; active: workbench.visible }
//
// `delay` holds the entrance back by that many ms (the item sits hidden meanwhile), so a
// view's parts can cascade — the footer a beat after the card above it.
//
// It only plays the way IN. Going out is the target's own `visible` going false, which is
// instant, and the panel's surface is resizing to the next view in the same moment, so a
// fade-out would play over a frame that is already changing shape.
//
// Owns target.opacity and target.transform (a Translate for the rise) — give the target
// neither another driver. Not before creation finishes: a view that starts out shown is
// simply there. Motion off: every duration is 0, so it lands at once.
// ─────────────────────────────────────────────────────────────────────────────
QtObject {
    id: root

    property Item target: null
    property bool active: false
    property real rise:   Tokens.spacingLg
    property int  delay:  0

    property Translate _shift: Translate {}
    onTargetChanged: if (root.target) root.target.transform = root._shift

    property bool _ready: false
    Component.onCompleted: { root._ready = true; if (root.target) root.target.transform = root._shift }

    onActiveChanged: if (root._ready && root.active) anim.restart()

    property SequentialAnimation _anim: SequentialAnimation {
        id: anim
        // Hidden BEFORE the pause, or a delayed view would show at full strength until it starts.
        ScriptAction { script: { if (root.target) root.target.opacity = 0; root._shift.y = root.rise } }
        PauseAnimation { duration: root.delay }
        ParallelAnimation {
            NumberAnimation { target: root.target; property: "opacity"; to: 1; duration: Motion.standard; easing.type: Motion.enter }
            NumberAnimation { target: root._shift; property: "y"; to: 0; duration: Motion.spatial; easing.type: Motion.overshoot; easing.overshoot: 1.1 }
        }
    }
}
