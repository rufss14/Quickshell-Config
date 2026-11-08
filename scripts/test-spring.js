// ── test-spring.js ────────────────────────────────────────────────────────────
// Regression tests for components/spring.js, the closed-form spring behind SpringValue
// and the Motion.spring* presets.
//
//     bun scripts/test-spring.js          (or: node scripts/test-spring.js)
//
// Pure functions; touches nothing. spring.js is loaded by stripping its `.pragma library`
// line, so the tests run against the real file.
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "components", "spring.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const { scaled, step, settled, overshoot } = new Function(
    src + "\nreturn { scaled, step, settled, overshoot };")();

let failed = 0;
function check(name, ok, detail) {
    if (!ok) { failed++; console.log("FAIL", name, detail ?? ""); }
}
const near = (a, b, eps) => Math.abs(a - b) < eps;

// Material 3 Expressive's spatial springs (Compose ExpressiveMotionTokens), and an effects one.
const FAST = { stiffness: 800, damping: 0.6 };
const DEFAULT = { stiffness: 380, damping: 0.8 };
const SLOW = { stiffness: 200, damping: 0.8 };
const EFFECTS = { stiffness: 1600, damping: 1.0 };
const OVER = { stiffness: 400, damping: 1.6 };

// Runs a 0 → 1 step at `hz`, returning the peak, when it peaked, and when it settled.
function run(spec, hz, from = { x: 0, v: 0 }, target = 1, seconds = 3) {
    let s = from, peak = -Infinity, tPeak = 0, tRest = -1
    const dt = 1 / hz
    // Counted, not accumulated: `t += dt` drifts and can drop the last frame.
    for (let i = 1; i <= Math.round(seconds * hz); i++) {
        const t = i * dt
        s = step(s, target, spec, dt)
        if (s.x > peak) { peak = s.x; tPeak = t }
        if (tRest < 0 && settled(s, target, 0.001)) tRest = t
    }
    return { s, peak, tPeak, tRest }
}

// The analytic overshoot matches the simulated one, for each underdamped preset.
for (const [name, spec] of [["fast", FAST], ["default", DEFAULT], ["slow", SLOW]]) {
    const r = run(spec, 1000)
    check(name + " overshoot", near(r.peak - 1, overshoot(spec), 2e-4), [r.peak - 1, overshoot(spec)])
    // Peak time is π / ωd.
    const wd = Math.sqrt(spec.stiffness) * Math.sqrt(1 - spec.damping ** 2)
    check(name + " peak time", near(r.tPeak, Math.PI / wd, 0.002), [r.tPeak, Math.PI / wd])
    check(name + " settles", r.tRest > 0 && near(r.s.x, 1, 1e-6))
}
// The numbers Material documents: ~9.5% for fast, ~1.5% for default/slow.
check("fast ~9.5%", near(overshoot(FAST), 0.095, 0.002), overshoot(FAST))
check("default ~1.5%", near(overshoot(DEFAULT), 0.015, 0.001), overshoot(DEFAULT))

// Critically damped and overdamped never pass the target.
for (const [name, spec] of [["effects", EFFECTS], ["overdamped", OVER]]) {
    const r = run(spec, 1000)
    check(name + " no overshoot", r.peak <= 1 + 1e-9, r.peak)
    check(name + " settles", r.tRest > 0, r.tRest)
}

// Exact: one big step equals many small ones, at every damping regime. This is what makes the
// result independent of the refresh rate (165 Hz vs 60 Hz land on the same curve).
for (const [name, spec] of [["fast", FAST], ["effects", EFFECTS], ["overdamped", OVER]]) {
    const one = step({ x: 0, v: 0 }, 1, spec, 0.1)
    let many = { x: 0, v: 0 }
    for (let i = 0; i < 100; i++) many = step(many, 1, spec, 0.001)
    check(name + " step-size independent", near(one.x, many.x, 1e-9) && near(one.v, many.v, 1e-7), [one, many])
    const a = run(spec, 165, undefined, 1, 0.2).s, b = run(spec, 60, undefined, 1, 0.2).s
    // Both runs stop on their own last frame, so compare against the exact state at that time.
    check(name + " 165Hz on the curve", near(a.x, step({ x: 0, v: 0 }, 1, spec, Math.round(0.2 * 165) / 165).x, 1e-9))
    check(name + " 60Hz on the curve", near(b.x, step({ x: 0, v: 0 }, 1, spec, Math.round(0.2 * 60) / 60).x, 1e-9))
}

// A stiff effects spring stays stable even across a long frame (Qt's 16 ms Euler step does not).
const stiff = { stiffness: 3800, damping: 1.0 }
const hop = step({ x: 0, v: 0 }, 1, stiff, 0.05)
check("stiff stable", hop.x > 0 && hop.x <= 1, hop)

// Retargeting keeps the velocity: a spring heading for 1 sent back to 0 mid-flight is still
// moving toward 1 at the instant of the change.
const mid = step({ x: 0, v: 0 }, 1, DEFAULT, 0.05)
const after = step(mid, 0, DEFAULT, 0.001)
check("retarget keeps momentum", after.x > mid.x, [mid.x, after.x])

// Time scaling: twice as slow lands at t·2 where the original was at t.
const base = step({ x: 0, v: 0 }, 1, DEFAULT, 0.1)
const slow2 = step({ x: 0, v: 0 }, 1, scaled(DEFAULT, 2), 0.2)
check("scaled", near(base.x, slow2.x, 1e-9), [base.x, slow2.x])
check("scale 0 = unscaled", scaled(DEFAULT, 0).stiffness === DEFAULT.stiffness)

// settled(): passing through the target at speed is not rest.
check("not settled at speed", !settled({ x: 1, v: 2 }, 1, 0.001))
check("settled", settled({ x: 1.0004, v: 0.01 }, 1, 0.001))

if (failed) { console.log(failed + " failed"); process.exit(1) }
console.log("spring: all passed")
