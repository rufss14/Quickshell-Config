// ── test-layout.js ────────────────────────────────────────────────────────────
// Regression tests for config/layout.js, the bar layout algebra.
//
//     bun scripts/test-layout.js          (or: node scripts/test-layout.js)
//
// Safe to run: layout.js is pure functions over plain data and touches nothing —
// no files, no processes, no Quickshell.
//
// ── Why these tests exist ─────────────────────────────────────────────────────
// This logic used to live inside Config.qml, where the only way to exercise it was to
// start the shell and drag pills around. Two parts of it are subtle enough that eyeing
// the bar is not evidence:
//
//   reconcile()      "the user removed this" and "this didn't exist yet" look
//                    IDENTICAL in a saved layout. Getting it backwards either
//                    resurrects a module you deliberately took off the bar, or hides
//                    one that an upgrade added. Neither announces itself.
//   moveIntoGroup()  dragging a module rightwards WITHIN its own group has to adjust
//                    the target index, because extracting it first shifts everything
//                    after it down one. Off by one, silently, in one direction only.
//
// layout.js is loaded by stripping its `.pragma library` line (a QML directive that
// isn't valid JS) and evaluating the rest, so the tests run against the real file
// rather than a copy that can drift.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "config", "layout.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");

const L = new Function(src + `
    return { REGIONS, SIDE_REGIONS, defaultLayout, clone, prune, locate, extract,
             moveToOwnGroup, moveIntoGroup, removeModule, addModule,
             reconcile, canonical, unifiedLayout, dedupeAcross, presetMatches };`)();

// A small catalogue standing in for Config.moduleList. Only `id` and `home` matter.
const CAT = [
    { id: "clock",      home: "right"  },
    { id: "wifi",       home: "right"  },
    { id: "battery",    home: "right"  },
    { id: "volume",     home: "left"   },
    { id: "settings",   home: "left"   },
    { id: "workspaces", home: "centre" }
];

const eq = (a, b) => L.canonical(a) === L.canonical(b);

let pass = 0;
const failures = [];
function check(name, got, want) {
    if (eq(got, want)) { pass++; return; }
    failures.push(`  ${name}\n      want ${JSON.stringify(want)}\n      got  ${JSON.stringify(got)}`);
}

// ── The shape of things ───────────────────────────────────────────────────────
check("REGIONS is the bar order", L.REGIONS, ["left", "centre", "right"]);
check("defaultLayout has all three regions",
      Object.keys(L.defaultLayout()).sort(), ["centre", "left", "right"]);

// ── clone is DEEP ─────────────────────────────────────────────────────────────
// The whole model rests on this: a shallow copy would share the inner group arrays, so
// a splice would edit the live layout before the assignment ever happened.
{
    const orig = { left: [["a", "b"]], centre: [], right: [] };
    const copy = L.clone(orig);
    copy.left[0].push("c");
    check("clone does not alias inner groups", orig.left[0], ["a", "b"]);
    check("clone carries the contents", L.clone(orig), orig);
}

// ── prune ─────────────────────────────────────────────────────────────────────
check("prune drops emptied groups",
      L.prune({ left: [["a"], [], ["b"]], centre: [[]], right: [] }),
      { left: [["a"], ["b"]], centre: [], right: [] });

// ── locate ────────────────────────────────────────────────────────────────────
{
    const l = { left: [["a", "b"], ["c"]], centre: [], right: [["d"]] };
    check("locate finds first group",  L.locate(l, "b"), { region: "left",  group: 0, index: 1 });
    check("locate finds later region", L.locate(l, "d"), { region: "right", group: 0, index: 0 });
    check("locate returns null when absent", L.locate(l, "zz"), null);
}

// ── extract ───────────────────────────────────────────────────────────────────
{
    const l = { left: [["a", "b"]], centre: [], right: [] };
    L.extract(l, "a");
    check("extract removes in place", l, { left: [["b"]], centre: [], right: [] });
    L.extract(l, "nope");
    check("extract of an absent id is a no-op", l, { left: [["b"]], centre: [], right: [] });
}

