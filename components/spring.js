.pragma library

// ── spring.js ─────────────────────────────────────────────────────────────────
// A damped spring, solved exactly. The physics behind `components/SpringValue` and the
// `Motion.spring*` presets (Material 3 Expressive's motion scheme), kept out of QML so it
// can be tested: `bun scripts/test-spring.js`.
//
// ── Why not Qt's SpringAnimation ─────────────────────────────────────────────
// It integrates in fixed 16 ms steps (measured headless, 2026-10-30: the value after its
// first frame is exactly one 16 ms Euler step, `x += 0.016·v`), so it can't move more often
// than ~62 times a second. The main screen here runs at 165 Hz: a SpringAnimation there
// holds still for two frames out of three. This is closed form, so it lands exactly where
// the spring is at whatever the frame time is, at any refresh rate and any stiffness. (Qt's
// Euler step also blows up for Material's stiff "effects" springs: 3800 at 16 ms is past
// what that integrator survives.)
//
// ── The model ─────────────────────────────────────────────────────────────────
// Unit mass. `stiffness` is k (N/m), `damping` is the damping RATIO ζ, exactly as Material
// and Compose state them: 1 = critically damped (no overshoot), below 1 overshoots. The
// state is { x, v }; everything works on the error e = x − target, so a new target in
// mid-flight keeps the velocity, which is what makes an interrupted spring feel continuous.
// ─────────────────────────────────────────────────────────────────────────────

// `timeScale` stretches time (Config.motionScale: 2 = twice as slow). A spring k slowed by s
// is k / s², with the same ζ: the same curve, s times longer.
function scaled(spec, timeScale) {
    const s = timeScale > 0 ? timeScale : 1
    return { stiffness: spec.stiffness / (s * s), damping: spec.damping }
}

// The state `dt` seconds on. Exact for any dt, so a long frame cannot destabilise it.
function step(state, target, spec, dt) {
    const k = Math.max(1e-6, spec.stiffness)
    const z = Math.max(0, spec.damping)
    const w = Math.sqrt(k)
    const e0 = state.x - target
    const v0 = state.v
    let e, v
    if (Math.abs(z - 1) < 1e-6) {
        // Critically damped.
        const a = e0, b = v0 + w * e0
        const ex = Math.exp(-w * dt)
        e = (a + b * dt) * ex
        v = (b - w * (a + b * dt)) * ex
    } else if (z < 1) {
        const wd = w * Math.sqrt(1 - z * z)
        const a = e0, b = (v0 + z * w * e0) / wd
        const ex = Math.exp(-z * w * dt)
        const c = Math.cos(wd * dt), s = Math.sin(wd * dt)
        e = ex * (a * c + b * s)
        v = ex * ((-z * w * a + wd * b) * c + (-z * w * b - wd * a) * s)
    } else {
        // Overdamped: two real roots.
        const r = Math.sqrt(z * z - 1)
        const r1 = -w * (z - r), r2 = -w * (z + r)
        const c2 = (v0 - r1 * e0) / (r2 - r1)
        const c1 = e0 - c2
        const x1 = Math.exp(r1 * dt), x2 = Math.exp(r2 * dt)
        e = c1 * x1 + c2 * x2
        v = r1 * c1 * x1 + r2 * c2 * x2
    }
    return { x: target + e, v: v }
}

// At rest: within `epsilon` of the target and moving slower than `epsilon` per 1/60 s,
// so a spring passing through its target at speed is not mistaken for one that arrived.
function settled(state, target, epsilon) {
    return Math.abs(state.x - target) < epsilon && Math.abs(state.v) < epsilon * 60
}

// The overshoot of a step response, as a fraction of the step (0 when ζ ≥ 1). For tests
// and for documenting a preset: Material's expressive default (ζ 0.8) is ~1.5%.
function overshoot(spec) {
    const z = spec.damping
    return z >= 1 ? 0 : Math.exp(-z * Math.PI / Math.sqrt(1 - z * z))
}
