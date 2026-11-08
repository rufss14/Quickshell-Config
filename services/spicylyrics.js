.pragma library
.import "objpack.js" as ObjPack

// ── spicylyrics.js ────────────────────────────────────────────────────────────
// Maps the Spicy Lyrics API payload onto the shape services/Lyrics.qml already speaks.
//
// ── Their format ──────────────────────────────────────────────────────────────
//   { Type: "Syllable" | "Line" | "Static",
//     StartTime: <seconds>,
//     Content: [ { Lead:       { StartTime, EndTime, Syllables: [ … ] },
//                  Background: [ { StartTime, EndTime, Syllables: [ … ] } ],
//                  OppositeAligned: bool } ] }
//
//   Syllable = { Text, StartTime, EndTime, IsPartOfWord?, TransliteratedText? }
//
// Times are SECONDS. Their own ConvertTime() multiplies by 1000 on the way to the DOM,
// which is what pins it down — and it happens to be the unit Lyrics.lines already uses,
// so nothing here converts.
//
// ── Why this is worth having ──────────────────────────────────────────────────
// `IsPartOfWord` means the timings are genuinely per SYLLABLE, measured rather than
// guessed. lyricsmotion.js splits words heuristically and interpolates the timing inside
// them because no other provider offers better; this one does. Where this payload is
// available the heuristic must be SKIPPED, not applied on top — re-splitting "beau" into
// pieces would be inventing detail on data that already has it.
//
// ── What is dropped, deliberately ─────────────────────────────────────────────
// Background vocals and OppositeAligned (duet) staging are real fields and are ignored
// here. The card is a single left-aligned column; a second voice would need a layout that
// does not exist yet, and silently interleaving background syllables into the lead line
// would corrupt the timing of the line you are actually reading.
// ─────────────────────────────────────────────────────────────────────────────

// ── Who actually wrote these ──────────────────────────────────────────────────
// Their payload carries a `source`, and it is not all one provider: a lot of what the API
// serves is community-uploaded rather than licensed, which is the whole reason its
// coverage beats the commercial sources. Worth surfacing rather than flattening to "Spicy
// Lyrics" — "Provided by" is a real credit, and a community transcription is exactly the
// kind of thing a user might want to know is not official.
var PROVIDERS = {
    "spt": "Spotify",
    "aml": "Apple Music",
    "spl": "Spicy Lyrics",
    "ldb": "Local DB"
}

// `spl` is their own database — the community-uploaded one.
var COMMUNITY = "spl"

function providerName(source) {
    return PROVIDERS[source] || "Unknown"
}

function _num(v) {
    var n = Number(v)
    return isFinite(n) ? n : 0
}

// ── Spicy Lyrics staples an invisible character to every word break ──────────
// Measured on a live payload: a line's `Text` reads `"Cry ​for ​me"` — a real
// space plus a ZERO WIDTH SPACE (U+200B) glued to the front of the next word. ​ is
// explicitly NOT in ECMAScript's `\s` class (unlike ﻿, which is), so it silently
// survived every `\s`-based check below: `_breaksFromText()`'s reconciliation compared a
// syllable join against a plain-text line one character short and declared a mismatch,
// which defeated the AUTHORITATIVE spacing path in favour of the flag heuristic even when
// the payload carried the real answer. Cleaned once, at the point each Text value is
// read, rather than chased through every regex that touches it afterward.
function _clean(s) {
    return typeof s === "string" ? s.replace(/​/g, "") : s
}

// One line's worth of syllables → the shell's word list.
//
// A syllable with IsPartOfWord joins the NEXT one without a gap; the last syllable of a
// word carries the trailing space, matching what yrc does and what the view's zero
// spacing requires.
// How each line decided its spacing, counted over the payload currently being mapped.
// Reset by toLines() and read back off its result — a module-level counter rather than a
// return value because _units() is called from three places and threading it through all
// of them would be more machinery than the number is worth.
var _spacingTally = null

