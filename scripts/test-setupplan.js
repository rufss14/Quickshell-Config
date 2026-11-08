// ── test-setupplan.js ─────────────────────────────────────────────────────────
// services/setupplan.js — the setup steps, the plan for a selection, what a failure means.
//
//     bun scripts/test-setupplan.js          (or: node scripts/test-setupplan.js)
//
// Safe: pure functions. Loaded by stripping the `.pragma library` line, as test-clips.js does.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "setupplan.js"), "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "");
const P = new Function(src + "\nreturn { parseScan, compat, blockers, hyprMode, catalogue, defaultSelection, buildPlan, etaText, explainFailure, formatReport, health, touchesFor, ORDER, TESTED };")();

let pass = 0, fail = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) pass++;
    else { fail++; console.log(`  FAIL  ${name}\n          got  ${g}\n          want ${w}`); }
}

// A fresh machine: nothing in, but a working Arch with a network.
const fresh = () => ({
    arch: true, network: true, pacmanLock: false, pacmanRunning: false, diskMiB: 50000, sudo: true, polkitAgent: false,
    quickshell: "0.3.2", hyprland: "0.56.2", qt: "6.11.1", gpu: "AMD", vulkan: ["vulkan-radeon"], nvidiaProprietary: false,
    aurHelper: "none", coreMissing: 40, pywal: false, blobInstalled: false, morph: false,
    hyprConfig: "absent", autostart: false, bindCount: 0,
    themes: { gtk: { state: "todo", sudo: true, detail: "" }, qt: { state: "todo", sudo: false, detail: "" },
              discord: { state: "absent", sudo: false, detail: "" }, spotify: { state: "absent", sudo: false, detail: "" },
              steam: { state: "absent", sudo: false, detail: "" } },
    palette: false, optional: {}, packs: {},
    packPkgs: { clips: "gpu-screen-recorder ffmpeg qt6-multimedia qt6-multimedia-ffmpeg", gamemode: "gamemode mangohud",
                blob: "cmake qt6-shadertools", ddc: "ddcutil", beatsync: "python-numpy", discordkeys: "xdotool wtype" }
});
// Everything done.
const full = () => ({
    ...fresh(), aurHelper: "paru", coreMissing: 0, pywal: true, blobInstalled: true, morph: true, hyprConfig: "bundled",
    autostart: true, bindCount: 12, palette: true,
    themes: { gtk: { state: "ready", sudo: false, detail: "" }, qt: { state: "ready", sudo: false, detail: "" } },
    optional: { wpe: true, argos: true, songrec: true, spicetify: true, bridge: true, awww: true },
    packs: { clips: true, gamemode: true, blob: true, ddc: true, beatsync: true, discordkeys: true }
});
const ids = steps => steps.map(s => s.id);

// ── the scan ──
const scan = parseScan => parseScan(["arch=1", "network=1", "pacmanLock=0", "diskMiB=48210", "sudo=1", "polkitAgent=1",
    "quickshell=0.3.2", "hyprland=0.56.2", "qt=6.12.0", "gpu=AMD", "vulkan=vulkan-radeon", "aurHelper=paru",
    "blobInstalled=1", "distro=arch", "evil=1", "gpu=Matrox"].join("\n"));
