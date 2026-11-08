.pragma library

// ── romajialign.js ────────────────────────────────────────────────────────────
// Puts a romanized line back onto the SYLLABLES it was made from, so the Latin letters light
// in step with the voice exactly as the original characters do. (bun scripts/test-romajialign.js)
//
// ── The problem ───────────────────────────────────────────────────────────────
// A romanizer (Google, pykakasi) answers with one string per LINE — "osae konde". The lyrics have
// timing per SYLLABLE (お さ え 込 ん で, each with its own start and length). To light "osa" with
// 抑 and "e" with え and "ko" with 込, every romaji piece has to be paired with the syllable it came
// from, and nothing in the answer says which is which.
//
// ── The method, for Japanese ──────────────────────────────────────────────────
// Kana are KNOWN: で is "de", ん is "n", え is "e" — whatever else the line says. Kanji are not:
// 抑 was read "osa", and the romanizer does not report where its reading ends. So:
//   1. The romanized line is cut into moras (ko · n · de), keeping its word breaks.
//   2. Walking the syllables in order, every kana is an ANCHOR: it takes the mora that spells it.
//   3. Between two anchors lie the kanji; they SHARE the moras between, as evenly as they divide.
// A kanji whose reading is longer than guessed therefore costs only its own group — the next
// anchor re-synchronises — instead of shifting every syllable after it (which splitting the line
// in proportion to character count would do, and what a one-line gloss gets away with).
//
// The things romanization does to kana are folded in: は read "wa", を "o", へ "e"; し as "shi" or
// "si"; しゃ as one mora; っ doubling the next consonant; and a long vowel ("ō", "ou", "aa") whose
// second kana (う, ー) has no mora of its own, so it takes nothing and the vowel before it keeps
// the macron.
//
// Hangul and Chinese are simpler — a block or a character is one syllable, and a romanized
// syllable one piece — and are paired in order (alignEven). Anything else is paired by letters.
// Every function returns [] when it cannot do better than the caller's fallback.
// ─────────────────────────────────────────────────────────────────────────────

// ── Moras ─────────────────────────────────────────────────────────────────────
var MACRON = { "ā": "a", "ī": "i", "ū": "u", "ē": "e", "ō": "o",
               "â": "a", "î": "i", "û": "u", "ê": "e", "ô": "o",
               "Ā": "a", "Ī": "i", "Ū": "u", "Ē": "e", "Ō": "o" }

function _plain(ch) {
    var l = MACRON[ch]
    return l !== undefined ? l : ch.toLowerCase()
}
function _isVowel(ch) { return "aeiou".indexOf(_plain(ch)) >= 0 }
function _isLetter(ch) { return /[A-Za-zÀ-ſ]/.test(ch) }
function _hasMacron(s) { return /[āīūēōâîûêôĀĪŪĒŌ]/.test(s) }

// The comparable form of a mora: lower-case, macrons plain, the doubled consonant a っ leaves
// ("kko" → "ko", "tchi" → "chi") taken off, and anything that is not a letter dropped.
function _key(text) {
    var k = ""
    for (var i = 0; i < text.length; i++) {
        var c = text.charAt(i)
        if (_isLetter(c)) k += _plain(c)
    }
    k = k.replace(/^tch/, "ch")
    k = k.replace(/^([bcdfghjklmpqrstvwxz])\1/, "$1")
    return k
}