function _resetSpacingTally() {
    _spacingTally = {
        // Which convention each LINE resolved to.
        plainText: 0, text: 0, continuations: 0, endsOnly: 0, allEnds: 0, none: 0,

        // Field names on the LINE and Lead objects. This is the half that was missing:
        // the syllable dump proved the flag was fully populated and still wrong, and the
        // only way to do better is a source that is not a flag.
        lineKeys: {}, leadKeys: {},

        // ── And what the syllables themselves actually carry ──────────────────
        // The per-line verdict was not enough: a line tallies as "continuations" on the
        // strength of ONE flagged syllable, while every other multi-syllable word on it
        // goes unmarked and comes apart. These are the numbers that distinguish "the
        // payload marks its joins" from "the payload marks a handful of them".
        //
        // Key NAMES, never values — a field name is structure, a field value is the lyric.
        syllables: 0, flagTrue: 0, flagFalse: 0, flagAbsent: 0,
        keys: {},

        // ── Does TIMING predict the flag? ─────────────────────────────────────
        // If the plain text turns out not to be there, this is the remaining signal:
        // syllables carved out of one word share an exact boundary, where separate words
        // usually do not. These four counts say whether that holds in a given payload —
        // measured on the lines that DO mark their joins, so the payload calibrates the
        // rule itself rather than us assuming a threshold.
        //
        // joinTight  = flagged as joining, and time-contiguous with the next
        // joinGap    = flagged as joining, but with a gap
        // endTight   = flagged as ending a word, yet time-contiguous
        // endGap     = flagged as ending a word, with a gap
        joinTight: 0, joinGap: 0, endTight: 0, endGap: 0
    }
}

function _tallyKeys(bucket, o) {
    if (!o || typeof o !== "object") return
    for (var k in o) {
        if (!Object.prototype.hasOwnProperty.call(o, k)) continue
        bucket[k] = (bucket[k] || 0) + 1
    }
}

function _tallyLine(entry) {
    _tallyKeys(_spacingTally.lineKeys, entry)
    if (entry) _tallyKeys(_spacingTally.leadKeys, entry.Lead)
}

function _tallySyllable(s) {
    _spacingTally.syllables += 1
    var fv = s ? s.IsPartOfWord : undefined
    if (fv === true)       _spacingTally.flagTrue  += 1
    else if (fv === false) _spacingTally.flagFalse += 1
    else                   _spacingTally.flagAbsent += 1

    if (s && typeof s === "object") {
        for (var k in s) {
            if (!Object.prototype.hasOwnProperty.call(s, k)) continue
            _spacingTally.keys[k] = (_spacingTally.keys[k] || 0) + 1
        }
    }
}
_resetSpacingTally()

// ── Word breaks from the line's OWN text ──────────────────────────────────────
// The authoritative answer, when the payload carries one. Everything below this is a
// heuristic reading of a flag that individual producers fill in inconsistently; the plain
// text of the line is not a heuristic at all — it says where the spaces are.
//
// Returns one boolean per syllable ("a word ends here") or null when the two cannot be
// reconciled. Reconciliation is strict on purpose: ignoring whitespace, the syllables
// concatenated must be exactly the line. Anything else — a transliteration, a corrected
// take, a stray edit — and the alignment would be silently off by a word, which is worse
// than the flag being wrong because it would look deliberate.
function _breaksFromText(syllables, plain) {
    if (typeof plain !== "string" || plain === "") return null
    plain = _clean(plain)

    var joined = ""
    for (var i = 0; i < syllables.length; i++) {
        var t = syllables[i] && syllables[i].Text
        joined += (typeof t === "string") ? _clean(t) : ""
    }

    var strip = /\s+/g
    if (joined.replace(strip, "") !== plain.replace(strip, "")) return null

    var out = []
    var p = 0
    for (var j = 0; j < syllables.length; j++) {
        var st = (syllables[j] && typeof syllables[j].Text === "string")
               ? _clean(syllables[j].Text) : ""

        // Walk this syllable's non-space characters against the line, so `p` ends up just
        // past the syllable's last character wherever the line put it.
        for (var k = 0; k < st.length; k++) {
            if (/\s/.test(st.charAt(k))) continue
            while (p < plain.length && /\s/.test(plain.charAt(p))) p++
            p++
        }

        // Whitespace immediately after is a word break. End of line is not — the last
        // unit of a row carries no trailing space.
        out.push(p < plain.length && /\s/.test(plain.charAt(p)))
    }
    return out
}

