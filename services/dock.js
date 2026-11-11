.pragma library

// ── dock.js ───────────────────────────────────────────────────────────────────
// The arithmetic behind the dock: which apps it shows and in what order, how
// windows group under an app, which window a click lands on, and where a dragged
// icon would drop.
//
// ── Why these are here and not inline in the strip ────────────────────────────
// Same reason as workspaces.js and calc.js: `bun scripts/test-dock.js` can reach
// a file like this, and a QML expression inside a delegate cannot. Every function
// below fails SILENTLY on screen when it is wrong — an icon drawn twice, a click
// that focuses the window you were already on, a pin that lands one slot short
// of where it was dropped — which is exactly the kind of bug that is noticed a
// week later and never traced back.
//
// Nothing here knows about Hyprland or QML. Windows arrive as plain records; a
// window's `ref` is whatever the caller wants handed back (the real
// HyprlandToplevel in the shell, a string in the tests).
// ─────────────────────────────────────────────────────────────────────────────

// ── dedupe ────────────────────────────────────────────────────────────────────
// First occurrence wins; empty keys are dropped. Pins written by two different
// generations of the dock can canonicalise to the same app ("Spotify" and
// "spotify" both resolve to spotify.desktop), and the dock must draw that app
// once, in the position of its FIRST pin.
function dedupe(keys) {
    // Null-prototype maps throughout: an app id is an arbitrary string, and on a
    // plain {} a key like "constructor" is already "present" before anything is
    // put there.
    const seen = Object.create(null)
    const out = []
    for (let i = 0; i < keys.length; i++) {
        const k = keys[i]
        if (!k || seen[k]) continue
        seen[k] = true
        out.push(k)
    }
    return out
}

// ── order ─────────────────────────────────────────────────────────────────────
// What the dock draws, left to right: every pin in pin order, then every running
// app that ISN'T pinned, in the order it was first seen. A pinned app that is
// running is drawn once, in its pinned slot, as a running icon — the Windows
// rule, and the one the old two-strip dock kept breaking by drawing it twice.
function order(pinned, running) {
    return dedupe(pinned.concat(running))
}

// ── group ─────────────────────────────────────────────────────────────────────
// Folds windows into one entry per app.
//
//     items: [{ key, ref, activated, urgent, seq }]   in OPENING order
//
// Returns { order: [key…], byKey: { key: group } }, where a group is
//
//     { key, windows: [ref…], recent, focused, urgent, count }
//
// `windows` keeps opening order on purpose, not recency: it is the model behind
// the hover preview, and thumbnails that reshuffled every time focus moved would
// jump out from under the pointer. Recency is a separate fact — `recent`, the
// window a plain click should land on — taken from `seq`, a focus counter the
// service bumps as windows take focus (0 = not focused since the shell started).
// Ties, including "none of them ever", go to the first-opened window.
function group(items) {
    const byKey = Object.create(null)
    const keys = []
    for (let i = 0; i < items.length; i++) {
        const it = items[i]
        if (!it || !it.key) continue

        let g = byKey[it.key]
        if (!g) {
            g = { key: it.key, windows: [], recent: null, focused: false,
                  urgent: false, count: 0, _seq: -1 }
            byKey[it.key] = g
            keys.push(it.key)
        }

        g.windows.push(it.ref)
        g.count++
        if (it.activated) g.focused = true
        if (it.urgent)    g.urgent  = true

        const s = it.seq || 0
        if (s > g._seq) { g._seq = s; g.recent = it.ref }
    }
    for (let i = 0; i < keys.length; i++) delete byKey[keys[i]]._seq
    return { order: keys, byKey: byKey }
}

// ── next ──────────────────────────────────────────────────────────────────────
// The window after `active` in `windows`, wrapping — what clicking an app that
// already has focus does (cycle its windows; Hyprland has no minimize to copy
// Windows with). Null for a lone window: cycling to the window you are already
// on would be a click that visibly does nothing while claiming to. An `active`
// that isn't in the list (focus is elsewhere) starts from the top.
function next(windows, active) {
    return cycle(windows, active, 1)
}

