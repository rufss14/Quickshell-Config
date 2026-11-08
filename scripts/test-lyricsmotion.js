// ── test-lyricsmotion.js ──────────────────────────────────────────────────────
// Regression tests for services/lyricsmotion.js, the lyrics phrasing engine.
//
//     bun scripts/test-lyricsmotion.js          (or: node scripts/test-lyricsmotion.js)
//
// Safe to run: lyricsmotion.js is pure functions and touches nothing — no network, no
// disk, no player.
//
// All fixtures below are SYNTHETIC timing data with placeholder text. The engine only
// ever looks at numbers (a duration, a gap), so there is nothing to gain from real
// lyrics and no reason to keep any in the repo.
//
// The cases that matter are the degenerate ones. Real yrc data contains words with no
// duration, lines that overlap the line before them, and songs whose last line has no
// successor to measure against — and every one of those, left alone, produces motion
// that looks like a bug rather than a style.
//
// lyricsmotion.js is loaded by stripping its `.pragma library` line (a QML directive
// that isn't valid JS) and evaluating the rest, so the tests run against the real file
// rather than a copy that can drift. Same approach as test-calc.js.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "lyricsmotion.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");

const M = new Function(
    src + "\nreturn { sustain, wordMotion, structure, interlude, lineEnd," +
          " syllables, syllabify, groupWords, isCjk, lineUnits, withInterludes, interludeAt, retimeWords };"
)();

let pass = 0, fail = 0;
function check(name, cond, detail) {
    if (cond) { pass++; }
    else { fail++; console.log(`  FAIL  ${name}${detail ? "  — " + detail : ""}`); }
}
function near(a, b, eps = 1e-6) { return Math.abs(a - b) <= eps; }

// ── sustain ───────────────────────────────────────────────────────────────────
console.log("sustain");
check("clipped word floors at 0", M.sustain(0.05) === 0);
check("held word ceils at 1", M.sustain(2.0) === 1);
check("midpoint ramps", M.sustain((0.12 + 0.90) / 2) > 0.49 && M.sustain((0.12 + 0.90) / 2) < 0.51);

// Unknown duration must NOT collapse to 0 — that made every line-only song animate as
// staccato, which is a confident claim about data we do not have.
check("undefined duration is mid, not zero", M.sustain(undefined) === 0.4);
check("zero duration is mid, not zero", M.sustain(0) === 0.4);
check("negative duration is mid, not zero", M.sustain(-3) === 0.4);
check("NaN duration is mid, not zero", M.sustain(NaN) === 0.4);
check("non-numeric duration is mid", M.sustain("0.5") === 0.4);

// ── wordMotion ────────────────────────────────────────────────────────────────
console.log("wordMotion");
const short = M.wordMotion(0.08, 1);
const long  = M.wordMotion(1.30, 1);

check("held word rises further", long.rise > short.rise);
check("held word pops harder", long.pop > short.pop);
check("held word rides the wave higher", long.waveGain > short.waveGain);

// A short word has to be lit almost immediately or it is over before the animation lands.
check("short attack is fast", short.attack <= 100, `attack=${short.attack}`);
check("attack never below floor", M.wordMotion(0.001, 1).attack >= 60);
check("attack never above ceiling", M.wordMotion(99, 1).attack <= 380);
check("release never below floor", M.wordMotion(0.001, 1).release >= 160);
check("release never above ceiling", M.wordMotion(99, 1).release <= 700);

// Intensity scales amplitude, never timing — a subtle setting should be quieter, not
// slower, or the motion stops tracking the vocal.
const bold   = M.wordMotion(0.8, 1);
const subtle = M.wordMotion(0.8, 0);
check("subtle reduces rise", subtle.rise < bold.rise);
check("subtle reduces pop", subtle.pop < bold.pop);
check("intensity leaves attack alone", subtle.attack === bold.attack);
check("intensity leaves release alone", subtle.release === bold.release);
check("intensity clamps above 1", M.wordMotion(0.8, 5).rise === bold.rise);
check("intensity clamps below 0", M.wordMotion(0.8, -5).rise === subtle.rise);
check("missing intensity defaults to bold", M.wordMotion(0.8).rise === bold.rise);