function _units(syllables, plain) {
    var out = []
    if (!syllables || syllables.length === 0) return out

    // Authoritative when it reconciles; falls through to the flag when it does not.
    var breaks = _breaksFromText(syllables, plain)

    // ── Who decides where the spaces go ───────────────────────────────────────
    // `IsPartOfWord` is OPTIONAL, and treating "absent" as "ends a word" broke real
    // lines: a word split into three syllables came out as three separate words with
    // gaps between them, because none of them carried the flag.
    //
    // So prefer the text's own spacing whenever the data actually uses it — if any
    // syllable on this line carries whitespace, the payload is encoding word breaks in
    // the text and nothing needs inventing. Only when the text has NO spacing at all
    // does the flag get to decide, which is the case it was there for.
    var textCarriesSpacing = false
    for (var p = 0; p < syllables.length; p++) {
        var pt = syllables[p] && syllables[p].Text
        if (typeof pt === "string" && /\s/.test(pt)) { textCarriesSpacing = true; break }
    }

    // ── WHICH convention is this line using ───────────────────────────────────
    // There are two in the wild, they are mirror images, and reading one as the other puts
    // a gap between every syllable of every multi-syllable word:
    //
    //   A. continuations are written out.  mid-word → IsPartOfWord: true,
    //      word-final → false or omitted.  A word ends wherever the flag is NOT true.
    //   B. only the ends are written out.  word-final → IsPartOfWord: false,
    //      mid-word → OMITTED.             A word ends only where the flag IS false.
    //
    // Under A, absent means "ends a word". Under B it means exactly the opposite. Assuming
    // A unconditionally is what rendered "forever" as "for ev er" and "together" as
    // "to ge ther": every syllable of those words was absent, so every one of them took a
    // space, while the single-syllable words around them came out right and hid it.
    //
    // The line says which it is. A `true` anywhere means continuations are being marked,
    // so it is A. No `true` at all, but a MIX of explicit `false` and absent, is only
    // meaningful under B — there is no reason to write `false` on some and omit it on
    // others if absence already meant the same thing. Everything else (all-false, or the
    // flag never appearing) reads identically under both.
    var anyTrue = false, anyFalse = false, anyAbsent = false
    for (var f = 0; f < syllables.length; f++) {
        var fv = syllables[f] ? syllables[f].IsPartOfWord : undefined
        if (fv === true)       anyTrue = true
        else if (fv === false) anyFalse = true
        else                   anyAbsent = true
        _tallySyllable(syllables[f])

        var nx = syllables[f + 1]
        if (nx && fv !== undefined) {
            var tight = Math.abs(_num(nx.StartTime) - _num(syllables[f].EndTime)) < 0.002
            _spacingTally[fv === true ? (tight ? "joinTight" : "joinGap")
                                      : (tight ? "endTight"  : "endGap")] += 1
        }
    }

    // Absent everywhere means "add nothing", which is also correct for scripts that write
    // without spaces and have no boundaries to mark in the first place.
    var flagUsed  = anyTrue || anyFalse
    var omitsTrue = !anyTrue && anyFalse && anyAbsent

    // Recorded so the choice is reportable rather than inferable. Which convention a
    // payload uses is not visible from the rendered line unless you already know what the
    // words were meant to be, which is how "for ev er" survived a release — counts only,
    // never a syllable of text. See toLines().
    _spacingTally[breaks               ? "plainText"
                : textCarriesSpacing   ? "text"
                : omitsTrue            ? "endsOnly"
                : anyTrue              ? "continuations"
                : flagUsed             ? "allEnds"
                : "none"] += 1

    for (var i = 0; i < syllables.length; i++) {
        var s = syllables[i]
        var text = (s && typeof s.Text === "string") ? _clean(s.Text) : ""
        if (text === "") continue

        var start = _num(s.StartTime)
        var end   = _num(s.EndTime)
        var dur   = end > start ? end - start : 0

        // A break only where the line is actually encoding one. In order of authority:
        // the line's own plain text, then spacing already in the syllable text, then the
        // flag read in this line's own convention.
        if (breaks) {
            if (breaks[i] && !/\s$/.test(text)) text += " "
        } else {
            var endsWord = omitsTrue ? (s.IsPartOfWord === false)
                                     : (s.IsPartOfWord !== true)

            if (!textCarriesSpacing && flagUsed && endsWord && !/\s$/.test(text))
                text += " "
        }

        out.push({ t: start, d: dur, text: text })
    }

    // The final syllable of a line has nothing to be spaced from, and a trailing space
    // there widens the line for the fit-scale measurement without drawing anything.
    if (out.length > 0)
        out[out.length - 1].text = out[out.length - 1].text.replace(/\s+$/, "")

    return out
}

