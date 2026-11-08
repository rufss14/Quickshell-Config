.pragma library

// ── musicpulse.js ─────────────────────────────────────────────────────────────
// What the music is doing, as a few numbers the desktop can move to: the logic behind
// services/MusicPulse (2026-10-31, the wallpaper effects and the music-reactive sidebar).
// Pure, so it can be tested: `bun scripts/test-musicpulse.js`.
//
// In: one frame of cava's spectrum (0..1 magnitudes, bass first) and the time since the
// last one. Out, all 0..1:
//
//   level   the whole spectrum, followed on an envelope (fast up, slower down)
//   bass    the bottom quarter of it (40–100 Hz), the same way — what a kick drum moves
//   mid     the middle, for brightness-like effects
//   high    the top, for sparkle (hi-hats)
//   kick    1 on a detected beat, decaying — the punch for shakes, flashes, glitches
//   beats   how many beats so far (a seed: each beat can pick a new direction)
//   flash   1 on a STRONG beat, decaying fast — the strobe's (2026-10-31). Never more than
//           three a second (`FLASH_GAP_MS`): the photosensitive-epilepsy guidance (WCAG 2.3.1)
//           is "no more than three flashes in any one second", and a strobe that followed every
//           beat of fast music would break it.
//   snare   1 on a snare or clap, decaying; `snares` counts them
//   hat     1 on a hi-hat, decaying
//   boom · impact   the helper's bass note and hardest hit; cava can't tell them apart, so
//           here `boom` is the kick and `impact` the flash (`booms`/`impacts` count them)
//
// This is the FALLBACK (services/MusicPulse runs scripts/music-pulse.py when it can, which
// hears the drums far better). The snare and hat here are rough (2026-10-31, the one-sound-
// per-effect split, services/wallfx.js): a rise in the bars above ~1.4 kHz that the kick band
// doesn't match is a snare, a rise in the top bar (~6.6–8 kHz) more than in those is a hat.
//
// ── The beat ──────────────────────────────────────────────────────────────────
// A beat is a RISE in the kick band, not a loud kick band: spectral flux — how much the
// lowest `KICK_BARS` bars went UP since the last frame, summed — above its own recent mean
// by `FLUX_K` standard deviations (both on a `FLUX_MS` moving average), over a floor, at most
// once per `REFRACTORY_MS`. Measured 2026-10-31 on 20 s of a 138 BPM funk track: the first
// detector (the bass LEVEL over 1.35× its average) found 3 beats — the shared stream's bass
// sat at its ceiling 52% of the time, so a kick never showed as a jump — where flux found 42,
// 433 ms apart, 83% on the beat grid. It reads MusicPulse's own stream (40 Hz–8 kHz in 24
// bars, from the player's node), whose bass clipped 2% of the time.
var ATTACK_MS = 35
var RELEASE_MS = 240
var KICK_DECAY_MS = 190
var REFRACTORY_MS = 160
var KICK_BARS = 4          // the onset band: 40–78 Hz in MusicPulse's 24 bars
var BASS_FRAC = 0.25       // `bass` is the bottom quarter: 40–100 Hz
var MID_FRAC = 0.6         // `mid` up to here, `high` above
var FLUX_MS = 900
var FLUX_K = 1.5
var FLUX_FLOOR = 0.02
var FLASH_K = 2.5          // a strong beat: flux this many deviations over its mean
var FLASH_GAP_MS = 340     // at most three flashes a second, and a margin
var FLASH_DECAY_MS = 70
var SNARE_FRAC = 0.66      // the snare's bars: from here…
var HAT_FRAC = 0.95        // …to here; the hat's above
var DRUM_K = 1.8
var DRUM_FLOOR = 0.02
var SNARE_REFRACTORY_MS = 120
var HAT_REFRACTORY_MS = 60
var SNARE_DECAY_MS = 150
var HAT_DECAY_MS = 70

function initial() {
    return { level: 0, bass: 0, mid: 0, high: 0, kick: 0, beats: 0, flash: 0, snare: 0, snares: 0, hat: 0, boom: 0, booms: 0, impact: 0, impacts: 0,
             prev: null, fluxMean: 0, fluxSq: 0, sinceKick: 1e9, sinceFlash: 1e9,
             sn: onsetState(), ht: onsetState() }
}

