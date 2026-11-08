// ── test-wallfx.js ────────────────────────────────────────────────────────────
// Regression tests for services/wallfx.js — the wallpaper's music effects: which sound moves
// which effect, how the song weighs them, the per-screen motion, and the shader's amounts.
//
//     bun scripts/test-wallfx.js          (or: node scripts/test-wallfx.js)
//
// Pure functions; touches nothing. Loaded by stripping its `.pragma library` line.
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "wallfx.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const F = new Function(src + "\nreturn { SOUNDS, ORDINARY, BUSY_FLOOR, RUMBLE_REACH, RUMBLE_MAX_MS, SHOCK_LIFE_MS," +
                             " trimOf, anyOn, adapt, motionInitial, step, amounts, glide, any };")();

let failed = 0, passed = 0;
function check(name, ok, detail) {
    if (ok) passed++; else { failed++; console.log("FAIL", name, detail ?? ""); }
}

const silent = { level: 0, bass: 0, mid: 0, high: 0, kick: 0, beats: 0, snare: 0, snares: 0, hat: 0,
                 boom: 0, booms: 0, impact: 0, impacts: 0, flash: 0 };
const loud = { level: 0.8, bass: 0.9, mid: 0.7, high: 0.5, kick: 1, beats: 7, snare: 1, snares: 3, hat: 1,
               boom: 1, booms: 5, impact: 1, impacts: 2, flash: 1 };
const groove = { kick: 2, snare: 1, hat: 4, boom: 1, energy: 0.7, breakdown: 0, hats: 0, age: 10000 };
const allOn = Object.fromEntries(F.SOUNDS.map(s => [s.id, 1]));
const onlyBass = { ...Object.fromEntries(F.SOUNDS.map(s => [s.id, 0])), bass: 2 };
const aspect = 16 / 9;

// A motion that has just heard a kick and a snare, `ms` ago, the bass still held.
function hit(ms, p = loud) {
    let m = F.step(F.motionInitial(), { ...p, beats: p.beats - 1, snares: p.snares - 1 }, 16);
    m = F.step(m, p, 16);
    for (let t = 0; t < ms; t += 16) m = F.step(m, p, 16);
    return m;
}

// ── The sounds ────────────────────────────────────────────────────────────────
check("nine sounds", F.SOUNDS.length === 9, F.SOUNDS.length);
check("each sound has its look",
      ["kick:Zoom & pulse", "bass:Rumble", "snare:Shockwave", "hats:Shimmer", "vocals:Bloom", "loudness:Glow",
       "hardest:Glitch", "breakdown:Blur", "strobe:Strobe"]
          .every(pair => { const [id, fx] = pair.split(":"); return F.SOUNDS.some(s => s.id === id && s.effect === fx) }));
check("strobe is the only opt-in, and warned", F.SOUNDS.filter(s => s.optIn).map(s => s.id).join() === "strobe"
      && F.SOUNDS.find(s => s.id === "strobe").warning === true);

// ── Trims ─────────────────────────────────────────────────────────────────────
check("absent = auto", F.trimOf({}, "kick") === 1 && F.trimOf(undefined, "snare") === 1);
check("strobe absent = off", F.trimOf({}, "strobe") === 0);
check("a trim is kept, clamped to 0..2", F.trimOf({ kick: 1.5 }, "kick") === 1.5 && F.trimOf({ kick: 9 }, "kick") === 2
      && F.trimOf({ kick: -1 }, "kick") === 0);
check("anything on by default", F.anyOn({}));
check("everything trimmed off = nothing on", !F.anyOn(Object.fromEntries(F.SOUNDS.map(s => [s.id, 0]))));

// ── Silence, off, intensity 0 ─────────────────────────────────────────────────
{
    const a = F.amounts(allOn, 1, silent, groove, F.motionInitial(), aspect);
    check("silence: nothing", !F.any(a), JSON.stringify(a));
    const off = F.amounts(Object.fromEntries(F.SOUNDS.map(s => [s.id, 0])), 1, loud, groove, hit(0), aspect);
    check("all off: nothing", !F.any(off), JSON.stringify(off));
    const zero = F.amounts(allOn, 0, loud, groove, hit(0), aspect);
    check("intensity 0: nothing", !F.any(zero), JSON.stringify(zero));
}