// Unknown duration must still produce sane timings, not NaN.
const unknown = M.wordMotion(undefined, 1);
check("unknown duration gives finite attack", Number.isFinite(unknown.attack));
check("unknown duration gives finite release", Number.isFinite(unknown.release));
check("unknown duration attack in range", unknown.attack >= 60 && unknown.attack <= 380);

// ── lineEnd ───────────────────────────────────────────────────────────────────
console.log("lineEnd");
check("uses real duration when present", M.lineEnd({ t: 10, dur: 2.5 }, { t: 20 }) === 12.5);
check("null line is 0", M.lineEnd(null, null) === 0);

// The trap: a line must NOT be assumed to run until the next one starts, or every gap
// is zero and no line-only song can contain a detectable break.
check("does not stretch to the next line", M.lineEnd({ t: 10, dur: 0 }, { t: 20 }) < 20);
check("caps at the next line when it is close",
      M.lineEnd({ t: 10, dur: 0 }, { t: 10.5 }) === 10.5);
check("last line gets a nominal tail", M.lineEnd({ t: 10, dur: 0 }, null) === 13);

// Longer text is assumed to take longer to sing.
const shortTxt = M.lineEnd({ t: 0, dur: 0, text: "aaaa" }, { t: 99 });
const longTxt  = M.lineEnd({ t: 0, dur: 0, text: "a".repeat(60) }, { t: 99 });
check("longer text ends later", longTxt > shortTxt);
check("text estimate has a floor", shortTxt >= 0.8);
check("text estimate has a ceiling", longTxt <= 5.0);
check("estimates from words when text is absent",
      M.lineEnd({ t: 0, dur: 0, words: [{ text: "aaaa" }, { text: "bbbb" }] }, { t: 99 }) >= 0.8);

// ── structure ─────────────────────────────────────────────────────────────────
console.log("structure");
check("empty input is empty", M.structure([]).length === 0);
check("null input is empty", M.structure(null).length === 0);

// Placeholder timing fixture: an intro, two continuous lines, a breath, then a solo.
const lines = [
    { t: 5.0,  dur: 2.0, text: "placeholder one" },   // open  (5s of intro)
    { t: 7.1,  dur: 2.0, text: "placeholder two" },   // flow  (0.1s gap)
    { t: 11.0, dur: 2.0, text: "placeholder three" }, // pause (1.9s gap)
    { t: 20.0, dur: 2.0, text: "placeholder four" },  // break (7.0s gap)
];
const st = M.structure(lines);

check("first line is open", st[0].kind === "open");
check("continuous line is flow", st[1].kind === "flow");
check("breath is pause", st[2].kind === "pause");
check("solo is break", st[3].kind === "break");
check("flow earns no entrance", st[1].entrance === 0);
check("break out-entrances pause", st[3].entrance > st[2].entrance);
check("entrance stays within 0..1", st.every(s => s.entrance >= 0 && s.entrance <= 1));
check("gap measured from line END not start", near(st[1].gapBefore, 0.1, 1e-9),
      `got ${st[1].gapBefore}`);

// Overlapping timings are real in yrc data. A negative gap must clamp, not propagate —
// otherwise it reads as an enormous entrance on a line that never paused.
const overlap = M.structure([
    { t: 5.0, dur: 5.0 },
    { t: 7.0, dur: 2.0 },   // starts 3s BEFORE the previous line ends
]);
check("overlap clamps gap to 0", overlap[1].gapBefore === 0);
check("overlap is flow, not break", overlap[1].kind === "flow");
check("overlap earns no entrance", overlap[1].entrance === 0);

// A provider with no durations at all must still classify.
const noDur = M.structure([{ t: 0, dur: 0 }, { t: 9, dur: 0 }]);
check("no-duration lines still classify", noDur[1].kind === "break");

// ── interlude ─────────────────────────────────────────────────────────────────
console.log("interlude");
check("silent before first line", M.interlude(lines, st, 1.0).active === false);
check("inactive mid-line", M.interlude(lines, st, 5.5).active === false);
check("inactive during a short pause", M.interlude(lines, st, 9.5).active === false);
check("inactive past the last line", M.interlude(lines, st, 99).active === false);
check("empty input is inactive", M.interlude([], [], 5).active === false);
check("null input is inactive", M.interlude(null, null, 5).active === false);

