.pragma library

// ── wallfx.js ─────────────────────────────────────────────────────────────────
// The wallpaper's music effects (modules/desktop/WallFx, shaders/wallfx.src.frag;
// 2026-10-31): which sound moves which effect, how the song shapes them, and each effect's
// amount on a frame. Pure, so it can be tested: `bun scripts/test-wallfx.js`.
//
// ── One look per sound (2026-10-31, third pass) ───────────────────────────────
// The user: the effects didn't "portray the element that they should per sound, also the
// shake looks quite odd" — a snare SOFTENED the picture (blur), hi-hats sent out smooth rings
// (ripple), and Shake slid the picture one way and back while zooming on every bass note.
// Picked: each look matches its sound —
//
//   kick          Zoom (punches in, colours split outward) + Pulse (brightens)
//   heavy kick    Rumble: a quick tremble for as long as the kick's bass rings; no zoom.
//                 (Was every bass note; the user: it "doesn't really match with what's
//                 played, it should be playing when big bass kicks come" — so it fires on a
//                 kick whose bass is big for this song, the helper's `heavy`.)
//                 The picture's edge is MIRRORED in the shader, so nothing has to zoom to
//                 hide it (the old shake zoomed by twice its reach on every note)
//   snare / clap  Shockwave: one sharp ring cracks out from the middle — on ACCENTED snares
//                 (the helper's `accents`: the strongest, ~1.2 a second at most; the user: the
//                 ring was "constantly getting spammed" by a funk track's claps and percussion).
//                 Without the helper, a snare at least `SHOCK_GAP_MS` after the last ring
//   hi-hat        Shimmer: the brightest parts twinkle, a new pattern per hat
//   vocals (mids) Bloom
//   loudness      Glow
//   structure     Glitch and Strobe (`impact`/`flash`: the rhythm engine's drops and phrase
//                 starts — always on a beat 1, rare; the user picked song structure over "the
//                 hardest hits", which landed off the beat) — and their kick punches harder.
//                 (The row's id stays "hardest", so a saved trim still applies.)
//   breakdown     Blur: soft while the drums drop out, sharp again on the drop's first kick —
//                 and only while there's music: the end of a song (silence, or the player
//                 stopping) is not a breakdown, so the blur goes with the sound (the user)
//   strong hits   Strobe (`flash`, ≤ 3 a second) — OPT-IN only, never adapted on: flashing
//                 light can trigger seizures (WCAG 2.3.1)
//
// ── No presets: the song decides (same day) ───────────────────────────────────
// The user: "instead of presets, the effects should adapt to the song itself, letting the user
// change intensity". Every sound is on; `adapt(view)` weighs each by the track as
// MusicPulse.songView describes it (musicpulse.js):
//   - a busy part plays smaller: past its ordinary rate (`ORDINARY`, hits a second) a hit
//     counts √(ordinary / rate), floored at `BUSY_FLOOR` — sixteenth hats twinkle, they don't
//     strobe; a rare snare cracks at full size
//   - how big this part of the song is — see "The section" below. (The first cut traded hits
//     against washes by the track's overall energy, so a calm track glowed MORE; replaced.)
// The user's say: the master intensity, and a trim per sound (`Config.wallFxMix`: id →
// 0..2, absent = 1 "auto"; 0 is off). Strobe's absent is 0.
//
// ── The section: calm parts calm, drops big (same day) ────────────────────────
// The user: "too intense in calmer parts of the song and when the drop hits it's quite
// underwhelming … sometimes the effects should calm down … the principal goal is to make it
// match the song's vibe". The helper's envelopes are renormalised every few seconds, so a calm
// verse read as loud as the drop, and calm tracks got MORE glow. Now everything follows
// `view.section` (musicpulse.js: how big this part is against the song, from the helper's
// non-renormalised loudness and sub weight) through `vibe` — a calm part keeps a trace of the
// washes (`*_FLOOR`), the hits almost nothing; a big part is everything — and `view.drop`
// (the section leaping up) boosts the hits by up to `DROP_BOOST` (the washes `DROP_WASH`) for a
// few seconds. A kick's
// punch also scales with how heavy its bass was (`heavy`): a soft verse kick nods, a drop's
// 808 kick slams.
//
// ── Smooth, not stepped (same day) ────────────────────────────────────────────
// The user: "make the overall animations smoother". `amounts` is the TARGET; `glide` follows
// it per effect with its own rise and fall (`GLIDE`, ms): a kick lands in the frame it's heard
// (rise 8 ms — 25 ms read as late: "it still feels out of sync") and falls smoothly, glow and
// bloom breathe instead of flickering with the level, and the
// helper's ~94 lines a second stop showing as steps on a 144 Hz screen. The rumble's sines are
// 7–13 Hz (at 11–23 Hz a 60 Hz screen aliased them into judder) and it, and the shockwave,
// ease in over their first ~30 ms. Glitch and strobe are not glided: a glitch is meant to cut,
// and a strobe smeared out is a longer flash.
//
// Without music-pulse.py (the cava fallback) the snare and hat come from services/
// musicpulse.js's rougher bands, and cava can't tell a bass note from a kick or the hardest
// hit from a strong one: there `boom` is the kick and `impact` the flash.
// ─────────────────────────────────────────────────────────────────────────────

