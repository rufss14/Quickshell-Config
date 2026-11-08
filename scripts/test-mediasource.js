// ── test-mediasource.js ───────────────────────────────────────────────────────
// services/mediasource.js: which window shows a playing video.
//
//     bun scripts/test-mediasource.js          (or: node scripts/test-mediasource.js)
//
// Pure functions; touches nothing. Loaded by stripping the `.pragma library` line.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "mediasource.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const { videoWindow, lyricsTrusted, idOf } = new Function(src + "; return { videoWindow, lyricsTrusted, idOf }")();

let failed = 0;
const eq = (name, got, want) => {
    if (got === want) return;
    failed++; console.log(`FAIL ${name}: got ${got}, want ${want}`);
};
const win = (id, title, appId = "zen", wayland = true) => ({ id, title, wayland: wayland ? { appId } : null });

const TITLE = "FNAF Lore Explained! (ft. Game Theory)";
const tab = win("tab", `(825) ${TITLE} - YouTube — Zen Browser`);
const other = win("other", "Settings-Refactor", "kitty");
const pip = win("pip", "Picture-in-Picture");
const id = w => w ? w.id : null;

eq("tab by title",              id(videoWindow([other, tab], TITLE, "zen")), "tab");
eq("case-insensitive",          id(videoWindow([tab], TITLE.toUpperCase(), "zen")), "tab");
eq("background tab → none",     id(videoWindow([other, win("t2", "Some other page — Zen Browser")], TITLE, "zen")), null);
eq("no title → none",           id(videoWindow([tab], "", "zen")), null);
eq("pip beats the tab window",  id(videoWindow([tab, other, pip], TITLE, "zen")), "pip");
eq("pip of another browser",    id(videoWindow([tab, win("p2", "Picture-in-Picture", "firefox")], TITLE, "zen")), "tab");
eq("pip alone, entry matches",  id(videoWindow([pip, other], TITLE, "zen")), "pip");
eq("pip alone, wrong browser",  id(videoWindow([pip], TITLE, "firefox")), null);
eq("no wayland handle skipped", id(videoWindow([win("x", TITLE, "zen", false)], TITLE, "zen")), null);
eq("empty list",                id(videoWindow([], TITLE, "zen")), null);
eq("null list",                 id(videoWindow(null, TITLE, "zen")), null);

const yt = { metadata: { "xesam:url": "https://www.youtube.com/watch?v=x" }, desktopEntry: "zen" };
eq("youtube has no lyrics",     lyricsTrusted(yt), false);
eq("youtube id",                idOf(yt), "youtube");

if (failed) { console.log(`${failed} failed`); process.exit(1); }
console.log("mediasource: all passed");
