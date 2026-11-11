.pragma library

// ── layout.js ─────────────────────────────────────────────────────────────────
// The bar layout algebra: region → groups → module ids, and every transformation
// the settings page's drag UI performs on it.
//
// ── Why this is a .js and not more of Config.qml ──────────────────────────────
// It is a real algorithm over plain data, and the repo's rule is that those live in
// a `.js` beside their consumer BECAUSE THAT CAN BE TESTED (`services/calc.js`,
// `services/palette.js`). Buried in a QML singleton it could only be exercised by
// running the shell, dragging pills around and looking at the bar.
//
// The subtle one is `reconcile()`. Its "the user removed this" vs "this didn't exist
// yet" rule is a genuine judgement call that is invisible from outside — get it wrong
// and either a module the user deliberately took off the bar silently comes back, or
// a module added by an upgrade never appears at all. Neither announces itself.
// `bun scripts/test-layout.js` pins it.
//
// ── Everything here is pure ───────────────────────────────────────────────────
// No QML, no singletons, no `root`. Every function takes the layout in and returns a
// NEW one — the callers in Config.qml assign the result. That mirrors the model's own
// most important rule ("replaced, never mutated"): an in-place edit fires no change
// signal, so the bar would quietly keep rendering the old layout.
//
// The only mutation is inside a function, on a clone it just made.
// ─────────────────────────────────────────────────────────────────────────────

// The three regions, in bar order. This is the single definition — Config.regionIds
// binds to it rather than repeating the array, so a fourth region would be one edit.
var REGIONS = ["left", "centre", "right"];

// The sidebar's regions, along its edge: `start` is the near end (under the bar on a
// side, the left end along the bottom), `end` the far corner. Config.sidebarLayout is
// this same algebra over these three — every function below takes the regions it
// works on, so nothing here is bar-specific but the default above.
var SIDE_REGIONS = ["start", "centre", "end"];

// ── The default ───────────────────────────────────────────────────────────────
// What a fresh install, Reset and the built-in "Default" preset get: the modules a
// first-time user expects on a bar, ~15 of them. Everything else in Config.moduleList
// is still one drag away in the settings tray (shape/mode toggles, reload, keyboard
// layout, night light, game mode, idle inhibit, OBS), so leaving it off costs nothing
// but the first-run noise.
//
// The long, comprehensive arrangement this used to be is the "Rufss" entry in
// presets/bar.json — a real preset, not a comment promising to stay in sync with one.
// (`rng` is gone from the catalogue altogether.)
//
// The centre region is update | workspaces, as two groups on purpose: the region puts
// the group CONTAINING workspaces on true screen centre, so workspaces must be alone in
// its group — an update pill appearing beside it would otherwise push it off-centre.
function defaultLayout() {
    return {
        left:   [["overview"], ["wallpaper", "palette"], ["volume"], ["visualizer"]],
        centre: [["update"], ["workspaces"]],
        right:  [["tray", "privacy", "notifications", "bluetooth", "wifi"],
                 ["battery"], ["clock"], ["settings"]]
    };
}

// A deep copy, because every mutator works on a throwaway and then hands it back. A
// shallow copy would share the inner group arrays with the live layout, so a splice
// would mutate what's on screen before the assignment — which is exactly the in-place
// mutation the model forbids.
function clone(l, regions) {
    const rs = regions || REGIONS;
    const out = {};
    for (const r of rs) out[r] = (l[r] || []).map(g => g.slice());
    return out;
}

// Groups only exist to hold modules. Dragging the last one out of a group leaves an
// empty pill sitting in the bar, so emptied groups are dropped on every write rather
// than at each call site remembering to.
function prune(l, regions) {
    const rs = regions || REGIONS;
    for (const r of rs) l[r] = (l[r] || []).filter(g => g.length > 0);
    return l;
}

// ── Where is this module right now? ───────────────────────────────────────────
// Returns { region, group, index } or null. The drag UI and the bar both need to
// answer this, and neither should be scanning the structure by hand.
function locate(l, id, regions) {
    const rs = regions || REGIONS;
    for (const r of rs) {
        const groups = l[r] || [];
        for (let g = 0; g < groups.length; g++) {
            const i = groups[g].indexOf(id);
            if (i !== -1) return { region: r, group: g, index: i };
        }
    }
    return null;
}