// ── Loud, everything on: every amount moves, none past 1 ──────────────────────
{
    const a = F.amounts({ ...allOn, strobe: 1 }, 1, loud, { ...groove, breakdown: 1 }, hit(32), aspect);
    for (const k of ["punch", "pulse", "shock", "shimmer", "glitch", "glow", "bloom", "strobe"])
        check("loud moves " + k, a[k] > 0 && a[k] <= 1, a[k]);
    check("loud zooms", a.zoom > 0 && a.zoom <= 0.12, a.zoom);
    check("loud rumbles", Math.hypot(a.shakeX, a.shakeY) > 0, a.shakeX + "," + a.shakeY);
    check("shockwave ring has left the middle", a.shockR > 0, a.shockR);
}

// ── One sound, its effect only ────────────────────────────────────────────────
{
    const only = (fields) => F.amounts({ ...allOn, strobe: 1 }, 1, { ...silent, ...fields }, groove, F.motionInitial(), aspect);
    const moved = (a) => Object.keys(a).filter(k => k !== "shockR" && Math.abs(a[k]) > 1e-6).sort().join();
    check("kick: zoom, punch, pulse", moved(only({ kick: 1 })) === "pulse,punch,zoom", moved(only({ kick: 1 })));
    check("hat: shimmer", moved(only({ hat: 1 })) === "shimmer", moved(only({ hat: 1 })));
    check("mids: bloom", moved(only({ mid: 1 })) === "bloom");
    check("loudness: glow", moved(only({ level: 1 })) === "glow");
    check("hardest hit: glitch", moved(only({ impact: 1 })) === "glitch");
    check("flash: strobe", moved(only({ flash: 1 })) === "strobe");
    check("snare envelope alone moves nothing (the shockwave is per snare)", moved(only({ snare: 1 })) === "");
    check("bass without a note doesn't rumble", moved(only({ bass: 1 })) === "");
}

// ── The rumble ────────────────────────────────────────────────────────────────
{
    // Held: the bass stays up, the gate decays slowly, and the tremble keeps going.
    const held = hit(300);
    check("rumble holds while the bass does", held.gate > 0.4, held.gate);
    const dropped = hit(300, { ...loud, bass: 0.1 });
    check("rumble dies when the bass falls", dropped.gate < 0.05, dropped.gate);
    const drone = hit(F.RUMBLE_MAX_MS + 300);
    check("a drone stops rattling", drone.gate < 0.05, drone.gate);
    // It shakes back and forth: over 200 ms the offset changes sign on both axes.
    let m = hit(0), sx = new Set(), sy = new Set(), reach = 0;
    for (let t = 0; t < 200; t += 8) {
        m = F.step(m, loud, 8);
        const a = F.amounts(onlyBass, 1, loud, groove, m, aspect);
        sx.add(Math.sign(a.shakeX)); sy.add(Math.sign(a.shakeY));
        reach = Math.max(reach, Math.abs(a.shakeY));
    }
    check("rumble trembles both ways", sx.has(1) && sx.has(-1) && sy.has(1) && sy.has(-1));
    check("rumble stays within its reach", reach <= 2 * F.RUMBLE_REACH + 1e-9, reach);
    const z = F.amounts(onlyBass, 1, loud, groove, hit(16), aspect);
    check("rumble never zooms", z.zoom === 0, z.zoom);
}

// ── The shockwave ─────────────────────────────────────────────────────────────
{
    const a1 = F.amounts(allOn, 1, silent, groove, hit(60), aspect);
    const a2 = F.amounts(allOn, 1, silent, groove, hit(300), aspect);
    const a0 = F.amounts(allOn, 1, silent, groove, hit(0), aspect);
    check("the ring eases in", a0.shock < a1.shock, a0.shock + " < " + a1.shock);
    check("the ring travels out", a2.shockR > a1.shockR, a1.shockR + " → " + a2.shockR);
    check("and fades", a2.shock < a1.shock && a1.shock > 0, a1.shock + " → " + a2.shock);
    const gone = F.amounts(allOn, 1, silent, groove, hit(F.SHOCK_LIFE_MS + 50), aspect);
    check("and is gone", gone.shock === 0 && gone.shockR === 0);
    // Turned on mid-song: the first frame only learns the counts.
    const first = F.step(F.motionInitial(), loud, 16);
    check("no stale hits on the first frame", first.gate === 0 && first.shockAge > F.SHOCK_LIFE_MS, JSON.stringify(first));
}