// The solo runs from the end of line 3 (13.0) to the start of line 4 (20.0).
const solo = M.interlude(lines, st, 16.5);
check("active during the solo", solo.active === true);
check("solo progress is fractional", near(solo.progress, (16.5 - 13.0) / 7.0, 1e-9),
      `got ${solo.progress}`);
check("solo remaining counts down", near(solo.remaining, 3.5, 1e-9));
check("progress clamps at the far end", M.interlude(lines, st, 19.999).progress <= 1);
check("progress never negative", M.interlude(lines, st, 13.0).progress >= 0);

// ── countdown ─────────────────────────────────────────────────────────────────
// Anchored to the END of the gap, not spread across it. `progress` across a long intro
// gave each dot ten seconds of imperceptible creep; the countdown always represents the
// final stretch, so the dots mean the same thing whatever the gap's length.
console.log("countdown");
check("countdown is 0 at the start of a long gap",
      M.interlude(lines, st, 13.0).countdown === 0);
check("countdown reaches 1 as the vocal returns",
      M.interlude(lines, st, 19.999).countdown > 0.99);
check("countdown rises monotonically",
      M.interlude(lines, st, 18).countdown > M.interlude(lines, st, 16).countdown);
check("countdown stays within 0..1",
      [13.5, 15, 17, 19.9].every(c => {
          const v = M.interlude(lines, st, c).countdown;
          return v >= 0 && v <= 1;
      }));

// A gap SHORTER than the countdown window starts part-filled — there really is less time
// left, and pretending otherwise would make the dots race.
const shortGap = [
    { t: 0,   dur: 1, text: "a" },
    { t: 6.0, dur: 1, text: "b" }     // 5s gap, under the 9s window
];
const shortSt = M.structure(shortGap);
check("short gap still counts down",
      M.interlude(shortGap, shortSt, 3).countdown > 0);
check("short gap still reaches 1",
      M.interlude(shortGap, shortSt, 5.99).countdown > 0.99);

// ── syllables ─────────────────────────────────────────────────────────────────
// Ordinary dictionary words, chosen to hit the split rules. The engine only ever sees
// characters, so there is nothing to gain from anything more specific.
console.log("syllables");

// THE invariant: the pieces must rebuild the input exactly. A split that quietly drops a
// character edits the lyric on screen, which is far worse than a linguistically wrong cut.
const words = [
    "beautiful", "running", "table", "open", "corner", "poem", "time", "sky",
    "rhythm", "a", "I", "the", "strength", "elephant", "under", "away",
    "hello,", "world!", "don't", "  ", "…", "", "café", "naïve"
];
let joinOk = true;
for (const w of words) {
    const parts = M.syllables(w);
    if (parts.join("") !== w) {
        joinOk = false;
        console.log(`    lost text: ${JSON.stringify(w)} -> ${JSON.stringify(parts)}`);
    }
}
check("pieces always rebuild the input", joinOk);
check("empty string yields no pieces", M.syllables("").length === 0);
check("non-string yields no pieces", M.syllables(null).length === 0);
check("no piece is ever empty",
      words.every(w => M.syllables(w).every(p => p.length > 0)));
check("punctuation-only stays whole", M.syllables("…").length === 1);
check("whitespace-only stays whole", M.syllables("  ").length === 1);

// Counts. Approximate by design — these assert the split HAPPENED, not that a linguist
// would agree with it.
check("multi-syllable word splits", M.syllables("beautiful").length >= 2);
check("single-vowel word stays whole", M.syllables("sky").length === 1);
check("vowelless word stays whole", M.syllables("rhythm").length === 1);
check("silent final e does not split off", M.syllables("time").length === 1);
check("consonant+le keeps its own syllable", M.syllables("table").length === 2);
check("VCCV splits inside the run", M.syllables("corner")[0] === "cor");
check("VCV gives the consonant to the next", M.syllables("open")[0] === "o");

// ── syllabify ─────────────────────────────────────────────────────────────────
console.log("syllabify");
check("empty input is empty", M.syllabify([]).length === 0);
check("null input is empty", M.syllabify(null).length === 0);