var SOUNDS = [
    { id: "kick",      label: "Kick",          effect: "Zoom & pulse", about: "The picture punches in and brightens on every kick — harder the heavier it is" },
    { id: "bass",      label: "Bass kicks",    effect: "Rumble",       about: "A tremble on the big bass kicks, as long as their bass rings" },
    { id: "snare",     label: "Snare & claps", effect: "Shockwave",    about: "One sharp ring cracks out from the middle" },
    { id: "hats",      label: "Hi-hats",       effect: "Shimmer",      about: "The brightest parts of the picture twinkle" },
    { id: "vocals",    label: "Vocals",        effect: "Bloom",        about: "The highlights bleed light with the vocals and mids" },
    { id: "loudness",  label: "Loudness",      effect: "Glow",         about: "A soft light in the palette's colour, brighter as it gets louder" },
    { id: "hardest",   label: "Drops & phrases", effect: "Glitch",     about: "Slices slip and colours split when the song changes: the drop, and the start of each phrase — always on a beat 1" },
    { id: "breakdown", label: "Breakdowns",    effect: "Blur",         about: "Softens while the drums drop out, sharp again when the drop hits" },
    // Never on unless asked for, and the page warns before it: flashing light can trigger
    // seizures. MusicPulse caps the flashes at three a second (WCAG 2.3.1).
    { id: "strobe",    label: "Song changes",  effect: "Strobe",       about: "A white flash on the drop and each phrase's first beat — rare, and never more than three a second", warning: true, optIn: true }
]

// Hits a second that are ordinary for each part — above it, each hit plays smaller.
var ORDINARY = { kick: 2.2, bass: 2.2, snare: 1.2, hats: 2.5 }
// The section's say (see "The section"): `vibe` is 0 in a calm part and 1 in a big one
// (smoothstep over SECTION_CALM..SECTION_BIG); each class keeps its floor in a calm part.
var SECTION_CALM = 0.3
var SECTION_BIG = 0.85
var HIT_FLOOR = 0.08
var HAT_FLOOR = 0.15
var WASH_FLOOR = 0.3
var DROP_BOOST = 0.8         // the hits, right after a drop…
var DROP_WASH = 0.3          // …and the washes, a little
// A kick's bass that makes it a "big bass kick" — the rumble's (`heavy`, smoothstep over
// these; measured: 0.8–1.0 for a track's big part, 0–0.25 in its calm one).
var HEAVY_FROM = 0.65
var HEAVY_FULL = 1.0
var BUSY_FLOOR = 0.35
var TRIM_MAX = 2

// The rumble: how long a bass note's tremble lasts. It holds (`RUMBLE_HOLD_MS`) while the bass
// stays at 60% of where it was when the note started, and dies fast (`RUMBLE_DROP_MS`) once it
// falls — or once it has held `RUMBLE_MAX_MS`, so a drone doesn't rattle forever.
var RUMBLE_HOLD_MS = 450
var RUMBLE_DROP_MS = 90
var RUMBLE_MAX_MS = 1200
var RUMBLE_REACH = 0.006       // uv at full strength: ~11 px across a 1920 px screen
var RUMBLE_EASE_MS = 30        // its first moment, eased in
// The shockwave: its ring travels `SHOCK_SPEED` screen heights a second, fading over
// `SHOCK_FADE_MS`; gone after `SHOCK_LIFE_MS`.
var SHOCK_SPEED = 2.2
var SHOCK_FADE_MS = 250
var SHOCK_LIFE_MS = 700
var SHOCK_EASE_MS = 30
var SHOCK_GAP_MS = 400
// Breakdown blur needs music under it: the level (each band normalised to its own recent peak,
// so a quiet breakdown still reads ~0.3+) at `PRESENT_LEVEL` or more counts in full.
var PRESENT_LEVEL = 0.15

