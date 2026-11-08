.pragma library

// ── karaoke.js ────────────────────────────────────────────────────────────────
// The karaoke module's arithmetic, pure so it can be tested
// (`bun scripts/test-karaoke.js`). services/Karaoke.qml owns the process, the clock and
// the state; everything that DECIDES — is this a voice, did that line match, what is the
// score — is here.
//
// ── What "a match" can honestly mean ─────────────────────────────────────────
// The song has no pitch track to compare a voice with, so there are exactly two signals:
//
//   TIMING  you are voicing while a lyric line is on. From the mic level and the line's
//           window. It cannot tell if the words are right — only that you are singing when
//           the song says someone should be.
//   WORDS   what a speech recogniser heard you sing, aligned against the words of the
//           lines around now. Optional (needs a model), rough, and the better evidence.
//
// With words, a line is scored mostly on words; without, on timing alone. Nothing here
// pretends one is the other: `lit` says how sure it is, and the score says which mode
// earned it.
// ─────────────────────────────────────────────────────────────────────────────

// ── The voice gate ────────────────────────────────────────────────────────────
// "Voiced" takes two things, because a level alone cannot tell a voice from a fan:
//
//   LOUD       the singing-band level clears the room's noise floor by a margin AND an
//              absolute minimum (a silent mic's floor is ~0, so a ratio alone would call a
//              breath a voice). The floor falls fast and rises slowly — ~20x slower still
//              while loud, so a held note can't teach it that loud is normal, but a steady fan
//              is learned in about a minute and a half.
//   PERIODIC   `voicing`, the helper's periodicity score: a vowel is near 1, breath and room
//              noise are low. With a hysteresis (on at 0.55, off at 0.38) so a note's wobble
//              doesn't chatter. Measured on synthetic signals: a vowel 10 dB over noise stays
//              >= 0.88, white noise never passed 0.46, smooth low-passed noise (a rumble) reached
//              0.69 — which is why LOUD is also required. With no numpy the helper sends no
//              `voicing` and the gate judges level alone, as it did before.
//
// The hold bridges the dip between words and a consonant's loss of periodicity. It is short
// (160 ms): the cell goes dark about as fast as you stop.
//
// Calibrated on a real (quiet) recording of speech, 2026-10-17: speech sat at RMS 0.010–0.019 and the
// first minimum, 0.012, caught 33 of 60 speech frames. Periodicity is what tells a voice from noise,
// so the absolute minimum is only there to ignore digital silence and mic self-noise; and speech
// glides ("zero" into "one") dip to a voicing of 0.3–0.5, so it is allowed to fall to 0.3 once on.
var GATE = { minRms: 0.004, ratio: 2.6, holdMs: 160, rise: 0.0015, fall: 0.25,
             voicingOn: 0.55, voicingOff: 0.3 };

function gateNew() {
    return { floor: GATE.minRms / GATE.ratio, voiced: false, lastVoiceAt: -1e9 };
}

// One reading → the next gate state. `rms` is 0..1 (a full-scale signal is 1), `now` any
// monotonic millisecond clock, `voicing` 0..1 or undefined (no numpy).
function gateStep(g, rms, now, voicing) {
    var r = Number(rms);
    if (!(r >= 0)) r = 0;                       // NaN, negative, undefined
    var floor = g.floor;
    var loud = r > Math.max(GATE.minRms, floor * GATE.ratio);
    var hasV = typeof voicing === "number" && voicing === voicing;
    var periodic = !hasV || voicing >= (g.voiced ? GATE.voicingOff : GATE.voicingOn);
    floor += (r - floor) * (r < floor ? GATE.fall : loud ? GATE.rise * 0.05 : GATE.rise);
    var sung = loud && periodic;
    var last = sung ? now : g.lastVoiceAt;
    return { floor: Math.max(floor, 1e-5), voiced: sung || (now - last) <= GATE.holdMs, lastVoiceAt: last };
}

// ── Words ─────────────────────────────────────────────────────────────────────
function _isCjk(c) { return (c >= 0x3040 && c <= 0x30FF) || (c >= 0x3400 && c <= 0x9FFF); }
function _isWordChar(ch) {
    if (/[0-9]/.test(ch)) return true;
    if (ch.toLowerCase() !== ch.toUpperCase()) return true;          // a cased letter, any script
    var c = ch.charCodeAt(0);
    if (c >= 0x0300 && c <= 0x036F) return true;                     // a combining accent continues its word
    if (c < 0x0370) return false;                                    // ASCII / Latin-1 punctuation
    if (c >= 0x2000 && c <= 0x2BFF) return false;                    // punctuation, symbols, arrows
    if ((c >= 0x3000 && c <= 0x303F) || (c >= 0xFE30 && c <= 0xFE4F)) return false;
    if ((c >= 0xFF00 && c <= 0xFF0F) || (c >= 0xFF1A && c <= 0xFF20)) return false;
    return true;                                                     // uncased scripts (kana, Hangul, Arabic…)
}

