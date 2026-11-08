.pragma library

// ── romanize.js ───────────────────────────────────────────────────────────────
// Does this song have anything to romanize? (bun scripts/test-romanize.js)
//
// The Now Playing toggle for romanization appears only on a song that has some — a song in
// English has nothing to show and a switch for it would be noise — so the question is asked of
// the lyrics themselves, by writing system, with no network and no library: the same cheap
// signal scripts/lyrics-translate.py's detect() uses, kept in step with the set
// scripts/lyrics-romanize.py will actually accept (ROMANIZABLE there).
//
// Kana decide Japanese before ideographs are looked at (Japanese uses both, Chinese only the
// latter — the same order translate's detector keeps, for the same reason).
// ─────────────────────────────────────────────────────────────────────────────

var KANA     = /[぀-ヿ]/g
var HANGUL   = /[가-힯ᄀ-ᇿ]/g
var HAN      = /[一-鿿㐀-䶿]/g
var CYRILLIC = /[Ѐ-ӿ]/g
var GREEK    = /[Ͱ-Ͽ]/g
var THAI     = /[฀-๿]/g
var ARABIC   = /[؀-ۿ]/g
var HEBREW   = /[֐-׿]/g
var LETTER   = /[A-Za-zÀ-ɏ]/g    // Latin, with its accents

// A script has to carry this much of the song's letters to count — a Japanese word in an
// English song, or an English refrain in a Japanese one, decides nothing.
var SHARE = 0.25

function _count(text, re) {
    var m = text.match(re)
    return m ? m.length : 0
}

// The language code of the song's non-Latin script ("ja" "ko" "zh" "ru" "el" "th" "ar" "he"),
// or "" when it has none worth romanizing.
function scriptOf(lines) {
    if (!lines || lines.length === 0) return ""
    var text = lines.join("\n")

    var kana = _count(text, KANA)
    var han  = _count(text, HAN)
    var tally = {
        ja: kana + (kana > 0 ? han : 0),        // ideographs with kana are Japanese
        zh: kana > 0 ? 0 : han,
        ko: _count(text, HANGUL),
        ru: _count(text, CYRILLIC),
        el: _count(text, GREEK),
        th: _count(text, THAI),
        ar: _count(text, ARABIC),
        he: _count(text, HEBREW)
    }
    var latin = _count(text, LETTER)

    var best = "", bestN = 0, total = latin
    for (var k in tally) {
        total += tally[k]
        if (tally[k] > bestN) { best = k; bestN = tally[k] }
    }
    if (bestN === 0 || total === 0) return ""
    return bestN / total >= SHARE ? best : ""
}