// ── The ring only on accents (the user: "constantly getting spammed") ──────────
{
    const base = { ...silent, accents: 4, snares: 10 };
    let m = F.step(F.motionInitial(), base, 16);
    m = F.step(m, { ...base, snares: 11 }, 16);
    check("a snare that isn't an accent: no ring", m.shockAge > F.SHOCK_LIFE_MS, m.shockAge);
    m = F.step(m, { ...base, snares: 12, accents: 5 }, 16);
    check("an accent: a ring", m.shockAge === 0, m.shockAge);
    // Without the helper (accents -1): snares, but not one ring on top of another.
    let f = F.step(F.motionInitial(), { ...silent, accents: -1, snares: 1 }, 16);
    f = F.step(f, { ...silent, accents: -1, snares: 2 }, 16);
    check("fallback: a snare rings", f.shockAge === 0);
    f = F.step(f, { ...silent, accents: -1, snares: 3 }, 100);
    check("fallback: not again within the gap", f.shockAge === 100, f.shockAge);
}

// ── Adapting to the song ──────────────────────────────────────────────────────
{
    const busyHats = F.adapt({ ...groove, hat: 16 }), fewHats = F.adapt({ ...groove, hat: 2 });
    check("busy hats play smaller", busyHats.hats < fewHats.hats * 0.6, busyHats.hats + " vs " + fewHats.hats);
    check("…never below the floor", F.adapt({ ...groove, hat: 1000 }).hats >= F.BUSY_FLOOR * 0.6 - 1e-9);
    // The section (the user: calm parts too intense, drops underwhelming).
    const big = F.adapt({ ...groove, section: 0.95 }), calm = F.adapt({ ...groove, section: 0.15 });
    for (const k of ["kick", "bass", "snare", "hats", "vocals", "loudness", "hardest"])
        check("a big part outdoes a calm one: " + k, big[k] > calm[k] * 2, big[k] + " vs " + calm[k]);
    check("a calm part: the hits almost still", calm.kick <= 0.1 && calm.snare <= 0.1 && calm.hardest <= 0.1, JSON.stringify(calm));
    check("a calm part: a trace of glow stays", calm.loudness >= 0.25 && calm.loudness < 0.5, calm.loudness);
    const dropW = F.adapt({ ...groove, section: 0.95, drop: 1 });
    check("the drop: hits boosted past a big part", dropW.kick > big.kick * 1.4 && dropW.snare > big.snare * 1.4,
          dropW.kick + " vs " + big.kick);
    check("the drop: washes lifted less than the hits", dropW.loudness > big.loudness
          && dropW.loudness / big.loudness < dropW.kick / big.kick);
    for (const v of [{ ...groove, section: 1, drop: 1, kick: 0.1 }, { ...groove, section: 0 }, undefined])
        check("weights stay 0..1.8", Object.values(F.adapt(v)).every(x => x >= 0 && x <= 1.8 + 1e-9), JSON.stringify(F.adapt(v)));
    // Heavy kicks: the punch scales with the kick's bass; only big bass kicks rumble.
    const kickOnly = { ...Object.fromEntries(F.SOUNDS.map(s => [s.id, 0])), kick: 1 };
    const nod = F.amounts(kickOnly, 1, { ...loud, heavy: 0.15 }, groove, hit(0), aspect);
    const slam = F.amounts(kickOnly, 1, { ...loud, heavy: 1 }, groove, hit(0), aspect);
    check("a heavy kick punches harder", slam.punch > nod.punch * 2, nod.punch + " vs " + slam.punch);
    const quiet = F.amounts(onlyBass, 1, { ...loud, heavy: 0.3 }, groove, hit(16, { ...loud, heavy: 0.3 }), aspect);
    check("a light kick doesn't rumble", quiet.shakeX === 0 && quiet.shakeY === 0, quiet.shakeX + "," + quiet.shakeY);
    let mm = hit(0, { ...loud, heavy: 1 }), shook = 0;
    for (let t = 0; t < 80; t += 8) {
        mm = F.step(mm, { ...loud, heavy: 1 }, 8);
        shook = Math.max(shook, Math.hypot(...Object.values((({ shakeX, shakeY }) => ({ shakeX, shakeY }))(
            F.amounts(onlyBass, 1, { ...loud, heavy: 1 }, groove, mm, aspect)))));
    }
    check("a big bass kick rumbles", shook > 0, shook);
    // A bass note between kicks is no longer a rumble.
    const note = F.step(F.step(F.motionInitial(), loud, 16), { ...loud, booms: loud.booms + 1 }, 16);
    check("a bass note alone doesn't rumble", note.gate === 0, note.gate);
    // The breakdown blurs, and the drop's kick snaps it sharp.
    const pads = { ...silent, level: 0.4 };
    const soft = F.amounts(allOn, 1, pads, { ...groove, breakdown: 1 }, F.motionInitial(), aspect);
    const drop = F.amounts(allOn, 1, { ...pads, kick: 1 }, { ...groove, breakdown: 1 }, F.motionInitial(), aspect);
    check("a breakdown blurs", soft.blur > 0.2, soft.blur);
    check("the drop's kick is sharp", drop.blur === 0, drop.blur);
    // The song ends: silence isn't a breakdown, whatever the song's picture still says.
    const end = F.amounts(allOn, 1, silent, { ...groove, breakdown: 1 }, F.motionInitial(), aspect);
    check("the song's end: no blur", end.blur === 0, end.blur);
    let gl = soft;
    for (let t = 0; t < 3000; t += 16) gl = F.glide(gl, end, 16);
    check("…and a blur already up goes by itself", gl.blur === 0 && !F.any(gl), JSON.stringify(gl));
    check("no breakdown, no blur", F.amounts(allOn, 1, loud, groove, hit(0), aspect).blur === 0);
}