// ── Background vocals ─────────────────────────────────────────────────────────
// `Background` is a LIST of segments, each with its own span and syllables — the short
// echoes and answers sung under the lead. Flattened into one word list per line: they are
// sequential within the line, and the card draws them as a single quieter row beneath it.
function _background(entry) {
    var segs = entry.Background
    if (!segs || segs.length === 0) return null

    var out = []
    for (var i = 0; i < segs.length; i++) {
        var s = segs[i]
        if (!s || !s.Syllables || s.Syllables.length === 0) continue
        var u = _units(s.Syllables, s.Text)
        for (var j = 0; j < u.length; j++) out.push(u[j])
    }
    if (out.length === 0) return null

    // _units() strips the trailing space from the last syllable of EACH segment, which is
    // right for a line but wrong once several segments are flattened into one — the last
    // word of one segment ran straight into the first word of the next. Re-space every
    // unit except the final one, which correctly ends the row.
    for (var k = 0; k < out.length - 1; k++) {
        if (!/\s$/.test(out[k].text)) out[k].text += " "
    }
    return out
}

function _lineFrom(entry) {
    if (!entry) return null

    // ── Which side is singing ─────────────────────────────────────────────────
    // `OppositeAligned` marks the second voice in a duet. Their client puts it on the far
    // side of the column, which is the whole point: with two singers trading lines, the
    // ALIGNMENT is what tells you who is on without reading a word of it.
    var aligned = entry.OppositeAligned === true ? "right" : "left"

    // Syllable-timed line.
    // The line's own text, wherever they put it. Where it exists it decides the spacing
    // outright — see _breaksFromText().
    _tallyLine(entry)

    var lead = entry.Lead
    if (lead && lead.Syllables && lead.Syllables.length > 0) {
        var plain = (typeof entry.Text === "string" && entry.Text !== "") ? entry.Text
                  : (typeof lead.Text === "string" ? lead.Text : "")

        var words = _units(lead.Syllables, plain)
        if (words.length === 0) return null

        var t   = _num(lead.StartTime)
        var end = _num(lead.EndTime)
        var bg  = _background(entry)

        return {
            t: t,
            dur: end > t ? end - t : 0,
            words: words,
            text: words.map(function (w) { return w.text }).join(""),
            aligned: aligned,
            bg: bg,
            bgText: bg ? bg.map(function (w) { return w.text }).join("") : ""
        }
    }

    // Line-timed: no syllables, just a span and some text. Their "Line" type, and also
    // the shape a syllable payload degrades to for a line nobody has timed.
    var txt = entry.Text || (lead ? lead.Text : "")
    if (typeof txt === "string" && txt !== "") {
        var lt  = _num(entry.StartTime !== undefined ? entry.StartTime
                                                     : (lead ? lead.StartTime : 0))
        var le  = _num(entry.EndTime !== undefined ? entry.EndTime
                                                   : (lead ? lead.EndTime : 0))
        return { t: lt, dur: le > lt ? le - lt : 0, words: null, text: _clean(txt),
                 aligned: aligned, bg: null, bgText: "" }
    }

    return null
}

