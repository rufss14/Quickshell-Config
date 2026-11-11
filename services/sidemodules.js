.pragma library

// ── sidemodules.js ────────────────────────────────────────────────────────────
// The small sidebar modules' arithmetic, pure so it can be tested
// (`bun scripts/test-sidemodules.js`). Most of it is "how many cells": the rail
// needs a module's length BEFORE anything is drawn (SideRail.cellsFor), and the
// module needs the same answer to draw — one function, so the two can't disagree
// and leave a module overrunning its pill or a gap at its end.
// ─────────────────────────────────────────────────────────────────────────────

// ── Voice ─────────────────────────────────────────────────────────────────────
// In a call: the people in it, up to MAX_FACES; more than that and the last face
// becomes a "+n". Then mute and deafen. Out of a call: the mic alone.
//
// The faces are ONE overlapping stack (2026-10-31, Material's avatar group — the user's
// pick for a quieter sidebar), not a cell each: `stack` is how many things are in it (the
// faces and the "+n"), and it takes one cell for up to two of them and half a cell for
// each one after (`stackCells`) — fractional, which Config.sidebarRun is fine with.
var MAX_FACES = 3;

function stackCells(stack) {
    const n = Math.max(0, stack | 0);
    return n === 0 ? 0 : n <= 2 ? 1 : 1 + (n - 2) * 0.5;
}

function voiceLayout(inCall, people, maxFaces) {
    const cap = maxFaces || MAX_FACES;
    if (!inCall) return { faces: 0, more: 0, stack: 0, cells: 1 };
    const n = Math.max(0, people | 0);
    const over = n > cap;
    const faces = over ? cap - 1 : n;
    const more = over ? n - faces : 0;
    const stack = faces + (over ? 1 : 0);
    return { faces: faces, more: more, stack: stack, cells: stackCells(stack) + 2 };
}

// ── The focused window ────────────────────────────────────────────────────────
// One cell, or none: it steps aside on an empty workspace (nothing to name) and when the
// focused app is already on the sidebar's dock, whose mark says it's the focused one
// (2026-10-31, the user's pick). Arranging the sidebar it always shows, so it can be
// picked up.
function windowCells(hasWindow, docked, arranging) {
    if (arranging) return 1;
    return hasWindow && !docked ? 1 : 0;
}

// ── The colour picker ─────────────────────────────────────────────────────────
// The last MAX_SWATCHES picks show as swatches after the pick cell; the history
// keeps a few more than that (HISTORY), so taking one off brings an older one back.
var MAX_SWATCHES = 4;
var HISTORY = 12;

// What hyprpicker printed, if it's a colour: "#rrggbb", lower-cased; else "". Its
// stdout is the trust boundary — nothing else reaches the history (a hand-editable
// file) or the clipboard. Cancelled (Escape), it prints nothing.
function parseHex(out) {
    const m = String(out === undefined || out === null ? "" : out).trim().match(/^#?([0-9a-fA-F]{6})$/);
    return m ? "#" + m[1].toLowerCase() : "";
}

// Newest first, no repeats, nothing that isn't a colour, at most `cap`.
function remember(list, hex, cap) {
    const c = parseHex(hex);
    const rest = (Array.isArray(list) ? list : []).map(parseHex).filter(x => x !== "" && x !== c);
    return (c !== "" ? [c] : []).concat(rest).slice(0, cap || HISTORY);
}

// The history as read back from disk: only colours, in order, no repeats.
function clean(list, cap) {
    const out = [];
    for (const x of (Array.isArray(list) ? list : [])) {
        const c = parseHex(x);
        if (c !== "" && out.indexOf(c) === -1) out.push(c);
    }
    return out.slice(0, cap || HISTORY);
}

function forget(list, hex) {
    const c = parseHex(hex);
    return (Array.isArray(list) ? list : []).filter(x => x !== c);
}

// The pick cell and a swatch per recent colour.
function colourCells(historyLength, maxSwatches) {
    return 1 + Math.max(0, Math.min(historyLength | 0, maxSwatches || MAX_SWATCHES));
}

// ── The stats ─────────────────────────────────────────────────────────────────
// A cell per metric (glyph + reading), the first MAX_STATS of what this machine
// can read, in the configured order. Nothing readable: one cell (the part's glyph).
var MAX_STATS = 4;

function statsCells(metrics, maxStats) {
    return Math.max(1, Math.min(metrics | 0, maxStats || MAX_STATS));
}

// ── The inner pill, per module ────────────────────────────────────────────────
// A module can opt out of its inner pill (Bar & sidebar › Modules, Config.moduleInnerPill);
// on the bar it then sits straight on the bar (BarGroup splits the run). On the sidebar the
// pill under a group or region is split the same way: one piece per run of modules that keep
// theirs. `mods` are the pill's modules in order along the edge, [{ at, len, on }], `at`
// relative to the pill's start; `span` is the pill's length. A run that reaches an end of
// the pill keeps the pill's own end (its padding); one that stops short of a module that
// opted out keeps the pill's end padding round its cells, never reaching into that module. All on: one piece, the whole pill. All off: none.
function innerRuns(mods, span) {
    const list = Array.isArray(mods) ? mods : [];
    if (list.length === 0) return [];
    if (list.every(m => m.on)) return [{ from: 0, to: span }];
    const pad = Math.max(0, list[0].at);
    const out = [];
    let start = -1;
    for (let i = 0; i <= list.length; i++) {
        const m = list[i];
        if (m && m.on) { if (start < 0) start = i; continue; }
        if (start < 0) continue;
        const first = list[start], last = list[i - 1];
        const prev = list[start - 1];
        out.push({ from: start === 0 ? 0 : Math.max(prev.at + prev.len, first.at - pad),
                   to:   i === list.length ? span : Math.min(m.at, last.at + last.len + pad) });
        start = -1;
    }
    return out;
}
