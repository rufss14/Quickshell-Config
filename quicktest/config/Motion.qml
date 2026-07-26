pragma Singleton
import Quickshell
import QtQuick

// ── Motion ────────────────────────────────────────────────────────────────────
// Every duration and easing curve in the shell. No widget defines its own.
//
// Personality: SNAPPY. Things move decisively and settle — they don't drift.
// Curves are decelerate-only (OutCubic): a surface appears already in motion and
// eases into rest, rather than accelerating from a standstill. Symmetric
// ease-in-out reads as weight, and weight reads as lag on a shell you poke at all
// day.
//
// ── The one rule that matters ─────────────────────────────────────────────────
// A Behavior must never animate a property that is ALREADY animating from
// somewhere else. If it does, it eases toward a target that is itself easing —
// re-aiming every frame, chasing instead of tracking. That is what "jittery" and
// "rubber-banding" actually are, and it is the single easiest way to make good
// timings feel broken.
//
// Concretely: don't put a Behavior on a container's implicitWidth when its
// children animate their own widths. Let the container track content 1:1 and
// animate only the values that change DISCRETELY (a toggle, a hover, a mode
// switch) — those can't chase, because they have nothing to chase.
//
// `track` exists for the opposite case: a property following a live continuous
// value (a slider under your cursor, a spectrum bar following audio). That is not
// UI motion and must not use the UI scale — at 150ms a slider visibly lags the
// pointer. It gets its own near-instant timing.
//
// ── This is the DESIGNED motion, scaled by the user's preference ──────────────
// Every duration below is the authored value run through `_d()`, which applies
// Config.motionScale and collapses everything to 0 when Config.motionEnabled is off.
//
// This is the one place in config/ that reads Config, and it's deliberate. Tokens must
// never import Config, because the tokens ARE what the defaults are defined as — the
// dependency would be circular in meaning as well as in code. Duration is genuinely
// different: the EFFECTIVE duration is the designed one times a preference, and the
// only alternative is every Behavior in the shell multiplying by hand. Config holds
// plain literals for these and never imports Motion, so there's no cycle.
//
// `track` is exempt on purpose. It isn't animation — it's the smoothing on a value
// following your cursor or the audio. Scaling it to 2× would make sliders lag the
// pointer; zeroing it would make the visualizer stairstep. "Turn off animations" means
// "stop things moving on their own", not "make live readouts worse".
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // Round, don't floor: a 60ms duration at 0.25× is 15ms, but flooring anything under
    // 1 would give 0 and silently turn a fast animation into a jump.
    function _d(ms) {
        return Config.motionEnabled ? Math.max(1, Math.round(ms * Config.motionScale)) : 0
    }

    // ── Durations ─────────────────────────────────────────────────────────────

    // track: following a live, continuously-changing value. Just enough to take
    // the stairstep off incoming data — never enough to be felt as animation.
    readonly property int track: 60

    // respond: hover tints, border color, press states. Acknowledgement. The user
    // is waiting on this before acting, so it must never be something they wait on.
    readonly property int respond: root._d(100)

    // fast: small geometry — a badge resizing, an icon swapping.
    readonly property int fast: root._d(120)

    // standard: the default for anything that moves or resizes.
    readonly property int standard: root._d(150)

    // emphasized: large surfaces entering — panels, the dock, the launcher.
    readonly property int emphasized: root._d(220)

    // exit: any surface leaving. Always faster than its enter — the user has
    // already decided they're done with it, and every frame after that is the UI
    // arguing.
    readonly property int exit: root._d(140)

    // slow: ambient, non-interactive motion (breathing dots, idle pulses) where
    // duration is atmosphere rather than responsiveness.
    readonly property int slow: root._d(400)

    // ── Spatial: things that TRAVEL ───────────────────────────────────────────
    // A window preview gliding across the workspace grid; a card sliding into
    // place; the overlay arriving. These are not acknowledgements — nobody is
    // waiting on them to act — and the whole scale above was tuned as if they were.
    //
    // That is why the shell felt abrupt next to the old overview. Everything moved
    // in 150ms on an OutCubic, which is right for a hover tint and much too curt for
    // an object crossing the screen: it arrives before the eye has followed it, so
    // motion reads as a cut rather than as movement. Distance needs time.
    //
    // 400ms with a Material-3 emphasized-decelerate curve: it leaves fast and takes
    // its time settling, which is what "smooth" actually means.
    readonly property int spatial: root._d(400)

    // spatialSlow: the largest movements, where the flourish is the point.
    readonly property int spatialSlow: root._d(500)

    // ── Easing ────────────────────────────────────────────────────────────────
    // Bezier control points, not the stock Easing enums. Qt's built-ins have no
    // emphasized curve and no overshoot, and both are load-bearing here.
    //
    // Use with:  easing.type: Easing.BezierSpline
    //            easing.bezierCurve: Motion.emphasizedDecel

    // emphasizedDecel: the house SPATIAL curve. Sprints out of the gate, glides into
    // rest. Material 3's emphasized-decelerate.
    readonly property list<real> emphasizedDecel: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]

    // spring: overshoots slightly past the target and settles back (note the 1.21 —
    // above 1 IS the overshoot). For motion that should feel physical rather than
    // merely correct: a preview snapping home, a card landing.
    readonly property list<real> spring: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]

    // effects: the fast counterpart, for scale/opacity rather than position.
    readonly property list<real> effects: [0.34, 0.8, 0.34, 1.0, 1.0, 1.0]

    // travel: the house curve. Decelerate-only — fast out of the gate, gentle
    // into rest.
    readonly property int travel: Easing.OutCubic

    // enter: a surface arriving from nothing.
    readonly property int enter: Easing.OutCubic

    // exitCurve: a surface leaving. Accelerate-only — it commits and gets out of
    // the way instead of dawdling near its start position.
    readonly property int exitCurve: Easing.InCubic

    // respondCurve: acknowledgement. Front-loaded, no drama.
    readonly property int respondCurve: Easing.OutQuad

    // trackCurve: live-value following. Nearly linear.
    readonly property int trackCurve: Easing.OutQuad

    // expressive: reserved for the one or two moments that should feel like a
    // flourish. Use sparingly — this is the exception that proves the shell has a
    // default.
    readonly property int expressive: Easing.OutQuint

    // ── Helpers ───────────────────────────────────────────────────────────────
    // A surface's enter and exit differ in BOTH duration and curve, and that
    // pairing is easy to get half-right. Pass the same `shown` boolean to both.
    function surfaceDuration(shown) { return shown ? root.emphasized : root.exit }
    function surfaceEasing(shown)   { return shown ? root.enter      : root.exitCurve }
}
