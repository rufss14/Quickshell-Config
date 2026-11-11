// ── test-dock.js ──────────────────────────────────────────────────────────────
// Regression tests for services/dock.js, the dock's ordering, grouping, click
// and drag arithmetic.
//
//     bun scripts/test-dock.js          (or: node scripts/test-dock.js)
//
// Safe to run: dock.js is pure functions and touches nothing.
//
// The cases that matter are the ones that go wrong quietly on screen: an app
// drawn twice, a click landing on the wrong window, a pin dropped one slot
// short, a dragged running app that pins itself when it was only nudged.
//
// Loaded by stripping the `.pragma library` line (a QML directive that isn't
// valid JS) and evaluating the rest, so the tests run against the real file
// rather than a copy that can drift.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "dock.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");

const { dedupe, order, group, next, cycle, dropTarget, shift, fit, tileSize,
        idCandidates, audioByKey, playerByKey, badgeCounts, badgeText,
        overlaps, groupPerMonitor, stepFocus, execArgv, fileUrlToPath, pathToFileUrl,
        insertTarget, downloadDir, magnify, groupBy, parseGioInfo, magnifyBoxes, magnifyBell, sideRail, sideGroups, sideJoins, sideSurface, railAvoid, thumbAspect } =
    new Function(src + "\nreturn { dedupe, order, group, next, cycle, dropTarget, shift, fit, " +
                 "tileSize, idCandidates, audioByKey, playerByKey, badgeCounts, badgeText, " +
                 "overlaps, groupPerMonitor, stepFocus, execArgv, fileUrlToPath, pathToFileUrl, " +
                 "insertTarget, downloadDir, magnify, groupBy, parseGioInfo, magnifyBoxes, magnifyBell, sideRail, sideGroups, sideJoins, sideSurface, railAvoid, thumbAspect };")();

let pass = 0;
let fail = 0;

function check(name, got, want) {
    const g = JSON.stringify(got);
    const w = JSON.stringify(want);
    if (g === w) {
        pass++;
    } else {
        fail++;
        console.log(`  FAIL  ${name}\n          got  ${g}\n          want ${w}`);
    }
}

// ── dedupe / order ────────────────────────────────────────────────────────────
check("dedupe keeps first occurrence", dedupe(["a", "b", "a", "c", "b"]), ["a", "b", "c"]);
check("dedupe drops empty keys",       dedupe(["", "a", null, "b", undefined]), ["a", "b"]);
check("dedupe survives prototype names",
      dedupe(["constructor", "toString", "constructor"]), ["constructor", "toString"]);

check("order: pins first, then unpinned running",
      order(["firefox", "kitty"], ["discord", "kitty", "zen"]),
      ["firefox", "kitty", "discord", "zen"]);
check("order: a pinned+running app is drawn once, in its pin slot",
      order(["kitty"], ["kitty"]), ["kitty"]);
check("order: nothing pinned",  order([], ["a", "b"]), ["a", "b"]);
check("order: nothing running", order(["a", "b"], []), ["a", "b"]);
check("order: duplicate pins collapse to the first",
      order(["spotify", "kitty", "spotify"], []), ["spotify", "kitty"]);

// ── group ─────────────────────────────────────────────────────────────────────
{
    const g = group([
        { key: "kitty",   ref: "k1", activated: false, urgent: false, seq: 3 },
        { key: "zen",     ref: "z1", activated: true,  urgent: false, seq: 9 },
        { key: "kitty",   ref: "k2", activated: false, urgent: true,  seq: 7 },
        { key: "discord", ref: "d1", activated: false, urgent: false, seq: 0 },
    ]);
    check("group: keys in first-seen order", g.order, ["kitty", "zen", "discord"]);
    check("group: windows keep OPENING order (not recency)", g.byKey.kitty.windows, ["k1", "k2"]);
    check("group: recent = highest focus seq", g.byKey.kitty.recent, "k2");
    check("group: urgent if any window is",    g.byKey.kitty.urgent, true);
    check("group: focused if any window is",   g.byKey.zen.focused, true);
    check("group: not focused otherwise",      g.byKey.kitty.focused, false);
    check("group: count",                      g.byKey.kitty.count, 2);
    check("group: never-focused app → first window", g.byKey.discord.recent, "d1");
    check("group: no internal fields leak",    Object.keys(g.byKey.discord).sort(),
          ["count", "focused", "key", "recent", "urgent", "windows"]);
}
{
    const g = group([
        { key: "a", ref: "a1", seq: 0 },
        { key: "a", ref: "a2", seq: 0 },
    ]);
    check("group: all-zero seq → first-opened wins the tie", g.byKey.a.recent, "a1");
}
check("group: skips keyless windows",
      group([{ key: "", ref: "x" }, { key: "a", ref: "a1" }]).order, ["a"]);