function onsetState() { return { mean: 0, sq: 0, since: 1e9 } }

// One onset detector's step (the kick's rule, for another band): the next state, and `hit`.
function onset(o, flux, dt, refractory) {
    o = o || onsetState()
    var sd = Math.sqrt(Math.max(0, o.sq - o.mean * o.mean))
    var since = o.since + dt
    var hit = flux > o.mean + DRUM_K * sd && flux > DRUM_FLOOR && since >= refractory
    var a = 1 - Math.exp(-dt / FLUX_MS)
    return { mean: o.mean + (flux - o.mean) * a, sq: o.sq + (flux * flux - o.sq) * a,
             since: hit ? 0 : since, hit: hit }
}

// The mean rise of bars [from, to) since the last frame.
function rise(bars, prev, from, to) {
    if (!prev || to <= from) return 0
    var f = 0
    for (var i = from; i < to; i++) f += Math.max(0, (bars[i] || 0) - (prev[i] || 0))
    return f / (to - from)
}

function mean(a, from, to) {
    var n = Math.max(1, to - from), s = 0
    for (var i = from; i < to; i++) s += a[i] || 0
    return s / n
}

// One envelope step toward `x`: `attack` ms going up, `release` ms coming down.
function follow(y, x, dt, attack, release) {
    var tau = x > y ? attack : release
    return y + (x - y) * (1 - Math.exp(-dt / Math.max(1, tau)))
}

function step(s, bars, dt) {
    var n = bars ? bars.length : 0
    dt = Math.max(0, Math.min(dt, 250))           // a stall must not read as a jump
    var out = {
        level: s.level, bass: s.bass, mid: s.mid, high: s.high, kick: s.kick, beats: s.beats,
        flash: s.flash * Math.exp(-dt / FLASH_DECAY_MS),
        prev: s.prev, fluxMean: s.fluxMean, fluxSq: s.fluxSq, sinceKick: s.sinceKick + dt,
        sinceFlash: s.sinceFlash + dt,
        snare: (s.snare || 0) * Math.exp(-dt / SNARE_DECAY_MS), snares: s.snares || 0,
        hat: (s.hat || 0) * Math.exp(-dt / HAT_DECAY_MS), sn: s.sn, ht: s.ht,
        boom: (s.boom || 0) * Math.exp(-dt / KICK_DECAY_MS), booms: s.booms || 0,
        impact: (s.impact || 0) * Math.exp(-dt / FLASH_DECAY_MS), impacts: s.impacts || 0
    }
    var lo = Math.max(1, Math.round(n * BASS_FRAC)), md = Math.max(lo + 1, Math.round(n * MID_FRAC))
    out.level = follow(s.level, n > 0 ? mean(bars, 0, n) : 0, dt, ATTACK_MS, RELEASE_MS)
    out.bass  = follow(s.bass,  n > 0 ? mean(bars, 0, Math.min(lo, n)) : 0, dt, ATTACK_MS, RELEASE_MS)
    out.mid   = follow(s.mid,   n > lo ? mean(bars, lo, Math.min(md, n)) : 0, dt, ATTACK_MS, RELEASE_MS)
    out.high  = follow(s.high,  n > md ? mean(bars, md, n) : 0, dt, ATTACK_MS, RELEASE_MS)
    out.kick  = s.kick * Math.exp(-dt / KICK_DECAY_MS)

    // Flux over the kick band: only rises count.
    var k = Math.min(KICK_BARS, n), flux = 0
    if (s.prev && k > 0) {
        for (var i = 0; i < k; i++) flux += Math.max(0, (bars[i] || 0) - (s.prev[i] || 0))
        flux /= k
    }
    var sd = Math.sqrt(Math.max(0, s.fluxSq - s.fluxMean * s.fluxMean))
    if (flux > s.fluxMean + FLUX_K * sd && flux > FLUX_FLOOR && out.sinceKick >= REFRACTORY_MS) {
        out.kick = 1; out.beats = s.beats + 1; out.sinceKick = 0
        out.boom = 1; out.booms = out.booms + 1
        if (flux > s.fluxMean + FLASH_K * sd && out.sinceFlash >= FLASH_GAP_MS) {
            out.flash = 1; out.sinceFlash = 0
            out.impact = 1; out.impacts = out.impacts + 1
        }
    }
    var a = 1 - Math.exp(-dt / FLUX_MS)
    out.fluxMean = s.fluxMean + (flux - s.fluxMean) * a
    out.fluxSq   = s.fluxSq + (flux * flux - s.fluxSq) * a

    // The snare and the hat (rough; see the header).
    var sf = Math.round(n * SNARE_FRAC), hf = Math.max(sf + 1, Math.round(n * HAT_FRAC))
    var sRise = rise(bars, s.prev, sf, Math.min(hf, n)), hRise = rise(bars, s.prev, Math.min(hf, n), n)
    var sn = onset(s.sn, sRise, dt, SNARE_REFRACTORY_MS), ht = onset(s.ht, hRise, dt, HAT_REFRACTORY_MS)
    var isSnare = sn.hit && sRise >= 0.5 * flux && sRise >= 0.8 * hRise
    if (isSnare) { out.snare = 1; out.snares = out.snares + 1 }
    if (ht.hit && !isSnare && hRise >= 1.5 * sRise) out.hat = 1
    out.sn = sn
    out.ht = ht

    out.prev = n > 0 ? bars.slice() : null
    return out
}