const units = M.syllabify([{ text: "beautiful", at: 10, d: 1.2 }]);
check("word expands to several units", units.length >= 2);
check("units rebuild the word", units.map(u => u.text).join("") === "beautiful");
check("first unit starts with the word", near(units[0].at, 10, 1e-9));
check("units advance in time", units.every((u, i) => i === 0 || u.at >= units[i - 1].at));
check("durations sum to the word's", near(units.reduce((a, u) => a + u.d, 0), 1.2, 1e-9));
check("first is flagged first", units[0].first === true && units[0].last === false);
check("last is flagged last", units[units.length - 1].last === true);

// Spacing lives in the text ("Feels " carries its trailing space) and must survive, or
// the words run together on screen.
const spaced = M.syllabify([{ text: "under ", at: 0, d: 1 }]);
check("trailing space survives the split",
      spaced.map(u => u.text).join("") === "under ");

// A word with no duration must not invent one for its pieces.
const noDurUnits = M.syllabify([{ text: "beautiful", at: 5, d: 0 }]);
check("no duration stays no duration", noDurUnits.every(u => u.d === 0));
check("no duration keeps every unit at the word's start",
      noDurUnits.every(u => u.at === 5));

// Single-syllable words pass through flagged as both ends, so the view can treat every
// unit uniformly.
const one = M.syllabify([{ text: "sky", at: 1, d: 0.5 }]);
check("single-syllable word is one unit", one.length === 1);
check("single-syllable is both first and last", one[0].first && one[0].last);

// ── groupWords ────────────────────────────────────────────────────────────────
// The card wraps long lines so the type size can stay fixed, and a wrap must never land
// inside a word. Grouping is by trailing space, which both sources already encode.
console.log("groupWords");
check("empty input is empty", M.groupWords([]).length === 0);
check("null input is empty", M.groupWords(null).length === 0);

// "un-der " + "o-ver" — two words, four syllables.
const grouped = M.groupWords([
    { text: "un" }, { text: "der " },
    { text: "o" },  { text: "ver" }
]);
check("groups into two words", grouped.length === 2);
check("first word keeps its syllables", grouped[0].length === 2);
check("second word keeps its syllables", grouped[1].length === 2);
check("no syllable is lost",
      grouped.flat().map(u => u.text).join("") === "under over");

// A line's last word has no trailing space and must still close.
check("final word closes without a space",
      M.groupWords([{ text: "un" }, { text: "der " }, { text: "last" }]).length === 2);

// ── Scripts with no spaces ────────────────────────────────────────────────────
// Japanese and Chinese lines carry no whitespace, so grouping by trailing space swept a
// whole line into ONE group — which the flow refuses to break inside, so the line ran off
// the card and the layout pass counted it as a single row while it rendered as several.
// Breaking between characters is correct for those scripts anyway.
const noSpaces = M.groupWords([{ text: "あ" }, { text: "い" }, { text: "う" }]);
check("space-free line breaks per unit", noSpaces.length === 3);
check("space-free grouping keeps every unit",
      noSpaces.reduce((n, g) => n + g.length, 0) === 3);
check("space-free groups hold one unit each",
      noSpaces.every(g => g.length === 1));

// ── Mixed scripts ─────────────────────────────────────────────────────────────
// The test is PER UNIT, not per line. A line mixing Japanese with an English phrase does
// contain spaces, so a whole-line test concluded "this line uses spacing" and swept the
// Japanese run into one unbreakable group — which then ran off the right edge.
// Two CJK units, then one latin word split across two syllables. Each CJK character is
// its own break opportunity; the latin syllables stay welded into one word.
const mixed = M.groupWords([
    { text: "あ" }, { text: "い" },
    { text: "Lea" }, { text: "ve " }
]);
check("CJK units stay separate in a mixed line", mixed.length === 3);
check("latin syllables still weld into one word",
      mixed[2].map(u => u.text).join("") === "Leave ");
check("mixed grouping keeps every unit",
      mixed.reduce((n, g) => n + g.length, 0) === 4);
check("each CJK unit is alone in its group",
      mixed[0].length === 1 && mixed[1].length === 1);

