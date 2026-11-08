// ── test-musicpulse.js ────────────────────────────────────────────────────────
// Regression tests for services/musicpulse.js, the envelopes and beat detector behind
// MusicPulse (the wallpaper effects, the music-reactive sidebar).
//
//     bun scripts/test-musicpulse.js          (or: node scripts/test-musicpulse.js)
//
// Pure functions; touches nothing. Loaded by stripping its `.pragma library` line, so the
// tests run against the real file.
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "musicpulse.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const M = new Function(src + "\nreturn { initial, step, rest, REFRACTORY_MS, songInitial, songStep, songView, character, schedInitial, schedLine, schedAt };")();

let failed = 0, passed = 0;
function check(name, ok, detail) {
    if (ok) passed++; else { failed++; console.log("FAIL", name, detail ?? ""); }
}

const N = 24, FRAME = 1000 / 60;
// MusicPulse's own stream: 24 bars, the kick band the bottom four, `bass` the bottom quarter.
const frame = (bass, rest) => Array.from({ length: N }, (_, i) => i < N / 4 ? bass : rest);
function run(frames) {
    let s = M.initial()
    for (const f of frames) s = M.step(s, f, FRAME)
    return s
}

// Silence: nothing moves, nothing fires.
{
    const s = run(Array(300).fill(frame(0, 0)))
    check("silence level", s.level === 0, s.level)
    check("silence beats", s.beats === 0, s.beats)
}

// 120 BPM kicks over a quiet bed for 8 s: a beat every 30 frames, the kick a few frames long.
{
    const frames = []
    for (let i = 0; i < 480; i++) frames.push(i % 30 < 4 ? frame(0.9, 0.15) : frame(0.12, 0.15))
    const s = run(frames)
    check("120 bpm beat count", s.beats >= 15 && s.beats <= 16, s.beats)
    check("bass envelope moved", s.bass > 0.1, s.bass)
}

// A steady loud tone fires once at most as it starts, then the average catches up.
{
    const s = run(Array(600).fill(frame(0.8, 0.6)))
    check("steady tone fires at most once", s.beats <= 1, s.beats)
    check("steady tone level up", s.level > 0.6, s.level)
}

// The kick decays: 1 on the beat, well under half a quarter-second later.
{
    let s = run(Array(60).fill(frame(0.1, 0.1)))
    s = M.step(s, frame(0.95, 0.1), FRAME)
    check("kick on beat", s.kick === 1, s.kick)
    for (let i = 0; i < 15; i++) s = M.step(s, frame(0.1, 0.1), FRAME)
    check("kick decays", s.kick < 0.4, s.kick)
}

// Refractory: two spikes 3 frames apart are one beat. (Sound out of silence is itself an
// onset, so the bed's first frame counted one: measure from after it.)
{
    let s = run(Array(60).fill(frame(0.1, 0.1)))
    const before = s.beats
    s = M.step(s, frame(0.95, 0.1), FRAME)
    s = M.step(s, frame(0.1, 0.1), FRAME)
    s = M.step(s, frame(0.1, 0.1), FRAME)
    s = M.step(s, frame(0.95, 0.1), FRAME)
    check("refractory merges close spikes", s.beats - before === 1, s.beats - before)
}

// A bass that sits near its ceiling still shows its kicks: the first detector (level over its
// own average) found 3 beats in 20 s of real music whose bass clipped half the time.
{
    const frames = []
    for (let i = 0; i < 480; i++) frames.push(i % 30 < 3 ? frame(1.0, 0.3) : frame(0.85, 0.3))
    const s = run(frames)
    check("saturated bass still finds kicks", s.beats >= 14 && s.beats <= 17, s.beats)
}

// A slow swell (no attack) is no beat: flux wants a rise within a frame or two.
{
    const frames = []
    for (let i = 0; i < 300; i++) frames.push(frame(Math.min(0.9, i / 300), 0.2))
    const s = run(frames)
    check("a swell is not a beat", s.beats <= 1, s.beats)
}

// The strobe's flash: never more than three a second, however fast the beats come.
{
    let s = M.initial(), flashes = 0, windowStart = 0, inWindow = 0, worst = 0, t = 0
    for (let i = 0; i < 1200; i++) {               // 20 s of hard kicks every 9 frames (~400 BPM)
        const before = s.sinceFlash
        s = M.step(s, i % 9 < 2 ? frame(1.0, 0.2) : frame(0.05, 0.2), FRAME)
        t += FRAME
        if (s.sinceFlash < before) {
            flashes++
            if (t - windowStart >= 1000) { windowStart = t; inWindow = 0 }
            worst = Math.max(worst, ++inWindow)
        }
    }
    check("flashes happen", flashes > 10, flashes)
    check("never more than 3 flashes a second", worst <= 3, worst)
}

