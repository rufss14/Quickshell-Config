// ── test-contagion.js ─────────────────────────────────────────────────────────
// Tests for services/contagion.js — which windows the wave's curtain covers, where
// the front meets each, when each app is told, and Hyprland's border fade.
//
//     bun scripts/test-contagion.js      (or: node scripts/test-contagion.js)
//
// Safe to run: pure functions, no I/O. Same contract as test-kelvin.js — the .js is
// loaded by stripping its `.pragma library` line, so the tests run against the real
// file rather than a copy that can drift.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "contagion.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");

const { reachMax, timeFor, logical, distance, kind, plan, decide, releaseAfter, LEADS, AFTER,
        borderAnim, borderAnimLua, borderFadeMs, borderValue } =
    new Function(src + "\nreturn { reachMax, timeFor, logical, distance, kind, plan, decide, releaseAfter, "
                     + "LEADS, AFTER, borderAnim, borderAnimLua, borderFadeMs, borderValue };")();

let pass = 0, fail = 0;
const failures = [];
function check(name, ok, detail) {
    if (ok) { pass++; return }
    fail++;
    failures.push(`  ${name}${detail ? "\n      " + detail : ""}`);
}
const near = (a, b, eps = 1e-6) => Math.abs(a - b) <= eps;

// ── The front's timing inverts OutCubic exactly ──────────────────────────────
// The shaders' R at progress p is p × reachMax; the spread's p(t) = 1 − (1 − t)³.
// So feeding timeFor's answer back through the curve must land on the distance.
{
    const aspect = 16 / 9, T = 1150;
    for (const d of [0, 0.1, 0.5, 1.0, 1.3, reachMax(aspect)]) {
        const t = timeFor(d, aspect, T) / T;
        const p = 1 - Math.pow(1 - t, 3);
        check(`timeFor round-trips at d=${d.toFixed(2)}`, near(p * reachMax(aspect), d, 1e-9),
              `p=${p} → R=${p * reachMax(aspect)}`);
    }
    check("the origin is reached at once", timeFor(0, aspect, T) === 0);
    check("past the farthest corner is the end", timeFor(99, aspect, T) === T);
    // OutCubic front-loads: half the reach takes well under half the time.
    check("front-loaded like the animation", timeFor(reachMax(aspect) / 2, aspect, T) < T * 0.25);
}

// ── Geometry ─────────────────────────────────────────────────────────────────
{
    const scaled = logical({ x: 0, y: 0, width: 3840, height: 2160, scale: 2, transform: 0 });
    check("logical size divides by the scale", scaled.w === 1920 && scaled.h === 1080, JSON.stringify(scaled));
    const turned = logical({ x: 0, y: 0, width: 1920, height: 1080, scale: 1, transform: 1 });
    check("a quarter turn swaps the axes", turned.w === 1080 && turned.h === 1920, JSON.stringify(turned));

    const mon = { x: 1920, y: 0, width: 1920, height: 1080, scale: 1, transform: 0 };
    // A window straddling the bottom middle is touched at once.
    check("over the origin: distance 0",
          distance({ x: 1920 + 900, y: 900, w: 200, h: 180 }, mon) === 0);
    // The top-left corner window: its nearest point is its bottom-right corner.
    const d = distance({ x: 1920, y: 0, w: 100, h: 100 }, mon);
    check("top-left window measured from its nearest corner",
          near(d, Math.hypot(100 - 960, 100 - 1080) / 1080), d);
    // Monitor offsets are honoured (a window on the second screen, in global coords).
    check("global coordinates are made monitor-local",
          near(distance({ x: 1920 + 960 - 50, y: 1080 - 540, w: 100, h: 10 }, mon), (1080 - 550) / 1080));
}