// A latin word must not be swallowed into a following CJK unit's group.
const boundary = M.groupWords([{ text: "end" }, { text: "あ" }]);
check("pending latin closes before a CJK unit", boundary.length === 2);
check("latin group keeps its text", boundary[0].map(u => u.text).join("") === "end");

check("isCjk detects kana", M.isCjk("あ") === true);
check("isCjk detects ideographs", M.isCjk("神") === true);
check("isCjk detects hangul", M.isCjk("한") === true);
check("isCjk is false for latin", M.isCjk("Leave ") === false);
check("isCjk is false for empty", M.isCjk("") === false);
check("isCjk is false for punctuation", M.isCjk("...") === false);

// Single-syllable words.
check("single-syllable words group one each",
      M.groupWords([{ text: "one " }, { text: "two " }, { text: "three" }]).length === 3);

// Every unit must land in exactly one group — a dropped syllable is a dropped piece of
// the lyric, and a duplicated one renders twice.
const many = [{ text: "a" }, { text: "b " }, { text: "c" }, { text: "d " }, { text: "e" }];
check("every unit lands in exactly one group",
      M.groupWords(many).reduce((n, g) => n + g.length, 0) === many.length);

// ── lineUnits: spacing belongs to the source, never to the card ──────────────
// The Spicy Lyrics mapper's own shape for "ex-am-ple one": no space inside a word.
const spicy = M.lineUnits([{ text: "ex", t: 1, d: 0.2 }, { text: "am", t: 1.2, d: 0.2 },
                           { text: "ple ", t: 1.4, d: 0.3 }, { text: "one", t: 2, d: 0.4 }]);
check("syllables inside a word get no space",
      spicy.map(u => u.text).join("") === "example one", spicy.map(u => u.text).join("|"));
check("timing is renamed t -> at", spicy[0].at === 1 && spicy[2].at === 1.4 && spicy[3].d === 0.4);

const yrc = M.lineUnits([{ text: "Feels ", t: 0, d: 0.5 }, { text: "like", t: 0.5, d: 0.5 }]);
check("yrc words keep their own trailing space", yrc.map(u => u.text).join("") === "Feels like");

const sep = M.lineUnits([{ text: "one", t: 0, d: 1 }, { text: " ", t: 1, d: 0 }, { text: "two", t: 1, d: 1 }]);
check("a whitespace-only unit is dropped but its space survives",
      sep.length === 2 && sep.map(u => u.text).join("") === "one two");
check("a leading whitespace-only unit is dropped", M.lineUnits([{ text: " ", t: 0, d: 0 }]).length === 0);
check("no words is no units", M.lineUnits(null).length === 0 && M.lineUnits([]).length === 0);

// The input belongs to the service: Lyrics.lines is shared and re-applied on an upgrade.
const shared = [{ text: "a", t: 0, d: 1 }, { text: " ", t: 1, d: 0 }];
M.lineUnits(shared);
check("input is not mutated", shared[0].text === "a");

// ── interludes as rows ────────────────────────────────────────────────────────
console.log("withInterludes");
const L = (t, dur, text = "x") => ({ t, dur, text, words: null });