// ── moveToOwnGroup ────────────────────────────────────────────────────────────
{
    const l = { left: [["a", "b"], ["c"]], centre: [], right: [] };
    check("moveToOwnGroup splits a module out at the index",
          L.moveToOwnGroup(l, "b", "left", 0),
          { left: [["b"], ["a"], ["c"]], centre: [], right: [] });
    check("moveToOwnGroup clamps past the end",
          L.moveToOwnGroup(l, "a", "left", 99),
          { left: [["b"], ["c"], ["a"]], centre: [], right: [] });
    check("moveToOwnGroup moves across regions",
          L.moveToOwnGroup(l, "a", "right", 0),
          { left: [["b"], ["c"]], centre: [], right: [["a"]] });
    check("moveToOwnGroup left the input alone", l,
          { left: [["a", "b"], ["c"]], centre: [], right: [] });
    // Gaps are named in the layout as it was. A lone module's own group goes away
    // when it's lifted out, so the gaps after it move down one.
    const lone = { left: [["a"], ["b"], ["c"]], centre: [], right: [] };
    check("moveToOwnGroup: into the gap right after its own group is a no-op",
          L.moveToOwnGroup(lone, "a", "left", 1), lone);
    check("moveToOwnGroup: into the gap right before its own group is a no-op",
          L.moveToOwnGroup(lone, "b", "left", 1), lone);
    check("moveToOwnGroup: a lone module moved one gap on",
          L.moveToOwnGroup(lone, "a", "left", 2),
          { left: [["b"], ["a"], ["c"]], centre: [], right: [] });
    check("moveToOwnGroup: a lone module to the end",
          L.moveToOwnGroup(lone, "a", "left", 3),
          { left: [["b"], ["c"], ["a"]], centre: [], right: [] });
    check("moveToOwnGroup: a lone module back to the front",
          L.moveToOwnGroup(lone, "c", "left", 0),
          { left: [["c"], ["a"], ["b"]], centre: [], right: [] });
    check("moveToOwnGroup: out of a shared group leaves the gaps where they were",
          L.moveToOwnGroup({ left: [["a", "b"], ["c"]], centre: [], right: [] }, "a", "left", 1),
          { left: [["b"], ["a"], ["c"]], centre: [], right: [] });
}

// ── moveIntoGroup — the index adjustment ──────────────────────────────────────
// The trap: extracting the module first shifts everything after it down one, so a
// target index captured BEFORE the extract is one too far right — but only when the
// module is moving rightwards within the group it already occupies.
{
    const l = { left: [["a", "b", "c"]], centre: [], right: [] };

    check("same group, moving RIGHT — index adjusted",
          L.moveIntoGroup(l, "a", "left", 0, 2),
          { left: [["b", "a", "c"]], centre: [], right: [] });

    check("same group, moving LEFT — index NOT adjusted",
          L.moveIntoGroup(l, "c", "left", 0, 0),
          { left: [["c", "a", "b"]], centre: [], right: [] });

    check("same group, to the very end",
          L.moveIntoGroup(l, "a", "left", 0, 3),
          { left: [["b", "c", "a"]], centre: [], right: [] });
}
{
    // Coming from a DIFFERENT group, no adjustment applies.
    const l = { left: [["a", "b"], ["c"]], centre: [], right: [] };
    check("different group — index used as given",
          L.moveIntoGroup(l, "c", "left", 0, 1),
          { left: [["a", "c", "b"]], centre: [], right: [] });
}
{
    // Emptying the source group must not renumber the target before we find it.
    const l = { left: [["solo"], ["x", "y"]], centre: [], right: [] };
    check("source group emptied, target still resolves",
          L.moveIntoGroup(l, "solo", "left", 1, 1),
          { left: [["x", "solo", "y"]], centre: [], right: [] });
}
{
    // A target group that doesn't exist must prune and bail, not throw.
    const l = { left: [["a"]], centre: [], right: [] };
    check("missing target group prunes instead of throwing",
          L.moveIntoGroup(l, "a", "left", 9, 0),
          { left: [], centre: [], right: [] });
}

// ── removeModule ──────────────────────────────────────────────────────────────
check("removeModule drops the module and its emptied group",
      L.removeModule({ left: [["a"], ["b"]], centre: [], right: [] }, "a"),
      { left: [["b"]], centre: [], right: [] });

// ── addModule ─────────────────────────────────────────────────────────────────
{
    const l = { left: [["volume"]], centre: [], right: [] };
    check("addModule appends to the module's home region as its own group",
          L.addModule(l, "clock", CAT),
          { left: [["volume"]], centre: [], right: [["clock"]] });
    check("addModule refuses one already placed", L.addModule(l, "volume", CAT), null);
    check("addModule refuses an unknown id",      L.addModule(l, "nope",   CAT), null);
}

