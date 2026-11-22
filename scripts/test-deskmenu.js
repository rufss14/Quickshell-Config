// ── test-deskmenu.js ──────────────────────────────────────────────────────────
// services/deskmenu.js — where the desktop menu opens, which pictures its strip shows, and the
// list edits behind its settings page and the hot corner's.
//
//     bun scripts/test-deskmenu.js          (or: node scripts/test-deskmenu.js)
//
// Safe: pure functions.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "deskmenu.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const D = new Function(src + "\nreturn { PLACES, PLACE_ORDER, TOOLS, TOOL_ORDER, PARTS, PART_ORDER, known, move, flip, place, pictures };")();

let passed = 0, failed = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) passed++;
    else { failed++; console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`); }
}

// place(): a 320 × 400 menu on a 1920 × 1080 screen, 12px kept inside.
check("room: corner at the pointer", D.place(500, 300, 320, 400, 1920, 1080, 12), { x: 500, y: 300, flipX: false, flipY: false });
check("near the right edge: opens leftward", D.place(1800, 300, 320, 400, 1920, 1080, 12), { x: 1480, y: 300, flipX: true, flipY: false });
check("near the bottom: opens upward", D.place(500, 900, 320, 400, 1920, 1080, 12), { x: 500, y: 500, flipX: false, flipY: true });
check("bottom-right corner: both", D.place(1900, 1070, 320, 400, 1920, 1080, 12), { x: 1580, y: 668, flipX: true, flipY: true });
check("flipped past the left edge: kept inside", D.place(100, 300, 320, 400, 120, 1080, 12), { x: 12, y: 300, flipX: true, flipY: false });
check("taller than the screen: kept at the margin", D.place(500, 500, 320, 2000, 1920, 1080, 12).y, 12);
check("a key (no pointer): the middle", D.place(-1, -1, 320, 400, 1920, 1080, 12), { x: 800, y: 340, flipX: false, flipY: false });
check("just fits at the right: no flip", D.place(1588, 300, 320, 400, 1920, 1080, 12).flipX, false);
check("one pixel too far: flips", D.place(1589, 300, 320, 400, 1920, 1080, 12).flipX, true);

// pictures(): the current one first, then the newest.
const list = ["/w/a.jpg", "/w/b.jpg", "/w/c.jpg", "/w/d.jpg"];
const mt = { "/w/a.jpg": 10, "/w/b.jpg": 40, "/w/c.jpg": 30, "/w/d.jpg": 20 };
check("current first, then newest", D.pictures(list, "c.jpg", mt, 3), ["/w/c.jpg", "/w/b.jpg", "/w/d.jpg"]);
check("no current (a video runs): newest", D.pictures(list, "", mt, 2), ["/w/b.jpg", "/w/c.jpg"]);
check("current that isn't in the library", D.pictures(list, "gone.jpg", mt, 2), ["/w/b.jpg", "/w/c.jpg"]);
check("more asked than there are", D.pictures(list, "a.jpg", mt, 9).length, 4);
check("none asked", D.pictures(list, "a.jpg", mt, 0), []);
check("no mtimes: library order kept", D.pictures(list, "b.jpg", null, 3), ["/w/b.jpg", "/w/a.jpg", "/w/c.jpg"]);
check("not a list", D.pictures(null, "a", mt, 3), []);

// known(): stale and doubled ids drop.
check("known drops unknown and doubles", D.known(["bar", "nope", "bar", "settings"], D.PLACES), ["bar", "settings"]);
check("known of nothing", D.known(undefined, D.PLACES), []);
check("every place is in the order", D.PLACE_ORDER.every(id => D.PLACES[id] !== undefined) && Object.keys(D.PLACES).length === D.PLACE_ORDER.length, true);

check("every tool is in the order", D.TOOL_ORDER.every(id => D.TOOLS[id] !== undefined) && Object.keys(D.TOOLS).length === D.TOOL_ORDER.length, true);
check("every place and tool names an icon and a label", [...Object.values(D.PLACES), ...Object.values(D.TOOLS)].every(m => m.symbol && m.label && m.detail), true);
check("known keeps tool order", D.known(["clip", "region", "nope"], D.TOOLS), ["clip", "region"]);

check("every hot corner part is in the order", D.PART_ORDER.every(id => D.PARTS[id] !== undefined) && Object.keys(D.PARTS).length === D.PART_ORDER.length, true);

// move() / flip()
check("move later", D.move(["a", "b", "c"], "a", 1), ["b", "a", "c"]);
check("move earlier", D.move(["a", "b", "c"], "c", -1), ["a", "c", "b"]);
check("move off the end: unchanged", D.move(["a", "b"], "b", 1), ["a", "b"]);
check("move the first earlier: unchanged", D.move(["a", "b"], "a", -1), ["a", "b"]);
check("move a stranger: unchanged", D.move(["a", "b"], "z", 1), ["a", "b"]);
check("move does not touch its input", (() => { const l = ["a", "b"]; D.move(l, "a", 1); return l; })(), ["a", "b"]);
check("flip adds at the end", D.flip(["a"], "b", 3), ["a", "b"]);
check("flip removes", D.flip(["a", "b"], "a", 3), ["b"]);
check("flip at the limit: refuses to add", D.flip(["a", "b"], "c", 2), ["a", "b"]);
check("flip at the limit still removes", D.flip(["a", "b"], "b", 2), ["a"]);

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
