// ── test-launcher.js ──────────────────────────────────────────────────────────
// Regression tests for services/launcher.js, the launcher's search and Enter logic.
//
//     bun scripts/test-launcher.js          (or: node scripts/test-launcher.js)
//
// Safe to run: launcher.js is pure functions and touches nothing.
//
// Ranking is a matter of taste until it has cases. The ones that matter most are the
// ORDERING rules — a better kind of match always beats a worse one, and history and
// pins only break ties inside a kind — because those are what make a launcher feel
// predictable, and they're the ones a "small tweak" quietly breaks.
//
// launcher.js is loaded by stripping its `.pragma library` line (a QML directive that
// isn't valid JS), so the tests run against the real file rather than a copy.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "launcher.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");

const L = new Function(src + `
return { scoreText, execName, buildIndex, search, highlight, modeFor, enterAction,
         cleanHistory, frecency, recordLaunch, capKinds, forget, cleanShortcuts, webShortcut,
         groupResults, bodyHeight, searchClip, searchEmoji, pushRecent };`)();

const DAY = 86400000;
const NOW = 1_800_000_000_000;

const apps = L.buildIndex([
    { id: "firefox.desktop", name: "Firefox", genericName: "Web Browser",
      comment: "Browse the World Wide Web", keywords: ["internet", "www"],
      execString: "/usr/lib/firefox/firefox %u" },
    { id: "firefox-dev.desktop", name: "Firefox Developer Edition", genericName: "Web Browser",
      execString: "firefox-developer-edition %u" },
    { id: "code.desktop", name: "Visual Studio Code", genericName: "Text Editor",
      comment: "Code editing. Redefined.", execString: "/usr/bin/code --unity-launch %F" },
    { id: "org.gnome.Terminal.desktop", name: "Terminal", genericName: "Terminal Emulator",
      execString: "env FOO=1 gnome-terminal" },
    { id: "kitty.desktop", name: "kitty", genericName: "Terminal emulator", execString: "kitty" },
    { id: "files.desktop", name: "Files", genericName: "File Manager", execString: "nautilus" },
    { id: "2048.desktop", name: "2048", genericName: "Game", execString: "2048-qt" },
    { id: "hidden.desktop", name: "Firefox Secret", noDisplay: true, execString: "x" },
    { id: "calc.desktop", name: "Calculator", execString: "gnome-calculator" },
    { id: "ark.desktop", name: "Ark", execString: "ark" },
]);

const top = (q, ctx) => L.search(apps, q, Object.assign({ now: NOW }, ctx)).map(h => h.id);
const first = (q, ctx) => top(q, ctx)[0];

let pass = 0;
const failures = [];
function check(label, ok, detail) {
    if (ok) pass++;
    else failures.push(`  ${label}${detail ? "  — " + detail : ""}`);
}
const eq = (label, got, want) =>
    check(label, JSON.stringify(got) === JSON.stringify(want),
          `want ${JSON.stringify(want)}  got ${JSON.stringify(got)}`);

// ── Match kinds, in order ─────────────────────────────────────────────────────
eq("empty query shows nothing", top(""), []);
eq("whitespace shows nothing", top("   "), []);
eq("exact name", first("files"), "files.desktop");
eq("prefix", first("fire"), "firefox.desktop");
eq("case does not matter", first("FIREFOX"), "firefox.desktop");
eq("word start", first("studio"), "code.desktop");
eq("initials", first("vsc"), "code.desktop");
eq("substring", first("irefo"), "firefox.desktop");
eq("fuzzy subsequence", first("frfx"), "firefox.desktop");
eq("two letters are not fuzzy", top("fx"), []);
eq("no match", top("zzzzz"), []);
eq("noDisplay is never offered", top("secret"), []);

// ── Other fields find an app, but rank below its name ─────────────────────────
check("generic name finds it", top("browser").includes("firefox.desktop"));
check("keyword finds it", top("internet").includes("firefox.desktop"));
eq("exec name finds an app named otherwise", first("gnome-terminal"), "org.gnome.Terminal.desktop");
eq("exec name: code → VS Code", first("code"), "code.desktop");
check("comment word start finds it", top("browse").includes("firefox.desktop"));
check("comment mid-word does not", !top("owse").includes("firefox.desktop"));
{
    // An app NAMED Browser beats one that merely calls itself a "Web Browser".
    const idx = L.buildIndex([
        { id: "a", name: "Chromium", genericName: "Web Browser", execString: "c" },
        { id: "b", name: "Browser Tool", execString: "b" },
    ]);
    eq("name beats generic name", L.search(idx, "browser", { now: NOW })[0].id, "b");
}

