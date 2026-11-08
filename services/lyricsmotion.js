.pragma library

// ── lyricsmotion.js ───────────────────────────────────────────────────────────
// How a lyric MOVES, derived from how it was sung.
//
// Everything here is a pure function of data the shell already has: NetEase's yrc gives a
// start AND a duration per word, and the line list gives the silences between phrases.
// Nothing samples audio, nothing guesses at mood — a word held for 1.3 seconds is held
// for 1.3 seconds, and that is the whole signal.
//
// ── Why it is a .js and not expressions in the card ───────────────────────────
// Same reason services/calc.js and services/palette.js are: this is an algorithm with
// edge cases (missing durations, line-only providers, negative gaps from overlapping
// timings), and an algorithm buried in a QML binding cannot be tested. Run the cases with
//     bun scripts/test-lyricsmotion.js
//
// ── The two things that drive everything ──────────────────────────────────────
//   sustain  — how HELD a word is. A clipped consonant and a held vowel should not get
//              the same animation; that difference is most of what makes a lyric read as
//              sung rather than displayed.
//   gap      — the silence before a line. Four seconds of it is an instrumental, and a
//              card that sits perfectly static through a solo looks broken rather than
//              finished.
// ─────────────────────────────────────────────────────────────────────────────

function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v) }
function lerp(a, b, t)    { return a + (b - a) * clamp(t, 0, 1) }

// ── Sustain ───────────────────────────────────────────────────────────────────
// Below SHORT a word is percussive; above LONG it is a held note and more sustain stops
// meaning anything. Between them it ramps.
var SHORT_S = 0.12
var LONG_S  = 0.90

// A word with NO duration (line-only providers, or the interpolated fallback the card
// builds for LRCLIB) gets a mid value rather than 0 — treating unknown as "clipped" made
// every LRCLIB song animate like rapid-fire staccato, which is a confident lie about data
// we do not have.
var UNKNOWN_SUSTAIN = 0.4

function sustain(d) {
    if (typeof d !== "number" || !isFinite(d) || d <= 0) return UNKNOWN_SUSTAIN
    return clamp((d - SHORT_S) / (LONG_S - SHORT_S), 0, 1)
}

// ── Per-word motion ───────────────────────────────────────────────────────────
// `intensity` is the user's Bold↔Subtle scalar, 0..1. It scales the AMPLITUDES but never
// the timings: a subtle setting should be quieter, not slower, or the motion stops
// matching the vocal it is supposed to be tracking.
function wordMotion(d, intensity) {
    var s = sustain(d)
    var k = clamp(typeof intensity === "number" ? intensity : 1, 0, 1)

    // Real duration in ms where we have one; the sustain-implied duration where we do not,
    // so attack/release stay sane for line-only providers.
    var ms = (typeof d === "number" && isFinite(d) && d > 0)
           ? d * 1000
           : lerp(SHORT_S, LONG_S, UNKNOWN_SUSTAIN) * 1000

    return {
        sustain: s,

        // Travel and scale grow with how held the word is — but small. The wave is a
        // shimmer UNDER the travelling light now, not the effect itself; it was carrying
        // the whole animation before the sweep existed, and at those amplitudes the two
        // together read as wobble rather than as a voice.
        rise: lerp(0.5, 1.7, s) * lerp(0.45, 1.0, k),
        pop:  lerp(0.01, 0.035, s) * lerp(0.45, 1.0, k),

        // A short word must be fully lit almost immediately or it is over before the
        // animation arrives. A held one can afford to swell.
        attack:  Math.round(clamp(ms * 0.30, 60, 380)),
        release: Math.round(clamp(ms * 0.55, 160, 700)),

        // Per-word gain on the card's shared wave, so a held note rides higher on the
        // same travelling phase rather than needing an animator of its own.
        waveGain: lerp(0.55, 1.35, s)
    }
}