// Toward silence when the music stops: everything eases to 0 without new frames.
function rest(s, dt) {
    return step(s, [], dt)
}

// ── The song: what this track is like (2026-10-31) ────────────────────────────
// The user, dropping the presets: "the effects should adapt to the song itself, letting the
// user change intensity if he wants". So MusicPulse keeps a running picture of the track —
// how often each drum is heard, and whether the drums have just dropped out — and
// services/wallfx.js weighs every effect by it. Fed the same pulse the effects read (the
// helper's or the fallback's), a step per line; reset when the track changes.
//
//   rates      hits a second over the last ~8 s (`SONG_RATE_MS`), for kick, snare, hi-hat and
//              bass note — counted from `beats`/`snares`/`booms`, and from the `hat` envelope
//              crossing `HAT_ON` (re-armed under `HAT_OFF`), since nothing counts hats.
//   energy     how driving it is, 0..1: kicks + 0.7 × snares + 0.5 × bass notes a second, over
//              `ENERGY_FULL` (a 128 BPM four-on-the-floor with a backbeat is ~1).
//   breakdown  0..1, the drums (kick + snare) of the last ~1.5 s against the last ~20 s: a
//              track whose drums dropped out (from 80% of usual down; gone by ~27%). 0 for
//              a track that never had drums.
//
// Rates are exponential: each hit adds 1000 / τ, everything decays by e^(−dt/τ), so a steady
// λ hits a second settles at λ. Read through `songView`, which corrects the first seconds of
// a track (the sum hasn't filled yet, so it divides by 1 − e^(−age/τ), Adam's bias fix) —
// without that, every track would start out "calm" for eight seconds.
// The level is NOT used: the helper normalises every band to its own recent peak (4 s), so a
// quiet stretch reads as loud again within seconds; what the drums do is what doesn't adapt.
var SONG_RATE_MS = 8000
var SONG_NOW_MS = 1500
var SONG_LONG_MS = 20000
var HAT_ON = 0.6
var HAT_OFF = 0.3
var ENERGY_FULL = 3.0
// How big this part of the song is (the user, 2026-10-31: "too intense in calmer parts …
// when the drop hits it's quite underwhelming … sometimes the effects should calm down").
// From the helper's `loud` and `sub` (scripts/music-pulse.py: NOT renormalised, against the
// song's loudest), half each; without the helper (`loud` < 0), from the drums now against
// the song's. Followed up fast (`SECTION_RISE_MS`: a drop lands at once) and down slowly
// (`SECTION_FALL_MS`: a calm part arrives, it doesn't flicker in). A DROP is the section
// leaping over where it has been (`SECTION_SLOW_MS`) by `DROP_JUMP`, into a big part
// (`DROP_FLOOR`): `drop` goes to 1 and fades over `DROP_FADE_MS`, at most one per `DROP_GAP_MS`.
var SECTION_RISE_MS = 150
var SECTION_FALL_MS = 1500
var SECTION_SLOW_MS = 6000
var DROP_JUMP = 0.3
var DROP_FLOOR = 0.7
var DROP_FADE_MS = 3000
var DROP_GAP_MS = 8000
var BREAKDOWN_MIN_RATE = 0.6   // drums a second the song must have had for a gap to count
var BREAKDOWN_DEAD = 0.8       // drums at this share of usual are no gap (hits are discrete: the
                               // short rate dips between them)