const s1 = scan(P.parseScan);
check("scan: booleans", [s1.arch, s1.pacmanLock, s1.sudo, s1.polkitAgent, s1.blobInstalled], [true, false, true, true, true]);
check("scan: numbers and strings", [s1.diskMiB, s1.quickshell, s1.hyprland, s1.qt, s1.aurHelper, s1.distro], [48210, "0.3.2", "0.56.2", "6.12.0", "paru", "arch"]);
check("scan: a later bad gpu value is dropped, not trusted", s1.gpu, "");
check("scan: vulkan packages", s1.vulkan, ["vulkan-radeon"]);
check("scan: network unknown stays null", P.parseScan("arch=1").network, null);
check("scan: network false", P.parseScan("network=0").network, false);
check("scan: an unknown key is ignored", "evil" in s1, false);
check("scan: garbage is a default scan", P.parseScan(null).aurHelper, "none");
check("scan: a package name with shell metacharacters is dropped", P.parseScan("vulkan=vulkan-radeon;$(id) vulkan-intel").vulkan, ["vulkan-intel"]);
check("scan: so is anything starting with a dash", P.parseScan("vulkan=-rf vulkan-intel").vulkan, ["vulkan-intel"]);
check("scan: version with junk is dropped", P.parseScan("qt=6.1$(id)").qt, "");
check("scan: an unknown helper is none", P.parseScan("aurHelper=rm").aurHelper, "none");

// ── compatibility ──
check("compat: the tested versions", P.compat({ quickshell: "0.3.2", hyprland: "0.56.2", qt: "6.11.1" }).map(r => r.state), ["ok", "ok", "ok"]);
check("compat: a newer Qt warns, never stops", P.compat({ quickshell: "0.3.2", hyprland: "0.56.2", qt: "6.12.0" }).map(r => r.state), ["ok", "ok", "warn"]);
check("compat: not found is unknown", P.compat({}).map(r => r.state), ["unknown", "unknown", "unknown"]);
check("compat: says what was tested", P.compat({ qt: "6.12.0" })[2].want, "6.11.x");

// ── blockers ──
check("blockers: a healthy machine has none", P.blockers(fresh()), []);
check("blockers: not Arch", P.blockers({ ...fresh(), arch: false }).map(b => [b.id, b.level]), [["arch", "fatal"]]);
check("blockers: a pacman lock", P.blockers({ ...fresh(), pacmanLock: true }).map(b => b.id), ["lock"]);
check("blockers: pacman running", P.blockers({ ...fresh(), pacmanRunning: true }).map(b => b.id), ["running"]);
check("blockers: a lock is not also 'running'", P.blockers({ ...fresh(), pacmanLock: true, pacmanRunning: true }).map(b => b.id), ["lock"]);
check("blockers: no network", P.blockers({ ...fresh(), network: false }).map(b => b.id), ["network"]);
check("blockers: network unknown is not a blocker", P.blockers({ ...fresh(), network: null }), []);
check("blockers: little disk is fatal", P.blockers({ ...fresh(), diskMiB: 900 })[0].level, "fatal");
check("blockers: tight disk only warns", P.blockers({ ...fresh(), diskMiB: 3000 })[0].level, "warn");
check("blockers: unknown disk says nothing", P.blockers({ ...fresh(), diskMiB: 0 }), []);

// ── hyprland ──
check("hypr: no config → the bundle", P.hyprMode("absent"), "full");
check("hypr: your own config → leave it alone", P.hyprMode("other"), "minimal");
check("hypr: already the bundle → stays on it", P.hyprMode("bundled"), "full");
check("hypr: already minimal → stays", P.hyprMode("minimal"), "minimal");

