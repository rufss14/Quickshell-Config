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
// ── Which one do I pick? ──────────────────────────────────────────────────────
// By what is happening, not by how long it feels. Duration, then curve:
//
//   a hover / press / border colour             respond   + respondCurve
//   a badge or icon changing size or swapping   fast      + travel
//   anything that moves or resizes (default)    standard  + travel
//   a big surface arriving (panel, launcher)    emphasized + enter   (surfaceDuration(true))
//   any surface leaving                         exit      + exitCurve (surfaceDuration(false))
//   a layout shifting position (spatial)        spatial   + travel
//   decoration, idle glow                       slow
//   a value following a live signal             track     + trackCurve   (never scaled)
//   a gauge easing into a new sample            settle / glide
//   a busy or attention pulse                   pulse
//
// Same-valued pairs are deliberate, not duplicates: `slow` and `spatial` are both 400
// today but one is atmosphere and one is geometry, and `travel` / `enter` are both
// OutCubic but name a move versus an arrival. Pick the one that says what you mean, so
// retuning one later does not drag the other with it.
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
//
// ══ WHEN A LITERAL DURATION IS CORRECT, AND WHAT IT OWES YOU ═════════════════
// Most motion belongs to a token above and gets `Config.motionEnabled` for free,
// because `_d()` collapses to 0. Three kinds don't, and each honours the
// preference a different way. A literal duration anywhere in the shell should say
// which of these it is — otherwise the next reader can only guess whether it was
// a decision or an oversight, and "Animations: off" quietly stops being true.
//
//   1. LIVE TRACKING — `track`, and anything matched to a sampling interval
//      (MediaController's progress bar advances at the rate its position is
//      re-read). Exempt from the scale AND from the toggle: this is smoothing on
//      incoming data, not something moving on its own.
//
//   2. FIXED GESTURE / AMBIENT — a designed physical timing that scaling would
//      distort rather than adjust. The lockscreen's 45-second Ken Burns drift; the
//      wrong-password shake. Honoured by NOT STARTING: `running:
//      Config.motionEnabled && …`, or simply never calling `restart()`.
//      Both LockScreen and GreetScreen carry the full reasoning.
//
//   3. BUSY INDICATORS — the reload pill's spinner, the update check's spinner.
//      Deliberately NOT gated, and this is the one exception that looks like a bug
//      from the outside: the rotation IS the information. Frozen mid-turn, a
//      spinner does not read as "animations are off", it reads as "this has hung"
//      — which is the single message it must never send by accident. Don't "fix"
//      these to honour the toggle.
//
// Category 2 has a trap worth stating once, because both sites here hit it: an
// animation is often the thing that RESTORES a property, not just the thing that
// moves it. Gate the restore away and you strand whatever set the value — a press
// that scales an icon down, a phase a shader reads. Stopping is not the same as
// resetting, so gate the whole gesture and put the property back yourself.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // Round, don't floor: a 60ms duration at 0.25× is 15ms, but flooring anything under
    // 1 would give 0 and silently turn a fast animation into a jump.
    function _d(ms) {
        return root.snap ? 0 : root._real(ms)
    }
    function _real(ms) {
        return Config.motionEnabled ? Math.max(1, Math.round(ms * Config.motionScale)) : 0
    }

    // ── snap: every duration 0, for a moment ──────────────────────────────────
    // Raised by WallWave (and only WallWave) while the shell sits under its snapshots, from
    // the new palette being read until the front leaves: the colours change under cover, and
    // each `Behavior on color` would otherwise spend a `standard` of that moment animating
    // something nobody can see — which the wave then waited out. Anything that must keep
    // its own time through it (the wave itself, below) is NOT run through `_d()`.
    property bool snap: false

    // ── Durations ─────────────────────────────────────────────────────────────

    // track: following a live, continuously-changing value. Just enough to take
    // the stairstep off incoming data — never enough to be felt as animation.
    readonly property int track: 60

    // settle: a live readout easing into each new SAMPLE, then resting — a gauge,
    // sparkline or meter fed once a second. Category 1 like `track` (it smooths
    // incoming data, so it is exempt from the scale), and its consumers gate it on
    // Config.motionEnabled themselves, as they always have.
    //
    // It replaced gliding for the WHOLE sample interval, and that is the point of it.
    // A glide that lasts exactly one interval never stops: the ring is always
    // travelling, so its surface redraws at the display's full refresh rate, forever —
    // 165 frames a second to show a number that changes once. On the desktop that was
    // the widget layer never going idle; on the lock screen, all night. 300ms reads as
    // smooth and leaves the surface still for the rest of every second. Consumers cap
    // it at their own interval (`Math.min`) so a faster stream never chases.
    readonly property int settle: 300

    // glide / glideCurve: `settle`'s longer sibling, for a gauge you WATCH rather
    // than glance at (the sidebar's stats rings). Eased in and out across most of a
    // second-long sample, so the arc never visibly starts or stops, and still at
    // rest for the last ~300ms of it — the idle budget `settle` exists to protect,
    // spent more slowly rather than not at all. A faster stream (the network's 4Hz)
    // retargets mid-glide, which reads as the ring following a smoothed signal.
    readonly property int glide: 700
    readonly property int glideCurve: Easing.InOutSine

    // respond: hover tints, border color, press states. Acknowledgement. The user
    // is waiting on this before acting, so it must never be something they wait on.
    readonly property int respond: root._d(100)

    // fast: small geometry — a badge resizing, an icon swapping.
    readonly property int fast: root._d(120)

    // standard: the default for anything that moves or resizes.
    readonly property int standard: root._d(150)

    // emphasized: large surfaces entering — panels, the dock, the launcher.
    //
    // 340, not the 220 it was. A panel that MELTS out of the bar is a different
    // gesture from one that simply appears: the blob's smooth-min has to be seen
    // stretching and letting go, and at 220ms the whole join happened inside three
    // frames — the surface was just suddenly there, which read as a cut rather than
    // as a morph. The Accordion's own open pause is this same token, so the content
    // still fades in exactly as the box finishes growing.
    readonly property int emphasized: root._d(340)

    // exit: any surface leaving. Always faster than its enter — the user has
    // already decided they're done with it, and every frame after that is the UI
    // arguing. Raised with `emphasized` and kept well under it: 200 against 340, the
    // same ratio the old 140/220 pair had, so leaving still reads as decisive.
    readonly property int exit: root._d(200)

    // slow: ambient, non-interactive motion (idle pulses, decorative glows) where
    // duration is atmosphere rather than responsiveness. Scaled and switchable like
    // everything else — this is decoration, and turning animations off should stop
    // decoration. For a pulse that carries INFORMATION, use `pulse` below.
    readonly property int slow: root._d(400)

    // ── pulse: the breathing of a SIGNAL ──────────────────────────────────────
    // Busy indicators, attention and urgency pulses — category 3 in the note above.
    // Same 400ms tempo as `slow`, deliberately, so the shell has one breathing rate
    // rather than two. The difference is that this one is NOT run through `_d()`.
    //
    // Exempt for the reason `track` is exempt: it is not a transition, it is a
    // channel. A dot that breathes while something is working conveys "working";
    // motionless, it conveys nothing at all, and a user who turned animations off
    // gets a lock screen that looks like it ignored their password.
    //
    // ── Why exemption has to be a TOKEN and not a literal ─────────────────────
    // Nine sites had reached for `slow` for exactly this job, including `BusyDot`,
    // whose own header says it exists because spinners "read as stuck rather than
    // busy" — and which therefore reintroduced that very failure at all 28 of its
    // call sites the moment animations were switched off. The mistake is easy
    // because `slow` is the right TEMPO and the wrong SWITCHABILITY, and nothing in
    // the name said so. Now the name says so.
    //
    // Measured, offscreen on Qt 6.11, before choosing exemption over a zero-length
    // loop: a SequentialAnimation at duration 0 with `loops: Infinite` changes its
    // value twice and then settles (against 32 changes in 500ms at 400ms). So a
    // collapsed pulse does not spin the CPU — it simply stops, silently, which is
    // the failure mode that matters here.
    readonly property int pulse: 400

    // ripple: a Material 3 state-layer wave crossing a control, from wherever you
    // actually pressed.
    //
    // Deliberately much longer than `standard`, which is the opposite of the rule the
    // rest of this file follows — and the exception is the point. The acknowledgement
    // already happened: the state fill answers in `respond` (100ms), before the wave
    // has gone anywhere. The wave is the flourish AFTER the answer, and a flourish
    // that finishes in 150ms doesn't read as a wave at all, it reads as a flicker.
    //
    // It is also the one duration here nobody is waiting on. You have already clicked;
    // the button has already responded; this is decoration playing out behind a
    // decision that is made.
    readonly property int ripple: root._d(500)

    // trail: the LAGGING edge of an object that stretches as it travels.
    //
    // Pair it with `standard` on the same target: two edges heading for the same
    // place at different speeds, so the shape stretches on the way and contracts as
    // the slow edge catches up. That is the entire mechanism — there is no separate
    // "stretch" animation and no overshoot curve involved, which is why this is a
    // duration and not an easing.
    //
    // 2× standard is where the stretch becomes legible without reading as rubber.
    // The bar's workspace indicator and the dock's focus indicator use it.
    readonly property int trail: root._d(300)

    // stagger: the step between siblings arriving one after another, so a row reads
    // as assembling itself rather than popping in as one block (the dock's icons
    // riding out with the sidebar). `staggerCap` bounds a long row, so its tail
    // never waits on its head long enough to look late.
    readonly property int stagger: root._d(18)
    readonly property int staggerCap: root._d(160)

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

    // zoom / zoomOut: the overview going into / out of a workspace (OverviewZoom) — a whole
    // screen of travel, the one move here that is seen from end to end. `zoomOut` is shorter
    // for the usual reason (you have decided), but not by much: the compositor's own
    // workspace slide is still settling underneath, and the zoom's tail is what hides it.
    readonly property int zoom:    root._d(440)
    readonly property int zoomOut: root._d(380)

    // intro / introExit: the shell arriving (launch, reload) and leaving (a reload's old
    // shell) — state/Intro, one clock that the bar, frame, pills and desktop widgets each
    // read a window of. The exit is the entrance backwards at well under half the length:
    // a reload is waiting on it, and leaving is not the part anyone watches.
    readonly property int intro:     root._d(700)
    readonly property int introExit: root._d(280)

    // wave: a wallpaper or palette change spreading from the bottom middle of the
    // screen like water (services/WallWave) — the new picture over the old, the new
    // colours eating the old look off the shell on the same front. The one HERO
    // motion in the shell, and deliberately far past `spatialSlow`: a fast rush, then
    // a long settle as it finds the corners. Taken from the shell it was ported from,
    // where it was tuned by eye. Runs on `travel` (OutCubic) — services/contagion.js
    // inverts exactly that curve to know when the front reaches a window, so the two
    // change together or not at all.
    // Not through `_d()`: the front's own time, which `snap` (raised for the moments before
    // it) must not take away.
    readonly property int wave: root._real(1150)

    // ── Easing ────────────────────────────────────────────────────────────────
    // Bezier control points, not the stock Easing enums. Qt's built-ins have no
    // emphasized curve and no overshoot, and both are load-bearing here.
    //
    // Use with:  easing.type: Easing.BezierSpline
    //            easing.bezierCurve: Motion.emphasizedDecel

    // emphasizedDecel: the house SPATIAL curve. Sprints out of the gate, glides into
    // rest. Material 3's emphasized-decelerate.
    //
    // The four control points come from the shared blend.lua (Blend.v.curve_points),
    // the same points Hyprland's `wind` curve uses for window/workspace animation —
    // so a panel sliding in and a window sliding in bend the same way. The fixed
    // 1.0, 1.0 tail stays here (a cubic-bezier's final point is always the target).
    readonly property list<real> emphasizedDecel: [
        Blend.v.curve_points[0], Blend.v.curve_points[1],
        Blend.v.curve_points[2], Blend.v.curve_points[3],
        1.0, 1.0
    ]

    // spring: overshoots slightly past the target and settles back (note the 1.21 —
    // above 1 IS the overshoot). For motion that should feel physical rather than
    // merely correct: a preview snapping home, a card landing.
    readonly property list<real> spring: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]

    // zoomCurve: ease IN and out, unlike every curve above. emphasizedDecel covers half the
    // distance in the first 7% of its time — two frames — which is right for a card
    // arriving and reads as a snap when the whole screen is what is moving. This one
    // leaves rest gently (the start's slope is 0), takes its speed by a quarter of the way,
    // and arrives softly. Material's emphasized is (0.2, 0, 0, 1); this is a little more
    // symmetrical. A taste knob: lengthen the first number to ease in harder.
    readonly property list<real> zoomCurve: [0.35, 0.0, 0.1, 1.0, 1.0, 1.0]

    // effects: the fast counterpart, for scale/opacity rather than position.
    readonly property list<real> effects: [0.34, 0.8, 0.34, 1.0, 1.0, 1.0]

    // ── Physical springs: Material 3 Expressive's motion scheme ───────────────
    // For `components/SpringValue` (closed form, frame-exact; components/spring.js says why
    // not Qt's SpringAnimation). Stiffness and damping RATIO exactly as Material/Compose
    // state them (ExpressiveMotionTokens), so they can be checked against the spec, not
    // re-tuned by eye. Spatial = position, size, shape, scale: they overshoot a little
    // (fast ~9.5%, the other two ~1.5%). Effects = opacity, colour, a wash: critically
    // damped, never past the target.
    //
    // Unlike a duration + curve, a spring keeps its velocity when its target changes in
    // mid-flight, so a hover that leaves before the grow has finished turns round instead
    // of restarting. That is what "fluid" means here.
    readonly property var springSpatialFast: ({ stiffness: 800,  damping: 0.6 })
    readonly property var springSpatial:     ({ stiffness: 380,  damping: 0.8 })
    readonly property var springSpatialSlow: ({ stiffness: 200,  damping: 0.8 })
    readonly property var springEffectsFast: ({ stiffness: 3800, damping: 1.0 })
    readonly property var springEffects:     ({ stiffness: 1600, damping: 1.0 })
    readonly property var springEffectsSlow: ({ stiffness: 800,  damping: 1.0 })

    // springSettleFast / springSettle: how long springSpatialFast / springSpatial take to settle
    // from rest on a unit step (components/spring.js, epsilon 0.005). Nothing in QML needs this —
    // SpringValue tracks a moving target continuously and never "finishes" on a timer — but a CSS
    // consumer (the Discord theme) pairs a duration with a baked easing curve, so it needs a number.
    // Scaled and switchable exactly like every duration above: slowing a spring by `s` is the same
    // curve `s` times longer (spring.js's `scaled()`), which is exactly what `_d()` already does.
    readonly property int springSettleFast: root._d(322)
    readonly property int springSettle:     root._d(371)

    // How much a spring's time is stretched (Config.motionScale), and 0 = no motion at all:
    // animations off, or `snap` under the wave. SpringValue lands on its target then.
    readonly property real springTime: (root.snap || !Config.motionEnabled) ? 0 : Config.motionScale

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

    // ambient: loops and breathing that run for as long as they are on. Symmetric, slow.
    readonly property int ambient: Easing.InOutSine

    // inOut: a symmetric move between two rests (a shake, a nudge back).
    readonly property int inOut: Easing.InOutQuad

    // overshoot: a control that lands past its target and settles back (a bounce, a pop).
    readonly property int overshoot: Easing.OutBack

    // ── Helpers ───────────────────────────────────────────────────────────────
    // A surface's enter and exit differ in BOTH duration and curve, and that
    // pairing is easy to get half-right. Pass the same `shown` boolean to both.
    function surfaceDuration(shown) { return shown ? root.emphasized : root.exit }
    function surfaceEasing(shown)   { return shown ? root.enter      : root.exitCurve }
}