// ── reconcile — the rule that cannot be eyeballed ─────────────────────────────
{
    const saved = { left: [["volume"]], centre: [["workspaces"]], right: [["clock"]] };

    // Everything known and present: unchanged, and nothing appended.
    check("reconcile passes a current layout through",
          L.reconcile(saved, CAT.map(m => m.id), CAT), saved);

    // A module in the layout that the catalogue no longer has must go.
    check("reconcile drops a module that no longer exists",
          L.reconcile({ left: [["volume", "ghost"]], centre: [], right: [] },
                      CAT.map(m => m.id), CAT),
          { left: [["volume"]], centre: [], right: [] });

    // Listed twice — building it twice means two of whatever process sits behind it.
    check("reconcile drops duplicates",
          L.reconcile({ left: [["volume"], ["volume"]], centre: [], right: [] },
                      CAT.map(m => m.id), CAT),
          { left: [["volume"]], centre: [], right: [] });

    // ── The two that look identical from the layout alone ─────────────────────
    // `battery` is absent. priorKnown says the catalogue ALREADY had it last write, so
    // its absence is a deliberate removal: it stays off.
    check("absent + known before  = user removed it, stays gone",
          L.reconcile(saved, CAT.map(m => m.id), CAT), saved);

    // Same layout, but priorKnown predates `battery` — so it is genuinely new and gets
    // appended to its home region.
    check("absent + unknown before = new module, gets appended",
          L.reconcile(saved, ["clock", "wifi", "volume", "settings", "workspaces"], CAT),
          { left: [["volume"]], centre: [["workspaces"]], right: [["clock"], ["battery"]] });

    // An empty priorKnown is a config written before the marker existed. Absences are
    // treated as deliberate rather than re-adding everything the user took off.
    check("empty priorKnown treats absences as deliberate",
          L.reconcile(saved, [], CAT), saved);
    check("missing priorKnown behaves the same",
          L.reconcile(saved, undefined, CAT), saved);

    // A layout with a region missing entirely must not throw.
    check("reconcile tolerates a missing region",
          L.reconcile({ left: [["volume"]] }, [], CAT),
          { left: [["volume"]], centre: [], right: [] });

    // config.json is hand-editable: a region or group of the wrong type is dropped,
    // not thrown on (a string region used to hit `.map` and take the load down).
    check("reconcile drops a region that isn't a list",
          L.reconcile({ left: "volume", centre: [["workspaces"]], right: {} }, [], CAT),
          { left: [], centre: [["workspaces"]], right: [] });
    check("reconcile drops a group that isn't a list",
          L.reconcile({ left: ["volume", ["settings"]], centre: [], right: [] }, [], CAT),
          { left: [["settings"]], centre: [], right: [] });
}

// ── The sidebar: the same algebra over its own regions ────────────────────────
// Config.sidebarLayout never tops a saved layout up (a sidebar module is opt-in, so
// one an upgrade adds waits in the pool): it reconciles with an empty priorKnown.
{
    const SIDE = L.SIDE_REGIONS;
    const SCAT = [{ id: "clips", home: "start" }, { id: "dock", home: "centre" },
                  { id: "stats", home: "end" }];
    check("SIDE_REGIONS runs along the edge", SIDE, ["start", "centre", "end"]);
    check("sidebar: an empty priorKnown adds nothing new",
          L.reconcile({ start: [], centre: [["dock"]], end: [] }, [], SCAT, SIDE),
          { start: [], centre: [["dock"]], end: [] });
    check("sidebar: a bar region name is not a sidebar region",
          L.reconcile({ left: [["dock"]], centre: [["stats"]] }, [], SCAT, SIDE),
          { start: [], centre: [["stats"]], end: [] });
    check("sidebar: addModule goes to its home region",
          L.addModule({ start: [], centre: [["dock"]], end: [] }, "stats", SCAT, SIDE),
          { start: [], centre: [["dock"]], end: [["stats"]] });
    const small = id => id !== "dock";
    check("sidebar: a small module joins the region's last small group",
          L.addModule({ start: [], centre: [["dock"]], end: [["clips"]] }, "stats", SCAT, SIDE, small),
          { start: [], centre: [["dock"]], end: [["clips", "stats"]] });
    check("sidebar: never joins a group the dock is in",
          L.addModule({ start: [], centre: [], end: [["dock"]] }, "stats", SCAT, SIDE, small),
          { start: [], centre: [], end: [["dock"], ["stats"]] });
    check("sidebar: an empty region starts a group",
          L.addModule({ start: [], centre: [["dock"]], end: [] }, "stats", SCAT, SIDE, small),
          { start: [], centre: [["dock"]], end: [["stats"]] });
    check("sidebar: moving between regions keeps the other regions",
          L.moveToOwnGroup({ start: [["clips"]], centre: [["dock"]], end: [["stats"]] },
                           "clips", "end", 0, SIDE),
          { start: [], centre: [["dock"]], end: [["clips"], ["stats"]] });
}