check("group: prototype-named key is a real group",
      group([{ key: "constructor", ref: "c1" }]).byKey.constructor.windows, ["c1"]);

// ── next ──────────────────────────────────────────────────────────────────────
check("next: cycles forward",          next(["a", "b", "c"], "a"), "b");
check("next: wraps at the end",        next(["a", "b", "c"], "c"), "a");
check("next: lone window → null",      next(["a"], "a"), null);
check("next: focus elsewhere → first", next(["a", "b"], "zzz"), "a");
check("next: empty → null",            next([], null), null);

// ── dropTarget ────────────────────────────────────────────────────────────────
// slot = 50; 5 icons, the first 3 pinned.
check("drop: centre inside slot 0",        dropTarget(2, 10,  50, 5, 3), 0);
check("drop: exactly on a slot boundary",  dropTarget(0, 100, 50, 5, 3), 2);
check("drop: pins clamp to the pinned run", dropTarget(0, 240, 50, 5, 3), 2);
check("drop: before the start clamps to 0", dropTarget(2, -40, 50, 5, 3), 0);
check("drop: running app into pins → that slot",   dropTarget(4, 60,  50, 5, 3), 1);
check("drop: running app among running → back home", dropTarget(4, 170, 50, 5, 3), 4);
check("drop: running app over its own slot → home",  dropTarget(3, 170, 50, 5, 3), 3);
check("drop: nothing pinned, running stays put",     dropTarget(1, 10,  50, 3, 0), 1);
check("drop: empty strip",                 dropTarget(0, 10, 50, 0, 0), 0);

// ── shift ─────────────────────────────────────────────────────────────────────
// Dragging index 1 to 3: 2 and 3 step back one slot, the rest stay.
check("shift: rightward drag", [0, 1, 2, 3, 4].map(i => shift(i, 1, 3)), [0, 0, -1, -1, 0]);
// Dragging index 3 to 1: 1 and 2 step forward one slot.
check("shift: leftward drag",  [0, 1, 2, 3, 4].map(i => shift(i, 3, 1)), [0, 1, 1, 0, 0]);
check("shift: no move → nothing shifts", [0, 1, 2].map(i => shift(i, 1, 1)), [0, 0, 0]);
check("shift: no drag → nothing shifts", [0, 1, 2].map(i => shift(i, -1, -1)), [0, 0, 0]);
// A running app (index 4) dropped into pin slot 1: the pins from 1 on make room.
check("shift: running into pins", [0, 1, 2, 3, 4].map(i => shift(i, 4, 1)), [0, 1, 1, 1, 0]);

// ── fit ───────────────────────────────────────────────────────────────────────
check("fit: landscape into landscape", fit(1920, 1080, 224, 126), { w: 224, h: 126 });
check("fit: portrait is pillarboxed",  fit(1080, 1920, 224, 126), { w: 71,  h: 126 });
check("fit: ultrawide is letterboxed", fit(3440, 1440, 224, 126), { w: 224, h: 94 });
check("fit: unknown source → whole box", fit(0, 0, 224, 126), { w: 224, h: 126 });

// ── tileSize ──────────────────────────────────────────────────────────────────
check("tile: room to spare → ideal",       tileSize(2, 1000, 224, 120, 8), 224);
check("tile: shrinks evenly to fit",       tileSize(5, 1000, 224, 120, 8), 193);
check("tile: never below the minimum",     tileSize(20, 1000, 224, 120, 8), 120);
check("tile: zero windows → ideal",        tileSize(0, 1000, 224, 120, 8), 224);

// ── cycle ─────────────────────────────────────────────────────────────────────
check("cycle: back from the first wraps to the last", cycle(["a", "b", "c"], "a", -1), "c");
check("cycle: back one",                cycle(["a", "b", "c"], "c", -1), "b");
check("cycle: focus elsewhere, back → last", cycle(["a", "b"], "z", -1), "b");
check("cycle: lone window → null",      cycle(["a"], "a", -1), null);

// ── idCandidates ──────────────────────────────────────────────────────────────
check("ids: binary suffixes dropped as extra candidates",
      idCandidates(["zen-bin", "Zen"]), ["zen-bin", "zen"]);
check("ids: chrome's -stable",  idCandidates(["google-chrome-stable"]),
      ["google-chrome-stable", "google-chrome"]);
