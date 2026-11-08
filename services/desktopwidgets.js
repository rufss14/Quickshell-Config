.pragma library

// ── desktopwidgets.js ─────────────────────────────────────────────────────────
// The desktop-widget list rules that REMOVE tiles, kept out of QML so they can be
// tested (`bun scripts/test-desktopwidgets.js`). A wrong answer here deletes something
// the user placed, which is not the kind of bug anyone notices for a week.
//
// ── One of each type, per screen ──────────────────────────────────────────────
// DesktopWidgets.add() refuses a second tile of a type already on that screen (the
// user's call — see the comment there). applyPreset() got round it. savePreset()
// stores the WHOLE desktop, every screen's tiles, so a preset saved on two monitors
// holds two complete layouts — and applying it to ONE screen retargeted every record
// onto that screen, stacking both layouts pixel-for-pixel. Each tile then ran twice,
// the top copy hiding the other: two lyrics cards, two system monitors, on a desktop
// that looked like it had one of each.
// ─────────────────────────────────────────────────────────────────────────────

// The records applyPreset(name, screen) should place on `screen`: the preset's own
// layout for that screen if it saved one; otherwise ONE source screen's layout (the
// first listed), so a preset saved on a different monitor still applies. No screen =
// every record to its own screen, as saved. Either way one of each type per screen,
// keeping the LAST of a type — draw order is list order, so the last copy is the one
// that was on top, the one the user was looking at when the preset was saved.
//
// A type that may be placed more than once (`multi(type)` true — the photo frame) keeps
// every one of its tiles: each is its own tile with its own picture, not a duplicate.
function presetFor(list, screen, multi) {
    let src = list
    if (screen) {
        const own = list.filter(w => w.screen === screen)
        const first = list.length > 0 ? list[0].screen : undefined
        src = own.length > 0 ? own : list.filter(w => w.screen === first)
    }
    const many = multi || (() => false)
    const key = w => (screen || w.screen) + "\u0000" + w.type + (many(w.type) ? "\u0000" + w.id : "")
    const last = {}
    for (let i = 0; i < src.length; i++) last[key(src[i])] = i
    return src.filter((w, i) => last[key(w)] === i)
}

// The live list with STACKED duplicates removed: an earlier tile with the same screen,
// type AND position as a later one. That is exactly the shape a duplicated preset
// leaves, and exactly the tiles nobody can see or reach — findFreeSpot() never puts
// one tile on another, so nothing placed by hand looks like this. Two deliberate tiles
// of one type (from before the one-per-type rule — two disk tiles, say) sit at
// different positions and are left alone.
//
// A tile whose type holds TYPED content (`holdsText(type)` — notes, reminders) is never
// dropped, stacked or not: the hidden copy's text is still the user's, and a cleanup
// that runs on load has no business deciding it is disposable.
//
// LAYOUT is part of the key (2026-10-30, live layouts per wallpaper): a wallpaper's own
// layout usually starts as a COPY of another, so the same type at the same spot on the same
// screen in two layouts is the normal case — and without the layout in the key, this would
// delete one of them on the next load.
function dropStacked(list, holdsText) {
    const key = w => [w.screen, w.layout ?? "", w.type, w.x, w.y].join("\u0000")
    const last = {}
    for (let i = 0; i < list.length; i++) last[key(list[i])] = i
    return list.filter((w, i) => last[key(w)] === i || holdsText(w.type))
}

// ── fit ───────────────────────────────────────────────────────────────────────
// Where each tile is DRAWN on a layer of `W`×`H`, which is not always where it is
// stored. The layer is inset by every exclusive zone on the screen (bar, frame, and the
// dock's reserve while it takes space), so it is smaller with the dock than without —
// and positions are plain pixels from its top-left, so the tiles on the far edges fell
// off it. A saved layout is never rewritten to fit: this is display only, so turning the
// dock off (or moving to a bigger screen) gives the layout back exactly as it was placed.
//
// A bare clamp would stack the edge tile on its neighbour, so tiles that overflow are
// pushed in against the edge and carry their neighbours with them, keeping the spacing
// they were placed with. Each axis is done on its own: right→left sorted by left edge,
// then bottom→top. `size(w)` gives a tile's { w, h }; `gap` is the spacing to keep,
// capped by the spacing the pair really had. Returns { [id]: { x, y } } — every tile,
// moved or not. No layer yet (W or H not positive) returns the stored positions.
function fit(list, W, H, size, gap) {
    const items = list.map(t => Object.assign({ id: t.id, x: t.x, y: t.y, x0: t.x, y0: t.y }, size(t)))
    if (W > 0 && H > 0) {
        // `p`/`l` the axis being squeezed, `c`/`cl` the one across it: tiles only push
        // each other when they share a row (or column).
        const squeeze = (p, l, c, cl, span) => {
            const far = items.slice().sort((a, b) => b[p + "0"] - a[p + "0"])
            for (let i = 0; i < far.length; i++) {
                const t = far[i]
                let limit = span - t[l]
                for (let j = 0; j < i; j++) {
                    const o = far[j]
                    if (o[p + "0"] < t[p + "0"]) continue
                    if (!(t[c] < o[c] + o[cl] && o[c] < t[c] + t[cl])) continue
                    const had = Math.max(0, o[p + "0"] - (t[p + "0"] + t[l]))
                    limit = Math.min(limit, o[p] - t[l] - Math.min(gap, had))
                }
                t[p] = Math.max(0, Math.min(t[p], limit))
            }
        }
        squeeze("x", "w", "y", "h", W)
        squeeze("y", "h", "x", "w", H)
    }
    const out = {}
    for (const t of items) out[t.id] = { x: t.x, y: t.y }
    return out
}

