// ── test-karaoke.js ───────────────────────────────────────────────────────────
// Regression tests for services/karaoke.js — the karaoke module's decisions: the voice
// gate, the word alignment, a line's tally, the session score, the headphone check.
//
//     bun scripts/test-karaoke.js          (or: node scripts/test-karaoke.js)
//
// Safe to run: pure functions, touches nothing. Loaded by stripping the
// `.pragma library` line and evaluating the rest, so the tests run the real file.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "karaoke.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const K = new Function(src + `
    return { GATE, gateNew, gateStep, words, sameWord, soundKey, closeness, wordSpans, matcherNew, matcherSync, matcherHear, LOOKAHEAD, isWeak, lineOpen, OPEN_LEAD, settleAfter, freeFlags, allFree, withFree, skipMark, skipSet, skipToggle, sanitizeSkips, overlapMap, overlapExcused, LANGS, LANG_ORDER, detectLanguage, modelDirsFor, grammarWords, grammarFor, grammarStale, stripUnk, lineText, lineEnd, inWindow, LEAD, TAIL,
             tallyNew, tallyTime, tallyMark, matched, timing, wordScore, points, lit,
             sessionNew, sessionFinish, percent, isHeadphones, litHtml,
             RANKS, judge, rankFor, lineResult, sessionAdd, sessionCombo, sessionBreak, comboRun, comboSurvives, inGrace, GRACE_S, nextSingableStart, firstSingableStart, startedFromStart, START_SLACK, accuracy, lastSingable, singableCount, songDone, result,
             stepLine, displayAccuracy, MODS, MOD_ORDER, modLabel, modsText, hideModeOf, modList, effectiveMods, modMultiplier, cleanMods, modsOf, rules, RULES_NORMAL, formatScore, songKey, coverName, sanitize, record, withCover, removeSong, list, summary, dbNew, MIN_SCORED_MS };`)();

let pass = 0;
const failures = [];
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { pass++; return; }
    failures.push(`  ${name}\n      want ${w}\n      got  ${g}`);
}
function ok(name, cond) { check(name, !!cond, true); }

// ── Words ─────────────────────────────────────────────────────────────────────
check("words: lower-cased, punctuation is a separator", K.words("Hello, World!"), ["hello", "world"]);
check("words: an apostrophe is not a break", K.words("Don't stop"), ["dont", "stop"]);
check("words: a curly apostrophe either", K.words("I’m here"), ["im", "here"]);
check("words: accents fold", K.words("Café naïve"), ["cafe", "naive"]);
check("words: digits are words", K.words("Take 5"), ["take", "5"]);
check("words: nothing", K.words(""), []);
check("words: undefined is nothing", K.words(undefined), []);
check("words: only punctuation", K.words("... ♪ ♪"), []);
check("words: kana and Han are one token each", K.words("あいう abc"), ["あ", "い", "う", "abc"]);
check("words: Cyrillic is cased, so it counts", K.words("Привет мир"), ["привет", "мир"]);

// ── Where the words are ───────────────────────────────────────────────────────
check("spans: character ranges", K.wordSpans("We will"), [{ s: 0, e: 2 }, { s: 3, e: 7 }]);
check("spans: an apostrophe stays in its word", K.wordSpans("don't go"), [{ s: 0, e: 5 }, { s: 6, e: 8 }]);
check("spans: punctuation separates", K.wordSpans("a, b!"), [{ s: 0, e: 1 }, { s: 3, e: 4 }]);
check("spans: a lone apostrophe is not a word", K.wordSpans("a ' b"), [{ s: 0, e: 1 }, { s: 4, e: 5 }]);
check("spans: kana one by one", K.wordSpans("\u3042\u3044x"), [{ s: 0, e: 1 }, { s: 1, e: 2 }, { s: 2, e: 3 }]);
check("spans: nothing", K.wordSpans(""), []);
check("spans: a combining accent stays in its word", K.wordSpans("cafe\u0301 x"), [{ s: 0, e: 5 }, { s: 6, e: 7 }]);
for (const line of ["We will rock you", "Don't stop - believin'", "caf\u00e9, na\u00efve!", "a ' b", "\u3042\u3044 abc", "...", "x"])
    check("spans and words agree in number: " + line, K.wordSpans(line).length, K.words(line).length);

// ── Same word: close enough to the ear ────────────────────────────────────────
ok("same: exact", K.sameWord("love", "love"));
ok("same: a mishearing, one edit in a long word", K.sameWord("lovin", "loving"));
ok("same: different words", !K.sameWord("heaven", "river"));
ok("same: a short word that is a different word (the / she)", !K.sameWord("the", "she"));
ok("same: a bare vowel is not every vowel (a / i)", !K.sameWord("a", "i"));
ok("same: go is not no", !K.sameWord("go", "no"));
ok("same: rock is not road", !K.sameWord("rock", "road"));
ok("same: we is not he", !K.sameWord("we", "he"));

// What a recogniser does to a sung word: it hears a neighbour of it. All of these count.
for (const [heard, want] of [
    ["wheel", "will"], ["luv", "love"], ["rack", "rock"], ["haven", "heaven"], ["believin", "believing"],
    ["know", "no"], ["to", "do"], ["nite", "night"], ["thot", "thought"], ["gunna", "gonna"],
    ["dawn", "down"], ["hurt", "heart"], ["turning", "burning"], ["ya", "you"], ["they", "the"],
    ["buy", "by"], ["our", "are"], ["lovin", "loving"], ["your", "you"]])
    ok("sounds like: " + heard + " ~ " + want, K.sameWord(heard, want));

// …and these, which only share a letter or two, do not.
for (const [heard, want] of [
    ["love", "hate"], ["heaven", "river"], ["fire", "higher"], ["cry", "try"], ["baby", "maybe"],
    ["yeah", "yes"], ["oh", "owe"]])
    ok("does not sound like: " + heard + " ~ " + want, !K.sameWord(heard, want));

// ── The sound key ─────────────────────────────────────────────────────────────
check("key: silent k and w", [K.soundKey("know"), K.soundKey("write")], ["N", "RT"]);
check("key: gh, mb", [K.soundKey("thought"), K.soundKey("lamb")], ["0T", "LM"]);
check("key: voiced and unvoiced fold", K.soundKey("bat") === K.soundKey("pad"), true);
check("key: v and f fold", K.soundKey("vine") === K.soundKey("fine"), true);
check("key: vowels don't count", K.soundKey("heaven") === K.soundKey("haven"), true);
check("key: a word that begins on a vowel keeps that", K.soundKey("art").charAt(0), "A");
check("key: a word-final w / y is silent", [K.soundKey("cry"), K.soundKey("now")], ["KR", "N"]);
check("key: not plain Latin has none (compared by spelling)", [K.soundKey("\u3042"), K.soundKey("caf\u00e9"), K.soundKey("4ever"), K.soundKey("")], ["", "", "", ""]);
check("key: sh and ch are one sound", K.soundKey("shoe") === K.soundKey("chew"), true);
ok("closeness: identical is 1", K.closeness("rock", "rock") === 1);
ok("closeness: a sound-alike is less than exact but more than the bar", K.closeness("wheel", "will") > 0.66 && K.closeness("wheel", "will") < 1);
ok("closeness: unrelated is low", K.closeness("love", "hate") < 0.4);

// ── The matcher: which lyric word did that sound belong to ───────────────────
// A tiny harness: lines are word lists, `say` feeds partial / final results and collects
// the (line, word) pairs it lit.
function ctxOf(lines, from, to, lit = {}) {
    const out = [];
    for (let i = Math.max(0, from); i <= Math.min(lines.length - 1, to); i++) {
        const words = K.words(lines[i]);
        out.push({ line: i, words, flags: lit[i] ?? words.map(() => false) });
    }
    return out;
}
function sing(lines, utterances, startLine = 0) {
    // utterances: [[tokens-so-far..., isFinal]...] as a sequence of partial results
    let m = K.matcherSync(K.matcherNew(), startLine), lit = [];
    for (const [text, fin, live] of utterances) {
        const line = live === undefined ? startLine : live;
        m = K.matcherSync(m, line);
        const r = K.matcherHear(m, ctxOf(lines, line - 1, line + 1), K.words(text), !!fin);
        m = r.m;
        for (const h of r.hits) lit.push(h.line + ":" + h.w);
    }
    return { lit, m };
}
const rock = ["We will rock you", "We will rock you", "Sing it loud"];

{
    // Singing the first line, word by word, as a recogniser reports it (each partial a word
    // longer, a word is taken once it has been seen twice running).
    const { lit } = sing(rock, [["we"], ["we will"], ["we will"], ["we will rock"], ["we will rock"], ["we will rock you"], ["we will rock you"]]);
    check("matcher: each word of the line sung is taken, in order", lit, ["0:0", "0:1", "0:2", "0:3"]);
}
{
    // THE BUG: the next line repeats the first line's words. Sung only once, it must light
    // only the first line — never the identical words after it.
    const { lit } = sing(rock, [["we will rock you"], ["we will rock you"], ["we will rock you", true]]);
    check("matcher: a repeated next line is NOT lit by words already sung", lit, ["0:0", "0:1", "0:2", "0:3"]);
}
{
    // …and the same words sung AGAIN, a second time, do light the second line — once the song
    // is on it.
    const first = sing(rock, [["we will rock you", true]]);
    let m = first.m;
    m = K.matcherSync(m, 1);
    const r = K.matcherHear(m, ctxOf(rock, 0, 2), K.words("we will rock you"), true);
    check("matcher: sung a second time, the repeated line lights", r.hits.map(h => h.line + ":" + h.w), ["1:0", "1:1", "1:2", "1:3"]);
}
{
    // One long utterance (no pause) across two identical lines: the first four words go to
    // line 0, the next four to line 1 — not all eight onto one line, not two onto each.
    const toks = "we will rock you we will rock you";
    const { lit } = sing(rock, [[toks], [toks], [toks, true]], 0);
    check("matcher: a continuous utterance walks across the repeat", lit,
          ["0:0", "0:1", "0:2", "0:3", "1:0", "1:1", "1:2", "1:3"]);
}
{
    // Sung a little off, still the word: the recogniser's neighbours of each one count.
    const { lit } = sing(["we will rock you"], [["we wheel rack you", true]]);
    check("matcher: close enough to the ear counts", lit, ["0:0", "0:1", "0:2", "0:3"]);
}
{
    // Of the words in reach, the best wins: "will" heard right after "we" belongs to the EXACT
    // "will", not to the sound-alike "wheel" that stands first.
    const { lit } = sing(["we wheel will"], [["we will", true]]);
    check("matcher: an exact word in reach beats a sound-alike at the cursor", lit, ["0:0", "0:2"]);
}
{
    // …and a sound-alike line is still not the next line's words until the cursor gets there:
    // the repeat is judged by the same forward rule, loose spelling or not.
    const { lit } = sing(["we will rock you", "we wheel rock you"], [["we will rack you", true]]);
    check("matcher: sound-alikes don't leak into a similar next line", lit, ["0:0", "0:1", "0:2", "0:3"]);
}
{
    // A heard word is consumed once: "go" sung once lights ONE "go", not both.
    const { lit } = sing(["go go now"], [["go", true]]);
    check("matcher: one sound lights one word", lit, ["0:0"]);
}
{
    // A stray recogniser word between two real ones is skipped, not an obstacle.
    const { lit } = sing(["we will rock"], [["we uh will rock", true]]);
    check("matcher: a stray word costs nothing", lit, ["0:0", "0:1", "0:2"]);
}
{
    // A missed word stays dark; the ones after it still land.
    const { lit } = sing(["we will rock you"], [["we rock you", true]]);
    check("matcher: a missed middle word stays dark", lit, ["0:0", "0:2", "0:3"]);
}
{
    // A word the recogniser first hears wrong and then corrects: the wrong one is never taken.
    const lines = ["we will rock"];
    let m = K.matcherSync(K.matcherNew(), 0), lit = [];
    for (const text of ["we wheel", "we will", "we will rock"]) {
        const r = K.matcherHear(m, ctxOf(lines, 0, 1), K.words(text), false);
        m = r.m;
        for (const h of r.hits) lit.push(h.w);
    }
    check("matcher: a revised word is only taken once it has settled", lit, [0, 1]);
}
{
    // The lookahead: a word far down the line can't be reached by a single stray sound, and a
    // short function word can't be fuzzily matched.
    const lines = ["alpha bravo charlie delta echo foxtrot golf"];
    const r = K.matcherHear(K.matcherSync(K.matcherNew(), 0), ctxOf(lines, 0, 0), ["golf"], true);
    check("matcher: a word beyond the lookahead is out of reach", r.hits, []);
    ok("matcher: the lookahead is a handful of words", K.LOOKAHEAD >= 3 && K.LOOKAHEAD <= 8);
}
{
    // Never backwards: a word already passed isn't lit by a late echo of it.
    const lines = ["one two three four"];
    let r = K.matcherHear(K.matcherSync(K.matcherNew(), 0), ctxOf(lines, 0, 0), ["one", "two", "three"], true);
    // The service hands the matcher what is already lit; a word that is lit can't be taken again.
    const lit = { 0: [true, true, true, false] };
    const second = K.matcherHear(r.m, ctxOf(lines, 0, 0, lit), ["one"], true);
    check("matcher: never backwards onto a word already lit", second.hits, []);
}
{
    // A new utterance after a final starts counting from nothing again, but the cursor stays.
    const lines = ["we will rock you", "sing it loud"];
    let m = K.matcherSync(K.matcherNew(), 0);
    let r = K.matcherHear(m, ctxOf(lines, 0, 1), ["we", "will"], true);
    check("matcher: a final ends the utterance", [r.m.took, r.m.prev.length], [0, 0]);
    r = K.matcherHear(r.m, ctxOf(lines, 0, 1), ["rock", "you"], true);
    check("matcher: the next utterance carries on from the cursor", r.hits.map(h => h.line + ":" + h.w), ["0:2", "0:3"]);
}
{
    // matcherSync: the cursor starts at the live line, trails by at most one, and a seek resets it.
    check("sync: starts at the live line", K.matcherSync(K.matcherNew(), 5).line, 5);
    check("sync: no line yet changes nothing", K.matcherSync(K.matcherNew(), -1).line, -1);
    check("sync: a cursor too far behind is brought to one behind", K.matcherSync({ line: 2, w: 3, took: 0, prev: [] }, 9).line, 8);
    check("sync: and its word resets", K.matcherSync({ line: 2, w: 3, took: 0, prev: [] }, 9).w, 0);
    check("sync: one behind is left alone", K.matcherSync({ line: 8, w: 3, took: 0, prev: [] }, 9).w, 3);
    check("sync: a seek back resets it", K.matcherSync({ line: 20, w: 1, took: 0, prev: [] }, 3).line, 3);
{
    // A LATE word: the song is two lines on and the singer is still on the line before. It lights that
    // line's word from behind, only when nothing ahead fits, and leaves the cursor where it was.
    const song = ["one two three four", "five six seven eight", "nine ten eleven twelve"];
    const hear = (tokens, lit = {}) => K.matcherHear(K.matcherSync({ line: 1, w: 0, took: 0, prev: [] }, 2), ctxOf(song, 0, 2, lit), tokens, true);
    let r = hear(["three", "four"]);
    check("late: words of a line two back are taken from behind", r.hits.map(h => h.line + ":" + h.w), ["0:2", "0:3"]);
    check("late: and the cursor stays", [r.m.line, r.m.w], [1, 0]);
    const rep = ["go home now", "go home now", "go home now"];
    r = K.matcherHear(K.matcherSync({ line: 1, w: 0, took: 0, prev: [] }, 1), ctxOf(rep, 0, 2), ["go"], true);
    check("late: a word that fits ahead is never taken from behind", r.hits.map(h => h.line + ":" + h.w), ["1:0"]);
    check("late: a word already lit is not lit twice", hear(["three"], { 0: [true, true, true, true] }).hits, []);
    check("late: a word that fits nothing lights nothing", hear(["banana"]).hits, []);
}
{
    // settleAfter: the wait before a line that has just ended is judged — longer for a short line.
    const ls = [{ t: 0 }, { t: 1 }, { t: 5 }, { t: 7.5 }, { t: 9.25 }, { t: 12, dur: 0.5 }];
    check("settleAfter: a 1 s line waits twice the grace", K.settleAfter(ls, 0), 2400);
    check("settleAfter: a 4 s line waits the grace", K.settleAfter(ls, 1), 1200);
    check("settleAfter: a 2.5 s line waits the grace", K.settleAfter(ls, 2), 1200);
    check("settleAfter: a 1.75 s line is between", K.settleAfter(ls, 3), 1800);
    check("settleAfter: never more than twice, however short", K.settleAfter(ls, 5), 2400);
    check("settleAfter: Time-Hell keeps its own, shorter base", K.settleAfter(ls, 0, K.rules(["TH"])), 1000);
    check("settleAfter: no such line is the base", [K.settleAfter(ls, -1), K.settleAfter(ls, 99)], [1200, 1200]);
}
}

// ── A line is out of reach until the song is near it ──────────────────────────
{
    // The real failure, replayed: while "nine oh two i no" is being sung the recogniser's partial
    // carries a stray "zero", which is the first word of the NEXT line. It must not light it, and
    // must not pull the cursor there — the real last words of this line are still to come.
    const lines = ["nine oh two i no", "zero one eight zero three"];
    const closed = () => ctxOf(lines, 0, 1).map(c => c.line === 1 ? { ...c, open: false } : c);
    let r = K.matcherHear(K.matcherSync(K.matcherNew(), 0), closed(), ["nine", "oh", "two", "i", "no", "zero"], true);
    check("open: a closed next line is not lit by its first word turning up early", r.hits.map(h => h.line + ":" + h.w), ["0:0", "0:1", "0:2", "0:3", "0:4"]);
    check("open: and the cursor stays in the line being sung", [r.m.line, r.m.w], [0, 5]);
    // Once the song gets there, the same word does light it.
    r = K.matcherHear({ line: 0, w: 5, took: 0, prev: [] }, ctxOf(lines, 0, 1), ["zero"], true);
    check("open: when the line opens its words are reachable", r.hits.map(h => h.line + ":" + h.w), ["1:0"]);
    // A closed line stops the search: nothing beyond it is reached either.
    const three = ["a b", "c d", "e f"];
    const ctx3 = ctxOf(three, 0, 2).map(c => c.line === 1 ? { ...c, open: false } : c);
    check("open: nothing past a closed line is reached", K.matcherHear({ line: 0, w: 2, took: 0, prev: [] }, ctx3, ["e"], true).hits, []);
}
check("lineOpen: before the lead-in it is closed", K.lineOpen([{ t: 10 }], 0, 10 - K.OPEN_LEAD - 0.1), false);
check("lineOpen: from the lead-in on it is open", K.lineOpen([{ t: 10 }], 0, 10 - K.OPEN_LEAD + 0.1), true);
check("lineOpen: a line long past stays open", K.lineOpen([{ t: 10 }], 0, 90), true);
check("lineOpen: no such line is not open", [K.lineOpen([{ t: 10 }], 5, 99), K.lineOpen([{ t: 10 }], -1, 99)], [false, false]);

// ── The combo is per word ─────────────────────────────────────────────────────
{
    const lines = [{ text: "one two three" }, { text: "" }, { text: "four five" }, { text: "six" }];
    check("comboRun: nothing sung on the line is 0", K.comboRun({}, lines, 0, 1), 0);
    check("comboRun: the run of lit words ending at this one", K.comboRun({ 0: [true, true, true] }, lines, 0, 2), 3);
    check("comboRun: an unlit word before it ends the run", K.comboRun({ 0: [true, false, true] }, lines, 0, 2), 1);
    check("comboRun: the word itself must be lit", K.comboRun({ 0: [true, true, false] }, lines, 0, 2), 0);
    check("comboRun: it carries back into the line before, past a silent row",
          K.comboRun({ 0: [true, true, true], 2: [true, true] }, lines, 2, 1), 5);
    check("comboRun: a line before that was not wholly sung stops it", K.comboRun({ 0: [true, true, false], 2: [true, true] }, lines, 2, 1), 2);
    check("comboRun: a line never sung stops it", K.comboRun({ 2: [true, true] }, lines, 2, 1), 2);
    check("comboRun: across several lines", K.comboRun({ 0: [true, true, true], 2: [true, true], 3: [true] }, lines, 3, 0), 6);
    check("comboRun: the second word alone (the first was skipped)", K.comboRun({ 2: [false, true] }, lines, 2, 1), 1);
}
{
    const sungAll = (txt, flags) => flags.reduce((t, f, i) => f ? K.tallyMark(t, i) : t, K.tallyNew(txt));
    check("comboSurvives: a line whose last word was sung keeps it", K.comboSurvives(sungAll("a b c", [true, true, true]), {}, 0), true);
    check("comboSurvives: a missed last word breaks it", K.comboSurvives(sungAll("a b c", [true, true, false]), { 0: [true, true, false] }, 0), false);
    check("comboSurvives: …unless a later word is already lit (the combo is that run now)", K.comboSurvives(sungAll("a b c", [true, true, false]), { 0: [true, true, false], 1: [false, true] }, 0), true);
    check("comboSurvives: a line with no words has nothing to break", K.comboSurvives(K.tallyNew(""), {}, 0), true);
}

// ── The grace period ──────────────────────────────────────────────────────────
check("grace: a line that starts inside it is a warm-up", [K.inGrace(3, 6), K.inGrace(5.99, 6)], [true, true]);
check("grace: one that starts at or after its end is not", [K.inGrace(6, 6), K.inGrace(20, 6)], [false, false]);
ok("grace: it is a handful of seconds", K.GRACE_S >= 3 && K.GRACE_S <= 10);
{
    const lines = [{ t: 2, text: "one" }, { t: 6, text: "" }, { t: 9, text: "two" }];
    check("nextSingableStart: the next line that sings", K.nextSingableStart(lines, 0), 2);
    check("nextSingableStart: skips a silent row", K.nextSingableStart(lines, 3), 9);
    check("nextSingableStart: none left", K.nextSingableStart(lines, 10), -1);
    check("nextSingableStart: not a line already begun", K.nextSingableStart(lines, 2), 9);
}

// ── A run has to start from the start to rank ─────────────────────────────────
{
    const lines = [{ t: 0, text: "" }, { t: 10, text: "one" }, { t: 14, text: "two" }];
    check("firstSingableStart: skips a silent opening row", K.firstSingableStart(lines), 10);
    check("firstSingableStart: none", K.firstSingableStart([{ t: 3, text: "" }]), -1);
    check("startedFromStart: at the very start", K.startedFromStart(lines, 0), true);
    check("startedFromStart: in the intro, before the first line", K.startedFromStart(lines, 7), true);
    check("startedFromStart: as the first line begins", K.startedFromStart(lines, 10), true);
    check("startedFromStart: a line barely begun can still be sung whole", K.startedFromStart(lines, 10 + K.START_SLACK), true);
    check("startedFromStart: once it is well under way, no", K.startedFromStart(lines, 10 + K.START_SLACK + 0.1), false);
    check("startedFromStart: in the middle of the song, no", K.startedFromStart(lines, 60), false);
    check("startedFromStart: no lyrics to judge by is nothing to miss", [K.startedFromStart([], 60), K.startedFromStart([{ t: 5, text: "" }], 60)], [true, true]);
}

// ── Lookback and gap-fill ─────────────────────────────────────────────────────
{
    // One wrong jump forward must not strand the real words behind it. "we will rock you":
    // "rock" is heard first (the recogniser caught it before the two words ahead of it) — then
    // "we will" arrive late; they are still reachable, unlit words just back in the same line.
    const lines = ["we will rock you"];
    const r1 = K.matcherHear(K.matcherSync(K.matcherNew(), 0), ctxOf(lines, 0, 0), ["rock"], true);
    const lit0 = { 0: [false, false, true, false] };
    const r2 = K.matcherHear(r1.m, ctxOf(lines, 0, 0, lit0), ["we", "will"], true);
    check("lookback: words just behind the cursor are still reachable", r2.hits.map(h => h.line + ":" + h.w), ["0:0", "0:1"]);
    const far = K.matcherHear({ line: 0, w: 6, took: 0, prev: [] }, ctxOf(["a b c d e f g h"], 0, 0, {}), ["a"], true);
    check("lookback: but only so far (not six words back)", far.hits, []);
}
{
    // …but never a word that is already lit, and never into an earlier line.
    const lines = ["we will rock you", "we will rock you"];
    const lit = { 0: [true, true, true, true] };
    const m = { line: 1, w: 0, took: 0, prev: [] };
    const r = K.matcherHear(m, ctxOf(lines, 0, 1, lit), ["we"], true);
    check("lookback: a repeated line's word lights THIS line, not the one before",
          r.hits.map(h => h.line + ":" + h.w), ["1:0"]);
    const lit2 = { 0: [true, true, true, false] };         // the last word of line 0 was never lit
    const r2 = K.matcherHear({ line: 1, w: 0, took: 0, prev: [] }, ctxOf(lines, 0, 1, lit2), ["you"], true);
    check("lookback: it does not reach across into the previous line", r2.hits.map(h => h.line + ":" + h.w).includes("0:3"), false);
}
{
    // A recogniser drops the small words. Heard on either side, they were sung.
    const lines = ["i want to be there"];
    const r = K.matcherHear(K.matcherSync(K.matcherNew(), 0), ctxOf(lines, 0, 0), ["i", "be", "there"], true);
    check("gap: 'want to' was dropped, 'want' is long so it stays dark", r.hits.map(h => h.w), [0, 3, 4]);
    const r2 = K.matcherHear(K.matcherSync(K.matcherNew(), 0), ctxOf(["in the end it does not matter"], 0, 0), ["end", "matter"], true);
    check("gap: leading small words (in the) are filled; 'it does not' is three, too many to assume", r2.hits.map(h => h.w), [0, 1, 2, 6]);
}
{
    const lines = ["go to the left now"];
    const r = K.matcherHear(K.matcherSync(K.matcherNew(), 0), ctxOf(lines, 0, 0), ["go", "left"], true);
    check("gap: two small words between two heard are filled (to the)", r.hits.map(h => h.w + (h.inferred ? "*" : "")), ["0", "1*", "2*", "3"]);
    const r2 = K.matcherHear(K.matcherSync(K.matcherNew(), 0), ctxOf(["love song tonight"], 0, 0), ["love", "tonight"], true);
    check("gap: a content word between two heard is NOT assumed sung", r2.hits.map(h => h.w), [0, 2]);
}
{
    // The leading gap across a line boundary: the cursor is spent its line, the next line's small
    // first word was dropped.
    const lines = ["we will rock you", "and we will go"];
    const m = { line: 0, w: 4, took: 0, prev: [] };
    const r = K.matcherHear(m, ctxOf(lines, 0, 1), ["we"], true);
    check("gap: the small first word of the next line is filled once the cursor has left the last",
          r.hits.map(h => h.line + ":" + h.w), ["1:0", "1:1"]);
    const m2 = { line: 0, w: 2, took: 0, prev: [] };           // NOT spent: still mid-line
    const r2 = K.matcherHear(m2, ctxOf(lines, 0, 1), ["rock"], true);
    check("gap: no filling across a line while the cursor is mid-line", r2.hits.map(h => h.line + ":" + h.w), ["0:2"]);
}
check("weak: short words and a few common ones", [K.isWeak("the"), K.isWeak("with"), K.isWeak("heart"), K.isWeak("love")], [true, true, false, false]);

// ── Languages ─────────────────────────────────────────────────────────────────
{
    const L = text => K.detectLanguage(text.split("\n").map(t => ({ text: t })));
    check("detect: English", L("I just want to be with you\nDon't you know that I love you\nOh baby it's all for me").lang, "en");
    check("detect: Portuguese", L("Eu n\u00e3o sei o que fazer sem voc\u00ea\nO meu cora\u00e7\u00e3o \u00e9 todo seu\nTudo que eu quero \u00e9 voc\u00ea aqui").lang, "pt");
    check("detect: Spanish", L("Yo no s\u00e9 qu\u00e9 hacer sin ti\nMi coraz\u00f3n es todo tuyo\nPero cuando te vas me quedo solo").lang, "es");
    check("detect: French", L("Je ne sais pas quoi faire sans toi\nMon coeur est \u00e0 toi\nMais tu es partie dans la nuit").lang, "fr");
    check("detect: German", L("Ich wei\u00df nicht was ich ohne dich tun soll\nDas ist mein Herz und es ist dein\nWenn du gehst bin ich allein").lang, "de");
    check("detect: Italian", L("Io non so che cosa fare senza di te\nIl mio cuore \u00e8 tutto tuo\nMa quando te ne vai sono solo").lang, "it");
    check("detect: Dutch", L("Ik weet niet wat ik moet doen zonder jou\nHet is mijn hart en het is van jou\nMaar als je gaat ben ik alleen").lang, "nl");
    check("detect: Russian, by its script", L("\u042f \u043d\u0435 \u0437\u043d\u0430\u044e \u0447\u0442\u043e \u0434\u0435\u043b\u0430\u0442\u044c\n\u0422\u044b \u043c\u043e\u044f \u043b\u044e\u0431\u043e\u0432\u044c").lang, "ru");
    check("detect: Portuguese and Spanish are told apart", [L("N\u00e3o, voc\u00ea n\u00e3o sabe o que eu sinto\nEu vou ficar aqui com voc\u00ea").lang, L("No, t\u00fa no sabes lo que siento\nYo voy a quedarme aqu\u00ed contigo").lang], ["pt", "es"]);
    check("detect: too little to go on is none", [L("la la la").lang, L("").lang, K.detectLanguage([]).lang], ["", "", ""]);
    check("detect: a script with no model here is none", L("\u3053\u3093\u306b\u3061\u306f\u4e16\u754c\u3055\u3088\u3046\u306a\u3089").lang, "");
    check("detect: no function words at all is none, not a guess", L("xyzzy plugh frobozz quux").lang, "");
    check("detect: it says how sure it is", L("I just want to be with you\nDon't you know that I love you").sure, true);
    check("detect: a mixed song goes to the language most of it is in", L("Eu n\u00e3o sei o que fazer sem voc\u00ea\nBaby I love you\nO meu cora\u00e7\u00e3o \u00e9 todo seu\nTudo que eu quero \u00e9 voc\u00ea").lang, "pt");
    check("langs: every code has a name, a model and stop words (but Russian has its script)",
          K.LANG_ORDER.every(c => K.LANGS[c].name && K.LANGS[c].model && (K.LANGS[c].stop.length > 0 || c === "ru")), true);
    check("langs: stop words are accent-folded, as words() makes them (or they would never match)",
          K.LANG_ORDER.every(c => K.LANGS[c].stop.every(w => w === w.normalize("NFD").replace(/[\u0300-\u036f]/g, ""))), true);
}
check("modelDirsFor: a path the user set is used for every language", [K.modelDirsFor("pt", "/m", "/d"), K.modelDirsFor("en", "/m", "/d")], [["/m"], ["/m"]]);
check("modelDirsFor: Portuguese looks in the user's data dir, then the system's",
      K.modelDirsFor("pt", "", "/d"), ["/d/quicktest/vosk-pt", "/usr/share/vosk-models/small-pt"]);
check("modelDirsFor: English keeps its old place first", K.modelDirsFor("en", "", "/d"),
      ["/d/quicktest/vosk", "/d/quicktest/vosk-en-us", "/usr/share/vosk-models/small-en-us"]);
check("modelDirsFor: an unknown language falls back to English", K.modelDirsFor("xx", "", "/d")[1], "/d/quicktest/vosk-en-us");

// ── The grammar, per language ─────────────────────────────────────────────────
// Measured on the real Portuguese model: these accented words are in its vocabulary; their folded
// spellings ("nao" "coracao" "ja" "mae") are NOT. Folding them, as English needs, would drop them.
check("grammarWords (pt): accents are kept", K.grammarWords("N\u00e3o, voc\u00ea \u00e9 meu cora\u00e7\u00e3o", "pt"), ["n\u00e3o", "voc\u00ea", "\u00e9", "meu", "cora\u00e7\u00e3o"]);
check("grammarWords (pt): a hyphen separates (guarda-chuva is not a word, guarda chuva is)", K.grammarWords("guarda-chuva", "pt"), ["guarda", "chuva"]);
check("grammarWords (pt): lowercase", K.grammarWords("AMOR Eterno", "pt"), ["amor", "eterno"]);
check("grammarWords (fr): an elision stays one token", K.grammarWords("J'ai l'amour", "fr"), ["j'ai", "l'amour"]);
check("grammarWords (es): the tilde and the inverted marks", K.grammarWords("\u00bfQu\u00e9 pasa, ni\u00f1o?", "es"), ["qu\u00e9", "pasa", "ni\u00f1o"]);
check("grammarWords (de): umlauts and eszett", K.grammarWords("Gr\u00fc\u00dfe f\u00fcr dich", "de"), ["gr\u00fc\u00dfe", "f\u00fcr", "dich"]);
check("grammarWords (ru): Cyrillic words", K.grammarWords("\u042f \u043b\u044e\u0431\u043b\u044e \u0442\u0435\u0431\u044f", "ru"), ["\u044f", "\u043b\u044e\u0431\u043b\u044e", "\u0442\u0435\u0431\u044f"]);
check("grammarWords (pt): the English dropped-g rule is NOT applied", K.grammarWords("cantin' vamos", "pt"), ["cantin", "vamos"]);
check("grammarWords (en): still folds accents, still puts the g back", K.grammarWords("Caf\u00e9 believin'", "en"), ["cafe", "believing"]);
check("grammarWords: no language is English", K.grammarWords("Caf\u00e9 believin'"), ["cafe", "believing"]);
check("grammarFor (pt): the phrases keep their accents", K.grammarFor([{ text: "N\u00e3o sei" }], 0, "pt").phrases, ["n\u00e3o sei", "n\u00e3o", "sei"]);
// The matching is by FOLDED words, on both sides, so an accent the recogniser adds or drops still matches.
check("matching: an accented word heard matches the same word without its accent in the lyric",
      K.matcherHear(K.matcherSync(K.matcherNew(), 0), [{ line: 0, words: K.words("Nao sei"), flags: [false, false] }], K.words("n\u00e3o sei"), true).hits.length, 2);

// ── The grammar ───────────────────────────────────────────────────────────────
check("grammarWords: lowercase, accents folded, apostrophes kept inside words",
      K.grammarWords("Don't stop, Caf\u00e9!"), ["don't", "stop", "cafe"]);
check("grammarWords: a dropped g is put back (the model knows believing)", K.grammarWords("Believin' and feelin'"), ["believing", "and", "feeling"]);
check("grammarWords: a leading apostrophe goes ('cause)", K.grammarWords("'Cause it's late"), ["cause", "it's", "late"]);
check("grammarWords: curly apostrophes too", K.grammarWords("I\u2019m here"), ["i'm", "here"]);
check("grammarWords: not Latin has none", K.grammarWords("\u3042\u3044\u3046"), []);
check("grammarWords: empty", K.grammarWords(undefined), []);
{
    const lines = [{ text: "We will rock you" }, { text: "We will rock you" }, { text: "" }, { text: "Sing it loud" }, { text: "Far away" }, { text: "Last" }];
    const g = K.grammarFor(lines, 1);
    check("grammarFor: covers one line behind and three ahead", [g.lo, g.hi], [0, 4]);
    check("grammarFor: a phrase per line (not the empty one), then each word once",
          g.phrases, ["we will rock you", "we will rock you", "sing it loud", "far away", "we", "will", "rock", "you", "sing", "it", "loud", "far", "away"]);
    check("grammarFor: at the start there is no line behind", K.grammarFor(lines, 0).lo, 0);
    check("grammarFor: at the end it stops", K.grammarFor(lines, 5).hi, 5);
    check("grammarFor: nothing sung is an empty list", K.grammarFor([{ text: "" }], 0).phrases, []);
}
{
    check("stale: no grammar yet", K.grammarStale(null, 0, 10), true);
    check("stale: fresh just after it was built", K.grammarStale({ lo: 4, hi: 8 }, 5, 20), false);
    check("stale: one line on is still covered", K.grammarStale({ lo: 4, hi: 8 }, 6, 20), false);
    check("stale: two lines on, the lines ahead run out", K.grammarStale({ lo: 4, hi: 8 }, 7, 20), true);
    check("stale: seeked back past its start", K.grammarStale({ lo: 4, hi: 8 }, 3, 20), true);
    check("stale: at the end of the lyrics, nothing more to add", K.grammarStale({ lo: 14, hi: 19 }, 19, 20), false);
    check("stale: from the first line there is nothing behind to add", K.grammarStale({ lo: 0, hi: 3 }, 0, 20), false);
}
check("stripUnk: [unk] is not a word", K.words(K.stripUnk("we [unk] will [UNK] rock")), ["we", "will", "rock"]);
check("stripUnk: undefined", K.stripUnk(undefined), "");

// ── The voice gate ────────────────────────────────────────────────────────────
function run(levels, ms) {
    let g = K.gateNew(), t = 0, trace = [];
    for (const l of levels) { g = K.gateStep(g, l, t); trace.push(g.voiced); t += ms; }
    return { g, trace };
}
check("gate: silence is never voiced", run(Array(40).fill(0.001), 50).trace.every(v => !v), true);
check("gate: mic self-noise below the minimum is not a voice", run(Array(40).fill(0.002), 50).trace.every(v => !v), true);
check("gate: singing is voiced", run(Array(10).fill(0.001).concat(Array(10).fill(0.12)), 50).trace[19], true);
{
    // Voiced for 10 frames, then silent: stays open through the hold, then closes.
    const { trace } = run(Array(10).fill(0.12).concat(Array(20).fill(0.001)), 50);
    check("gate: the hold bridges a gap between words", trace[10 + 2], true);
    check("gate: and closes after it", trace[10 + 10], false);
}
check("gate: NaN is silence", K.gateStep(K.gateNew(), NaN, 0).voiced, false);
check("gate: negative is silence", K.gateStep(K.gateNew(), -3, 0).voiced, false);
check("gate: undefined is silence", K.gateStep(K.gateNew(), undefined, 0).voiced, false);
{
    // A steady fan: loud against the minimum at first, but it must not read as a voice
    // forever — the floor learns the room.
    const { trace } = run(Array(6000).fill(0.04), 50);
    check("gate: a fan reads as voice at first", trace[0], true);
    check("gate: and the gate learns it is only a room after a few minutes", trace[5999], false);
}
{
    // A held note must not close the gate on itself within seconds.
    const { trace } = run(Array(200).fill(0.15), 50);
    check("gate: a ten-second held note stays voiced", trace.every(v => v), true);
}

// ── The gate with voicing ─────────────────────────────────────────────────────
function runV(levels, voicings, ms) {
    let g = K.gateNew(), t = 0, trace = [];
    levels.forEach((l, i) => { g = K.gateStep(g, l, t, voicings[i]); trace.push(g.voiced); t += ms; });
    return trace;
}
check("gate+voicing: loud and periodic is a voice", runV([0.1], [0.9], 30)[0], true);
check("gate+voicing: loud but aperiodic (a fan) is not", runV(Array(40).fill(0.1), Array(40).fill(0.2), 30).every(v => !v), true);
check("gate+voicing: periodic but too quiet is not", runV(Array(40).fill(0.003), Array(40).fill(0.95), 30).every(v => !v), true);
check("gate+voicing: a fan never reads as a voice, from the first frame", runV(Array(3000).fill(0.04), Array(3000).fill(0.25), 30).some(v => v), false);
{
    // Hysteresis: on at 0.55, but once voiced, a wobble down to 0.35 does not drop it.
    const trace = runV(Array(40).fill(0.1), [0.9].concat(Array(39).fill(0.35)), 30);
    check("gate+voicing: a note's wobble above the off level stays voiced", trace.every(v => v), true);
    const down = runV(Array(40).fill(0.1), [0.9].concat(Array(39).fill(0.15)), 30);
    check("gate+voicing: but a real loss of periodicity ends it, after the hold", [down[2], down[39]], [true, false]);
    const start = runV([0.1, 0.1, 0.1], [0.45, 0.45, 0.45], 30);
    check("gate+voicing: it takes the higher bar to START", start.some(v => v), false);
}
check("gate+voicing: NaN voicing falls back to level alone", runV([0.1], [NaN], 30)[0], true);
check("gate+voicing: undefined voicing falls back to level alone", runV([0.1], [undefined], 30)[0], true);
{
    // Faster: voiced on the very first loud periodic frame, and dark within the hold.
    const trace = runV([0.1, 0.001, 0.001, 0.001, 0.001, 0.001, 0.001, 0.001], [0.9, 0, 0, 0, 0, 0, 0, 0], 30);
    check("gate+voicing: lights on the first frame", trace[0], true);
    check("gate+voicing: and is dark within about 200 ms of stopping", [trace[4], trace[7]], [true, false]);
}

// ── Lines ─────────────────────────────────────────────────────────────────────
check("lineText: text wins", K.lineText({ text: "Hello there", words: [{ text: "x" }] }), "Hello there");
check("lineText: else the timed words", K.lineText({ words: [{ text: "Hello " }, { text: "there" }] }), "Hello there");
check("lineText: nothing", K.lineText(null), "");
{
    const lines = [{ t: 10, dur: 3 }, { t: 12, dur: 5 }, { t: 30, dur: 0 }];
    check("lineEnd: its own duration", K.lineEnd(lines, 2) - 30, 4);
    check("lineEnd: never past the next line", K.lineEnd(lines, 0), 12);
    check("lineEnd: a stated duration inside the gap", K.lineEnd(lines, 1), 17);
    ok("inWindow: a beat early counts", K.inWindow(lines, 1, 12 - K.LEAD + 0.01));
    ok("inWindow: too early doesn't", !K.inWindow(lines, 1, 12 - K.LEAD - 0.5));
    ok("inWindow: a beat late counts", K.inWindow(lines, 1, 17 + K.TAIL - 0.01));
    ok("inWindow: long after doesn't", !K.inWindow(lines, 1, 17 + K.TAIL + 1));
    ok("inWindow: before the first line", !K.inWindow(lines, -1, 0));
}

// ── A line's tally ────────────────────────────────────────────────────────────
{
    let t = K.tallyNew("We will rock you");
    check("tally: words and no flags", [t.words.length, K.matched(t)], [4, 0]);
    for (let i = 0; i < 20; i++) t = K.tallyTime(t, 100, i < 14);          // 2s on, voiced for 1.4s
    check("tally: time on and voiced", [t.activeMs, t.voicedMs], [2000, 1400]);
    check("timing: a line 70% voiced is full marks (well past the 45% that is)", K.timing(t), 1);
    const half = K.tallyTime(K.tallyNew("a b"), 1000, false);
    check("timing: silent is nothing", K.timing(half), 0);
    check("timing: nothing yet is nothing", K.timing(K.tallyNew("a")), 0);
}
{
    const t = K.tallyNew("We will rock you");
    const t2 = K.tallyMark(t, 1);
    check("mark: lights that word", t2.flags, [false, true, false, false]);
    check("mark: doesn't mutate its input", t.flags, [false, false, false, false]);
    check("mark: flags only ever turn on", K.tallyMark(K.tallyMark(t2, 3), 1).flags, [false, true, false, true]);
    check("mark: marking a lit word again is the same tally", K.tallyMark(t2, 1) === t2, true);
    check("mark: out of range is ignored", K.tallyMark(t, 9) === t && K.tallyMark(t, -1) === t, true);
}

// ── Lit and points ────────────────────────────────────────────────────────────
{
    const t = K.tallyNew("one two three four");
    check("lit: silent is dark", K.lit(t, false, true, true), 0);
    check("lit: off the line is dark", K.lit(t, true, false, true), 0);
    check("lit: timing only is full", K.lit(t, true, true, false), 1);
    check("lit: words mode, no words yet, a base glow", K.lit(t, true, true, true), 0.35);
    const sung = [0, 1, 2, 3].reduce((a, w) => K.tallyMark(a, w), t);
    check("lit: words mode, all landed, full", K.lit(sung, true, true, true), 1);
}
{
    let t = K.tallyNew("one two three four");
    for (let i = 0; i < 30; i++) t = K.tallyTime(t, 100, true);
    check("points: timing only, in time, is full", K.points(t, false), 1);
    check("points: words mode but no words heard is NOTHING (no credit for just making a noise)", K.points(t, true), 0);
    const sung = [0, 1, 2, 3].reduce((a, w) => K.tallyMark(a, w), t);
    check("points: words mode, all heard, in time, is full", K.points(sung, true), 1);
    // Half the words is clearly worse than all of them: the curve (WORD_CURVE 1.5) on the word share.
    let ten = K.tallyNew("a b c d e f g h i j");
    for (let i = 0; i < 30; i++) ten = K.tallyTime(ten, 100, true);
    const share = n => Array.from({ length: n }, (_, i) => i).reduce((a, w) => K.tallyMark(a, w), ten);
    check("points: 7 of 10 words in time is still full (the 70%)", K.points(share(7), true), 1);
    check("points: 5 of 10 words in time is ~0.6, a Good", [Math.round(K.points(share(5), true) * 100) / 100, K.judge(K.points(share(5), true))], [0.6, "good"]);
    check("points: 3 of 10 words in time is a Miss", K.judge(K.points(share(3), true)), "miss");
    check("points: 1 of 10 words in time is ~0.05", Math.round(K.points(share(1), true) * 100) / 100, 0.05);
    // Timing shapes how much of the words counts: off the beat is three quarters of them.
    let off = K.tallyNew("a b c d e f g h i j");
    for (let i = 0; i < 30; i++) off = K.tallyTime(off, 100, false);
    check("points: all the words but no voicing in time is 0.75", K.points(Array.from({ length: 10 }, (_, i) => i).reduce((a, w) => K.tallyMark(a, w), off), true), 0.75);
    check("points: a line with no words has no word score", K.wordScore(K.tallyNew("")), 0);
}

// ── Words the recogniser cannot hear (out of its vocabulary) ──────────────────
{
    const oov = { piroca: true, yeah: true };
    check("free: flags per word", K.freeFlags(["quero", "piroca", "yeah"], oov), [false, true, true]);
    check("free: no list is none free", K.freeFlags(["a", "b"], undefined), [false, false]);
    check("free: a line of only those", [K.allFree(["yeah", "piroca"], oov), K.allFree(["yeah", "amor"], oov), K.allFree([], oov)], [true, false, false]);
    const song = ["quero piroca yeah amor", "yeah eu quero", "xa xb xc xd xe xf cantar"];
    const free = (i, o = { ...oov, xa: true, xb: true, xc: true, xd: true, xe: true, xf: true }) => K.freeFlags(K.words(song[i]), o);
    const ctx = (lit = {}) => song.map((s, i) => ({ line: i, words: K.words(s), flags: lit[i] ?? K.words(s).map(() => false), free: free(i), open: true }));
    let r = K.matcherHear(K.matcherSync(K.matcherNew(), 0), ctx().slice(0, 1), ["quero"], true);
    check("free: a heard word lights the unhearable ones after it", r.hits.map(h => h.line + ":" + h.w).sort(), ["0:0", "0:1", "0:2"]);
    check("free: and the cursor steps over them", [r.m.line, r.m.w], [0, 3]);
    r = K.matcherHear(r.m, ctx({ 0: [true, true, true, false] }).slice(0, 1), ["amor"], true);
    check("free: the next heard word is then the next hearable one", r.hits.map(h => h.line + ":" + h.w), ["0:3"]);
    r = K.matcherHear(K.matcherSync(K.matcherNew(), 1), ctx().slice(1, 2), ["eu"], true);
    check("free: and the ones before it", r.hits.map(h => h.line + ":" + h.w).sort(), ["1:0", "1:1"]);
    r = K.matcherHear(K.matcherSync(K.matcherNew(), 2), ctx().slice(2, 3), ["cantar"], true);
    check("free: six of them do not push a word out of the lookahead", r.hits.some(h => h.w === 6), true);
    check("free: an unhearable word is never itself a match", K.matcherHear(K.matcherSync(K.matcherNew(), 0), ctx().slice(0, 1), ["piroca"], true).hits, []);
    // Judged: a words run leaves a line of only those out; the same line in timing alone is judged.
    let t = K.tallyTime(K.tallyNew("yeah piroca"), 3000, true);
    check("free: a line of only unhearable words is not judged (words run)", K.lineResult(K.withFree(t, oov), true), null);
    check("free: nor are the others affected", K.lineResult(K.withFree(K.tallyTime(K.tallyNew("yeah amor"), 3000, true), oov), true) !== null, true);
    check("free: timing alone still judges it", K.lineResult(K.withFree(t, oov), false) !== null, true);
    // The combo runs through such a line, and such a line does not end it.
    const lines = [{ text: "a b" }, { text: "yeah piroca" }, { text: "c" }];
    const sungMap = { 0: [true, true], 2: [true] };
    check("free: the combo runs through a line of only unhearable words", K.comboRun(sungMap, lines, 2, 0, oov), 3);
    check("free: and is cut by it without the list", K.comboRun(sungMap, lines, 2, 0), 1);
    check("free: a line of only those leaves the combo alive", K.comboSurvives(K.tallyNew("yeah piroca"), {}, 1, oov), true);
    check("free: the same line with nothing sung does not, without the list", K.comboSurvives(K.tallyNew("yeah piroca"), {}, 1), false);
}

// ── Lines not to be counted: skipped by the user, or overlapped in a duet ─────
{
    const lines = [{ t: 0, text: "oh oh oh" }, { t: 4, text: "real line here" }, { t: 8, text: "oh oh oh" }];
    check("skip: a mark names the line and its words", K.skipMark(lines, 1), "1:real line here");
    check("skip: no such line is no mark", K.skipMark(lines, 9), "");
    check("skip: a mark gives its line back", K.skipSet(lines, ["0:oh oh oh"]), { 0: true });
    check("skip: the same words on another line are not skipped by it", K.skipSet(lines, ["0:oh oh oh"])[2], undefined);
    check("skip: lyrics that came back different match nothing", K.skipSet([{ t: 0, text: "other" }, ...lines.slice(1)], ["0:oh oh oh"]), {});
    check("skip: a mark whose line moved matches nothing", K.skipSet(lines.slice(1), ["1:real line here"]), {});
    check("skip: toggling adds then removes", [K.skipToggle([], "0:a"), K.skipToggle(["0:a"], "0:a")], [["0:a"], []]);
    check("skip: toggling leaves the original alone", (() => { const m = ["0:a"]; K.skipToggle(m, "1:b"); return m; })(), ["0:a"]);
    check("skip: an empty mark changes nothing", K.skipToggle(["0:a"], ""), ["0:a"]);
    check("skip: the file is made safe",
        K.sanitizeSkips({ songs: { "a::b": ["0:x", "0:x", "no colon", 5, "1:" + "y".repeat(400)], "": ["0:x"], c: "nope", d: [] } }), { "a::b": ["0:x"] });
    check("skip: junk is no skips", [K.sanitizeSkips(null), K.sanitizeSkips("x"), K.sanitizeSkips({ songs: 3 })], [{}, {}, {}]);
    check("skip: a skipped line is not counted in the song", K.singableCount(lines, { 0: true, 2: true }), 1);
    check("skip: and none skipped is the count", K.singableCount(lines), 3);
    // Through the combo: a skipped line is stepped over, not a break.
    const song = [{ text: "a b" }, { text: "oh oh" }, { text: "c" }];
    const sung = { 0: [true, true], 2: [true] };
    check("skip: the combo runs through a skipped line", K.comboRun(sung, song, 2, 0, undefined, l => l === 1), 3);
    check("skip: and is cut by it otherwise", K.comboRun(sung, song, 2, 0), 1);
    check("skip: a skipped line leaves the combo alive", K.comboSurvives(K.tallyNew("oh oh"), {}, 1, undefined, l => l === 1), true);
}
{
    // A duet: line 1 starts while line 0 still has 2 s to run. Lines without a duration never overlap.
    const duet = [{ t: 10, dur: 4, text: "a a a a" }, { t: 12, dur: 4, text: "b b b b" }, { t: 20, dur: 2, text: "c c" }, { t: 21.7, dur: 2, text: "d d" }, { t: 30, text: "e" }, { t: 30.2, text: "f" }];
    const ov = K.overlapMap(duet);
    check("overlap: a pair that share 2 s", ov, { 0: [1], 1: [0] });
    check("overlap: 0.3 s of shared time is not one", ov[2], undefined);
    check("overlap: lines with no duration do not overlap", [ov[4], ov[5]], [undefined, undefined]);
    const half = [true, true, false, false];
    check("overlap: the line not sung is excused when the other was", [K.overlapExcused(ov, { 0: [true, true, true, true], 1: [false, false, false, false] }, 1)], [true]);
    check("overlap: not when its partner was not sung either", K.overlapExcused(ov, { 0: [false, false, false, false], 1: [false, false, false, false] }, 1), false);
    check("overlap: not when it was sung itself", K.overlapExcused(ov, { 0: [true, true, true, true], 1: half }, 1), false);
    check("overlap: half a partner is enough", K.overlapExcused(ov, { 0: half, 1: [] }, 1), true);
    check("overlap: a line with no partner is never excused", K.overlapExcused(ov, {}, 2), false);
    check("overlap: the other way round too", K.overlapExcused(ov, { 0: [], 1: [true, true, true, true] }, 0), true);
}

// ── The session ───────────────────────────────────────────────────────────────
{
    const sung = () => { let t = K.tallyNew("a line of words"); for (let i = 0; i < 20; i++) t = K.tallyTime(t, 100, true); return t; };
    const silent = () => { let t = K.tallyNew("a line of words"); for (let i = 0; i < 20; i++) t = K.tallyTime(t, 100, false); return t; };
    let s = K.sessionNew();
    check("session: starts empty", [K.percent(s), s.count], [0, 0]);
    s = K.sessionFinish(s, sung(), false);
    s = K.sessionFinish(s, sung(), false);
    check("session: two sung lines", [K.percent(s), s.count], [100, 2]);
    s = K.sessionFinish(s, silent(), false);
    check("session: a missed line drops the percent", [K.percent(s), s.count, s.miss], [67, 3, 1]);
    check("session: a line does not move the combo (the words do)", [s.streak, s.best], [0, 0]);
    check("session: the words in judged lines are counted", [s.wordsHit, s.wordsTotal], [0, 12]);
    check("session: and each line is on the timeline", s.timeline.map(x => x.judgment), ["perfect", "perfect", "miss"]);
    const before = JSON.stringify(s);
    s = K.sessionFinish(s, K.tallyNew("a"), false);
    check("session: a line never on counts for nothing", JSON.stringify(s), before);
    const blip = K.tallyTime(K.tallyNew("a line"), 300, false);
    check("session: a line barely on isn't judged (seeked into)", JSON.stringify(K.sessionFinish(s, blip, false)), before);
    const instrumental = K.tallyTime(K.tallyNew(""), 5000, false);
    check("session: an instrumental has no words, so isn't scored", JSON.stringify(K.sessionFinish(s, instrumental, false)), before);
}

// ── Which line, steadily (the underline bug) ──────────────────────────────────
check("stepLine: the first line is a seek (nothing before it to keep)", K.stepLine(-1, 4, 20, 0), { idx: 4, seek: true });
check("stepLine: the same line is nothing", K.stepLine(4, 4, 20.1, 20), { idx: 4, seek: false });
check("stepLine: walking on is not a seek", K.stepLine(4, 5, 24.1, 24), { idx: 5, seek: false });
check("stepLine: skipping a line (overlapping lines) is not a seek", K.stepLine(4, 6, 24.1, 24), { idx: 6, seek: false });
// THE bug: the clock steps back a few tenths at a line boundary. It must stay on the line it was on,
// and it must NOT be a seek (a seek drops what was just sung).
check("stepLine: a blip back across a boundary stays on the line, not a seek", K.stepLine(5, 4, 24.0, 24.3), { idx: 5, seek: false });
check("stepLine: even a half-second step back", K.stepLine(5, 4, 23.8, 24.3), { idx: 5, seek: false });
check("stepLine: a step back of a second is still noise", K.stepLine(5, 4, 23.4, 24.3), { idx: 5, seek: false });
check("stepLine: two lines back is a real seek", K.stepLine(5, 3, 20, 24.3), { idx: 3, seek: true });
check("stepLine: more than a second and a half back is a real seek", K.stepLine(5, 4, 22.0, 24.3), { idx: 4, seek: true });
check("stepLine: a jump forward past three seconds is a seek", K.stepLine(4, 9, 60, 24), { idx: 9, seek: true });
check("stepLine: a forward jump under three seconds is not", K.stepLine(4, 6, 26.5, 24), { idx: 6, seek: false });
{
    // Replayed: a line sung, the clock jitters back and forth across the boundary four times.
    let from = 5, last = 24.4, kept = true;
    for (const pos of [24.5, 24.25, 24.6, 24.2, 24.7, 24.3, 24.9]) {
        const idx = pos < 24.5 ? 4 : 5;                       // the raw line the jittery clock says
        const r = K.stepLine(from, idx, pos, last);
        if (r.seek || r.idx !== 5) kept = false;
        from = r.idx; last = pos;
    }
    check("stepLine: a clock jittering across a boundary never seeks, never leaves the line", kept, true);
}

// ── The game ──────────────────────────────────────────────────────────────────
check("judge: the bands", [K.judge(1), K.judge(0.9), K.judge(0.899), K.judge(0.7), K.judge(0.699), K.judge(0.5), K.judge(0.499), K.judge(0)],
      ["perfect", "perfect", "great", "great", "good", "good", "miss", "miss"]);

// The rank bands, exactly as specified: SS above 95, S above 90, A 80-89, B 70-79, C 60-69, F below.
for (const [acc, want] of [[100, "SS+"], [99.9, "SS"], [97.2, "SS"], [95, "SS"], [94.9, "S"], [92, "S"], [90, "S"], [89.9, "A"], [85, "A"], [80, "A"],
                           [79.9, "B"], [75, "B"], [70, "B"], [69.9, "C"], [65, "C"], [60, "C"], [59.9, "F"], [30, "F"], [0, "F"]])
    check("rank: " + acc + "% is " + want, K.rankFor(acc), want);
check("rank: judged as it is DISPLAYED (89.96 shows as 90.0, an S)", K.rankFor(89.96), "S");
check("rank: and 94.96 shows as 95.0, an SS", K.rankFor(94.96), "SS");
check("rank: 89.94 shows as 89.9, an A", K.rankFor(89.94), "A");
check("rank: nonsense is F", [K.rankFor(NaN), K.rankFor(undefined), K.rankFor(-5)], ["F", "F", "F"]);

{
    const sung = (voiced, ms, words = "a line of words") => {
        let t = K.tallyNew(words);
        for (let i = 0; i < ms / 100; i++) t = K.tallyTime(t, 100, i < voiced / 100);
        return t;
    };
    check("lineResult: a line sung all through is a perfect, with its word count", K.lineResult(sung(2000, 2000), false), { points: 1, judgment: "perfect", hit: 0, words: 4 });
    check("lineResult: a silent line is a miss", K.lineResult(sung(0, 2000), false), { points: 0, judgment: "miss", hit: 0, words: 4 });
    check("lineResult: the words heard are counted", K.lineResult(K.tallyMark(K.tallyMark(sung(2000, 2000), 0), 2), true).hit, 2);
    check("lineResult: 45% voiced is already full marks", K.lineResult(sung(900, 2000), false).judgment, "perfect");
    check("lineResult: 40% voiced is a hair short of it (0.89)", K.lineResult(sung(800, 2000), false).judgment, "great");
    check("lineResult: 20% voiced is a miss in timing-only", K.lineResult(sung(400, 2000), false).judgment, "miss");
    check("lineResult: never on is not judged", K.lineResult(K.tallyNew("a b"), false), null);
    check("lineResult: barely on is not judged", K.lineResult(K.tallyTime(K.tallyNew("a b"), 300, true), false), null);
    check("lineResult: an instrumental is not judged", K.lineResult(K.tallyTime(K.tallyNew(""), 5000, false), false), null);

    // The combo and the score.
    let s = K.sessionNew();
    const perfect = { points: 1, judgment: "perfect" }, great = { points: 0.8, judgment: "great" }, miss = { points: 0.1, judgment: "miss" };
    // The score is the line's value times a multiplier for the WORD combo held when the line is judged.
    s = K.sessionAdd(s, perfect);
    check("score: a perfect with no combo is 300 at x1", [s.score, s.perfect], [300, 1]);
    check("score: a line does not touch the combo", [s.streak, s.best], [0, 0]);
    check("score: 25 words in, x1.5", K.sessionAdd(K.sessionCombo(K.sessionNew(), 25), perfect).score, 450);
    check("score: 50 words in, x2", K.sessionAdd(K.sessionCombo(K.sessionNew(), 50), perfect).score, 600);
    check("score: a great is 200 at the multiplier", K.sessionAdd(K.sessionCombo(K.sessionNew(), 50), great).score, 400);
    check("score: a miss is worth nothing at any combo", K.sessionAdd(K.sessionCombo(K.sessionNew(), 50), miss).score, 0);
    check("score: the multiplier tops out at x3 (100 words)", [K.sessionAdd(K.sessionCombo(K.sessionNew(), 100), perfect).score, K.sessionAdd(K.sessionCombo(K.sessionNew(), 500), perfect).score], [900, 900]);

    // The combo itself.
    let c = K.sessionCombo(K.sessionNew(), 7);
    check("combo: set, and the best follows", [c.streak, c.best], [7, 7]);
    c = K.sessionCombo(c, 3);
    check("combo: it can go down without losing the best", [c.streak, c.best], [3, 7]);
    c = K.sessionBreak(c);
    check("combo: a break zeroes it and keeps the best", [c.streak, c.best], [0, 7]);
    check("combo: breaking nothing is the same session", K.sessionBreak(K.sessionNew()).streak, 0);
    check("combo: a combo is never negative or fractional", [K.sessionCombo(K.sessionNew(), -4).streak, K.sessionCombo(K.sessionNew(), 2.6).streak], [0, 3]);
    check("combo: doesn't mutate its input", (() => { const o = K.sessionNew(); K.sessionCombo(o, 9); return o.streak; })(), 0);
    check("accuracy: a line's judgment does not depend on the combo", K.accuracy(K.sessionAdd(K.sessionCombo(K.sessionNew(), 90), perfect)), 100);
    check("accuracy: the mean of the points, a percent", Math.round(K.accuracy(K.sessionAdd(K.sessionAdd(K.sessionNew(), perfect), miss)) * 1000) / 1000, 55);
    check("accuracy: nothing judged is 0", K.accuracy(K.sessionNew()), 0);
}

check("formatScore: thousands", [K.formatScore(0), K.formatScore(999), K.formatScore(1000), K.formatScore(1234567)], ["0", "999", "1,000", "1,234,567"]);
check("formatScore: rounds, and nonsense is 0", [K.formatScore(1499.6), K.formatScore(NaN), K.formatScore(-5), K.formatScore(undefined)], ["1,500", "0", "0", "0"]);

// ── SS+ ───────────────────────────────────────────────────────────────────────
check("SS+: exactly 100%", [K.rankFor(100), K.rankFor(99.95)], ["SS+", "SS+"]);
check("SS+: 99.9 is an SS, the best of the rest", K.rankFor(99.9), "SS");
check("SS+: the bands in order", K.RANKS, ["SS+", "SS", "S", "A", "B", "C", "F"]);
check("displayAccuracy: 100 is 100", K.displayAccuracy(100), 100);
check("displayAccuracy: 99.96 would ROUND to 100.0 — it is capped at 99.9", K.displayAccuracy(99.96), 99.9);
check("displayAccuracy: and so is 99.999", K.displayAccuracy(99.999), 99.9);
check("displayAccuracy: lower values round as before", [K.displayAccuracy(89.96), K.displayAccuracy(92.44)], [90, 92.4]);
{
    const flawless = (n) => { let s = K.sessionNew(); for (let i = 0; i < n; i++) s = K.sessionAdd(s, { points: 1, judgment: "perfect" }); return s; };
    check("SS+: every line a perfect is an SS+", K.result(flawless(10), 10).rank, "SS+");
    let nearly = flawless(19);
    nearly = K.sessionAdd(nearly, { points: 0.99, judgment: "perfect" });
    check("SS+: one line a hair under is NOT (99.95 must not display as a flawless 100.0)", [K.result(nearly, 20).accuracy, K.result(nearly, 20).rank], [99.9, "SS"]);
}

// ── Mods ──────────────────────────────────────────────────────────────────────
check("mods: the four codes, in order (HD+ is the code HDP)", K.MOD_ORDER, ["HD", "HDP", "HR", "TH"]);
check("mods: flags to a list", [K.modList({}), K.modList({ hd: true }), K.modList({ th: true, hd: true, hr: true }), K.modList(undefined)], [[], ["HD"], ["HD", "HR", "TH"], []]);
check("mods: only a real true counts", K.modList({ hd: "yes", hr: 1 }), []);
check("mods: the multipliers", [K.modMultiplier([]), K.modMultiplier(["HD"]), K.modMultiplier(["HR"]), K.modMultiplier(["TH"])], [1, 1.06, 1.12, 1.2]);
check("mods: they multiply", [K.modMultiplier(["HD", "HR"]), K.modMultiplier(["HD", "HR", "TH"])], [1.19, 1.42]);
check("mods: an unknown one is nothing", K.modMultiplier(["XX", "HD"]), 1.06);
check("mods: Hard Rock earns nothing without words to be strict about", [K.effectiveMods(["HD", "HR", "TH"], false), K.effectiveMods(["HD", "HR", "TH"], true)], [["HD", "TH"], ["HD", "HR", "TH"]]);
check("mods: a stored string is cleaned (known, once each, in order)", [K.cleanMods("th+HD"), K.cleanMods("HD+HD+zz"), K.cleanMods("<script>"), K.cleanMods(undefined), K.cleanMods("hd hr")], ["HD+TH", "HD", "", "", "HD+HR"]);
check("mods: a string back to a list", [K.modsOf("HD+TH"), K.modsOf("")], [["HD", "TH"], []]);
check("mods: every mod has a name, a label, a note and a multiplier above 1", K.MOD_ORDER.every(m => K.MODS[m].name && K.MODS[m].label && K.MODS[m].note && K.MODS[m].mult > 1), true);

// Hidden Lyrics has two levels: HD (partial) and HD+ (everything).
check("HD levels: 0 is off, 1 is HD, 2 is HD+", [K.modList({ hidden: 0 }), K.modList({ hidden: 1 }), K.modList({ hidden: 2 })], [[], ["HD"], ["HDP"]]);
check("HD levels: HD+ takes the place of HD, never both", [K.modList({ hidden: 2, hd: true }), K.modList({ hidden: 2, hr: true, th: true })], [["HDP"], ["HDP", "HR", "TH"]]);
check("HD levels: nonsense is off", [K.modList({ hidden: 3 }), K.modList({ hidden: "yes" }), K.modList({ hidden: -1 })], [[], [], []]);
check("HD levels: the multipliers differ (HD+ is worth more)", [K.modMultiplier(["HD"]), K.modMultiplier(["HDP"])], [1.06, 1.25]);
ok("HD levels: HD+ is worth more than HD", K.MODS.HDP.mult > K.MODS.HD.mult);
check("HD levels: with the others", [K.modMultiplier(["HDP", "HR"]), K.modMultiplier(["HDP", "HR", "TH"])], [1.4, 1.68]);
check("HD levels: HD+ is shown as HD+, the code is HDP", [K.modLabel("HDP"), K.modLabel("HD"), K.modLabel("TH"), K.modLabel("nope")], ["HD+", "HD", "TH", ""]);
check("HD levels: a list as one line", [K.modsText(["HDP", "TH"]), K.modsText("HD+HR"), K.modsText([]), K.modsText("")], ["HD+ TH", "HD HR", "", ""]);
check("HD levels: a stored string keeps HD+ and drops the HD it replaces", [K.cleanMods("HD+HDP+TH"), K.cleanMods("hdp"), K.cleanMods("TH+HDP+HD")], ["HDP+TH", "HDP", "HDP+TH"]);
check("HD levels: which hide a run has", [K.hideModeOf([]), K.hideModeOf(["HD"]), K.hideModeOf(["HDP"]), K.hideModeOf(["HD", "TH"]), K.hideModeOf(["HDP", "HR"]), K.hideModeOf(undefined)], ["", "partial", "all", "partial", "all", ""]);
check("HD levels: neither hide changes the judging", [K.rules(["HD"]), K.rules(["HDP"])], [K.RULES_NORMAL, K.RULES_NORMAL]);
check("HD levels: a result carries HD+ under its code", K.result(K.sessionAdd(K.sessionNew(), { points: 1, judgment: "perfect" }), 1, false, ["HDP"]).mods, "HDP");
check("HD levels: and its multiplier", K.result(K.sessionAdd(K.sessionNew(), { points: 1, judgment: "perfect" }), 1, false, ["HDP"]).modMult, 1.25);
check("HD levels: a stored run keeps HDP", K.record(K.dbNew(), { accuracy: 80, score: 1, mods: "HDP+TH" }, { artist: "a", title: "b" }, 1).entry.best.mods, "HDP+TH");

// The rules each mod sets.
check("rules: none is the normal rules", K.rules([]), K.RULES_NORMAL);
check("rules: HD changes no judging", K.rules(["HD"]), K.RULES_NORMAL);
check("rules: HR is stricter wording only", [K.rules(["HR"]).strictWords, K.rules(["HR"]).wordFull, K.rules(["HR"]).timingFull, K.rules(["HR"]).lead], [true, 0.9, 0.45, 0.15]);
check("rules: TH tightens every timing number", (({ lead, tail, openLead, graceMs, timingFull }) => [lead, tail, openLead, graceMs, timingFull])(K.rules(["TH"])), [0.05, 0.1, 0.3, 500, 0.65]);
check("rules: TH does not touch the wording", [K.rules(["TH"]).strictWords, K.rules(["TH"]).wordFull], [false, 0.7]);
check("rules: both together", [K.rules(["HR", "TH"]).strictWords, K.rules(["HR", "TH"]).timingFull], [true, 0.65]);
check("rules: doesn't mutate the normal rules", (() => { K.rules(["HR", "TH"]); return K.RULES_NORMAL.strictWords + "/" + K.RULES_NORMAL.lead; })(), "false/0.15");

// Hard Rock: wording.
ok("HR: normal still takes a sound-alike", K.sameWord("wheel", "will", false));
ok("HR: strict does not", !K.sameWord("wheel", "will", true));
ok("HR: strict takes the exact word", K.sameWord("will", "will", true));
ok("HR: strict takes one letter off in a long word (85%: seven letters or more)", K.sameWord("believin", "believing", true) && K.sameWord("beautful", "beautiful", true));
ok("HR: but not in a six-letter one (one edit is 83%)", !K.sameWord("lovin", "loving", true) && !K.sameWord("heavn", "heaven", true));
ok("HR: nor two letters off in a long one", !K.sameWord("beutful", "beautiful", true));
ok("HR: never a short word that is merely close", !K.sameWord("the", "she", true) && !K.sameWord("no", "know", true));
{
    const ctx = [{ line: 0, words: K.words("we will rock you"), flags: [false, false, false, false] }];
    const heard = K.words("we wheel rack you");
    check("HR: 'close enough' lights all four, as it always did", K.matcherHear(K.matcherSync(K.matcherNew(), 0), ctx, heard, true).hits.length, 4);
    check("HR: strict lights only the two sung exactly", K.matcherHear(K.matcherSync(K.matcherNew(), 0), ctx, heard, true, true).hits.map(h => h.w), [0, 3]);
}
{
    let t = K.tallyNew("a b c d e f g h i j");
    for (let i = 0; i < 9; i++) t = K.tallyMark(t, i);              // 9 of 10 words
    for (let i = 0; i < 30; i++) t = K.tallyTime(t, 100, true);
    check("HR: 80% of the words is full marks normally (70% is enough)", K.wordScore(K.tallyMark(K.tallyMark(K.tallyNew("a b c d e f g h i j"), 0), 1), K.rules([])) < 1, true);
    const eight = [0, 1, 2, 3, 4, 5, 6, 7].reduce((a, w) => K.tallyMark(a, w), K.tallyNew("a b c d e f g h i j"));
    check("HR: 8 of 10 is full marks normally", K.wordScore(eight, K.rules([])), 1);
    check("HR: and not under Hard Rock (it wants 90%)", K.wordScore(eight, K.rules(["HR"])) < 1, true);
    check("HR: 9 of 10 is full marks under Hard Rock", K.wordScore(t, K.rules(["HR"])), 1);
    check("HR: so a line's points are lower for the same singing", K.points(eight, true, K.rules(["HR"])) < K.points(eight, true, K.rules([])), true);
}

// Time-Hell: timing.
{
    const lines = [{ t: 10, dur: 4, text: "one two" }, { t: 14, dur: 4, text: "three" }];
    ok("TH: normal counts a voice 0.3 s early", K.inWindow(lines, 0, 10 - 0.3 + 0.01, K.rules([])) === false && K.inWindow(lines, 0, 10 - 0.1, K.rules([])));
    ok("TH: 0.1 s early is in the window normally", K.inWindow(lines, 0, 9.9, K.rules([])));
    ok("TH: and out of it under Time-Hell (0.05)", !K.inWindow(lines, 0, 9.9, K.rules(["TH"])));
    ok("TH: 0.3 s after the line ends is in normally (0.35)", K.inWindow(lines, 0, 14.3, K.rules([])));
    ok("TH: out of it under Time-Hell (0.1)", !K.inWindow(lines, 0, 14.3, K.rules(["TH"])));
    ok("TH: a line opens 0.8 s ahead normally", K.lineOpen(lines, 1, 13.3, K.rules([])));
    ok("TH: only 0.3 s ahead under Time-Hell", !K.lineOpen(lines, 1, 13.3, K.rules(["TH"])) && K.lineOpen(lines, 1, 13.8, K.rules(["TH"])));
    let t = K.tallyNew("a b");
    for (let i = 0; i < 20; i++) t = K.tallyTime(t, 100, i < 10);        // voiced half the window
    check("TH: half the window voiced is full marks normally (45%)", K.timing(t, K.rules([])), 1);
    check("TH: not under Time-Hell (65%)", K.timing(t, K.rules(["TH"])) < 1, true);
    check("TH: 65% voiced is full marks under Time-Hell", K.timing((() => { let u = K.tallyNew("a b"); for (let i = 0; i < 20; i++) u = K.tallyTime(u, 100, i < 13); return u; })(), K.rules(["TH"])), 1);
}
check("rules default: no rules given is the normal behaviour", [K.timing(K.tallyTime(K.tallyNew("a"), 1000, true)), K.inWindow([{ t: 5, text: "x" }], 0, 4.9)], [1, true]);

// The multiplier: on the SCORE only.
{
    const p = { points: 1, judgment: "perfect" };
    check("multiplier: a mod's multiplier is on the line's score", [K.sessionAdd(K.sessionNew(), p).score, K.sessionAdd(K.sessionNew(), p, 1.2).score, K.sessionAdd(K.sessionNew(), p, 1.42).score], [300, 360, 426]);
    check("multiplier: and it stacks with the word combo", K.sessionAdd(K.sessionCombo(K.sessionNew(), 50), p, 1.2).score, 720);
    check("multiplier: never on the accuracy", K.accuracy(K.sessionAdd(K.sessionNew(), p, 3)), 100);
    check("multiplier: nonsense is x1", [K.sessionAdd(K.sessionNew(), p, 0).score, K.sessionAdd(K.sessionNew(), p, -2).score, K.sessionAdd(K.sessionNew(), p, undefined).score], [300, 300, 300]);
    check("multiplier: sessionFinish carries it", K.sessionFinish(K.sessionNew(), (() => { let t = K.tallyNew("a line"); for (let i = 0; i < 20; i++) t = K.tallyTime(t, 100, true); return t; })(), false, K.rules([]), 1.2).score, 360);
}
{
    let s = K.sessionNew();
    for (let i = 0; i < 5; i++) s = K.sessionAdd(s, { points: 1, judgment: "perfect" }, 1.19);
    const r = K.result(s, 5, true, ["HD", "HR"]);
    check("result: carries the mods and their multiplier", [r.mods, r.modMult], ["HD+HR", 1.19]);
    check("result: Hard Rock without words is dropped from what it earned", [K.result(s, 5, false, ["HD", "HR"]).mods, K.result(s, 5, false, ["HD", "HR"]).modMult], ["HD", 1.06]);
    check("result: no mods", [K.result(s, 5, true).mods, K.result(s, 5, true).modMult], ["", 1]);
    check("result: mods may arrive as a string", K.result(s, 5, true, "TH+HD").mods, "HD+TH");
}
{
    const run = { accuracy: 90, score: 1000, mods: "HD+TH" };
    const r = K.record(K.dbNew(), run, { artist: "a", title: "b" }, 1);
    check("record: the run keeps its mods", [r.entry.best.mods, r.entry.last.mods], ["HD+TH", "HD+TH"]);
    check("sanitize: a hostile mods string is cleaned to the known mods", K.sanitize({ songs: { "a::b": { title: "b", best: { accuracy: 50, mods: "HD+<img src=x>+TH+rm -rf" } } } }).songs["a::b"].best.mods, "HD+TH");
}

// ── Song end and the result ───────────────────────────────────────────────────
{
    const lines = [{ t: 0, dur: 3, text: "one two" }, { t: 4, dur: 3, text: "three four" }, { t: 8, dur: 4, text: "" }];
    check("lastSingable: skips a silent last row", K.lastSingable(lines), 1);
    check("lastSingable: none", K.lastSingable([{ t: 0, text: "" }]), -1);
    check("singableCount: lines that sing", K.singableCount(lines), 2);
    check("songDone: not while the last line is on", K.songDone(lines, 6), false);
    check("songDone: not in the beat after it", K.songDone(lines, 7.5), false);
    check("songDone: after it, with a beat to spare", K.songDone(lines, 8.6), true);
    check("songDone: the grace is a parameter", K.songDone(lines, 7.2, 0.1), true);
    check("songDone: no lyrics is never done", K.songDone([], 100), false);
}
{
    let s = K.sessionNew();
    for (let i = 0; i < 8; i++) s = K.sessionAdd(s, { points: 1, judgment: "perfect" });
    s = K.sessionAdd(s, { points: 0.6, judgment: "good" });
    const r = K.result(s, 12);
    check("result: accuracy to a tenth", r.accuracy, Math.round((8.6 / 9) * 1000) / 10);
    check("result: its rank (95.6% is an SS)", r.rank, "SS");
    let s2 = K.sessionNew();
    for (let i = 0; i < 7; i++) s2 = K.sessionAdd(s2, { points: 1, judgment: "perfect" });
    for (let i = 0; i < 2; i++) s2 = K.sessionAdd(s2, { points: 0.6, judgment: "good" });
    check("result: 91.1% is an S", [K.result(s2, 12).accuracy, K.result(s2, 12).rank], [91.1, "S"]);
    const withCombo = K.result(K.sessionCombo(s, 9), 12, true);
    check("result: the counts", [r.perfect, r.great, r.good, r.miss, r.lines, r.total, withCombo.maxCombo], [8, 0, 1, 0, 9, 12, 9]);
    check("result: carries whether words were judged, the words, and the timeline", [withCombo.wordsMode, r.wordsMode, withCombo.wordsTotal, withCombo.timeline.length], [true, false, 0, 9]);
    check("result: no miss is a full combo", r.fullCombo, true);
    check("result: nine of twelve lines is ranked", r.ranked, true);
    check("result: a miss is not a full combo", K.result(K.sessionAdd(s, { points: 0, judgment: "miss" }), 12).fullCombo, false);
    check("result: five of twelve lines is NOT ranked (less than half the song)", K.result(K.sessionAdd(K.sessionAdd(K.sessionAdd(K.sessionAdd(K.sessionAdd(K.sessionNew(), { points: 1, judgment: "perfect" }), { points: 1, judgment: "perfect" }), { points: 1, judgment: "perfect" }), { points: 1, judgment: "perfect" }), { points: 1, judgment: "perfect" }), 12).ranked, false);
    check("result: two lines of a two-line song is not ranked (fewer than three)", K.result(K.sessionAdd(K.sessionAdd(K.sessionNew(), { points: 1, judgment: "perfect" }), { points: 1, judgment: "perfect" }), 2).ranked, false);
    check("result: nothing played is not a full combo", K.result(K.sessionNew(), 10).fullCombo, false);
}

// ── The scores on disk ────────────────────────────────────────────────────────
{
    const meta = { artist: "Queen", title: "We Will Rock You", album: "News of the World", art: "https://i.scdn.co/image/abc" };
    const run = (acc, score, extra = {}) => ({ accuracy: acc, score, maxCombo: 10, perfect: 8, great: 1, good: 1, miss: 0, lines: 10, total: 12, fullCombo: true, ...extra });
    check("songKey: case and spacing fold", K.songKey("  QUEEN ", "We  will rock YOU"), "queen::we will rock you");
    check("songKey: no title is no song", K.songKey("Queen", ""), "");
    check("songKey: an unknown artist is still a song", K.songKey(undefined, "Intro"), "::intro");
    ok("coverName: eight hex and a fixed extension", /^[0-9a-f]{8}\.img$/.test(K.coverName("queen::x")));
    check("coverName: stable", K.coverName("a::b"), K.coverName("a::b"));
    ok("coverName: different songs differ", K.coverName("a::b") !== K.coverName("a::c"));

    let r = K.record(K.dbNew(), run(92.4, 9000), meta, 1000);
    check("record: the first play is a new best", [r.newBest, r.previousBest, r.entry.plays], [true, null, 1]);
    check("record: stored under the song's key", Object.keys(r.db.songs), ["queen::we will rock you"]);
    check("record: the rank is derived", r.entry.best.rank, "S");
    check("record: the art and album kept", [r.entry.art, r.entry.album], ["https://i.scdn.co/image/abc", "News of the World"]);
    let db = r.db;
    r = K.record(db, run(88, 12000), meta, 2000);
    check("record: a lower accuracy is not a new best, even with a higher score", [r.newBest, r.entry.best.accuracy, r.entry.last.accuracy, r.entry.plays], [false, 92.4, 88, 2]);
    check("record: the previous best is reported", r.previousBest.accuracy, 92.4);
    db = r.db;
    r = K.record(db, run(92.4, 9500), meta, 3000);
    check("record: the same accuracy and a higher score is a new best", [r.newBest, r.entry.best.score], [true, 9500]);
    check("record: the history is newest first", r.entry.history.map(h => h.at), [3000, 2000, 1000]);
    db = r.db;
    let many = db;
    for (let i = 0; i < 14; i++) many = K.record(many, run(60 + i, 100 + i), meta, 4000 + i).db;
    check("record: the history is bounded", many.songs["queen::we will rock you"].history.length, 10);
    check("record: plays keep counting", many.songs["queen::we will rock you"].plays, 3 + 14);
    check("record: no title records nothing", K.record(db, run(90, 1), { artist: "x", title: "" }, 1).entry, null);
    check("record: doesn't mutate its input", JSON.stringify(K.record(db, run(99, 1), meta, 9).db) !== JSON.stringify(db) && db.songs["queen::we will rock you"].plays, 3);

    // The cover.
    const name = K.coverName("queen::we will rock you");
    let withC = K.withCover(db, "queen::we will rock you", name);
    check("withCover: recorded", withC.songs["queen::we will rock you"].cover, name);
    check("withCover: a wrong name is refused", K.withCover(db, "queen::we will rock you", "../../etc/passwd") === db, true);
    check("withCover: an unknown song is ignored", K.withCover(db, "no::such", K.coverName("no::such")) === db, true);
    check("record: the cover is kept while the art is the same", K.record(withC, run(70, 1), meta, 5).entry.cover, name);
    check("record: and dropped when the art changes (it must be fetched again)", K.record(withC, run(70, 1), { ...meta, art: "https://x/y.png" }, 5).entry.cover, "");
    check("record: no new art keeps the old", K.record(withC, run(70, 1), { ...meta, art: "" }, 5).entry.art, "https://i.scdn.co/image/abc");

    // Order and the header.
    let two = K.record(db, run(70, 100), { artist: "ABBA", title: "Waterloo" }, 5000).db;
    check("list: recent first", K.list(two, "recent").map(e => e.title), ["Waterloo", "We Will Rock You"]);
    check("list: by best score", K.list(two, "best").map(e => e.title), ["We Will Rock You", "Waterloo"]);
    check("list: by accuracy", K.list(two, "rank").map(e => e.best.rank), ["S", "B"]);
    check("summary: songs, plays and a count per rank", K.summary(two), { songs: 2, plays: 4, ranks: { "SS+": 0, SS: 0, S: 1, A: 0, B: 1, C: 0, F: 0 } });
    check("removeSong: gone", Object.keys(K.removeSong(two, "abba::waterloo").songs), ["queen::we will rock you"]);
    check("removeSong: an unknown key is the same db", K.removeSong(two, "x") === two, true);

    // The trust boundary: a hand-edited file.
    check("sanitize: junk is an empty db", [K.sanitize(null), K.sanitize("x"), K.sanitize({}), K.sanitize({ songs: 5 })].map(d => Object.keys(d.songs).length), [0, 0, 0, 0]);
    const round = K.sanitize(JSON.parse(JSON.stringify(two)));
    check("sanitize: a good document comes back the same", JSON.stringify(Object.keys(round.songs).sort()), JSON.stringify(Object.keys(two.songs).sort()));
    check("sanitize: and with its scores", round.songs["queen::we will rock you"].best.score, 9500);
    const evil = K.sanitize({ songs: {
        "x::y": { title: "Y", artist: "x", art: "javascript:alert(1)", cover: "../../x", plays: 1e12, best: { accuracy: 500, rank: "SS", score: -9, maxCombo: "lots", fullCombo: "yes" }, last: {}, history: "no" },
        "no title": { artist: "z" },
        "q::r": null,
    } });
    check("sanitize: a hostile entry is clamped, not trusted", (({ best, art, cover, plays, history }) => [best.accuracy, best.rank, best.score, best.maxCombo, best.fullCombo, art, cover, plays, history])(evil.songs["x::y"]),
          [100, "SS+", 0, 0, false, "", "", 1e6, []]);
    check("sanitize: an entry with no title is dropped, and a null one", Object.keys(evil.songs), ["x::y"]);
    check("sanitize: a rank is derived from the accuracy, not believed", K.sanitize({ songs: { "a::b": { title: "b", best: { accuracy: 40, rank: "SS" } } } }).songs["a::b"].best.rank, "F");
    const huge = {};
    for (let i = 0; i < 900; i++) huge["k" + i + "::t"] = { title: "t" + i, last: { at: i } };
    check("sanitize: the number of songs is bounded, the oldest go", Object.keys(K.sanitize({ songs: huge }).songs).length, 400);
    let capped = K.dbNew();
    for (let i = 0; i < 405; i++) capped = K.record(capped, run(70, 1), { artist: "a" + i, title: "t" + i }, i + 1).db;
    check("record: also bounded", Object.keys(capped.songs).length, 400);
    check("record: and it is the OLDEST that goes", capped.songs["a0::t0"], undefined);
}

// ── Headphones ────────────────────────────────────────────────────────────────
ok("headphones: a headset's form factor", K.isHeadphones({ "device.form-factor": "headset" }));
ok("headphones: a headphone form factor", K.isHeadphones({ "device.form-factor": "headphone" }));
ok("headphones: pulse's spelling", K.isHeadphones({ "device.form_factor": "Headset" }));
ok("headphones: by icon when there's no form factor", K.isHeadphones({ "device.icon-name": "audio-headphones" }));
ok("headphones: speakers are not", !K.isHeadphones({ "device.form-factor": "speaker" }));
ok("headphones: HDMI is not", !K.isHeadphones({ "device.icon-name": "audio-card-analog", "device.bus": "pci" }));
ok("headphones: nothing known is not (refuse, don't guess)", !K.isHeadphones({}));
ok("headphones: undefined is not", !K.isHeadphones(undefined));

// ── The lit line ──────────────────────────────────────────────────────────────
check("litHtml: sung words lit, the rest dim; a separator takes the word before it",
      K.litHtml("We will", [true, false], "#fff", "#888"),
      '<span style="color:#fff">We </span><span style="color:#888">will</span>');
check("litHtml: markup in a lyric is escaped", K.litHtml("a <b> & c", [], "#fff", "#888").includes("&lt;b&gt;"), true);
check("litHtml: an apostrophe stays inside its word",
      K.litHtml("don't go", [true, false], "#fff", "#888").startsWith('<span style="color:#fff">don\'t'), true);
check("litHtml: no flags is all dim", K.litHtml("hi", undefined, "#fff", "#888"), '<span style="color:#888">hi</span>');
check("litHtml: kana lights one character at a time",
      K.litHtml("あい", [true, false], "#fff", "#888"),
      '<span style="color:#fff">あ</span><span style="color:#888">い</span>');

if (failures.length) {
    console.log(failures.join("\n"));
    console.log(`\n${pass} passed, ${failures.length} FAILED`);
    process.exit(1);
}
console.log(`${pass} passed, 0 failed`);
