// ── test-changelog.js ─────────────────────────────────────────────────────────
// Checks assets/changelog.json, the patch notes the overview's "What's changed" page draws
// (services/Changelog.qml → FeedChanges). Hand-written data that the shell reads at runtime, so a
// typo is a blank page or a help-circle icon, never an error anyone sees.
//
//     bun scripts/test-changelog.js          (or: node scripts/test-changelog.js)
//
// What it checks: the shape, newest version first, the newest one being Config.version, and every
// icon name being one services/icons.js knows (a new one needs material-symbols-map.py --emit).
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const doc = JSON.parse(readFileSync(join(root, "assets", "changelog.json"), "utf8"));
const icons = readFileSync(join(root, "services", "icons.js"), "utf8");
const version = /readonly property string version:\s*"([^"]+)"/.exec(readFileSync(join(root, "config", "Config.qml"), "utf8"))[1];

let pass = 0, fail = 0;
function check(name, cond) { if (cond) pass++; else { fail++; console.log("FAIL", name); } }
const known = n => icons.includes('"' + n + '"');
const num = v => v.split(".").map(Number);
const newer = (a, b) => { const x = num(a), y = num(b); for (let i = 0; i < Math.max(x.length, y.length); i++) { if ((x[i] || 0) !== (y[i] || 0)) return (x[i] || 0) > (y[i] || 0); } return false; };

check("versions is a non-empty list", Array.isArray(doc.versions) && doc.versions.length > 0);
check("the newest is Config.version (" + version + ")", doc.versions[0].version === version);
for (let i = 1; i < doc.versions.length; i++)
    check("newest first: " + doc.versions[i - 1].version + " > " + doc.versions[i].version, newer(doc.versions[i - 1].version, doc.versions[i].version));
for (const v of doc.versions) {
    const at = "v" + v.version;
    check(at + " has a name and summary", typeof v.name === "string" && v.name && typeof v.summary === "string" && v.summary);
    check(at + " date is YYYY-MM or YYYY-MM-DD", /^\d{4}-\d{2}(-\d{2})?$/.test(v.date));
    check(at + " highlights is a list", Array.isArray(v.highlights));
    for (const h of v.highlights) {
        check(at + " highlight '" + h.title + "' has text", !!h.title && !!h.text);
        check(at + " highlight icon '" + h.symbol + "' exists", known(h.symbol));
    }
    check(at + " has sections", Array.isArray(v.sections) && v.sections.length > 0);
    for (const s of v.sections) {
        check(at + " section '" + s.title + "' icon '" + s.symbol + "' exists", known(s.symbol));
        check(at + " section '" + s.title + "' has items", Array.isArray(s.items) && s.items.length > 0);
        for (const it of s.items) check(at + " item is one line of text: " + String(it).slice(0, 40), typeof it === "string" && it.length > 0 && it.length <= 140 && !it.includes("\n"));
    }
}
console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