// ── Mutators ──────────────────────────────────────────────────────────────────
// All of them take the module OUT first and put it back somewhere. Move and insert are
// the same operation with a different destination, and writing them separately is how
// you end up with a module existing twice.
//
// `extract` is the one in-place helper, and it is only ever called on a fresh clone.
function extract(l, id, regions) {
    const rs = regions || REGIONS;
    for (const r of rs) {
        for (const g of (l[r] || [])) {
            const i = g.indexOf(id);
            if (i !== -1) { g.splice(i, 1); return; }
        }
    }
}

// Drop onto a gap: the module becomes its own group at `groupIndex` in `region`.
//
// `groupIndex` names a gap in the layout as it was, BEFORE the module came out. A
// module that was alone in a group of this region leaves no group behind it, so every
// gap after that one moves down a place: without the adjustment, dropping a lone
// module into the gap right after its own group moved it one group too far.
function moveToOwnGroup(l, id, region, groupIndex, regions) {
    const from = locate(l, id, regions);
    const vacated = from && from.region === region
                 && ((l[region] || [])[from.group] || []).length === 1
                 && from.group < groupIndex;
    const next = clone(l, regions);
    extract(next, id, regions);
    prune(next, regions);
    const at = Math.max(0, Math.min(vacated ? groupIndex - 1 : groupIndex, next[region].length));
    next[region].splice(at, 0, [id]);
    return next;
}

// Drop onto another module: join its group at `index`. This is the phone-folder
// gesture — dropping one thing on another is what makes them a cluster, so grouping
// never needs a mode or a modifier key.
function moveIntoGroup(l, id, region, groupIndex, index, regions) {
    const next = clone(l, regions);

    // Where it was matters: pulling it out of the SAME group shifts everything after it
    // down one, so an index captured before the extract would land the module one slot
    // too far right. Everywhere else is unaffected.
    const from = locate(l, id, regions);
    const sameGroup = from && from.region === region && from.group === groupIndex;
    const adjusted  = (sameGroup && from.index < index) ? index - 1 : index;

    extract(next, id, regions);

    // The group may have just been emptied and pruned away — but pruning first would
    // renumber the groups after it and invalidate `groupIndex`. So target the group,
    // THEN prune.
    const g = next[region] ? next[region][groupIndex] : null;
    if (!g) return prune(next, regions);
    g.splice(Math.max(0, Math.min(adjusted, g.length)), 0, id);

    return prune(next, regions);
}

function removeModule(l, id, regions) {
    const next = clone(l, regions);
    extract(next, id, regions);
    return prune(next, regions);
}

// Putting a module back from the available pool. Its own group at the end of the region
// it belongs to by default — a returning module shouldn't silently join a cluster it
// was never part of.
//
// `canJoin` (optional, the sidebar's): when it holds for the module AND for everything
// in the region's last group, the module joins that group instead. The sidebar's small
// modules read as loose buttons one pill each; the top bar passes nothing.
//
// Returns null for "nothing to do" (unknown id, or already placed) rather than an
// unchanged copy, so the caller can skip the assignment and the change signal with it.
function addModule(l, id, moduleList, regions, canJoin) {
    const m = moduleList.find(x => x.id === id);
    if (!m || locate(l, id, regions)) return null;
    const next = clone(l, regions);
    const groups = next[m.home];
    const last = groups.length > 0 ? groups[groups.length - 1] : null;
    if (canJoin && canJoin(id) && last && last.length > 0 && last.every(canJoin)) last.push(id);
    else groups.push([id]);
    return next;
}