// ── Length tiebreak ───────────────────────────────────────────────────────────
eq("shorter name first on equal prefix", top("firefox").slice(0, 2),
   ["firefox.desktop", "firefox-dev.desktop"]);

// ── Several words are an AND, in any order ────────────────────────────────────
eq("two words", first("visual code"), "code.desktop");
eq("two words, other order", first("code visual"), "code.desktop");
eq("one word missing → no match", top("visual banana"), []);
eq("multi-word name as a phrase", first("developer edition"), "firefox-dev.desktop");

// ── History and pins break ties, never tiers ──────────────────────────────────
{
    const history = { "firefox-dev.desktop": { n: 40, last: NOW - DAY } };
    eq("history reorders equal matches",
       top("fire", { history }).slice(0, 2), ["firefox-dev.desktop", "firefox.desktop"]);
}
{
    // Forty launches of a mere word-start match must not outrank the exact name.
    const history = { "code.desktop": { n: 500, last: NOW } };
    const idx = L.buildIndex([
        { id: "code.desktop", name: "Code Editor Studio", execString: "x" },
        { id: "studio.desktop", name: "Studio", execString: "y" },
    ]);
    eq("history cannot lift a worse match over an exact one",
       L.search(idx, "studio", { now: NOW, history })[0].id, "studio.desktop");
    eq("pin cannot either",
       L.search(idx, "studio", { now: NOW, pinned: ["code.desktop"] })[0].id, "studio.desktop");
}
eq("pinned breaks a tie", top("fire", { pinned: ["firefox-dev.desktop"] })[0], "firefox-dev.desktop");
{
    const fresh = { "kitty.desktop": { n: 3, last: NOW } };
    const stale = { "kitty.desktop": { n: 3, last: NOW - 200 * DAY } };
    check("frecency decays", L.frecency(fresh["kitty.desktop"], NOW)
                           > L.frecency(stale["kitty.desktop"], NOW) * 100);
    eq("unknown id has none", L.frecency(undefined, NOW), 0);
}

// ── Numbers are searchable (the calculator must not hide the game) ────────────
eq("2048 is an app", first("2048"), "2048.desktop");

// ── limit ─────────────────────────────────────────────────────────────────────
eq("limit", L.search(apps, "e", { now: NOW, limit: 2 }).length <= 2, true);

// ── Ranges for highlighting ───────────────────────────────────────────────────
eq("prefix range", L.search(apps, "fire", { now: NOW })[0].ranges, [[0, 4]]);
eq("keyword hit highlights nothing", L.search(apps, "internet", { now: NOW })[0].ranges, []);
eq("fuzzy ranges", L.scoreText("firefox", "frfx").ranges, [[0, 1], [2, 3], [4, 5], [6, 7]]);
eq("fuzzy ranges merge", L.scoreText("firefox", "frefx").ranges, [[0, 1], [2, 5], [6, 7]]);
eq("exact beats prefix even with history",
   top("firefox", { history: { "firefox-dev.desktop": { n: 999, last: NOW } } })[0], "firefox.desktop");
eq("initials ranges", L.scoreText("visual studio code", "vsc").ranges, [[0, 1], [7, 8], [14, 15]]);
eq("highlight wraps", L.highlight("Firefox", [[0, 4]], "<b>", "</b>"), "<b>Fire</b>fox");
eq("highlight escapes markup", L.highlight("<b>x</b>", [], "<i>", "</i>"), "&lt;b&gt;x&lt;/b&gt;");
eq("highlight escapes inside a span", L.highlight("a&b", [[0, 3]], "[", "]"), "[a&amp;b]");
eq("highlight ignores out-of-range", L.highlight("ab", [[0, 9]], "[", "]"), "ab");