function songInitial() {
    return { age: 0, kick: 0, snare: 0, hat: 0, boom: 0, drumsNow: 0, drumsLong: 0,
             beats: -1, snares: -1, booms: -1, hats: 0, hatArmed: true,
             section: -1, sectionSlow: -1, drop: 0, sinceDrop: 1e9 }
}

// One step: `p` is the pulse (MusicPulse's fields), `dt` ms since the last step.
function songStep(s, p, dt) {
    var d = Math.max(0, Math.min(dt, 1000))
    var add = function (raw, n, tau) { return raw * Math.exp(-d / tau) + n * 1000 / tau }
    var count = function (now, was) { return was < 0 || now < was ? 0 : now - was }
    var nk = count(p.beats || 0, s.beats), ns = count(p.snares || 0, s.snares), nb = count(p.booms || 0, s.booms)
    var hat = p.hat || 0, nh = 0, armed = s.hatArmed
    if (armed && hat >= HAT_ON) { nh = 1; armed = false }
    else if (!armed && hat <= HAT_OFF) armed = true
    var drumsNow = add(s.drumsNow, nk + ns, SONG_NOW_MS), drumsLong = add(s.drumsLong, nk + ns, SONG_LONG_MS)
    // The section: the helper's loudness and sub weight, or the drums against the song's.
    var raw
    if (typeof p.loud === "number" && p.loud >= 0)
        raw = 0.5 * p.loud + 0.5 * Math.max(0, p.sub || 0)
    else {
        var age = s.age + d
        var now = drumsNow / Math.max(0.05, 1 - Math.exp(-age / SONG_NOW_MS))
        var long = drumsLong / Math.max(0.05, 1 - Math.exp(-age / SONG_LONG_MS))
        raw = long < BREAKDOWN_MIN_RATE ? 0.6 : Math.min(1, 0.25 + 0.75 * now / long)
    }
    var follow = function (y, tau) { return y < 0 ? raw : y + (raw - y) * (1 - Math.exp(-d / tau)) }
    // The rhythm engine's own section, when it sends one, is already followed the same way.
    var helperSection = typeof p.section === "number" && p.section >= 0
    if (helperSection) raw = p.section
    var section = helperSection ? raw : follow(s.section, raw > s.section ? SECTION_RISE_MS : SECTION_FALL_MS)
    var slow = follow(s.sectionSlow, SECTION_SLOW_MS)
    var sinceDrop = s.sinceDrop + d, drop = s.drop * Math.exp(-d / DROP_FADE_MS)
    // Not in the first SECTION_SLOW_MS: there is no "where it has been" yet (a replay of a real
    // track called a drop 2 s in, off the warm-up).
    // The rhythm engine calls drops itself, on the drop's own kick (`drops` counts them); this
    // guess is for the cava fallback.
    var engine = typeof p.drops === "number" && p.drops >= 0
    var nDrops = engine ? count(p.drops, s.drops === undefined ? -1 : s.drops) : 0
    if (nDrops > 0) { drop = 1; sinceDrop = 0 }
    else if (!engine && section - slow >= DROP_JUMP && section >= DROP_FLOOR
             && sinceDrop >= DROP_GAP_MS && s.age > SECTION_SLOW_MS) {
        drop = 1
        sinceDrop = 0
    }
    return {
        age: s.age + d,
        section: section, sectionSlow: slow, drop: drop, sinceDrop: sinceDrop,
        drops: typeof p.drops === "number" && p.drops >= 0 ? p.drops : -1,
        kick: add(s.kick, nk, SONG_RATE_MS),
        snare: add(s.snare, ns, SONG_RATE_MS),
        hat: add(s.hat, nh, SONG_RATE_MS),
        boom: add(s.boom, nb, SONG_RATE_MS),
        drumsNow: drumsNow,
        drumsLong: drumsLong,
        beats: p.beats || 0, snares: p.snares || 0, booms: p.booms || 0,
        hats: s.hats + nh, hatArmed: armed
    }
}

