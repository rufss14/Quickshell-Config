.pragma library

// ── surfaces.js ───────────────────────────────────────────────────────────────
// Rules that span BOTH surfaces — the top bar and the sidebar — as pure functions over
// plain data, so `bun scripts/test-surfaces.js` can pin them. Config.qml calls these
// and assigns the results (replaced, never mutated, as layout.js).
//
// ── The hero: one string per surface ──────────────────────────────────────────
// A surface has at most one hero (the user's rule, 2026-11-08). It is stored as one
// string per surface — Config.barHero, Config.sidebarHero — rather than a flag per
// module, because one-per-surface is then true by construction: there is no state in
// which two flags are on. The hero follows its module between surfaces because the
// code that moves a module (Config._leaveBar / _leaveSidebar) moves the string too
// (moveHero). Which modules MAY be a hero is the catalogue's `heroable`.
//
// Before this the bar kept a `hero` flag per module in Config.moduleSettings, clock
// on by default; heroFromFlags turns such a document into the bar's string.
// ─────────────────────────────────────────────────────────────────────────────

// The bar's hero, from a document written before Config.barHero existed: the first
// module in bar order whose `hero` flag is on (the clock's defaulted on); with none,
// the clock unless its flag was explicitly turned off — so a clock added later still
// comes back as the hero, as it did. `heroable(id)` is the catalogue's.
function heroFromFlags(moduleSettings, barLayout, regions, heroable) {
    const ms = moduleSettings || {};
    const flag = id => {
        const m = ms[id];
        return (m && m.hero !== undefined) ? m.hero === true : id === "clock";
    };
    for (const r of (regions || [])) {
        for (const g of ((barLayout || {})[r] || [])) {
            for (const id of g) if (heroable(id) && flag(id)) return id;
        }
    }
    const c = ms.clock;
    return (c && c.hero === false) ? "" : "clock";
}

// moduleSettings without the retired per-module `hero` flags. An entry left empty is
// dropped, so a module whose only customisation was the hero doesn't keep Reset lit.
// Same object back when there was nothing to strip.
function stripHeroFlags(moduleSettings) {
    const ms = moduleSettings || {};
    let any = false;
    for (const k in ms) if (ms[k] && ms[k].hero !== undefined) any = true;
    if (!any) return ms;
    const out = {};
    for (const k in ms) {
        const e = Object.assign({}, ms[k]);
        delete e.hero;
        if (Object.keys(e).length > 0) out[k] = e;
    }
    return out;
}

// A module moving onto surface `to` ("bar" | "side"): if it was the other surface's
// hero, that surface loses its hero, and the module becomes `to`'s hero unless `to`
// already has one standing on it (`destHasHero`) — the destination keeps its own.
// `heroes` is { bar, side }; returns a new one, or the same object when nothing moves.
function moveHero(heroes, id, to, destHasHero) {
    const from = to === "bar" ? "side" : "bar";
    if (heroes[from] !== id) return heroes;
    const out = { bar: heroes.bar, side: heroes.side };
    out[from] = "";
    if (!destHasHero) out[to] = id;
    return out;
}

// ── The sidebar's look: the bar's, unless unlinked ────────────────────────────
// One set of style knobs for both surfaces (the user's pick, 2026-11-08): each is
// "Sidebar: same as bar" until unlinked, and then the sidebar keeps its own value.
// Config.sidebarStyle holds ONLY the unlinked ones (sparse), so linked knobs follow
// the bar live and "relink" is a delete. The bounds are the bar's own sliders'
// (Config.barRoundnessMax, barOpacityMin, the 0.8–1.6 scales).
var STYLE_KEYS = {
    roundness:  { type: "number",  min: 0,   max: 20,  int: true },
    opacity:    { type: "number",  min: 0.5, max: 1 },
    innerPill:  { type: "boolean" },
    musicReact: { type: "boolean" },
    fontScale:  { type: "number",  min: 0.8, max: 1.6 },
    iconScale:  { type: "number",  min: 0.8, max: 1.6 }
};

function _clean(key, v) {
    const k = STYLE_KEYS[key];
    if (!k || typeof v !== k.type) return undefined;
    if (k.type !== "number") return v;
    if (!isFinite(v)) return undefined;
    const c = Math.max(k.min, Math.min(k.max, v));
    return k.int ? Math.round(c) : c;
}

// A hand-editable document's overrides: known keys with the right type, clamped;
// anything else dropped.
function cleanStyle(raw) {
    const out = {};
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out;
    for (const key in STYLE_KEYS) {
        const v = _clean(key, raw[key]);
        if (v !== undefined) out[key] = v;
    }
    return out;
}

// Unlink `key` at `value` (clamped), or leave the style alone for a bad key/value.
function setOverride(style, key, value) {
    const v = _clean(key, value);
    if (v === undefined) return style;
    const out = Object.assign({}, style);
    out[key] = v;
    return out;
}

// Link `key` back to the bar's.
function clearOverride(style, key) {
    if (!style || style[key] === undefined) return style;
    const out = Object.assign({}, style);
    delete out[key];
    return out;
}