// ── the catalogue ──
const cf = P.catalogue(fresh());
check("catalogue: in running order", ids(cf), ["core", "aurhelper", "aur", "clips", "gamemode", "blob", "hypr", "autostart", "themes", "colours", "spotify", "wpe", "argos", "songrec", "awww", "ddc", "beatsync", "discordkeys"]);
check("catalogue: a fresh machine needs everything essential", cf.filter(s => ["core", "aurhelper", "aur", "clips", "gamemode", "blob", "hypr", "autostart", "themes", "colours"].includes(s.id)).every(s => s.state === "todo"), true);
check("catalogue: the AUR helper step is there only without one", ids(P.catalogue({ ...fresh(), aurHelper: "yay" })).includes("aurhelper"), false);
check("catalogue: the helper is not recommended when pywal is already in", P.catalogue({ ...fresh(), pywal: true }).find(s => s.id === "aurhelper").recommended, false);
check("catalogue: default selection is the recommended todo ones", P.defaultSelection(cf), ["core", "aurhelper", "aur", "clips", "gamemode", "blob", "hypr", "autostart", "themes", "colours"]);
check("catalogue: extras are never ticked", P.defaultSelection(cf).some(id => ["spotify", "wpe", "argos", "songrec", "awww", "ddc", "beatsync", "discordkeys"].includes(id)), false);
check("packs: a pack step runs its pack job", ["clips", "gamemode", "ddc", "beatsync", "discordkeys"].map(id => cf.find(s => s.id === id).jobs), [["pack-clips"], ["pack-gamemode"], ["pack-ddc"], ["pack-beatsync"], ["pack-discordkeys"]]);
check("packs: the blob step installs its toolchain, then builds", cf.find(s => s.id === "blob").jobs, ["pack-blob", "blob"]);
check("packs: an installed pack is done", P.catalogue({ ...fresh(), packs: { clips: true } }).find(s => s.id === "clips").state, "done");
check("packs: a pack only partly installed is still to do", P.catalogue({ ...fresh(), packs: { clips: false } }).find(s => s.id === "clips").state, "todo");
check("packs: a pacman lock blocks a pack, with a reason", (c => [c.state, c.why !== ""])(P.catalogue({ ...fresh(), pacmanLock: true }).find(s => s.id === "gamemode")), ["blocked", true]);
check("packs: every pack step needs root", cf.filter(s => /^pack-/.test(s.jobs[0])).every(s => s.root), true);
check("packs: no pack step needs the AUR helper", P.buildPlan(P.catalogue({ ...fresh(), coreMissing: 0 }), ["clips", "ddc"]).run.map(s => s.id), ["clips", "ddc"]);
check("catalogue: apps that are not installed are not a to-do", cf.find(s => s.id === "themes").detail.includes("Discord"), false);
check("catalogue: themes step needs root when a todo app does", cf.find(s => s.id === "themes").root, true);
check("catalogue: …and not when none does", P.catalogue({ ...fresh(), themes: { qt: { state: "todo", sudo: false, detail: "" } } }).find(s => s.id === "themes").root, false);
const cfull = P.catalogue(full());
check("catalogue: a finished machine is all done", cfull.every(s => s.state === "done"), true);
check("catalogue: …and nothing is ticked", P.defaultSelection(cfull), []);
check("catalogue: a plugin that is installed but won't load is a rebuild", (c => [c.state, c.verb, c.detail.includes("rebuild")])(P.catalogue({ ...fresh(), blobInstalled: true }).find(s => s.id === "blob")), ["todo", "Rebuild", true]);
check("catalogue: your own hypr config gets the minimal job", P.catalogue({ ...fresh(), hyprConfig: "other" }).find(s => s.id === "hypr").jobs, ["hyprMin"]);
check("catalogue: no hypr config gets the bundle", cf.find(s => s.id === "hypr").jobs, ["hypr"]);
check("catalogue: the minimal one is done only when minimal is in place", P.catalogue({ ...fresh(), hyprConfig: "other" }, "minimal").find(s => s.id === "hypr").state, "todo");
check("catalogue: the bundle is not 'done' by a minimal file", P.catalogue({ ...fresh(), hyprConfig: "minimal" }, "full").find(s => s.id === "hypr").state, "todo");
check("catalogue: a pacman lock blocks the package steps, with a reason", (c => [c.state, c.why !== ""])(P.catalogue({ ...fresh(), pacmanLock: true }).find(s => s.id === "core")), ["blocked", true]);
check("catalogue: …but not the ones that install nothing", P.catalogue({ ...fresh(), pacmanLock: true }).find(s => s.id === "autostart").state, "todo");
check("catalogue: a step already done is never blocked", P.catalogue({ ...full(), pacmanLock: true }).every(s => s.state === "done"), true);
check("catalogue: every step names jobs", cf.every(s => s.jobs.length > 0), true);
check("catalogue: the eta of the core step grows with what's missing", P.catalogue({ ...fresh(), coreMissing: 100 }).find(s => s.id === "core").eta > cf.find(s => s.id === "core").eta, true);