// ── cycle ─────────────────────────────────────────────────────────────────────
// next() in either direction — scrolling over an app walks its windows both ways.
// An `active` that isn't in the list starts from the top going forward, and from
// the bottom going back, so the first step always lands on an end.
function cycle(windows, active, dir) {
    if (!windows || windows.length < 2) return null
    const n = windows.length
    const i = windows.indexOf(active)
    if (i < 0) return dir < 0 ? windows[n - 1] : windows[0]
    return windows[((i + (dir < 0 ? -1 : 1)) % n + n) % n]
}

// ── dropTarget ────────────────────────────────────────────────────────────────
// Which slot a dragged icon would land in.
//
//     from      its own index in the drawn list
//     center    its centre along the strip's main axis, measured from slot 0's
//               leading edge (so the launcher button, if any, is already
//               subtracted out)
//     slot      one icon plus one gap
//     count     how many icons are drawn
//     pinCount  how many of those are pins (they come first — see order())
//
// The slot whose box contains the icon's centre wins, which is what makes a
// neighbour step aside at the moment the dragged icon is half over it.
//
// Pins stay among pins: dragging one past the last pin clamps to the end of the
// pinned run. Running order is not a stored thing (it is the order apps were
// opened in), so a running icon either lands among the pins — which PINS it
// there — or goes back where it came from.
function dropTarget(from, center, slot, count, pinCount) {
    if (count <= 0 || slot <= 0) return from
    const raw = Math.max(0, Math.min(count - 1, Math.floor(center / slot)))
    if (from < pinCount) return Math.min(raw, pinCount - 1)
    return raw < pinCount ? raw : from
}

// ── shift ─────────────────────────────────────────────────────────────────────
// How many slots icon `i` moves aside while icon `from` hovers over slot `to`:
// the icons between the two close the gap the dragged one left, and open one
// where it will land. Everything else stays put.
function shift(i, from, to) {
    if (from < 0 || to < 0 || from === to || i === from) return 0
    if (from < to && i > from && i <= to) return -1
    if (from > to && i >= to && i < from) return 1
    return 0
}

// ── fit ───────────────────────────────────────────────────────────────────────
// The largest box of the source's aspect ratio that fits inside `boxW × boxH`.
// A preview thumbnail is letterboxed inside a fixed tile rather than sized to
// the window, so the preview card keeps one size while its captures arrive —
// before the first frame lands the source size is unknown (0), and the answer
// is then the whole box, not a zero-sized sliver.
function fit(srcW, srcH, boxW, boxH) {
    if (!(srcW > 0) || !(srcH > 0)) return { w: boxW, h: boxH }
    const s = Math.min(boxW / srcW, boxH / srcH)
    return { w: Math.round(srcW * s), h: Math.round(srcH * s) }
}

// ── tileSize ──────────────────────────────────────────────────────────────────
// How big each preview tile may be along the row, so `count` of them fit in
// `avail` px with `gap` between them: `ideal` when there's room, shrinking
// evenly when there isn't, never below `min` (past that the thumbnail stops
// being recognisable, and the card is clamped to the screen instead).
function tileSize(count, avail, ideal, min, gap) {
    if (count <= 0) return ideal
    const each = (avail - gap * (count - 1)) / count
    return Math.floor(Math.max(min, Math.min(ideal, each)))
}

// ── idCandidates ──────────────────────────────────────────────────────────────
// The names something outside Hyprland (a PipeWire stream, an MPRIS player, a
// notification) might be known by, in the order worth trying against the dock's
// keys. Streams in particular report a BINARY, and binaries drift from the
// desktop entry in a handful of predictable ways — "zen-bin", "brave-browser",
// "google-chrome-stable" — so each is also offered with that suffix dropped.
// Lower-cased and deduplicated; empties dropped.
function idCandidates(names) {
    const out = []
    const seen = Object.create(null)
    function add(v) {
        if (!v) return
        const k = String(v).toLowerCase()
        if (seen[k]) return
        seen[k] = true
        out.push(k)
    }
    for (let i = 0; i < names.length; i++) {
        const v = names[i]
        if (!v) continue
        add(v)
        const stripped = String(v).toLowerCase().replace(/[-.](bin|browser|stable|beta|nightly)$/, "")
        add(stripped)
    }
    return out
}