// ── execName ──────────────────────────────────────────────────────────────────
eq("execName path", L.execName("/usr/bin/code --unity-launch %F"), "code");
eq("execName env", L.execName("env FOO=1 BAR=2 gnome-terminal"), "gnome-terminal");
eq("execName quoted", L.execName('"/opt/My App/run" %U'), "run");
eq("execName quoted, first word of the path is not the name", L.execName("'/opt/a b/c d' x"), "c d");
eq("execName empty", L.execName(""), "");
eq("execName undefined", L.execName(undefined), "");

// ── History is untrusted input ────────────────────────────────────────────────
eq("cleanHistory keeps good", L.cleanHistory({ a: { n: 2, last: 5 } }), { a: { n: 2, last: 5 } });
eq("cleanHistory drops bad", L.cleanHistory({ a: { n: 0, last: 5 }, b: { n: "x", last: 1 },
                                              c: null, d: { n: 1 } }), {});
eq("cleanHistory array", L.cleanHistory([1, 2]), {});
eq("cleanHistory null", L.cleanHistory(null), {});
eq("cleanHistory clamps", L.cleanHistory({ a: { n: 1e12, last: 1 } }).a.n, 100000);
{
    const h = JSON.parse('{"__proto__": {"n": 1, "last": 1}, "ok": {"n": 1, "last": 1}}');
    eq("cleanHistory refuses __proto__", Object.keys(L.cleanHistory(h)), ["ok"]);
}
{
    let h = {};
    h = L.recordLaunch(h, "a", NOW);
    h = L.recordLaunch(h, "a", NOW + 1);
    eq("recordLaunch counts", h.a, { n: 2, last: NOW + 1 });
    eq("recordLaunch is pure", L.recordLaunch(h, "b", NOW).a, h.a);
    eq("recordLaunch ignores empty id", L.recordLaunch(h, "", NOW), h);
    let big = {};
    for (let i = 0; i < 400; i++) big = L.recordLaunch(big, "app" + i, NOW + i);
    eq("history is bounded", Object.keys(big).length, 300);
    big = L.recordLaunch(big, "app0", NOW + 999);
    eq("bounded history keeps the strongest", "app399" in big, true);
}

// ── Modes and Enter ───────────────────────────────────────────────────────────
eq("> is run", L.modeFor(">"), "run");
eq("? is ask", L.modeFor("?"), "ask");
eq("anything else is none", L.modeFor("a"), "");
eq("empty char is none", L.modeFor(""), "");

const E = (s) => L.enterAction(Object.assign({ mode: "", text: "", chatting: false, results: 0, calc: false }, s));
eq("enter: nothing", E({}), "");
eq("enter: run needs a command", E({ mode: "run", text: "  " }), "");
eq("enter: run", E({ mode: "run", text: "htop" }), "run");
eq("enter: run beats results", E({ mode: "run", text: "htop", results: 3 }), "run");
eq("enter: ask", E({ mode: "ask", text: "why" }), "ask");
eq("enter: ask needs a question", E({ mode: "ask", text: "" }), "");
eq("enter: chat follow-up", E({ chatting: true, text: "and then?" }), "ask");
eq("enter: chat with empty field is nothing", E({ chatting: true, text: "" }), "");
eq("enter: launch", E({ text: "fire", results: 2 }), "launch");
eq("enter: calc when no app", E({ text: "2+2", calc: true }), "copy");
eq("enter: app wins over calc", E({ text: "2048", calc: true, results: 1 }), "launch");
eq("+ is packages", L.modeFor("+"), "pkg");
eq("enter: install the pick", E({ mode: "pkg", text: "fire", results: 3 }), "install");
eq("enter: nothing to install", E({ mode: "pkg", text: "zzz", results: 0 }), "");