// Music stopping: rest() eases everything back toward 0.
{
    let s = run(Array(120).fill(frame(0.8, 0.5)))
    for (let i = 0; i < 120; i++) s = M.rest(s, FRAME)
    check("rest eases level", s.level < 0.02, s.level)
}

// A stalled frame (a 2 s gap) is clamped, not read as one huge step.
{
    let s = run(Array(60).fill(frame(0.1, 0.1)))
    const t = M.step(s, frame(0.1, 0.1), 2000)
    check("stall clamped", Math.abs(t.sinceKick - s.sinceKick - 250) < 1e-6, t.sinceKick - s.sinceKick)
}

// The fallback's drums (2026-10-31, one sound per effect): a rise high up is a snare, the
// top bar alone a hat, and a kick is neither.
{
    const bed = Array(N).fill(0.1)
    const hit = (from, to, v) => bed.map((x, i) => (i >= from && i < to ? v : x))
    const play = (f) => {
        let s = M.initial(), hats = 0
        for (let t = 0; t < 480; t++) {
            const prevHat = s.hat
            s = M.step(s, t % 30 < 3 ? f : bed, FRAME)
            if (s.hat === 1 && prevHat < 1) hats++
        }
        return { snares: s.snares, hats, beats: s.beats }
    }
    const sn = play(hit(16, 23, 0.9))
    check("fallback: snares are snares", sn.snares >= 14 && sn.beats === 0 && sn.hats === 0, JSON.stringify(sn))
    const ht = play(hit(23, 24, 0.9))
    check("fallback: hats are hats", ht.hats >= 14 && ht.snares === 0 && ht.beats === 0, JSON.stringify(ht))
    const k = play(hit(0, 4, 0.9))
    check("fallback: a kick is no snare or hat", k.beats >= 14 && k.snares === 0 && k.hats === 0, JSON.stringify(k))
}

// The song (2026-10-31, the effects adapting to the track): rates settle on what's played,
// from the first seconds (the bias fix), hats are counted off their envelope, and a gap in
// the drums of a track that had them is a breakdown.
{
    // A pulse stream at 100 lines a second: kicks every `kickMs`, snares every `snareMs`, hats
    // every `hatMs` (0 = none), for `ms`.
    const play = (s, ms, kickMs, snareMs, hatMs, from) => {
        let p = from || { beats: 0, snares: 0, booms: 0, hat: 0 }
        for (let t = 0; t < ms; t += 10) {
            p = { ...p }
            if (kickMs && t % kickMs === 0) p.beats++
            if (snareMs && t % snareMs === 0) p.snares++
            p.hat = hatMs && t % hatMs < 20 ? 1 : 0
            s = M.songStep(s, p, 10)
        }
        return { s, p }
    }
    const near = (a, b, tol) => Math.abs(a - b) <= tol
    let r = play(M.songInitial(), 3000, 500, 1000, 250)
    let v = M.songView(r.s)
    check("song: kick rate from 3 s", near(v.kick, 2, 0.5), v.kick)
    check("song: snare rate from 3 s", near(v.snare, 1, 0.4), v.snare)
    check("song: hats counted off the envelope", near(v.hat, 4, 0.8) && r.s.hats === 12, v.hat + " " + r.s.hats)
    check("song: a 120 BPM backbeat drives", v.energy > 0.6, v.energy)
    check("song: drums playing, no breakdown", v.breakdown === 0, v.breakdown)
    r = play(r.s, 20000, 500, 1000, 250, r.p)
    check("song: says what it is", M.character(M.songView(r.s)).startsWith("Driving"), M.character(M.songView(r.s)))
    const gap = play(r.s, 4000, 0, 0, 0, r.p)
    v = M.songView(gap.s)
    check("song: the drums gone is a breakdown", v.breakdown > 0.7, v.breakdown)
    check("song: and says so", M.character(v) === "Breakdown", M.character(v))
    const back = play(gap.s, 3000, 500, 1000, 250, gap.p)
    check("song: the drop ends it", M.songView(back.s).breakdown < 0.3, M.songView(back.s).breakdown)
    const calm = play(M.songInitial(), 10000, 0, 0, 0)
    v = M.songView(calm.s)
    check("song: no drums is calm, never a breakdown", v.energy === 0 && v.breakdown === 0 && M.character(v) === "Calm",
          JSON.stringify(v))
    // Turning on mid-song: the first step only learns the counts.
    const mid = M.songStep(M.songInitial(), { beats: 400, snares: 200, booms: 90, hat: 0 }, 10)
    check("song: no stale burst", mid.kick === 0 && mid.snare === 0 && mid.boom === 0, JSON.stringify(mid))
    check("song: nothing to say at first", M.character(M.songView(M.songInitial())) === "")
}

