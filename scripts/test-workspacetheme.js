// ── test-workspacetheme.js ────────────────────────────────────────────────────
// services/workspacetheme.js — which windows, terminals and apps get which palette.
//
//     bun scripts/test-workspacetheme.js          (or: node scripts/test-workspacetheme.js)
//
// Safe: pure. contagion.js is loaded for its app kinds, both with their QML
// directives stripped.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const read = f => readFileSync(join(here, "..", "services", f), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "").replace(/^\s*\.import\s+.*$/mg, "");
const Kinds = new Function(read("contagion.js") + "\nreturn { kind };")();
const W = new Function("Kinds", read("workspacetheme.js") + "\nreturn { plan, parseOwn, effectiveScenes, sceneKey };")(Kinds);

let passed = 0, failed = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) passed++;
    else { failed++; console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`); }
}

const LIVE = "/c/wal/colors.json", ARCH = "/c/ws/arch/colors.json", FUR = "/c/ws/furina/colors.json";
const own = { 2: ARCH, 3: ARCH, 4: FUR };
const fileFor = ws => own[ws] || "";
const C = (address, cls, ws, pid) => ({ address, class: cls, workspace: { id: ws }, pid });
const clients = [
    C("0xa1", "discord", 2, 1687),
    C("0xa2", "kitty", 4, 500),
    C("0xa3", "kitty", 4, 501),
    C("0xa4", "steam_proton", 1, 2442),
    C("0xa5", "Spotify", 3, 900),
];

let p = W.plan(clients, fileFor, LIVE, {}, ["discord"]);
check("borders: only the windows on workspaces with their own", p.borders.map(b => b.address + ">" + b.file),
      ["0xa1>" + ARCH, "0xa2>" + FUR, "0xa3>" + FUR, "0xa5>" + ARCH]);
check("terminals grouped by palette", p.terminals, { [FUR]: [500, 501] });
check("Discord and Spotify wear their window's workspace", p.apps, { [ARCH]: ["discord", "spotify"] });
check("nothing told twice", W.plan(clients, fileFor, LIVE, p.wears, ["discord"]),
      { borders: [], terminals: {}, apps: {}, wears: p.wears });

// Discord's workspace loses its own wallpaper: it goes back to the shared palette.
const own2 = { 4: FUR };
let q = W.plan(clients, ws => own2[ws] || "", LIVE, p.wears, ["discord"]);
check("back to shared: Discord told the live palette", q.apps, { [LIVE]: ["discord", "spotify"] });
check("back to shared: its border too", q.borders.map(b => b.address + ">" + b.file),
      ["0xa1>" + LIVE, "0xa5>" + LIVE]);
check("back to shared: wearing the shared one leaves no record", "0xa1" in q.wears || "app:discord" in q.wears, false);

// A window moved onto another workspace.
const moved = clients.map(c => c.address === "0xa2" ? C("0xa2", "kitty", 2, 500) : c);
let m = W.plan(moved, fileFor, LIVE, p.wears, ["discord"]);
check("moved terminal re-told", m.terminals, { [ARCH]: [500] });
check("moved window's border re-told", m.borders.map(b => b.address), ["0xa2"]);

// Closed windows are forgotten.
let g = W.plan(clients.slice(0, 1), fileFor, LIVE, p.wears, ["discord"]);
check("closed windows and pids dropped", Object.keys(g.wears).sort(), ["0xa1", "app:discord"]);

check("junk addresses ignored", W.plan([C("nope", "kitty", 2, 5)], fileFor, LIVE, {}, []).borders, []);
check("special workspaces wear the shared palette", W.plan([C("0xb1", "kitty", -98, 7)], fileFor, LIVE, {}, []),
      { borders: [], terminals: {}, apps: {}, wears: {} });

// ── Scenes per workspace ───────────────────────────────────────────────────────
check("own: an image", W.parseOwn("/w/a.png"), { image: "/w/a.png" });
check("own: a scene", W.parseOwn("scene:3661092645"), { scene: "3661092645" });
check("own: a bad scene id", W.parseOwn("scene:../../x"), null);
check("own: a relative path", W.parseOwn("a.png"), null);
check("own: junk", W.parseOwn(42), null);

const SH = { isScene: true, defaultId: "111", perScreen: { "HDMI-A-1": "222" }, target: ["DP-2", "HDMI-A-1"] };
check("shared scene, no workspace scenes", W.effectiveScenes(["DP-2", "HDMI-A-1"], {}, SH), { "DP-2": "111", "HDMI-A-1": "222" });
check("a workspace scene on one screen", W.effectiveScenes(["DP-2", "HDMI-A-1"], { "DP-2": "333" }, SH),
      { "DP-2": "333", "HDMI-A-1": "222" });
check("a workspace picture takes its screen off the renderer", W.effectiveScenes(["DP-2", "HDMI-A-1"], { "DP-2": "" }, SH),
      { "HDMI-A-1": "222" });
check("shared is a picture: only workspace scenes play", W.effectiveScenes(["DP-2", "HDMI-A-1"], { "HDMI-A-1": "333" },
      { isScene: false }), { "HDMI-A-1": "333" });
check("nothing wants a scene", W.effectiveScenes(["DP-2"], { "DP-2": "" }, { isScene: false }), {});
check("default scene pinned to one screen", W.effectiveScenes(["DP-2", "HDMI-A-1"], {},
      { isScene: true, defaultId: "111", perScreen: {}, target: ["DP-2"] }), { "DP-2": "111" });
check("key is order-free", W.sceneKey({ b: "2", a: "1" }), W.sceneKey({ a: "1", b: "2" }));
check("key of nothing", W.sceneKey({}), "");

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
