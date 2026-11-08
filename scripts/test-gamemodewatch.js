// ── test-gamemodewatch.js ─────────────────────────────────────────────────────
// Tests for services/gamemodewatch.js — Game Mode's "follow games" protocol.
//
//     bun scripts/test-gamemodewatch.js      (or: node scripts/test-gamemodewatch.js)
//
// Safe to run: pure functions, no I/O. Same contract as test-kelvin.js. The monitor
// lines are REAL gdbus output from gamemode 1.8.2 (a `gamemoderun sleep 3`), not a
// guess at the format — that is the whole point of the fixture.
//
// Also checks that the region markers here match scripts/gamemode-profile.py's
// byte-for-byte: the two files are two ends of one format.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "gamemodewatch.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const W = new Function(src + "\nreturn { parseMonitorLine, parseListGames, apply, seed, parseProfile, BEGIN, END, steamWindows, steamAppId, tidyComm, labelFor, parseComms, addSession, cleanSessions, whenLabel };")();

let pass = 0, fail = 0;
const failures = [];
function check(name, ok, detail) {
    if (ok) { pass++; return }
    fail++;
    failures.push(`  ${name}${detail ? "\n      " + detail : ""}`);
}
const J = v => JSON.stringify(v);

// ── Real captured output ──────────────────────────────────────────────────────
const CAPTURE = [
    "Monitoring signals from all objects owned by com.feralinteractive.GameMode",
    "The name com.feralinteractive.GameMode is owned by :1.58",
    "/com/feralinteractive/GameMode: com.feralinteractive.GameMode.GameRegistered (11340, objectpath '/com/feralinteractive/GameMode/Games/11340')",
    "/com/feralinteractive/GameMode: org.freedesktop.DBus.Properties.PropertiesChanged ('com.feralinteractive.GameMode', {'ClientCount': <1>}, @as [])",
    "/com/feralinteractive/GameMode: com.feralinteractive.GameMode.GameUnregistered (11340, objectpath '/com/feralinteractive/GameMode/Games/11340')",
    "/com/feralinteractive/GameMode: org.freedesktop.DBus.Properties.PropertiesChanged ('com.feralinteractive.GameMode', {'ClientCount': <0>}, @as [])",
];
const evs = CAPTURE.map(W.parseMonitorLine);
check("the banner is not an event", evs[0] === null);
check("owner line", J(evs[1]) === J({ kind: "owner", owned: true }), J(evs[1]));
check("GameRegistered", J(evs[2]) === J({ kind: "registered", pid: 11340 }), J(evs[2]));
check("ClientCount changes are ignored", evs[3] === null && evs[5] === null);
check("GameUnregistered", J(evs[4]) === J({ kind: "unregistered", pid: 11340 }), J(evs[4]));
check("vanished owner",
      J(W.parseMonitorLine("The name com.feralinteractive.GameMode does not have an owner"))
      === J({ kind: "owner", owned: false }));
check("garbage and empty lines are null",
      W.parseMonitorLine("") === null && W.parseMonitorLine(undefined) === null
      && W.parseMonitorLine("GameRegistered 12") === null);

// ── ListGames ─────────────────────────────────────────────────────────────────
check("one game", J(W.parseListGames("([(11340, objectpath '/com/feralinteractive/GameMode/Games/11340')],)")) === "[11340]");
check("several (a Proton tree registers every process)",
      J(W.parseListGames("([(10, objectpath '/c/f/G/Games/10'), (22, objectpath '/c/f/G/Games/22')],)")) === "[10,22]");
check("none", J(W.parseListGames("(@a(io) [],)")) === "[]");
check("error output is none", J(W.parseListGames("Error: GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown")) === "[]");

// ── The PID set ───────────────────────────────────────────────────────────────
const OWN = 500;
let s = [];
s = W.apply(s, evs[2], OWN);
check("a game registering joins the set", J(s) === "[11340]");
const same = W.apply(s, evs[2], OWN);
check("a repeated registration changes nothing (same array back)", same === s);
check("the shell's own hold is never a game",
      J(W.apply([], { kind: "registered", pid: OWN }, OWN)) === "[]");