// ── Which app is which ───────────────────────────────────────────────────────
{
    const discord = ["discord", "vesktop", "webcord", "legcord", "armcord", "dorion"];
    check("kitty", kind("kitty", discord) === "kitty");
    check("Discord Canary via a prefix", kind("discordcanary", discord) === "discord");
    check("Vesktop", kind("vesktop", discord) === "discord");
    check("Zen", kind("zen", discord) === "browser");
    check("Firefox, any case", kind("Firefox", discord) === "browser");
    check("Steam", kind("steam", discord) === "steam");
    check("a Steam game is not the Steam client", kind("steam_app_730", discord) === "");
    check("anything else: border only", kind("org.gnome.Nautilus", discord) === "");
    check("a kitty lookalike is not kitty", kind("kitty-scratch", discord) === "");
    check("no class list: never Discord", kind("vesktop", undefined) === "");
}

// ── The plan: what the curtain covers, and when the front meets each window ────
// Shaped like `hyprctl clients -j` — what Contagion feeds it.
const mons = [
    { id: 0, name: "DP-2", x: 0, y: 0, width: 1920, height: 1080, scale: 1, transform: 0,
      activeWorkspace: 1, specialWorkspace: 0 },
    { id: 1, name: "HDMI-A-1", x: 1920, y: 0, width: 1680, height: 1050, scale: 1, transform: 0,
      activeWorkspace: 2, specialWorkspace: -98 },
];
const discord = ["vesktop", "discord"];
const client = (address, extra) => Object.assign({
    address, pid: 100, class: "", at: [0, 0], size: [100, 100], monitor: 0,
    workspace: { id: 1, name: "1" }, fullscreen: 0, mapped: true, hidden: false }, extra);
{
    const p = plan([
        // The user's real shape: one near-full-screen window per workspace.
        client("0xa1", { class: "zen", at: [78, 60], size: [1820, 998] }),
        client("0xa2", { class: "discord", monitor: 1, workspace: { id: 2 }, at: [1998, 60], size: [1580, 968] }),
        client("0xa3", { class: "Spotify", monitor: 1, workspace: { id: 3 }, at: [1998, 60], size: [1580, 968] }),
        client("0xa4", { class: "kitty", pid: 41, monitor: 1, workspace: { id: -98 }, at: [2200, 300], size: [600, 400] }),
        client("0xa5", { fullscreen: 2, at: [0, 0], size: [1920, 1080] }),
        client("0xa6", { fullscreen: 1, class: "kitty", pid: 42, at: [0, 0], size: [1920, 1080] }),
        client("0xa7", { mapped: false }),
        client("0xa8", { hidden: true }),
        client('0x1" }) hl.exec_cmd("x', {}),
    ], mons, 1150, discord, 3);
    const e = a => p.entries.find(x => x.address === a);

    // Its bottom edge stops 22px short of the screen's (the frame): met in ~5ms.
    check("a near-full-screen window is met almost at once", e("0xa1").at < 20, JSON.stringify(e("0xa1")));
    check("…and covered, grown by the border margin, monitor-local",
          JSON.stringify(p.covers["DP-2"][0]) === JSON.stringify({ x: 75, y: 57, w: 1826, h: 1004 }),
          JSON.stringify(p.covers["DP-2"]));
    check("a window on the other monitor is measured from ITS bottom middle",
          e("0xa2").looked && e("0xa2").at < 20 && e("0xa2").monitor === "HDMI-A-1", JSON.stringify(e("0xa2")));
    check("covers are monitor-local on the second monitor",
          p.covers["HDMI-A-1"].some(r => r.x === 75 && r.y === 57), JSON.stringify(p.covers["HDMI-A-1"]));
    check("another workspace: not looked at, no cover", !e("0xa3").looked
          && p.covers["HDMI-A-1"].length === 2, JSON.stringify(p.covers["HDMI-A-1"]));
    check("an open special workspace is looked at", e("0xa4").looked && e("0xa4").at > 0, JSON.stringify(e("0xa4")));
    check("a looked-at FULLSCREEN window is left out entirely", !e("0xa5"));
    check("a MAXIMISED window is an ordinary one", e("0xa6") && e("0xa6").looked);
    check("unmapped: skipped", !e("0xa7"));
    check("a hidden group tab: not looked at", e("0xa8") && !e("0xa8").looked);
    check("an address that isn't hex never reaches the plan", p.entries.every(x => /^0x[0-9a-f]+$/.test(x.address)));
    check("apps named", e("0xa2").app === "discord" && e("0xa3").app === "spotify"
          && e("0xa4").app === "kitty" && e("0xa1").app === "browser");
    check("covers stay on screen", Object.values(p.covers).flat().every(r => r.x >= 0 && r.y >= 0));
}