// ── Syllables ─────────────────────────────────────────────────────────────────
// No provider gives syllable timing. yrc is per WORD, and Musixmatch's richsync is too —
// so this is a heuristic split, and the timing inside a word is interpolated across the
// pieces rather than measured.
//
// That is honest for what it drives. A travelling light needs somewhere to travel THROUGH;
// a word lit as one block has no interior for the sweep to cross. Being a syllable out on
// "beautiful" costs nothing visible, because the eye is tracking a moving highlight, not
// auditing where the linguists would have put the boundary.
//
// ── The invariant that matters ────────────────────────────────────────────────
// The pieces must concatenate back to the input EXACTLY — same characters, same order,
// including spaces and punctuation. Anything else silently edits the lyric on screen,
// which is far worse than a wrong split. It is the first thing the tests check.
var VOWELS = "aeiouyAEIOUY"

function isVowel(ch) { return VOWELS.indexOf(ch) >= 0 }
function isAlpha(ch) { return /[a-zA-Z]/.test(ch) }

function syllables(text) {
    if (typeof text !== "string" || text.length === 0) return []

    // Vowel GROUPS, not vowels: "ea" in "beat" is one nucleus, not two.
    var groups = []
    var i = 0
    while (i < text.length) {
        if (isVowel(text[i])) {
            var s = i
            while (i < text.length && isVowel(text[i])) i++
            groups.push({ start: s, end: i })
        } else i++
    }

    // No vowel, or one — nothing to split. Covers "rhythm", "sky", and any run of
    // punctuation, all of which must come back unchanged rather than as [].
    if (groups.length <= 1) return [text]

    // A trailing silent "e" is not its own syllable ("time", not "tim-e"). The exception
    // is consonant + "le", which genuinely is one ("ta-ble") — so only merge when the
    // letter before the final e is NOT an l.
    var last = groups[groups.length - 1]
    if (last.end === text.length && last.end - last.start === 1
        && text[last.start] === "e" && last.start > 0
        && text[last.start - 1] !== "l" && isAlpha(text[last.start - 1])) {
        groups.pop()
        if (groups.length <= 1) return [text]
    }

    // Cut between each pair of nuclei.
    //   0 consonants  V|V     — "po-em"
    //   1 consonant   V|CV    — the consonant leads the next syllable, "o-pen"
    //   2+ consonants VC|CV   — the run splits after its first, "cor-ner"
    var cuts = []
    for (var g = 0; g < groups.length - 1; g++) {
        var run = groups[g + 1].start - groups[g].end
        var cut = run === 0 ? groups[g + 1].start
                : run === 1 ? groups[g + 1].start - 1
                            : groups[g].end + 1
        // Never cut at 0 or at the very end: a leading or trailing empty piece is a unit
        // with no glyphs, which the view would animate as an invisible beat.
        if (cut > 0 && cut < text.length) cuts.push(cut)
    }

    if (cuts.length === 0) return [text]

    var out = []
    var prev = 0
    for (var c = 0; c < cuts.length; c++) {
        if (cuts[c] <= prev) continue      // guard against non-monotonic cuts
        out.push(text.substring(prev, cuts[c]))
        prev = cuts[c]
    }
    out.push(text.substring(prev))
    return out.filter(function (p) { return p.length > 0 })
}

// ── Provider words → the card's units ─────────────────────────────────────────
// Where a break goes is the SOURCE's call, written into the text: yrc carries the trailing
// space on the word ("Feels "), and the Spicy Lyrics mapper puts one on the last syllable
// of each word and none on the ones inside it ("ex" "am" "ple "). Units are laid out with
// zero spacing, so that text is the whole answer — adding a space to "every unit that
// lacks one" is what tore "forever" into "for ev er".
//
// A whitespace-only unit is dropped as a unit, but its whitespace is kept: it was the
// separator between two words, and losing it ran them together.
function lineUnits(words) {
    var out = []
    for (var i = 0; i < (words ? words.length : 0); i++) {
        var w = words[i]
        var text = (w && typeof w.text === "string") ? w.text : ""
        if (text.trim() === "") {
            if (out.length > 0 && text !== "" && !/\s$/.test(out[out.length - 1].text))
                out[out.length - 1].text += text
            continue
        }
        out.push({ text: text, at: w.t, d: w.d })
    }
    return out
}