s = W.apply(s, { kind: "registered", pid: 11341 }, OWN);
s = W.apply(s, evs[4], OWN);
check("one of two leaving keeps the other", J(s) === "[11341]");
const before = s;
check("an unknown PID leaving changes nothing (same array back)",
      W.apply(s, { kind: "unregistered", pid: 9 }, OWN) === before);
check("gamemoded vanishing empties the set",
      J(W.apply([1, 2], { kind: "owner", owned: false }, OWN)) === "[]");
check("gamemoded appearing changes nothing by itself",
      J(W.apply([1], { kind: "owner", owned: true }, OWN)) === "[1]");
check("null event is a no-op", W.apply(before, null, OWN) === before);
{
    const input = [1, 2];
    W.apply(input, { kind: "registered", pid: 3 }, OWN);
    W.apply(input, { kind: "unregistered", pid: 1 }, OWN);
    check("apply never mutates its input", J(input) === "[1,2]");
}
check("seed drops the own hold and duplicates", J(W.seed([OWN, 7, 7, 8], OWN)) === "[7,8]");

// ── Profile regions ───────────────────────────────────────────────────────────
const py = readFileSync(join(here, "gamemode-profile.py"), "utf8");
const pyConst = name => (py.match(new RegExp("^" + name + ' = "(.*)"$', "m")) || [])[1];
check("BEGIN marker matches gamemode-profile.py", pyConst("BEGIN") === W.BEGIN, pyConst("BEGIN"));
check("END marker matches gamemode-profile.py", pyConst("END") === W.END, pyConst("END"));

const userIni = ["[general]", "reaper_freq=5", "", W.BEGIN, "; Priority for games.", "[general]",
                 "renice=10", "ioprio=0", W.END, ""].join("\n");
check("user region", J(W.parseProfile(userIni)) === J({ installed: true, renice: 10, gpuLevel: "" }),
      J(W.parseProfile(userIni)));
const sysIni = [W.BEGIN, "[gpu]", "apply_gpu_optimisations=accept-responsibility", "gpu_device=1",
                "amd_performance_level=high", W.END, ""].join("\n");
check("system region", J(W.parseProfile(sysIni)) === J({ installed: true, renice: 0, gpuLevel: "high" }),
      J(W.parseProfile(sysIni)));
check("keys OUTSIDE the region are not ours",
      J(W.parseProfile("[general]\nrenice=7\n[gpu]\namd_performance_level=high\n"))
      === J({ installed: false, renice: 0, gpuLevel: "" }));
check("a missing file (empty text) is not installed", W.parseProfile("").installed === false
      && W.parseProfile(undefined).installed === false);
check("renice 0 comment reads as 0",
      W.parseProfile([W.BEGIN, "; renice left at 0: …", "ioprio=0", W.END].join("\n")).renice === 0);

// ── Steam windows and the game's name ─────────────────────────────────────────
const wins = [{ appClass: "steam", title: "Steam" }, { appClass: "steam_app_1245620", title: "ELDEN RING" },
              { appClass: "steam_app_0", title: "Some shortcut" }, { appClass: "steam_app_", title: "x" },
              { appClass: "steam_app_7a", title: "x" }, { appClass: "firefox", title: "y" }, {}, null];
check("steamWindows keeps steam_app_<digits> only",
      J(W.steamWindows(wins).map(w => w.appClass)) === J(["steam_app_1245620", "steam_app_0"]),
      J(W.steamWindows(wins)));
check("the Steam client is not a game", W.steamWindows([{ appClass: "steam" }]).length === 0);
check("steamWindows of nothing is empty", W.steamWindows(undefined).length === 0 && W.steamWindows([]).length === 0);

check("tidyComm drops .exe and -bin", W.tidyComm("eldenring.exe") === "eldenring" && W.tidyComm("factorio-bin") === "factorio");
check("tidyComm: plumbing is not a game name",
      ["wine64-preloader", "wineserver", "reaper", "pressure-vessel-wrap", "steam", "gamemoderun", "cat", "python3.12", ""]
          .every(c => W.tidyComm(c) === ""), J(["wine64-preloader", "reaper"].map(W.tidyComm)));
check("tidyComm keeps an ordinary name", W.tidyComm("cs2") === "cs2" && W.tidyComm("Celeste") === "Celeste");