// ── audioByKey ────────────────────────────────────────────────────────────────
// Playback streams folded per app: { key: { streams: [ref…], muted, level } }.
// `muted` only when EVERY stream is — one live tab in a browser is still sound.
// `level` is the loudest stream's, which is what a scroll starts from.
//
//     items: [{ key, ref, muted, level }]
function audioByKey(items) {
    const out = Object.create(null)
    for (let i = 0; i < items.length; i++) {
        const it = items[i]
        if (!it || !it.key) continue
        let a = out[it.key]
        if (!a) { a = out[it.key] = { streams: [], muted: true, level: 0 } }
        a.streams.push(it.ref)
        if (!it.muted) a.muted = false
        a.level = Math.max(a.level, it.level || 0)
    }
    return out
}

// ── playerByKey ───────────────────────────────────────────────────────────────
// One media player per app: the first one PLAYING, else the first one seen. A
// browser can expose a player per tab; the one making sound is the one the dock's
// controls should reach.
//
//     items: [{ key, ref, playing }]
function playerByKey(items) {
    const out = Object.create(null)
    const playing = Object.create(null)
    for (let i = 0; i < items.length; i++) {
        const it = items[i]
        if (!it || !it.key) continue
        if (out[it.key] === undefined || (it.playing && !playing[it.key])) {
            out[it.key] = it.ref
            playing[it.key] = !!it.playing
        }
    }
    return out
}

// ── badgeCounts ───────────────────────────────────────────────────────────────
// Unseen notifications per app: those newer than BOTH the shell's start (so a
// restored history from yesterday doesn't paint every icon) and the last moment
// that app was in front of you (seenAt[key], ms). { key: count }, zero omitted.
//
//     items: [{ key, time }]
function badgeCounts(items, seenAt, since) {
    const out = Object.create(null)
    for (let i = 0; i < items.length; i++) {
        const it = items[i]
        if (!it || !it.key) continue
        const floor = Math.max(since || 0, (seenAt && seenAt[it.key]) || 0)
        if ((it.time || 0) > floor) out[it.key] = (out[it.key] || 0) + 1
    }
    return out
}

// ── badgeText ─────────────────────────────────────────────────────────────────
// What fits on a badge: the count up to 9, then "9+".
function badgeText(n) {
    return n > 9 ? "9+" : String(n)
}

// ── overlaps ──────────────────────────────────────────────────────────────────
// Does any window rect cover the dock's rect? "Dodge windows" auto-hide asks this:
// the dock stays out while nothing is in its way and ducks into the frame the
// moment something is. Rects are {x, y, w, h}; touching edges don't count — a
// tiled window butting up against the dock's reserved strip isn't "under" it.
function overlaps(rect, rects) {
    if (!rect || !(rect.w > 0) || !(rect.h > 0)) return false
    for (let i = 0; i < rects.length; i++) {
        const r = rects[i]
        if (!r) continue
        if (r.x < rect.x + rect.w && rect.x < r.x + r.w
            && r.y < rect.y + rect.h && rect.y < r.y + r.h) return true
    }
    return false
}

// ── groupPerMonitor ───────────────────────────────────────────────────────────
// group(), once per monitor — for "each screen's dock shows the windows on that
// screen" (Windows' "taskbar where the window is open"). Items carry `monitor`.
// { monitorName: { order, byKey } }.
function groupPerMonitor(items) {
    return groupBy(items, "monitor")
}

// ── groupBy ───────────────────────────────────────────────────────────────────
// group(), once per value of `field` — per monitor, or per workspace for "this
// workspace only". Items with no value for the field belong nowhere.
function groupBy(items, field) {
    const split = Object.create(null)
    for (let i = 0; i < items.length; i++) {
        const it = items[i]
        const v = it ? it[field] : undefined
        if (v === undefined || v === null || v === "") continue
        if (!split[v]) split[v] = []
        split[v].push(it)
    }
    const out = Object.create(null)
    for (const v in split) out[v] = group(split[v])
    return out
}

// ── stepFocus ─────────────────────────────────────────────────────────────────
// Keyboard focus along the dock: -1 is the launcher button (when there is one),
// 0…count-1 the apps. Clamped, not wrapped — hitting the end and stopping is how
// every other row of buttons behaves under the arrow keys. Home/End jump.
function stepFocus(current, move, count, hasLauncher) {
    const lo = hasLauncher ? -1 : 0
    const hi = count - 1
    if (hi < lo) return lo
    if (move === "home") return lo
    if (move === "end")  return hi
    const next = current + (move < 0 ? -1 : 1)
    return Math.max(lo, Math.min(hi, next))
}