// Expand a word list into SYLLABLE units, interpolating each word's span across its
// pieces by character count. The result has the same shape a word has — {text, at, d} —
// so the view renders units without caring which it was handed.
function syllabify(words) {
    var out = []
    if (!words || words.length === 0) return out

    for (var i = 0; i < words.length; i++) {
        var w = words[i]
        var parts = syllables(w.text || "")

        if (parts.length <= 1) {
            out.push({ text: w.text, at: w.at, d: w.d, first: true, last: true })
            continue
        }

        var total = 0
        for (var p = 0; p < parts.length; p++) total += parts[p].length

        // A word with no duration cannot have one invented for its pieces; they inherit
        // the unknown and lyricsmotion's UNKNOWN_SUSTAIN handles it.
        var span = (typeof w.d === "number" && isFinite(w.d) && w.d > 0) ? w.d : 0

        var seen = 0
        for (var q = 0; q < parts.length; q++) {
            var frac = total > 0 ? parts[q].length / total : 1 / parts.length
            out.push({
                text:  parts[q],
                at:    w.at + (span > 0 ? (seen / total) * span : 0),
                d:     span > 0 ? span * frac : 0,
                first: q === 0,
                last:  q === parts.length - 1
            })
            seen += parts[q].length
        }
    }
    return out
}

// ── Word grouping ─────────────────────────────────────────────────────────────
// Syllables, grouped back into the words they came from.
//
// The card lays a line out as a wrapping flow so the type size can stay fixed, and a wrap
// must never fall INSIDE a word. So the flow's items have to be words, each containing its
// own syllables, rather than a flat run of syllables.
//
// The boundary is the trailing space, which is how both sources already encode it: yrc
// carries it in the word text, and the Spicy Lyrics mapper appends one wherever
// IsPartOfWord is absent. That means this works for either without knowing which it has.
// ── Scripts that do not use spaces ────────────────────────────────────────────
// Japanese, Chinese and Korean write without spaces and break between characters. A unit
// in one of those scripts is therefore its own break opportunity, whatever the rest of
// the line is doing.
//
// Tested PER UNIT, not per line, and that distinction is the bug it fixes: a line mixing
// Japanese with an English phrase does contain spaces, so a whole-line test concluded
// "this line uses spacing" and swept the entire Japanese run into one unbreakable token.
// It then ran straight off the right edge, because a group is precisely what the card's
// flow will not break inside.
var CJK = /[　-ヿ㐀-䶿一-鿿가-힯豈-﫿＀-￯]/

function isCjk(text) {
    return CJK.test(text || "")
}

function groupWords(units) {
    var out = []
    if (!units || units.length === 0) return out

    var cur = []
    for (var i = 0; i < units.length; i++) {
        var t = units[i].text || ""

        // A CJK unit stands alone. Anything already accumulated closes first, so the
        // Latin word before it is not swallowed into the same group.
        if (isCjk(t)) {
            if (cur.length > 0) { out.push(cur); cur = [] }
            out.push([units[i]])
            continue
        }

        cur.push(units[i])

        // A unit ending in whitespace closes the word. The last unit closes it regardless,
        // since a line's final word carries no trailing space.
        if (/\s$/.test(t) || i === units.length - 1) {
            out.push(cur)
            cur = []
        }
    }
    if (cur.length > 0) out.push(cur)
    return out
}

// ── Structure ─────────────────────────────────────────────────────────────────
var BREAK_S = 4.0     // instrumental / solo
var PAUSE_S = 1.8     // a breath between phrases

// How long the three-dot countdown represents. Three dots, three seconds each — long
// enough to read as counted beats, short enough that the row is doing something for the
// whole time it is on screen.
var COUNTDOWN_S = 9.0

// Where a line stops being SUNG — which is not the same as where the next one starts.
//
// yrc carries a real duration. LRCLIB does not, and the obvious fallback ("a line lasts
// until the next line begins") is a trap: it makes every gap exactly zero by
// construction, so no line-only song could ever contain a detectable break. Every
// instrumental in every LRCLIB track was classified as "flow" and the card sat still
// through all of them. The test caught it; nothing in the UI would have.
//
// So estimate instead, and cap at the next line's start. Reading speed is a guess, but a
// guess that can be wrong is worth more here than a definition that is always wrong.
var NOMINAL_LINE_S = 3.0
var SEC_PER_CHAR   = 0.09