// [rise, fall] in ms for each amount `glide` follows.
var GLIDE = {
    zoom: [8, 140], punch: [8, 140], pulse: [10, 160],   // a kick lands in the frame it's heard
    glow: [120, 450], bloom: [120, 450], shimmer: [15, 110],
    blur: [600, 160]      // in slowly with the breakdown; out quickly on the drop
}

function clamp01(x) { return Math.max(0, Math.min(1, x)) }

// The user's trim for a sound: absent = auto (1), or off for an opt-in one.
function trimOf(mix, id) {
    var v = (mix || {})[id]
    if (typeof v === "number") return Math.max(0, Math.min(TRIM_MAX, v))
    var s = SOUNDS.find(function (x) { return x.id === id })
    return s && s.optIn ? 0 : 1
}

// Whether anything can move at all.
function anyOn(mix) {
    return SOUNDS.some(function (s) { return trimOf(mix, s.id) > 0 })
}

function smoothstep(a, b, x) {
    var t = clamp01((x - a) / (b - a))
    return t * t * (3 - 2 * t)
}

// 0 in a calm part, 1 in a big one.
function vibe(view) {
    var sec = view && typeof view.section === "number" ? view.section : 0.6
    return smoothstep(SECTION_CALM, SECTION_BIG, sec)
}

function busy(rate, ordinary) {
    return rate <= ordinary ? 1 : Math.max(BUSY_FLOOR, Math.sqrt(ordinary / rate))
}

// How much of each sound's effect this moment of the song gets: 0..1, ×(1 + DROP_BOOST) for the
// hits right after a drop, ×(1 + DROP_WASH) for the washes (before the user's trim and intensity).
function adapt(view) {
    var v = view || {}
    var vb = vibe(v), boost = 1 + DROP_BOOST * clamp01(v.drop || 0)
    var hits = (HIT_FLOOR + (1 - HIT_FLOOR) * vb) * boost
    var washes = (WASH_FLOOR + (1 - WASH_FLOOR) * vb) * (1 + DROP_WASH * clamp01(v.drop || 0))
    return {
        kick:      hits * busy(v.kick || 0, ORDINARY.kick),
        bass:      hits * busy(v.kick || 0, ORDINARY.bass),
        snare:     hits * busy(v.snare || 0, ORDINARY.snare),
        hats:      (HAT_FLOOR + (1 - HAT_FLOOR) * vb) * busy(v.hat || 0, ORDINARY.hats),
        vocals:    washes,
        loudness:  washes,
        hardest:   hits,
        breakdown: 1,
        strobe:    vb
    }
}

// ── Motion: what each screen remembers between frames ─────────────────────────
// The rumble's gate (opened by a new kick), the shockwave's age (restarted by a new
// snare) and the clock the tremble runs on. Counts start at -1: the first frame only learns
// them, so turning the effects on mid-song doesn't fire a stale hit.
function motionInitial() {
    return { t: 0, beats: -1, snares: -1, accents: -1, gate: 0, ref: 0, held: 0, shockAge: 1e9 }
}

function step(m, p, dt) {
    var d = Math.max(0, Math.min(dt, 250))
    var bass = clamp01(p.bass || 0)
    var gate = m.gate, ref = m.ref, held = m.held + d
    if (m.beats >= 0 && (p.beats || 0) > m.beats) { gate = 1; ref = Math.max(0.2, bass); held = 0 }
    var holding = bass >= 0.6 * ref && held < RUMBLE_MAX_MS
    gate *= Math.exp(-d / (holding ? RUMBLE_HOLD_MS : RUMBLE_DROP_MS))
    var accented = typeof p.accents === "number" && p.accents >= 0
    var ring = accented ? m.accents >= 0 && p.accents > m.accents
                        : m.snares >= 0 && (p.snares || 0) > m.snares && m.shockAge >= SHOCK_GAP_MS
    var shockAge = ring ? 0 : m.shockAge + d
    return { t: (m.t + d / 1000) % 600, beats: p.beats || 0, snares: p.snares || 0,
             accents: accented ? p.accents : -1,
             gate: gate < 0.001 ? 0 : gate, ref: ref, held: held, shockAge: shockAge }
}

var NONE = { zoom: 0, punch: 0, shakeX: 0, shakeY: 0, shock: 0, shockR: 0, shimmer: 0, glitch: 0,
             blur: 0, glow: 0, bloom: 0, pulse: 0, strobe: 0 }