// ── Deciding: under the curtain everything is told at once ───────────────────
{
    const p = plan([
        client("0xb1", { class: "vesktop", at: [78, 60], size: [1820, 998] }),       // met at 0
        client("0xb2", { class: "kitty", pid: 7, at: [100, 70], size: [400, 300] }),
        client("0xb3", { class: "kitty", pid: 7, at: [1400, 70], size: [400, 300] }),  // same process
        client("0xb4", { class: "Spotify", workspace: { id: 9 } }),                    // not looked at
    ], mons, 1000, discord, 3);

    const d = decide(p, { "DP-2": true }, {}, 150, 450);
    const app = a => d.flips.filter(f => f.app === a);
    check("everything covered or unseen is due NOW", d.flips.every(f => f.t === 0), JSON.stringify(d.flips));
    check("every window's border flips", d.flips.filter(f => f.border).length === 4);
    check("kitty signalled once per process", app("kitty").length === 1 && app("kitty")[0].pid === 7);
    check("Discord and Spotify told once each", app("discord").length === 1 && app("spotify").length === 1);
    // Under the curtain Discord isn't guessed at: it HOLDS the spread on the real
    // thing, with the front's head start to its nearest window.
    const met = p.entries.find(x => x.address === "0xb1").at;
    const dc = app("discord")[0];
    check("a covered Discord holds the spread", dc.hold === true && dc.atMin === met, JSON.stringify(dc));
    check("…so it adds nothing to the fixed wait (kitty's lead is what's left)",
          d.delay === Math.max(150, LEADS.kitty - p.entries.find(x => x.address === "0xb2").at), d.delay);
    check("an unseen Spotify neither holds nor waits", app("spotify")[0].hold === false && d.delay < LEADS.spotify);
    check("released AFTER what the app does once its script is done, less the head start",
          releaseAfter("discord", met) === AFTER.discord - met && releaseAfter("spotify", 5000) === 0);

    // Uncovered and slow near the start: the fixed wait is capped — a pause, not a wave.
    const slow = decide(plan([client("0xc1", { class: "Spotify", at: [78, 60], size: [1820, 998] })],
                             mons, 1000, discord, 3), {}, {}, 150, 450);
    check("the wait is capped", slow.delay === 600, slow.delay);
    check("uncovered: no hold, just the estimate", slow.flips.every(f => !f.hold));
    // Nothing slow: the palette's own settle.
    const quick = decide(plan([client("0xc2", { at: [700, 100], size: [100, 100] })], mons, 1000, discord, 3),
                         { "DP-2": true }, {}, 150, 450);
    check("no app, no wait beyond the settle", quick.delay === 150, quick.delay);
}

// ── Only the apps this machine can reach ─────────────────────────────────────
{
    const p = plan([
        client("0xe1", { class: "zen", at: [78, 60], size: [1820, 998] }),
        client("0xe2", { class: "discord", monitor: 1, workspace: { id: 2 }, at: [1998, 60], size: [1580, 968] }),
    ], mons, 1000, discord, 3);
    const d = decide(p, { "DP-2": true, "HDMI-A-1": true }, {}, 150, 450, { discord: true });
    check("no Pywalfox: the browser is only a border — no run, no hold",
          !d.flips.some(f => f.app === "browser"), JSON.stringify(d.flips));
    check("…its border still flips", d.flips.some(f => f.border && f.address === "0xe1"));
    check("a reachable Discord still holds", d.flips.some(f => f.app === "discord" && f.hold));
    check("the plan itself is untouched", p.entries.find(x => x.address === "0xe1").app === "browser");
}