// ── Reconciling a saved layout against the current catalogue ──────────────────
// A saved layout can't be trusted: it was written by a previous version of the shell.
// Modules added since aren't in it (they'd silently never appear), and modules REMOVED
// since still are (the bar would try to build a widget that no longer exists).
//
// ── "You removed this" vs "this didn't exist yet" ─────────────────────────────
// Both look identical in a saved layout — the module simply isn't there — and they want
// opposite treatment. `priorKnown` is what the catalogue held last time the config was
// written, so a module missing from BOTH the layout and priorKnown is genuinely new and
// gets appended; a module missing from the layout but present in priorKnown was
// deliberately removed and stays gone.
//
// An empty priorKnown means a config written before this was tracked. Treat its
// absences as deliberate rather than re-adding everything the user took out — the
// layout is better evidence of intent than a marker we never wrote.
function reconcile(saved, priorKnown, moduleList, regions) {
    const rs    = regions || REGIONS;
    const known = moduleList.map(m => m.id);
    const seen  = [];
    const out   = {};

    for (const r of rs) {
        // Hand-editable: a region or a group that isn't an array is dropped rather
        // than thrown on (`.map`/`.filter` of a string or an object).
        out[r] = (Array.isArray(saved[r]) ? saved[r] : [])
            .map(g => (Array.isArray(g) ? g : []).filter(id => {
                // Also drops DUPLICATES. A layout listing a module twice would build the
                // widget twice, and for the tray or the visualizer that means two of the
                // thing plus two of whatever process sits behind it.
                if (known.indexOf(id) === -1 || seen.indexOf(id) !== -1) return false;
                seen.push(id);
                return true;
            }))
            .filter(g => g.length > 0);
    }

    const prior = (priorKnown && priorKnown.length > 0) ? priorKnown : known;
    for (const m of moduleList) {
        if (seen.indexOf(m.id) === -1 && prior.indexOf(m.id) === -1)
            out[m.home].push([m.id]);
    }

    return out;
}

// ── The bar's shape, from anything a document may hold ────────────────────────
// The bar is one surface now — the pills shapes were scrapped (the user's call). A
// config or preset written before carries `pills` / `pillsAnchored`, or older still
// no `barLayout` at all and a `frameMerge` bool; each maps to its unified twin, so
// an install keeps whether its bar sat on the frame. Anything unknown is the default.
function unifiedLayout(name, frameMerge) {
    if (name === "unified" || name === "pills") return "unified";
    if (name === "unifiedAnchored" || name === "pillsAnchored") return "unifiedAnchored";
    if (name === undefined || name === null) return frameMerge === false ? "unified" : "unifiedAnchored";
    return "unifiedAnchored";
}

// ── Stable serialisation, for comparing a preset against the live bar ─────────
// Serialise with object keys in a stable order, at every depth.
//
// Plain JSON.stringify follows INSERTION order, which was fine while presets only ever
// came from _snapshot() and every one of them was built by the same literal. They come
// off disk now, and the file is meant to be hand-edited — so the moment you reorder two
// keys in presets/bar.json by hand, a byte-identical preset stops matching and the
// active dot goes out. Same data, different string.
function canonical(v) {
    if (Array.isArray(v)) return "[" + v.map(canonical).join(",") + "]";
    if (v !== null && typeof v === "object")
        return "{" + Object.keys(v).sort()
            .map(k => JSON.stringify(k) + ":" + canonical(v[k])).join(",") + "}";
    return JSON.stringify(v);
}

// ── One place per module, across both surfaces ────────────────────────────────
// Config's mutators already keep a module on one surface (_leaveBar/_leaveSidebar),
// but a document is hand-editable and a preset may carry a bar layout without a
// sidebar one: either can name a module that already stands on the other surface.
// The bar's copy wins — it is the one a preset or a load just asked for — and the
// sidebar's is dropped (its emptied group pruned). Returns the sidebar layout,
// unchanged (the same object) when nothing was shared, so the caller can skip the
// assignment and its change signal.
function dedupeAcross(bar, side, barRegions, sideRegions) {
    const br = barRegions || REGIONS, sr = sideRegions || SIDE_REGIONS;
    const onBar = [];
    for (const r of br) for (const g of (bar[r] || [])) for (const id of g) onBar.push(id);
    let shared = false;
    for (const r of sr) for (const g of (side[r] || [])) if (g.some(id => onBar.indexOf(id) !== -1)) shared = true;
    if (!shared) return side;
    const next = clone(side, sr);
    for (const r of sr) next[r] = next[r].map(g => g.filter(id => onBar.indexOf(id) === -1));
    return prune(next, sr);
}

// ── Does a preset match the live snapshot? ────────────────────────────────────
// `optional` keys were added to the snapshot after presets already existed (the
// sidebar's layout, the two hero strings): a preset that doesn't mention one says
// nothing about it — loading it leaves that setting alone — so the comparison
// leaves it out too, instead of no old preset ever showing as active again.
function presetMatches(preset, snap, optional) {
    const s = Object.assign({}, snap);
    for (const k of (optional || [])) if (preset[k] === undefined) delete s[k];
    return canonical(preset) === canonical(s);
}