// A long silence between two lines gets a row exactly filling it.
{
    const out = M.withInterludes([L(1, 2), L(30, 2)]);
    check("a 27s gap adds a row", out.length === 3 && out[1].interlude === true);
    check("it starts where the line ends", near(out[1].t, 3));
    check("and fills the gap", near(out[1].t + out[1].dur, 30));
    check("the sung lines are untouched, in order", out[0].t === 1 && out[2].t === 30);
}
// A short gap (a breath) gets nothing.
check("a 2s gap adds nothing", M.withInterludes([L(1, 2), L(5, 2)]).length === 2);
// The intro counts: dots from the start of the track.
{
    const out = M.withInterludes([L(12, 2)]);
    check("a long intro adds a row at 0", out.length === 2 && out[0].interlude && near(out[0].t, 0) && near(out[0].dur, 12));
}
check("a short intro adds nothing", M.withInterludes([L(2, 2)]).length === 1);
// A provider's own blank row is taken over, not doubled.
{
    const out = M.withInterludes([L(1, 2), { t: 3, dur: 0, text: "", words: null }, L(30, 2)]);
    check("a blank row spanning the gap becomes the interlude", out.length === 3 && out[1].interlude && near(out[1].dur, 27));
}
{
    const out = M.withInterludes([L(1, 2), { t: 3, dur: 0, text: "", words: null }, L(5, 2)]);
    check("a short blank row stays a blank row", out.length === 3 && !out[1].interlude);
}
// Never mutates what it is given.
{
    const src = [L(1, 2), L(30, 2)];
    M.withInterludes(src);
    check("input is not mutated", src.length === 2 && !("interlude" in src[0]));
}
check("empty and null input", M.withInterludes([]).length === 0 && M.withInterludes(null).length === 0);
// A row it inserted is not inserted again if the list is run through twice (an upgrade re-applies).
{
    const once = M.withInterludes([L(1, 2), L(30, 2)]);
    const twice = M.withInterludes(once);
    check("idempotent", twice.length === once.length);
}

// structure() with interludes: the line after one is still the one with the entrance.
{
    const rows = M.withInterludes([L(1, 2), L(30, 2)]);
    const st2 = M.structure(rows);
    check("the interlude row has no entrance of its own", st2[1].kind === "interlude" && st2[1].entrance === 0);
    check("the line after it is a break", st2[2].kind === "break" && st2[2].entrance > 0.5);
}

// interludeAt: how far through the dots.
{
    const row = { t: 12, dur: 18, interlude: true };
    check("start", near(M.interludeAt(row, 12).progress, 0));
    check("halfway", near(M.interludeAt(row, 21).progress, 0.5) && near(M.interludeAt(row, 21).remaining, 9));
    check("end", near(M.interludeAt(row, 30).progress, 1));
    check("clamped before and after", M.interludeAt(row, 0).progress === 0 && M.interludeAt(row, 99).progress === 1);
    check("no duration is finished", M.interludeAt({ t: 1, dur: 0 }, 1).progress === 1);
}

// ── retimeWords: romanized words on the original's timing ────────────────────
console.log("retimeWords");
{
    // Two original units of equal length: the first sung in 1s, the second in 3s.
    const orig = [{ text: "ab", at: 10, d: 1 }, { text: "cd", at: 11, d: 3 }];
    const w = M.retimeWords("xx yy", orig);
    check("one word per romanized word", w.length === 2 && w[0].text === "xx " && w[1].text === "yy");
    check("the first word starts with the line", near(w[0].at, 10));
    check("a word covering the fast half takes the fast half's time", near(w[0].d, 1));
    check("the second takes the slow half", near(w[1].at, 11) && near(w[1].d, 3));
}
{
    // One long original, spread evenly: the romanized words split it by their letters.
    const w = M.retimeWords("aaa b", [{ text: "xxxx", at: 0, d: 4 }]);
    check("uneven words split by letters", near(w[0].at, 0) && near(w[0].d, 3) && near(w[1].at, 3) && near(w[1].d, 1));
}
{
    // A word that straddles two originals reaches from one's timing into the other's.
    const w = M.retimeWords("abcd", [{ text: "ab", at: 0, d: 1 }, { text: "cd", at: 5, d: 1 }]);
    check("a single word spans the whole line", w.length === 1 && near(w[0].at, 0) && near(w[0].at + w[0].d, 6));
}
check("no original timing is nothing to place", M.retimeWords("abc", []).length === 0 && M.retimeWords("abc", null).length === 0);
check("an empty romanization is nothing", M.retimeWords("", [{ text: "a", at: 0, d: 1 }]).length === 0);
check("whitespace-only originals are nothing", M.retimeWords("abc", [{ text: " ", at: 0, d: 1 }]).length === 0);
check("zero-length original units still give a start", near(M.retimeWords("ab", [{ text: "x", at: 2, d: 0 }])[0].at, 2));
{
    const src = [{ text: "ab", at: 1, d: 1 }];
    M.retimeWords("xx", src);
    check("input is not mutated", src.length === 1 && src[0].at === 1 && !("base" in src[0]));
}

// ── Result ────────────────────────────────────────────────────────────────────
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
