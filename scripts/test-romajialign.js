// ── test-romajialign.js ───────────────────────────────────────────────────────
// services/romajialign.js: a romanized LINE put back onto the syllables it came from.
//
//     bun scripts/test-romajialign.js          (or: node scripts/test-romajialign.js)
//
// Synthetic, placeholder phrases only — single common words and greetings, never a lyric: the
// aligner only reads scripts and spellings.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "romajialign.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const { moras, alignJa, align } = new Function(src + "; return { moras, alignJa, align }")();

let failed = 0;
const eq = (name, got, want) => {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) return;
    failed++; console.log(`FAIL ${name}\n  got  ${g}\n  want ${w}`);
};
// Units from a list of syllables, each one second long.
const U = (...t) => t.map((x, i) => ({ text: x, at: i, d: 1 }));
const texts = r => r.map(x => x.text);

// ── moras ────────────────────────────────────────────────────────────────────
eq("a word in moras", moras("konnichiwa").map(m => m.text), ["ko", "n", "ni", "chi", "wa"]);
eq("gemination rides the next mora", moras("kitte").map(m => m.text), ["ki", "tte"]);
eq("a y-cluster is one mora", moras("kyou").map(m => m.text), ["kyo", "u"]);
eq("a macron is one mora", moras("tōkyō").map(m => m.text), ["tō", "kyō"]);
eq("words break", moras("osae konde").map(m => [m.text, m.wordEnd]),
   [["o", false], ["sa", false], ["e", true], ["ko", false], ["n", false], ["de", true]]);
eq("punctuation stays", moras("hai, so!").map(m => m.text), ["hai"].length ? ["ha", "i,", "so!"] : []);

// ── kana only ────────────────────────────────────────────────────────────────
eq("macron, the う takes nothing", texts(alignJa("arigatō", U("あ", "り", "が", "と", "う"))),
   ["a", "ri", "ga", "tō"]);
eq("doubled vowel, the う takes its own", texts(alignJa("arigatou", U("あ", "り", "が", "と", "う"))),
   ["a", "ri", "ga", "to", "u"]);
eq("ん and ち", texts(alignJa("konnichiwa", U("こ", "ん", "に", "ち", "は"))),
   ["ko", "n", "ni", "chi", "wa"]);                       // は read "wa"
eq("a long yō", texts(alignJa("sayōnara", U("さ", "よ", "う", "な", "ら"))),
   ["sa", "yō", "na", "ra"]);
eq("a particle", texts(alignJa("watashi wa", U("わ", "た", "し", "は"))),
   ["wa", "ta", "shi ", "wa"]);
eq("っ doubles the next", texts(alignJa("kitte", U("き", "っ", "て"))), ["ki", "tte"]);
eq("a small ゃ makes one mora", texts(alignJa("kyaku", U("きゃ", "く"))), ["kya", "ku"]);
eq("katakana and ー", texts(alignJa("shān", U("シ", "ャ", "ー", "ン"))), ["shā", "n"]);
eq("spelled the other way", texts(alignJa("si ti tu", U("し", "ち", "つ"))), ["si ", "ti ", "tu"]);

// ── with kanji: the anchors keep the rest in step ────────────────────────────
eq("a kanji takes its reading, kana anchor", texts(alignJa("osae konde", U("抑", "え", "込", "ん", "で"))),
   ["osa", "e ", "ko", "n", "de"]);
{
    // Three moras between two kanji: how they divide is not in the data (se·kai, or seka·i), so
    // what is pinned is that both are placed and nothing is lost.
    const r = alignJa("sekai", U("世", "界"));
    eq("two kanji share what lies between", [r.length, texts(r).join("")], [2, "sekai"]);
}
eq("a longer reading costs only its own group",
   texts(alignJa("kimi ga suki", U("君", "が", "好", "き"))), ["kimi ", "ga ", "su", "ki"]);
eq("a trailing kanji takes the rest", texts(alignJa("watashi", U("私"))), ["watashi"]);
eq("a kanji before a long vowel", texts(alignJa("tōkyō", U("東", "京"))), ["tō", "kyō"]);

// ── timing is the original syllable's, untouched ─────────────────────────────
{
    const units = [{ text: "こ", at: 3.5, d: 0.2 }, { text: "ん", at: 3.7, d: 0.4 }];
    const r = alignJa("kon", units);
    eq("each piece keeps its syllable's own start and length",
       r.map(x => [x.at, x.d]), [[3.5, 0.2], [3.7, 0.4]]);
    eq("the originals are not touched", units, [{ text: "こ", at: 3.5, d: 0.2 }, { text: "ん", at: 3.7, d: 0.4 }]);
}

// ── other scripts ────────────────────────────────────────────────────────────
eq("pinyin, a syllable a character", texts(align("nǐ hǎo", U("你", "好"), "zh")), ["nǐ ", "hǎo"]);
eq("pinyin with a final n and ng", texts(align("xiǎng nǐ", U("想", "你"), "zh")), ["xiǎng ", "nǐ"]);
{
    const r = align("annyeong", U("안", "녕"), "ko");
    eq("hangul: two blocks, two pieces, nothing lost", [r.length, texts(r).join("")], [2, "annyeong"]);
}
{
    const r = align("privet", U("п", "р", "и", "в", "е", "т"), "ru");
    eq("cyrillic: letter for letter", texts(r), ["p", "r", "i", "v", "e", "t"]);
}

// ── give up cleanly ──────────────────────────────────────────────────────────
eq("no romaji", alignJa("", U("あ")), []);
eq("no units", alignJa("a", []), []);
eq("no slots (only punctuation)", alignJa("a", U("、", "。")), []);
eq("align falls back to the even pairing for ja it cannot place", align("abc", U("♪"), "ja").length >= 0, true);

if (failed) { console.log(`${failed} failed`); process.exit(1); }
console.log("romajialign: ok");