// ── a plan ──
const plan = P.buildPlan(cf, P.defaultSelection(cf));
check("plan: the recommended set, in order", ids(plan.run), ["core", "aurhelper", "aur", "clips", "gamemode", "blob", "hypr", "autostart", "themes", "colours"]);
check("plan: it needs root", plan.root, true);
check("plan: it has a size and a time", [plan.count, plan.eta > 0], [10, true]);
const onlyAur = P.buildPlan(cf, ["aur"]);
check("plan: choosing the AUR step pulls in the helper and the base tools", ids(onlyAur.run), ["core", "aurhelper", "aur"]);
check("plan: …and says they came on their own", onlyAur.run.map(s => s.auto), [true, true, false]);
check("plan: an extra pulls in the helper", ids(P.buildPlan(cf, ["wpe"]).run), ["core", "aurhelper", "wpe"]);
check("plan: with a helper already, an extra pulls in nothing", ids(P.buildPlan(P.catalogue({ ...fresh(), aurHelper: "paru", coreMissing: 0 }), ["wpe"]).run), ["wpe"]);
check("plan: spotify needs no root", P.buildPlan(P.catalogue({ ...fresh(), aurHelper: "paru", coreMissing: 0 }), ["spotify"]).root, false);
check("plan: a plan of unprivileged steps needs no password", P.buildPlan(cf, ["autostart", "hypr"]).root, false);
check("plan: a finished machine has nothing to run", P.buildPlan(cfull, P.defaultSelection(cfull)).count, 0);
check("plan: redoing a done step is allowed (Custom)", P.buildPlan(cfull, ["blob"]).run.map(s => [s.id, s.redo]), [["blob", true]]);
check("plan: an unknown id is ignored", P.buildPlan(cf, ["nope"]).count, 0);
check("plan: duplicates run once", ids(P.buildPlan(cf, ["aur", "aur", "core"]).run), ["core", "aurhelper", "aur"]);
const locked = P.buildPlan(P.catalogue({ ...fresh(), pacmanLock: true }), ["core", "aur", "autostart"]);
check("plan: a blocked step is left out", ids(locked.run), ["autostart"]);
check("plan: …and what is blocked is said", locked.blocked.map(b => b.id).sort(), ["aur", "core"]);
// A step that is not blocked itself but NEEDS a blocked one goes with it, and says why.
const needy = P.buildPlan(P.catalogue({ ...fresh(), pacmanLock: true }), ["colours"]);
check("plan: a dependent of a blocked step does not run", needy.run.length, 0);
check("plan: …and is reported with the reason", needy.blocked.filter(b => b.id === "colours").map(b => b.why.startsWith("Needs Theming tools")), [true]);
check("plan: …with a reason", locked.blocked.every(b => b.why.length > 0), true);
check("plan: selecting nothing is nothing", P.buildPlan(cf, []).count, 0);
check("plan: garbage", P.buildPlan(cf, null).count, 0);

// ── time ──
check("eta: seconds", P.etaText(20), "under a minute");
check("eta: minutes", P.etaText(380), "about 6 min");
check("eta: an hour", P.etaText(3900), "about 1 h 5 min");
check("eta: junk", P.etaText("x"), "under a minute");

