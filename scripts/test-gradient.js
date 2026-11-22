// ── test-gradient.js ──────────────────────────────────────────────────────────
// services/gradient.js: the bar gradient's document, its line and its colours.
//
//     bun scripts/test-gradient.js     (or: node ...)
//
// Reads gradient.js and every file in colorschemes/; writes nothing.
//
// The document arrives from scheme files other people write, so the failures worth pinning are the
// silent ones: a bad stop painted as black, a NaN angle that reaches the shader, a scheme whose
// gradient key stops loading after an edit.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync, readdirSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const G = new Function(
    readFileSync(join(here, "..", "services", "gradient.js"), "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "")
    + "\nreturn { ROLES, DEFAULTS, STRENGTH_MAX, clean, axis, mix, colours, vivid, raw, same };")();

let pass = 0, fail = 0;
function ok(name, cond, detail) {
    if (cond) pass++;
    else { fail++; console.log(`  FAIL  ${name}${detail ? "\n          " + detail : ""}`); }
}
const near = (a, b) => Math.abs(a - b) < 1e-6;

// clean(): never throws, always complete
for (const bad of [undefined, null, 7, "x", [], {}, { stops: "no" }, { angle: NaN }, { angle: "up" }]) {
    const d = G.clean(bad);
    ok(`clean(${JSON.stringify(bad)}) is complete`,
       d.on === false && isFinite(d.angle) && d.stops.length >= 2 && d.strength >= 0 && d.strength <= 1);
}
ok("clean keeps a valid document", G.same(G.clean({ on: true, angle: 45, strength: 0.8, mid: 0.3, stops: ["#112233", "vivid", "fg"] }),
   { on: true, angle: 45, strength: 0.8, mid: 0.3, stops: ["#112233", "vivid", "fg"] }));
ok("clean drops an unknown role", G.clean({ stops: ["primary", "nope", "focus"] }).stops.join() === "primary,focus");
ok("clean drops a short hex", G.clean({ stops: ["#fff", "#abc"] }).stops.join() === G.DEFAULTS.stops.join());
ok("clean drops a hex with an alpha", G.clean({ stops: ["#11223344", "#112233"] }).stops.join() === G.DEFAULTS.stops.join());
ok("clean caps at three stops", G.clean({ stops: ["primary", "focus", "vivid", "fg"] }).stops.length === 3);
ok("clean wraps the angle", near(G.clean({ angle: -90 }).angle, 270) && near(G.clean({ angle: 450 }).angle, 90));
ok("clean clamps strength and mid", G.clean({ strength: 9 }).strength === 1 && G.clean({ strength: -1 }).strength === 0
   && G.clean({ mid: 0 }).mid === 0.1 && G.clean({ mid: 1 }).mid === 0.9);
ok("clean: only true turns it on", G.clean({ on: "yes" }).on === false && G.clean({ on: 1 }).on === false);
ok("clean does not alias the default stops", G.clean({}).stops !== G.DEFAULTS.stops);

// axis(): corners reach the ends
for (const [a, w, h] of [[0, 1920, 1080], [90, 1920, 1080], [30, 1920, 1080], [135, 800, 600], [270, 100, 400]]) {
    const [x0, y0, dx, dy] = G.axis(a, w, h), len2 = dx * dx + dy * dy;
    const t = (x, y) => ((x - x0) * dx + (y - y0) * dy) / len2;
    const ts = [t(0, 0), t(w, 0), t(0, h), t(w, h)];
    ok(`axis ${a}°: the corners span 0..1`, near(Math.min(...ts), 0) && near(Math.max(...ts), 1), ts.join());
}
{
    const [x0, y0, dx, dy] = G.axis(0, 1000, 500);
    ok("axis 0° runs left to right", near(x0, 0) && near(dx, 1000) && near(dy, 0));
    const down = G.axis(90, 1000, 500);
    ok("axis 90° runs top to bottom", near(down[1], 0) && near(down[3], 500) && Math.abs(down[2]) < 1e-9);
}
ok("axis of an empty surface is a valid line", G.axis(30, 0, 0).join() === "0,0,1,0");