// One romanized word → its moras [{ text, key, wordEnd }]. Punctuation stays on the mora it
// touches. A mora is consonants + ONE vowel ("ko", "kya", "tsu", "kko"), or a lone "n".
function _wordMoras(word) {
    var out = []
    var i = 0
    var n = word.length
    var lead = ""

    while (i < n) {
        // Leading punctuation rides on the first mora of the word.
        if (!_isLetter(word.charAt(i)) && word.charAt(i) !== "'") {
            if (out.length === 0) lead += word.charAt(i)
            else out[out.length - 1].text += word.charAt(i)
            i++
            continue
        }
        if (word.charAt(i) === "'") {                 // an n' marker: part of the mora before it
            if (out.length) out[out.length - 1].text += "'"
            i++
            continue
        }

        // A run of consonants.
        var j = i
        while (j < n && _isLetter(word.charAt(j)) && !_isVowel(word.charAt(j))) j++
        var run = word.substring(i, j)

        // "nd", "nsh", "nn": the ん is its own mora, and what is left starts the next one. "ny"
        // is a consonant cluster (にゃ) and stays whole.
        if (run.length > 1 && (run.charAt(0) === "n" || run.charAt(0) === "N")
                && run.charAt(1).toLowerCase() !== "y" && j < n) {
            out.push({ text: lead + run.charAt(0), key: "n", wordEnd: false })
            lead = ""
            i++
            continue
        }

        if (j < n && _isLetter(word.charAt(j))) {           // consonants + a vowel
            var mora = lead + run + word.charAt(j)
            lead = ""
            out.push({ text: mora, key: _key(mora), wordEnd: false })
            i = j + 1
        } else {                                            // consonants with no vowel after them
            var tail = lead + run
            lead = ""
            // A trailing "n" is the ん mora; any other final consonant belongs to the mora before.
            if (/^n$/i.test(run) && out.length >= 0) out.push({ text: tail, key: "n", wordEnd: false })
            else if (out.length) out[out.length - 1].text += tail
            else out.push({ text: tail, key: _key(tail), wordEnd: false })
            i = j
        }
    }
    if (lead !== "" && out.length) out[out.length - 1].text += lead
    if (out.length) out[out.length - 1].wordEnd = true
    return out
}

function moras(line) {
    var words = String(line || "").split(/\s+/).filter(function (w) { return w !== "" })
    var out = []
    for (var i = 0; i < words.length; i++) {
        var m = _wordMoras(words[i])
        for (var k = 0; k < m.length; k++) out.push(m[k])
    }
    return out
}

// ── Kana ──────────────────────────────────────────────────────────────────────
// The spellings of each kana's mora. Where romanizers disagree both are listed.
var ROW = {
    "あ": [[""], "a"], "い": [[""], "i"], "う": [[""], "u"], "え": [[""], "e"], "お": [[""], "o"],
    "か": [["k"], "a"], "き": [["k"], "i"], "く": [["k"], "u"], "け": [["k"], "e"], "こ": [["k"], "o"],
    "が": [["g"], "a"], "ぎ": [["g"], "i"], "ぐ": [["g"], "u"], "げ": [["g"], "e"], "ご": [["g"], "o"],
    "さ": [["s"], "a"], "し": [["sh", "s"], "i"], "す": [["s"], "u"], "せ": [["s"], "e"], "そ": [["s"], "o"],
    "ざ": [["z"], "a"], "じ": [["j", "z"], "i"], "ず": [["z"], "u"], "ぜ": [["z"], "e"], "ぞ": [["z"], "o"],
    "た": [["t"], "a"], "ち": [["ch", "t"], "i"], "つ": [["ts", "t"], "u"], "て": [["t"], "e"], "と": [["t"], "o"],
    "だ": [["d"], "a"], "ぢ": [["j", "d", "z"], "i"], "づ": [["z", "d"], "u"], "で": [["d"], "e"], "ど": [["d"], "o"],
    "な": [["n"], "a"], "に": [["n"], "i"], "ぬ": [["n"], "u"], "ね": [["n"], "e"], "の": [["n"], "o"],
    "は": [["h"], "a"], "ひ": [["h"], "i"], "ふ": [["f", "h"], "u"], "へ": [["h"], "e"], "ほ": [["h"], "o"],
    "ば": [["b"], "a"], "び": [["b"], "i"], "ぶ": [["b"], "u"], "べ": [["b"], "e"], "ぼ": [["b"], "o"],
    "ぱ": [["p"], "a"], "ぴ": [["p"], "i"], "ぷ": [["p"], "u"], "ぺ": [["p"], "e"], "ぽ": [["p"], "o"],
    "ま": [["m"], "a"], "み": [["m"], "i"], "む": [["m"], "u"], "め": [["m"], "e"], "も": [["m"], "o"],
    "や": [["y"], "a"], "ゆ": [["y"], "u"], "よ": [["y"], "o"],
    "ら": [["r"], "a"], "り": [["r"], "i"], "る": [["r"], "u"], "れ": [["r"], "e"], "ろ": [["r"], "o"],
    "わ": [["w"], "a"], "ゐ": [[""], "i"], "ゑ": [[""], "e"], "を": [["w", ""], "o"],
    "ゔ": [["v"], "u"]
}
var PARTICLE = { "は": ["wa"], "へ": ["e"], "を": ["o"] }
var SMALL_Y = { "ゃ": "a", "ゅ": "u", "ょ": "o" }
var SMALL_V = { "ぁ": "a", "ぃ": "i", "ぅ": "u", "ぇ": "e", "ぉ": "o" }

