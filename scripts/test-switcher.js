// ── test-switcher.js ──────────────────────────────────────────────────────────
// services/switcher.js — Alt+Tab's events, the recent-windows order, window search.
//
//     bun scripts/test-switcher.js          (or: node scripts/test-switcher.js)
//
// Safe: pure functions. switcher.js `.import`s launcher.js for its scorer; both files
// are loaded with their QML directives stripped, so the tests run the real code.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const read = f => readFileSync(join(here, "..", "services", f), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "")
    .replace(/^\s*\.import\s+.*$/mg, "");

const L = new Function(read("launcher.js") + "\nreturn { scoreText };")();
const S = new Function("L", read("switcher.js") + `
return { parseEvent, byHistory, arrange, filter, score, initialIndex, step, keep, norm, ago, nearest, parseQuery, hasFlag, toggleFlag, splitOps };`)(L);

let passed = 0, failed = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) passed++;
    else { failed++; console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`); }
}

// ── Events ───────────────────────────────────────────────────────────────────
check("next with order", S.parseEvent("qs-switch:next:562d73b1be60,0xABC"),
      { kind: "next", order: ["0x562d73b1be60", "0xabc"] });
check("prev", S.parseEvent("qs-switch:prev:0x1").kind, "prev");
check("up", S.parseEvent("qs-switch:up"), { kind: "up", order: [] });
check("next without order", S.parseEvent("qs-switch:next"), { kind: "next", order: [] });
check("other prefix", S.parseEvent("qs-sfx-key:dk"), null);
check("unknown kind", S.parseEvent("qs-switch:boom:0x1"), null);
check("junk addresses dropped", S.parseEvent("qs-switch:next:0x1,rm -rf,,0x1,zz").order, ["0x1"]);
check("not a string", S.parseEvent(null), null);
check("order capped", S.parseEvent("qs-switch:next:" +
      Array.from({ length: 100 }, (_, i) => (i + 1).toString(16)).join(",")).order.length, 64);

// ── Order ────────────────────────────────────────────────────────────────────
const W = (address, title, appName, appClass) => ({ address, title, appName, appClass });
const kitty = W("0xa", "~/projects", "Kitty", "kitty");
const zen = W("0xb", "GitHub — Zen Browser", "Zen Browser", "zen");
const spot = W("0xc", "Spotify Premium", "Spotify", "spotify");
const code = W("0xd", "main.qml — Visual Studio Code", "Visual Studio Code", "code");
const hist = { "0xa": 2, "0xb": 0, "0xc": 1 };
check("by history, unknown last", S.byHistory([kitty, zen, spot, code], a => hist[a]).map(w => w.address),
      ["0xb", "0xc", "0xa", "0xd"]);
check("arrange by event order, the rest after in their order", S.arrange(["0xc", "0x99", "0xa"], [code, kitty, zen, spot])
      .map(w => w.address), ["0xc", "0xa", "0xd", "0xb"]);
check("arrange normalises addresses", S.arrange(["c"], [kitty, spot]).map(w => w.address), ["0xc", "0xa"]);

// ── Search ───────────────────────────────────────────────────────────────────
const all = [zen, spot, kitty, code];
check("empty query keeps everything in order", S.filter(all, "  ").map(w => w.address), ["0xb", "0xc", "0xa", "0xd"]);
check("by app name", S.filter(all, "spot").map(w => w.address), ["0xc"]);
check("by title word", S.filter(all, "github").map(w => w.address), ["0xb"]);
check("by class", S.filter(all, "kitty").map(w => w.address), ["0xa"]);
check("initials", S.filter(all, "vsc").map(w => w.address), ["0xd"]);
check("two words across app and title", S.filter(all, "zen github").map(w => w.address), ["0xb"]);
check("two words, one missing", S.filter(all, "zen spotify").length, 0);
check("better match first", S.filter([W("0x1", "notes about code", "Notes", "notes"), code], "code")[0].address, "0xd");
check("case-insensitive", S.filter(all, "SPOTIFY").length, 1);
check("no match", S.filter(all, "qqq"), []);


// ── Operators ────────────────────────────────────────────────────────────────
const placed = (w, ws) => ({ ...w, workspaceId: ws });
const ops = [placed(zen, 1), placed(spot, 2), placed(kitty, 2), placed(code, 3)];
const facts = { "0xa": { floating: true, pinned: false, fullscreen: false, audio: false },
                "0xb": { floating: false, pinned: false, fullscreen: false, audio: false },
                "0xc": { floating: false, pinned: true, fullscreen: false, audio: true },
                "0xd": { floating: false, pinned: false, fullscreen: true, audio: false } };
const ids = (q, f) => S.filter(ops, q, f).map(w => w.address);
const fo = w => facts[w.address];
check("parse: words and operators", S.parseQuery("Zen ws:2 is:fl app:kit"),
      { text: "zen", ws: [[2]], app: ["kit"], flags: ["floating"] });
check("parse: a workspace list", S.parseQuery("ws:1,3").ws, [[1, 3]]);
check("parse: key with no value yet is dropped", S.parseQuery("kitty ws: is:"), { text: "kitty", ws: [], app: [], flags: [] });
check("parse: not an operator stays a word", S.parseQuery("is:xyz ws:abc http://x").text, "is:xyz ws:abc http://x");
check("parse: flag by prefix", S.parseQuery("is:f").flags, ["floating"]);
check("filter: ws", ids("ws:2"), ["0xc", "0xa"]);
check("filter: ws list", ids("ws:1,3"), ["0xb", "0xd"]);
check("filter: app", ids("app:spot"), ["0xc"]);
check("filter: flag", ids("is:floating", fo), ["0xa"]);
check("filter: tiled is not floating", ids("is:tiled", fo), ["0xb", "0xc", "0xd"]);
check("filter: audio", ids("is:audio", fo), ["0xc"]);
check("filter: operators AND together", ids("ws:2 is:pinned", fo), ["0xc"]);
check("filter: operators then text", ids("ws:2 spot", fo), ["0xc"]);
check("filter: text with no match inside the narrowed set", ids("ws:3 kitty"), []);
check("filter: flag with no resolver matches nothing", ids("is:floating"), []);
check("filter: no operators, same as before", S.filter(all, "spot").map(w => w.address), ["0xc"]);
check("filter: an incomplete operator keeps everything", ids("ws:").length, 4);
let asked = 0;
S.filter(ops, "spot", w => { asked++; return {}; });
check("facts are only asked for when a flag is", asked, 0);
check("hasFlag", [S.hasFlag("kitty is:floating", "floating"), S.hasFlag("kitty", "floating")], [true, false]);
check("toggleFlag adds", S.toggleFlag("kitty", "pinned"), "kitty is:pinned");
check("toggleFlag removes", S.toggleFlag("is:pinned kitty is:PINNED", "pinned"), "kitty");
check("toggleFlag on empty", S.toggleFlag("", "audio"), "is:audio");

// ── Picking ──────────────────────────────────────────────────────────────────
check("alt+tab starts on the previous window", S.initialIndex(4, "next"), 1);
check("shift+alt+tab starts on the oldest", S.initialIndex(4, "prev"), 3);
check("one window", S.initialIndex(1, "next"), 0);
check("none", S.initialIndex(0, "next"), -1);
check("step wraps forward", S.step(3, 4, 1), 0);
check("step wraps back", S.step(0, 4, -1), 3);
check("step from nothing, forward", S.step(-1, 4, 1), 1);
check("step from nothing, back", S.step(-1, 4, -1), 3);
check("step empty", S.step(0, 0, 1), -1);
check("keep the same window", S.keep("0xc", [kitty, spot], 0), 1);
check("keep: gone, nearest place", S.keep("0xz", [kitty, spot], 5), 1);
check("keep: nothing was picked", S.keep("", [kitty], -1), -1);
check("norm rejects junk", S.norm("0xZZ"), "");

// ── How long ago ─────────────────────────────────────────────────────────────
const T = 1_800_000_000_000;
check("ago: unknown", S.ago(0, T), "");
check("ago: seconds", S.ago(T - 20_000, T), "just now");
check("ago: minutes", S.ago(T - 5 * 60_000, T), "5 min ago");
check("ago: hours", S.ago(T - 3 * 3_600_000, T), "3 h ago");
check("ago: days", S.ago(T - 50 * 3_600_000, T), "2 d ago");
check("ago: clock behind", S.ago(T + 5000, T), "just now");

// ── Arrow keys on the grid ───────────────────────────────────────────────────
// Two rows of three: a b c / d e f, 100 apart; g sits a little right of b, lower.
const at = (address, x, y) => ({ address, x, y });
const grid = [at("a", 0, 0), at("b", 100, 0), at("c", 200, 0),
              at("d", 0, 100), at("e", 100, 100), at("f", 200, 100), at("g", 130, 40)];
check("right", S.nearest(grid[0], grid, 1, 0), "b");
check("down prefers straight under", S.nearest(grid[0], grid, 0, 1), "d");
check("left from c", S.nearest(grid[2], grid, -1, 0), "b");
check("up from e: b straight above beats g, nearer but off to the side", S.nearest(grid[4], grid, 0, -1), "b");
check("up from e without b: g, slightly off, beats a and c far off", S.nearest(grid[4], grid.filter(w => w.address !== "b"), 0, -1), "g");
check("nothing that way", S.nearest(grid[0], grid, -1, 0), "");
check("not itself", S.nearest(at("a", 0, 0), [at("a", 0, 0)], 1, 0), "");
check("a twin at the same centre is not ahead", S.nearest(at("a", 0, 0), [at("z", 0, 0)], 1, 0), "");

// ── Operators out of the typed text (the search's chips) ─────────────────────
check("ops: complete one", JSON.stringify(S.splitOps("ws:2 ")), JSON.stringify({ ops: ["ws:2"], rest: "" }));
check("ops: still being typed", JSON.stringify(S.splitOps("ws:2")), JSON.stringify({ ops: [], rest: "ws:2" }));
check("ops: words kept, trailing space kept", JSON.stringify(S.splitOps("foo is:floating bar ")), JSON.stringify({ ops: ["is:floating"], rest: "foo bar " }));
check("ops: two", JSON.stringify(S.splitOps("app:kitty ws:1,2 x")), JSON.stringify({ ops: ["app:kitty", "ws:1,2"], rest: "x" }));
check("ops: looks like one but is not", JSON.stringify(S.splitOps("is:xyz ")), JSON.stringify({ ops: [], rest: "is:xyz " }));
check("ops: key with no value", JSON.stringify(S.splitOps("ws: ")), JSON.stringify({ ops: [], rest: "ws: " }));
check("ops: case folded", JSON.stringify(S.splitOps("IS:Floating ")), JSON.stringify({ ops: ["is:floating"], rest: "" }));

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