// ── fileUrlToPath / pathToFileUrl ─────────────────────────────────────────────
// A dropped file arrives as a URL; an app's Exec wants a path for %f and a URL
// for %u. Only local files — anything that isn't file:// yields "".
function fileUrlToPath(url) {
    const s = String(url || "")
    const m = /^file:\/\/(localhost)?(\/.*)$/.exec(s)
    if (!m) return ""
    try { return decodeURIComponent(m[2]) } catch (e) { return "" }
}

function pathToFileUrl(path) {
    return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
}

// ── execArgv ──────────────────────────────────────────────────────────────────
// An app's desktop-entry Exec line, with files substituted in — how "open this
// file with that app" works (a file dropped on its icon, a recent file in its
// jump list). Follows the Desktop Entry spec's quoting and field codes:
//
//   "…"            one argument; \" \` \$ \\ escape inside it
//   %f / %u        one file, as a path / as a file:// URL
//   %F / %U        every file, each its own argument
//   %i %c %k       (icon, name, location) dropped — nothing here needs them
//   %d %D %n %N %v %m   deprecated, dropped
//   %%             a literal %
//
// Returns { argv, acceptsFiles }. `acceptsFiles` is false when the line has no
// file code at all: the app would ignore the file, so a drop should refuse
// rather than launch it empty-handed and look like it worked.
function execArgv(exec, paths) {
    const files = paths || []
    const toks = []
    let cur = ""
    let started = false
    let inQuote = false
    const s = String(exec || "")
    for (let i = 0; i < s.length; i++) {
        const c = s[i]
        if (inQuote) {
            if (c === "\\" && i + 1 < s.length && "\"`$\\".indexOf(s[i + 1]) >= 0) { cur += s[++i]; continue }
            if (c === "\"") { inQuote = false; continue }
            cur += c
            continue
        }
        if (c === "\"") { inQuote = true; started = true; continue }
        if (c === " " || c === "\t") {
            if (started) { toks.push(cur); cur = ""; started = false }
            continue
        }
        cur += c
        started = true
    }
    if (started) toks.push(cur)

    const argv = []
    let accepts = false
    for (let i = 0; i < toks.length; i++) {
        const t = toks[i]
        if (t === "%f" || t === "%u") {
            accepts = true
            if (files.length > 0) argv.push(t === "%u" ? pathToFileUrl(files[0]) : files[0])
            continue
        }
        if (t === "%F" || t === "%U") {
            accepts = true
            for (let j = 0; j < files.length; j++)
                argv.push(t === "%U" ? pathToFileUrl(files[j]) : files[j])
            continue
        }
        // Dropped only when it was made of nothing BUT dropped codes ("%i") — a
        // quoted empty argument ("") is a real, empty argument and stays.
        let out = ""
        let onlyCodes = true
        let sawCode = false
        for (let j = 0; j < t.length; j++) {
            if (t[j] === "%" && j + 1 < t.length) {
                sawCode = true
                const code = t[++j]
                if (code === "%") { out += "%"; onlyCodes = false }
                else if (code === "f" || code === "F") { accepts = true; out += files[0] || ""; onlyCodes = false }
                else if (code === "u" || code === "U") { accepts = true; out += files.length ? pathToFileUrl(files[0]) : ""; onlyCodes = false }
                // every other code is dropped
                continue
            }
            out += t[j]
            onlyCodes = false
        }
        if (!(sawCode && onlyCodes)) argv.push(out)
    }
    return { argv: argv, acceptsFiles: accepts }
}

// ── insertTarget ──────────────────────────────────────────────────────────────
// Where an app dragged in from OUTSIDE the strip (the launcher) would land among
// the pins. `from` is its index if the dock already draws it (pinned or running
// — then it's an ordinary move, dropTarget's rules), or -1 for an app the dock
// doesn't have yet, which can go anywhere from the first pin to just after the
// last. `center` is measured like dropTarget's.
function insertTarget(from, center, slot, count, pinCount) {
    if (from >= 0) return dropTarget(from, center, slot, count, pinCount)
    if (slot <= 0) return pinCount
    return Math.max(0, Math.min(pinCount, Math.floor(center / slot + 0.5)))
}

