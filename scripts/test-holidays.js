// ── test-holidays.js ──────────────────────────────────────────────────────────
// Regression tests for services/holidays.js — classifying Nager.Date's response
// into the calendar's special dates.
//
//     bun scripts/test-holidays.js          (or: node scripts/test-holidays.js)
//
// Safe to run: pure functions, no network. The sample entries are the real shapes
// the API returned for Portugal (2026), trimmed.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "holidays.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const H = new Function(src + "\nreturn { classify, next, key, kindLabel };")();

let pass = 0, fail = 0;
function eq(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { pass++; return; }
    fail++;
    console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`);
}

const PT = [
    { date: "2026-02-17", localName: "Carnaval", name: "Carnival", global: true, counties: null, types: ["Optional"] },
    { date: "2026-06-01", localName: "Dia dos Açores", name: "Azores Day", global: false, counties: ["PT-20"], types: ["Public"] },
    { date: "2026-10-05", localName: "Implantação da República", name: "Republic Day", global: true, counties: null, types: ["Public"] },
    { date: "2026-12-25", localName: "Natal", name: "Christmas Day", global: true, counties: null, types: ["Public"] },
    { date: "2026-12-25", localName: "Dia de Natal (Madeira)", name: "Christmas (Madeira)", global: false, counties: ["PT-30"], types: ["Public"] },
];

const map = H.classify(PT);
eq("observance", map["2026-2-17"], [{ name: "Carnaval", english: "Carnival", kind: "observance" }]);
eq("regional", map["2026-6-1"][0].kind, "regional");
eq("national keeps local name + english", map["2026-10-5"], [{ name: "Implantação da República", english: "Republic Day", kind: "national" }]);
eq("two on one day, national first", map["2026-12-25"].map(e => e.kind), ["national", "regional"]);
eq("keys are unpadded", Object.keys(map).sort(), ["2026-10-5", "2026-12-25", "2026-2-17", "2026-6-1"]);

eq("english omitted when identical", H.classify([{ date: "2026-01-01", localName: "New Year", name: "New Year", global: true, types: ["Public"] }])["2026-1-1"][0].english, "");
eq("falls back to english name", H.classify([{ date: "2026-01-01", name: "New Year", global: true, types: ["Public"] }])["2026-1-1"][0].name, "New Year");
eq("garbage skipped", H.classify([null, 5, { date: "26-1-1", name: "x" }, { date: "2026-01-02" }, { date: "2026-01-03", name: "   " }]), {});
eq("not an array", H.classify({ message: "not found" }), {});
eq("name capped", H.classify([{ date: "2026-01-01", name: "x".repeat(500), types: ["Public"], global: true }])["2026-1-1"][0].name.length, 120);
eq("missing types → observance", H.classify([{ date: "2026-03-01", name: "Something", global: true }])["2026-3-1"][0].kind, "observance");

const L = (y, m, d) => new Date(y, m - 1, d).getTime();
eq("next finds the day", H.next(map, L(2026, 9, 13)).day, L(2026, 10, 5));
eq("next inclusive of today", H.next(map, L(2026, 10, 5)).entries[0].name, "Implantação da República");
eq("next respects the window", H.next(map, L(2026, 9, 13), 10), null);
eq("next with no map", H.next(null, L(2026, 1, 1)), null);
eq("labels", ["national", "regional", "observance", "?"].map(H.kindLabel), ["Public holiday", "Regional holiday", "Observance", ""]);

console.log(`${pass} passed, ${fail} failed`);
if (fail) process.exit(1);