// ── Paths a tile names (the photo frame's folder or picture) ──────────────────
// Stored `~`-relative, never with the home directory spelled out: widget presets are saved
// into the published repo (presets/widgets.json), and a preset naming /home/<you>/Pictures
// would bake this machine's home into it. `contractHome` on the way in (a picker hands back
// an absolute path), `expandHome` on the way out — DesktopWidgets.contractPath/expandPath
// are the one place either happens.
function expandHome(p, home) {
    const s = (p || "").trim()
    if (!home) return s
    if (s === "~") return home
    if (s.indexOf("~/") === 0) return home + s.slice(1)
    return s
}

function contractHome(p, home) {
    const s = (p || "").trim()
    if (!home || home === "/") return s
    if (s === home) return "~"
    if (s.indexOf(home + "/") === 0) return "~" + s.slice(home.length)
    return s
}

// ── Habits ────────────────────────────────────────────────────────────────────
// A habit is { id, name, days: ["YYYY-MM-DD", …] } — the LOCAL dates it was done, sorted,
// no duplicates. Dates rather than timestamps: "did I do it on Tuesday" is a calendar
// question, and a timestamp would move across midnight with the timezone.

function isoDay(d) {
    const p = n => (n < 10 ? "0" : "") + n
    return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate())
}

// `n` days after `iso` (negative: before). Built from the calendar fields, never by
// adding 86400000 ms, so a daylight-saving change can't land it on the same day twice.
function dayShift(iso, n) {
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso || "")
    if (!m) return ""
    return isoDay(new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]) + n))
}

// The last `n` days ending at `todayIso`, oldest first.
function lastDays(todayIso, n) {
    const out = []
    for (let i = n - 1; i >= 0; i--) out.push(dayShift(todayIso, -i))
    return out
}

// `days` with `iso` flipped: added (kept sorted) if absent, removed if present.
function toggleDay(days, iso) {
    const list = (days || []).filter(d => d !== iso)
    if (list.length === (days || []).length) list.push(iso)
    return list.sort()
}

// Consecutive days done, ending today — or ending yesterday when today isn't ticked
// yet, so a streak doesn't read 0 every morning until you've done the thing.
function streak(days, todayIso) {
    const set = {}
    for (const d of days || []) set[d] = true
    let at = set[todayIso] ? todayIso : dayShift(todayIso, -1)
    let n = 0
    while (set[at]) { n++; at = dayShift(at, -1) }
    return n
}

// ── Smart stack ───────────────────────────────────────────────────────────────
// Which card a smart stack should bring forward, or -1 to leave it where it is: the
// timer while one is running (it is the most time-critical thing on it), else the first
// media card while something plays.
var STACK_MEDIA = ["nowplaying", "lyrics", "visualizer"]
function stackSurface(cards, ctx) {
    const list = cards || []
    if (ctx.timer) {
        const t = list.indexOf("timer")
        if (t >= 0) return t
    }
    if (ctx.playing) {
        for (let i = 0; i < list.length; i++)
            if (STACK_MEDIA.indexOf(list[i]) >= 0) return i
    }
    return -1
}

// ── Layouts ───────────────────────────────────────────────────────────────────
// A record's `layout` ("" or absent = the normal layout) says which layout it belongs to;
// a screen shows the records of ITS active layout only. `inLayout` is the one test.
function inLayout(w, layout) {
    return (w.layout ?? "") === (layout ?? "")
}

// A layout name from `base` (a wallpaper's file name, say) that isn't in `taken`: "Furina",
// then "Furina 2", "Furina 3"… An empty base is "Layout".
function uniqueName(base, taken) {
    const b = (base || "").trim() || "Layout"
    const set = {}
    for (const t of taken || []) set[t] = true
    if (!set[b]) return b
    let n = 2
    while (set[b + " " + n]) n++
    return b + " " + n
}

// A wallpaper value's short name for a person: the file name without its extension, or
// "Scene <id>" for a Wallpaper Engine scene.
function wallName(key) {
    const k = key || ""
    if (k.indexOf("scene:") === 0) return "Scene " + k.slice(6)
    const file = k.split("/").pop()
    const dot = file.lastIndexOf(".")
    return dot > 0 ? file.slice(0, dot) : file
}