// Katakana → hiragana, by code point (ア..ヶ sit 0x60 above ぁ..ゖ).
function _hira(ch) {
    var c = ch.charCodeAt(0)
    return (c >= 0x30A1 && c <= 0x30F6) ? String.fromCharCode(c - 0x60) : ch
}

// What a kana (or kana + its small partner) can be spelled as: ["shi", "si"]; null if it is not
// one the table knows.
function _spellings(base, small) {
    var row = ROW[base]
    if (!row) return null
    var cons = row[0], v = row[1]
    var out = []
    for (var i = 0; i < cons.length; i++) {
        var c = cons[i]
        if (small && SMALL_Y[small]) {
            // しゃ → sha / sya; き + ゃ → kya
            var yv = SMALL_Y[small]
            if (c === "sh" || c === "ch" || c === "j") out.push(c + yv)
            out.push((c === "sh" ? "s" : c === "ch" ? "t" : c === "j" ? "z" : c) + "y" + yv)
            if (c === "j") out.push("jy" + yv)
        } else if (small && SMALL_V[small]) {
            out.push(c + SMALL_V[small])               // ふぁ → fa, てぃ → ti
        } else {
            out.push(c + v)
        }
    }
    if (!small && PARTICLE[base]) out = out.concat(PARTICLE[base])
    return out
}

function _isKana(ch) {
    var c = ch.charCodeAt(0)
    return (c >= 0x3041 && c <= 0x3096) || (c >= 0x30A1 && c <= 0x30FA) || ch === "ー"
}
function _isHan(ch) {
    var c = ch.charCodeAt(0)
    return (c >= 0x4E00 && c <= 0x9FFF) || (c >= 0x3400 && c <= 0x4DBF)
}

// A unit's characters as ALIGNMENT SLOTS, in order:
//   { kind: "kana", spell: ["de"], unit }    a known mora
//   { kind: "n",    unit }                   ん (n, or m before b/p/m)
//   { kind: "unk",  unit }                   a kanji, or anything else: its reading is not known
// っ and ー have no mora of their own — a doubled consonant and a long vowel live in the mora
// before or after — so they make no slot and cost nothing.
function _slots(units) {
    var slots = []
    for (var u = 0; u < units.length; u++) {
        var t = String(units[u].text || "").replace(/\s+/g, "")
        for (var i = 0; i < t.length; i++) {
            var ch = t.charAt(i)
            var h = _hira(ch)
            if (h === "っ" || h === "ー" || SMALL_Y[h] || SMALL_V[h]) continue
            if (h === "ん") { slots.push({ kind: "n", unit: u }); continue }
            if (ROW[h]) {
                var small = i + 1 < t.length ? _hira(t.charAt(i + 1)) : ""
                var sp = _spellings(h, (SMALL_Y[small] || SMALL_V[small]) ? small : "")
                if (sp) { slots.push({ kind: "kana", spell: sp, unit: u, vowel: ROW[h][0][0] === "" && h !== "を" }); continue }
            }
            // CJK and general punctuation (、 。 ・ 「 」 — … ♪) has no reading: nothing to align.
            if (/[\u2000-\u206f\u2190-\u2bff\u3000-\u303f\uff00-\uff0f\uff1a-\uff20]/.test(ch)) continue
            if (_isKana(ch) || _isHan(ch) || /[^\x00-\x7f]/.test(ch)) { slots.push({ kind: "unk", unit: u }); continue }
            // Latin letters and digits inside a line pass through the romanizer unchanged.
            if (/[A-Za-z0-9]/.test(ch)) { slots.push({ kind: "unk", unit: u }); continue }
        }
    }
    return slots
}