function lineEnd(line, next) {
    if (!line) return 0
    if (typeof line.dur === "number" && line.dur > 0) return line.t + line.dur

    var cap = next ? next.t : line.t + NOMINAL_LINE_S

    var txt = line.text || ""
    if (!txt && line.words && line.words.length)
        txt = line.words.map(function (w) { return w.text || "" }).join("")

    var est = txt ? clamp(txt.length * SEC_PER_CHAR, 0.8, 5.0) : NOMINAL_LINE_S
    return Math.min(line.t + est, cap)
}

// Per-line structural description.
//
//   kind      "open"  — the first line; the run-in from silence at the start of a track
//             "break" — preceded by an instrumental
//             "pause" — preceded by a breath
//             "flow"  — continuous with the line before it
//   entrance  0..1, how much entrance emphasis the line has earned
function structure(lines) {
    var out = []
    if (!lines || lines.length === 0) return out

    for (var i = 0; i < lines.length; i++) {
        var prev = i > 0 ? lines[i - 1] : null
        var gap  = prev ? (lines[i].t - lineEnd(prev, lines[i])) : lines[i].t

        // An interlude row (withInterludes) fills its gap exactly, which would read as no gap
        // at all to the line after it — the line that follows one is the one that earned the
        // entrance. The row itself is not a sung line and has none to earn.
        if (lines[i].interlude) {
            out.push({ gapBefore: 0, kind: "interlude", entrance: 0 })
            continue
        }
        if (prev && prev.interlude) gap = prev.dur

        // Overlapping or out-of-order timings do occur in real yrc data. Clamp rather
        // than propagate a negative, which would otherwise read as a huge entrance.
        gap = Math.max(0, gap)

        var kind = i === 0 ? "open"
                 : gap >= BREAK_S ? "break"
                 : gap >= PAUSE_S ? "pause"
                 : "flow"

        out.push({
            gapBefore: gap,
            kind: kind,
            entrance: kind === "flow" ? 0
                    : clamp((gap - PAUSE_S) / (BREAK_S - PAUSE_S), 0, 1) * 0.7
                      + (kind === "open" ? 0.3 : (kind === "break" ? 0.3 : 0))
        })
    }
    return out
}

// ── A line's words in another script, on the voice's own timing ───────────────
// Romanization REPLACES the lyric (the card shows "konnichiwa" where "こんにちは" was), but it
// has no timing of its own: it is one string for a whole line. The original's syllables DO —
// so each romanized word is placed by the share of the line it takes up (by letters), and that
// share is looked up on the original's timeline: the point 40% of the way through the original
// letters is wherever the voice was 40% of the way through them. A line sung fast then slow
// lights its romaji fast then slow, which spreading the line's span evenly (what the translation
// does, having nothing better) would flatten.
//
//   text    the romanized line
//   units   the original's units, [{ text, at, d }] — as unitsFor() builds them
//   → [{ text (word + the space after it), at, d }], or [] when either is empty
function retimeWords(text, units) {
    var words = String(text || "").split(/\s+/).filter(function (w) { return w !== "" })
    if (words.length === 0 || !units || units.length === 0) return []

    // The original's timeline: each unit covers its own letters, from `at` to `at + d`.
    var segs = []
    var total = 0
    for (var i = 0; i < units.length; i++) {
        var n = String(units[i].text || "").replace(/\s+/g, "").length
        if (n === 0) continue
        segs.push({ from: total, to: total + n, at: units[i].at || 0, d: units[i].d > 0 ? units[i].d : 0 })
        total += n
    }
    if (total === 0) return []

    function timeAt(fraction) {
        var target = clamp(fraction, 0, 1) * total
        for (var k = 0; k < segs.length; k++) {
            if (target <= segs[k].to || k === segs.length - 1) {
                var s = segs[k]
                return s.at + clamp((target - s.from) / (s.to - s.from), 0, 1) * s.d
            }
        }
        return segs[segs.length - 1].at
    }

    var letters = 0
    for (var w = 0; w < words.length; w++) letters += words[w].length

    var out = []
    var seen = 0
    for (var j = 0; j < words.length; j++) {
        var start = timeAt(seen / letters)
        var end   = timeAt((seen + words[j].length) / letters)
        out.push({ text: words[j] + (j < words.length - 1 ? " " : ""),
                   at: start, d: Math.max(0.05, end - start) })
        seen += words[j].length
    }
    return out
}