function _fold(t) {
    var s = String(t);
    if (typeof s.normalize === "function") s = s.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    return s.toLowerCase().replace(/[\u2019'`]/g, "");
}

// Where the words are in `text`: [{ s, e }], character indices, e exclusive. The ONE
// tokenizer — words() is these spans folded, and the lyrics card draws its underlines from
// the same spans — so "the third word" is the same word to the matcher and to the eye.
// An apostrophe is part of a word ("don't"); other punctuation separates; each kana or Han
// character is a word of its own (they have no spaces). A run that folds to nothing (a lone
// apostrophe) is not a word.
function wordSpans(text) {
    var s = String(text === undefined || text === null ? "" : text);
    var out = [];
    var start = -1;
    function close(end) {
        if (start >= 0 && _fold(s.slice(start, end)) !== "") out.push({ s: start, e: end });
        start = -1;
    }
    for (var i = 0; i < s.length; i++) {
        var ch = s.charAt(i);
        var w = _isWordChar(ch) || ch === "'" || ch === "\u2019" || ch === "`";
        if (!w) { close(i); continue; }
        if (_isCjk(s.charCodeAt(i))) { close(i); start = i; close(i + 1); continue; }
        if (start < 0) start = i;
    }
    close(s.length);
    return out;
}

// Text → comparable tokens: lower-cased, accents folded, apostrophes dropped ("don't" is
// one word), punctuation a separator.
function words(text) {
    var s = String(text === undefined || text === null ? "" : text);
    return wordSpans(s).map(function (sp) { return _fold(s.slice(sp.s, sp.e)); });
}

function _lev(a, b) {
    var n = a.length, m = b.length;
    if (n === 0) return m;
    if (m === 0) return n;
    var prev = [], cur = [];
    for (var j = 0; j <= m; j++) prev.push(j);
    for (var i = 1; i <= n; i++) {
        cur = [i];
        for (var k = 1; k <= m; k++)
            cur.push(Math.min(prev[k] + 1, cur[k - 1] + 1, prev[k - 1] + (a.charAt(i - 1) === b.charAt(k - 1) ? 0 : 1)));
        prev = cur;
    }
    return prev[m];
}

// ── Does it SOUND like the word? ──────────────────────────────────────────────
// A recogniser hears a sung word as a neighbour of it — "wheel" for "will", "lovin" for
// "loving", "rack" for "rock" — and a lyric word sung slightly off is still the word. So
// closeness is judged on how it SOUNDS, not only how it is spelt: soundKey() boils a word to
// its consonant skeleton, folding the pairs a voice and a microphone confuse (b/p, d/t, g/k,
// v/f, z/s), dropping silent letters (knight, thought, lamb) and the vowels (the least stable
// part of a sung word), and treating sh/ch/th as the one sound each. It is English-shaped,
// which is what Vosk's small English model hears; anything that isn't plain Latin letters has
// no key and is compared by spelling alone.
var _CLASS = { b: "P", p: "P", d: "T", t: "T", g: "K", k: "K", v: "F", f: "F", z: "S", s: "S",
               j: "J", l: "L", m: "M", n: "N", r: "R" };

function soundKey(word) {
    var w = String(word === undefined || word === null ? "" : word).toLowerCase();
    if (!/^[a-z]+$/.test(w)) return "";
    w = w.replace(/^(kn|gn|pn|wr|ps)/, function (m) { return m.charAt(1); })
         .replace(/^x/, "s").replace(/^wh/, "w")
         .replace(/ph/g, "f").replace(/(.)gh/g, "$1").replace(/tch/g, "ch").replace(/ck/g, "k")
         .replace(/dg/g, "j").replace(/sch/g, "sk").replace(/(sh|ch)/g, "X").replace(/th/g, "0")
         .replace(/c(?=[eiy])/g, "s").replace(/[cq]/g, "k").replace(/x/g, "ks").replace(/mb$/, "m");
    var out = "", prev = "";
    for (var i = 0; i < w.length; i++) {
        var c = w.charAt(i), nxt = w.charAt(i + 1), code;
        if ("aeiou".indexOf(c) >= 0) {
            if (out === "") out = "A";            // a word that begins on a vowel keeps that
            prev = "";
            continue;
        }
        if (c === "h") code = "";
        else if (c === "w" || c === "y") code = nxt !== "" && "aeiou".indexOf(nxt) >= 0 ? c.toUpperCase() : "";
        else code = _CLASS[c] || c;
        if (code && code !== prev) out += code;
        if (code) prev = code;
    }
    return out;
}

// How alike two words are, 0..1: the better of their spelling and their sound. Equal sound is
// 0.92 — never quite 1, so an exact word still beats a sound-alike when both are on offer.
function closeness(heard, want) {
    if (heard === want) return 1;
    var m = Math.max(heard.length, want.length);
    if (m === 0) return 1;
    var ortho = 1 - _lev(heard, want) / m;
    var ka = soundKey(heard), kb = soundKey(want), sound = 0;
    if (ka !== "" && kb !== "") {
        if (ka === kb) sound = (ka.length >= 2 || ka !== "A") ? 0.92 : 0;      // a bare vowel is every vowel
        else {
            // One sound off counts only in a key long enough to stay specific: a single edit in a
            // three-letter skeleton scores 0.67 and let "golf" pass for "alpha".
            var r = 1 - _lev(ka, kb) / Math.max(ka.length, kb.length);
            sound = r >= 0.75 ? r : 0;
        }
    }
    return Math.max(ortho, sound);
}

// ── Mods ──────────────────────────────────────────────────────────────────────
// osu!'s mods, for singing: switch one on before a run and it makes the run harder in one way, and its score
// worth more by a multiplier. They change how a run is JUDGED (so accuracy and rank are earned against the
// harder rule); the multiplier is on the SCORE.
//
//   HD   Hidden Lyrics   a PARTIAL hide: only the line being sung is shown, the rest fade out. Judging is
//                        unchanged.                                                                   x1.06
//   HD+  Hidden Lyrics+  hides EVERYTHING, the line being sung too: you sing from memory, and see only the
//                        underlines of the words you hit. (Code `HDP`: a stored mods string is joined with
//                        "+", so the plus cannot be in a code.) Replaces HD; the two are never both on.     x1.25
//   HR   Hard Rock       stricter WORDING: "close enough to the ear" stops counting (a word must be spelt
//                        nearly right), and 90% of a line's words, not 70%, are full marks. Needs a
//                        recogniser: with timing alone there is no wording to be strict about, so it earns
//                        nothing.                                                                       x1.12
//   TH   Time-Hell       strict TIMING: the window a voice counts in shrinks (a beat early to a beat late
//                        becomes barely either), a line's words may only be sung close to its time, and 65%
//                        of the window voiced, not 45%, is full marks.                                  x1.20
//
// Mods are fixed for a run when it begins; changing one mid-song would be changing the rules under a score.
var MODS = {
    HD:  { name: "Hidden Lyrics",  label: "HD",  mult: 1.06, note: "Only the line being sung is shown" },
    HDP: { name: "Hidden Lyrics+", label: "HD+", mult: 1.25, note: "Everything is hidden, the line being sung too: sing from memory" },
    HR:  { name: "Hard Rock",      label: "HR",  mult: 1.12, note: "Stricter wording: close enough no longer counts, and 90% of the words are full marks" },
    TH:  { name: "Time-Hell",      label: "TH",  mult: 1.2,  note: "Strict timing: come in on the beat, hold the line, nothing counts outside its window" }
};
var MOD_ORDER = ["HD", "HDP", "HR", "TH"];

// Config's choices → the active mods, in order: ["HDP", "TH"]. `hidden` is 0 (off), 1 (HD) or 2 (HD+); for
// the one that is a plain switch, `hd: true` is HD. HD and HD+ are one control with three positions.
function modList(flags) {
    var f = flags || {}, out = [];
    var hidden = f.hidden === 2 ? 2 : f.hidden === 1 || f.hd === true ? 1 : 0;
    if (hidden === 1) out.push("HD");
    if (hidden === 2) out.push("HDP");
    if (f.hr === true) out.push("HR");
    if (f.th === true) out.push("TH");
    return out;
}

// What a run actually earns for: HR does nothing without words to be strict about.
function effectiveMods(list, wordsMode) {
    return (list || []).filter(function (m) { return wordsMode || m !== "HR"; });
}

function modMultiplier(list) {
    var m = 1, l = list || [];
    for (var i = 0; i < l.length; i++) if (MODS[l[i]]) m *= MODS[l[i]].mult;
    return Math.round(m * 100) / 100;
}

// A stored mods string ("HD+TH") made safe: only the known mods, once each, in order — and HD+ replaces HD
// (the stronger hide wins) — anything else drops.
function cleanMods(str) {
    var have = {}, parts = String(str === undefined || str === null ? "" : str).split(/[^A-Za-z]+/);
    for (var i = 0; i < parts.length; i++) if (MODS[parts[i].toUpperCase()]) have[parts[i].toUpperCase()] = true;
    if (have.HDP) delete have.HD;
    return MOD_ORDER.filter(function (m) { return have[m] === true; }).join("+");
}
function modsOf(str) { var s = cleanMods(str); return s === "" ? [] : s.split("+"); }

// What a mod is called on screen ("HD+" for the code HDP), and a whole list as one line: "HD+ TH".
function modLabel(code) { return MODS[code] ? MODS[code].label : ""; }
function modsText(list) {
    var l = Array.isArray(list) ? list : modsOf(list);
    return l.map(modLabel).filter(function (x) { return x !== ""; }).join(" ");
}

// Which hide is a run played with: "" (none), "partial" (HD) or "all" (HD+).
function hideModeOf(list) {
    var l = list || [];
    return l.indexOf("HDP") >= 0 ? "all" : l.indexOf("HD") >= 0 ? "partial" : "";
}

// The numbers the mods change. Normal is what every default in this file says.
// How long a line that has just ended waits for its late words before it is judged, in ms. The recogniser
// lags and a singer trails the lyric, and in a FAST song the next line is on before the last one's words
// have landed. So the wait is `graceMs` for a line of a normal length and up to twice that for a short
// one: a line of 2.5 s or more waits graceMs, one of 1 s or less twice that (about 2.4 s; Time-Hell 1 s).
var GRACE_PACE_FULL = 2.5, GRACE_PACE_SPAN = 1.5;
function settleAfter(lines, i, rl) {
    var base = rl ? rl.graceMs : 1200;
    if (i < 0 || i >= lines.length) return base;
    var shortBy = Math.max(0, Math.min(GRACE_PACE_SPAN, GRACE_PACE_FULL - (lineEnd(lines, i) - lines[i].t)));
    return Math.round(base * (1 + shortBy / GRACE_PACE_SPAN));
}

var RULES_NORMAL = { strictWords: false, lead: 0.15, tail: 0.35, openLead: 0.8, graceMs: 1200, timingFull: 0.45, wordFull: 0.7 };

function rules(list) {
    var l = list || [];
    var r = Object.assign({}, RULES_NORMAL);
    if (l.indexOf("HR") >= 0) { r.strictWords = true; r.wordFull = 0.9; }
    if (l.indexOf("TH") >= 0) { r.lead = 0.05; r.tail = 0.1; r.openLead = 0.3; r.graceMs = 500; r.timingFull = 0.65; }
    return r;
}

// Did the recogniser hear THIS lyric word? A word of three letters or fewer is only taken on
// its SOUND ("the" is not "she"; "know" is "no") — one edit in three letters is a different
// word; anything longer on spelling or sound, at 0.66.
//
// `strict` (Hard Rock): no sound-alikes at all, and spelling must be 85% right — one wrong letter in a long
// word, nothing for a short one.
function sameWord(heard, want, strict) {
    if (heard === want) return true;
    if (strict) {
        var m = Math.max(heard.length, want.length);
        return m > 3 && 1 - _lev(heard, want) / m >= 0.85;
    }
    if (Math.max(heard.length, want.length) <= 3) {
        var ka = soundKey(heard), kb = soundKey(want);
        return ka !== "" && ka === kb && (ka.length >= 2 || ka !== "A");
    }
    return closeness(heard, want) >= 0.66;
}

// ── Words the recogniser cannot hear ──────────────────────────────────────────
// A speech model has a vocabulary, and a word outside it is not misheard: it can NEVER be output. Slang
// ("piroca"), a name, an ad-lib in another language ("yeah" in a Portuguese song) — about 13% of the word
// tokens in 40 real Portuguese songs against the small model. Held against the singer they cut the combo on
// every line, lowered the words share, and left a word never underlined however well it was sung. The
// helper reports them (`oov`); here they are FREE: a free word is lit together with the heard word next to
// it, as though sung, and a line made only of them is not judged. `oov` is an object {foldedWord: true}.
function freeFlags(ws, oov) {
    var out = [];
    for (var i = 0; i < ws.length; i++) out.push(!!(oov && oov[ws[i]]));
    return out;
}

function allFree(ws, oov) {
    if (!oov || ws.length === 0) return false;
    for (var i = 0; i < ws.length; i++) if (!oov[ws[i]]) return false;
    return true;
}

// A tally that knows which of its words are free (lineResult leaves a line of only those unjudged).
function withFree(t, oov) { return Object.assign({}, t, { free: freeFlags(t.words, oov) }); }

// ── Which lyric word did that sound belong to? ───────────────────────────────
// A forward-only CURSOR through the lyric words, not an alignment redone from scratch on
// every partial result. The re-aligning version had a real bug: when two lines share words
// ("we will rock you" twice), the words you had ALREADY sung still sat in the recogniser's
// utterance, matched equally well against the next line's identical words, and lit them —
// the next line read as sung before you opened your mouth.
//
// Here each heard word is consumed once, in order:
//   • it is matched against the next LOOKAHEAD lyric words from the cursor — never into an
//     earlier line, never further than that, so a stray word between two real ones is skipped
//     and a distant repeat is out of reach. (It may step back up to four UNLIT words in its own line, so
//     one wrong jump forward can't strand the real words behind it — see _find);
//   • a hit moves the cursor past that word, so the same sound can't light a second one;
//   • a PARTIAL result's last word may still change, so only words seen unchanged in two
//     consecutive partials are taken (a final result takes them all and ends the utterance);
//   • the cursor is kept within a line of the song (matcherSync): a singer who stopped can't
//     have late words land on a line long gone, and a seek resets it.
//
// A state is { line, w, took, prev }: the cursor (a line index into the lyrics, and a word in
// it), how many of this utterance's words are already taken, and the previous partial.
var LOOKAHEAD = 5;
var LOOKBACK = 4;

function matcherNew() { return { line: -1, w: 0, took: 0, prev: [] }; }

function matcherSync(m, line) {
    if (line < 0) return m;
    if (m.line < 0 || m.line > line + 1) return { line: line, w: 0, took: m.took, prev: m.prev };
    if (m.line < line - 1) return { line: line - 1, w: 0, took: m.took, prev: m.prev };
    return m;
}

// Words a recogniser drops or a singer slurs: short, or common function words. When the words
// either side of one were heard and it was not, it was almost certainly sung.
var WEAK = ["with", "that", "this", "your", "just", "from", "have", "they", "then", "them", "when", "what"];
function isWeak(w) { return w.length <= 3 || WEAK.indexOf(w) >= 0; }

// `ctx` is the lines the cursor may reach: [{ line, words, flags, open }] in ascending order
// (`flags` is what is already lit, per word; `open` — default true — is whether the song has got
// near enough to the line for its words to be sung: see lineOpen). A closed line is out of reach.
// Measured on a real recording: the recogniser's partial for one line briefly carried a stray
// word that is the FIRST word of the next, and with partials confirmed promptly it lit the next
// line's word and pulled the cursor into it, stranding the real last words of the line being sung. Of the words within reach that the sound could be, the BEST
// wins — closeness less a little for each word skipped — so a sound-alike right at the cursor
// doesn't steal a word sung exactly two on.
//
// It may also look BACK, up to LOOKBACK words, in the cursor's own line, at words not yet lit: one wrong
// jump forward (a sound-alike two words ahead) must not make the real words behind it
// unreachable for good. Never into an earlier line (that would light the first of a repeated
// line's words from the second's), never onto a word already lit or taken this call.
function _find(ctx, line, w, token, used, strict) {
    var steps = 0, best = null, bestScore = -1;
    for (var i = 0; i < ctx.length; i++) {
        var c = ctx[i];
        if (c.line === line) {
            for (var b = w - 1; b >= Math.max(0, w - LOOKBACK); b--) {
                if ((c.flags && c.flags[b]) || (c.free && c.free[b]) || used[c.line + ":" + b] || !sameWord(token, c.words[b], strict)) continue;
                var back = closeness(token, c.words[b]) - 0.12 * (w - b);
                if (back > bestScore) { bestScore = back; best = { line: c.line, w: b, back: true }; }
            }
        }
    }
    for (i = 0; i < ctx.length && steps < LOOKAHEAD; i++) {
        c = ctx[i];
        if (c.line < line) continue;
        if (c.open === false) break;                  // nor any line after one that is not yet on
        for (var k = (c.line === line ? w : 0); k < c.words.length && steps < LOOKAHEAD; k++, steps++) {
            if (c.free && c.free[k]) { steps--; continue; }       // unhearable: not a candidate, and not a step
            if (!sameWord(token, c.words[k], strict)) continue;
            var score = closeness(token, c.words[k]) - 0.06 * steps;
            if (score > bestScore) { bestScore = score; best = { line: c.line, w: k }; }
        }
    }
    // Nothing ahead matches: a LATE word. In a fast song the line it belongs to is already behind the live
    // one (a line left a moment ago is kept for its grace, and may be several back when lines are short), and
    // the cursor has moved on. Only then — a word that fits something ahead is never taken from behind — it
    // lights the best unlit word of those lines, the nearest line first. The cursor stays where it is.
    if (best === null) {
        for (i = 0; i < ctx.length; i++) {
            c = ctx[i];
            if (c.line >= line) continue;
            for (k = 0; k < c.words.length; k++) {
                if ((c.flags && c.flags[k]) || (c.free && c.free[k]) || used[c.line + ":" + k] || !sameWord(token, c.words[k], strict)) continue;
                score = closeness(token, c.words[k]) - 0.12 * (line - c.line);
                if (score > bestScore) { bestScore = score; best = { line: c.line, w: k, back: true }; }
            }
        }
    }
    return best;
}

// The words between the cursor and a hit that were most likely sung and not heard: all weak,
// no more than two, and in the line the hit is in (the cursor at a line's end counts as the
// start of the next). Returns [{ line, w }].
function _gap(ctx, line, w, hit, used) {
    var c = null, from = w;
    for (var i = 0; i < ctx.length; i++) {
        if (ctx[i].line === hit.line) c = ctx[i];
    }
    if (!c) return [];
    if (hit.line !== line) {
        // Only from a cursor that is spent its own line, into the line straight after it.
        var prev = null;
        for (i = 0; i < ctx.length; i++) if (ctx[i].line === line) prev = ctx[i];
        if (!prev || w < prev.words.length) return [];
        for (i = 0; i < ctx.length; i++)
            if (ctx[i].line > line && ctx[i].line < hit.line && ctx[i].words.length > 0) return [];
        from = 0;
    }
    if (hit.w - from < 1) return [];
    // At most two WEAK words may have been dropped; a free (unhearable) word between is no bar and no count.
    var out = [], weak = 0;
    for (var k = from; k < hit.w; k++) {
        if ((c.flags && c.flags[k]) || used[hit.line + ":" + k]) return [];
        if (!(c.free && c.free[k])) {
            if (!isWeak(c.words[k]) || ++weak > 2) return [];
        }
        out.push({ line: hit.line, w: k, inferred: true });
    }
    return out;
}

// The free words standing right beside a hit, unlit: before it, and after it (the cursor then steps over
// those). A hit on a word makes the run of unhearable words around it sung, since nothing else could say so.
function _freeNear(ctx, hit, used) {
    var c = null;
    for (var i = 0; i < ctx.length; i++) if (ctx[i].line === hit.line) c = ctx[i];
    var before = [], after = [];
    if (!c || !c.free) return { before: before, after: after };
    for (var k = hit.w - 1; k >= 0 && c.free[k]; k--)
        if (!(c.flags && c.flags[k]) && !used[hit.line + ":" + k]) before.push({ line: hit.line, w: k, inferred: true });
    for (k = hit.w + 1; k < c.words.length && c.free[k]; k++)
        if (!(c.flags && c.flags[k]) && !used[hit.line + ":" + k]) after.push({ line: hit.line, w: k, inferred: true });
    return { before: before, after: after };
}

// What the recogniser has heard of the utterance so far (all of it, as tokens). Returns the
// next state and the lyric words it just took: [{ line, w }] (an `inferred` one is a small word
// between two heard that the recogniser dropped).
function matcherHear(m, ctx, heard, isFinal, strict) {
    var took = m.took, prev = m.prev;
    if (heard.length < took - 2) { took = 0; prev = []; }    // a new utterance with no final between
    var stable = heard.length;
    if (!isFinal) {
        stable = 0;
        while (stable < heard.length && stable < prev.length && heard[stable] === prev[stable]) stable++;
    }
    var line = m.line, w = m.w, hits = [], used = {};
    for (var j = took; j < stable; j++) {
        var at = _find(ctx, line, w, heard[j], used, strict);
        if (!at) continue;
        if (!at.back) {
            var gap = _gap(ctx, line, w, at, used);
            for (var g = 0; g < gap.length; g++) { hits.push(gap[g]); used[gap[g].line + ":" + gap[g].w] = true; }
            line = at.line;
            w = at.w + 1;
        }
        hits.push({ line: at.line, w: at.w });
        used[at.line + ":" + at.w] = true;
        var near = _freeNear(ctx, at, used), around = near.before.concat(near.after);
        for (var f = 0; f < around.length; f++) { hits.push(around[f]); used[around[f].line + ":" + around[f].w] = true; }
        if (!at.back) w = at.w + 1 + near.after.length;
    }
    return { m: { line: line, w: w, took: isFinal ? 0 : Math.max(took, stable), prev: isFinal ? [] : heard },
             hits: hits };
}

// How early a line's words may be sung, in seconds: a singer comes in ahead of the lyric clock
// by a little, and the clock itself is only as good as the lyrics' timing and Lyrics.offset.
var OPEN_LEAD = 0.8;

// Has the song reached `lines[i]` closely enough for its words to count?
function lineOpen(lines, i, pos, rl) {
    return i >= 0 && i < lines.length && pos >= lines[i].t - (rl ? rl.openLead : OPEN_LEAD);
}

// ── Lines ─────────────────────────────────────────────────────────────────────
// The words a line sings: its timed words if it has them, else its text.
function lineText(line) {
    if (!line) return "";
    if (line.text) return String(line.text);
    if (line.words && line.words.length) return line.words.map(function (w) { return w.text || ""; }).join("");
    return "";
}

// When a line is on, in seconds: its own duration if it states one, else until the next
// line begins — and never past that, or two lines would both claim the same moment.
function lineEnd(lines, i) {
    var l = lines[i], next = lines[i + 1];
    var end = l.dur > 0 ? l.t + l.dur : (next ? next.t : l.t + 4);
    return next ? Math.min(end, next.t) : end;
}

// A singer starts a beat late and holds a beat over: the window a voice counts in.
var LEAD = 0.15, TAIL = 0.35;

function inWindow(lines, i, pos, rl) {
    if (i < 0 || i >= lines.length) return false;
    return pos >= lines[i].t - (rl ? rl.lead : LEAD) && pos <= lineEnd(lines, i) + (rl ? rl.tail : TAIL);
}

// ── A line's running tally ────────────────────────────────────────────────────
function tallyNew(text) {
    var w = words(text);
    var flags = [];
    for (var i = 0; i < w.length; i++) flags.push(false);
    return { words: w, flags: flags, activeMs: 0, voicedMs: 0 };
}

// Time passing while the line is on: `dt` ms, and whether you were voicing.
function tallyTime(t, dt, voiced) {
    return { words: t.words, flags: t.flags, activeMs: t.activeMs + dt, voicedMs: t.voicedMs + (voiced ? dt : 0) };
}

// A lyric word was sung: the tally with that word's flag on. Flags only ever turn on — a
// partial result that revises a word away must not un-light it.
function tallyMark(t, w) {
    if (w < 0 || w >= t.flags.length || t.flags[w]) return t;
    var flags = t.flags.slice();
    flags[w] = true;
    return { words: t.words, flags: flags, activeMs: t.activeMs, voicedMs: t.voicedMs };
}

function matched(t) {
    var n = 0;
    for (var i = 0; i < t.flags.length; i++) if (t.flags[i]) n++;
    return n;
}

// How much of a line was sung, 0..1 each. 45% of the line's window voiced counts as fully in time:
// the window is the line's own span plus a beat either side (and, for lyrics with only line times, runs
// to the next line), and no real phrase fills that — a singer breathes, a consonant is not voiced, a
// line has gaps. It was 70%, a guess; replayed on a real recording where EVERY word was heard it scored
// each line "Great" and the run an A, because the speech filled ~60% of the window. 70% of the words
// counts as fully right (a recogniser misses some).
var TIMING_FULL = 0.45;
function timing(t, rl) { return t.activeMs > 0 ? Math.min(1, (t.voicedMs / t.activeMs) / (rl ? rl.timingFull : TIMING_FULL)) : 0; }

// WORD_CURVE bends the word share so half the words is clearly worse than all of them: at 1.5, with the
// normal 70% for full marks, 50% of a line's words is 0.60 (it was 0.71), 35% is 0.35, and 10% is 0.05.
var WORD_CURVE = 1.5;
function wordScore(t, rl) {
    if (t.words.length === 0) return 0;
    return Math.pow(Math.min(1, (matched(t) / t.words.length) / (rl ? rl.wordFull : 0.7)), WORD_CURVE);
}

// The line's points, 0..1. With words, the WORDS decide it and timing only shapes how much of them
// counts: 0.75 of the word score for singing it off the beat, all of it in time. A line with no word
// landed is 0, however well it was voiced in time — it was a quarter once ("free credit for making a
// noise"), and replayed over 199 real lyrics a whole song of other words or mumbling still came out
// ~30%, so a song half sung wrong could still pass as a C. (Sung to the wrong words, 7% of a line's words
// land by chance; mumbling "la na oh", 4%.) Without words there is nothing to hear but whether you
// sang, so timing alone is the line — and so a hummed line in time is full marks there; that mode
// cannot tell it from the words.
function points(t, wordsMode, rl) {
    return wordsMode ? wordScore(t, rl) * (0.75 + 0.25 * timing(t, rl)) : timing(t, rl);
}

// How lit the cell is right now, 0..1: nothing while silent or off the line; in time, a
// base glow; with words, brighter as the line's words land.
function lit(t, voiced, onLine, wordsMode) {
    if (!voiced || !onLine) return 0;
    if (!wordsMode || t.words.length === 0) return 1;
    return 0.35 + 0.65 * Math.min(1, matched(t) / t.words.length / 0.7);
}

// ── A grace period when a song starts too fast ────────────────────────────────
// A run begins when Karaoke is switched on, a song starts, or you seek: and the first line can come
// before you are ready. For GRACE_S seconds of SONG TIME after that (not wall time: a pause does not
// spend it), a line that starts inside it is a WARM-UP — judged as usual, but if it comes out a miss
// it is simply not counted, so a line you missed getting ready neither lowers the accuracy nor
// breaks anything. A warm-up line you DO sing well counts in full: no one is robbed of a good line.
var GRACE_S = 6;

function inGrace(lineStart, graceUntil) { return lineStart < graceUntil; }

// When the next line that sings something starts after `pos`, or -1.
function nextSingableStart(lines, pos) {
    for (var i = 0; i < lines.length; i++)
        if (lines[i].t > pos && words(lineText(lines[i])).length > 0) return lines[i].t;
    return -1;
}

// ── Did the run start from the start? ─────────────────────────────────────────
// A score means something only for a whole song. Joining part-way through is not that, however well you
// sing the rest, so a run ranks only if it BEGAN at the start: before the first line had been going for
// more than a moment (a line barely begun can still be sung nearly whole). The coverage rule (half the
// song's lines) stays as a second guard; this is the one the player is told about, and can fix by
// restarting. A song with no lyrics to judge by has no start to miss.
var START_SLACK = 1.5;

function firstSingableStart(lines) {
    for (var i = 0; i < lines.length; i++)
        if (words(lineText(lines[i])).length > 0) return lines[i].t;
    return -1;
}

function startedFromStart(lines, pos) {
    var first = firstSingableStart(lines);
    return first < 0 || pos <= first + START_SLACK;
}

// ── Which line the song is on, steadily ───────────────────────────────────────
// `idx` is where the song clock says the song is; `from` is the line we had. The clock is not
// steady to the line: a player's position is coarse and re-anchors, so it steps BACK a few tenths
// now and then — and at a line boundary that read as "the song went back a line". Treated as a seek,
// it dropped what had just been sung, and the underlines went with it. A step back is only a seek if
// it is real: more than one line, or more than a second and a half of clock; a jump forward is one
// past three seconds. Anything smaller is the same line still. Returns { idx, seek }.
function stepLine(from, idx, pos, lastPos) {
    var seek = from < 0;
    if (from >= 0 && idx !== from) {
        if (idx < from) {
            if (idx < from - 1 || pos < lastPos - 1.5) seek = true;
            else idx = from;
        } else if (pos - lastPos > 3) {
            seek = true;
        }
    }
    return { idx: idx, seek: seek };
}

// ── The game ──────────────────────────────────────────────────────────────────
// osu!'s shape, on lyrics. Each line you sing is JUDGED by its points (0..1, from points()):
//
//     PERFECT  >= 0.90      300      GREAT  >= 0.70      200
//     GOOD     >= 0.50      100      MISS   below         0
//
// The COMBO is per WORD: every word you sing adds one, a word you skip cuts it, a line that ends with
// its last words unsung breaks it. (A line used to be a combo step; a whole line for one point of
// combo made a long song's counter crawl, and hid the thing a singer actually feels — "I dropped
// that word".) A judged line's score is its value times a multiplier that grows with the word combo
// at that moment, x1 to x3 by 100 words. ACCURACY is the mean of every judged line's points, as a
// percent, and the RANK is read off it:
//
//     SS+  exactly 100%  SS  95–99.9     S  90–94.9     A  80–89.9     B  70–79.9     C  60–69.9     F  below
//
// (Read off the accuracy as it is DISPLAYED, to a tenth — 89.96 shows as 90.0 and is an S, not an
// A that looks like one.) Only lines that sing something and were on long enough to judge count
// (>= 600 ms: a line you seeked into is not a line you missed). A line left silent is judged, and
// is a miss: that is what makes the accuracy mean something.
var MIN_SCORED_MS = 600;
var JUDGE_AT = { perfect: 0.9, great: 0.7, good: 0.5 };
var JUDGE_VALUE = { perfect: 300, great: 200, good: 100, miss: 0 };
var RANKS = ["SS+", "SS", "S", "A", "B", "C", "F"];

function judge(points) {
    return points >= JUDGE_AT.perfect ? "perfect" : points >= JUDGE_AT.great ? "great"
         : points >= JUDGE_AT.good ? "good" : "miss";
}

function rankFor(accuracy) {
    var a = Math.round(Number(accuracy) * 10) / 10;
    if (!(a >= 0)) a = 0;
    return a >= 100 ? "SS+" : a >= 95 ? "SS" : a >= 90 ? "S" : a >= 80 ? "A" : a >= 70 ? "B" : a >= 60 ? "C" : "F";
}

// The judged result of one line's tally, or null when it is not to be judged.
function lineResult(t, wordsMode, rl) {
    if (t.words.length === 0 || t.activeMs < MIN_SCORED_MS) return null;
    // A line of nothing the recogniser can hear has nothing to judge, in a words run (timing alone still can).
    if (wordsMode && t.free && t.free.length === t.words.length && t.free.every(function (f) { return f; })) return null;
    var p = points(t, wordsMode, rl);
    return { points: p, judgment: judge(p), hit: matched(t), words: t.words.length };
}

function sessionNew() {
    // streak is the WORD combo as it stands, best its highest; timeline is one entry per judged line.
    return { points: 0, count: 0, streak: 0, best: 0, score: 0, perfect: 0, great: 0, good: 0, miss: 0,
             wordsHit: 0, wordsTotal: 0, timeline: [] };
}

var MAX_TIMELINE = 400;

// A judged line added to the session: a new session. Its score is its value times the multiplier for
// the word combo the session holds at this moment; the combo itself is moved by sessionCombo /
// sessionBreak, not by a line.
//
// `modMult` is the mods' multiplier (modMultiplier), on the score only — never on the accuracy.
function sessionAdd(s, lr, modMult) {
    var multiplier = (1 + Math.min(Math.max(s.streak, 0), 100) / 50) * (modMult > 0 ? modMult : 1);
    var timeline = s.timeline.length < MAX_TIMELINE ? s.timeline.concat([{ points: lr.points, judgment: lr.judgment }]) : s.timeline;
    return {
        points: s.points + lr.points, count: s.count + 1, streak: s.streak, best: s.best,
        score: s.score + Math.round(JUDGE_VALUE[lr.judgment] * multiplier),
        perfect: s.perfect + (lr.judgment === "perfect" ? 1 : 0),
        great: s.great + (lr.judgment === "great" ? 1 : 0),
        good: s.good + (lr.judgment === "good" ? 1 : 0),
        miss: s.miss + (lr.judgment === "miss" ? 1 : 0),
        wordsHit: s.wordsHit + (lr.hit || 0), wordsTotal: s.wordsTotal + (lr.words || 0),
        timeline: timeline
    };
}

// The word combo is now `n` (and the best is kept), or broken.
function sessionCombo(s, n) {
    var c = Math.max(0, Math.round(n));
    return Object.assign({}, s, { streak: c, best: Math.max(s.best, c) });
}
function sessionBreak(s) { return s.streak === 0 ? s : Object.assign({}, s, { streak: 0 }); }

function sessionFinish(s, t, wordsMode, rl, modMult) {
    var lr = lineResult(t, wordsMode, rl);
    return lr ? sessionAdd(s, lr, modMult) : s;
}

// The combo as the song's words see it: the run of LIT words that ends at (line, w), carried back
// across line boundaries (skipping silent rows). `sung` is line index → per-word flags; `lines` the
// lyrics. A word not lit ends the run; so does a line that was never sung at all. A skipped word
// therefore cuts the combo by itself — there is no separate break to keep.
function comboRun(sung, lines, line, w, oov, skip) {
    var f = sung[line];
    if (!f) return 0;
    var n = 0, l = line, k = w;
    for (var guard = 0; guard < 20000; guard++) {
        if (k >= 0) {
            if (!f[k]) break;
            n++; k--;
            continue;
        }
        do { l--; } while (l >= 0 && (words(lineText(lines[l])).length === 0 || allFree(words(lineText(lines[l])), oov) || (skip && skip(l))));
        if (l < 0) break;
        f = sung[l];
        if (!f) break;
        k = f.length - 1;
    }
    return n;
}

// A line has ended (and its grace is over): did it leave the combo alive? Only if its LAST word was
// sung, or a word after it already has been (then the combo is already that later run).
function comboSurvives(tally, sung, line, oov, skip) {
    if (tally.words.length === 0 || tally.flags[tally.words.length - 1] || allFree(tally.words, oov) || (skip && skip(line))) return true;
    for (var k in sung) {
        if (Number(k) <= line) continue;
        for (var i = 0; i < sung[k].length; i++) if (sung[k][i]) return true;
    }
    return false;
}

// The mean of the judged lines' points, as a percent: exact (percent() is the rounded integer).
function accuracy(s) { return s.count > 0 ? 100 * s.points / s.count : 0; }
function percent(s) { return s.count > 0 ? Math.round(accuracy(s)) : 0; }

// ── When a song is over, and what it was worth ────────────────────────────────
function lastSingable(lines) {
    for (var i = lines.length - 1; i >= 0; i--) if (words(lineText(lines[i])).length > 0) return i;
    return -1;
}

function singableCount(lines, skipped) {
    var n = 0;
    for (var i = 0; i < lines.length; i++) if (words(lineText(lines[i])).length > 0 && !(skipped && skipped[i])) n++;
    return n;
}

// Has the last sung line finished, with a beat to spare for its last words to land?
function songDone(lines, pos, graceSec) {
    var last = lastSingable(lines);
    if (last < 0) return false;
    return pos >= lineEnd(lines, last) + (graceSec === undefined ? 1.5 : graceSec);
}

// A run ranks only if it covers at least half the song's lines, and at least three: sing one line
// of a song and you have not earned its SS. (A run that does not rank is shown, not saved.)
var MIN_RANKED_SHARE = 0.5;

// The accuracy shown is to a tenth, and 99.96 would round UP to a displayed 100.0 — an SS+ for a run that
// missed. So it is capped at 99.9 unless the run was exactly 100: SS+ is flawless or nothing.
function displayAccuracy(exact) {
    var a = Math.round(exact * 10) / 10;
    return exact < 100 && a >= 100 ? 99.9 : a;
}

function result(s, total, wordsMode, mods) {
    var acc = displayAccuracy(accuracy(s));
    var list = effectiveMods(modsOf(Array.isArray(mods) ? mods.join("+") : mods), wordsMode === true);
    return {
        accuracy: acc, rank: rankFor(acc), score: s.score, maxCombo: s.best,
        // The mods the run was played with, as they earned (HR only counts with words), and their multiplier.
        mods: list.join("+"), modMult: modMultiplier(list),
        perfect: s.perfect, great: s.great, good: s.good, miss: s.miss,
        lines: s.count, total: total,
        // Words heard of the words in the lines that were judged; only meaningful with a recogniser.
        wordsHit: s.wordsHit, wordsTotal: s.wordsTotal, wordsMode: wordsMode === true,
        timeline: s.timeline,
        fullCombo: s.count > 0 && s.miss === 0,
        ranked: s.count >= 3 && total > 0 && s.count >= Math.ceil(total * MIN_RANKED_SHARE)
    };
}

// 1234567 → "1,234,567" (a score, as a game shows it).
function formatScore(n) {
    var x = Math.max(0, Math.round(Number(n) || 0));
    return String(x).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

// ── The scores on disk ────────────────────────────────────────────────────────
// Per song: the best run, the last, how many times it was played, a short history, and where its
// cover is cached. The file is hand-editable and is read back as a trust boundary: every number is
// clamped, every string capped, a rank must be a rank, a URL must be http(s) or a local file, a
// cover must be the name this module would have made. Anything else is dropped, never defaulted
// into a plausible score.
var MAX_SONGS = 400, MAX_HISTORY = 10, MAX_STR = 200;

function _norm(x) { return String(x === undefined || x === null ? "" : x).toLowerCase().replace(/\s+/g, " ").trim().slice(0, MAX_STR); }
function _str(x) { return String(x === undefined || x === null ? "" : x).replace(/[\u0000-\u001f]/g, " ").trim().slice(0, MAX_STR); }
function _num(x, lo, hi, dflt) {
    var n = Number(x);
    if (!(n === n) || n === Infinity || n === -Infinity) return dflt;
    return Math.max(lo, Math.min(hi, n));
}

// A song's identity: its artist and title, case and spacing folded. "" for no title (not a song).
function songKey(artist, title) {
    var t = _norm(title);
    return t === "" ? "" : _norm(artist) + "::" + t;
}

// Where its cover is cached, by name: eight hex digits of the key (djb2) and a fixed extension.
function coverName(key) {
    var h = 5381, k = String(key);
    for (var i = 0; i < k.length; i++) h = ((h * 33) ^ k.charCodeAt(i)) >>> 0;
    return ("00000000" + h.toString(16)).slice(-8) + ".img";
}

function _url(x) { var u = _str(x); return /^(https?|file):\/\/\S+$/.test(u) ? u.slice(0, 500) : ""; }

function _run(r) {
    r = r || {};
    var acc = Math.round(_num(r.accuracy, 0, 100, 0) * 10) / 10;
    return {
        accuracy: acc, rank: rankFor(acc),                    // the rank is always re-derived, never trusted
        score: Math.round(_num(r.score, 0, 1e9, 0)), maxCombo: Math.round(_num(r.maxCombo, 0, 1e5, 0)),
        perfect: Math.round(_num(r.perfect, 0, 1e5, 0)), great: Math.round(_num(r.great, 0, 1e5, 0)),
        good: Math.round(_num(r.good, 0, 1e5, 0)), miss: Math.round(_num(r.miss, 0, 1e5, 0)),
        lines: Math.round(_num(r.lines, 0, 1e5, 0)), total: Math.round(_num(r.total, 0, 1e5, 0)),
        fullCombo: r.fullCombo === true, mods: cleanMods(r.mods), at: _num(r.at, 0, 1e12, 0)
    };
}

function _entry(raw, key) {
    if (!raw || typeof raw !== "object" || key === "") return null;
    var hist = [];
    var src = Array.isArray(raw.history) ? raw.history.slice(0, MAX_HISTORY) : [];
    for (var i = 0; i < src.length; i++) {
        var h = _run(src[i]);
        hist.push({ accuracy: h.accuracy, rank: h.rank, score: h.score, at: h.at });
    }
    var cover = _str(raw.cover);
    return {
        key: key, artist: _str(raw.artist), title: _str(raw.title), album: _str(raw.album),
        art: _url(raw.art), cover: cover === coverName(key) ? cover : "",
        plays: Math.round(_num(raw.plays, 0, 1e6, 0)),
        best: _run(raw.best), last: _run(raw.last), history: hist
    };
}

function dbNew() { return { songs: {} }; }

// A document read from disk, made safe. Never throws, never returns the input.
function sanitize(raw) {
    var db = dbNew();
    if (!raw || typeof raw !== "object" || !raw.songs || typeof raw.songs !== "object") return db;
    var keys = Object.keys(raw.songs).slice(0, MAX_SONGS * 2);
    var entries = [];
    for (var i = 0; i < keys.length; i++) {
        var e = _entry(raw.songs[keys[i]], _norm(keys[i]));
        if (e && e.title !== "") entries.push(e);
    }
    entries.sort(function (a, b) { return b.last.at - a.last.at; });
    entries = entries.slice(0, MAX_SONGS);
    for (var j = 0; j < entries.length; j++) db.songs[entries[j].key] = entries[j];
    return db;
}

// A finished run recorded: { db, newBest, previousBest, entry }. `meta` is the song: artist, title,
// album, art (a URL). `now` is seconds since the epoch. The best is the higher accuracy, then the
// higher score. A song with no title is not recorded.
function record(db, res, meta, now) {
    var key = songKey(meta && meta.artist, meta && meta.title);
    if (key === "") return { db: db, newBest: false, previousBest: null, entry: null };
    var prev = db.songs[key] || null;
    var run = _run(Object.assign({}, res, { at: now }));
    var newBest = !prev || run.accuracy > prev.best.accuracy
               || (run.accuracy === prev.best.accuracy && run.score > prev.best.score);
    var art = _url(meta.art) || (prev ? prev.art : "");
    var history = [{ accuracy: run.accuracy, rank: run.rank, score: run.score, at: run.at }]
        .concat(prev ? prev.history : []).slice(0, MAX_HISTORY);
    var entry = {
        key: key, artist: _str(meta.artist), title: _str(meta.title), album: _str(meta.album) || (prev ? prev.album : ""),
        art: art, cover: prev && prev.art === art ? prev.cover : "",
        plays: (prev ? prev.plays : 0) + 1, best: newBest ? run : prev.best, last: run, history: history
    };
    var next = dbNew();
    var all = Object.keys(db.songs).map(function (k) { return db.songs[k]; }).filter(function (e) { return e.key !== key; });
    all.push(entry);
    all.sort(function (a, b) { return b.last.at - a.last.at; });
    all = all.slice(0, MAX_SONGS);
    for (var i = 0; i < all.length; i++) next.songs[all[i].key] = all[i];
    return { db: next, newBest: newBest, previousBest: prev ? prev.best : null, entry: entry };
}

// The cover for `key` was cached under `name`.
function withCover(db, key, name) {
    var e = db.songs[key];
    if (!e || name !== coverName(key)) return db;
    var next = dbNew();
    for (var k in db.songs) next.songs[k] = db.songs[k];
    next.songs[key] = Object.assign({}, e, { cover: name });
    return next;
}

function removeSong(db, key) {
    if (!db.songs[key]) return db;
    var next = dbNew();
    for (var k in db.songs) if (k !== key) next.songs[k] = db.songs[k];
    return next;
}

// The songs as a list: "recent" (last played first), "best" (highest score first), "rank" (best
// accuracy first).
function list(db, order) {
    var all = Object.keys(db.songs).map(function (k) { return db.songs[k]; });
    var by = order === "best" ? function (a, b) { return b.best.score - a.best.score; }
           : order === "rank" ? function (a, b) { return b.best.accuracy - a.best.accuracy || b.best.score - a.best.score; }
           : function (a, b) { return b.last.at - a.last.at; };
    return all.sort(by);
}

// A header's worth: how many songs, how many plays, and how many songs sit at each best rank.
function summary(db) {
    var out = { songs: 0, plays: 0, ranks: { "SS+": 0, SS: 0, S: 0, A: 0, B: 0, C: 0, F: 0 } };
    for (var k in db.songs) {
        out.songs++;
        out.plays += db.songs[k].plays;
        out.ranks[db.songs[k].best.rank]++;
    }
    return out;
}

// ── Lines that are not to be counted ──────────────────────────────────────────
// Two reasons a line should not be held against the singer, both because it is not something one person
// sings at that moment:
//
//  • The USER SKIPPED it (right-click on the lyric): an ad-lib, a spoken part, a backing line, anything on
//    this song's lyrics that is not meant to be sung. It is kept per song as a mark, "index:words of the
//    line" — the index alone would point at the wrong line if the lyrics came back from another source, the
//    words alone would skip every repeat of a chorus line; both together only match the line that was marked.
//
//  • It OVERLAPS another in time (a duet: two voices on the lyrics at once). One singer cannot sing both,
//    so a line of such a pair that was not sung is excused when its partner was — see overlapExcused.
var OVERLAP_MIN = 0.4;

function skipMark(lines, i) { return lines[i] ? i + ":" + words(lineText(lines[i])).join(" ") : ""; }

// The marks that still point at a line of these lyrics → { index: true }.
function skipSet(lines, marks) {
    var out = {}, m = marks || [];
    for (var i = 0; i < m.length; i++) {
        var idx = parseInt(m[i], 10);
        if (idx >= 0 && idx < lines.length && skipMark(lines, idx) === m[i]) out[idx] = true;
    }
    return out;
}

// The marks with `mark` added, or taken out if it is there.
function skipToggle(marks, mark) {
    var m = (marks || []).slice(), at = m.indexOf(mark);
    if (mark === "") return m;
    if (at >= 0) m.splice(at, 1); else m.push(mark);
    return m;
}

// The skips file made safe to use: { songKey: [mark, …] }. It is hand-editable, so keys and marks are
// bounded strings and a song holds a bounded number.
function sanitizeSkips(doc) {
    var src = doc && typeof doc === "object" && doc.songs && typeof doc.songs === "object" ? doc.songs : {};
    var out = {}, n = 0;
    for (var k in src) {
        if (n >= 2000) break;
        if (typeof k !== "string" || k === "" || k.length > 200 || !Array.isArray(src[k])) continue;
        var marks = [];
        for (var i = 0; i < src[k].length && marks.length < 400; i++) {
            var s = src[k][i];
            if (typeof s === "string" && s.length <= 300 && /^\d+:/.test(s) && marks.indexOf(s) < 0) marks.push(s);
        }
        if (marks.length > 0) { out[k] = marks; n++; }
    }
    return out;
}

// Which lines overlap which, by their own spans (a line's `dur`, which the lyrics state, not the clamped
// lineEnd): { index: [partner indexes] }, only for lines that have one. Line-level lyrics with no `dur`
// never overlap.
function overlapMap(lines) {
    var out = {};
    for (var i = 0; i < lines.length; i++) {
        var a = lines[i];
        if (!(a.dur > 0) || words(lineText(a)).length === 0) continue;
        for (var j = Math.max(0, i - 4); j <= Math.min(lines.length - 1, i + 4); j++) {
            var b = lines[j];
            if (j === i || !(b.dur > 0) || words(lineText(b)).length === 0) continue;
            if (Math.min(a.t + a.dur, b.t + b.dur) - Math.max(a.t, b.t) >= OVERLAP_MIN) (out[i] = out[i] || []).push(j);
        }
    }
    return out;
}

function _share(flags) {
    if (!flags || flags.length === 0) return 0;
    var n = 0;
    for (var i = 0; i < flags.length; i++) if (flags[i]) n++;
    return n / flags.length;
}

// A line that overlaps another, was mostly NOT sung, while one it overlaps WAS (half its words or more):
// the singer took the other voice. It is excused — a miss on it is not counted and it does not cut the
// combo. A line sung half or more, or one whose partners were not sung either, is judged as any other.
function overlapExcused(overlaps, sung, i) {
    var p = overlaps && overlaps[i];
    if (!p || _share(sung[i]) >= 0.5) return false;
    for (var k = 0; k < p.length; k++) if (_share(sung[p[k]]) >= 0.5) return true;
    return false;
}

// ── Languages ─────────────────────────────────────────────────────────────────
// A speech model is for ONE language, so karaoke has to know which a song is in. The lyrics tell it:
// detectLanguage() reads their function words (the commonest, least song-specific words of each
// language — "the" "and" "you"; "não" "você" "que"; "je" "tu" "est"), or their script. The user can
// pin a language instead (Config.karaokeLanguage); "" is auto.
//
// Each entry: `name`, `native` (as its speakers write it), `model` (Vosk's code: the small model is
// vosk-model-small-<model>), `keepAccents` (does the model's vocabulary use the language's own
// letters — see grammarWords), `stop` (function words, ACCENT-FOLDED as words() makes them, so they
// match what is tokenised). The stop lists are deliberately short: they only have to tell languages
// apart, and the ones that two languages share ("de", "que", "a") count for both and so decide nothing.
var LANGS = {
    en: { name: "English", native: "English", model: "en-us", keepAccents: false,
          stop: "the and you i to a of it in me my is that on for with we your be this but all just im dont are was so if oh its ill cant".split(" ") },
    pt: { name: "Portuguese", native: "Portugu\u00eas", model: "pt", keepAccents: true,
          stop: "nao voce voces eu de que e o a os as um uma em com para por me te meu minha mais mas tudo quando sem nos ele ela vou vai foi ser seu sua tem ja ao na no do da dos das se so ate tao como aqui la pra".split(" ") },
    es: { name: "Spanish", native: "Espa\u00f1ol", model: "es", keepAccents: true,
          stop: "no que el la de y en un una tu mi te me es por con para lo los las yo pero cuando sin si se su al del mas como ya muy soy eres esta".split(" ") },
    fr: { name: "French", native: "Fran\u00e7ais", model: "fr", keepAccents: true,
          stop: "je tu il elle nous vous le la les de des un une et est pas que qui dans pour avec mon ton sur ce cette au du mais tout suis tes mes ne plus comme".split(" ") },
    de: { name: "German", native: "Deutsch", model: "de", keepAccents: true,
          stop: "ich du und der die das nicht ist ein eine mit fur mir mich dich wir sie auf wie zu den dem es im aber nur wenn".split(" ") },
    it: { name: "Italian", native: "Italiano", model: "it", keepAccents: true,
          stop: "io tu il lo la che non di e un una per con mi ti sei ma come tutto quando si mio mia sono anche piu nel della ho ha questa".split(" ") },
    nl: { name: "Dutch", native: "Nederlands", model: "nl", keepAccents: true,
          stop: "ik je jij de het een en van niet is dat op met voor ze we zijn maar als aan er ook mijn".split(" ") },
    ru: { name: "Russian", native: "\u0420\u0443\u0441\u0441\u043a\u0438\u0439", model: "ru", keepAccents: true, stop: [] }
};

var LANG_ORDER = ["en", "pt", "es", "fr", "de", "it", "nl", "ru"];

// The share of a text's letters that are Cyrillic (a language's own script is a surer sign than any
// word list, and the only one for Russian).
function _cyrillicShare(s) {
    var letters = 0, cyr = 0;
    for (var i = 0; i < s.length; i++) {
        var ch = s.charAt(i);
        if (ch.toLowerCase() === ch.toUpperCase()) continue;
        letters++;
        var c = ch.charCodeAt(0);
        if (c >= 0x0400 && c <= 0x04FF) cyr++;
    }
    return letters > 0 ? cyr / letters : 0;
}

// What language are these lyric lines in? { lang, score, runnerUp, sure }: `lang` the best guess ("" for
// none — nothing to go on, or a script no model here covers), `score` the share of the words that were
// that language's function words, `sure` true when it beat the next language clearly. Pure; runs once per
// song, never per frame.
function detectLanguage(lines) {
    var text = "", all = [];
    for (var i = 0; i < lines.length; i++) {
        var t = lineText(lines[i]);
        text += t + " ";
        var ws = words(t);
        for (var k = 0; k < ws.length; k++) all.push(ws[k]);
    }
    if (all.length < 3) return { lang: "", score: 0, runnerUp: "", sure: false };
    if (_cyrillicShare(text) > 0.5) return { lang: "ru", score: 1, runnerUp: "", sure: true };
    var scores = {}, best = "", second = "";
    for (var j = 0; j < LANG_ORDER.length; j++) {
        var code = LANG_ORDER[j];
        if (LANGS[code].stop.length === 0) continue;
        var set = {}, stops = LANGS[code].stop;
        for (var s = 0; s < stops.length; s++) set[stops[s]] = true;
        var hits = 0;
        for (var w = 0; w < all.length; w++) if (set[all[w]] === true) hits++;
        scores[code] = hits / all.length;
    }
    for (var c = 0; c < LANG_ORDER.length; c++) {
        var cc = LANG_ORDER[c];
        if (scores[cc] === undefined) continue;
        if (best === "" || scores[cc] > scores[best]) { second = best; best = cc; }
        else if (second === "" || scores[cc] > scores[second]) second = cc;
    }
    // Enough evidence, not only a high share of a few words: a "la la la" refrain is three words of
    // Portuguese, Spanish, French and Italian at once, and decides nothing.
    if (best === "" || scores[best] < 0.1 || scores[best] * all.length < 4)
        return { lang: "", score: best === "" ? 0 : scores[best], runnerUp: second, sure: false };
    var sure = second === "" || scores[best] >= scores[second] * 1.25;
    return { lang: best, score: scores[best], runnerUp: second, sure: sure };
}

// Where to look for the model for `lang`, best first. `given` is Config.karaokeModelDir (a path the user
// set: used for every language, as it always was), `dataHome` is $XDG_DATA_HOME (already resolved, so no
// home directory is baked in here). `scripts/karaoke-model.sh <lang>` puts one in the first place.
function modelDirsFor(lang, given, dataHome) {
    if (given) return [given];
    var spec = LANGS[lang] || LANGS.en;
    var out = [dataHome + "/quicktest/vosk-" + spec.model, "/usr/share/vosk-models/small-" + spec.model];
    // English had one place before there were languages.
    if (spec.model === "en-us") out.unshift(dataHome + "/quicktest/vosk");
    return out;
}

// ── What the recogniser is told to listen for ─────────────────────────────────
// Measured on Vosk's small English model, against free-form recognition: told the lyric words, it
// recovered a line it had misheard ("nine oh two i no" came out "nah no to i know"), and its words
// appeared 0.1–0.25 s EARLIER. Speech that was not in the grammar came out as [unk], not as a lyric
// word, so it does not hallucinate matches. That is the single biggest lever on accuracy AND speed.
//
// The grammar is the words of the lines around now: each line as a phrase, and each word on its
// own (so a skipped line or a word out of order is still heard), plus [unk]. Vosk's vocabulary is
// lowercase, and a word it does not know is ignored (not an error) — so a name or a coinage is just
// not heard, and the small words around it are filled in by the matcher.
function grammarWords(text, lang) {
    var s = String(text === undefined || text === null ? "" : text);
    var spec = lang ? LANGS[lang] : null;
    var out = [];
    var parts, w;
    if (spec && spec.keepAccents) {
        // Portuguese, Spanish, French, German, Italian, Dutch, Russian…: the model's vocabulary HAS its
        // accents and letters — measured on the real Portuguese model, "não" "você" "coração" "está"
        // "também" "já" "mãe" are all words and "nao" "coracao" "ja" "mae" are not. So: no folding. Any
        // CASED letter is a letter (accents included, Cyrillic too); an apostrophe stays inside a word
        // (French and Italian elide with one); a hyphen separates ("guarda-chuva" is not in the
        // vocabulary, "guarda chuva" is).
        if (typeof s.normalize === "function") s = s.normalize("NFC");
        s = s.toLowerCase().replace(/[\u2019`]/g, "'");
        var cur = "";
        for (var i = 0; i <= s.length; i++) {
            var ch = i < s.length ? s.charAt(i) : " ";
            if (ch.toLowerCase() !== ch.toUpperCase() || ch === "'") { cur += ch; continue; }
            if (cur !== "") {
                w = cur.replace(/^'+/, "").replace(/'+$/, "");
                if (w !== "") out.push(w);
                cur = "";
            }
        }
        return out;
    }
    if (typeof s.normalize === "function") s = s.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    s = s.toLowerCase().replace(/[\u2019`]/g, "'");
    parts = s.split(/[^a-z']+/);
    for (var n = 0; n < parts.length; n++) {
        w = parts[n].replace(/^'+/, "").replace(/'+$/, "");
        if (w === "") continue;
        // "believin'" is "believing" to the model; the sung dropped g is not in its vocabulary.
        if (/in$/.test(w) && /in'$/.test(parts[n])) w += "g";
        out.push(w);
    }
    return out;
}

var GRAMMAR_BEHIND = 1, GRAMMAR_AHEAD = 3;

// The grammar for the song at line `idx`: { lo, hi, phrases }. `lines` are the lyric lines.
function grammarFor(lines, idx, lang) {
    var lo = Math.max(0, idx - GRAMMAR_BEHIND), hi = Math.min(lines.length - 1, idx + GRAMMAR_AHEAD);
    var phrases = [], seen = {}, singles = [];
    for (var i = lo; i <= hi; i++) {
        var ws = grammarWords(lineText(lines[i]), lang);
        if (ws.length === 0) continue;
        phrases.push(ws.join(" "));
        for (var k = 0; k < ws.length; k++) if (!seen[ws[k]]) { seen[ws[k]] = true; singles.push(ws[k]); }
    }
    return { lo: lo, hi: hi, phrases: phrases.concat(singles) };
}

// Does the grammar that is loaded (`cover`, or null for none) still reach the lines the song is
// about to sing? The one line behind and the two ahead must be inside it — unless the lyrics end.
function grammarStale(cover, idx, count) {
    if (!cover) return true;
    if (idx - 1 < cover.lo && cover.lo > 0) return true;
    return idx + 2 > cover.hi && cover.hi < count - 1;
}

// What the recogniser says for a sound it could not place, which is not a word.
function stripUnk(text) {
    return String(text === undefined || text === null ? "" : text).replace(/\[unk\]/gi, " ");
}

// ── Can it run here ───────────────────────────────────────────────────────────
// The microphone hears the song unless it is in your ears. A speaker would light the cell
// from the music itself — a match that means nothing — so it refuses, with a reason, rather
// than mislead. PipeWire names the physical form factor on the node.
var HEADSET_FORMS = ["headphone", "headphones", "headset", "hands-free", "handsfree"];

function isHeadphones(props) {
    var p = props || {};
    var form = String(p["device.form-factor"] || p["device.form_factor"] || "").toLowerCase();
    if (HEADSET_FORMS.indexOf(form) >= 0) return true;
    var icon = String(p["device.icon-name"] || p["device.icon_name"] || "").toLowerCase();
    return icon.indexOf("headphone") >= 0 || icon.indexOf("headset") >= 0;
}

// The karaoke card's current line as rich text: the words you have sung lit, the rest
// dimmed. `text` is the lyric line; `flags` is per word, in `words()` order. A word that is
// not a token (punctuation) takes the colour of the word before it.
function esc(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function litHtml(text, flags, onColour, offColour) {
    var s = String(text === undefined || text === null ? "" : text);
    var spans = wordSpans(s);
    var out = "";
    var run = "";
    var runLit = null;
    var k = -1;                                  // the word we are in or just left
    var lit = false;
    function flush() {
        if (run === "") return;
        out += "<span style=\"color:" + (runLit ? onColour : offColour) + "\">" + esc(run) + "</span>";
        run = "";
    }
    for (var i = 0; i < s.length; i++) {
        if (k + 1 < spans.length && i === spans[k + 1].s) { k++; lit = !!(flags && flags[k]); }
        if (runLit !== lit) { flush(); runLit = lit; }
        run += s.charAt(i);
    }
    flush();
    return out;
}