function _matches(slot, mora) {
    if (!slot || !mora) return false
    if (slot.kind === "n") return mora.key === "n" || mora.key === "m"
    if (slot.kind !== "kana") return false
    for (var i = 0; i < slot.spell.length; i++)
        if (mora.key === slot.spell[i]) return true
    return false
}

// Words are kept: a romaji piece ends with a space when its mora ended its word.
function _textOf(ms) {
    var s = ""
    for (var i = 0; i < ms.length; i++) s += ms[i].text + (ms[i].wordEnd ? " " : "")
    return s
}

// ── Japanese ──────────────────────────────────────────────────────────────────
// text   the romanized line;  units  [{ text, at, d }] — the lead's syllables.
// → [{ text, at, d }] — one per syllable that has romaji, on that syllable's own timing.
function alignJa(text, units) {
    var ms = moras(text)
    if (ms.length === 0 || !units || units.length === 0) return []
    var slots = _slots(units)
    if (slots.length === 0) return []

    var M = ms.length
    var got = []                       // per unit: the moras it was given
    for (var u = 0; u < units.length; u++) got.push([])
    var p = 0
    var last = -1                      // the unit that last received a mora
    var i = 0

    function give(unit, from, to) {
        for (var k = from; k < to; k++) got[unit].push(ms[k])
        if (to > from) last = unit
    }

    while (i < slots.length) {
        var s = slots[i]

        if (s.kind === "unk") {
            // A run of kanji, up to the next anchor.
            var g = 0
            while (i + g < slots.length && slots[i + g].kind === "unk") g++
            var next = slots[i + g]
            var take

            if (!next) {
                take = M - p
            } else {
                var best = -1, bestCost = 1e9
                var lo = p + g, hi = Math.min(M - 1, p + 3 * g + 2)
                for (var q = lo; q <= hi; q++) {
                    if (!_matches(next, ms[q])) continue
                    // Two anchors in a row are better evidence than one.
                    var after = slots[i + g + 1]
                    var bonus = (after && after.kind !== "unk" && _matches(after, ms[q + 1])) ? -1.5 : 0
                    var cost = Math.abs(q - (p + 2 * g)) + bonus
                    if (cost < bestCost) { bestCost = cost; best = q }
                }
                take = best >= 0 ? best - p : Math.max(g, Math.min(M - p, 2 * g))
            }
            take = Math.max(0, Math.min(take, M - p))

            // Shared out as evenly as they divide; the first kanji takes the remainder.
            var base = Math.floor(take / g), rem = take % g
            for (var k = 0; k < g; k++) {
                var cnt = base + (k < rem ? 1 : 0)
                give(slots[i + k].unit, p, p + cnt)
                p += cnt
            }
            i += g
            continue
        }

        // A known mora: it takes its own, if that is what comes next.
        if (p < M && _matches(s, ms[p])) { give(s.unit, p, p + 1); p++; i++; continue }

        // A vowel with no mora of its own: the long vowel before it already holds it (a macron,
        // or the same vowel doubled), so it takes nothing.
        if (s.kind === "kana" && s.vowel && p > 0
                && (_hasMacron(ms[p - 1].text) || ms[p - 1].key.slice(-1) === _plainVowelOf(s))) {
            i++
            continue
        }

        // Out of step: the next anchor is a mora or two ahead, and what lies between belongs to
        // whoever came before (a doubled vowel — "kaa" for カー — or an extra syllable).
        var found = -1
        for (var a = p + 1; a <= Math.min(M - 1, p + 2); a++) if (_matches(s, ms[a])) { found = a; break }
        if (found >= 0) {
            give(last >= 0 ? last : s.unit, p, found)
            p = found
            give(s.unit, p, p + 1); p++; i++
            continue
        }

        // Nothing matches: take what is there, so the line still reads.
        if (p < M) { give(s.unit, p, p + 1); p++ }
        i++
    }
    // Whatever romaji is left belongs on the last syllable that had any.
    if (p < M) give(last >= 0 ? last : units.length - 1, p, M)

    var out = []
    for (var w = 0; w < units.length; w++) {
        if (got[w].length === 0) continue
        out.push({ text: _textOf(got[w]), at: units[w].at || 0, d: units[w].d > 0 ? units[w].d : 0 })
    }
    // The line's last piece has no word after it.
    if (out.length) out[out.length - 1].text = out[out.length - 1].text.replace(/\s+$/, "")
    return out
}

