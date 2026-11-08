// ── test-romanize.js ──────────────────────────────────────────────────────────
// services/romanize.js: does a song have anything to romanize, and in which script.
//
//     bun scripts/test-romanize.js          (or: node scripts/test-romanize.js)
//
// Synthetic, placeholder text only (single words) — the detector only reads scripts.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "romanize.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const { scriptOf } = new Function(src + "; return { scriptOf }")();

let failed = 0;
const eq = (name, got, want) => {
    if (got === want) return;
    failed++; console.log(`FAIL ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
};

eq("kana and kanji are Japanese",      scriptOf(["こんにちは", "世界"]), "ja");
eq("kanji alone is Chinese",           scriptOf(["你好", "世界"]), "zh");
eq("kanji beside kana is NOT Chinese", scriptOf(["世界", "さようなら"]), "ja");
eq("hangul is Korean",                 scriptOf(["안녕하세요"]), "ko");
eq("cyrillic is Russian",              scriptOf(["Привет", "мир"]), "ru");
eq("greek",                            scriptOf(["Γειά σου"]), "el");
eq("thai",                             scriptOf(["สวัสดี"]), "th");
eq("arabic",                           scriptOf(["مرحبا"]), "ar");
eq("hebrew",                           scriptOf(["שלום"]), "he");

eq("English has nothing",              scriptOf(["Hello", "world again"]), "");
eq("accented Latin has nothing",       scriptOf(["Bonjour mon âme", "señor"]), "");
eq("punctuation has nothing",          scriptOf(["♪ ...!", ""]), "");
eq("empty and null",                   scriptOf([]) + scriptOf(null), "");

// A song is its dominant script: a little of the other does not decide it either way.
eq("an English refrain in a Japanese song", scriptOf(["こんにちは世界", "さようなら", "Hello"]), "ja");
eq("one Japanese word in an English song",  scriptOf(["Hello there my friend", "and you again", "ねえ"]), "");

if (failed) { console.log(`${failed} failed`); process.exit(1); }
console.log("romanize: ok");