check("ids: empties and repeats dropped", idCandidates(["", null, "Spotify", "spotify"]), ["spotify"]);
check("ids: a name that merely CONTAINS 'bin' is left whole", idCandidates(["binance"]), ["binance"]);

// ── audioByKey ────────────────────────────────────────────────────────────────
{
    const a = audioByKey([
        { key: "zen",     ref: "s1", muted: true,  level: 0.4 },
        { key: "zen",     ref: "s2", muted: false, level: 0.7 },
        { key: "spotify", ref: "s3", muted: true,  level: 0.5 },
    ]);
    check("audio: streams grouped", a.zen.streams, ["s1", "s2"]);
    check("audio: one unmuted stream → not muted", a.zen.muted, false);
    check("audio: all muted → muted", a.spotify.muted, true);
    check("audio: level is the loudest", a.zen.level, 0.7);
}

// ── playerByKey ───────────────────────────────────────────────────────────────
check("player: the playing one wins",
      playerByKey([{ key: "zen", ref: "p1", playing: false },
                   { key: "zen", ref: "p2", playing: true },
                   { key: "zen", ref: "p3", playing: true }]).zen, "p2");
check("player: none playing → first",
      playerByKey([{ key: "zen", ref: "p1", playing: false },
                   { key: "zen", ref: "p2", playing: false }]).zen, "p1");

// ── badgeCounts ───────────────────────────────────────────────────────────────
{
    const b = badgeCounts([
        { key: "discord", time: 50  },    // before the shell started
        { key: "discord", time: 150 },
        { key: "discord", time: 250 },    // after it was last looked at
        { key: "mail",    time: 120 },
    ], { discord: 200 }, 100);
    check("badge: only after start AND after last seen", b.discord, 1);
    check("badge: never seen → since start", b.mail, 1);
    check("badge: zero counts omitted", Object.keys(badgeCounts([{ key: "x", time: 1 }], {}, 5)), []);
}
check("badgeText: small", badgeText(3), "3");
check("badgeText: capped", badgeText(12), "9+");

// ── overlaps ──────────────────────────────────────────────────────────────────
{
    const dock = { x: 700, y: 1000, w: 500, h: 60 };
    check("overlap: a window over the dock",   overlaps(dock, [{ x: 0, y: 0, w: 1920, h: 1040 }]), true);
    check("overlap: a window above it",        overlaps(dock, [{ x: 0, y: 0, w: 1920, h: 1000 }]), false);
    check("overlap: touching the edge ≠ over", overlaps(dock, [{ x: 0, y: 900, w: 700, h: 180 }]), false);
    check("overlap: beside it",                overlaps(dock, [{ x: 1300, y: 900, w: 300, h: 180 }]), false);
    check("overlap: no windows",               overlaps(dock, []), false);
    check("overlap: empty dock rect",          overlaps({ x: 0, y: 0, w: 0, h: 60 }, [{ x: 0, y: 0, w: 99, h: 99 }]), false);
}

// ── groupPerMonitor ───────────────────────────────────────────────────────────
{
    const m = groupPerMonitor([
        { key: "kitty", ref: "k1", monitor: "DP-2" },
        { key: "kitty", ref: "k2", monitor: "HDMI-A-1" },
        { key: "zen",   ref: "z1", monitor: "DP-2" },
        { key: "lost",  ref: "l1" },
    ]);
    check("perMonitor: split by monitor", m["DP-2"].order, ["kitty", "zen"]);
    check("perMonitor: each keeps only its windows", m["HDMI-A-1"].byKey.kitty.windows, ["k2"]);
    check("perMonitor: no monitor → nowhere", Object.keys(m).sort(), ["DP-2", "HDMI-A-1"]);
}

// ── stepFocus ─────────────────────────────────────────────────────────────────
check("focus: right from the launcher", stepFocus(-1, 1, 3, true), 0);
check("focus: left onto the launcher",  stepFocus(0, -1, 3, true), -1);
check("focus: no launcher clamps at 0", stepFocus(0, -1, 3, false), 0);
check("focus: clamps at the end",       stepFocus(2, 1, 3, true), 2);
check("focus: home / end",              [stepFocus(2, "home", 3, true), stepFocus(-1, "end", 3, true)], [-1, 2]);
check("focus: empty dock, launcher only", stepFocus(-1, 1, 0, true), -1);