// ── Shell actions share the index ─────────────────────────────────────────────
{
    const idx = L.buildIndex([
        { id: "nightlight.desktop", name: "Night Light" },
        { id: "action:nightlight", name: "Night light", keywords: ["warm", "redshift"], kind: "action", penalty: 5 },
        { id: "action:lock", name: "Lock screen", kind: "action", penalty: 5 },
        { id: "locker.desktop", name: "Lockbox Password Manager" },
        { id: "action:huge", name: "Huge", kind: "action", penalty: 500 },
    ]);
    const s1 = L.search(idx, "night light", { now: NOW });
    eq("tie: the app before the action", s1.map(h => h.id).slice(0, 2), ["nightlight.desktop", "action:nightlight"]);
    eq("kind travels with the hit", s1[1].kind, "action");
    eq("an action's keyword finds it", L.search(idx, "redshift", { now: NOW })[0]?.id, "action:nightlight");
    eq("a better match still wins across kinds", L.search(idx, "lock screen", { now: NOW })[0]?.id, "action:lock");
    const hist = { "action:nightlight": { n: 30, last: NOW } };
    eq("history lifts an action within the tier", L.search(idx, "night light", { now: NOW, history: hist })[0]?.id,
       "action:nightlight");
    eq("penalty is clamped under a tier", L.buildIndex([{ id: "a", name: "a", penalty: 500 }])[0].penalty, 9);
    eq("apps default to kind app", idx[0].kind, "app");
    const capped = L.capKinds([{ kind: "app" }, { kind: "action" }, { kind: "action" }, { kind: "app" }, { kind: "action" }],
                              { action: 2 });
    eq("capKinds keeps order and caps a kind", capped.map(h => h.kind), ["app", "action", "action", "app"]);
}


