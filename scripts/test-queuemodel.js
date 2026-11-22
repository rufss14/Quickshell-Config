// ── test-queuemodel.js ────────────────────────────────────────────────────────
// Tests for services/queuemodel.js: the Spotify queue the media page draws, and the moves it asks for.
//
//     bun scripts/test-queuemodel.js      (or: node scripts/test-queuemodel.js)
//
// Pure functions, no I/O.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "queuemodel.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const Q = new Function(src + "\nreturn { MAX_ROWS, imageUrl, parseQueue, moveTo, runs, creditFor };")();

let pass = 0, fail = 0;
function check(name, ok, detail) {
    if (ok) pass++; else { fail++; console.log("FAIL", name, detail === undefined ? "" : JSON.stringify(detail)); }
}
const J = JSON.stringify;
const mk = (n, extra) => Object.assign({ uid: "u" + n, uri: "spotify:track:" + String(n).padStart(22, "0"), title: "T" + n, artist: "A", album: "B", provider: "context" }, extra || {});
const ids = l => l.map(r => r.uid).join(",");

// ── images ──
check("an image uri becomes the cdn address", Q.imageUrl("spotify:image:ab67616d00001e02aabbccddeeff00112233") === "https://i.scdn.co/image/ab67616d00001e02aabbccddeeff00112233");
check("a cdn address is kept", Q.imageUrl("https://i.scdn.co/image/abc123") === "https://i.scdn.co/image/abc123");
check("anything else is dropped", Q.imageUrl("http://evil.example/x.png") === "" && Q.imageUrl("file:///etc/passwd") === "" && Q.imageUrl("") === "" && Q.imageUrl(null) === "");

// ── parsing ──
const p = Q.parseQueue({ rev: 7, current: mk(0), next: [mk(1, { provider: "queue", by: "zed" }), mk(2), { nope: 1 }, null, mk(3, { provider: "weird" })], more: 12, context: "Some Album" });
check("rev is text", p.rev === "7");
check("rows without a uri are dropped", ids(p.next) === "u1,u2,u3", ids(p.next));
check("an unknown provider is the context", p.next[2].provider === "context");
check("the current track parses", p.current && p.current.uid === "u0");
check("more and context carry", p.more === 12 && p.context === "Some Album");
check("garbage in is an empty queue", J(Q.parseQueue(null).next) === "[]" && Q.parseQueue("x").current === null && Q.parseQueue({ next: "no" }).next.length === 0);
const big = Q.parseQueue({ next: Array.from({ length: 500 }, (_, i) => mk(i + 1)) });
check("rows are capped", big.next.length === Q.MAX_ROWS);
check("a long title is cut", Q.parseQueue({ next: [mk(1, { title: "x".repeat(5000) })] }).next[0].title.length === 200);
check("a duration is bounded", Q.parseQueue({ next: [mk(1, { durationMs: -5 })] }).next[0].durationMs === 0 && Q.parseQueue({ next: [mk(1, { durationMs: 1e12 })] }).next[0].durationMs === 86400000);

// ── the Jam ──
const jm = Q.parseQueue({ next: [], jam: { members: [{ id: "1", username: "me", name: "Me", you: true, host: true }, { id: "2", username: "zed", name: "Zed" }, { name: "" }], youHost: true, queueOnly: true } }).jam;
check("a jam keeps its members", jm.members.length === 2 && jm.youHost === true && jm.queueOnly === true);
check("liked comes through as a flag", Q.parseQueue({ liked: true }).liked === true && Q.parseQueue({ liked: "yes" }).liked === false);
check("the DJ flag comes through", Q.parseQueue({ dj: true }).dj === true && Q.parseQueue({}).dj === false);
check("a listener's picture comes through, only as a cdn address",
    Q.parseQueue({ jam: { members: [{ name: "a", image: "https://i.scdn.co/image/abc123" }, { name: "b", image: "http://x/y" }] } }).jam.members[0].image === "https://i.scdn.co/image/abc123"
    && Q.parseQueue({ jam: { members: [{ name: "b", image: "http://x/y" }] } }).jam.members[0].image === "");
check("the volume switch is offered only when Spotify offers it", Q.parseQueue({ jam: { volumeAvailable: true } }).jam.volumeAvailable === true && Q.parseQueue({ jam: {} }).jam.volumeAvailable === false);
check("no jam is null", Q.parseQueue({ next: [] }).jam === null && Q.parseQueue({ next: [], jam: "x" }).jam === null);
check("credit: another member by username", Q.creditFor({ by: "zed" }, jm) === "Zed");
check("credit: you", Q.creditFor({ by: "me" }, jm) === "you");
check("credit: by id works too", Q.creditFor({ by: "2" }, jm) === "Zed");
check("credit: a stranger or no jam is nobody", Q.creditFor({ by: "who" }, jm) === "" && Q.creditFor({ by: "zed" }, null) === "" && Q.creditFor({ by: "" }, jm) === "");

// ── moves ──
const L = [mk(1), mk(2), mk(3), mk(4)];
let m = Q.moveTo(L, "u3", 0);
check("to the top: order", ids(m.list) === "u3,u1,u2,u4", ids(m.list));
check("to the top: before the old first", m.where === "before" && m.anchor === "u1");
m = Q.moveTo(L, "u1", 2);
check("down two: order", ids(m.list) === "u2,u3,u1,u4", ids(m.list));
check("down two: before the row it lands on", m.where === "before" && m.anchor === "u4");
m = Q.moveTo(L, "u1", 3);
check("to the end: order", ids(m.list) === "u2,u3,u4,u1", ids(m.list));
check("to the end: after the old last", m.where === "after" && m.anchor === "u4");
check("same place is nothing", Q.moveTo(L, "u2", 1) === null);
check("past the end clamps to last", ids(Q.moveTo(L, "u1", 99).list) === "u2,u3,u4,u1");
check("before the start clamps to first", ids(Q.moveTo(L, "u4", -5).list) === "u4,u1,u2,u3");
check("an unknown row is nothing", Q.moveTo(L, "nope", 0) === null);
check("a row with no uid can't be moved", Q.moveTo([mk(1, { uid: "" }), mk(2)], "", 1) === null);
check("one row has nowhere to go", Q.moveTo([mk(1)], "u1", 0) === null);
check("the input is not changed", ids(L) === "u1,u2,u3,u4");

// ── groups ──
const g = Q.runs([mk(1, { provider: "queue" }), mk(2, { provider: "queue" }), mk(3), mk(4), mk(5, { provider: "autoplay" })]);
check("groups follow the providers", J(g.map(r => [r.provider, r.from, r.to])) === J([["queue", 0, 2], ["context", 2, 4], ["autoplay", 4, 5]]), g);
check("no rows, no groups", Q.runs([]).length === 0);

console.log(fail === 0 ? "ok  " + pass + " checks" : fail + " FAILED of " + (pass + fail));
process.exit(fail === 0 ? 0 : 1);
