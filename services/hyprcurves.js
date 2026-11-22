.pragma library

// ── hyprcurves.js ─────────────────────────────────────────────────────────────
// What a Hyprland animation LOOKS like, for the live stage on Settings › Window manager › Tuning
// (modules/settings/pages/MotionStage): its duration, its curve and the kind of movement it is.
//
//     bun scripts/test-hyprcurves.js
//
// Hyprland's `speed` is in deciseconds: 6 is 600 ms; a disabled animation is instant. The curves
// are the ones the shipped hypr/animation.lua names — `wind` is the shell's own emphasized-decelerate
// (blend.lua gives both the same control points), so it is passed in; a curve this table does not
// know (one added by hand) is drawn as `wind` rather than guessed at.
// ─────────────────────────────────────────────────────────────────────────────

// Control points [x1, y1, x2, y2]. Values outside 0..1 are real overshoots (winIn leaves the unit box).
var KNOWN = {
    winIn:  [0.1, 1.1, 0.1, 1.1],
    winOut: [0.3, -0.3, 0, 1],
    liner:  [1, 1, 1, 1]
}

// The curve as an easing bezier list ([x1, y1, x2, y2, 1, 1], what Qt's `easing.bezierCurve` takes).
// `wind` is the list for the shell's own curve (Motion.emphasizedDecel).
function curveFor(name, wind) {
    if (name === "wind" || KNOWN[name] === undefined) return wind
    return KNOWN[name].concat([1, 1])
}

// Milliseconds for a Hyprland speed. Disabled, or a speed of 0 or less, is 0.
function durationMs(speed, enabled) {
    var s = Number(speed)
    if (enabled === false || !(s > 0)) return 0
    return Math.round(s * 100)
}

// How to draw a leaf: "window" (it grows in and out), "fade" (it dissolves), "slide" (it moves across),
// "border" (the outline). Leaves are named like windowsIn, fadeOut, workspacesIn, layers.
function kindFor(leaf) {
    var l = String(leaf || "")
    if (l.indexOf("fade") === 0) return "fade"
    if (l.indexOf("border") === 0) return "border"
    if (l.indexOf("workspaces") === 0 || l.indexOf("specialWorkspace") === 0 || l === "windowsMove") return "slide"
    if (l.indexOf("layers") === 0) return "fade"
    return "window"
}

// "Out" leaves play the movement backwards (it leaves instead of arriving).
function leaving(leaf) {
    return /Out$/.test(String(leaf || ""))
}
