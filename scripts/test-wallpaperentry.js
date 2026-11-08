// ── test-wallpaperentry.js ───────────────────────────────────────────────────
// Regression tests for services/wallpaperentry.js, the gallery entry normaliser.
//
//     bun scripts/test-wallpaperentry.js          (or: node scripts/test-wallpaperentry.js)
//
// Safe to run: describe() is a pure function — no disk, no network, no shell.
//
// The cases that matter are the degenerate ones, because that is exactly what the
// three views hit at runtime: a string entry asked about during a source switch
// while the tab flag still says "scenes", a scene whose preview file is missing,
// an image path with no extension, and null during delegate construction.
//
// wallpaperentry.js is loaded by stripping its `.pragma library` line (a QML
// directive that isn't valid JS) and evaluating the rest, so the tests run
// against the real file rather than a copy that can drift. Same approach as
// test-lyricsmotion.js / test-calc.js.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "wallpaperentry.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");

const { describe } = new Function(src + "\nreturn { describe };")();

let pass = 0, fail = 0;
function check(name, cond, detail) {
    if (cond) { pass++; }
    else { fail++; console.log(`  FAIL  ${name}${detail ? "  — " + detail : ""}`); }
}
function eq(name, got, want) {
    check(name, JSON.stringify(got) === JSON.stringify(want),
          `got ${JSON.stringify(got)} want ${JSON.stringify(want)}`);
}

// ── image path ───────────────────────────────────────────────────────────────
eq("image: kind", describe("/home/u/walls/Clouds.png").kind, "image");
eq("image: key is the path", describe("/home/u/walls/Clouds.png").key, "/home/u/walls/Clouds.png");
eq("image: name is the bare filename", describe("/home/u/walls/Clouds.png").name, "Clouds.png");
eq("image: thumb is a file url", describe("/home/u/walls/Clouds.png").thumb, "file:///home/u/walls/Clouds.png");
eq("image: type is the lowercased extension", describe("/home/u/walls/HAKUREI.JPG").type, "jpg");
eq("image: gif is detected", describe("/home/u/walls/spin.gif").isGif, true);
eq("image: png is not a gif", describe("/home/u/walls/Clouds.png").isGif, false);
eq("image: no extension -> empty type, not the whole name",
   describe("/home/u/walls/Wallpaper").type, "");

// ── scene object ─────────────────────────────────────────────────────────────
const scene = { id: "1234567890", title: "Ado Rule", type: "Scene",
                preview: "/steam/workshop/1234567890/preview.gif" };
eq("scene: kind", describe(scene).kind, "scene");
eq("scene: key is the id", describe(scene).key, "1234567890");
eq("scene: name is the title", describe(scene).name, "Ado Rule");
eq("scene: thumb is a file url", describe(scene).thumb, "file:///steam/workshop/1234567890/preview.gif");
eq("scene: type is lowercased", describe(scene).type, "scene");
eq("scene: gif preview is detected", describe(scene).isGif, true);
eq("scene: video type passes through",
   describe({ id: "9", title: "Waves", type: "video", preview: "" }).type, "video");
eq("scene: missing preview -> empty thumb, no 'file://' prefix",
   describe({ id: "9", title: "Waves", type: "scene", preview: "" }).thumb, "");

// ── action card ──────────────────────────────────────────────────────────────
const action = { action: "add", glyph: "\u{F02FA}", title: "Add images",
                 caption: "Copy pictures in from any folder" };
eq("action: kind", describe(action).kind, "action");
eq("action: key is empty", describe(action).key, "");
eq("action: name is the title", describe(action).name, "Add images");
eq("action: thumb is empty", describe(action).thumb, "");
eq("action: type is empty", describe(action).type, "");
// action.action === "" must still read as an action (the browse card could carry it)
eq("action: empty action string still counts as action",
   describe({ action: "", title: "x" }).kind, "action");

// ── degenerate ───────────────────────────────────────────────────────────────
eq("null -> inert image", describe(null),
   { kind: "image", key: "", name: "", thumb: "", type: "", isGif: false });
eq("undefined -> inert image", describe(undefined),
   { kind: "image", key: "", name: "", thumb: "", type: "", isGif: false });
eq("empty string -> inert image", describe("").kind, "image");
check("empty string: name is empty, not undefined", describe("").name === "");

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