// How big this part is (2026-10-31: calm parts calm, drops big). From the helper's loud/sub.
{
    const feed = (s, ms, loud, sub, from) => {
        let p = from || { beats: 0, snares: 0, booms: 0, hat: 0 }
        for (let t = 0; t < ms; t += 10) {
            p = { ...p, loud, sub }
            if (t % 500 === 0) p.beats++
            s = M.songStep(s, p, 10)
        }
        return { s, p }
    }
    let r = feed(M.songInitial(), 10000, 0.3, 0.1)
    let v = M.songView(r.s)
    check("section: a calm part reads small", v.section < 0.25, v.section)
    check("section: and says so", M.character(v) === "A calm part", M.character(v))
    const before = r.s.section
    r = feed(r.s, 300, 0.95, 0.95, r.p)
    v = M.songView(r.s)
    check("section: the drop lands at once", v.section > 0.8, before + " → " + v.section)
    check("section: and is called a drop", v.drop > 0.9 && M.character(v) === "The drop", v.drop + " " + M.character(v))
    r = feed(r.s, 6000, 0.95, 0.95, r.p)
    check("section: the drop fades into the big part", M.songView(r.s).drop < 0.2 && M.songView(r.s).section > 0.9,
          JSON.stringify(M.songView(r.s)))
    const once = feed(r.s, 1000, 0.3, 0.1, r.p)
    const again = feed(once.s, 300, 0.95, 0.95, once.p)
    check("section: one drop per 8 s", M.songView(again.s).drop < 0.5, M.songView(again.s).drop)
    const down = feed(r.s, 300, 0.2, 0.0, r.p)
    check("section: a calm part arrives slowly", M.songView(down.s).section > 0.6, M.songView(down.s).section)
    const steady = feed(M.songInitial(), 10000, 0.9, 0.9)
    check("section: a song loud from the start has no drop", M.songView(steady.s).drop < 0.05, M.songView(steady.s).drop)
}

// The scheduler (2026-10-31): each event shown when the speakers play it.
{
    const S = M.schedInitial()
    const sline = (t) => ["s", String(t), "0.5", "0.4", "0.3", "0.2", "0.8", "0.7", "0.75", "128.0", "1", "1.5"]
    M.schedLine(S, ["latency", "32"], 0, 0)
    // Lines arrive in bursts: four hops' worth at once, 21 ms late at worst.
    let wall = 1000
    for (let k = 0; k < 40; k++) {
        const tAudio = k * 0.0213
        for (let j = 0; j < 4; j++) M.schedLine(S, sline(tAudio + j * 0.0053), wall + k * 21.3 + 21.3, 0)
    }
    check("sched: the clock mapping is the earliest arrival", Math.abs(S.off - (wall + 21.3 - 3 * 5.3)) < 1.0, S.off)
    // A kick at audio 0.500 s: due at 500 + off + 32 ms latency (+ 20 ms Sync).
    M.schedLine(S, ["e", "0.5000", "kick", "0.8", "0.9", "down"], wall + 600, 20)
    const due = 500 + S.off + 32 + 20
    let p = M.schedAt(S, due - 1)
    check("sched: nothing before it's heard", p.kick === 0 && p.beats === 0, JSON.stringify([p.kick, p.beats]))
    p = M.schedAt(S, due)
    check("sched: on the frame it's heard", p.kick === 1 && p.beats === 1 && p.heavy === 0.9 && p.kickRole === "down",
          JSON.stringify(p))
    p = M.schedAt(S, due + 170)
    check("sched: and decays", Math.abs(p.kick - Math.exp(-1)) < 1e-6, p.kick)
    // Roles: a back snare is an accent, a ghost isn't; a drop is an impact, and boosts its kick.
    M.schedLine(S, ["e", "0.6000", "snare", "0.7", "0.0", "back"], wall + 700, 20)
    M.schedLine(S, ["e", "0.6500", "snare", "0.5", "0.0", "ghost"], wall + 750, 20)
    M.schedLine(S, ["e", "0.7000", "kick", "0.9", "1.0", "down"], wall + 800, 20)
    M.schedLine(S, ["e", "0.7000", "drop", "1.0", "0.0", "struct"], wall + 800, 20)
    p = M.schedAt(S, 700 + S.off + 52 + 1)
    check("sched: a back snare rings, a ghost doesn't", p.snares === 2 && p.accents === 1, JSON.stringify([p.snares, p.accents]))
    check("sched: the drop is an impact on its kick, which punches harder", p.impacts === 1 && p.drops === 1 && p.kickBoost > 1,
          JSON.stringify([p.impacts, p.drops, p.kickBoost]))
    check("sched: the state line's section comes through", p.section === 0.75 && p.loud === 0.8, JSON.stringify([p.section, p.loud]))
    check("sched: queues stay bounded", S.events.length === 0)
}

console.log(`${passed} passed, ${failed} failed`)
process.exit(failed ? 1 : 0)