// ── downloadDir ───────────────────────────────────────────────────────────────
// The Downloads folder from xdg-user-dirs' own file ($XDG_CONFIG_HOME/
// user-dirs.dirs, lines like XDG_DOWNLOAD_DIR="$HOME/Downloads"), falling back
// to ~/Downloads when there's no file or no entry. Only $HOME is expanded — it's
// the one variable the format allows. A value that isn't an absolute path after
// expansion is ignored rather than trusted.
function downloadDir(text, home) {
    const fallback = home + "/Downloads"
    const m = /^\s*XDG_DOWNLOAD_DIR\s*=\s*"([^"]*)"\s*$/m.exec(String(text || ""))
    if (!m) return fallback
    const dir = m[1].replace(/^\$HOME(?=\/|$)/, home).replace(/\/+$/, "")
    return dir.startsWith("/") ? dir : fallback
}

// ── magnify ───────────────────────────────────────────────────────────────────
// macOS-style magnification: how much a button's icon swells for a pointer `d`
// px away along the dock. Full `max` under the pointer, easing to 1 at `range`
// px out on a cosine, so neighbours rise and fall smoothly instead of stepping.
function magnify(d, range, max) {
    if (!(range > 0)) return 1
    const t = Math.min(1, Math.abs(d) / range)
    return 1 + (max - 1) * 0.5 * (1 + Math.cos(Math.PI * t))
}

// ── parseGioInfo ──────────────────────────────────────────────────────────────
// `gio info -a standard::type,standard::icon -- PATH`, read once when a file or
// folder is pinned to the dock: is it a folder, and which themed icon names
// describe it (most specific first, symbolic variants dropped — the dock draws
// full-colour icons). null for output that isn't an info block (a gio error).
function parseGioInfo(text) {
    const s = String(text || "")
    if (!/^attributes:/m.test(s)) return null
    const type = /^\s*standard::type:\s*(\d+)/m.exec(s)
    const icon = /^\s*standard::icon:\s*(.+)$/m.exec(s)
    const icons = icon
        ? icon[1].split(",").map(x => x.trim()).filter(x => x !== "" && !/-symbolic$/.test(x))
        : []
    return { dir: type ? Number(type[1]) === 2 : false, icons: icons }
}

// ── magnifyBoxes ──────────────────────────────────────────────────────────────
// Where magnified buttons reach, as boxes for the blob — so the welded dock's
// material swells around them instead of the icons poking out of its outline.
// One box per button swollen past `minScale`, in the strip's own coordinates:
// the button's square, scaled by its magnification from the dock's outer edge
// (bottom / left / right — see DockIconStrip.magnifyOrigin), plus `lift` inward.
//
//     centers  each button's centre along the strip (already minus any scroll)
//     scaleAt  centre → that button's current scale
//
// A box spans the whole button depth too, so it overlaps the dock's own lobe
// and the smooth-min welds the two into one bump.
function magnifyBoxes(centers, scaleAt, button, lift, edge, minScale) {
    const out = []
    for (let i = 0; i < centers.length; i++) {
        const c = centers[i]
        const m = scaleAt(c)
        if (!(m > minScale)) continue
        const size = button * m
        const grow = size - button + lift            // past the strip's inner face
        const start = c - size / 2
        if (edge === "left")       out.push({ x: 0,     y: start, w: button + grow, h: size })
        else if (edge === "right") out.push({ x: -grow, y: start, w: button + grow, h: size })
        else                       out.push({ x: start, y: -grow, w: size, h: button + grow })
    }
    return out
}