// The shader's uniforms for one frame.
//   mix        Config.wallFxMix      intensity  Config.wallFxIntensity, 0..1
//   p          MusicPulse's fields   view       MusicPulse.songView
//   m          this screen's motion (`step`)   aspect     width / height
function amounts(mix, intensity, p, view, m, aspect) {
    if (!p || !m) return NONE
    var k = clamp01(intensity), w = adapt(view)
    var g = function (id) { return trimOf(mix, id) * k * w[id] }
    var kick = clamp01(p.kick || 0), level = clamp01(p.level || 0), mid = clamp01(p.mid || 0)
    var bass = clamp01(p.bass || 0), hat = clamp01(p.hat || 0), impact = clamp01(p.impact || 0)

    // How heavy the last kick's bass was; without the helper (no `heavy`), the bass envelope.
    var heavy = typeof p.heavy === "number" && p.heavy >= 0 ? clamp01(p.heavy) : bass
    // The punch: the kick's own envelope, sharpened, so it's in at once and gone fast — as big
    // as the kick is heavy.
    // A drop's or a phrase's own kick (`kickBoost`, the rhythm engine's structure) hits harder:
    // the biggest punches follow the song's structure (the user's pick).
    var boost = typeof p.kickBoost === "number" ? p.kickBoost : 1
    var punch = clamp01(g("kick") * 0.8 * Math.pow(kick, 1.3) * (0.35 + 0.65 * heavy) * boost)

    // The tremble: two pairs of sines at unrelated rates (7–13 Hz — any faster aliases on a
    // 60 Hz screen), so it never repeats a shape — a rattle, not a sway — at the gate's
    // strength and the bass's, eased in over its first moment.
    var ease = 1 - Math.exp(-m.held / RUMBLE_EASE_MS)
    var amp = clamp01(g("bass") * smoothstep(HEAVY_FROM, HEAVY_FULL, heavy)) * m.gate * ease
            * clamp01(bass + 0.3) * RUMBLE_REACH
    var t = m.t * Math.PI * 2
    var sx = (Math.sin(t * 9) + 0.6 * Math.sin(t * 13 + 1.7)) / 1.6
    var sy = (Math.sin(t * 7 + 0.9) + 0.6 * Math.sin(t * 11 + 2.3)) / 1.6

    var live = m.shockAge < SHOCK_LIFE_MS
    var shock = live ? clamp01(g("snare") * Math.exp(-m.shockAge / SHOCK_FADE_MS)
                               * (1 - Math.exp(-m.shockAge / SHOCK_EASE_MS))) : 0
    // Breakdown: only with music under it, and never on a kick (the drop snaps it sharp).
    var present = clamp01(level / PRESENT_LEVEL)
    var breakdown = clamp01((view && view.breakdown) || 0) * present * (kick > 0.3 ? 0 : 1)

    return {
        zoom:    0.14 * punch,
        punch:   punch,
        shakeX:  amp * sx / Math.max(0.1, aspect || 1),
        shakeY:  amp * sy,
        shock:   shock,
        shockR:  live ? SHOCK_SPEED * m.shockAge / 1000 : 0,
        shimmer: clamp01(g("hats") * 0.9 * hat),
        glitch:  impact > 0.05 ? clamp01(g("hardest") * 0.6 * Math.pow(impact, 1.5)) : 0,
        blur:    clamp01(g("breakdown") * 0.4 * breakdown),
        glow:    clamp01(g("loudness") * 0.84 * level),
        bloom:   clamp01(g("vocals") * 0.6 * mid),
        pulse:   clamp01(g("kick") * 0.5 * kick),
        strobe:  clamp01(g("strobe") * (p.flash || 0))
    }
}

// One frame of gliding: `prev` (last frame's glided amounts, or null) toward `raw` (this
// frame's `amounts`), `dt` ms. Amounts not in GLIDE pass straight through.
function glide(prev, raw, dt) {
    if (!prev) return raw
    var d = Math.max(0, dt), out = {}
    for (var k in raw) {
        var g = GLIDE[k], was = prev[k]
        if (!g || typeof was !== "number") { out[k] = raw[k]; continue }
        var v = was + (raw[k] - was) * (1 - Math.exp(-d / (raw[k] > was ? g[0] : g[1])))
        out[k] = raw[k] === 0 && v < 0.0005 ? 0 : v
    }
    return out
}

// Is anything still moving? (The layer stays up while an effect winds down.)
function any(a) {
    return a.zoom > 0.0005 || a.punch > 0.002 || Math.abs(a.shakeX) + Math.abs(a.shakeY) > 0.00005
        || a.shock > 0.002 || a.shimmer > 0.002 || a.glitch > 0.002 || a.blur > 0.002
        || a.glow > 0.002 || a.bloom > 0.002 || a.pulse > 0.002 || a.strobe > 0.002
}
