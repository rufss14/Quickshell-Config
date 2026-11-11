// ── test-clips.js ─────────────────────────────────────────────────────────────
// Regression tests for services/clips.js, the clips module's logic.
//
//     bun scripts/test-clips.js          (or: node scripts/test-clips.js)
//
// Safe to run: clips.js is pure functions and touches nothing.
// Loaded by stripping the `.pragma library` line, as test-dock.js does.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
// clips.js imports clockfmt.js with `.import`, which node can't read: inline it, and the
// ClockFmt object the .import would have bound.
const clockSrc = readFileSync(join(here, "..", "services", "clockfmt.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
// calllog.js likewise, in its own scope (its helper names would clash with clips.js's).
const callSrc = readFileSync(join(here, "..", "services", "calllog.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const src = clockSrc + "\nconst ClockFmt = { clock };\n" +
    "const CallLog = (function () {\n" + callSrc + "\nreturn { cleanName, people };\n})();\n" +
    readFileSync(join(here, "..", "services", "clips.js"), "utf8")
        .replace(/^\s*\.pragma\s+library\s*$/m, "")
        .replace(/^\s*\.import\s+.*$/gm, "");

const { target, region, windowGeom, settings, recorderArgv, saveCommand, saveLengths, timelineAt, parseEvents, newEvents,
        clock, span, age, bufferMiB, summary, audioText, trimSpan, clipKind, libraryView, stamp,
        gameOf, gamesOf, isToday, aheadPlan, PRESETS, matchPreset, RECORD_LIMITS, limitOf, limitHit,
        estimateBufferMiB, explainError, diagnose, FILE_MANAGERS, pickFileManager, fileManagerArgv, prettyName, dayLabel, groupByDay,
        DISCORD_CAPS, discordPlan, prunePlan, bytesText, contextOf, contextLine, cleanBook, listSig,
        layoutRows, cleanTag, cleanTagBook, withTag, withoutTag, tagCounts, groupLine, withoutAll } =
    new Function(src + "\nreturn { target, region, windowGeom, settings, recorderArgv, saveCommand, saveLengths, timelineAt, " +
                 "parseEvents, newEvents, clock, span, age, bufferMiB, summary, audioText, trimSpan, " +
                 "clipKind, libraryView, stamp, gameOf, gamesOf, isToday, aheadPlan, PRESETS, matchPreset, " +
                 "RECORD_LIMITS, limitOf, limitHit, estimateBufferMiB, explainError, diagnose, FILE_MANAGERS, pickFileManager, fileManagerArgv, prettyName, dayLabel, groupByDay, " +
                 "DISCORD_CAPS, discordPlan, prunePlan, bytesText, contextOf, contextLine, cleanBook, listSig, " +
                 "layoutRows, cleanTag, cleanTagBook, withTag, withoutTag, tagCounts, groupLine, withoutAll };")();

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

// ── target / region ──────────────────────────────────────────────────────────
check("target: a connector name", target("DP-1"), "DP-1");
check("target: HDMI", target("HDMI-A-1"), "HDMI-A-1");
check("target: portal", target("portal"), "portal");
check("target: empty is nothing", target(""), "");
check("target: undefined is nothing", target(undefined), "");
check("target: no paths", target("/dev/video0"), "");
check("target: no flags", target("-o x"), "");
check("target: no separators", target("DP-1|DP-2"), "");
check("region: slurp's format", region("1280x720+100+50"), "1280x720+100+50");
check("region: trimmed", region(" 800x600+0+0\n"), "800x600+0+0");
check("region: negative offsets (a monitor left of the origin)", region("300x200+-1920+0"), "300x200+-1920+0");
check("region: too small", region("1x1+0+0"), "");
check("region: garbage", region("hello"), "");
check("region: cancelled slurp (empty)", region(""), "");

check("window: its area", windowGeom([10, 20], [800, 600]), "800x600+10+20");
check("window: fractional coords rounded", windowGeom([10.4, 20.6], [800.2, 600]), "800x600+10+21");
check("window: on a monitor left of the origin", windowGeom([-1920, 0], [640, 480]), "640x480+-1920+0");
check("window: no size", windowGeom([0, 0], [0, 0]), "");
check("window: garbage", windowGeom(undefined, null), "");

// ── settings ─────────────────────────────────────────────────────────────────
const d = settings({});
check("settings: defaults", [d.fps, d.quality, d.cbr, d.codec, d.container, d.resolution, d.cursor,
                             d.desktop, d.mic, d.split, d.buffer, d.storage],
      [60, "very_high", false, "auto", "mp4", "original", true, true, false, false, 120, "ram"]);
check("settings: an unknown quality falls back", settings({ quality: "insane" }).quality, "very_high");
check("settings: an unknown container falls back", settings({ container: "avi" }).container, "mp4");
check("settings: fps clamped", [settings({ fps: 0 }).fps, settings({ fps: 9999 }).fps], [10, 360]);
check("settings: fps not a number", settings({ fps: "abc" }).fps, 60);
check("settings: buffer clamped", [settings({ bufferSeconds: 1 }).buffer, settings({ bufferSeconds: 1e6 }).buffer], [5, 1800]);
check("settings: resolution by key", settings({ resolution: "1080" }).resolution, "1080");
check("settings: numeric resolution too", settings({ resolution: 720 }).resolution, "720");
check("settings: unknown resolution", settings({ resolution: "4320" }).resolution, "original");
check("settings: no prototype keys", settings({ resolution: "toString" }).resolution, "original");
check("settings: kbps clamped", settings({ kbps: 5 }).kbps, 1000);

// ── recorderArgv ─────────────────────────────────────────────────────────────
check("argv: the replay buffer",
      recorderArgv({}, "replay", "DP-1", "/v/Clips"),
      ["gpu-screen-recorder", "-w", "DP-1", "-c", "mp4", "-f", "60", "-k", "auto", "-bm", "auto",
       "-q", "very_high", "-cursor", "yes", "-a", "default_output",
       "-r", "120", "-replay-storage", "ram", "-o", "/v/Clips", "-ro", "/v/Clips"]);
check("argv: a recording",
      recorderArgv({ mic: true, cursor: false, resolution: "1080", codec: "hevc", container: "mkv" },
                   "record", "DP-2", "/v/Clips/Recording.mkv"),
      ["gpu-screen-recorder", "-w", "DP-2", "-c", "mkv", "-f", "60", "-k", "hevc", "-bm", "auto",
       "-q", "very_high", "-s", "1920x1080", "-cursor", "no", "-a", "default_output|default_input",
       "-o", "/v/Clips/Recording.mkv"]);
check("argv: constant bitrate",
      recorderArgv({ bitrateMode: "cbr", kbps: 20000 }, "replay", "DP-1", "/o").slice(9, 13),
      ["-bm", "cbr", "-q", "20000"]);
check("argv: split tracks are one -a each",
      recorderArgv({ mic: true, splitAudio: true }, "record", "DP-1", "/o.mp4")
          .filter((x, i, a) => x === "-a" || a[i - 1] === "-a"),
      ["-a", "default_output", "-a", "default_input"]);
check("argv: no audio at all",
      recorderArgv({ desktopAudio: false }, "record", "DP-1", "/o.mp4").indexOf("-a"), -1);
check("argv: portal restores its session",
      recorderArgv({}, "record", "portal", "/o.mp4").slice(-4, -2), ["-restore-portal-session", "yes"]);
check("argv: a region",
      recorderArgv({}, "record", "region", "/o.mp4", "640x480+10+20").slice(1, 5),
      ["-w", "region", "-region", "640x480+10+20"]);
check("argv: a region with no geometry", recorderArgv({}, "record", "region", "/o.mp4", ""), null);
check("argv: a bad target", recorderArgv({}, "record", "; rm -rf /", "/o.mp4"), null);
check("argv: no output", recorderArgv({}, "replay", "DP-1", ""), null);
check("argv: an unknown mode", recorderArgv({}, "stream", "DP-1", "/o"), null);
check("argv: every element a string",
      recorderArgv({ fps: 144, bitrateMode: "cbr" }, "replay", "DP-1", "/o").every(x => typeof x === "string"), true);

// ── saveCommand ──────────────────────────────────────────────────────────────
check("save: the whole buffer", saveCommand(0, 120), "save");
check("save: 30s of a 2 min buffer", saveCommand(30, 120), "save:30");
check("save: a length it has no signal for", saveCommand(45, 120), "save");
check("save: no shorter than the buffer", saveCommand(60, 60), "save");
check("save: longer than the buffer", saveCommand(300, 120), "save");
check("save: garbage", saveCommand("x", 120), "save");
// The panel's chips: only lengths with a signal, and only shorter than the buffer
// (every one of them round-trips to its own save command).
check("lengths: a 2 min buffer", saveLengths(120), [10, 30, 60]);
check("lengths: a 30 min buffer stops short of it", saveLengths(1800), [10, 30, 60, 300, 600]);
check("lengths: a buffer too short for any", saveLengths(10), []);
check("lengths: garbage", saveLengths("x"), []);
check("lengths: each is a cut, not the whole", saveLengths(600).every(n => saveCommand(n, 600) === "save:" + n), true);
// The HUD card's timeline: back from now, by a square root.
check("timeline: now", timelineAt(0, 120), 0);
check("timeline: the whole buffer", timelineAt(120, 120), 1);
check("timeline: past the buffer is the whole", timelineAt(600, 120), 1);
check("timeline: a quarter of the time is half the width", timelineAt(30, 120), 0.5);
check("timeline: grows with the length", saveLengths(1800).map(n => timelineAt(n, 1800)).every((v, i, a) => i === 0 || v > a[i - 1]), true);
check("timeline: no buffer", timelineAt(30, 0), 0);
check("timeline: garbage", timelineAt("x", 120), 0);

// ── events ───────────────────────────────────────────────────────────────────
const ev = parseEvents([
    '{"path":"/v/Replay_1.mp4","type":"replay","t":1000}',
    '',
    '{"path":"/v/Video_2.mp4","type":"regular","t":2000}',
    '{"path":"/v/torn',
    '{"type":"replay","t":3000}',
    '"just a string"',
    '{"path":"/v/x.mp4","type":"replay","t":"nope"}',
    '{"path":"/v/Replay_3.mp4","type":"replay","t":4000}'
].join("\n"));
check("events: good lines only", ev.map(e => e.path), ["/v/Replay_1.mp4", "/v/Video_2.mp4", "/v/Replay_3.mp4"]);
check("events: nothing", parseEvents(""), []);
check("events: undefined", parseEvents(undefined), []);
check("events: newer than seen", newEvents(ev, 2000).map(e => e.t), [4000]);
check("events: all seen", newEvents(ev, 4000), []);

// ── formatting ───────────────────────────────────────────────────────────────
check("clock: seconds", clock(7), "0:07");
check("clock: minutes", clock(125), "2:05");
check("clock: hours", clock(3725), "1:02:05");
check("clock: garbage", clock(undefined), "0:00");
check("clock: negative", clock(-5), "0:00");
check("span: seconds", span(45), "45s");
check("span: minutes", span(120), "2 min");
check("span: mixed", span(90), "1 min 30s");
check("age: now", age(1000, 30000), "just now");
check("age: minutes", age(0, 4 * 60000), "4 min ago");
check("age: hours", age(0, 3 * 3600000), "3 h ago");
check("age: days", age(0, 2 * 86400000), "2 d ago");
check("bufferMiB: cbr", bufferMiB({ bitrateMode: "cbr", kbps: 40000, bufferSeconds: 120 }), 572);
check("bufferMiB: quality mode has no fixed size", bufferMiB({}), -1);
check("summary", summary({ resolution: "1440", fps: 144, codec: "h264" }), "1440p · 144 fps · H.264");
check("summary: defaults", summary({}), "Native · 60 fps · Auto codec");
check("audio: default", audioText({}), "Desktop audio");
check("audio: both, split", audioText({ mic: true, splitAudio: true }), "Desktop + mic · separate tracks");
check("audio: mic only", audioText({ desktopAudio: false, mic: true }), "Microphone");
check("audio: none", audioText({ desktopAudio: false }), "No audio");

// ── trimSpan ─────────────────────────────────────────────────────────────────
check("trim: a span", trimSpan(0.25, 0.75, 60), { start: 15, end: 45 });
check("trim: handles crossed", trimSpan(0.75, 0.25, 60), { start: 15, end: 45 });
check("trim: clamped", trimSpan(-1, 2, 10), { start: 0, end: 10 });
check("trim: too short", trimSpan(0.5, 0.501, 60), null);
check("trim: unknown duration", trimSpan(0, 1, 0), null);

// ── library ──────────────────────────────────────────────────────────────────
check("kind: a replay", clipKind("Replay_2026-09-26_19-31-59", "mp4"), "clip");
check("kind: a recording", clipKind("Recording_2026-09-26_19-00-00", "mkv"), "recording");
check("kind: the recorder's own regular file", clipKind("Video_2026-09-26", "mp4"), "recording");
check("kind: a trim", clipKind("Replay_x-trim", "mp4"), "edit");
check("kind: a second edit", clipKind("Replay_x-edit-2", "mp4"), "edit");
check("kind: a gif", clipKind("Replay_x", "gif"), "edit");
check("kind: renamed is a clip", clipKind("Ace clutch", "mp4"), "clip");
check("kind: a word that merely contains edit", clipKind("credited run", "mp4"), "clip");
const lib = [
    { path: "/a", name: "Replay_a", ext: "mp4", mtime: 3, duration: 10, size: 5 },
    { path: "/b", name: "Recording_b", ext: "mkv", mtime: 1, duration: 90, size: 50 },
    { path: "/c", name: "Replay_a-trim", ext: "mp4", mtime: 2, duration: 4, size: 90 }
];
check("library: newest first", libraryView(lib, "", "all", [], "newest").map(c => c.path), ["/a", "/c", "/b"]);
check("library: oldest", libraryView(lib, "", "all", [], "oldest").map(c => c.path), ["/b", "/c", "/a"]);
check("library: longest", libraryView(lib, "", "all", [], "longest").map(c => c.path), ["/b", "/a", "/c"]);
check("library: largest", libraryView(lib, "", "all", [], "largest").map(c => c.path), ["/c", "/b", "/a"]);
check("library: search", libraryView(lib, "REPLAY", "all", [], "newest").map(c => c.path), ["/a", "/c"]);
check("library: favourites", libraryView(lib, "", "favourites", ["/b"], "newest").map(c => c.path), ["/b"]);
check("library: by kind", libraryView(lib, "", "edit", [], "newest").map(c => c.path), ["/c"]);
check("library: never sorts the input", (libraryView(lib, "", "all", [], "oldest"), lib[0].path), "/a");
check("library: garbage", libraryView(null, null, "all", null, "x"), []);
check("stamp", stamp(65.37), "1:05.3");
check("stamp: zero", stamp(0), "0:00.0");


// ── game names ──
check("game: from a replay", gameOf("Elden-Ring_Replay_2026-10-18_21-41-05"), "Elden Ring");
check("game: from a recording", gameOf("Counter-Strike-2_Recording_2026-10-18_21-41-05"), "Counter Strike 2");
check("game: the recorder's own name has none", gameOf("Replay_2026-10-18_21-41-05"), "");
check("game: a rename has none", gameOf("Ace clutch"), "");
check("game: garbage", gameOf(null), "");
check("kind: a game-named recording", clipKind("Elden-Ring_Recording_2026-10-18_21-41-05", "mkv"), "recording");
check("kind: a game-named video", clipKind("Elden-Ring_Video_2026-10-18_21-41-05", "mp4"), "recording");
check("kind: a game-named replay is a clip", clipKind("Elden-Ring_Replay_2026-10-18_21-41-05", "mp4"), "clip");
check("kind: a game-named trim", clipKind("Elden-Ring_Replay_2026-10-18_21-41-05-trim", "mp4"), "edit");
const games = [
    { name: "Elden-Ring_Replay_2026-10-18_21-41-05" }, { name: "Elden-Ring_Replay_2026-10-17_20-00-00" },
    { name: "Hades_Replay_2026-10-18_10-00-00" }, { name: "Replay_2026-10-18_09-00-00" }
];
check("games: counted, most first", gamesOf(games), [{ game: "Elden Ring", count: 2 }, { game: "Hades", count: 1 }]);
check("games: none", gamesOf([]), []);
check("games: garbage", gamesOf(null), []);
const noon = new Date(2026, 9, 18, 12, 0, 0).getTime();
check("today: the same day", isToday(new Date(2026, 9, 18, 0, 5).getTime(), noon), true);
check("today: last minute of it", isToday(new Date(2026, 9, 18, 23, 59).getTime(), noon), true);
check("today: yesterday", isToday(new Date(2026, 9, 17, 23, 59).getTime(), noon), false);
check("today: a year ago, same date", isToday(new Date(2025, 9, 18, 12).getTime(), noon), false);
const gl = [
    { path: "/a", name: "Elden-Ring_Replay_2026-10-18_21-41-05", ext: "mp4", mtime: noon - 1000, duration: 9, size: 1 },
    { path: "/b", name: "Hades_Replay_2026-10-17_10-00-00", ext: "mp4", mtime: noon - 86400000, duration: 9, size: 1 },
    { path: "/c", name: "Replay_2026-10-18_09-00-00", ext: "mp4", mtime: noon - 2000, duration: 9, size: 1 }
];
check("library: today", libraryView(gl, "", "today", [], "newest", "", noon).map(c => c.path), ["/a", "/c"]);
check("library: a game", libraryView(gl, "", "all", [], "newest", "Hades", noon).map(c => c.path), ["/b"]);
check("library: a game and today", libraryView(gl, "", "today", [], "newest", "Hades", noon).map(c => c.path), []);
check("library: no game filter = all", libraryView(gl, "", "all", [], "newest", "", noon).length, 3);

// ── clip it + N more seconds ──
check("ahead: none is a plain save", aheadPlan(30, 0, 120), { delay: 0, command: "save:30", keep: 0, want: 0 });
check("ahead: whole buffer, none", aheadPlan(0, 0, 120), { delay: 0, command: "save", keep: 0, want: 0 });
check("ahead: 30 + 10 → the 60 signal, cut to 40", aheadPlan(30, 10, 120), { delay: 10, command: "save:60", keep: 40, want: 40 });
check("ahead: 10 + 20 → exactly 30, no cut", aheadPlan(10, 20, 120), { delay: 20, command: "save:30", keep: 0, want: 30 });
check("ahead: 60 + 30 → the 5 min signal, cut to 90", aheadPlan(60, 30, 600), { delay: 30, command: "save:300", keep: 90, want: 90 });
check("ahead: past the buffer is the whole buffer", aheadPlan(60, 30, 90), { delay: 30, command: "save", keep: 0, want: 90 });
check("ahead: the whole buffer + 10 is the buffer again", aheadPlan(0, 10, 120), { delay: 10, command: "save", keep: 0, want: 120 });
check("ahead: the wait is capped under the buffer", aheadPlan(5, 500, 60), { delay: 59, command: "save", keep: 0, want: 60 });
check("ahead: a negative wait is none", aheadPlan(30, -5, 120).delay, 0);
check("ahead: junk", aheadPlan("x", "y", "z"), { delay: 0, command: "save", keep: 0, want: 0 });

// ── presets ──
check("presets: unique ids", new Set(PRESETS.map(p => p.id)).size, PRESETS.length);
check("presets: every one names the same keys", new Set(PRESETS.map(p => Object.keys(p.v).sort().join())).size, 1);
const fromPreset = p => ({ fps: p.v.fps, quality: p.v.quality, bitrateMode: p.v.cbr ? "cbr" : "auto", codec: p.v.codec,
                           resolution: p.v.resolution, bufferSeconds: p.v.buffer, desktopAudio: p.v.desktop,
                           mic: p.v.mic, splitAudio: p.v.split });
for (const p of PRESETS) check("presets: " + p.id + " matches itself", matchPreset(fromPreset(p))?.id, p.id);
check("presets: one setting off is custom", matchPreset({ ...fromPreset(PRESETS[0]), fps: 144 }), null);
check("presets: the defaults are the Game preset's neighbour, not a match (mic off)", matchPreset({}), null);
check("presets: values survive settings()'s clamps", PRESETS.every(p => {
    const s = settings(fromPreset(p));
    return Object.keys(p.v).every(k => s[k] === p.v[k]);
}), true);

// ── limits ──
check("limit: unknown is none", limitOf("nope").id, "off");
check("limit: none never trips", limitHit("off", 99999, 1e12), "");
check("limit: time", limitHit("10m", 600, 0), "time");
check("limit: time not yet", limitHit("10m", 599, 1e12), "");
check("limit: size", limitHit("2g", 5, 2147483648), "size");
check("limit: size not yet", limitHit("2g", 99999, 2147483647), "");
check("limit: ids are unique", new Set(RECORD_LIMITS.map(l => l.id)).size, RECORD_LIMITS.length);

// ── what a buffer costs ──
check("estimate: cbr is exact", estimateBufferMiB({ bitrateMode: "cbr", kbps: 40000, bufferSeconds: 120 }), bufferMiB({ bitrateMode: "cbr", kbps: 40000, bufferSeconds: 120 }));
check("estimate: quality is a rough figure", estimateBufferMiB({ quality: "very_high", bufferSeconds: 120 }), 358);
check("estimate: on disk costs no RAM", estimateBufferMiB({ storage: "disk", bufferSeconds: 120 }), 0);

// ── explaining the recorder ──
check("explain: kms permission", explainError("gsr error: kms server: Operation not permitted")?.fix, "portal");
check("explain: portal", explainError("failed to start portal session")?.fix, "portal");
check("explain: a monitor", explainError("gsr error: monitor DP-9 not found")?.fix, "target");
check("explain: a codec", explainError("vaapi: hevc encoder not supported")?.fix, "codec");
check("explain: unknown words are left to the caller", explainError("something odd"), null);
check("explain: empty", explainError(""), null);

// ── diagnosing ──
const ok = { probed: true, installed: true, wanted: true, buffering: true, gaveUp: false, error: "", target: "", screens: ["DP-2"],
             kms: true, memAvailMiB: 16000, diskFreeMiB: 200000, opts: {} };
check("diagnose: nothing before the probe", diagnose({ ...ok, probed: false }), []);
check("diagnose: healthy is empty", diagnose(ok), []);
check("diagnose: not installed", diagnose({ ...ok, installed: false }).map(d => d.id), ["missing"]);
check("diagnose: a monitor that went away", diagnose({ ...ok, buffering: false, target: "DP-9" }).map(d => d.id), ["target"]);
check("diagnose: the portal needs no monitor", diagnose({ ...ok, target: "portal" }), []);
check("diagnose: failing with a known reason", diagnose({ ...ok, buffering: false, error: "kms Operation not permitted" }).map(d => d.id), ["explained"]);
check("diagnose: failing, unknown reason, no capability", diagnose({ ...ok, buffering: false, gaveUp: true, error: "boom", kms: false }).map(d => d.id), ["kms"]);
check("diagnose: failing, unknown reason", diagnose({ ...ok, buffering: false, gaveUp: true, error: "boom" }).map(d => d.id), ["failed"]);
check("diagnose: not clipping on purpose is not a problem", diagnose({ ...ok, wanted: false, buffering: false, error: "old error" }), []);
check("diagnose: a buffer that will not fit in RAM", diagnose({ ...ok, memAvailMiB: 300, opts: { bitrateMode: "cbr", kbps: 40000, bufferSeconds: 120 } }).map(d => d.id), ["ram"]);
check("diagnose: RAM unknown is not a warning", diagnose({ ...ok, memAvailMiB: 0 }), []);
check("diagnose: low disk is a warning", diagnose({ ...ok, diskFreeMiB: 2000 }).map(d => d.level), ["warn"]);
check("diagnose: very low disk is an error", diagnose({ ...ok, diskFreeMiB: 100 }).map(d => d.level), ["error"]);
check("diagnose: errors come first", diagnose({ ...ok, buffering: false, gaveUp: true, error: "boom", diskFreeMiB: 2000 }).map(d => d.level), ["error", "warn"]);


// ── file managers ──
check("fm: automatic takes the first installed, Nautilus first", pickFileManager("", ["dolphin", "nautilus"]), "nautilus");
check("fm: automatic with only Dolphin", pickFileManager("", ["dolphin"]), "dolphin");
check("fm: a preference that is installed wins", pickFileManager("dolphin", ["nautilus", "dolphin"]), "dolphin");
check("fm: a preference that is not installed is ignored", pickFileManager("thunar", ["nautilus"]), "nautilus");
check("fm: nothing installed is none", pickFileManager("", []), "");
check("fm: an unknown preference is ignored", pickFileManager("rm", ["rm", "caja"]), "caja");
check("fm: garbage", pickFileManager(null, null), "");
check("fm: nautilus opens a folder in a new window", fileManagerArgv("nautilus", "/home/u/Videos/Clips", ""), ["nautilus", "--new-window", "/home/u/Videos/Clips"]);
check("fm: nautilus selects a file", fileManagerArgv("nautilus", "/home/u/Videos/Clips", "/home/u/Videos/Clips/a.mp4"), ["nautilus", "--select", "/home/u/Videos/Clips/a.mp4"]);
check("fm: dolphin selects a file", fileManagerArgv("dolphin", "/d", "/d/a.mp4"), ["dolphin", "--select", "/d/a.mp4"]);
check("fm: thunar can only open the folder", fileManagerArgv("thunar", "/d", "/d/a.mp4"), ["thunar", "/d"]);
check("fm: unknown", fileManagerArgv("xterm", "/d", ""), null);
check("fm: a relative folder is refused", fileManagerArgv("nautilus", "d", ""), null);
check("fm: a relative file is refused", fileManagerArgv("nautilus", "/d", "a.mp4"), null);
check("fm: ids are unique", new Set(FILE_MANAGERS.map(f => f.id)).size, FILE_MANAGERS.length);
check("fm: every one has a binary of its own id", FILE_MANAGERS.every(f => f.bin === f.id), true);
check("fm: every argv starts with its binary", FILE_MANAGERS.every(f => fileManagerArgv(f.id, "/d", "/d/a")[0] === f.bin), true);


// ── names a person would say ──
check("pretty: a game replay", prettyName("Elden-Ring_Replay_2026-10-11_21-41-05", "mp4", 0), { title: "Elden Ring", time: "21:41", tag: "" });
check("pretty: a plain replay", prettyName("Replay_2026-10-11_02-22-38", "mp4", 0), { title: "Replay", time: "02:22", tag: "" });
check("pretty: a recording", prettyName("Recording_2026-10-11_02-22-38", "mkv", 0), { title: "Recording", time: "02:22", tag: "" });
check("pretty: the recorder's regular file is a recording", prettyName("Video_2026-10-11_02-22-38", "mp4", 0).title, "Recording");
check("pretty: a trim", prettyName("Replay_2026-10-11_02-22-38-trim", "mp4", 0), { title: "Replay", time: "02:22", tag: "Trimmed" });
check("pretty: a second trim", prettyName("Replay_2026-10-11_02-22-38-trim-2", "mp4", 0).tag, "Trimmed");
check("pretty: an edit", prettyName("Hades_Replay_2026-10-11_10-00-00-edit", "mp4", 0), { title: "Hades", time: "10:00", tag: "Edited" });
check("pretty: a gif", prettyName("Replay_2026-10-11_02-22-38", "gif", 0).tag, "GIF");
const at = new Date(2026, 9, 11, 7, 5).getTime();
check("pretty: your own name keeps it, with the file's time", prettyName("Poor Raiden", "mp4", at), { title: "Poor Raiden", time: "07:05", tag: "" });
check("pretty: your name with trim", prettyName("Ace clutch-trim", "mp4", at), { title: "Ace clutch", time: "07:05", tag: "Trimmed" });
check("pretty: garbage", prettyName(null, null, null).title, "");

// ── days ──
const nowD = new Date(2026, 9, 18, 15, 0).getTime();
const at_ = (y, mo, d, h = 12) => new Date(y, mo, d, h).getTime();
check("day: today", dayLabel(at_(2026, 9, 18, 1), nowD), "Today");
check("day: yesterday", dayLabel(at_(2026, 9, 17, 23), nowD), "Yesterday");
check("day: this week is a weekday", dayLabel(at_(2026, 9, 14), nowD), "Wednesday");
check("day: six days ago is still a weekday", dayLabel(at_(2026, 9, 12), nowD), "Monday");
check("day: a week ago is a date", dayLabel(at_(2026, 9, 11), nowD), "11 October");
check("day: another year has the year", dayLabel(at_(2025, 11, 31), nowD), "31 December 2025");
const dl = [{ mtime: at_(2026, 9, 18, 14) }, { mtime: at_(2026, 9, 18, 9) }, { mtime: at_(2026, 9, 17, 22) }, { mtime: at_(2026, 9, 11) }];
check("groups: by day, in order", groupByDay(dl, nowD, true).map(g => [g.label, g.clips.length]),
      [["Today", 2], ["Yesterday", 1], ["11 October", 1]]);
check("groups: not by day is one unlabelled group", groupByDay(dl, nowD, false).map(g => [g.label, g.clips.length]), [["", 4]]);
check("groups: nothing", groupByDay([], nowD, true), []);
check("groups: nothing, not by day", groupByDay([], nowD, false), []);
check("groups: garbage", groupByDay(null, nowD, true), []);
check("groups: the same day apart is two groups when something sits between", groupByDay(
      [{ mtime: at_(2026, 9, 18) }, { mtime: at_(2026, 9, 17) }, { mtime: at_(2026, 9, 18) }], nowD, true).length, 3);

// ── Discord's upload cap ─────────────────────────────────────────────────────
const MB = 1048576;
check("discord: under the cap is left alone", discordPlan(8 * MB, 10, 30), { shrink: false, sizeMB: 0, cap: 10, fits: true });
check("discord: close under the cap is left alone", discordPlan(9.5 * MB, 10, 30).shrink, false);
check("discord: just over the cap shrinks to it", discordPlan(10.2 * MB, 10, 30), { shrink: true, sizeMB: 10, cap: 10, fits: true });
check("discord: a big clip shrinks", discordPlan(200 * MB, 10, 60).shrink, true);
check("discord: unknown size is not shrunk", discordPlan(0, 10, 60).shrink, false);
check("discord: a bad cap is 10", discordPlan(50 * MB, "x", 30).cap, 10);
check("discord: a cap is clamped to 500", discordPlan(900 * MB, 9999, 30).cap, 500);
check("discord: ten minutes cannot fit 10 MB", discordPlan(900 * MB, 10, 600).fits, false);
check("discord: thirty seconds fits 10 MB", discordPlan(100 * MB, 10, 30).fits, true);
check("discord: caps offered", DISCORD_CAPS, [10, 25, 50, 500]);

// ── Clearing out ─────────────────────────────────────────────────────────────
const DAY = 86400000, GB = 1073741824, T0 = Date.UTC(2026, 10, 9, 12);
const mk = (n, ageDays, size, extra) => Object.assign({ path: "/c/" + n, name: n, mtime: T0 - ageDays * DAY, size: size }, extra || {});
const L = [mk("new", 0.5, GB), mk("a", 3, GB), mk("b", 40, GB), mk("c", 90, GB), mk("fav", 200, GB)];
check("prune: nothing without a limit", prunePlan(L, [], { days: 0, gb: 0 }, T0), { paths: [], bytes: 0, count: 0 });
check("prune: by age, oldest first", prunePlan(L, [], { days: 30, gb: 0 }, T0).paths, ["/c/fav", "/c/c", "/c/b"]);
check("prune: a favourite is kept", prunePlan(L, ["/c/fav"], { days: 30, gb: 0 }, T0).paths, ["/c/c", "/c/b"]);
check("prune: bytes add up", prunePlan(L, ["/c/fav"], { days: 30, gb: 0 }, T0).bytes, 2 * GB);
check("prune: by size drops the oldest until it fits", prunePlan(L, [], { days: 0, gb: 3 }, T0).paths, ["/c/fav", "/c/c"]);
check("prune: size counts what age already took", prunePlan(L, [], { days: 100, gb: 4 }, T0).paths, ["/c/fav"]);
check("prune: size cannot touch a favourite", prunePlan(L, ["/c/fav", "/c/c", "/c/b", "/c/a", "/c/new"], { days: 0, gb: 1 }, T0).count, 0);
check("prune: a fresh file is never taken", prunePlan([mk("w", 0, GB, { mtime: T0 - 60000 })], [], { days: 0, gb: 0.001 }, T0).count, 0);
check("prune: an entry with no time is never taken", prunePlan([{ path: "/c/x", size: GB }], [], { days: 1, gb: 0 }, T0).count, 0);
check("prune: garbage in", prunePlan(null, null, null, T0), { paths: [], bytes: 0, count: 0 });
check("prune: days are clamped", prunePlan(L, [], { days: -5, gb: 0 }, T0).count, 0);
check("bytes: gigabytes", bytesText(3.2 * GB), "3.2 GB");
check("bytes: megabytes", bytesText(412 * MB), "412 MB");
check("bytes: nothing", bytesText(null), "0 MB");

// ── What was going on ────────────────────────────────────────────────────────
const call = [{ id: "123456789012345678", name: "Alice" }, { id: "223456789012345678", name: "Bob" },
              { id: "323456789012345678", name: "Me", isSelf: true }, { id: "423456789012345678", name: "Bot", bot: true },
              { id: "bad", name: "Mallory" }];
check("context: song and company", contextOf({ artist: "Daft Punk", title: "Around the World" }, call, true, true),
      { artist: "Daft Punk", title: "Around the World", with: ["Alice", "Bob"] });
check("context: yourself, bots and bad ids are not company", contextOf(null, call, false, true).with, ["Alice", "Bob"]);
check("context: music off", contextOf({ artist: "A", title: "T" }, [], false, true), null);
check("context: call off", contextOf({ artist: "A", title: "T" }, call, true, false).with, []);
check("context: nothing playing, nobody there", contextOf({ artist: "", title: "" }, [], true, true), null);
check("context: a song with no artist", contextOf({ title: "Untitled" }, [], true, true), { artist: "", title: "Untitled", with: [] });
check("context: control and bidi characters are removed", contextOf({ artist: "A\u202eB", title: "T\u0007" }, [], true, true).artist, "AB");
check("context: a name is cut at 64", contextOf({ title: "x".repeat(200) }, [], true, true).title.length, 64);
check("line: both", contextLine({ artist: "A", title: "T", with: ["X", "Y"] }), "♪ A — T  ·  with X, Y");
check("line: only company", contextLine({ artist: "", title: "", with: ["X"] }), "with X");
check("line: only a song, no artist", contextLine({ artist: "", title: "T", with: [] }), "♪ T");
check("line: none", contextLine(null), "");
check("book: keeps good entries", cleanBook({ paths: { "/a.mp4": { artist: "A", title: "T", with: ["X"] } } }),
      { "/a.mp4": { artist: "A", title: "T", with: ["X"] } });
check("book: a relative path is dropped", Object.keys(cleanBook({ paths: { "a.mp4": { title: "T" } } })), []);
check("book: an empty entry is dropped", Object.keys(cleanBook({ paths: { "/a.mp4": { title: "", with: [] } } })), []);
check("book: wrong types are dropped", cleanBook({ paths: { "/a.mp4": { title: 5, with: [1, "Z"] } } }), { "/a.mp4": { artist: "", title: "", with: ["Z"] } });
check("book: garbage", cleanBook("x"), {});
check("book: people capped at 8", cleanBook({ paths: { "/a": { with: "abcdefghijkl".split("") } } })["/a"].with.length, 8);
const big = {}; for (let i = 0; i < 5100; i++) big["/p" + i] = { title: "t" };
check("book: the latest 5000 are kept", [Object.keys(cleanBook({ paths: big })).length, Object.keys(cleanBook({ paths: big }))[0]], [5000, "/p100"]);
const ctxv = { "/c/a": { artist: "Daft Punk", title: "Around", with: ["Alice"] } };
check("library: search finds the song", libraryView([mk("a", 1, 1), mk("b", 2, 1)], "daft", "all", [], "newest", "", T0, ctxv).map(c => c.name), ["a"]);
check("library: search finds the company", libraryView([mk("a", 1, 1), mk("b", 2, 1)], "alice", "all", [], "newest", "", T0, ctxv).map(c => c.name), ["a"]);
check("library: no context is the old behaviour", libraryView([mk("a", 1, 1), mk("b", 2, 1)], "", "all", [], "newest", "", T0).length, 2);

// ── "Did what I show change" ────────────────────────────────────────────────
check("sig: same list, same signature", listSig(L, 3), listSig(L.slice(), 3));
check("sig: a later entry changing is not seen", listSig(L, 2), listSig(L.slice(0, 2).concat([mk("z", 1, 1)]), 2));
check("sig: a new first entry is", listSig(L, 3) !== listSig([mk("z", 0.1, 1)].concat(L), 3), true);
check("sig: a thumbnail arriving is", listSig([mk("a", 1, 1)], 1) !== listSig([mk("a", 1, 1, { thumb: "/t.jpg" })], 1), true);
check("sig: garbage", listSig(null, 3), "");

// ── Rows for a virtual list ──────────────────────────────────────────────────
const gA = { key: "d1", label: "Today", clips: [1, 2, 3, 4, 5].map(i => ({ path: "/r/" + i, size: GB, duration: 60 })) };
const gB = { key: "d2", label: "Yesterday", clips: [{ path: "/r/6", size: 0, duration: 0 }] };
const rows = layoutRows([gA, gB], 2);
check("rows: a heading, then rows of two, then the next day", rows.map(r => r.kind + ":" + (r.clips ? r.clips.length : r.label)),
      ["head:Today", "row:2", "row:2", "row:1", "head:Yesterday", "row:1"]);
check("rows: heading carries the weight", [rows[0].count, rows[0].bytes, rows[0].secs], [5, 5 * GB, 300]);
check("rows: keys are unique", new Set(rows.map(r => r.key)).size, rows.length);
check("rows: an unlabelled group has no heading", layoutRows([{ key: "all", label: "", clips: gA.clips }], 3).map(r => r.kind), ["row", "row"]);
check("rows: a bad column count is one", layoutRows([gB], 0).length, 2);
check("rows: nothing", layoutRows(null, 3), []);
check("rows: an empty group is skipped", layoutRows([{ key: "x", label: "Empty", clips: [] }], 3), []);
check("line: plural", groupLine(5, 5 * GB, 300), "5 clips · 5 GB · 5:00");
check("line: one, no footage", groupLine(1, 412 * MB, 0), "1 clip · 412 MB");

// ── Tags ─────────────────────────────────────────────────────────────────────
check("tag: trimmed and collapsed", cleanTag("  to   edit "), "to edit");
check("tag: cut at 24", cleanTag("x".repeat(40)).length, 24);
check("tag: control characters go", cleanTag("a\u202eb\u0007"), "ab");
check("tag: not a string", cleanTag(5), "");
let tb = withTag({}, ["/a", "/b"], "Clutch");
check("tag: added to every path", tb, { "/a": ["Clutch"], "/b": ["Clutch"] });
check("tag: the same tag in another case is the same", withTag(tb, ["/a"], "clutch")["/a"], ["Clutch"]);
check("tag: six at most", withTag({ "/a": ["1", "2", "3", "4", "5", "6"] }, ["/a"], "7")["/a"].length, 6);
check("tag: a relative path is ignored", withTag({}, ["a"], "x"), {});
check("tag: an empty tag changes nothing", withTag(tb, ["/a"], "  "), tb);
check("tag: removed from the ones named", withoutTag(tb, ["/a"], "CLUTCH"), { "/b": ["Clutch"] });
check("tag: removal leaves other tags", withoutTag({ "/a": ["x", "y"] }, ["/a"], "x"), { "/a": ["y"] });
check("tag: input is not mutated", tb, { "/a": ["Clutch"], "/b": ["Clutch"] });
check("tags: a trashed path is gone", withoutAll({ "/a": ["x"], "/b": ["y"] }, ["/a"]), { "/b": ["y"] });
check("tags: counted, most first", tagCounts({ "/a": ["x", "y"], "/b": ["y"] }, null), [{ tag: "y", count: 2 }, { tag: "x", count: 1 }]);
check("tags: counted for a selection", tagCounts({ "/a": ["x", "y"], "/b": ["y"] }, ["/a"]).map(t => t.tag), ["x", "y"]);
check("tags: cleaned at the door", cleanTagBook({ paths: { "/a": ["ok", "OK", "", 5, "\u0007"], "b": ["no"], "/c": "x" } }), { "/a": ["ok"] });
check("tags: garbage", cleanTagBook(7), {});
const tview = [mk("a", 1, 1), mk("b", 2, 1), mk("c", 3, 1)];
const tbook = { "/c/a": ["clutch"], "/c/b": ["funny", "clutch"] };
check("library: filter by tag", libraryView(tview, "", "all", [], "newest", "", T0, null, { tag: "clutch", tags: tbook }).map(c => c.name), ["a", "b"]);
check("library: search finds a tag", libraryView(tview, "fun", "all", [], "newest", "", T0, null, { tags: tbook }).map(c => c.name), ["b"]);
const sbook = { "/c/a": { artist: "A", title: "T", with: [] }, "/c/b": { artist: "", title: "", with: ["X"] } };
check("library: only clips with a song", libraryView(tview, "", "all", [], "newest", "", T0, sbook, { stamp: "music" }).map(c => c.name), ["a"]);
check("library: only clips with company", libraryView(tview, "", "all", [], "newest", "", T0, sbook, { stamp: "call" }).map(c => c.name), ["b"]);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail > 0 ? 1 : 0);