// ── fileUrlToPath / pathToFileUrl ─────────────────────────────────────────────
check("url→path: plain",        fileUrlToPath("file:///home/u/a.txt"), "/home/u/a.txt");
check("url→path: localhost",    fileUrlToPath("file://localhost/tmp/x"), "/tmp/x");
check("url→path: escapes",      fileUrlToPath("file:///home/u/My%20File%23.txt"), "/home/u/My File#.txt");
check("url→path: not local",    fileUrlToPath("https://example.com/a"), "");
check("path→url: # and space escaped", pathToFileUrl("/a b/c#d"), "file:///a%20b/c%23d");

// ── execArgv ──────────────────────────────────────────────────────────────────
check("exec: %F expands every file",
      execArgv("code-oss %F", ["/a", "/b"]), { argv: ["code-oss", "/a", "/b"], acceptsFiles: true });
check("exec: %u is one URL",
      execArgv("firefox %u", ["/x y.html", "/z"]), { argv: ["firefox", "file:///x%20y.html"], acceptsFiles: true });
check("exec: no file code → refuses",
      execArgv("spotify --uri=spotify:x", ["/a"]).acceptsFiles, false);
check("exec: quoted args and escapes",
      execArgv('sh -c "echo \\"hi\\" $x" %f', ["/f"]).argv, ["sh", "-c", 'echo "hi" $x', "/f"]);
check("exec: %i %c %k dropped, %% kept",
      execArgv("app %i %c --pct=50%% %k %f", ["/f"]).argv, ["app", "--pct=50%", "/f"]);
check("exec: embedded code",
      execArgv("app --file=%f", ["/f"]).argv, ["app", "--file=/f"]);
check("exec: flatpak's @@ markers survive",
      execArgv("/usr/bin/flatpak run --file-forwarding org.x.App @@u %U @@", ["/f"]).argv,
      ["/usr/bin/flatpak", "run", "--file-forwarding", "org.x.App", "@@u", "file:///f", "@@"]);
check("exec: no files given → codes vanish",
      execArgv("gimp %U", []), { argv: ["gimp"], acceptsFiles: true });
check("exec: quoted empty argument kept", execArgv('app "" %f', ["/f"]).argv, ["app", "", "/f"]);

// ── insertTarget ──────────────────────────────────────────────────────────────
// slot 50, 3 pins, 5 drawn. A NEW app lands on the nearest gap between pins.
check("insert: before the first pin",   insertTarget(-1, 10,  50, 5, 3), 0);
check("insert: between pins 1 and 2",   insertTarget(-1, 95,  50, 5, 3), 2);
check("insert: just after the last pin", insertTarget(-1, 400, 50, 5, 3), 3);
check("insert: no pins yet",            insertTarget(-1, 200, 50, 2, 0), 0);
check("insert: already pinned → a move", insertTarget(0, 120, 50, 5, 3), 2);
check("insert: running → pins it there", insertTarget(4, 60, 50, 5, 3), 1);

// ── downloadDir ───────────────────────────────────────────────────────────────
check("downloads: no file → ~/Downloads", downloadDir("", "/home/u"), "/home/u/Downloads");
check("downloads: $HOME expanded", downloadDir('XDG_DOWNLOAD_DIR="$HOME/Téléchargements"\n', "/home/u"),
      "/home/u/Téléchargements");
check("downloads: absolute kept", downloadDir('XDG_DOWNLOAD_DIR="/data/dl/"', "/home/u"), "/data/dl");
check("downloads: relative rejected", downloadDir('XDG_DOWNLOAD_DIR="dl"', "/home/u"), "/home/u/Downloads");
check("downloads: other dirs ignored",
      downloadDir('XDG_DESKTOP_DIR="$HOME/Desktop"', "/home/u"), "/home/u/Downloads");
check("downloads: $HOMEX isn't $HOME", downloadDir('XDG_DOWNLOAD_DIR="$HOMEX/d"', "/h"), "/h/Downloads");

// ── magnify ───────────────────────────────────────────────────────────────────
check("magnify: full under the pointer", magnify(0, 100, 1.5), 1.5);
check("magnify: none at the range",      magnify(100, 100, 1.5), 1);
check("magnify: none past it",           magnify(250, 100, 1.5), 1);
check("magnify: halfway is half",        Math.round(magnify(50, 100, 1.5) * 100) / 100, 1.25);
check("magnify: symmetric",              magnify(-30, 100, 1.4), magnify(30, 100, 1.4));