// ── magnifyBell ───────────────────────────────────────────────────────────────
// The blob's swell under magnification, as a few stacked boxes that together
// trace a bell — the SAME cosine the icons follow (magnify()) — centred on the
// pointer. The smooth-min rounds the steps between layers into one continuous
// hump. (One box per icon read as a lumpy staircase: neighbouring icons are
// different heights and each box is square.)
//
// Layer f (0 < f ≤ 1) is as tall as f of the peak and as wide as the part of the
// bell at least that tall, plus half an icon at that scale either side (the
// icon's own width). Clamped along the dock to [lo, hi] — the host keeps that
// clear of the dock's own rounded corners, where a layer ending ON the corner
// made a notch. Boxes are in the strip's coordinates and reach through the whole
// button depth so they overlap the dock's own lobe.
//
// Each box carries its own corner radius `r`: as round as the layer is tall
// (capped at half its length). With one small radius for every layer, each
// step's corners stood proud of the stack and the hump rippled; rounded to their
// own height, the layers' ends are quarter-circles that stack into a dome.
//
//     pointer  pointer position along the strip          range  magnify()'s
//     max      peak scale    amount  0..1 strength        button, lift  as usual
function magnifyBell(pointer, range, max, amount, button, lift, edge, lo, hi, layers) {
    const peak = button * (max - 1) * amount + lift
    if (!(amount > 0) || !(peak > 0) || !(hi > lo)) return []
    const out = []
    for (let k = 1; k <= layers; k++) {
        const f = k / layers
        // Distance from the pointer where the bell falls to f of its height:
        // 0.5·(1+cos(πt)) = f  →  t = acos(2f−1)/π
        const t = Math.acos(Math.max(-1, Math.min(1, 2 * f - 1))) / Math.PI
        const half = t * range + button * (1 + (max - 1) * f * amount) / 2
        const a = Math.max(lo, pointer - half)
        const b = Math.min(hi, pointer + half)
        if (b - a < 1) continue
        const grow = peak * f
        const r = Math.min((b - a) / 2, Math.max(2, grow))
        if (edge === "left")       out.push({ x: 0,     y: a, w: button + grow, h: b - a, r: r })
        else if (edge === "right") out.push({ x: -grow, y: a, w: button + grow, h: b - a, r: r })
        else                       out.push({ x: a,     y: -grow, w: b - a, h: button + grow, r: r })
    }
    return out
}