function _plainVowelOf(slot) {
    // The vowel a vowel-only kana spells (あ → a, う → u).
    var sp = slot.spell && slot.spell[0]
    return sp ? sp.charAt(sp.length - 1) : ""
}

// ── Hangul, Chinese and the rest ──────────────────────────────────────────────
// One character is one syllable, and the romanization has one piece per syllable: paired in
// order. `pieces` is the romanization already cut into syllables by the caller's rule.
function _pairInOrder(pieces, units, weightOf) {
    if (pieces.length === 0 || !units || units.length === 0) return []
    var total = 0
    var ws = []
    for (var u = 0; u < units.length; u++) {
        var w = weightOf(String(units[u].text || ""))
        ws.push(w)
        total += w
    }
    if (total === 0) return []

    var out = []
    var cum = 0
    var from = 0
    for (var k = 0; k < units.length; k++) {
        cum += ws[k]
        var to = k === units.length - 1 ? pieces.length : Math.round(pieces.length * cum / total)
        if (to > from) {
            var txt = ""
            for (var j = from; j < to; j++) txt += pieces[j].text + (pieces[j].wordEnd ? " " : "")
            out.push({ text: txt, at: units[k].at || 0, d: units[k].d > 0 ? units[k].d : 0 })
            from = to
        }
    }
    if (out.length) out[out.length - 1].text = out[out.length - 1].text.replace(/\s+$/, "")
    return out
}

// Pinyin: initial + final (+ n / ng / r), one syllable each; tone marks stay on the vowel.
var PINYIN = /(?:zh|ch|sh|[bpmfdtnlgkhjqxzcsryw])?[aeiouüvāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜ]+(?:ng|n|r)?(?![aeiouüvāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜ])/gi

function _pinyinPieces(text) {
    var out = []
    var words = String(text || "").split(/\s+/).filter(function (w) { return w !== "" })
    for (var i = 0; i < words.length; i++) {
        var m = words[i].match(PINYIN)
        if (!m) { out.push({ text: words[i], wordEnd: true }); continue }
        for (var k = 0; k < m.length; k++) out.push({ text: m[k], wordEnd: k === m.length - 1 })
    }
    return out
}

// Each character of the line weighs the same.
function _perChar(t) { return t.replace(/\s+/g, "").length }

// A romanized line cut into its LETTERS, for scripts where nothing better is known (Cyrillic,
// Greek, Thai, Arabic, Hebrew, Hangul): each original character gets the share of the letters
// its own share of the line is worth.
function _letterPieces(text) {
    var out = []
    var words = String(text || "").split(/\s+/).filter(function (w) { return w !== "" })
    for (var i = 0; i < words.length; i++)
        for (var k = 0; k < words[i].length; k++)
            out.push({ text: words[i].charAt(k), wordEnd: k === words[i].length - 1 })
    return out
}

function alignEven(text, units, script) {
    if (script === "zh") return _pairInOrder(_pinyinPieces(text), units, _perChar)
    return _pairInOrder(_letterPieces(text), units, _perChar)
}

// ── The entry point ───────────────────────────────────────────────────────────
// script: the language code romanize.js reports ("ja", "ko", "zh", "ru", …).
function align(text, units, script) {
    if (script === "ja") {
        var r = alignJa(text, units)
        if (r.length > 0) return r
    }
    return alignEven(text, units, script)
}
