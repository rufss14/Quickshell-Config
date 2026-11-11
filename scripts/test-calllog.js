// ── test-calllog.js ───────────────────────────────────────────────────────────
// services/calllog.js — who counts, crediting, the file's cleaning, the ranking, hide/forget.
//
//     bun scripts/test-calllog.js
//
// Safe: pure functions, no file touched.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "calllog.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const C = new Function(src + `
return { cleanName, cleanAvatar, person, people, arrive, credit, clean, ranking, hide, forget, duration, ago };`)();

let passed = 0, failed = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) passed++;
    else { failed++; console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`); }
}

const A = "111111111111111111", B = "222222222222222222", ME = "999999999999999999";
const AV = "https://cdn.discordapp.com/avatars/111111111111111111/abc.png?size=64";
const u = (id, extra = {}) => ({ id, name: "n" + id.slice(0, 2), avatar: "", isSelf: false, bot: false, ...extra });

// ── Who counts ────────────────────────────────────────────────────────────────
check("person ok", C.person(u(A, { avatar: AV })), { id: A, name: "n11", avatar: AV });
check("self refused", C.person(u(ME, { isSelf: true })), null);
check("bot refused", C.person(u(B, { bot: true })), null);
check("bad id refused", [C.person(u("12")), C.person(u("../x")), C.person(u("__proto__")), C.person(null)], [null, null, null, null]);
check("people filters", C.people([u(A), u(ME, { isSelf: true }), u(B, { bot: true })]).map(p => p.id), [A]);
check("name: controls and bidi out, trimmed", C.cleanName("  ev\u0000il‮ name ​ "), "evil name");
check("name: cut", C.cleanName("x".repeat(200)).length, 64);
check("name: not a string", [C.cleanName(null), C.cleanName(undefined), C.cleanName(12)], ["", "", "12"]);
check("avatar: discord cdn only", [C.cleanAvatar(AV), C.cleanAvatar("http://cdn.discordapp.com/a.png"),
      C.cleanAvatar("https://evil.example/a.png"), C.cleanAvatar("https://cdn.discordapp.com/a.png\"onerror="),
      C.cleanAvatar("file:///etc/passwd")], [AV, "", "", "", ""]);

// ── Crediting ─────────────────────────────────────────────────────────────────
let b = C.arrive({}, u(A, { avatar: AV }), 1000);
check("arrive makes a record", b[A], { name: "n11", avatar: AV, seconds: 0, calls: 1, last: 1000, hidden: false });
b = C.arrive(b, u(A), 2000);
check("arrive again: another call, picture kept", [b[A].calls, b[A].avatar, b[A].last], [2, AV, 2000]);
check("arrive ignores self/bots", [C.arrive({}, u(ME, { isSelf: true }), 1), C.arrive({}, u(B, { bot: true }), 1)], [{}, {}]);
b = C.credit(b, [u(A), u(B)], 10000, 40000, 100000);
check("credit both", [b[A].seconds, b[B].seconds, b[A].last], [30, 30, 40000]);
check("credit makes a record for a first-seen person", [b[B].calls, b[B].name], [0, "n22"]);
check("credit clips to the last maxSpan", C.credit({}, [u(A)], 0, 1000000, 60000)[A].seconds, 60);
check("credit: nothing in the call", C.credit(b, [], 1, 5000), b);
check("credit: no time", C.credit(b, [u(A)], 5, 5), b);
check("credit: new object", C.credit(b, [u(A)], 1, 2000) !== b, true);
check("a rename wins, an empty one doesn't erase", [C.credit(b, [u(A, { name: "New" })], 1, 2000)[A].name, C.credit(b, [u(A, { name: "" })], 1, 2000)[A].name], ["New", "n11"]);
const before = JSON.stringify(b);
C.credit(b, [u(A)], 1, 99999); C.hide(b, A, true); C.forget(b, A);
check("inputs never mutated", JSON.stringify(b), before);

// ── The file ──────────────────────────────────────────────────────────────────
const raw = { version: 1, people: {
    [A]: { name: "Ann", avatar: AV, seconds: 120.6, calls: 3, last: 5000, hidden: true },
    [B]: { name: 5, avatar: "javascript:1", seconds: -4, calls: "x", last: null },
    "bad id": { seconds: 999 }, "__proto__": { seconds: 5 }, "333333333333": "no", "444444444444": null } };
check("clean", C.clean(raw), {
    [A]: { name: "Ann", avatar: AV, seconds: 121, calls: 3, last: 5000, hidden: true },
    [B]: { name: "5", avatar: "", seconds: 0, calls: 0, last: 0, hidden: false } });
check("clean: junk", [C.clean(null), C.clean([]), C.clean({ people: [] }), C.clean({ people: "x" }), C.clean({})], [{}, {}, {}, {}, {}]);
const many = { people: {} };
for (let i = 0; i < 2105; i++) many.people[String(100000 + i)] = { seconds: i };
const cm = C.clean(many);
check("clean keeps the biggest 2000", [Object.keys(cm).length, cm["102104"] !== undefined, cm["100000"] === undefined], [2000, true, true]);

// ── The board ─────────────────────────────────────────────────────────────────
const book = { "100001": { name: "a", seconds: 50, calls: 1, last: 10, hidden: false },
               "100002": { name: "b", seconds: 90, calls: 2, last: 5, hidden: false },
               "100003": { name: "c", seconds: 90, calls: 1, last: 9, hidden: false },
               "100004": { name: "d", seconds: 500, calls: 9, last: 9, hidden: true },
               "100005": { name: "e", seconds: 0, calls: 0, last: 0, hidden: false } };
check("ranking: time, then recent", C.ranking(book).map(r => r.id), ["100003", "100002", "100001"]);
check("ranking: hidden when asked", C.ranking(book, true).map(r => r.id), ["100004", "100003", "100002", "100001"]);
check("ranking: empty", C.ranking({}), []);
check("hide / unhide", [C.hide(book, "100001", true)["100001"].hidden, C.hide(C.hide(book, "100001", true), "100001", false)["100001"].hidden], [true, false]);
check("hide: unknown id", C.hide(book, "nope", true), book);
check("forget", [Object.keys(C.forget(book, "100001")).length, C.forget(book, "nope") === book], [4, true]);

// ── Words ─────────────────────────────────────────────────────────────────────
check("duration", [C.duration(0), C.duration(30), C.duration(45 * 60), C.duration(3 * 3600 + 12 * 60), C.duration(7200)], ["", "under a minute", "45 m", "3 h 12 m", "2 h"]);
const now = new Date(2026, 10, 8, 15).getTime();
const d = (n) => new Date(2026, 10, 8 - n, 3).getTime();
check("ago", [C.ago(0, now), C.ago(d(0), now), C.ago(d(1), now), C.ago(d(5), now), C.ago(d(20), now), C.ago(d(100), now)],
      ["", "Today", "Yesterday", "5 days ago", "2 weeks ago", "3 months ago"]);

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