check("labelFor: a Steam title wins over a comm", W.labelFor(["Elden Ring"], ["eldenring.exe"]) === "Elden Ring");
check("labelFor: blank titles fall through to the first real comm",
      W.labelFor(["", "  "], ["reaper", "wine64-preloader", "hades.exe"]) === "hades");
check("labelFor: nothing usable is empty", W.labelFor([], ["reaper"]) === "" && W.labelFor(undefined, undefined) === "");

check("parseComms keeps PID order, blank for a PID that went",
      J(W.parseComms("11 cs2\n13 reaper\n", [11, 12, 13])) === J(["cs2", "", "reaper"]),
      J(W.parseComms("11 cs2\n13 reaper\n", [11, 12, 13])));
check("parseComms ignores junk", J(W.parseComms("sh: x\n\n", [5])) === J([""]));

check("steamAppId reads the id from the class", W.steamAppId("steam_app_1245620") === "1245620");
check("steamAppId: anything else is empty", ["steam", "steam_app_", "steam_app_7a", "Hollow Knight Silksong", "", null, undefined].every(c => W.steamAppId(c) === ""));

// ── Session history ───────────────────────────────────────────────────────────
const t0 = new Date(2026, 10, 7, 18, 20).getTime();
const a = W.addSession([], { start: t0, seconds: 4300, game: "Hollow Knight Silksong", appId: "1030300", auto: true }, 60);
const art = W.addSession([], { start: t0, seconds: 100, game: "g", appId: "1", art: "/home/u/.cache/quicktest/gamemode-art/1.jpg" }, 60);
check("a row keeps the picture's path", art[0].art === "/home/u/.cache/quicktest/gamemode-art/1.jpg", J(art));
check("a bad picture path is dropped", ["rel/x.jpg", "/a\nb", "/" + "x".repeat(400), 5, null].every(p => W.addSession([], { start: t0, seconds: 100, art: p }, 60)[0].art === ""));
check("the picture path survives a save and load", W.cleanSessions({ sessions: art })[0].art === art[0].art);
check("addSession adds a row", a.length === 1 && a[0].appId === "1030300" && a[0].auto === true && a[0].seconds === 4300, J(a));
check("a session under a minute is not kept", W.addSession(a, { start: t0, seconds: 59 }, 60) === a);
check("junk is not kept", W.addSession(a, null) === a && W.addSession(a, { seconds: 500 }) === a && W.addSession(a, { start: 1, seconds: "x" }) === a);
const b = W.addSession(a, { start: t0 + 1e7, seconds: 120, game: "x".repeat(200), appId: "12;rm", auto: "yes" }, 60);
check("newest first, name capped, bad id and non-boolean auto dropped",
      b.length === 2 && b[0].seconds === 120 && b[0].game.length === 80 && b[0].appId === "" && b[0].auto === false, J(b));
check("never mutates its input", a.length === 1);
check("the list is capped", W.addSession(b, { start: t0 + 2e7, seconds: 300 }, 2).length === 2);
const c = W.cleanSessions({ sessions: [{ start: t0, seconds: 100 }, { start: t0 + 5, seconds: 10 }, null, "x", { start: t0 + 9, seconds: 90, game: 5, appId: "42" }] });
check("cleanSessions keeps well-formed rows, newest first",
      c.length === 2 && c[0].start === t0 + 9 && c[0].game === "" && c[0].appId === "42" && c[1].start === t0, J(c));
check("cleanSessions of nothing is empty", W.cleanSessions(null).length === 0 && W.cleanSessions({}).length === 0 && W.cleanSessions({ sessions: 3 }).length === 0);

const now = new Date(2026, 10, 7, 20, 0).getTime();
check("whenLabel today", W.whenLabel(t0, now) === "Today 18:20");
check("whenLabel yesterday", W.whenLabel(new Date(2026, 10, 6, 9, 5).getTime(), now) === "Yesterday 09:05");
check("whenLabel this week", W.whenLabel(new Date(2026, 10, 4, 21, 40).getTime(), now) === "Wed 21:40", W.whenLabel(new Date(2026, 10, 4, 21, 40).getTime(), now));
check("whenLabel older", W.whenLabel(new Date(2026, 9, 21, 12, 0).getTime(), now) === "21 Oct");

console.log(`gamemodewatch: ${pass} passed, ${fail} failed`);
if (fail) { console.log(failures.join("\n")); process.exit(1); }