// ── The side rail ─────────────────────────────────────────────────────────────
// Where everything on the sidebar goes along its edge. The layout
// (Config.sidebarLayout) is three regions of groups of module ids, and each region
// keeps the place the clips, the dock and the stats first had, so any module can
// take any of them:
//
//   start   packed from `near`, in order: flush in the near corner — under the bar
//           on a side, against the left strip along the bottom. `collapsed` (a
//           panel over that corner; SideRail decides) takes it out of the centre's
//           way: its groups keep their places, and their hosts sink into the frame.
//   centre  one block, centred along the span and stepped past `avoid` (where a
//           panel hanging down from the bar ends along it, 0 = none in the way).
//           Kept `gap` clear of the start block and of the end block, or `margin`
//           off the span's ends without one. Too long to stay centred, it slides
//           back from the end block — and never into the start one: when it can't
//           clear both, the start wins.
//   end     packed back from `corner`, in order: flush in the far corner — below a
//           side dock, right of a bottom one.
//
// Groups stand `gap` apart. Inside one, members are `inner` apart with `pad` at
// each end. A module 0 long (off, empty, still loading) takes no room and no gap,
// and neither does a group of nothing but those.
//
// `room` is how long each module could grow AT REST — the dock's ceiling in its
// "grow" mode: the span less everything else on the rail. Resting, so neither
// `avoid` nor `collapsed` moves it: a panel passing over the edge must not reflow
// the dock underneath it.
//
//   o = { start, end, margin, gap, near, corner, avoid, collapsed, pad, inner,
//         layout: { start: [[id, …], …], centre: …, end: … }, lengths: { id: px } }
//
// Returns { at: { id: pos }, room: { id: px },
//           groups: [{ region, index, ids, pos, len }] }   (only groups with a length)
function sideRail(o) {
    const REGIONS = ["start", "centre", "end"]
    const gap = o.gap, pad = o.pad || 0, inner = o.inner || 0
    const lenOf = id => Math.max(0, (o.lengths && o.lengths[id]) || 0)

    // A group's members laid out from its own start; `skip` leaves one out (room).
    function lay(ids, skip) {
        const rel = {}
        let p = pad, n = 0
        for (const id of ids) {
            const l = id === skip ? 0 : lenOf(id)
            if (!(l > 0)) continue
            if (n > 0) p += inner
            rel[id] = p
            p += l
            n++
        }
        return { rel: rel, len: n > 0 ? p + pad : 0 }
    }

    // `o.joined[region][i]`: group i is the next piece of the same LAYOUT group as i - 1
    // (sideGroups splits a group round the dock; sideJoins says which pieces were one).
    // Joined pieces butt together with no gap — every length carries its own pad — so
    // the dock and the modules grouped with it read as one group (one island,
    // SideRegionPills), as on the bar. A piece whose neighbour is absent (no length)
    // takes the gap as usual.
    const joinedAt = (r, i) => !!(o.joined && o.joined[r] && o.joined[r][i])
    const groups = {}
    for (const r of REGIONS)
        groups[r] = ((o.layout && o.layout[r]) || []).map((ids, index) =>
            Object.assign({ region: r, index: index, ids: ids }, lay(ids)))
    const present = list => list.filter(g => g.len > 0)
    const between = (a, b) => b.region === a.region && b.index === a.index + 1 && joinedAt(b.region, b.index) ? 0 : gap
    const block = list => {
        const p = present(list)
        let s = 0
        for (let i = 0; i < p.length; i++) s += p[i].len + (i > 0 ? between(p[i - 1], p[i]) : 0)
        return s
    }

    // start: from the near corner, in order
    let p = Math.round(o.near)
    {
        const list = present(groups.start)
        for (let i = 0; i < list.length; i++) {
            if (i > 0) p += between(list[i - 1], list[i])
            list[i].pos = p
            p += list[i].len
        }
    }

    // end: back from the far corner, in order
    p = o.corner
    {
        const list = present(groups.end)
        for (let i = list.length - 1; i >= 0; i--) {
            p -= list[i].len
            list[i].pos = Math.round(p)
            if (i > 0) p -= between(list[i - 1], list[i])
        }
    }

    // centre: one block between the two
    const starts = present(groups.start), ends = present(groups.end)
    const lastStart = starts[starts.length - 1]
    const floor = lastStart && !o.collapsed
        ? Math.max(o.start + o.margin, lastStart.pos + lastStart.len + gap)
        : o.start + o.margin
    const centreLen = block(groups.centre)
    const limit = (ends.length > 0 ? ends[0].pos - gap : o.end - o.margin) - centreLen
    let c = Math.round(o.start + (o.end - o.start - centreLen) / 2)
    if (o.avoid > 0) c = Math.max(c, Math.round(o.avoid))
    c = Math.max(floor, Math.min(c, limit))
    {
        const list = present(groups.centre)
        for (let i = 0; i < list.length; i++) {
            if (i > 0) c += between(list[i - 1], list[i])
            list[i].pos = c
            c += list[i].len
        }
    }

    const at = {}
    const out = []
    for (const r of REGIONS) {
        const list = present(groups[r])
        list.forEach((g, i) => {
            for (const id in g.rel) at[id] = g.pos + g.rel[id]
            const e = { region: r, index: g.index, ids: g.ids, pos: g.pos, len: g.len }
            // Present only when it is: a piece continuing the group before it.
            if (i > 0 && gap > 0 && between(list[i - 1], g) === 0) e.joined = true
            out.push(e)
        })
    }

    // ── Room at rest ──────────────────────────────────────────────────────────
    // A module's room is what its group may take, less the rest of its own group.
    // What the group may take depends on its region: the centre has what's between
    // the two corner blocks; a corner block has everything short of the other
    // corner's block and the centre's.
    const startLen = block(groups.start), endLen = block(groups.end)
    const lo = startLen > 0 ? Math.max(o.start + o.margin, o.near + startLen + gap) : o.start + o.margin
    const hi = endLen > 0 ? o.corner - endLen - gap : o.end - o.margin
    const without = (list, g) => block(list.filter(x => x !== g))
    const room = {}
    for (const r of REGIONS)
        for (const g of groups[r])
            for (const id of g.ids) {
                const rest = lay(g.ids, id).len
                const own = rest > 0 ? rest + inner : pad * 2
                const others = without(groups[r], g)
                const beside = others > 0 ? others + gap : 0
                const mid = centreLen > 0 ? centreLen + gap : 0
                const span = r === "centre" ? hi - lo - beside
                           : r === "start"  ? hi - o.near - beside - mid
                           :                  o.corner - lo - beside - mid
                room[id] = Math.max(0, span - own)
            }

    return { at: at, room: room, groups: out }
}