// ── Steam: scripted like the others, and only when the user opted in ─────────
{
    const p = plan([client("0xf1", { class: "steam", at: [78, 60], size: [1820, 998] })], mons, 1000, discord, 3);
    check("planned as steam", p.entries.find(x => x.address === "0xf1").app === "steam");
    const on = decide(p, { "DP-2": true }, {}, 150, 450, { steam: true });
    check("reachable: one run, and the wave holds for it",
          on.flips.filter(f => f.app === "steam").length === 1 && on.flips.find(f => f.app === "steam").hold === true,
          JSON.stringify(on.flips));
    const off = decide(p, { "DP-2": true }, {}, 150, 450, {});
    check("not opted in: Steam is only a border — no run, no hold", !off.flips.some(f => f.app === "steam"), JSON.stringify(off.flips));
    check("…its border still flips", off.flips.some(f => f.border && f.address === "0xf1"));
    check("its script's exit is the repaint: only a frame of margin after", AFTER.steam > 0 && AFTER.steam <= 40, AFTER.steam);
    check("released after that, less the head start", releaseAfter("steam", 5) === Math.max(0, AFTER.steam - 5));
}

// ── Deciding without a curtain: timed to the front ───────────────────────────
{
    const T = 1000;
    const p = plan([
        client("0xd1", { class: "kitty", pid: 9, at: [0, 0], size: [100, 100] }),       // a far corner
        client("0xd2", { at: [900, 960], size: [120, 120] }),                           // at the origin
    ], mons, T, discord, 3);
    const d = decide(p, {}, {}, 150, 450);
    const corner = p.entries.find(x => x.address === "0xd1");
    const f = a => d.flips.find(x => x.address === a && x.border);
    check("uncovered: a border lands as the front arrives",
          f("0xd1").t === d.delay + corner.at - LEADS.border, JSON.stringify({ t: f("0xd1").t, at: corner.at, delay: d.delay }));
    check("uncovered: an app is told its lead early",
          d.flips.find(x => x.app === "kitty").t === d.delay + corner.at - LEADS.kitty);
    check("never before now", d.flips.every(x => x.t >= 0));
    check("soonest first", d.flips.every((x, i) => i === 0 || d.flips[i - 1].t <= x.t));
    // A border fade that couldn't be held off leads by its whole length.
    const faded = decide(p, {}, { border: 640 }, 150, 450);
    check("a border fade left on leads by its length (within the cap)",
          faded.delay === Math.min(600, 640 - p.entries.find(x => x.address === "0xd2").at), faded.delay);
}

// ── Hyprland's border fade: read, switched off, put back exactly ─────────────
{
    const leaf = { name: "border", overridden: true, bezier: "liner", enabled: true, speed: 6.4, style: "" };
    const a = borderAnim(leaf);
    check("a leaf of its own is kept", a && a.speed === 6.4 && a.curve === "liner" && a.enabled);
    check("switched off with its own values",
          borderAnimLua(a, false) === 'hl.animation({ leaf = "border", enabled = false, speed = 6.4, bezier = "liner" })',
          borderAnimLua(a, false));
    check("put back exactly", borderAnimLua(a, true).includes("enabled = true, speed = 6.4, bezier = \"liner\""));
    check("its length, in ms", borderFadeMs(a) === 640);
    check("a style rides along", borderAnimLua(borderAnim(Object.assign({}, leaf, { style: "once" })), true)
          .endsWith(', style = "once" })'));
    check("an inherited leaf can't be put back: left alone",
          borderAnim({ name: "border", overridden: false, bezier: "", enabled: true, speed: 0 }) === null);
    check("a curve name that isn't a word never reaches Lua",
          borderAnim(Object.assign({}, leaf, { bezier: 'x" }) hl.exec_cmd("y' })) === null);
    check("no leaf, no Lua", borderAnimLua(null, false) === "");
    check("a disabled fade is no fade", borderFadeMs(borderAnim(Object.assign({}, leaf, { enabled: false }))) === 0);
}

// ── Border values ────────────────────────────────────────────────────────────
{
    check("hex → Hyprland rgba", borderValue("#1A2b3C") === "rgba(1a2b3cff)");
    check("not a colour → nothing", borderValue("red") === "" && borderValue("#12345") === ""
          && borderValue('#123456") })--') === "" && borderValue(undefined) === "");
}

if (fail) {
    console.log(failures.join("\n"));
    console.log(`\n${pass} passed, ${fail} failed`);
    process.exit(1);
}
console.log(`${pass} passed`);