// ── Gliding ───────────────────────────────────────────────────────────────────
{
    const rest = F.amounts(allOn, 1, silent, groove, F.motionInitial(), aspect);
    const kick = F.amounts(allOn, 1, { ...silent, kick: 1 }, groove, F.motionInitial(), aspect);
    const one = F.glide(rest, kick, 16);
    check("glide: a kick lands most of the way in a frame", one.zoom > kick.zoom * 0.4 && one.zoom < kick.zoom,
          one.zoom + " of " + kick.zoom);
    let g = rest;
    for (let t = 0; t < 300; t += 16) g = F.glide(g, kick, 16);
    check("glide: and all the way soon after", Math.abs(g.zoom - kick.zoom) < 1e-4, g.zoom);
    const g1 = F.glide(g, rest, 16);
    check("glide: falls slower than it rose", g1.zoom > g.zoom - (g.zoom - one.zoom), g1.zoom);
    const gl = F.amounts({ hardest: 1 }, 1, { ...silent, impact: 1 }, groove, F.motionInitial(), aspect);
    check("glide: a glitch still cuts", F.glide(rest, gl, 16).glitch === gl.glitch);
    check("glide: first frame is the target", F.glide(null, kick, 16) === kick);
    // The rumble eases in over its first moment (`held` drives the ease).
    const m0 = hit(0);
    check("rumble eases in", m0.held < 40, m0.held);
}

// ── Structure: a drop's kick punches harder (the rhythm engine's kickBoost) ────
{
    const kickOnly = { ...Object.fromEntries(F.SOUNDS.map(s => [s.id, 0])), kick: 1 };
    const plain = F.amounts(kickOnly, 0.5, { ...silent, kick: 1, heavy: 0.6 }, groove, F.motionInitial(), aspect);
    const drop = F.amounts(kickOnly, 0.5, { ...silent, kick: 1, heavy: 0.6, kickBoost: 1.4 }, groove, F.motionInitial(), aspect);
    check("a drop's kick punches harder", drop.punch > plain.punch * 1.3 && drop.zoom > plain.zoom, plain.punch + " vs " + drop.punch);
}

// ── Strobe: only when asked ───────────────────────────────────────────────────
check("strobe off unless trimmed on", F.amounts({}, 1, loud, groove, hit(0), aspect).strobe === 0);
check("strobe when asked", F.amounts({ strobe: 1 }, 1, loud, groove, hit(0), aspect).strobe > 0);

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