// colours()
const role = n => ({ primary: "#ff0000", focus: "#0000ff", vivid: "#00ff00", fg: "#ffffff", primaryContainer: "#808080" })[n];
{
    const full = G.colours({ stops: ["primary", "#00ff00", "focus"], strength: 1 }, role, "#000000");
    const m = G.STRENGTH_MAX;
    ok("strength 1 stops at STRENGTH_MAX of the way", full.join() === [G.mix("#000000", "#ff0000", m), G.mix("#000000", "#00ff00", m), G.mix("#000000", "#0000ff", m)].join());
    ok("STRENGTH_MAX is 0.6", m === 0.6);
    const flat = G.colours({ stops: ["primary", "focus"], strength: 0 }, role, "#101010");
    ok("strength 0 is the plain fill, three times", flat.join() === "#101010,#101010,#101010");
    const half = G.colours({ stops: ["primary", "focus"], strength: 0.5, mid: 0.5 }, role, "#000000");
    ok("half strength moves half of STRENGTH_MAX", half[0] === G.mix("#000000", "#ff0000", 0.5 * m) && half[2] === G.mix("#000000", "#0000ff", 0.5 * m));
    ok("two stops gain a middle between them", half[1] === G.mix(half[0], half[2], 0.5), half.join());
    const skew = G.colours({ stops: ["primary", "focus"], strength: 1, mid: 0.25 }, role, "#000000");
    ok("the middle follows `mid`", skew[1] === G.mix(skew[0], skew[2], 0.25));
    ok("raw gives the stops unmixed", G.raw({ stops: ["primary", "#00ff00"] }, role).join() === "#ff0000,#00ff00");
    ok("a fill with an alpha is read as its colour", G.colours({ strength: 0 }, role, "#80102030")[0] === "#102030");
    // vivid(): the stops whole, whatever the strength
    const v = G.vivid({ stops: ["primary", "#00ff00", "focus"], strength: 0.1 }, role);
    ok("vivid ignores strength", v.join() === "#ff0000,#00ff00,#0000ff", v.join());
    const v2 = G.vivid({ stops: ["primary", "focus"], strength: 0, mid: 0.25 }, role);
    ok("vivid: two stops gain a middle at `mid`", v2[0] === "#ff0000" && v2[2] === "#0000ff" && v2[1] === G.mix("#ff0000", "#0000ff", 0.25), v2.join());
    ok("vivid reads a role with an alpha as its colour", G.vivid({ stops: ["primary", "focus"] }, () => "#80102030")[0] === "#102030");
    ok("vivid of nothing is still three colours", G.vivid(undefined, role).length === 3);
}

// every shipped scheme's gradient (if any) survives clean() unchanged in meaning
let withGradient = 0;
const dir = join(here, "..", "colorschemes");
for (const f of readdirSync(dir).filter(f => f.endsWith(".json"))) {
    const raw = JSON.parse(readFileSync(join(dir, f), "utf8"));
    if (raw.gradient === undefined) continue;
    withGradient++;
    const d = G.clean(raw.gradient);
    ok(`${f}: gradient is on`, raw.gradient.on === true && d.on === true);
    ok(`${f}: every stop is valid, none dropped`, raw.gradient.stops.length === d.stops.length
       && raw.gradient.stops.every((s, i) => s === d.stops[i]), JSON.stringify(raw.gradient.stops));
    ok(`${f}: angle and strength survive`, near(d.angle, ((raw.gradient.angle % 360) + 360) % 360)
       && near(d.strength, raw.gradient.strength));
    ok(`${f}: a gradient scheme still has its palette`, !!raw.colors && !!raw.special);
}
ok("a shipped scheme carries a gradient", withGradient >= 1);

console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