// ── toLines ───────────────────────────────────────────────────────────────────
// Returns the same object shape scripts/lyrics.py prints, so Lyrics.qml can apply either
// without caring which produced it:
//
//   { kind: "syllable" | "line" | "plain" | "none", lines: [ … ], plain: "" }
//
// "syllable" is a NEW kind. It behaves like "word" everywhere except that the view must
// not run the heuristic splitter over it.
// ── Unwrap ────────────────────────────────────────────────────────────────────
// The API does not always hand back the lyrics object directly. Measured against the
// live endpoint, `result.data` came through as a TWO-ELEMENT ARRAY — which matches their
// own fetchLyrics(), typed `Promise<[object | string, number]>`: a [payload, status]
// tuple. Reaching for `.Content` on that yields undefined and the whole thing silently
// maps to nothing.
//
// So find the lyrics object rather than assuming its position: the element that actually
// carries Content or Type. Position-independent on purpose — a tuple whose order changes
// is a lot cheaper to survive than to debug.
function unwrap(payload, out) {
    if (!payload || typeof payload !== "object") return null
    if (!Array.isArray(payload)) return payload

    // ── The packed wire format ────────────────────────────────────────────────
    // Measured against the live endpoint, `result.data` arrives as a two-element array of
    // two arrays: a table of distinct primitives and a flat integer opcode stream. That is
    // not a [payload, status] tuple — it is the dictionary encoding their API answers with,
    // and reaching for `.Content` on it yields undefined and maps to nothing at all.
    //
    // objpack.js decodes it. Its `unpack` returns null rather than throwing, so a payload
    // in any other shape simply falls through to the checks below.
    if (payload.length === 2
        && Array.isArray(payload[0]) && Array.isArray(payload[1])) {
        var packOut = {}
        var decoded = ObjPack.unpack(payload, packOut)
        if (decoded && typeof decoded === "object" && !Array.isArray(decoded))
            return decoded
        if (Array.isArray(decoded)) {
            payload = decoded
        } else if (out) {
            // unpack failed outright — capture WHY, not just that it did. Without this
            // the caller only ever gets "did not map" plus the outer [values, stream]
            // shape it already knew was a pair; the actual opcode/pointer/count that
            // broke the decode was reaching nobody. See CLAUDE.md's Lyrics section:
            // this exact class of silent failure cost four rounds to diagnose once.
            out.packReason = packOut.reason
        }
    }

    // Otherwise look for the lyrics object by shape rather than by position — a tuple
    // whose order changes is cheaper to survive than to debug.
    for (var i = 0; i < payload.length; i++) {
        var el = payload[i]
        if (el && typeof el === "object" && !Array.isArray(el)
            && (el.Content !== undefined || el.Type !== undefined
                || el.Lyrics !== undefined))
            return el
    }
    return null
}

function toLines(raw) {
    var empty = { kind: "none", lines: [], plain: "", source: "", provider: "",
                  community: false }

    var unwrapOut = {}
    var payload = unwrap(raw, unwrapOut)
    if (!payload || typeof payload !== "object") {
        if (unwrapOut.packReason) empty.reason = unwrapOut.packReason
        return empty
    }

    var src       = typeof payload.source === "string" ? payload.source : ""
    var provider  = src ? providerName(src) : ""
    var community = src === COMMUNITY

    // The server's own "nothing for this track" — `{ error: "MISSING_LYRICS" }`. Not a
    // shape problem, so it is flagged as MISSING rather than left to read as a failed map.
    if (typeof payload.error === "string" && payload.Content === undefined) {
        empty.missing = true
        empty.reason = payload.error.slice(0, 60)
        return empty
    }

    var content = payload.Content
    if (!content || content.length === 0) {
        // A Static payload is untimed text. Their field naming varies: `Lyrics` / `Text`
        // as one block, or — measured on the live API — `Lines: [{ Text }]`, which was
        // dropped entirely and mapped to "none".
        var flat = payload.Lyrics || payload.Text || ""
        if (!flat && Array.isArray(payload.Lines))
            flat = payload.Lines
                .map(function (e) { return e && typeof e.Text === "string" ? e.Text : "" })
                .join("\n")
        return flat
            ? { kind: "plain", lines: [], plain: _clean(String(flat)),
                source: src, provider: provider, community: community }
            : empty
    }

    var lines = []
    var syllabic = false

    _resetSpacingTally()

    for (var i = 0; i < content.length; i++) {
        var l = _lineFrom(content[i])
        if (!l) continue
        if (l.words && l.words.length > 0) syllabic = true
        lines.push(l)
    }

    if (lines.length === 0) return empty

    // Out-of-order lines are not expected here, but the shell binary-searches this list
    // and a single misordered entry makes lineAt() return the wrong line for a whole
    // region of the song rather than failing visibly.
    lines.sort(function (a, b) { return a.t - b.t })

    return {
        kind: syllabic ? "syllable" : "line",
        lines: lines,
        plain: "",
        source: src,
        provider: provider,
        community: community,

        // Which spacing convention each line turned out to be using. Counts, never text.
        // "for ev er" shipped because nothing could report this: a payload that splits
        // every word looks, from outside, exactly like a payload whose words are short.
        spacing: _spacingTally
    }
}
