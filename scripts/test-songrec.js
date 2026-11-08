// ── test-songrec.js ───────────────────────────────────────────────────────────
// Tests for services/songrec.js, the reading of `songrec listen --json` output.
//
//     bun scripts/test-songrec.js      (or: node scripts/test-songrec.js)
//
// Safe to run: pure functions, no I/O. The sample shapes are Shazam's response as
// the SongRec integration in ii reads it (`track.title/subtitle/url`); songrec
// itself is not installed to confirm the layout, which is why the reader accepts
// both compact and pretty-printed output.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "songrec.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const { objects, pick, safeUrl, searchUrl } =
    new Function(src + "\nreturn { objects, pick, safeUrl, searchUrl };")();

let pass = 0, fail = 0;
const failures = [];
function check(name, ok, detail) {
    if (ok) { pass++; return }
    fail++;
    failures.push(`  ${name}${detail ? "\n      " + detail : ""}`);
}
const eq = (name, got, want) =>
    check(name, JSON.stringify(got) === JSON.stringify(want), `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);

const hit = { matches: [{ id: "1" }], track: { title: "Ado", subtitle: "Usseewa", url: "https://www.shazam.com/track/1",
                                                 images: { coverart: "https://is1.example.com/a.jpg" } } };
const miss = { matches: [] };

// ── layout: compact, pretty, noisy ───────────────────────────────────────────
eq("compact hit", pick(JSON.stringify(hit)).title, "Ado");
eq("pretty-printed hit", pick(JSON.stringify(hit, null, 2)).artist, "Usseewa");
eq("log chatter around it", pick("Listening…\n" + JSON.stringify(hit) + "\nbye").title, "Ado");
eq("a miss is nothing", pick(JSON.stringify(miss)), null);
eq("miss then hit", pick(JSON.stringify(miss) + "\n" + JSON.stringify(hit, null, 2)).title, "Ado");
eq("empty text", pick(""), null);
eq("null text", pick(null), null);

// ── partial output: not there yet ────────────────────────────────────────────
{
    const full = JSON.stringify(hit, null, 2);
    eq("half an object is not a hit", pick(full.slice(0, full.length - 5)), null);
    eq("the rest arriving completes it", pick(full).title, "Ado");
}

// ── strings with braces, escapes ─────────────────────────────────────────────
{
    const tricky = { track: { title: "Brace } and { quote \" song", subtitle: "A\\B" } };
    eq("braces and quotes inside strings", pick(JSON.stringify(tricky)).title, "Brace } and { quote \" song");
    eq("a backslash survives", pick(JSON.stringify(tricky)).artist, "A\\B");
    eq("objects() counts top-level only", objects(JSON.stringify(hit)).length, 1);
}
eq("braces in chatter are skipped", objects("{not json} " + JSON.stringify(miss)).length, 1);

// ── a track must have a title ────────────────────────────────────────────────
eq("track without title", pick(JSON.stringify({ track: { subtitle: "x" } })), null);
eq("track not an object", pick(JSON.stringify({ track: "x" })), null);

// ── urls ─────────────────────────────────────────────────────────────────────
eq("https passes", safeUrl("https://www.shazam.com/x"), "https://www.shazam.com/x");
eq("http is dropped", safeUrl("http://www.shazam.com/x"), "");
eq("javascript: is dropped", safeUrl("javascript:alert(1)"), "");
eq("file: is dropped", safeUrl("file:///etc/passwd"), "");
eq("spaces are dropped", safeUrl("https://a.com/x y"), "");
eq("a hostile url becomes empty in the track", pick(JSON.stringify({ track: { title: "t", url: "javascript:x" } })).url, "");
eq("search link is encoded", searchUrl({ title: "A & B", artist: "C" }),
   "https://www.youtube.com/results?search_query=A%20%26%20B%20C");
eq("search link without an artist", searchUrl({ title: "T", artist: "" }),
   "https://www.youtube.com/results?search_query=T");

if (fail) {
    console.log(`FAIL  ${fail} failed, ${pass} passed`);
    console.log(failures.join("\n"));
    process.exit(1);
}
console.log(`ok  ${pass} checks`);
