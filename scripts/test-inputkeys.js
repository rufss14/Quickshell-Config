// ── test-inputkeys.js ─────────────────────────────────────────────────────────
// Tests for services/inputkeys.js: the HUD input overlay's Lua hook, and the parser for
// what comes back.
//
//     bun scripts/test-inputkeys.js          (or: node scripts/test-inputkeys.js)
//
// Safe to run: pure functions, plus lua5.4 on a STUB `hl` in a child process — it never
// touches Hyprland. The Lua runs inside the compositor on the input path, so it is
// parsed AND executed here. The point most worth pinning: a key that isn't drawn is never
// NAMED outside the compositor (its press goes out as a bare count, for keys-per-second). Skipped (said so) if lua5.4 isn't installed.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { spawnSync } from "child_process";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "inputkeys.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const K = new Function(src + `
    return { PREFIX, ANON, XKB_OFFSET, KEYS, BUTTONS, IDS, COLS, ROWS, WINDOW_MS, INSTALL_LUA, REMOVE_LUA, parse, apply, counts, prune, LAYOUTS, LAYOUT_IDS, DEFAULT_LAYOUT, DEF, layoutOf, installLua, isLayout };`)();

let pass = 0;
const failures = [];
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { pass++; return; }
    failures.push(`  ${name}\n      want ${w}\n      got  ${g}`);
}

// ── The table ─────────────────────────────────────────────────────────────────
check("ids are unique", new Set(K.IDS).size, K.IDS.length);
const allCodes = K.KEYS.flatMap(k => k.codes);
check("keycodes are unique", new Set(allCodes).size, allCodes.length);
check("every key fits the block",
      K.KEYS.filter(k => k.x < 0 || k.x + k.w > K.COLS + 1e-9 || k.y < 0 || k.y >= K.ROWS).map(k => k.id), []);
check("no two keys overlap in a row",
      K.KEYS.filter(a => K.KEYS.some(b => a !== b && a.y === b.y && a.x < b.x + b.w && b.x < a.x + a.w)).map(k => k.id), []);

// ── The layouts ───────────────────────────────────────────────────────────────
check("five layouts, the default first", K.LAYOUT_IDS, ["wasd", "gaming", "compact", "tkl", "full"]);
check("the default is the old three-row board", [K.layoutOf("wasd").keys.length, K.layoutOf("wasd").cols, K.layoutOf("wasd").rows], [12, 5.75, 3]);
check("an unknown layout is the default", K.layoutOf("nope").id, "wasd");
check("isLayout", [K.isLayout("full"), K.isLayout("x"), K.isLayout(undefined)], [true, false, false]);
for (const id of K.LAYOUT_IDS) {
    const L = K.layoutOf(id);
    check(`${id}: every key is in the table`, L.keys.filter(k => !K.DEF[k.id]).map(k => k.id), []);
    const byId = {};
    for (const k of L.keys) byId[k.id] = JSON.stringify(k.codes);
    const codes = Object.keys(byId).flatMap(i => JSON.parse(byId[i]));
    check(`${id}: a keycode names one id`, new Set(codes).size, codes.length);
    check(`${id}: every key fits`, L.keys.filter(k => k.x < 0 || k.y < 0 || k.x + k.w > L.cols + 1e-9 || k.y + k.h > L.rows + 1e-9).map(k => k.id), []);
    check(`${id}: no two keys overlap`,
          L.keys.filter((a, i) => L.keys.some((b, j) => i !== j && a.x < b.x + b.w - 1e-9 && b.x < a.x + a.w - 1e-9 && a.y < b.y + b.h - 1e-9 && b.y < a.y + a.h - 1e-9)).map(k => k.id), []);
}
// "all" must mean all: every letter and digit of the main block is there.
const typing = "abcdefghijklmnopqrstuvwxyz".split("").concat("0123456789".split("").map(d => "n" + d));
for (const id of K.LAYOUT_IDS.filter(i => K.layoutOf(i).exposes === "all"))
    check(`${id}: exposes "all" keys, so it draws every letter and digit`, typing.filter(t => !K.layoutOf(id).keys.some(k => k.id === t)), []);
check("the small layouts do not draw every letter",
      K.LAYOUT_IDS.filter(i => K.layoutOf(i).exposes !== "all" && typing.every(t => K.layoutOf(i).keys.some(k => k.id === t))), []);
check("full has 104 keys' worth of caps", K.layoutOf("full").keys.length, 104);

// ── parse ─────────────────────────────────────────────────────────────────────
check("a key down", K.parse("qs-input:dw"), { id: "w", down: true });
check("a key up", K.parse("qs-input:uspace"), { id: "space", down: false });
check("a mouse button", K.parse("qs-input:dlmb"), { id: "lmb", down: true });
check("an id that is no key at all", K.parse("qs-input:dzz"), null);
check("any key of the table is a valid id (the layout decides what is drawn)", K.parse("qs-input:dt"), { id: "t", down: true });
check("a bad state", K.parse("qs-input:xw"), null);
check("empty", K.parse("qs-input:"), null);
check("someone else's event", K.parse("qs-sfx-key:dk"), null);
check("not a string", K.parse(undefined), null);
check("an undrawn key's press", K.parse(K.ANON), { anon: true });

// ── apply ─────────────────────────────────────────────────────────────────────
const h0 = {};
const h1 = K.apply(h0, { id: "w", down: true });
check("a press holds", h1, { w: true });
check("it is a new object (a binding notices)", h1 !== h0 && Object.keys(h0).length === 0, true);
const h2 = K.apply(K.apply(h1, { id: "lmb", down: true }), { id: "w", down: false });
check("a release lets go of that one only", h2, { lmb: true });
check("a release of something not held is harmless", K.apply({}, { id: "q", down: false }), {});

// ── counts / prune ────────────────────────────────────────────────────────────
check("what each press counts toward",
      ["qs-input:dlmb", "qs-input:drmb", "qs-input:dw", "qs-input:dspace", K.ANON,
       "qs-input:ulmb", "qs-input:uw", "qs-input:dmmb", "qs-input:dm4"].map(d => K.counts(K.parse(d))),
      ["left", "right", "keys", "keys", "keys", "", "", "", ""]);
check("nothing counts for nothing", K.counts(null), "");
check("prune keeps the last second", K.prune([0, 500, 1000, 1500, 1999], 2000), [1000, 1500, 1999].filter(t => t > 2000 - K.WINDOW_MS));
check("prune with nothing stale returns the same array", (() => { const a = [1500, 1900]; return K.prune(a, 2000) === a })(), true);
check("prune empties when you stop", K.prune([100, 200], 5000), []);

// ── The Lua ───────────────────────────────────────────────────────────────────
const lua = spawnSync("lua5.4", ["-v"]);
if (lua.error) {
    console.log("SKIP the Lua checks: lua5.4 not installed");
} else {
    // A stub `hl` that records what the snippet subscribes to, binds and dispatches.
    // `sent` is what would have gone out on Hyprland's event socket.
    function run(events, extra = "", install = K.INSTALL_LUA) {
        const prog = `
            local sent, keycb, binds, handles = {}, nil, {}, {}
            local function handle() local h = { removed = false }; function h:remove() self.removed = true end; handles[#handles + 1] = h; return h end
            hl = {
                on = function(name, f) assert(name == "input.keyboard.key"); keycb = f; return handle() end,
                bind = function(key, f, opts) binds[#binds + 1] = { key = key, f = f, opts = opts or {} }; return handle() end,
                dispatch = function(d) sent[#sent + 1] = d end,
                dsp = { event = function(s) return s end },
            }
            local function press(key, release)
                for _, b in ipairs(binds) do
                    if b.key == key and (b.opts.release == true) == release then b.f() end
                end
            end
            ${extra}
            local ok, err = pcall(function() ${install}\n end)
            if not ok then print("INSTALL-ERROR " .. tostring(err)); os.exit(0) end
            ${events}
            for _, s in ipairs(sent) do print(s) end
        `;
        const r = spawnSync("lua5.4", ["-e", prog], { encoding: "utf8" });
        if (r.status !== 0) return ["LUA-ERROR " + r.stderr];
        return r.stdout.split("\n").filter(Boolean);
    }

    // Hyprland's key event carries evdev + XKB_OFFSET; `kc(evdev)` is what it would send.
    const kc = c => c + K.XKB_OFFSET;
    check("installs cleanly", run(""), []);
    check("W down and up (time, keycode, state)",
          run(`keycb(123456789, ${kc(17)}, 1); keycb(123456790, ${kc(17)}, 0)`), ["qs-input:dw", "qs-input:uw"]);
    check("the order of the numbers doesn't matter",
          run(`keycb(1, ${kc(57)}, 123456789)`), ["qs-input:dspace"]);
    check("a key that isn't drawn is counted, never named (T, Enter, 1)",
          run(`keycb(5, ${kc(20)}, 1); keycb(5, ${kc(28)}, 1); keycb(5, ${kc(2)}, 1)`), [K.ANON, K.ANON, K.ANON]);
    check("…and its release isn't sent at all", run(`keycb(5, ${kc(20)}, 0)`), []);
    check("a plain evdev code is NOT a drawn key (what the socket recording caught)",
          run("keycb(5, 17, 1); keycb(5, 57, 1)"), [K.ANON, K.ANON]);
    check("both shifts and both ctrls light the same cap",
          run(`keycb(5, ${kc(42)}, 1); keycb(5, ${kc(54)}, 1); keycb(5, ${kc(29)}, 1); keycb(5, ${kc(97)}, 1)`),
          ["qs-input:dshift", "qs-input:dshift", "qs-input:dctrl", "qs-input:dctrl"]);
    check("a payload it can't place sends nothing",
          run('keycb({ key = "w" }); keycb("w"); keycb()'), []);
    check("an error inside the callback stays inside", run(`keycb(5, ${kc(17)}, 1)`,
          'hl.dsp.event = function() error("boom") end'), []);

    // The crash this guards: a runtime hl.bind from `hyprctl eval` segfaulted Hyprland
    // 0.56.2 on re-install. The install must never bind, nor call anything on a keybind.
    check("the install never calls hl.bind", run('', 'hl.bind = function() error("BOUND") end'), []);
    check("…nor does a re-install over an install", run(K.INSTALL_LUA, 'hl.bind = function() error("BOUND") end'), []);
    check("it switches the static mouse binds on",
          run('print("ON=" .. tostring(_G.qs_input_on))'), ["ON=true"]);
    check("removing switches them off",
          run(K.REMOVE_LUA + '\nprint("ON=" .. tostring(_G.qs_input_on))'), ["ON=false"]);

    // What the first build left behind: [1] its key subscription, then runtime keybinds.
    // Only [1] may be touched.
    const legacy = `local kb = {}
        local trap = setmetatable({}, { __index = function() error("TOUCHED A KEYBIND") end })
        local sub1 = { removed = false }; function sub1:remove() self.removed = true end
        _G.qs_input_subs = { sub1, trap, trap }`;
    check("an old install: its subscription is removed, its keybinds never touched",
          run('print("SUB1=" .. tostring(sub1.removed) .. " LEFT=" .. tostring(_G.qs_input_subs))', legacy),
          ["SUB1=true LEFT=nil"]);

    const removed = `for i, h in ipairs(handles) do print("H" .. i .. "=" .. tostring(h.removed)) end`;
    check("a reinstall removes the earlier subscription first",
          run(K.INSTALL_LUA + "\n" + removed), ["H1=true", "H2=false"]);
    check("removing removes it",
          run(K.REMOVE_LUA + "\n" + removed).filter(l => l.endsWith("=false")).length, 0);

    // The static block in hypr/binds.lua, run as Hyprland would at config load.
    const binds = readFileSync(join(here, "..", "hypr", "binds.lua"), "utf8");
    const m = binds.match(/-- >>> qs-input[^\n]*\n([\s\S]*?)-- <<< qs-input/);
    check("hypr/binds.lua has the input overlay block", !!m, true);
    if (m) {
        const block = m[1];
        const listed = run(`${block}
            for _, b in ipairs(binds) do
                print("BIND " .. b.key .. " nc=" .. tostring(b.opts.non_consuming) .. " im=" .. tostring(b.opts.ignore_mods) .. " rel=" .. tostring(b.opts.release == true))
            end`, "", "").filter(l => l.startsWith("BIND"));
        check("a press and a release bind per button", listed.length, K.BUTTONS.length * 2);
        check("every bind lets the click through, with any modifier", listed.filter(l => !/nc=true im=true/.test(l)), []);
        check("silent while the overlay is off",
              run(`${block}\n_G.qs_input_on = false; press("mouse:272", false); press("mouse:272", true)`, "", ""), []);
        check("every button down and up, named as the shell expects",
              run(`${block}\n_G.qs_input_on = true
                   for _, n in ipairs({ 272, 273, 274, 275, 276 }) do press("mouse:" .. n, false); press("mouse:" .. n, true) end`, "", "")
                  .map(K.parse).map(e => e && (e.down ? "d" : "u") + e.id),
              K.BUTTONS.flatMap(b => ["d" + b.id, "u" + b.id]));
    }
    // Each layout's hook names ITS keys (and counts the rest, unnamed) — the privacy promise.
    for (const id of K.LAYOUT_IDS) {
        const L = K.layoutOf(id);
        const inLayout = [...new Map(L.keys.map(k => [k.id, k])).values()];
        const outLayout = Object.values(K.DEF).filter(d => !inLayout.some(k => k.id === d.id));
        check(`${id}: every key it draws is named down`,
              run(inLayout.map(k => `keycb(5, ${kc(k.codes[0])}, 1)`).join("; "), "", K.installLua(id)),
              inLayout.map(k => "qs-input:d" + k.id));
        check(`${id}: a key it does not draw is only counted`,
              run(outLayout.slice(0, 6).map(d => `keycb(5, ${kc(d.codes[0])}, 1)`).join("; "), "", K.installLua(id)),
              outLayout.slice(0, 6).map(() => K.ANON));
    }
    check("removing when nothing is installed is harmless", run("", "", K.REMOVE_LUA), []);
}

console.log(`${pass} passed, ${failures.length} failed`);
if (failures.length) { console.log(failures.join("\n")); process.exit(1); }