// ── Interludes as rows ────────────────────────────────────────────────────────
// A gap of BREAK_S or more between two lines (or before the first) becomes a row of its own,
// { t, dur, text: "", words: null, interlude: true }, which the card draws as three dots.
// A row, because the dots are part of the song: the view scrolls to them, they take the place
// the next line would, and the next line follows — instead of a line scrolling to the next one
// across a long silence with a widget laid over it.
//
// Not inserted where a row already stands in the gap: a provider's own blank line (LRC and
// yrc both carry them) is taken over instead — if it is long enough it becomes the interlude,
// keeping its own timing. Returns a NEW list; the input belongs to the service and is shared
// (it is re-applied on an upgrade), so nothing in it is touched.
function _blank(line) {
    return !line.text && !(line.words && line.words.length)
}

function withInterludes(lines) {
    var out = []
    if (!lines) return out

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i]
        var prev = out.length ? out[out.length - 1] : null

        if (_blank(line)) {
            // A blank row that spans a long silence is the interlude.
            var span = (typeof line.dur === "number" && line.dur > 0)
                     ? line.dur
                     : (i + 1 < lines.length ? lines[i + 1].t - line.t : 0)
            if (span >= BREAK_S && !line.interlude) {
                out.push({ t: line.t, dur: span, text: "", words: null, interlude: true,
                           aligned: "left" })
                continue
            }
            out.push(line)
            continue
        }

        // A real line: is there a long silence in front of it with nothing standing in it?
        if (!(prev && (prev.interlude || _blank(prev)))) {
            var start = prev ? lineEnd(prev, line) : 0
            var silence = line.t - start
            if (silence >= BREAK_S)
                out.push({ t: start, dur: silence, text: "", words: null, interlude: true,
                           aligned: "left" })
        }
        out.push(line)
    }
    return out
}

// How far through an interlude row the clock is, and what is left of it.
//   { progress 0..1, remaining seconds }
function interludeAt(line, clock) {
    var dur = (line && line.dur > 0) ? line.dur : 0
    if (dur <= 0) return { progress: 1, remaining: 0 }
    return { progress: clamp((clock - line.t) / dur, 0, 1),
             remaining: Math.max(0, line.t + dur - clock) }
}

// ── Interlude ─────────────────────────────────────────────────────────────────
// (the card no longer reads this — the interlude is a row now, see above — but it is kept and
// tested, and still answers "in a gap?" for a list that has none inserted)
// Are we in a gap right now, and how far through it? Lets the card breathe during a solo
// instead of holding the last sung line perfectly still, and gives a progress value for
// an approach indicator.
//
//   { active, progress 0..1, remaining, kind }
function interlude(lines, struct, clock) {
    var idle = { active: false, progress: 0, remaining: 0, kind: "flow" }
    if (!lines || lines.length === 0 || !struct) return idle

    // The first line whose start is still ahead of us.
    var next = -1
    for (var i = 0; i < lines.length; i++) {
        if (lines[i].t > clock) { next = i; break }
    }
    if (next <= 0) return idle          // before the first line, or past the last

    var prevEnd = lineEnd(lines[next - 1], lines[next])
    if (clock < prevEnd) return idle    // still inside the previous line

    var s = struct[next]
    if (!s || s.kind !== "break") return idle

    var span = lines[next].t - prevEnd
    if (span <= 0) return idle

    var remaining = Math.max(0, lines[next].t - clock)

    return {
        active: true,
        progress: clamp((clock - prevEnd) / span, 0, 1),
        remaining: remaining,

        // ── A countdown, not a progress bar ───────────────────────────────────
        // `progress` runs across the WHOLE gap, which is the wrong clock to show. A thirty
        // second intro gave each dot ten seconds of imperceptible creep, and a five second
        // one had them racing — the same indicator meaning something different every time.
        //
        // `countdown` is anchored to the END instead: it always represents the final
        // COUNTDOWN_S before the vocal returns, so three dots are three fixed beats being
        // counted in, whatever the gap's length. Short gaps simply start part-filled,
        // which is honest — there genuinely is less time left.
        countdown: clamp(1 - remaining / Math.min(span, COUNTDOWN_S), 0, 1),

        kind: s.kind
    }
}
