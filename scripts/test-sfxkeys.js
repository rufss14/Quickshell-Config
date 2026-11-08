// ── test-sfxkeys.js ───────────────────────────────────────────────────────────
// Tests for services/sfxkeys.js: the Lua hook Hyprland is handed, and the parser for
// what comes back.
//
//     bun scripts/test-sfxkeys.js          (or: node scripts/test-sfxkeys.js)
//
// Safe to run: pure functions, plus lua5.4 on a STUB `hl` in a child process — it never
// touches Hyprland. The Lua is the part that runs inside the compositor on the input
// path, so it is parsed AND executed here against every payload shape it tries to handle.
// Skipped (said so) if lua5.4 isn't installed.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { spawnSync } from "child_process";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "sfxkeys.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const K = new Function(src + `
    return { PREFIX, SHAPE_PREFIX, SHAPE_REPORTS, INSTALL_LUA, REMOVE_LUA, parse, sounds };`)();

let pass = 0;
const failures = [];
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { pass++; return; }
    failures.push(`  ${name}\n      want ${w}\n      got  ${g}`);
}

// ── parse ─────────────────────────────────────────────────────────────────────
check("a key down", K.parse("qs-sfx-key:dk"), { down: true, cls: "key" });
check("a space down", K.parse("qs-sfx-key:ds"), { down: true, cls: "space" });
check("an enter up", K.parse("qs-sfx-key:ue"), { down: false, cls: "enter" });
check("a backspace, state unknown", K.parse("qs-sfx-key:?b"), { down: null, cls: "back" });
check("a shape report", K.parse("qs-sfx-shape:{a:number}"), { shape: "{a:number}" });
check("a shape report is bounded", K.parse("qs-sfx-shape:" + "x".repeat(900)).shape.length, 400);
check("someone else's custom event", K.parse("other:dk"), null);
check("our prefix, a bad class", K.parse("qs-sfx-key:dz"), null);
check("our prefix, a bad state", K.parse("qs-sfx-key:xk"), null);
check("our prefix, too long (a key's identity can't ride along)", K.parse("qs-sfx-key:dka"), null);
check("our prefix, empty", K.parse("qs-sfx-key:"), null);
check("not a string", K.parse(undefined), null);
check("a release does not sound", K.sounds(K.parse("qs-sfx-key:uk")), false);
check("a press sounds", K.sounds(K.parse("qs-sfx-key:dk")), true);
check("an unknown state sounds", K.sounds(K.parse("qs-sfx-key:?k")), true);
check("a shape report is not a sound", K.sounds(K.parse("qs-sfx-shape:x")), false);
check("garbage is not a sound", K.sounds(null), false);

// ── The Lua ───────────────────────────────────────────────────────────────────
const lua = spawnSync("lua5.4", ["-v"]);
if (lua.error) {
    console.log("SKIP the Lua checks: lua5.4 not installed");
} else {
    // A stub `hl` that records what the snippet subscribes to and dispatches, then feeds
    // it payloads. `sent` is what would have gone out on Hyprland's event socket.
    function run(events, extra = "") {
        const prog = `
            local sent, cb = {}, nil
            local subscription = { removed = false }
            function subscription:remove() self.removed = true end
            hl = {
                on = function(name, f) assert(name == "input.keyboard.key"); cb = f; return subscription end,
                dispatch = function(d) sent[#sent + 1] = d end,
                dsp = { event = function(s) return s end },
            }
            ${extra}
            local ok, err = pcall(function() ${K.INSTALL_LUA}\n end)
            if not ok then print("INSTALL-ERROR " .. tostring(err)); os.exit(0) end
            ${events}
            for _, s in ipairs(sent) do print(s) end
            print("REMOVED=" .. tostring(subscription.removed))
        `;
        const r = spawnSync("lua5.4", ["-e", prog], { encoding: "utf8" });
        if (r.status !== 0) return ["LUA-ERROR " + r.stderr];
        return r.stdout.split("\n").filter(Boolean);
    }
    const keys = out => out.filter(l => l.startsWith(K.PREFIX));
    const shapes = out => out.filter(l => l.startsWith(K.SHAPE_PREFIX));

    check("the install snippet loads and subscribes", run("").some(l => l.startsWith("INSTALL-ERROR")), false);

    // Shape A: a table with a key NAME and a state.
    let o = run(`cb({ key = "a", state = "pressed" }); cb({ key = "a", state = "released" });
                 cb({ key = "space", state = "pressed" }); cb({ key = "Return", state = "pressed" });
                 cb({ key = "BackSpace", state = "pressed" }); cb({ key = "Shift_L", state = "pressed" })`);
    check("named keys: letter down, up, space, enter, backspace; shift silent",
          keys(o), ["qs-sfx-key:dk", "qs-sfx-key:uk", "qs-sfx-key:ds", "qs-sfx-key:de", "qs-sfx-key:db"]);

    // Shape B: a table with a keycode and a boolean. Codes are xkb (evdev + 8), what
    // Hyprland 0.56 sends — measured 2026-10-19 off the event socket: a=38, space=65.
    o = run(`cb({ keycode = 38, pressed = true }); cb({ keycode = 38, pressed = false });
             cb({ keycode = 65, pressed = true }); cb({ keycode = 36, pressed = true });
             cb({ keycode = 22, pressed = true }); cb({ keycode = 50, pressed = true });
             cb({ keycode = 111, pressed = true }); cb({ keycode = 68, pressed = true })`);
    check("keycodes: a, a up, space, enter, backspace; shift, up-arrow, F2 silent",
          keys(o), ["qs-sfx-key:dk", "qs-sfx-key:uk", "qs-sfx-key:ds", "qs-sfx-key:de", "qs-sfx-key:db"]);

    // Shape C: numeric state.
    o = run(`cb({ keycode = 38, state = 1 }); cb({ keycode = 38, state = 0 })`);
    check("numeric state", keys(o), ["qs-sfx-key:dk", "qs-sfx-key:uk"]);

    // Shape E — THE REAL ONE (measured: "number|number|number"): bare numbers, in
    // IKeyboard::SKeyEvent order (timeMs, keycode, state). 4500123 ms, a=38, space=65...
    o = run(`cb(4500123, 38, 1); cb(4500190, 38, 0); cb(4500400, 65, 1); cb(4500460, 65, 0);
             cb(4500600, 36, 1); cb(4500700, 22, 1); cb(4500800, 50, 1); cb(4500900, 111, 1)`);
    check("bare numbers: a down+up (ONE click, not two), space, enter, backspace; shift/up silent",
          keys(o), ["qs-sfx-key:dk", "qs-sfx-key:uk", "qs-sfx-key:ds", "qs-sfx-key:us",
                    "qs-sfx-key:de", "qs-sfx-key:db"]);
    check("…and a release is not a sound once parsed",
          keys(o).map(l => K.sounds(K.parse(l.replace(K.PREFIX, K.PREFIX)))).join(), "true,false,true,false,true,true");

    // The order is placed by magnitude, not trusted: the same events as (keycode, state, time).
    o = run(`cb(38, 1, 4500123); cb(38, 0, 4500190); cb(65, 1, 4500400)`);
    check("bare numbers, another order (keycode, state, time)", keys(o),
          ["qs-sfx-key:dk", "qs-sfx-key:uk", "qs-sfx-key:ds"]);
    // Esc is xkb 9 (evdev 1). It's silent, whatever order the numbers come in.
    o = run(`cb(4500123, 9, 1); cb(4500200, 9, 0)`);
    check("Escape (xkb 9) is silent, not a key", keys(o), []);

    // Not placeable: three smalls (time absent, a mask present) falls back to "unknown".
    o = run(`cb(30, 1, 4); cb(30, 0, 4)`);
    check("an unplaceable triple still sounds, state unknown", keys(o), ["qs-sfx-key:?k", "qs-sfx-key:?k"]);

    // The shape report for the real payload: bucketed, no keycode.
    o = run(`cb(4500123, 30, 1); cb(4500190, 30, 0)`);
    const sh = shapes(o);
    check("the real shape is reported, bucketed",
          sh, ["qs-sfx-shape:number:big|number:small|number:1", "qs-sfx-shape:number:big|number:small|number:0"]);
    check("…and carries no exact keycode or time", sh.some(l => /30|4500/.test(l)), false);

    // Shape D: a bare number, or nothing recognisable: still sounds, state unknown.
    o = run(`cb(30); cb({ weird = true }); cb()`);
    check("an unrecognised payload still sounds, state unknown",
          keys(o), ["qs-sfx-key:?k", "qs-sfx-key:?k", "qs-sfx-key:?k"]);

    // It must NEVER throw into the compositor, whatever it is handed.
    o = run(`cb(nil); cb(true); cb("x"); cb({ key = {} }); cb({ keycode = "x" }); cb(function() end);
             cb(setmetatable({}, { __index = function() error("boom") end }))`);
    check("hostile payloads do not escape the callback", o.some(l => l.startsWith("LUA-ERROR")), false);

    // Privacy: what goes out is two characters, never the key.
    o = run(`cb({ key = "q", keycode = 16, state = "pressed", text = "q" });
             cb({ key = "p", keycode = 25, state = "pressed", text = "p" })`);
    check("only a class is sent, never which key", keys(o), ["qs-sfx-key:dk", "qs-sfx-key:dk"]);
    check("every key event is exactly prefix + 2 characters",
          keys(o).every(l => l.length === K.PREFIX.length + 2), true);

    // The shape report: field names and types; never key / keycode / text values.
    o = run(`cb({ key = "q", keycode = 16, state = "pressed", text = "q", mods = 4 })`);
    const rep = shapes(o)[0] || "";
    check("a shape report is sent", rep.length > 0, true);
    check("…naming the fields", /keycode:number/.test(rep) && /key:string/.test(rep) && /text:string/.test(rep), true);
    check("…with the state value, which the fix needs", /state:string=pressed/.test(rep), true);
    check("…and never the key's identity", /=q|=16/.test(rep), false);
    check("…but only the first few events", shapes(run(`for i = 1, 20 do cb({ key = "a", state = "pressed" }) end`)).length,
          K.SHAPE_REPORTS);

    // Installing twice must not leave two subscriptions.
    o = run(`cb({ key = "a", state = "pressed" })`, `_G.qs_sfx_sub = subscription`);
    check("a second install removes the first subscription", o.includes("REMOVED=true"), true);

    // Removing.
    const rm = spawnSync("lua5.4", ["-e", `
        local s = { removed = false }; function s:remove() self.removed = true end
        _G.qs_sfx_sub = s
        ${K.REMOVE_LUA}
        print(tostring(s.removed), tostring(_G.qs_sfx_sub))`], { encoding: "utf8" });
    check("the remove snippet removes and clears", rm.stdout.trim(), "true\tnil");
    check("removing with nothing installed is fine",
          spawnSync("lua5.4", ["-e", K.REMOVE_LUA]).status, 0);
}

if (failures.length) {
    console.log(`FAIL ${failures.length}, pass ${pass}\n` + failures.join("\n"));
    process.exit(1);
}
console.log(`ok ${pass}`);
