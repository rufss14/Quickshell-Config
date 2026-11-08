pragma Singleton
import Quickshell
import QtQuick
import "../config"
import "desktopwidgets.js" as Rules

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
    //
    // `category` groups the gallery (WidgetsPage) — one string per row, so a new
    // widget stays "a catalogue row and a QML file" the same way `editable` already
    // does. The four groupings below are a first cut, not a technical constraint;
    // relabelling or regrouping later touches only this file.
    readonly property var catalogue: [
        { type: "clock",     label: "Clock",     glyph: "󰅐",
          detail: "Time and date",              sizes: ["small", "medium"],
          category: "Time" },
        { type: "calendar",  label: "Calendar",  glyph: "󰃭",
          detail: "This month at a glance",     sizes: ["small", "medium", "large"],
          category: "Time" },
        { type: "weather",   label: "Weather",   glyph: "󰖕",
          detail: "Current conditions and forecast", sizes: ["small", "medium", "large"],
          category: "Info" },
        // `editable` means the widget takes TYPED input, which is what decides whether
        // the desktop layer asks for keyboard focus at all. It lives here rather than as
        // a list of type names inside the layer, so adding a widget stays a matter of a
        // catalogue row and a QML file — which is what the comment above promises.
        { type: "notes",     label: "Notes",     glyph: "󰎞",
          detail: "A scratch pad you can type in",   sizes: ["medium", "large"],
          editable: true, category: "Personal" },
        { type: "reminders", label: "Reminders", glyph: "󰄹",
          detail: "A checklist that persists",  sizes: ["medium", "large"],
          editable: true, category: "Personal" },

        // ── Live tiles ────────────────────────────────────────────────────────
        // Each of these is a view over a service the shell already runs, and every one
        // of those services is refcounted — so a type that is not placed costs nothing.
        // `bare` means the tile draws NO frame of its own by default — its content is
        // already one of the overview's cards, and a frame around a card is a box around
        // a box. Still a default, not a rule: the per-tile option overrides it.
        // Not bare any more (2026-10-30): it draws its own layout on the tile now, not the
        // overview's card. See NowplayingWidget.
        { type: "nowplaying", label: "Now playing", glyph: "󰎈",
          detail: "What's playing, with transport controls",
          sizes: ["medium", "large"], category: "Media" },
        // Medium and large only. The lyrics card is a COLUMN of rows that scrolls the
        // current line to its middle — at 168×168 it would show one line and a half, which
        // is a caption, not a lyrics view.
        // Framed like every tile since 2026-10-30: the card draws no surface of its own on
        // the desktop any more (LyricsWidget), so the tile's is the background.
        { type: "lyrics",    label: "Lyrics",      glyph: "󰲹",
          detail: "Synced lyrics for whatever is playing",
          sizes: ["medium", "large"], category: "Media" },
        { type: "sysmon",    label: "System",      glyph: "󰍛",
          detail: "CPU, memory and temperature",  sizes: ["small", "medium", "large"],
          category: "Info" },
        { type: "visualizer", label: "Visualizer", glyph: "󰄨",
          detail: "A spectrum of whatever is playing",
          sizes: ["small", "medium", "large"], category: "Media" },
        { type: "network",   label: "Network",     glyph: "󰛳",
          detail: "Up and down, live",            sizes: ["small", "medium", "large"],
          category: "Info" },
        { type: "clipboard", label: "Clipboard",   glyph: "󰅌",
          detail: "Recent copies, click to copy back", sizes: ["medium", "large"],
          category: "Personal" },
        { type: "timer",     label: "Timer",       glyph: "󰔛",
          detail: "Timer and stopwatch",          sizes: ["small", "medium"],
          category: "Time" },
        { type: "disk",      label: "Disk space",  glyph: "󰋊",
          detail: "How much room is left",        sizes: ["small", "medium", "large"],
          category: "Info" },
        { type: "updates",   label: "Updates",     glyph: "󰚰",
          detail: "Packages waiting to install",  sizes: ["small", "medium"],
          category: "Info" },
        // `multiple`: the one type you may place more than once on a screen — each frame
        // holds its own picture or folder, so two are two different things, not a copy.
        // Bare by default: the picture IS the tile, edge to edge or cut to a shape.
        { type: "photo",     label: "Photo frame", glyph: "󰋩",
          detail: "A picture, a folder, or your wallpapers", sizes: ["small", "medium", "large"],
          multiple: true, bare: true, category: "Media" },

        // ── Arithmetic tiles ──────────────────────────────────────────────────
        // No service and no process behind these — just the system clock.
        { type: "worldclock", label: "World clock", glyph: "󰇧",
          detail: "The time somewhere else",      sizes: ["small", "medium", "large"],
          category: "Time" },
        { type: "sun",       label: "Sun",         glyph: "󰖙",
          detail: "Sunrise, sunset and the day's arc", sizes: ["medium", "large"],
          category: "Time" },
        { type: "countdown", label: "Countdown",   glyph: "󰃯",
          detail: "Days until a date you set",    sizes: ["small", "medium"],
          category: "Time" },

        // ── 2026-10-30 ────────────────────────────────────────────────────────
        // Devices and toggles are views over services that already run (DeviceBatteries,
        // ShellActions); the stack holds other tiles; habits is typed content like reminders.
        { type: "devices",   label: "Devices",       glyph: "\u{F0FB0}",
          detail: "Battery of your mouse, headset, controller…", sizes: ["small", "medium", "large"],
          category: "Info" },
        { type: "toggles",   label: "Quick toggles", glyph: "\u{F0A1D}",
          detail: "Wi-Fi, Bluetooth, Do not disturb, night light", sizes: ["small", "medium", "large"],
          category: "Personal" },
        { type: "stack",     label: "Smart stack",   glyph: "\u{F0570}",
          detail: "Several widgets in one; it flips to what matters", sizes: ["small", "medium", "large"],
          category: "Info" },
        { type: "habits",    label: "Habits",        glyph: "\u{F00ED}",
          detail: "A week of ticks per habit, with streaks", sizes: ["medium", "large"],
          editable: true, category: "Personal" }
    ]

    function info(type) {
        return root.catalogue.find(c => c.type === type) ?? null
    }

    // ── Does this tile draw its own frame? ────────────────────────────────────
    // ONE definition, because the settings switch and the frame itself have to agree.
    // Resolved twice they would not: the catalogue defaults these media tiles to bare, so
    // a switch reading `!opts.bare` shows "frame on" over a tile that is rendering without
    // one — the same two-sources-of-truth shape that produced every layout bug in the
    // lyrics card.
    //
    // `opts.bare` absent means "whatever this type does by default"; setOpt(…, undefined)
    // is how the page clears back to that.
    function isBare(rec) {
        if (!rec) return false
        return (rec.opts ?? {}).bare ?? (root.info(rec.type)?.bare ?? false)
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
        // A week with some ticks in it, relative to today, so the preview shows streaks.
        if (type === "habits") {
            const today = Rules.isoDay(new Date())
            const ago = n => Rules.dayShift(today, -n)
            return { habits: [{ id: 1, name: "Read",    days: [ago(4), ago(3), ago(2), ago(1), today] },
                              { id: 2, name: "Workout", days: [ago(5), ago(3), ago(1)] },
                              { id: 3, name: "Water",   days: [ago(2), ago(1)] }] }
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

    // The tiles `name` shows: its records in the layout that screen is showing (see "Live
    // layouts per wallpaper" below). Everything that asks "what is on this screen" — the
    // layer, collisions, the one-per-type rule, the settings map — comes through here, so
    // they all see the same layout.
    function forScreen(name) {
        const layout = root.layoutOn(name)
        return root.widgets.filter(w => w.screen === name && Rules.inLayout(w, layout))
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
        return root.forScreen(name).map(w => w.id)
    }

    // Where each tile on `name` is DRAWN on a layer of W×H — the stored position, pulled
    // in when the layer is smaller than the layout was placed on (the dock's reserve).
    // Display only; see desktopwidgets.js fit().
    function fitFor(name, W, H) {
        return Rules.fit(root.forScreen(name), W, H,
                         w => ({ w: root.widthOf(w.size), h: root.heightOf(w.size) }), root.gap)
    }

    function get(id) {
        return root.widgets.find(w => w.id === id) ?? null
    }

    // ── Mutation ──────────────────────────────────────────────────────────────
    // Every one of these REPLACES `widgets` with a new array rather than editing an
    // entry in place. An in-place mutation fires no change signal in QML, so the
    // desktop would not repaint and the store would never write — the same rule
    // JsonStore states about its own `value`, and the same trap Config.layout has.

    // ── One of each type, per screen (user's call) ───────────────────────────────
    // The settings page's gallery is one tile per type with a placed/not-placed
    // state, and `add()` below enforces the same rule for presets and IPC by
    // handing back the existing tile rather than stacking a second. The cases a
    // strict cap loses — two `disk` tiles for `/` and `/home`, two `countdown`s,
    // two region-split `worldclock`s — are worth revisiting if asked, but the
    // multi-instance options (mount, date, zones) already fold several readings
    // into one tile.
    //
    // `has()`/`count()` stay: the gallery reads `has()` for its checkmark.
    function has(type, screen) {
        return root.forScreen(screen).some(w => w.type === type)
    }

    function count(type, screen) {
        return root.forScreen(screen).filter(w => w.type === type).length
    }

    // A type that may be placed more than once per screen (catalogue `multiple`).
    function isMulti(type) {
        return root.info(type)?.multiple === true
    }

    function add(type, screen, x, y) {
        const meta = root.info(type)
        if (!meta) return -1
        // One of each type per screen. The settings page's switch enforces this,
        // but a preset or IPC could still ask — hand back the existing one. Unless
        // the type is `multiple` (the photo frame): then every add is a new tile.
        const dup = meta.multiple ? null : root.forScreen(screen).find(w => w.type === type)
        if (dup) return dup.id
        const id   = root._seq++
        const size = meta.sizes[0]
        // Placed where asked, or in the first free slot — never on top of something
        // already there. A tile dropped under another is invisible AND unreachable.
        const spot = root.findFreeSpot(screen, size, -1,
                                       x === undefined ? root.gap : x,
                                       y === undefined ? root.gap : y)
        const list = root.widgets.slice()
        list.push(root._inLayoutOf(screen, {
            id: id, type: type, screen: screen,
            x: spot.x, y: spot.y,
            size: size,
            opts: root._defaultOpts(type)
        }))
        root.widgets = list
        root._persist()
        return id
    }

    // A record placed into the layout `screen` is showing. The normal layout carries no
    // field at all, so every record from before layouts existed is in it by definition.
    function _inLayoutOf(screen, rec) {
        const layout = root.layoutOn(screen)
        const out = Object.assign({}, rec)
        if (layout !== "") out.layout = layout
        else delete out.layout
        return out
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
        // Only the layout the screen shows: another wallpaper's tiles aren't in the way.
        return root.forScreen(screen).some(w =>
            w.id !== excludeId && root._hits(me, root._rectOf(w)))
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

    // ── Putting one back ──────────────────────────────────────────────────────
    // For the settings page's undo. Re-seats the record as it was — same screen,
    // same position, same options — rather than going through add(), which would
    // hand it a fresh id and drop it in the first free slot. `opts` is deep-copied
    // so the restored widget cannot share an object with anything still holding the
    // old record.
    function restoreWidget(rec) {
        if (!rec || rec.id === undefined) return
        if (root.widgets.some(w => w.id === rec.id)) return
        const next = root.widgets.slice()
        next.push(Object.assign({}, rec, {
            opts: JSON.parse(JSON.stringify(rec.opts ?? {}))
        }))
        root.widgets = next
        root._persist()
    }

    // A copy of a placed widget, seated in the nearest free spot to the original —
    // same reasoning as `add()`, never on top of the thing it's a copy of. `opts` is
    // deep-copied (JSON round-trip, the same idiom `applyPreset` uses) so editing the
    // duplicate's mount point or countdown date can never reach back and edit the
    // original's.
    function duplicate(id) {
        const w = root.get(id)
        if (!w) return -1
        const newId = root._seq++
        const spot  = root.findFreeSpot(w.screen, w.size, -1, w.x, w.y)
        const list  = root.widgets.slice()
        list.push(Object.assign({
            id: newId, type: w.type, screen: w.screen,
            x: spot.x, y: spot.y,
            size: w.size,
            opts: JSON.parse(JSON.stringify(w.opts ?? {}))
        }, w.layout ? { layout: w.layout } : {}))
        root.widgets = list
        root._persist()
        return newId
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

    // Moves a widget to another screen. Re-seats through `findFreeSpot` on arrival —
    // the target screen has its own occupants and its own dimensions, and the
    // widget's old x/y is almost certainly wrong for both. The old position is still
    // passed in as the PREFERRED spot: `findFreeSpot`'s own clamp already pulls an
    // off-screen preference back inside `boundsW`/`boundsH` before it searches, so a
    // widget that lived at (1800, 40) on a 1920-wide monitor lands sensibly rather
    // than off the edge of a 1366-wide one.
    function setScreen(id, name, boundsW, boundsH) {
        const w = root.get(id)
        if (!w) return
        const spot = root.findFreeSpot(name, w.size, -1, w.x, w.y, boundsW, boundsH)
        // Into the layout the target screen is showing — moved to a screen, it should be
        // on that screen, not filed under a layout it doesn't show.
        root.widgets = root.widgets.map(x =>
            x.id === id ? root._inLayoutOf(name, Object.assign({}, x, { screen: name, x: spot.x, y: spot.y })) : x)
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

    // A tile's starting options — for a card inside a smart stack, which has no record of its own.
    function defaultOpts(type) { return root._defaultOpts(type) }

    function _defaultOpts(type) {
        if (type === "clock")     return { seconds: false, hour24: true }
        if (type === "notes")     return { text: "" }
        if (type === "reminders") return { items: [] }
        if (type === "timer")     return { stopwatch: false }
        if (type === "photo")     return { seconds: 30, source: "library", shape: "rect" }
        if (type === "disk")      return { mount: "/" }
        if (type === "countdown") return { date: "", label: "" }
        if (type === "habits")    return { habits: [] }
        // Eight, so large has a full 2×4; small and medium show the first four.
        if (type === "toggles")
            return { toggles: ["wifi", "bluetooth", "dnd", "nightlight", "awake", "gamemode", "mute", "micMute"] }
        // The cards a stack starts with — any that don't come in the stack's size are skipped.
        if (type === "stack")
            return { cards: ["weather", "calendar", "sysmon", "nowplaying", "visualizer"], smart: true, rotate: 0 }
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

    // ── Habits ────────────────────────────────────────────────────────────────
    // Ids from the shared sequence, for the reason reminders give (above). The day maths
    // is desktopwidgets.js (toggleDay, streak — tested).
    function addHabit(id, name) {
        const t = (name || "").trim()
        if (t === "") return
        const w = root.get(id)
        if (!w) return
        const habits = (w.opts.habits ?? []).slice()
        habits.push({ id: root._seq++, name: t, days: [] })
        root.setOpt(id, "habits", habits)
    }

    function toggleHabit(id, habitId, iso) {
        const w = root.get(id)
        if (!w) return
        root.setOpt(id, "habits", (w.opts.habits ?? []).map(
            h => h.id === habitId ? Object.assign({}, h, { days: Rules.toggleDay(h.days, iso) }) : h))
    }

    function removeHabit(id, habitId) {
        const w = root.get(id)
        if (!w) return
        root.setOpt(id, "habits", (w.opts.habits ?? []).filter(h => h.id !== habitId))
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

    // ══ Live layouts per wallpaper ═══════════════════════════════════════════
    // A wallpaper can have a layout of its OWN (the user's call, 2026-10-30): bind one and,
    // whenever a screen shows that wallpaper, it shows that layout's tiles instead of the
    // normal ones. LIVE, not a preset applied on switch: a layout's tiles are ordinary
    // records carrying `layout: "<name>"` (the normal layout carries none), so moving a tile
    // or typing in a note on it is saved where it is, switching is a filter change, and
    // nothing is ever copied over anything. A wallpaper with no binding shows the normal
    // layout. It follows per-workspace wallpapers: a screen's layout is the one bound to
    // the picture ITS workspace shows.
    //
    //   bindings        wallpaper key → layout name, saved in widgets.json beside the tiles
    //                   (a layout without its wallpaper means nothing, and vice versa)
    //   activeLayouts   screen → the layout it is SHOWING, and wallKeys screen → its
    //                   wallpaper's key; both published by each screen's WidgetLayer, which
    //                   is what knows its workspace and holds the old layout while it leaves
    //
    // A key is the wallpaper's value — a `~`-relative path, "scene:<id>", or "material" —
    // never the still a scene shows, which changes when its first frame is captured.
    property var bindings: ({})
    property var activeLayouts: ({})
    property var wallKeys: ({})

    function layoutOn(screen) { return root.activeLayouts[screen] ?? "" }

    function setActive(screen, layout, key) {
        if (!screen) return
        if ((root.activeLayouts[screen] ?? "") !== (layout ?? "")) {
            const next = Object.assign({}, root.activeLayouts)
            next[screen] = layout ?? ""
            root.activeLayouts = next
        }
        if ((root.wallKeys[screen] ?? "") !== (key ?? "")) {
            const next = Object.assign({}, root.wallKeys)
            next[screen] = key ?? ""
            root.wallKeys = next
        }
    }

    // The wallpaper a screen showing workspace `ws` wears, as a binding key.
    function wallKeyFor(ws) {
        if (Config.wallMaterial) return "material"
        const own = Wallpaper.perWorkspace ? Wallpaper.wallFor(ws) : ""
        const v = own !== "" ? own
                : (WallpaperEngine.sharedIsScene && Config.wpeCurrent !== "") ? "scene:" + Config.wpeCurrent
                : Wallpaper.currentPath
        return v === "" ? "" : root.contractPath(v)
    }
    function layoutForKey(key) { return key ? (root.bindings[key] ?? "") : "" }
    function wallName(key) { return Rules.wallName(key) }

    // Every tile on screen right now, across screens: each screen's shown layout.
    readonly property var shown: root.widgets.filter(w => Rules.inLayout(w, root.layoutOn(w.screen)))

    // Every named layout — any a record lives in or a wallpaper is bound to — with the
    // wallpapers bound to it: [{ name, keys: [...], tiles }], by name.
    readonly property var layouts: {
        const byName = {}
        const add = n => byName[n] ?? (byName[n] = { name: n, keys: [], tiles: 0 })
        for (const w of root.widgets) if (w.layout) add(w.layout).tiles++
        for (const k in root.bindings) add(root.bindings[k]).keys.push(k)
        return Object.keys(byName).sort().map(n => byName[n])
    }

    // Show layout `name` on wallpaper `key` (an existing layout, or a new empty one).
    function bindWallpaper(key, name) {
        if (!key || !name) return
        const next = Object.assign({}, root.bindings)
        next[key] = name
        root.bindings = next
        root._persist()
    }

    // Back to the normal layout on `key`. The layout's tiles are KEPT — it is still listed
    // and can be bound again; deleting it is deleteLayout, a separate, undoable step.
    function unbindWallpaper(key) {
        if (!key || root.bindings[key] === undefined) return
        const next = {}
        for (const k in root.bindings) if (k !== key) next[k] = root.bindings[k]
        root.bindings = next
        root._persist()
    }

    // A new layout for wallpaper `key`, named after it, seeded from `seed`:
    //   "copy"          what `screen` shows now (the usual start: then change what differs)
    //   "empty"         nothing
    //   "preset:<name>" a saved preset, laid out on `screen`
    // Returns the layout's name. The seeded tiles are new records with new ids: the
    // original layout is untouched.
    function newLayoutFor(key, screen, seed) {
        if (!key) return ""
        const name = Rules.uniqueName(Rules.wallName(key), root.layouts.map(l => l.name))
        let src = []
        if (seed === "copy") src = root.forScreen(screen)
        else if ((seed || "").indexOf("preset:") === 0) {
            const p = root.presets[seed.slice(7)]
            if (p) src = Rules.presetFor(p, screen, t => root.isMulti(t)).map(w => Object.assign({}, w, { screen: screen }))
        }
        if (src.length > 0) {
            const list = root.widgets.slice()
            for (const w of src) {
                list.push(Object.assign({}, w, {
                    id: root._seq++,
                    layout: name,
                    opts: JSON.parse(JSON.stringify(w.opts ?? {}))
                }))
            }
            root.widgets = list
        }
        root.bindWallpaper(key, name)
        return name
    }

    // Removes a layout: its tiles and every binding to it. Returns what it removed, for
    // the settings page's undo (restoreLayout) — a layout can hold typed notes.
    function deleteLayout(name) {
        if (!name) return null
        const gone = { name: name, tiles: root.widgets.filter(w => w.layout === name), keys: [] }
        const next = {}
        for (const k in root.bindings) {
            if (root.bindings[k] === name) gone.keys.push(k)
            else next[k] = root.bindings[k]
        }
        root.widgets = root.widgets.filter(w => w.layout !== name)
        root.bindings = next
        root._persist()
        return gone
    }

    function restoreLayout(gone) {
        if (!gone || !gone.name) return
        const ids = {}
        for (const w of root.widgets) ids[w.id] = true
        root.widgets = root.widgets.concat(gone.tiles.filter(w => !ids[w.id]))
        const next = Object.assign({}, root.bindings)
        for (const k of gone.keys) next[k] = gone.name
        root.bindings = next
        root._persist()
    }

    // ── Paths a tile names ────────────────────────────────────────────────────
    // The photo frame's folder or picture: stored `~`-relative (contractPath, when the
    // picker hands one over) and expanded only here (expandPath, when a tile reads it).
    // desktopwidgets.js says why — presets are saved into the published repo.
    readonly property string _home: Quickshell.env("HOME") || ""
    function expandPath(p)   { return Rules.expandHome(p, root._home) }
    function contractPath(p) { return Rules.contractHome(p, root._home) }

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

    // What is ON SCREEN now — each screen's shown layout — without the layout field: a
    // preset is a layout to put somewhere, not a copy of every layout you have.
    function savePreset(name) {
        const n = (name || "").trim()
        if (n === "") return
        const next = Object.assign({}, root.presets)
        next[n] = root.shown.map(w => { const c = Object.assign({}, w); delete c.layout; return c })
        root.presets = next
        presetStore.value = { presets: next }
    }

    function deletePreset(name) {
        const next = {}
        for (const k in root.presets) if (k !== name) next[k] = root.presets[k]
        root.presets = next
        presetStore.value = { presets: next }
    }

    // ── Putting one back ──────────────────────────────────────────────────────
    // For the settings page's undo. NOT savePreset(name), which would store whatever
    // is on the desktop NOW — undoing a delete has to restore the layout that was in
    // the preset, not the one you happen to be looking at.
    function restorePreset(name, list) {
        const n = (name || "").trim()
        if (n === "" || !Array.isArray(list)) return
        const next = Object.assign({}, root.presets)
        next[n] = list
        root.presets = next
        presetStore.value = { presets: next }
    }

    // REPLACES the current desktop rather than merging. A preset is a layout, and
    // merging two layouts is how you get widgets on top of each other — the exact thing
    // findFreeSpot exists to prevent.
    //
    // Applied to one screen, it places THAT screen's saved layout, not every screen's
    // stacked together — a preset holds the whole multi-monitor desktop. And one of
    // each type per screen, the rule add() enforces. See desktopwidgets.js.
    //
    // With layouts, "the desktop" is the layout each screen is SHOWING: only that one is
    // replaced. Every other layout's tiles — another wallpaper's notes — are kept.
    function applyPreset(name, screen) {
        const p = root.presets[name]
        if (!p) return
        const kept = root.widgets.filter(w => screen
            ? !(w.screen === screen && Rules.inLayout(w, root.layoutOn(screen)))
            : !Rules.inLayout(w, root.layoutOn(w.screen)))
        const out = kept.slice()
        for (const w of Rules.presetFor(p, screen, t => root.isMulti(t))) {
            const on = screen || w.screen
            out.push(root._inLayoutOf(on, Object.assign({}, w, {
                id: root._seq++,
                screen: on,
                opts: JSON.parse(JSON.stringify(w.opts ?? {}))
            })))
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
        defaults: ({ widgets: [], seq: 1, bindings: {} })

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
                root.bindings = Object.assign({}, store.value.bindings ?? {}, root.bindings)
                store.value = { widgets: root.widgets, seq: root._seq, bindings: root.bindings }
                return
            }
            // Stacked duplicates (a duplicated preset's leftovers) are dropped on the way
            // in and the cleaned list written back, so the fix is permanent rather than
            // re-done every launch. desktopwidgets.js has the exact rule and what it
            // refuses to touch.
            const cleaned = Rules.dropStacked(fromFile, t => root.takesText(t))
            root._loading = true
            root.widgets  = cleaned
            root._seq     = Math.max(store.value.seq ?? 1, root._seq)
            root.bindings = store.value.bindings ?? ({})
            root._loading = false
            if (cleaned.length !== fromFile.length) {
                console.info("DesktopWidgets: removed " + (fromFile.length - cleaned.length)
                             + " stacked duplicate tile(s)")
                store.value = { widgets: root.widgets, seq: root._seq, bindings: root.bindings }
            }
        }
    }

    function _persist() {
        // The `_loading` check comes FIRST. Applying the file assigns `widgets`, which
        // reaches here — marking `_touched` before this returned meant merely LOADING
        // the store armed the flush branch above.
        if (root._loading) return
        root._touched = true
        if (!store.ready) return
        store.value = { widgets: root.widgets, seq: root._seq, bindings: root.bindings }
    }
}