// ── groupBy ───────────────────────────────────────────────────────────────────
{
    const w = groupBy([
        { key: "kitty", ref: "k1", workspace: 1 },
        { key: "kitty", ref: "k2", workspace: 3 },
        { key: "zen",   ref: "z1", workspace: 1 },
        { key: "odd",   ref: "o1", workspace: 0 },
    ], "workspace");
    check("groupBy: per workspace", w["1"].order, ["kitty", "zen"]);
    check("groupBy: workspace 0 is a real value", w["0"].order, ["odd"]);
    check("groupBy: only that workspace's windows", w["3"].byKey.kitty.windows, ["k2"]);
}

// ── parseGioInfo ──────────────────────────────────────────────────────────────
check("gio: a folder, symbolic icons dropped",
      parseGioInfo("type: directory\nuri: file:///h/D\nattributes:\n  standard::type: 2\n" +
                   "  standard::icon: inode-directory, folder, inode-directory-symbolic, folder-symbolic\n"),
      { dir: true, icons: ["inode-directory", "folder"] });
check("gio: a regular file",
      parseGioInfo("attributes:\n  standard::type: 1\n  standard::icon: text-plain, text-x-generic\n"),
      { dir: false, icons: ["text-plain", "text-x-generic"] });
check("gio: an error is null",
      parseGioInfo("gio: file:///x: Error when getting information for file: No such file or directory"), null);

// ── magnifyBoxes ──────────────────────────────────────────────────────────────
{
    const scale = c => (c === 50 ? 1.5 : c === 100 ? 1.2 : 1.0);   // 48px buttons
    const b = magnifyBoxes([0, 50, 100, 150], scale, 48, 2, "bottom", 1.01);
    check("boxes: only swollen buttons", b.length, 2);
    check("boxes: bottom dock grows upward from the outer edge",
          b[0], { x: 14, y: -26, w: 72, h: 74 });
    check("boxes: smaller swell, smaller box", b[1].h < b[0].h, true);
    const l = magnifyBoxes([50], scale, 48, 2, "left", 1.01)[0];
    check("boxes: left dock grows rightward", [l.x, l.w], [0, 74]);
    const r = magnifyBoxes([50], scale, 48, 2, "right", 1.01)[0];
    check("boxes: right dock grows leftward", [r.x, r.w], [-26, 74]);
    check("boxes: nothing swollen, nothing drawn", magnifyBoxes([0, 50], () => 1, 48, 2, "bottom", 1.01), []);
}

// ── magnifyBell ───────────────────────────────────────────────────────────────
{
    // pointer 300 on a 0..600 strip, range 100, peak 1.5×, 48px buttons, no lift.
    const b = magnifyBell(300, 100, 1.5, 1, 48, 0, "bottom", 0, 600, 4);
    check("bell: one box per layer", b.length, 4);
    check("bell: layers get taller…", b.map(x => Math.round(-x.y)), [6, 12, 18, 24]);
    check("bell: …and narrower", b[0].w > b[1].w && b[1].w > b[2].w && b[2].w > b[3].w, true);
    check("bell: centred on the pointer", b.every(x => Math.abs(x.x + x.w / 2 - 300) < 0.001), true);
    check("bell: the top layer is the icon's own width", Math.round(b[3].w), 72);
    check("bell: reaches the full button depth", b[0].h, 48 + 6);
    const e = magnifyBell(10, 100, 1.5, 1, 48, 0, "bottom", 0, 600, 4);
    check("bell: clamped to the dock's start", e.every(x => x.x >= 0), true);
    check("bell: nothing at zero strength", magnifyBell(300, 100, 1.5, 0, 48, 0, "bottom", 0, 600, 4), []);
    const half = magnifyBell(300, 100, 1.5, 0.5, 48, 0, "bottom", 0, 600, 4);
    check("bell: half strength, half the height", Math.round(-half[3].y), 12);
    const l = magnifyBell(300, 100, 1.5, 1, 48, 0, "left", 0, 600, 4)[3];
    check("bell: left dock swells rightward", [l.x, Math.round(l.w)], [0, 72]);
    check("bell: each layer as round as it is tall", b.map(x => Math.round(x.r)), [6, 12, 18, 24]);
    check("bell: radius never past half the layer's length",
          magnifyBell(300, 10, 3, 1, 48, 0, "bottom", 0, 600, 1)[0].r <= 48 * 3 / 2, true);
}