// ── what went wrong ──
const why = (t) => P.explainFailure("core", t.split("\n"));
check("why: a lock", why("error: failed to init transaction (unable to lock database)").title, "pacman is busy");
check("why: a lock is not worth retrying", why("unable to lock database").retry, false);
check("why: a 404 is the mirrors", why("error: failed retrieving file 'x.pkg.tar.zst' from mirror.example : The requested URL returned error: 404").title, "Your mirrors are out of sync");
check("why: DNS is the network", why("curl: (6) Could not resolve host: archlinux.org").title, "Couldn't download");
check("why: the network is worth retrying", why("Could not resolve host").retry, true);
check("why: a signature", why("error: x: signature from \"A\" is unknown trust").title, "A package signature didn't verify");
check("why: a full disk", why("error: write failed: No space left on device").title, "The disk is full");
check("why: a conflict", why("error: failed to commit transaction (conflicting files)").title, "A file is in the way");
check("why: a missing package", why("error: target not found: nonsense").title, "A package isn't available");
check("why: a wrong password", why("sudo: 1 incorrect password attempt").title, "The password wasn't accepted");
check("why: a wrong password can be retried", why("sorry, try again").retry, true);
check("why: a dismissed polkit dialog", why("Error executing command as another user: Not authorized\nThis incident has been reported. polkit request dismissed").title, "The authentication dialog was dismissed");
check("why: a failed compile", why("CMake Error at CMakeLists.txt:12 (find_package)").title, "The plugin didn't build");
check("why: an AUR build", why("==> ERROR: A failure occurred in build().\n  Aborting...\nerror: failed to build 'x'").title, "An AUR package didn't build");
check("why: nothing recognised is null", why("something odd happened"), null);
check("why: log lines as objects", P.explainFailure("core", [{ text: "unable to lock database", err: true }]).title, "pacman is busy");
check("why: empty", P.explainFailure("core", []), null);
check("why: garbage", P.explainFailure("core", null), null);

// ── what a step will do ──
{
    const all = P.catalogue(fresh());
    check("touches: every step says what it does", all.filter(st => !st.touches || st.touches.length === 0).map(st => st.id), []);
    check("touches: core names the GPU's driver", P.catalogue(fresh()).find(st => st.id === "core").touches.some(t => t.t.includes("vulkan-radeon")), true);
    check("touches: no GPU says software", P.catalogue({ ...fresh(), vulkan: [], gpu: "" }).find(st => st.id === "core").touches.some(t => /software/i.test(t.t)), true);
    check("touches: the AUR step names the helper in use", P.catalogue({ ...fresh(), aurHelper: "yay" }).find(st => st.id === "aur").touches[0].t, "yay -S --needed quickshell python-pywal16");
    check("touches: no helper yet → paru", P.catalogue(fresh()).find(st => st.id === "aur").touches[0].t.startsWith("paru -S"), true);
    check("touches: full Hyprland says it backs up first", P.catalogue(fresh(), "full").find(st => st.id === "hypr").touches.some(t => /bak/.test(t.t)), true);
    check("touches: minimal says it does not edit hyprland.lua", P.catalogue(fresh(), "minimal").find(st => st.id === "hypr").touches.some(t => /NOT edited/.test(t.t)), true);
    check("touches: themes lists only the apps still to do", P.catalogue(fresh()).find(st => st.id === "themes").touches.filter(t => t.k === "file").length, 2);
    check("touches: themes with nothing to do lists no files", P.catalogue(full()).find(st => st.id === "themes").touches.filter(t => t.k === "file").length, 0);
    check("touches: unknown id", P.touchesFor("nope", fresh(), "full"), []);
    check("touches: a pack names its packages, from the probe", P.catalogue(fresh()).find(st => st.id === "ddc").touches[1].t, "pacman -S --needed ddcutil");
    check("touches: a pack with no names yet still says something", P.touchesFor("clips", { ...fresh(), packPkgs: {} }, "full")[1].t.startsWith("pacman -S --needed"), true);
    check("touches: the blob step names its toolchain first", P.catalogue(fresh()).find(st => st.id === "blob").touches[1].t, "pacman -S --needed cmake qt6-shadertools");
}