// ── unifiedLayout: every stored shape lands on a unified one ──────────────────
check("shape: unified stays", L.unifiedLayout("unified"), "unified");
check("shape: on-frame stays", L.unifiedLayout("unifiedAnchored"), "unifiedAnchored");
check("shape: floating pills → floating bar", L.unifiedLayout("pills"), "unified");
check("shape: pills on frame → bar on frame", L.unifiedLayout("pillsAnchored"), "unifiedAnchored");
check("shape: none, welded frameMerge → on frame", L.unifiedLayout(undefined, true), "unifiedAnchored");
check("shape: none, frameMerge off → floating", L.unifiedLayout(undefined, false), "unified");
check("shape: garbage → the default", L.unifiedLayout("banana"), "unifiedAnchored");

// ── canonical ─────────────────────────────────────────────────────────────────
// The point is key ORDER independence: a hand-edited presets/bar.json must still match
// a byte-identical preset built by _snapshot().
check("canonical is key-order independent",
      L.canonical({ a: 1, b: 2 }), L.canonical({ b: 2, a: 1 }));
check("canonical is key-order independent at depth",
      L.canonical({ o: { x: 1, y: [{ p: 1, q: 2 }] } }),
      L.canonical({ o: { y: [{ q: 2, p: 1 }], x: 1 } }));
check("canonical still distinguishes different data",
      L.canonical({ a: 1 }) !== L.canonical({ a: 2 }), true);
check("canonical keeps ARRAY order significant",
      L.canonical([1, 2]) !== L.canonical([2, 1]), true);

// ── Both surfaces: one place per module ───────────────────────────────────────
{
    const bar  = { left: [["volume"]], centre: [["workspaces"]], right: [["clock"]] };
    const side = { start: [["clock", "timer"]], centre: [["dock"]], end: [["volume"]] };
    check("dedupeAcross: the bar's copy wins, emptied groups pruned",
          L.dedupeAcross(bar, side), { start: [["timer"]], centre: [["dock"]], end: [] });
    const clean = { start: [["timer"]], centre: [["dock"]], end: [] };
    check("dedupeAcross: nothing shared hands back the SAME object (no change signal)",
          L.dedupeAcross(bar, clean) === clean, true);
    check("dedupeAcross: input untouched", side.start, [["clock", "timer"]]);
}

// ── Presets: keys added after presets existed are optional ────────────────────
{
    const snap = { barRoundness: 17, layout: { left: [] }, barHero: "clock",
                   sidebarHero: "claude", sidebarLayout: { start: [] } };
    const OPT = ["barHero", "sidebarHero", "sidebarLayout"];
    check("presetMatches: an old preset without the new keys still matches",
          L.presetMatches({ layout: { left: [] }, barRoundness: 17 }, snap, OPT), true);
    check("presetMatches: a new preset is compared on them",
          L.presetMatches({ barRoundness: 17, layout: { left: [] }, barHero: "visualizer",
                            sidebarHero: "claude", sidebarLayout: { start: [] } }, snap, OPT), false);
    check("presetMatches: a non-optional key still has to be there",
          L.presetMatches({ layout: { left: [] }, barHero: "clock" }, snap, OPT), false);
}

// ── A module that only gains a bar form is not appended to the bar ────────────
// Config._barKnown adds every sidebar id to priorKnown, so the dock and Now playing
// getting bar forms (2026-11-08) don't land on BOTH surfaces after an upgrade.
{
    const CAT2 = CAT.concat([{ id: "dock", home: "centre" }, { id: "nowplaying", home: "right" }]);
    const saved = { left: [["volume"]], centre: [["workspaces"]], right: [["clock"]] };
    const known = ["volume", "workspaces", "clock", "wifi", "settings"].concat(["dock", "nowplaying"]);
    const got = L.reconcile(saved, known, CAT2);
    check("gaining a bar form: dock not appended", L.locate(got, "dock"), null);
    check("gaining a bar form: nowplaying not appended", L.locate(got, "nowplaying"), null);
}
check("defaultLayout names no dead id", L.locate(L.defaultLayout(), "controlcenter"), null);

const total = pass + failures.length;
console.log(`${pass}/${total} passed`);
if (failures.length > 0) {
    console.log("\nFAILED:");
    console.log(failures.join("\n"));
    process.exit(1);
}