// The song as the effects read it: bias-corrected rates, energy, breakdown, and the hat count
// (the shimmer's seed — a new twinkle per hat).
function songView(s) {
    var st = s || songInitial()
    var fill = function (tau) { return Math.max(0.05, 1 - Math.exp(-st.age / tau)) }
    var r = fill(SONG_RATE_MS)
    var kick = st.kick / r, snare = st.snare / r, hat = st.hat / r, boom = st.boom / r
    var now = st.drumsNow / fill(SONG_NOW_MS), long = st.drumsLong / fill(SONG_LONG_MS)
    var energy = Math.max(0, Math.min(1, (kick + 0.7 * snare + 0.5 * boom) / ENERGY_FULL))
    // The drums gone AND the part gone small: sparse drums under a full orchestra are no
    // breakdown (measured: a cinematic track was called one at full section).
    var sec = st.section < 0 ? 0.6 : st.section
    var breakdown = long < BREAKDOWN_MIN_RATE || st.age < SONG_NOW_MS * 2 ? 0
                  : Math.max(0, Math.min(1, 1.5 * (1 - now / long / BREAKDOWN_DEAD)))
                    * Math.max(0, Math.min(1, 1.5 * (1 - sec)))
    return { kick: kick, snare: snare, hat: hat, boom: boom, energy: energy, breakdown: breakdown,
             section: sec, drop: st.drop || 0,
             hats: st.hats, age: st.age }
}

// A few words for what the effects are adapting to, for the Effects page: "Driving · kick-led".
// "" before there is anything to say (the first two seconds).
function character(v) {
    if (!v || v.age < 2000) return ""
    if (v.drop > 0.5) return "The drop"
    if (v.breakdown > 0.5) return "Breakdown"
    if (v.section < 0.35) return "A calm part"
    var mood = v.energy < 0.25 ? "Calm" : v.energy < 0.6 ? "Groovy" : "Driving"
    // The part that stands out most against what's ordinary for it.
    var parts = [
        { word: "kick-led", x: v.kick / 2.0 },
        { word: "snare-heavy", x: v.snare / 1.5 },
        { word: "busy hats", x: v.hat / 4.0 },
        { word: "bass-heavy", x: v.boom / 1.5 }
    ]
    var top = parts[0]
    for (var i = 1; i < parts.length; i++) if (parts[i].x > top.x) top = parts[i]
    return top.x >= 0.6 ? mood + " · " + top.word : mood
}

// ── The rhythm engine's events, shown when they're HEARD (2026-10-31) ─────────
// scripts/music-pulse.py's rhythm engine prints timestamped lines (its audio clock, seconds):
//   s <t> level bass mid high loud sub section bpm locked barpos      ~94 a second
//   e <t0> <kind> <strength> <heavy> <role>                           one per decided hit
//   latency <ms>                                                       once: speakers vs. tap
// `schedLine` reads one; `schedAt(st, now)` is the music as it sounds at wall time `now` (ms).
// An event is due at t0 + `off` + latency + sync, where `off` maps the audio clock onto the wall
// clock: the SMALLEST (wall − t) over the last OFF_WINDOW lines — PipeWire hands the helper audio
// in quantum-sized bursts (21 ms here), so most lines arrive late by part of one; the earliest
// arrival is the true mapping. The tap is ahead of the speakers by `latency` (PipeWire's buffers,
// measured by the helper), so nothing is shown before it's heard, and the helper's lookahead
// (it judges a hit ~21 ms after it) costs nothing on screen. `sync` is the user's Sync fader.
//
// Envelopes are computed from the events' due times, not stepped: a kick is exp(−age / 170 ms)
// from the frame it's due, so a 144 Hz screen sees its attack on the right frame. Roles carry
// through: a "back" snare is an accent (the ring), a drop or phrase an impact (glitch, strobe),
// and a kick within STRUCT_KICK_MS of one punches harder (`kickBoost`).
var OFF_WINDOW = 128
var STRUCT_KICK_MS = 40
var STRUCT_BOOST = 1.4
var DECAY = { kick: 170, snare: 150, hat: 70, impact: 220, flash: 70 }