// ── sideGroups ────────────────────────────────────────────────────────────────
// The layout as the rail lays it out. A big module — one with a host of its own:
// the dock, with its previews and menus — always stands alone, so a group holding
// one is split round it, in order. Small modules (the stats and clips buttons
// among them) keep the groups they were given (they share a pill, SideGroupHost).
// config.json is hand-editable, and the drag that could build such a group only
// has to be refused, not trusted.
//
//   layout { start: [[id, …], …], centre: …, end: … }, isBig(id)  →  the same shape
function sideGroups(layout, isBig) {
    const out = {}
    for (const r of ["start", "centre", "end"]) {
        out[r] = []
        for (const g of (layout && layout[r]) || []) {
            let run = []
            for (const id of g) {
                if (isBig(id)) {
                    if (run.length > 0) { out[r].push(run); run = [] }
                    out[r].push([id])
                } else run.push(id)
            }
            if (run.length > 0) out[r].push(run)
        }
    }
    return out
}

// ── sideJoins ─────────────────────────────────────────────────────────────────
// Which of sideGroups' pieces continue the layout group before them, aligned with its
// output: { start: [false, true, …], … }. A group of [clips, dock, stats] splits into
// three pieces that were ONE group — the rail lays them gapless (sideRail `joined`) and
// SideRegionPills draws one island round them, so the dock groups like any module.
function sideJoins(layout, isBig) {
    const out = {}
    for (const r of ["start", "centre", "end"]) {
        out[r] = []
        for (const g of (layout && layout[r]) || []) {
            let first = true, run = false
            for (const id of g) {
                if (isBig(id)) {
                    if (run) { out[r].push(!first); first = false; run = false }
                    out[r].push(!first)
                    first = false
                } else run = true
            }
            if (run) out[r].push(!first)
        }
    }
    return out
}

// ── sideSurface ───────────────────────────────────────────────────────────────
// Where the sidebar's surface lies ACROSS its edge, measured in from the screen
// edge, and how much of the edge the sidebar takes. `depth` is what its content
// needs (Config.sidebarDepth); where it starts is the top bar's shape (SidePill):
//   welded    from the edge itself: the frame's strip is the same material, and
//             what stands on it centres across strip and all
//   flush     from the strip's inner edge, where nothing welds it (no plugin);
//             with no frame, from the screen edge
//   floating  on the strip, or `inset` off a bare edge, and `inset` short of what
//             it takes — the floating top bar's pills, turned on end
// SideRail draws from `lo`..`hi`; DockReserve reserves `reserve` (less the frame's
// own strip, which the frame reserves). One function, so the two can't disagree.
//
//   o = { depth, strip, anchored, welded, inset }   →   { lo, hi, reserve }
function sideSurface(o) {
    const lo = o.welded ? 0 : o.anchored ? o.strip : Math.max(o.strip, o.inset)
    const hi = lo + o.depth
    return { lo: lo, hi: hi, reserve: hi + (o.anchored ? 0 : o.inset) }
}

// ── railAvoid ─────────────────────────────────────────────────────────────────
// How far down the span the side rail must start to clear every panel card that
// crosses its band (`lo`..`hi` across the edge, in the same coordinates as the
// cards). A closed card is 0 tall and never counts. Only a side rail runs along
// the bar's panels; a bottom dock is never in their way, so it gets 0.
//
//     cards  [{ x, y, w, h }]       clearance  space kept below the lowest one
function railAvoid(edge, lo, hi, cards, clearance) {
    if (edge !== "left" && edge !== "right") return 0
    let out = 0
    for (const c of cards) {
        if (!(c.h > 0.5) || c.x >= hi || c.x + c.w <= lo) continue
        out = Math.max(out, c.y + c.h + clearance)
    }
    return out
}

// ── thumbAspect ───────────────────────────────────────────────────────────────
// A window's width/height as a thumbnail's aspect: clamped, so a very tall or very
// wide window still gets a tile you can read (and a title that fits). 16:9 when
// the size isn't known yet.
function thumbAspect(w, h) {
    if (!(w > 0) || !(h > 0)) return 16 / 9
    return Math.max(0.6, Math.min(2.4, w / h))
}
