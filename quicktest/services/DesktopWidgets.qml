pragma Singleton
import Quickshell
import QtQuick
import "../config"

// ── DesktopWidgets ────────────────────────────────────────────────────────────
// What is on the desktop, where, and what each one holds.
//
// ── One document, not two ─────────────────────────────────────────────────────
// Placement is a preference and a note's text is user data, so they could have been
// split between Config and a state file. They aren't, because they are joined at the
// hip: deleting a widget has to delete its note, and a note with no widget is
// unreachable. Keeping them in one store means removal is one operation that cannot
// half-fail and leave orphaned text nobody can see or clear.
//
// It lives in `statePath("widgets.json")` rather than in Config's prefs document
// because it grows with content — a page of notes has no business being re-serialised
// every time a slider moves.
//
// ── Sizes are named, not free ─────────────────────────────────────────────────
// small / medium / large, in grid units, the way macOS does it. Free resizing sounds
// more flexible and is worse: every widget would need a layout that works at every
// aspect ratio, and the desktop fills up with slightly-different rectangles. Three
// sizes means each widget has three layouts to get right, and they line up with each
// other by construction.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── Geometry ──────────────────────────────────────────────────────────────
    // One unit is a square tile; the larger sizes are whole numbers of units plus the
    // gaps between them, so a medium sits flush beside two smalls.
    readonly property int unit: 168
    readonly property int gap:  16

    function widthOf(size) {
        return size === "small" ? root.unit : root.unit * 2 + root.gap
    }
    function heightOf(size) {
        return size === "large" ? root.unit * 2 + root.gap : root.unit
    }

    readonly property var sizes: ["small", "medium", "large"]

    // ── The catalogue ─────────────────────────────────────────────────────────
    // What can be placed. The settings page renders this directly, so adding a widget
    // type means adding a row here and a QML file — nothing else knows the list.
    readonly property var catalogue: [
        { type: "clock",     label: "Clock",     glyph: "󰅐",
          detail: "Time and date",              sizes: ["small", "medium"] },
        { type: "calendar",  label: "Calendar",  glyph: "󰃭",
          detail: "This month at a glance",     sizes: ["small", "medium", "large"] },
        { type: "weather",   label: "Weather",   glyph: "󰖕",
          detail: "Current conditions and forecast", sizes: ["small", "medium", "large"] },
        // `editable` means the widget takes TYPED input, which is what decides whether
        // the desktop layer asks for keyboard focus at all. It lives here rather than as
        // a list of type names inside the layer, so adding a widget stays a matter of a
        // catalogue row and a QML file — which is what the comment above promises.
        { type: "notes",     label: "Notes",     glyph: "󰎞",
          detail: "A scratch pad you can type in",   sizes: ["medium", "large"],
          editable: true },
        { type: "reminders", label: "Reminders", glyph: "󰄹",
          detail: "A checklist that persists",  sizes: ["medium", "large"],
          editable: true },

        // ── Live tiles ────────────────────────────────────────────────────────
        // Each of these is a view over a service the shell already runs, and every one
        // of those services is refcounted — so a type that is not placed costs nothing.
        { type: "nowplaying", label: "Now playing", glyph: "󰎈",
          detail: "What's playing, with transport controls",
          sizes: ["small", "medium", "large"] },
        { type: "sysmon",    label: "System",      glyph: "󰍛",
          detail: "CPU, memory and temperature",  sizes: ["small", "medium", "large"] },
        { type: "visualizer", label: "Visualizer", glyph: "󰄨",
          detail: "A spectrum of whatever is playing",
          sizes: ["small", "medium", "large"] },
        { type: "network",   label: "Network",     glyph: "󰛳",
          detail: "Up and down, live",            sizes: ["small", "medium", "large"] },
        { type: "clipboard", label: "Clipboard",   glyph: "󰅌",
          detail: "Recent copies, click to copy back", sizes: ["medium", "large"] },
        { type: "timer",     label: "Timer",       glyph: "󰔛",
          detail: "Timer and stopwatch",          sizes: ["small", "medium"] },
        { type: "disk",      label: "Disk space",  glyph: "󰋊",
          detail: "How much room is left",        sizes: ["small", "medium", "large"] },
        { type: "updates",   label: "Updates",     glyph: "󰚰",
          detail: "Packages waiting to install",  sizes: ["small", "medium"] },
        { type: "photo",     label: "Photo frame", glyph: "󰋩",
          detail: "Your wallpapers, cycling",     sizes: ["small", "medium", "large"] },

        // ── Arithmetic tiles ──────────────────────────────────────────────────
        // No service and no process behind these — just the system clock.
        { type: "worldclock", label: "World clock", glyph: "󰇧",
          detail: "The time somewhere else",      sizes: ["small", "medium", "large"] },
        { type: "sun",       label: "Sun",         glyph: "󰖙",
          detail: "Sunrise, sunset and the day's arc", sizes: ["medium", "large"] },
        { type: "countdown", label: "Countdown",   glyph: "󰃯",
          detail: "Days until a date you set",    sizes: ["small", "medium"] }
    ]

    function info(type) {
        return root.catalogue.find(c => c.type === type) ?? null
    }

    // Does this type take typed input? Read by the desktop layer to decide whether the
    // surface asks for keyboard focus — a desktop that competes for every keystroke when
    // nothing on it can be typed into is worse than one that never asks.
    function takesText(type) {
        return (root.info(type)?.editable ?? false) === true
    }

    // ── Representative content for a catalogue preview ────────────────────────
    // An empty Notes tile previews as a blank rectangle and an empty Reminders tile as
    // the words "Nothing yet" — neither tells you what the widget is for, which is the
    // one job the picker has. These are for DISPLAY only: nothing here is ever written
    // to the store, and a real widget still starts empty.
    function sampleOpts(type) {
        if (type === "notes")
            return { text: "Ideas\n· analog clock\n· photo frame tile" }
        if (type === "reminders")
            return { items: [{ id: 1, text: "Water the plants", done: false },
                             { id: 2, text: "Reply to Sam",     done: false },
                             { id: 3, text: "Renew domain",     done: true }] }
        // A countdown with no date previews as "Pick a date in Settings", which tells
        // you where to configure it and nothing about what it looks like. The sample
        // is relative to today, so the preview never shows a date in the past.
        if (type === "countdown") {
            const d = new Date()
            d.setDate(d.getDate() + 42)
            const iso = d.getFullYear() + "-"
                      + ("0" + (d.getMonth() + 1)).slice(-2) + "-"
                      + ("0" + d.getDate()).slice(-2)
            return { date: iso, label: "Trip" }
        }
        return root._defaultOpts(type)
    }

    // ── State ─────────────────────────────────────────────────────────────────
    // [{ id, type, screen, x, y, size, opts }]. Newest last; draw order is list order,
    // so a widget dropped on top of another stays on top.
    property var widgets: []
    property int _seq: 1
    property bool _loading: false
    property bool _touched: false

    readonly property bool ready: store.ready

    function forScreen(name) {
        return root.widgets.filter(w => w.screen === name)
    }

    // ── The IDs, for use as a Repeater MODEL ──────────────────────────────────
    // Never hand `forScreen()` to a Repeater. Every mutation here replaces the whole
    // `widgets` array by design (an in-place edit fires no change signal), so a model of
    // whole records is a different array of partly-different objects each time, and Qt
    // resets the delegate list. MEASURED: editing one widget's opts rebuilt all five
    // tiles — every Loader torn down, every widget reconstructed, which is exactly the
    // "all the other tiles reload when I tap one" the user reported.
    //
    // A list of ints compares equal when nothing was added or removed, so the Repeater
    // leaves the delegates alone and only the one delegate whose record changed
    // re-evaluates its own bindings. Same measurement after: 0 rebuilds.
    function idsFor(name) {
        return root.widgets.filter(w => w.screen === name).map(w => w.id)
    }

    function get(id) {
        return root.widgets.find(w => w.id === id) ?? null
    }

    // ── Mutation ──────────────────────────────────────────────────────────────
    // Every one of these REPLACES `widgets` with a new array rather than editing an
    // entry in place. An in-place mutation fires no change signal in QML, so the
    // desktop would not repaint and the store would never write — the same rule
    // JsonStore states about its own `value`, and the same trap Config.layout has.

    // ── One of each type per screen ───────────────────────────────────────────
    // Clicking a catalogue row twice used to add a second identical tile, which is how
    // two empty Reminders ended up stacked on the desktop. macOS allows duplicates and
    // they are almost never what you meant; the user asked for none, and a widget you
    // added by accident is one you then have to find and delete.
    function has(type, screen) {
        return root.widgets.some(w => w.type === type && w.screen === screen)
    }

    function add(type, screen, x, y) {
        const meta = root.info(type)
        if (!meta) return -1
        if (root.has(type, screen)) return -1
        const id   = root._seq++
        const size = meta.sizes[0]
        // Placed where asked, or in the first free slot — never on top of something
        // already there. A tile dropped under another is invisible AND unreachable.
        const spot = root.findFreeSpot(screen, size, -1,
                                       x === undefined ? root.gap : x,
                                       y === undefined ? root.gap : y)
        const list = root.widgets.slice()
        list.push({
            id: id, type: type, screen: screen,
            x: spot.x, y: spot.y,
            size: size,
            opts: root._defaultOpts(type)
        })
        root.widgets = list
        root._persist()
        return id
    }

    // ── Collision ─────────────────────────────────────────────────────────────
    // The desktop is free-form, so nothing stops two tiles occupying the same pixels
    // except this. Rectangles are half-open on the far edge, so two tiles sharing an
    // edge do NOT count as overlapping — otherwise widgets could never sit flush.
    function _rectOf(w) {
        return { x: w.x, y: w.y,
                 w: root.widthOf(w.size), h: root.heightOf(w.size) }
    }

    function _hits(a, b) {
        return a.x < b.x + b.w && b.x < a.x + a.w
            && a.y < b.y + b.h && b.y < a.y + a.h
    }

    function collides(screen, x, y, size, excludeId) {
        const me = { x: x, y: y, w: root.widthOf(size), h: root.heightOf(size) }
        return root.widgets.some(w =>
            w.screen === screen && w.id !== excludeId && root._hits(me, root._rectOf(w)))
    }

    // Nearest free slot to (prefX, prefY), searched on the tile grid outward in rings.
    // Rings rather than a raster scan so a tile you dropped bumps to the space BESIDE
    // it, not to the top-left corner of the screen.
    function findFreeSpot(screen, size, excludeId, prefX, prefY, boundsW, boundsH) {
        const W = boundsW || 1920
        const H = boundsH || 1080
        const w = root.widthOf(size)
        const h = root.heightOf(size)
        const step = root.unit + root.gap

        const clamp = (v, hi) => Math.max(root.gap, Math.min(hi, v))
        let px = clamp(prefX === undefined ? root.gap : prefX, W - w - root.gap)
        let py = clamp(prefY === undefined ? root.gap : prefY, H - h - root.gap)

        if (!root.collides(screen, px, py, size, excludeId)) return { x: px, y: py }

        for (let ring = 1; ring <= 12; ring++) {
            for (let dy = -ring; dy <= ring; dy++) {
                for (let dx = -ring; dx <= ring; dx++) {
                    // Only the ring's edge — the inside was covered by earlier rings.
                    if (Math.abs(dx) !== ring && Math.abs(dy) !== ring) continue
                    const nx = clamp(px + dx * step, W - w - root.gap)
                    const ny = clamp(py + dy * step, H - h - root.gap)
                    if (!root.collides(screen, nx, ny, size, excludeId))
                        return { x: nx, y: ny }
                }
            }
        }
        // Nowhere free within a sensible search. Returning the preferred spot is the
        // honest fallback: overlapping is bad, refusing to place the widget is worse.
        return { x: px, y: py }
    }

    function remove(id) {
        root.widgets = root.widgets.filter(w => w.id !== id)
        root._persist()
    }

    // Drops that land on another widget slide to the nearest free slot instead of
    // stacking. The caller passes the screen size so the search cannot push a tile off
    // the edge of a monitor it does not know the dimensions of.
    function move(id, x, y, boundsW, boundsH) {
        const me = root.get(id)
        if (!me) return
        const spot = root.findFreeSpot(me.screen, me.size, id,
                                       Math.round(x), Math.round(y), boundsW, boundsH)
        root.widgets = root.widgets.map(w =>
            w.id === id ? Object.assign({}, w, { x: spot.x, y: spot.y }) : w)
        root._persist()
    }

    function setScreen(id, name) {
        root.widgets = root.widgets.map(w =>
            w.id === id ? Object.assign({}, w, { screen: name }) : w)
        root._persist()
    }

    function setSize(id, size) {
        const w = root.get(id)
        if (!w) return
        const meta = root.info(w.type)
        // A type only offers the sizes its layouts actually handle — a clock has no
        // large form, and silently accepting one would render an empty half-tile.
        if (meta && meta.sizes.indexOf(size) === -1) return
        root.widgets = root.widgets.map(x =>
            x.id === id ? Object.assign({}, x, { size: size }) : x)
        // Growing a tile can swallow its neighbour, so the new footprint is re-seated
        // the same way a drop is. Done after the size is applied, because the free-spot
        // search measures the size the widget now IS.
        const after = root.get(id)
        if (after && root.collides(after.screen, after.x, after.y, size, id)) {
            const spot = root.findFreeSpot(after.screen, size, id, after.x, after.y)
            root.widgets = root.widgets.map(x =>
                x.id === id ? Object.assign({}, x, { x: spot.x, y: spot.y }) : x)
        }
        root._persist()
    }

    function setOpt(id, key, value) {
        root.widgets = root.widgets.map(w => {
            if (w.id !== id) return w
            const opts = Object.assign({}, w.opts)
            opts[key] = value
            return Object.assign({}, w, { opts: opts })
        })
        root._persist()
    }

    function _defaultOpts(type) {
        if (type === "clock")     return { seconds: false, hour24: true }
        if (type === "notes")     return { text: "" }
        if (type === "reminders") return { items: [] }
        if (type === "timer")     return { stopwatch: false }
        if (type === "photo")     return { seconds: 30 }
        if (type === "disk")      return { mount: "/" }
        if (type === "countdown") return { date: "", label: "" }
        // Seeded rather than empty. A world clock with no zones is a tile that says
        // "go and configure me", which is a worse first impression than three cities
        // you can edit — and the offsets are only a starting point either way, since
        // they are the user's to correct across a daylight-saving boundary.
        if (type === "worldclock")
            return { hour24: true,
                     zones: [{ label: "New York", offset: -4 },
                             { label: "London",   offset:  1 },
                             { label: "Tokyo",    offset:  9 }] }
        return {}
    }

    // ── Reminders ─────────────────────────────────────────────────────────────
    // Item ids come from the SAME sequence the widgets use. The first version used
    // `Date.now()`, reasoning that ids only have to be unique within one list — which
    // is true, and still wrong: two reminders added in the same millisecond get the
    // same timestamp. Typing two items quickly, or adding them from a script, produced
    // duplicate ids, and then ticking one ticked both. Caught by a test that added two
    // in a row; a monotonic counter cannot collide however fast you type.
    function addReminder(id, text) {
        const t = (text || "").trim()
        if (t === "") return
        const w = root.get(id)
        if (!w) return
        const items = (w.opts.items ?? []).slice()
        items.push({ id: root._seq++, text: t, done: false })
        root.setOpt(id, "items", items)
    }

    function toggleReminder(id, itemId) {
        const w = root.get(id)
        if (!w) return
        root.setOpt(id, "items", (w.opts.items ?? []).map(
            it => it.id === itemId ? Object.assign({}, it, { done: !it.done }) : it))
    }

    function removeReminder(id, itemId) {
        const w = root.get(id)
        if (!w) return
        root.setOpt(id, "items", (w.opts.items ?? []).filter(it => it.id !== itemId))
    }

    function clearDone(id) {
        const w = root.get(id)
        if (!w) return
        root.setOpt(id, "items", (w.opts.items ?? []).filter(it => !it.done))
    }

    // ── World clock zones ─────────────────────────────────────────────────────
    // Addressed by INDEX rather than by an id, unlike reminders. A zone list is edited
    // from one settings panel and never from two places at once, so there is no window
    // in which an index can go stale — and an id would have to be persisted for a list
    // whose whole content is two editable fields.
    function addZone(id, label, offset) {
        const w = root.get(id)
        if (!w) return
        const zones = (w.opts.zones ?? []).slice()
        zones.push({ label: label ?? "New city", offset: offset ?? 0 })
        root.setOpt(id, "zones", zones)
    }

    function setZone(id, index, key, value) {
        const w = root.get(id)
        if (!w) return
        const zones = (w.opts.zones ?? []).slice()
        if (index < 0 || index >= zones.length) return
        zones[index] = Object.assign({}, zones[index])
        zones[index][key] = value
        root.setOpt(id, "zones", zones)
    }

    function removeZone(id, index) {
        const w = root.get(id)
        if (!w) return
        root.setOpt(id, "zones", (w.opts.zones ?? []).filter((z, i) => i !== index))
    }

    // ── Presets ───────────────────────────────────────────────────────────────
    // Named whole-desktop layouts, the same idea as the bar's. Stored in the SHELL
    // directory rather than in state, like `presets/bar.json`, because a preset is
    // something you author and might want to keep alongside the config — not runtime
    // state that happens to persist.
    //
    // A preset stores the widgets VERBATIM, content included: saving a layout with a
    // half-written note and restoring it later should give you the note back. The ids
    // are re-issued on load so a restore cannot collide with widgets already placed.
    property var presets: ({})
    readonly property var presetNames: Object.keys(root.presets).sort()

    function savePreset(name) {
        const n = (name || "").trim()
        if (n === "") return
        const next = Object.assign({}, root.presets)
        next[n] = root.widgets
        root.presets = next
        presetStore.value = { presets: next }
    }

    function deletePreset(name) {
        const next = {}
        for (const k in root.presets) if (k !== name) next[k] = root.presets[k]
        root.presets = next
        presetStore.value = { presets: next }
    }

    // REPLACES the current desktop rather than merging. A preset is a layout, and
    // merging two layouts is how you get widgets on top of each other — the exact thing
    // findFreeSpot exists to prevent.
    function applyPreset(name, screen) {
        const p = root.presets[name]
        if (!p) return
        const kept = screen ? root.widgets.filter(w => w.screen !== screen) : []
        const out = kept.slice()
        for (const w of p) {
            out.push(Object.assign({}, w, {
                id: root._seq++,
                screen: screen || w.screen,
                opts: JSON.parse(JSON.stringify(w.opts ?? {}))
            }))
        }
        root.widgets = out
        root._persist()
    }

    JsonStore {
        id: presetStore
        path: Quickshell.shellPath("presets/widgets.json")
        defaults: ({ presets: {} })
        onLoaded: root.presets = presetStore.value.presets ?? ({})
    }

    // ── Persistence ───────────────────────────────────────────────────────────
    JsonStore {
        id: store
        path: Quickshell.statePath("widgets.json")
        defaults: ({ widgets: [], seq: 1 })

        onLoaded: {
            // The read is asynchronous. If the user has already placed or typed
            // something by the time it lands, applying the file would discard that —
            // the same late-load trap Timers documents. Live state wins.
            //
            // But it has to be WRITTEN, not merely kept: `_persist` refuses while the
            // store is unready, so anything done in that window was live in memory and
            // absent from disk. A widget added during startup and never touched again
            // vanished on the next reload. Flushing here is what closes that gap.
            //
            // ── The clobber guard, and why it exists ──────────────────────────
            // "Live state wins" is right for a widget you just placed and WRONG for an
            // empty list. `_persist` marks `_touched` and then returns when the store
            // is not ready yet, so a single mutation attempt during startup was enough
            // to arm this branch — and it would then write an EMPTY `widgets` over a
            // populated file, destroying every placed widget with no way back.
            //
            // So memory only wins when memory actually has something in it. An empty
            // list defers to the file. The cost of being wrong in this direction is a
            // widget you deleted coming back, which you can delete again; the cost of
            // being wrong the other way is losing the lot.
            const fromFile = store.value.widgets ?? []
            if (root._touched && root.widgets.length > 0) {
                // Carry the sequence forward past anything the file already used, or a
                // restored file could hand out an id that memory has also issued.
                root._seq = Math.max(root._seq, store.value.seq ?? 1)
                store.value = { widgets: root.widgets, seq: root._seq }
                return
            }
            root._loading = true
            root.widgets  = fromFile
            root._seq     = Math.max(store.value.seq ?? 1, root._seq)
            root._loading = false
        }
    }

    function _persist() {
        // The `_loading` check comes FIRST. Applying the file assigns `widgets`, which
        // reaches here — marking `_touched` before this returned meant merely LOADING
        // the store armed the flush branch above.
        if (root._loading) return
        root._touched = true
        if (!store.ready) return
        store.value = { widgets: root.widgets, seq: root._seq }
    }
}