function schedInitial() {
    return { offs: [], off: null, latency: 30, events: [], states: [], cur: null,
             beats: 0, snares: 0, accents: 0, hats: 0, impacts: 0, drops: 0,
             kick: null, snare: null, hat: null, impact: null }
}

// One line from the helper (already split on spaces). Mutates and returns `st`.
function schedLine(st, f, wallMs, syncMs) {
    if (f[0] === "latency") { st.latency = +f[1] || 0; return st }
    if (f[0] !== "s" && f[0] !== "e") return st
    var t = +f[1] * 1000
    if (!isFinite(t)) return st
    st.offs.push(wallMs - t)
    if (st.offs.length > OFF_WINDOW) st.offs.shift()
    var off = Infinity
    for (var i = 0; i < st.offs.length; i++) off = Math.min(off, st.offs[i])
    st.off = off
    var due = t + off + st.latency + (syncMs || 0)
    if (f[0] === "s" && f.length >= 12) {
        st.states.push({ due: due, level: +f[2], bass: +f[3], mid: +f[4], high: +f[5], loud: +f[6], sub: +f[7],
                         section: +f[8], bpm: +f[9], locked: f[10] === "1", barpos: +f[11] })
        if (st.states.length > 400) st.states.shift()        // (a stalled consumer mustn't grow it)
    } else if (f[0] === "e" && f.length >= 6) {
        st.events.push({ due: due, kind: f[2], strength: +f[3], heavy: +f[4], role: f[5] })
        if (st.events.length > 400) st.events.shift()
    }
    return st
}

// The pulse at wall time `nowMs`: consumes what has come due. Mutates `st`.
function schedAt(st, nowMs) {
    var keep = []
    for (var i = 0; i < st.events.length; i++) {
        var e = st.events[i]
        if (e.due > nowMs) { keep.push(e); continue }
        if (e.kind === "kick") { st.beats++; st.kick = e }
        else if (e.kind === "snare") { st.snares++; st.snare = e; if (e.role === "back") st.accents++ }
        else if (e.kind === "hat") { st.hats++; st.hat = e }
        else if (e.kind === "drop" || e.kind === "phrase") {
            st.impacts++; st.impact = e
            if (e.kind === "drop") st.drops++
        }
    }
    st.events = keep
    while (st.states.length > 0 && st.states[0].due <= nowMs) st.cur = st.states.shift()
    var c = st.cur || { level: 0, bass: 0, mid: 0, high: 0, loud: -1, sub: -1, section: -1, bpm: 0, locked: false, barpos: -1 }
    var env = function (e, tau, scale) {
        if (!e) return 0
        var age = nowMs - e.due
        return age < 0 ? 0 : (scale === undefined ? 1 : scale) * Math.exp(-age / tau)
    }
    var boost = st.kick && st.impact && Math.abs(st.kick.due - st.impact.due) <= STRUCT_KICK_MS ? STRUCT_BOOST : 1
    return {
        level: c.level, bass: c.bass, mid: c.mid, high: c.high, loud: c.loud, sub: c.sub, section: c.section,
        bpm: c.bpm, locked: c.locked, barpos: c.barpos,
        kick: env(st.kick, DECAY.kick), beats: st.beats, heavy: st.kick ? st.kick.heavy : -1, kickBoost: boost,
        kickRole: st.kick ? st.kick.role : "",
        snare: env(st.snare, DECAY.snare, st.snare && st.snare.role === "back" ? 1 : 0.5), snares: st.snares,
        accents: st.accents,
        hat: env(st.hat, DECAY.hat), hats: st.hats,
        impact: env(st.impact, DECAY.impact), impacts: st.impacts, drops: st.drops,
        // The strobe follows the song's structure too (the user's pick): drops and phrases only.
        flash: env(st.impact, DECAY.flash),
        boom: 0, booms: 0
    }
}

// A new helper process (a restart: new audio clock, empty queues) — but the counts carry on, so
// "a new kick" (a count rising) still means one to everything that watches them.
function schedRestart(st) {
    var n = schedInitial()
    if (st) {
        n.beats = st.beats; n.snares = st.snares; n.accents = st.accents; n.hats = st.hats
        n.impacts = st.impacts; n.drops = st.drops; n.latency = st.latency
    }
    return n
}