// ── 2026-11: modes, shortcuts, groups, clipboard, emoji ──────────────────────
{
    eq("; is the clipboard mode", L.modeFor(";"), "clip");
    eq(": is the emoji mode", L.modeFor(":"), "emoji");
    eq("a letter is no mode", L.modeFor("a"), "");
    eq("clip: Enter picks", L.enterAction({ mode: "clip", text: "", results: 2 }), "pick");
    eq("emoji: nothing to pick, nothing to do", L.enterAction({ mode: "emoji", text: "zz", results: 0 }), "");

    const h = { a: { n: 3, last: NOW }, b: { n: 1, last: NOW } };
    eq("forget drops one id", Object.keys(L.forget(h, "a")), ["b"]);
    eq("forget leaves the original alone", Object.keys(h), ["a", "b"]);
    eq("forget of a stranger changes nothing", L.forget(h, "zzz"), h);

    const sc = L.cleanShortcuts([
        { key: "YT", name: "YouTube", url: "https://www.youtube.com/results?search_query=%s" },
        { key: "yt", name: "dup", url: "https://dup.example/?q=%s" },
        { key: "bad key", url: "https://x.example/?q=%s" },
        { key: "js", url: "javascript:alert(%s)" },
        { key: "file", url: "file:///etc/passwd?%s" },
        { key: "nos", url: "https://x.example/" },
        { key: "gh", url: "https://github.com/search?q=%s" },
        null, 7,
    ]);
    eq("shortcuts: valid ones survive, keys lowercased, dups dropped", sc.map(x => x.key), ["yt", "gh"]);
    eq("shortcuts: a missing name falls back to the key", sc[1].name, "gh");
    eq("shortcuts: junk in, empty out", L.cleanShortcuts("nope"), []);

    const w = L.webShortcut("yt cats & dogs", sc);
    eq("web: query is encoded", w && w.url, "https://www.youtube.com/results?search_query=cats%20%26%20dogs");
    eq("web: query and name", w && [w.query, w.name], ["cats & dogs", "YouTube"]);
    eq("web: key alone is not a search", L.webShortcut("yt", sc), null);
    eq("web: key plus spaces alone is not a search", L.webShortcut("yt   ", sc), null);
    eq("web: unknown key", L.webShortcut("zz cats", sc), null);
    eq("web: key is case-blind", L.webShortcut("GH quickshell", sc)?.query, "quickshell");
    eq("web: $& in a query stays literal", L.webShortcut("gh $& x", sc).url, "https://github.com/search?q=%24%26%20x");

    const rows = [{ kind: "app", id: "a" }, { kind: "action", id: "x" }, { kind: "app", id: "b" }, { kind: "setting", id: "s" }];
    const g = L.groupResults(rows);
    eq("groups: kinds ordered by first appearance, rank kept inside", g.map(r => r.id), ["a", "b", "x", "s"]);
    eq("groups: header on the first of each group", g.map(r => r.groupFirst), [true, false, true, true]);
    eq("groups: labels", g.map(r => r.group), ["Apps", "Apps", "Actions", "Settings"]);
    eq("one kind: no headers at all", L.groupResults([{ kind: "app", id: "a" }, { kind: "app", id: "b" }]).map(r => r.groupFirst), [false, false]);
    eq("groups: input is not mutated", rows[0].group, undefined);

    const o = { rowH: 44, gap: 2, headerH: 24, maxRows: 3, pad: 4 };
    eq("height: none", L.bodyHeight([], o), 0);
    eq("height: one row, no header", L.bodyHeight([{ groupFirst: false }], o), 44 + 8);
    eq("height: headers count", L.bodyHeight(g, o), 3 * 44 + 2 * 2 + 8 + 2 * 24);
    eq("height: capped at maxRows (the 4th row scrolls)", L.bodyHeight(g, Object.assign({}, o, { maxRows: 2 })), 2 * 44 + 2 + 8 + 24);

    const clip = [
        { label: "ssh root@host", text: "ssh root@host" },
        { label: "Image", text: "image" },
        { label: "Hello World", text: "Hello World\nsecond line about SSH" },
    ];
    eq("clip: no query is the newest", L.searchClip(clip, "", 2).map(r => r.i), [0, 1]);
    eq("clip: case-blind, any line", L.searchClip(clip, "ssh", 5).map(r => r.i), [0, 2]);
    eq("clip: every word must match", L.searchClip(clip, "ssh world", 5).map(r => r.i), [2]);
    eq("clip: highlight is in the label", L.searchClip(clip, "world", 5)[0].ranges, [[6, 11]]);
    eq("clip: no match", L.searchClip(clip, "zzz", 5), []);
    eq("clip: limit", L.searchClip(clip, "", 1).length, 1);

    const em = [["\u{1F600}", "grinning face", "Smileys & Emotion"], ["\u{1F525}", "fire", "Travel & Places"],
                ["\u{1F692}", "fire engine", "Travel & Places"], ["\u{1F415}", "dog", "Animals & Nature"],
                ["\u{1F436}", "dog face", "Animals & Nature"], ["\u{1F44D}", "thumbs up", "People & Body"]];
    eq("emoji: exact word beats a longer name", L.searchEmoji(em, "fire", [], 5).map(r => r.i), [1, 2]);
    eq("emoji: every word", L.searchEmoji(em, "thumbs up", [], 5).map(r => r.i), [5]);
    eq("emoji: a group word lists the group", L.searchEmoji(em, "animal", [], 5).map(r => r.i), [3, 4]);
    eq("emoji: substring finds too", L.searchEmoji(em, "rinn", [], 5).map(r => r.i), [0]);
    eq("emoji: a recent is lifted among equals", L.searchEmoji(em, "dog", ["\u{1F436}"], 5).map(r => r.i), [4, 3]);
    eq("emoji: empty query = recents then the top", L.searchEmoji(em, "", ["\u{1F44D}"], 3).map(r => r.i), [5, 0, 1]);
    eq("emoji: a recent that left the list is skipped", L.searchEmoji(em, "", ["x"], 2).map(r => r.i), [0, 1]);
    eq("emoji: highlight", L.searchEmoji(em, "dog", [], 5)[0].ranges, [[0, 3]]);
    eq("recents: moved to front, capped, no twin", L.pushRecent(["a", "b", "c"], "b", 3), ["b", "a", "c"]);
    eq("recents: cap", L.pushRecent(["a", "b", "c"], "d", 3), ["d", "a", "b"]);
}


// ── The bundled emoji list (scripts/gen-emoji.py) ────────────────────────────
{
    const real = JSON.parse(readFileSync(join(here, "..", "services", "emoji.json"), "utf8"));
    check("emoji.json: a real list", Array.isArray(real) && real.length > 1500, `length ${real.length}`);
    check("emoji.json: [char, name, group] strings, no blanks",
          real.every(e => Array.isArray(e) && e.length === 3 && e.every(x => typeof x === "string" && x !== "")));
    check("emoji.json: no skin-tone variants",
          real.every(e => !/[\u{1F3FB}-\u{1F3FF}]/u.test(e[0])));
    check("emoji.json: no twin characters", new Set(real.map(e => e[0])).size === real.length);
    eq("emoji.json: fire finds the fire", real[L.searchEmoji(real, "fire", [], 1)[0].i][0], "\u{1F525}");
}

console.log(`${pass}/${pass + failures.length} passed`);
if (failures.length > 0) {
    console.log("\nFAILED:");
    console.log(failures.join("\n"));
    process.exit(1);
}