// ── the report ──
{
    const run = { items: [
        { id: "core", title: "System packages", state: "ok", startedAt: 1000, endedAt: 13000, log: [] },
        { id: "aur", title: "Theming tools", state: "failed", startedAt: 13000, endedAt: 20000, explain: { title: "pacman is busy", text: "Close it." },
          log: [{ text: "error: failed to lock /home/alice/.cache/x" }, { text: "unable to lock database", err: true }] },
        { id: "colours", title: "Colours from your wallpaper", state: "skipped", why: "Needs Theming tools, which didn't finish" }
    ] };
    const r = P.formatReport(fresh(), run, { home: "/home/alice", now: 1000000000000, polkit: true });
    check("report: header", r.startsWith("Quicktest setup report\nGenerated: 2001-09-09T01:46:40.000Z"), true);
    check("report: machine line", r.includes("Quickshell 0.3.2   Hyprland 0.56.2   Qt 6.11.1"), true);
    check("report: gpu", r.includes("gpu: AMD (vulkan-radeon)"), true);
    check("report: step marks", [r.includes("[ok] System packages  (12 s)"), r.includes("[FAILED] Theming tools  (7 s)"), r.includes("[skipped] Colours from your wallpaper")], [true, true, true]);
    check("report: the failure's meaning", r.includes("pacman is busy — Close it."), true);
    check("report: its output is quoted", r.includes("unable to lock database"), true);
    check("report: the home directory is scrubbed", [r.includes("/home/alice"), r.includes("~/.cache/x")], [false, true]);
    check("report: polkit noted", r.includes("root through polkit"), true);
    check("report: skipped says why", r.includes("Needs Theming tools, which didn't finish"), true);
    check("report: no run", P.formatReport(fresh(), null, {}).includes("nothing ran"), true);
    check("report: only the last 12 lines of a failure", (P.formatReport(fresh(), { items: [{ id: "x", title: "X", state: "failed",
        log: Array.from({ length: 30 }, (_, i) => ({ text: "line " + i })) }] }, {}).match(/line \d+/g) || []).length, 12);
}

// ── health ──
{
    const ok = { ...full() };
    check("health: a healthy machine has nothing to say", P.health(ok, { rivalNotifiers: [], rivalBars: [], rivalAgents: [], barBlur: "on", barOpacity: 0.8 }), []);
    const h = (f, x) => P.health(f, x || {}).map(i => i.id);
    check("health: a plugin that is there but not loading", h({ ...ok, morph: false }), ["morph"]);
    check("health: no autostart on a machine with a config", h({ ...ok, autostart: false }), ["autostart"]);
    check("health: no autostart without any config isn't drift", h({ ...ok, hyprConfig: "absent", autostart: false, bindCount: 0 }), []);
    check("health: no binds", h({ ...ok, bindCount: 0 }), ["binds"]);
    check("health: another notification daemon is the most urgent", h({ ...ok, autostart: false }, { rivalNotifiers: ["mako"] }), ["notifier", "autostart"]);
    check("health: missing core packages are bad", P.health({ ...ok, coreMissing: 3 }, {})[0].level, "bad");
    check("health: pywal missing", h({ ...ok, pywal: false }), ["pywal"]);
    check("health: no palette (pywal present)", h({ ...ok, palette: false }), ["palette"]);
    check("health: two password agents only when ours is on", [h(ok, { polkitConfig: true, rivalAgents: ["hyprpolkitagent"] }), h(ok, { polkitConfig: false, rivalAgents: ["hyprpolkitagent"] })], [["agents"], []]);
    check("health: translucent bar with no blur", h(ok, { barBlur: "off", barOpacity: 0.7 }), ["blur"]);
    check("health: an opaque bar needs no blur", h(ok, { barBlur: "off", barOpacity: 1 }), []);
    check("health: an untested version is info only", P.health({ ...ok, hyprland: "0.99.0" }, {}).map(i => i.level), ["info"]);
    check("health: a finding that needs a command has no page", P.health(ok, { rivalNotifiers: ["dunst"] })[0].page, -1);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail > 0 ? 1 : 0);
