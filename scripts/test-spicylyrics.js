// ── test-spicylyrics.js ───────────────────────────────────────────────────────
// Regression tests for services/spicylyrics.js, the Spicy Lyrics payload mapper.
//
//     bun scripts/test-spicylyrics.js          (or: node scripts/test-spicylyrics.js)
//
// Safe to run: pure functions, no network. It never contacts the API — the fixtures below
// are hand-written stand-ins with placeholder syllables, which is all the mapper needs,
// since it only ever moves numbers and strings between two shapes.
//
// The cases that matter are the malformed ones. This payload arrives from a third-party
// service over the network, gets handed straight to a binary search in Lyrics.lineAt(),
// and a single out-of-order or zero-duration line silently scrolls the wrong words for a
// whole region of a song rather than failing where anyone would notice.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));

// spicylyrics.js pulls in the packed-payload decoder with QML's `.import`, which is not
// JavaScript. Both directives are stripped and objpack.js is evaluated into an `ObjPack`
// namespace by hand, so the tests still run the real files rather than copies that drift.
const objpackSrc = readFileSync(join(here, "..", "services", "objpack.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");

const src = readFileSync(join(here, "..", "services", "spicylyrics.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "")
    .replace(/^\s*\.import\s+.*$/m, "");

const ObjPack = new Function(objpackSrc + "\nreturn { unpack };")();
const S = new Function("ObjPack", src + "\nreturn { toLines };")(ObjPack);

let pass = 0, fail = 0;
function check(name, cond, detail) {
    if (cond) pass++;
    else { fail++; console.log(`  FAIL  ${name}${detail ? "  — " + detail : ""}`); }
}
function near(a, b, eps = 1e-9) { return Math.abs(a - b) <= eps; }

// A two-line syllable payload. "ex-am-ple" is split the way their API splits a word:
// every piece but the last carries IsPartOfWord.
const syllablePayload = {
    Type: "Syllable",
    StartTime: 1.0,
    Content: [
        {
            Lead: {
                StartTime: 1.0, EndTime: 3.0,
                Syllables: [
                    { Text: "ex",  StartTime: 1.0, EndTime: 1.4, IsPartOfWord: true },
                    { Text: "am",  StartTime: 1.4, EndTime: 1.7, IsPartOfWord: true },
                    { Text: "ple", StartTime: 1.7, EndTime: 2.2 },
                    { Text: "one", StartTime: 2.2, EndTime: 3.0 }
                ]
            }
        },
        {
            Lead: {
                StartTime: 4.0, EndTime: 6.0,
                // Flagged, because the line above is: a payload either encodes word
                // boundaries or it does not, and a line with no flags at all means
                // "nothing to mark here" rather than "every syllable ends a word".
                Syllables: [
                    { Text: "two", StartTime: 4.0, EndTime: 5.0, IsPartOfWord: false },
                    { Text: "end", StartTime: 5.0, EndTime: 6.0 }
                ]
            }
        }
    ]
};

// ── Shape ─────────────────────────────────────────────────────────────────────
console.log("toLines / syllable");
const out = S.toLines(syllablePayload);

check("reports the syllable kind", out.kind === "syllable");
check("keeps both lines", out.lines.length === 2);
check("line start is the lead start", near(out.lines[0].t, 1.0));
check("line duration spans the lead", near(out.lines[0].dur, 2.0));
check("keeps every syllable", out.lines[0].words.length === 4);
check("syllable start passes through", near(out.lines[0].words[0].t, 1.0));
check("duration is end minus start", near(out.lines[0].words[0].d, 0.4));

// Times are SECONDS and must NOT be rescaled — Lyrics.lines is already in seconds.
check("does not convert to milliseconds", out.lines[1].t < 100, `t=${out.lines[1].t}`);

// ── Word joining ──────────────────────────────────────────────────────────────
// IsPartOfWord is the whole reason spacing works. Pieces of one word must butt together;
// separate words must not.
console.log("word joining");
const w = out.lines[0].words;
check("joined syllable carries no space", w[0].text === "ex");
check("second joined syllable carries no space", w[1].text === "am");
check("word-final syllable carries a space", w[2].text === "ple ");
check("line text reassembles with spacing", out.lines[0].text === "example one");
check("line-final syllable has no trailing space", w[3].text === "one");
check("second line reassembles", out.lines[1].text === "two end");

// ── Line-timed payloads ───────────────────────────────────────────────────────
console.log("toLines / line");
const linePayload = {
    Type: "Line",
    Content: [
        { Text: "placeholder alpha", StartTime: 2.0, EndTime: 4.0 },
        { Text: "placeholder beta",  StartTime: 4.0, EndTime: 6.0 }
    ]
};
const lineOut = S.toLines(linePayload);
check("reports the line kind", lineOut.kind === "line");
check("carries the text", lineOut.lines[0].text === "placeholder alpha");
check("has no word list", lineOut.lines[0].words === null);
check("keeps the timing", near(lineOut.lines[1].t, 4.0));

// ── Ordering ──────────────────────────────────────────────────────────────────
// Lyrics.lineAt() binary-searches this. One misordered entry returns the wrong line for a
// whole region rather than failing anywhere visible.
console.log("ordering");
const shuffled = S.toLines({
    Type: "Line",
    Content: [
        { Text: "third",  StartTime: 30, EndTime: 32 },
        { Text: "first",  StartTime: 10, EndTime: 12 },
        { Text: "second", StartTime: 20, EndTime: 22 }
    ]
});
check("sorts lines by start time",
      shuffled.lines.map(l => l.text).join(",") === "first,second,third");

// ── Degenerate input ──────────────────────────────────────────────────────────
console.log("degenerate input");
check("null payload is none", S.toLines(null).kind === "none");
check("undefined payload is none", S.toLines(undefined).kind === "none");
check("string payload is none", S.toLines("nope").kind === "none");
check("empty object is none", S.toLines({}).kind === "none");
check("empty content is none", S.toLines({ Content: [] }).kind === "none");
check("content of nulls is none", S.toLines({ Content: [null, null] }).kind === "none");

check("static text becomes plain",
      S.toLines({ Type: "Static", Lyrics: "placeholder block" }).kind === "plain");
check("static text is carried",
      S.toLines({ Type: "Static", Lyrics: "placeholder block" }).plain === "placeholder block");

// The live API's Static shape: a Lines array of { Text }. This was mapped to "none".
{
    const r = S.toLines({ Type: "Static", Lines: [{ Text: "one" }, { Text: "two" }, null] });
    check("static Lines array becomes plain", r.kind === "plain", r.kind);
    check("static Lines are joined per line", r.plain === "one\ntwo\n", JSON.stringify(r.plain));
}

// The server's "nothing for this track" is flagged, not reported as a failed map.
{
    const r = S.toLines({ error: "MISSING_LYRICS" });
    check("missing lyrics is none", r.kind === "none");
    check("missing lyrics is flagged", r.missing === true);
    check("missing lyrics carries the token", r.reason === "MISSING_LYRICS", r.reason);
    check("a normal empty map is not flagged missing", !S.toLines({}).missing);
}

// Empty syllable text must be dropped, not rendered as a zero-width unit that the sweep
// still spends time crossing.
const blanks = S.toLines({
    Content: [{ Lead: { StartTime: 0, EndTime: 1, Syllables: [
        { Text: "",   StartTime: 0,   EndTime: 0.2 },
        { Text: "ok", StartTime: 0.2, EndTime: 1.0 }
    ] } }]
});
check("empty syllables are dropped", blanks.lines[0].words.length === 1);
check("surviving syllable is kept", blanks.lines[0].words[0].text === "ok");

// A line whose syllables are ALL empty has nothing to show and must not become a blank row.
check("all-empty line is dropped",
      S.toLines({ Content: [{ Lead: { StartTime: 0, EndTime: 1, Syllables: [
          { Text: "", StartTime: 0, EndTime: 1 }
      ] } }] }).kind === "none");

// Non-numeric times must not propagate NaN into the binary search.
const bad = S.toLines({
    Content: [{ Lead: { StartTime: "x", EndTime: null, Syllables: [
        { Text: "a", StartTime: undefined, EndTime: "y" }
    ] } }]
});
check("bad times become 0, not NaN", Number.isFinite(bad.lines[0].t));
check("bad syllable times become 0, not NaN",
      Number.isFinite(bad.lines[0].words[0].t) && Number.isFinite(bad.lines[0].words[0].d));
check("negative span clamps to 0 duration", bad.lines[0].dur === 0);

// Background vocals are deliberately ignored — see the header. What matters is that their
// presence does not corrupt the lead line.
const withBg = S.toLines({
    Content: [{
        Lead: { StartTime: 0, EndTime: 2, Syllables: [{ Text: "lead", StartTime: 0, EndTime: 2 }] },
        Background: [{ StartTime: 0, EndTime: 2,
                       Syllables: [{ Text: "back", StartTime: 0, EndTime: 2 }] }]
    }]
});
check("background vocals do not enter the lead line",
      withBg.lines[0].words.length === 1 && withBg.lines[0].text === "lead");

// ── Provider ──────────────────────────────────────────────────────────────────
// Not everything the API serves is licensed — a lot is community-uploaded, which is why
// its coverage beats the commercial sources. The card credits it, so the flag has to
// survive the mapping.
console.log("provider");
function withSource(s) {
    return S.toLines({
        source: s,
        Content: [{ Lead: { StartTime: 0, EndTime: 1,
                            Syllables: [{ Text: "x", StartTime: 0, EndTime: 1 }] } }]
    });
}
check("spl names Spicy Lyrics", withSource("spl").provider === "Spicy Lyrics");
check("spl is flagged community", withSource("spl").community === true);
check("spt names Spotify", withSource("spt").provider === "Spotify");
check("spt is not community", withSource("spt").community === false);
check("aml names Apple Music", withSource("aml").provider === "Apple Music");
check("ldb names Local DB", withSource("ldb").provider === "Local DB");
check("unknown code is named, not blank", withSource("zz").provider === "Unknown");
check("unknown code is not community", withSource("zz").community === false);
check("absent source leaves provider blank", withSource(undefined).provider === "");
check("absent source is not community", withSource(undefined).community === false);
check("source survives on plain payloads",
      S.toLines({ source: "spl", Lyrics: "placeholder" }).community === true);
check("degenerate payload still has the fields",
      S.toLines(null).provider === "" && S.toLines(null).community === false);

// ── Tuple unwrapping ──────────────────────────────────────────────────────────
// Measured against the live endpoint: result.data arrives as a [payload, status] tuple,
// matching their own fetchLyrics() return type. Reaching for .Content on the array gives
// undefined and everything maps to nothing, silently.
console.log("unwrapping");
const inner = {
    Type: "Syllable", source: "spl",
    Content: [{ Lead: { StartTime: 0, EndTime: 1,
                        Syllables: [{ Text: "x", StartTime: 0, EndTime: 1 }] } }]
};

check("unwraps a [payload, status] tuple", S.toLines([inner, 200]).kind === "syllable");
check("tuple keeps the provider", S.toLines([inner, 200]).community === true);
check("finds the payload in either slot", S.toLines([200, inner]).kind === "syllable");
check("still accepts a bare object", S.toLines(inner).kind === "syllable");
check("array of junk is none", S.toLines([1, 2, 3]).kind === "none");
check("empty array is none", S.toLines([]).kind === "none");
check("array of nulls is none", S.toLines([null, null]).kind === "none");
check("nested arrays do not recurse into nonsense",
      S.toLines([[inner], 200]).kind === "none");

// ── The packed wire format, end to end ────────────────────────────────────────
// This is what the API actually returns: a table of distinct primitives plus a flat
// opcode stream. Built by hand so the test exercises the real decode path rather than a
// convenient stand-in — objpack.js has its own unit tests, but nothing else proves the
// two halves meet.
//
// Encodes: { Type: "Syllable", source: "spl",
//            Content: [ { Lead: { StartTime: 0, EndTime: 1,
//                                 Syllables: [ { Text: "x", StartTime: 0, EndTime: 1 } ] } } ] }
console.log("packed payload");
const packedValues = [
    "Type",       // 0
    "Syllable",   // 1
    "source",     // 2
    "spl",        // 3
    "Content",    // 4
    "Lead",       // 5
    "StartTime",  // 6
    "EndTime",    // 7
    "Syllables",  // 8
    "Text",       // 9
    "x",          // 10
    0,            // 11
    1             // 12
];
const packedStream = [
    -1, 3, 0, 2, 4,          // { Type, source, Content }
    1,                       //   Type    = "Syllable"
    3,                       //   source  = "spl"
    -5,                      //   Content = [ … ] (single element)
    -1, 1, 5,                //     { Lead }
    -1, 3, 6, 7, 8,          //       { StartTime, EndTime, Syllables }
    11,                      //         StartTime = 0
    12,                      //         EndTime   = 1
    -5,                      //         Syllables = [ … ]
    -1, 3, 9, 6, 7,          //           { Text, StartTime, EndTime }
    10, 11, 12               //             "x", 0, 1
];

const packed = S.toLines([packedValues, packedStream]);
check("packed payload decodes and maps", packed.kind === "syllable");
check("packed payload keeps the line", packed.lines.length === 1);
check("packed payload keeps the syllable", packed.lines[0].words.length === 1);
check("packed payload keeps the timing", near(packed.lines[0].words[0].d, 1));
check("packed payload keeps the provider", packed.provider === "Spicy Lyrics");
check("packed payload flags community", packed.community === true);

// A packed pair that decodes to nonsense must fall through, not crash.
check("undecodable packed pair is none", S.toLines([["a"], [-7]]).kind === "none");

// ── Where the spaces come from ────────────────────────────────────────────────
// IsPartOfWord is optional, and treating "absent" as "ends a word" split real words into
// pieces with gaps between them. When the payload's own text carries spacing, that wins.
console.log("spacing source");

function syl(list) {
    return S.toLines({ Content: [{ Lead: { StartTime: 0, EndTime: 1, Syllables: list } }] })
            .lines[0];
}

// Text already carries the spacing: nothing may be added, or words come apart.
const spaced = syl([
    { Text: "aa",  StartTime: 0,   EndTime: 0.2 },
    { Text: "bb ", StartTime: 0.2, EndTime: 0.4 },
    { Text: "cc",  StartTime: 0.4, EndTime: 1.0 }
]);
check("text spacing is preserved verbatim", spaced.text === "aabb cc");
check("no space invented mid-word", spaced.words[0].text === "aa");

// No spacing in the text, but the flag IS in use on this line: an absent flag then really
// does mean "ends a word", and a space belongs after it.
const flagged = syl([
    { Text: "aa", StartTime: 0,   EndTime: 0.2, IsPartOfWord: true },
    { Text: "bb", StartTime: 0.2, EndTime: 0.4 },
    { Text: "cc", StartTime: 0.4, EndTime: 1.0 }
]);
check("flag joins where text is silent", flagged.words[0].text === "aa");
check("flag breaks where text is silent", flagged.words[1].text === "bb ");

// ── The flag never appears at all ─────────────────────────────────────────────
// Nothing is being encoded, so nothing may be invented. Reading each absence as a word
// boundary put a gap between every syllable and split single words into their pieces —
// which is what scripts that write without spaces always look like.
const unflagged = syl([
    { Text: "aa", StartTime: 0,   EndTime: 0.3 },
    { Text: "bb", StartTime: 0.3, EndTime: 0.6 },
    { Text: "cc", StartTime: 0.6, EndTime: 1.0 }
]);
check("no flag anywhere adds no spaces", unflagged.text === "aabbcc");
check("no flag anywhere leaves units untouched",
      unflagged.words.every(w => !/\s$/.test(w.text)));

// An explicit false counts as the flag being in use.
const explicitFalse = syl([
    { Text: "aa", StartTime: 0,   EndTime: 0.5, IsPartOfWord: false },
    { Text: "bb", StartTime: 0.5, EndTime: 1.0 }
]);
check("an explicit false counts as the flag being used",
      explicitFalse.text === "aa bb");

// The reported bug: several syllables of one word, none carrying the flag, no spacing in
// the text. They must NOT each become their own word.
const oneWord = syl([
    { Text: "aa", StartTime: 0,   EndTime: 0.2, IsPartOfWord: true },
    { Text: "bb", StartTime: 0.2, EndTime: 0.4, IsPartOfWord: true },
    { Text: "cc", StartTime: 0.4, EndTime: 1.0, IsPartOfWord: true }
]);
check("a fully-flagged word stays whole", oneWord.text === "aabbcc");

// A trailing space already present must never be doubled.
const nodouble = syl([
    { Text: "aa ", StartTime: 0,   EndTime: 0.5 },
    { Text: "bb",  StartTime: 0.5, EndTime: 1.0 }
]);
check("existing trailing space is not doubled", nodouble.text === "aa bb");

// ── The OTHER convention: only word ENDS are written out ──────────────────────
// A payload that marks word-final syllables `IsPartOfWord: false` and simply omits the
// flag mid-word is the mirror image of the one above, and reading it the first way puts a
// space after every syllable. On screen: "for ev er", "to ge ther" — while every
// single-syllable word around them came out right and hid what was happening.
//
// No `true` anywhere plus a MIX of explicit `false` and absent is the signature: there is
// no reason to write `false` on some and leave it off others unless absence means the
// opposite thing.
const endsOnly = syl([
    { Text: "for", StartTime: 0,   EndTime: 0.2 },
    { Text: "ev",  StartTime: 0.2, EndTime: 0.4 },
    { Text: "er",  StartTime: 0.4, EndTime: 0.6, IsPartOfWord: false },
    { Text: "now", StartTime: 0.6, EndTime: 1.0, IsPartOfWord: false }
]);
check("ends-only convention keeps a word whole", endsOnly.text === "forever now");
check("ends-only convention spaces only at word ends",
      endsOnly.words.map(w => w.text).join("|") === "for|ev|er |now");

// The same line under convention A — a `true` present anywhere — must be unaffected.
const contMarked = syl([
    { Text: "for", StartTime: 0,   EndTime: 0.2, IsPartOfWord: true },
    { Text: "ev",  StartTime: 0.2, EndTime: 0.4, IsPartOfWord: true },
    { Text: "er",  StartTime: 0.4, EndTime: 0.6 },
    { Text: "now", StartTime: 0.6, EndTime: 1.0 }
]);
check("continuation convention still keeps a word whole", contMarked.text === "forever now");

// All-false with nothing absent is unambiguous: every syllable really does end a word,
// and it must read the same as it always has.
const allFalse = syl([
    { Text: "aa", StartTime: 0,   EndTime: 0.5, IsPartOfWord: false },
    { Text: "bb", StartTime: 0.5, EndTime: 1.0, IsPartOfWord: false }
]);
check("all-false is unchanged", allFalse.text === "aa bb");

// ── The line's own text outranks the flag ─────────────────────────────────────
// The flag is filled in by whoever made the transcription, and they do it inconsistently
// WITHIN one payload: a real 164-line track had 153 lines marking their joins and 20 lines
// with every syllable set false — so those 20 split every multi-syllable word while the
// single-syllable words around them looked perfect and hid it. That is "it only happens on
// some songs", and no reading of the flag can repair a line where the flag is wrong.
//
// Where the payload carries the line as plain text, that is not a heuristic — it says
// where the spaces are.
function sylText(list, text) {
    return S.toLines({ Content: [{ Text: text,
                                   Lead: { StartTime: 0, EndTime: 1, Syllables: list } }] })
            .lines[0];
}

// Every syllable explicitly false — the shape that breaks — but the line text is present.
const rescued = sylText([
    { Text: "for", StartTime: 0,   EndTime: 0.2, IsPartOfWord: false },
    { Text: "ev",  StartTime: 0.2, EndTime: 0.4, IsPartOfWord: false },
    { Text: "er",  StartTime: 0.4, EndTime: 0.6, IsPartOfWord: false },
    { Text: "now", StartTime: 0.6, EndTime: 1.0, IsPartOfWord: false }
], "forever now");
check("line text overrides a wrong flag", rescued.text === "forever now");
check("line text spaces only at real word ends",
      rescued.words.map(w => w.text).join("|") === "for|ev|er |now");

// It must also override the flag in the other direction: a flag that JOINS where the line
// text separates.
const splitByText = sylText([
    { Text: "one", StartTime: 0,   EndTime: 0.5, IsPartOfWord: true },
    { Text: "two", StartTime: 0.5, EndTime: 1.0, IsPartOfWord: true }
], "one two");
check("line text separates where the flag joined", splitByText.text === "one two");

// Strict reconciliation: text that is not the same characters must be ignored entirely
// rather than aligned approximately. Being off by a word would look deliberate.
const mismatched = sylText([
    { Text: "aa", StartTime: 0,   EndTime: 0.2, IsPartOfWord: true },
    { Text: "bb", StartTime: 0.2, EndTime: 1.0 }
], "completely different words");
check("mismatched line text is ignored", mismatched.text === "aabb");

// Whitespace differences alone must NOT block reconciliation — that is the whole point.
const spacedText = sylText([
    { Text: "to", StartTime: 0,   EndTime: 0.3, IsPartOfWord: false },
    { Text: "ge", StartTime: 0.3, EndTime: 0.6, IsPartOfWord: false },
    { Text: "ther", StartTime: 0.6, EndTime: 1.0, IsPartOfWord: false }
], "together");
check("a single word stays whole", spacedText.text === "together");

// ── Duet alignment and background vocals ──────────────────────────────────────
// Two fields that were dropped on the floor before. `OppositeAligned` marks the second
// voice in a duet; `Background` is the quieter echoes sung under the lead.
console.log("duet + background");

function lineWith(extra) {
    return S.toLines({
        Content: [Object.assign({
            Lead: { StartTime: 0, EndTime: 2,
                    Syllables: [{ Text: "lead", StartTime: 0, EndTime: 2 }] }
        }, extra)]
    }).lines[0];
}

check("default alignment is left", lineWith({}).aligned === "left");
check("OppositeAligned becomes right", lineWith({ OppositeAligned: true }).aligned === "right");
check("explicit false stays left", lineWith({ OppositeAligned: false }).aligned === "left");
check("non-boolean does not flip it", lineWith({ OppositeAligned: "yes" }).aligned === "left");

check("no Background is null", lineWith({}).bg === null);
check("empty Background list is null", lineWith({ Background: [] }).bg === null);
check("Background of empty segments is null",
      lineWith({ Background: [{ StartTime: 0, EndTime: 1, Syllables: [] }] }).bg === null);

const withBgLine = lineWith({
    Background: [
        { StartTime: 0, EndTime: 1, Syllables: [{ Text: "oh", StartTime: 0, EndTime: 1 }] },
        { StartTime: 1, EndTime: 2, Syllables: [{ Text: "ah", StartTime: 1, EndTime: 2 }] }
    ]
});
check("background segments flatten into one list", withBgLine.bg.length === 2);
check("background keeps its timing", near(withBgLine.bg[1].t, 1));
check("background text is joined", withBgLine.bgText === "oh ah");
check("background never enters the lead", withBgLine.text === "lead");
check("lead is untouched by background", withBgLine.words.length === 1);

// Line-timed payloads carry the fields too, so the view never has to branch on kind.
const linePlain = S.toLines({
    Content: [{ Text: "placeholder", StartTime: 0, EndTime: 1, OppositeAligned: true }]
}).lines[0];
check("line-timed entries carry alignment", linePlain.aligned === "right");
check("line-timed entries have no background", linePlain.bg === null);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