// ── sideRail / railAvoid ─────────────────────────────────────────────────────
{
    // The layout every sidebar had before it could be arranged: clips in the near
    // corner, the dock centred, stats in the far corner. These pin that nothing moved.
    const CLASSIC = { start: [["clips"]], centre: [["dock"]], end: [["stats"]] };
    const rail = (start, end, margin, dockLen, statsLen, gap, avoid, corner, clipsLen = 0, near = start,
                  collapsed = false, layout = CLASSIC) =>
        sideRail({ start, end, margin, gap, near, corner, avoid, collapsed, layout,
                   lengths: { dock: dockLen, stats: statsLen, clips: clipsLen } });

    check("rail: dock alone, centred", rail(0, 1000, 50, 200, 0, 20, 0, 1000).at.dock, 400);
    check("rail: stats alone, at the far end", rail(0, 1000, 50, 0, 100, 20, 0, 1000).at.stats, 900);
    check("rail: dock stays centred, stats in the corner", rail(0, 1000, 50, 200, 100, 20, 0, 1000).at, { dock: 400, stats: 900 });
    check("rail: dock steps past a panel", rail(0, 1000, 50, 200, 100, 20, 500, 1000).at, { dock: 500, stats: 900 });
    check("rail: a panel above the centre changes nothing", rail(0, 1000, 50, 200, 0, 20, 100, 1000).at.dock, 400);
    check("rail: can't clear it → stops short of the stats", rail(0, 1000, 50, 200, 100, 20, 900, 1000).at, { dock: 680, stats: 900 });
    check("rail: a long dock slides back from the stats", rail(0, 1000, 50, 800, 100, 20, 0, 1000).at.dock, 80);
    check("rail: never before the start margin", rail(100, 400, 50, 400, 0, 20, 0, 400).at.dock, 150);
    check("rail: clips stuck in the near corner", rail(0, 1000, 50, 200, 100, 20, 0, 1000, 60, 0).at, { clips: 0, dock: 400, stats: 900 });
    check("rail: the near corner can be the bar's edge", rail(40, 1000, 50, 200, 100, 20, 0, 1000, 60, 40).at.clips, 40);
    check("rail: the dock clears the clips by the gap", rail(0, 1000, 50, 800, 100, 20, 0, 1000, 60, 0).at.dock, 80);
    check("rail: …but never the start margin, short clips", rail(0, 1000, 50, 870, 100, 20, 0, 1000, 10, 0).at.dock, 50);
    check("rail: collapsed clips give the dock its room back",
          rail(0, 1000, 50, 200, 100, 20, 500, 1000, 60, 0, true).at, { clips: 0, dock: 500, stats: 900 });
    check("rail: an absent module is not placed", rail(0, 1000, 50, 200, 0, 20, 0, 1000).at, { dock: 400 });

    // ── The dock's room never depends on the dock's own length ────────────────
    // SideRail pins the dock's length to 1 to compute `dockRoom`, so that room doesn't
    // read the dock's own (animated) length: DockHost caps its length by that room, and
    // reading it back closed a binding loop ("Binding loop detected for property placed").
    // That is only sound while this holds, in every region the dock can stand in.
    {
        const roomOf = (layout, dock, extra = {}) =>
            sideRail(Object.assign({ start: 0, end: 1000, margin: 50, gap: 20, near: 0, corner: 1000,
                                     avoid: 0, collapsed: false, layout,
                                     lengths: { dock, clips: 60, stats: 100, voice: 80 } }, extra)).room.dock;
        const layouts = {
            "start":  { start: [["dock"], ["clips"]], centre: [["voice"]], end: [["stats"]] },
            "centre": { start: [["clips"]], centre: [["dock"], ["voice"]], end: [["stats"]] },
            "end":    { start: [["clips"]], centre: [["voice"]], end: [["dock"], ["stats"]] },
            "alone":  { start: [], centre: [["dock"]], end: [] },
        };
        for (const [name, layout] of Object.entries(layouts))
            for (const extra of [{}, { avoid: 400 }, { collapsed: true }])
                check("rail: room.dock ignores the dock's length (" + name + ", " + JSON.stringify(extra) + ")",
                      [0, 1, 200, 900].map(d => roomOf(layout, d, extra)).every((r, _, a) => r === a[0]), true);
        check("rail: …and a dock that isn't in the layout has no room entry",
              sideRail({ start: 0, end: 1000, margin: 50, gap: 20, near: 0, corner: 1000, avoid: 0, collapsed: false,
                         layout: { start: [], centre: [["voice"]], end: [] }, lengths: { dock: 1, voice: 80 } }).room.dock, undefined);
    }

    // ── Anything anywhere ─────────────────────────────────────────────────────
    const any = (layout, lengths, extra = {}) =>
        sideRail(Object.assign({ start: 0, end: 1000, margin: 50, gap: 20, near: 0, corner: 1000,
                                 avoid: 0, collapsed: false, layout, lengths }, extra));
    check("rail: the dock can stand in the near corner",
          any({ start: [["dock"]], centre: [], end: [["stats"]] }, { dock: 300, stats: 100 }).at,
          { dock: 0, stats: 900 });
    check("rail: two groups in a corner pack from it, in order",
          any({ start: [["clips"], ["power"]], centre: [], end: [] }, { clips: 60, power: 40 }).at,
          { clips: 0, power: 80 });
    check("rail: the far corner packs back from it; the LAST group is flush",
          any({ start: [], centre: [], end: [["tools"], ["stats"]] }, { tools: 40, stats: 100 }).at,
          { tools: 840, stats: 900 });
    check("rail: two centre groups are centred as one block",
          any({ start: [], centre: [["dock"], ["voice"]], end: [] }, { dock: 200, voice: 60 }).at,
          { dock: 360, voice: 580 });
    check("rail: members of a group sit `inner` apart inside `pad`",
          any({ start: [], centre: [["dock", "tools"]], end: [] }, { dock: 200, tools: 40 },
              { pad: 4, inner: 2 }).groups,
          [{ region: "centre", index: 0, ids: ["dock", "tools"], pos: 375, len: 250 }]);
    check("rail: …and each member's own place follows",
          any({ start: [], centre: [["dock", "tools"]], end: [] }, { dock: 200, tools: 40 },
              { pad: 4, inner: 2 }).at,
          { dock: 379, tools: 581 });
    check("rail: a 0-long member takes no room and no gap",
          any({ start: [], centre: [["dock", "tools", "voice"]], end: [] }, { dock: 200, tools: 0, voice: 40 },
              { pad: 4, inner: 2 }).at,
          { dock: 379, voice: 581 });
    check("rail: a group of nothing takes no gap",
          any({ start: [["clips"], ["power"], ["tools"]], centre: [], end: [] }, { clips: 60, power: 0, tools: 40 }).at,
          { clips: 0, tools: 80 });

    // ── Room: the dock's ceiling, at rest ─────────────────────────────────────
    check("room: alone, the span less both margins", rail(0, 1000, 50, 200, 0, 20, 0, 1000).room.dock, 900);
    check("room: between the clips and the stats", rail(0, 1000, 50, 200, 100, 20, 0, 1000, 60, 0).room.dock, 800);
    check("room: a panel passing over doesn't shrink it",
          rail(0, 1000, 50, 200, 100, 20, 700, 1000, 60, 0, true).room.dock, 800);
    check("room: never counts its own length",
          rail(0, 1000, 50, 900, 100, 20, 0, 1000, 60, 0).room.dock, 800);
    check("room: less the other centre groups",
          any({ start: [], centre: [["dock"], ["voice"]], end: [["stats"]] }, { dock: 200, voice: 60, stats: 100 }).room.dock,
          900 - 50 - 20 - 60 - 20);
    check("room: less the rest of its own group",
          any({ start: [], centre: [["dock", "tools"]], end: [] }, { dock: 200, tools: 40 },
              { pad: 4, inner: 2 }).room.dock,
          900 - (4 + 40 + 4) - 2);
    check("room: in the near corner, up to the centre and the far corner",
          any({ start: [["dock"]], centre: [["voice"]], end: [["stats"]] }, { dock: 300, voice: 60, stats: 100 }).room.dock,
          (1000 - 100 - 20) - 0 - (60 + 20));
    check("room: in the far corner, back to the centre and the near corner",
          any({ start: [["clips"]], centre: [], end: [["dock"]] }, { clips: 60, dock: 300 }).room.dock,
          1000 - (0 + 60 + 20));
    // ── sideGroups: big modules stand alone ───────────────────────────────────
    // The dock is the one big module; the stats and clips are buttons now.
    const big = id => id === "dock";
    check("groups: small ones keep their group",
          sideGroups({ start: [["tools", "power"]], centre: [], end: [] }, big),
          { start: [["tools", "power"]], centre: [], end: [] });
    check("groups: the stats and clips buttons group like the rest",
          sideGroups({ start: [["clips", "tools"]], centre: [], end: [["stats", "power"]] }, big),
          { start: [["clips", "tools"]], centre: [], end: [["stats", "power"]] });
    check("groups: a big one is split out, in order",
          sideGroups({ start: [["tools", "dock", "power"]], centre: [], end: [] }, big),
          { start: [["tools"], ["dock"], ["power"]], centre: [], end: [] });
    check("groups: the dock alone beside a button group",
          sideGroups({ start: [], centre: [["dock", "stats"]], end: [] }, big),
          { start: [], centre: [["dock"], ["stats"]], end: [] });

    // ── sideJoins: which pieces were one group (the dock grouped like any module) ──
    check("joins: aligned with sideGroups, first piece of each group not joined",
          sideJoins({ start: [["tools", "dock", "power"], ["clips"]], centre: [["dock", "stats"]], end: [["stats"]] }, big),
          { start: [false, true, true, false], centre: [false, true], end: [false] });
    check("joins: a group without the dock is one unjoined piece",
          sideJoins({ start: [["clips", "tools"]], centre: [], end: [] }, big),
          { start: [false], centre: [], end: [] });
    {
        const L = { start: [["clips", "dock", "power"]], centre: [], end: [] };
        const r = sideRail({ start: 0, end: 1000, margin: 50, gap: 20, near: 0, corner: 1000, avoid: 0, collapsed: false,
                             layout: sideGroups(L, big), joined: sideJoins(L, big),
                             lengths: { clips: 60, dock: 300, power: 40 } });
        check("rail: joined pieces butt together (no group gap)", r.at, { clips: 0, dock: 60, power: 360 });
        check("rail: pieces say which are joined", r.groups.map(g => !!g.joined), [false, true, true]);
        const e = sideRail({ start: 0, end: 1000, margin: 50, gap: 20, near: 0, corner: 1000, avoid: 0, collapsed: false,
                             layout: { start: [], centre: [], end: sideGroups({ end: [["dock", "power"]] }, big).end },
                             joined: { end: [false, true] }, lengths: { dock: 300, power: 40 } });
        check("rail: joined in the far corner too", e.at, { dock: 660, power: 960 });
        const c = sideRail({ start: 0, end: 1000, margin: 50, gap: 20, near: 0, corner: 1000, avoid: 0, collapsed: false,
                             layout: { start: [], centre: [["dock"], ["power"]], end: [] },
                             joined: { centre: [false, true] }, lengths: { dock: 300, power: 40 } });
        check("rail: joined in the centre: one block, centred", c.at, { dock: 330, power: 630 });
        const a = sideRail({ start: 0, end: 1000, margin: 50, gap: 20, near: 0, corner: 1000, avoid: 0, collapsed: false,
                             layout: { start: [["clips"], ["dock"], ["power"]], centre: [], end: [] },
                             joined: { start: [false, true, true] }, lengths: { clips: 60, dock: 0, power: 40 } });
        check("rail: a joined piece after an absent one takes the gap", a.at, { clips: 0, power: 80 });
    }
    check("groups: a missing region is empty", sideGroups({ centre: [["dock"]] }, big),
          { start: [], centre: [["dock"]], end: [] });

    // ── sideSurface: where the surface lies across the edge ───────────────────
    const surf = (anchored, welded, strip) => sideSurface({ depth: 68, strip, anchored, welded, inset: 4 });
    check("surface: welded starts at the edge, the strip inside it", surf(true, true, 12), { lo: 0, hi: 68, reserve: 68 });
    check("surface: flush stands on the strip", surf(true, false, 12), { lo: 12, hi: 80, reserve: 80 });
    check("surface: flush with no frame is at the edge", surf(true, false, 0), { lo: 0, hi: 68, reserve: 68 });
    check("surface: floating stands on the strip, an inset short of its reserve", surf(false, false, 12), { lo: 12, hi: 80, reserve: 84 });
    check("surface: floating off a bare edge by the inset", surf(false, false, 0), { lo: 4, hi: 72, reserve: 76 });

    const cards = [{ x: 10, y: 40, w: 500, h: 300 }, { x: 1400, y: 40, w: 500, h: 600 }, { x: 700, y: 40, w: 500, h: 0 }];
    check("avoid: the card over a left rail", railAvoid("left", 0, 80, cards, 16), 356);
    check("avoid: the card over a right rail", railAvoid("right", 1840, 1920, cards, 16), 656);
    check("avoid: a closed card never counts", railAvoid("left", 700, 800, cards, 16), 0);
    check("avoid: a bottom dock is never in the way", railAvoid("bottom", 0, 1920, cards, 16), 0);
}

// ── thumbAspect ──────────────────────────────────────────────────
{
    check("aspect: unknown size is 16:9", thumbAspect(0, 0), 16 / 9);
    check("aspect: a tall window is clamped", thumbAspect(500, 2000), 0.6);
    check("aspect: a very wide one too", thumbAspect(5000, 1000), 2.4);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
