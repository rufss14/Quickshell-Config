.pragma library

// ── contagion.js ──────────────────────────────────────────────────────────────
// The apps' share of a colour change (services/WallWave.qml), for
// services/Contagion.qml: which windows there are, where the front meets each, and
// when to tell each app.
//
// ── Why apps sit under a curtain ──────────────────────────────────────────────
// The first cut flipped each app as the front first touched its window. It read as
// LATE — a border fades for 640ms, a browser or Spotify takes hundreds of ms to
// repaint — and, worse, a window near full-screen flipped entirely the moment the
// front touched its bottom edge, so the wave could not be seen crossing an app at
// all. Now every looked-at window is frozen under a copy of itself (the curtain,
// modules/desktop/WaveCurtain), every app is told AT ONCE, underneath, and the same
// front that eats the shell's old look eats the curtain: each app is revealed
// already recoloured, pixel by pixel. Timing only matters where the curtain can't
// cover (then: timed flips, as before).
//
//     bun scripts/test-contagion.js
//
// ── The front ─────────────────────────────────────────────────────────────────
// shaders/wavefront.glsl: R = progress × (maxR + 0.14), in screen heights from the
// monitor's bottom middle, where maxR reaches a top corner. The rim's wobble and
// tendrils are left out — they swing a few hundredths either way. `progress` runs
// on Motion.travel, OutCubic: p = 1 − (1 − t)³. So a point `d` away is reached at
//     t = 1 − (1 − d / (maxR + 0.14))^⅓        (× the spread's duration)
// Change the curve or R and change this with it.

function reachMax(aspect) {
    return Math.sqrt(Math.pow(0.5 * aspect, 2) + 1) + 0.14
}

// Milliseconds after the spread starts at which the front is `dist` screen heights
// from the origin.
function timeFor(dist, aspect, spreadMs) {
    const p = Math.min(1, Math.max(0, dist / reachMax(aspect)))
    return spreadMs * (1 - Math.cbrt(1 - p))
}

// A Hyprland monitor in LOGICAL pixels — the space windows' `at`/`size` are in.
// Hyprland reports the mode's physical size plus a scale, and the odd transforms
// are the quarter turns, which swap the axes.
function logical(m) {
    const s = m.scale > 0 ? m.scale : 1
    const rot = (m.transform % 2) === 1
    return {
        x: m.x, y: m.y,
        w: (rot ? m.height : m.width) / s,
        h: (rot ? m.width : m.height) / s
    }
}

// How far a window's NEAREST point is from its monitor's bottom middle, in screen
// heights — the moment the front first touches it.
function distance(win, mon) {
    const L = logical(mon)
    const x = win.x - L.x, y = win.y - L.y
    const ox = L.w / 2, oy = L.h
    const nx = Math.max(x, Math.min(ox, x + win.w))
    const ny = Math.max(y, Math.min(oy, y + win.h))
    return Math.hypot(nx - ox, ny - oy) / Math.max(1, L.h)
}

// ── What each app needs ───────────────────────────────────────────────────────
//   kitty    SIGUSR1 to the window's own process: kitty re-reads its theme, which
//            the commit already wrote (scripts/wave-lib.sh). Per PROCESS — kitty
//            runs one per window unless single-instance, and then one signal
//            reloads them all.
//   discord  Vencord's theme script (reload-theme.sh --app discord).
//            Matched on the Discord service's configurable class prefixes, never a
//            literal (Vesktop, WebCord, Legcord… set different classes).
//   browser  Pywalfox (reload-theme.sh --app browser).
//   spotify  Spicetify's recolour (reload-theme.sh --app spotify).
//   steam    steam-live.py's push through Steam's debug port (reload-theme.sh --app steam);
//            reachable only once the user opted in — `--probe` says so, like the rest.
// Per APP, those four: one run recolours every window of it. Everything else only
// has its border; GTK/Qt apps take the palette with the fan-out after the wave.
const BROWSERS = ["zen", "firefox", "librewolf"]

function kind(cls, discordClasses) {
    const c = String(cls || "").toLowerCase()
    if (c === "kitty") return "kitty"
    if ((discordClasses || []).some(p => p && c.startsWith(String(p).toLowerCase()))) return "discord"
    if (BROWSERS.some(p => c.startsWith(p))) return "browser"
    if (c === "spotify") return "spotify"
    if (c === "steam") return "steam"
    return ""
}

// ── How long each takes to SHOW its new colours once asked (ms) ───────────────
// The border is instant while the wave holds Hyprland's border fade off (a lead of
// the fade's length when it can't), kitty re-reads a file it was just handed. Both
// are small and steady, so the spread is simply held that long (`delay`).
//
// The SCRIPTED apps are neither: Discord, a browser and Spotify each recolour through
// `reload-theme.sh --app …`, and how long that takes depends on the machine and the
// app. Guessed leads were wrong in both directions (Discord's 300 missed Vencord's own
// 300ms debounce; Spotify's pipeline outran any fixed wait). So under the curtain the
// wave WAITS for them — Contagion holds the spread from the moment it starts each
// script until the script has exited plus AFTER[app], the part that happens in the
// app once the script is done:
//   discord  Vencord re-reads its themes 300ms after the file stops changing (its
//            watcher's debounce, measured in its build), then restyles
//   browser  Pywalfox's add-on applying the theme
//   steam    nothing to guess either, and nothing after: the push's script returns only once
//            every window has painted two frames (capped), so its exit IS the repaint —
//            AFTER is one frame of margin
//   spotify  nothing to guess: the shell's Spicetify extension SAYS when the new
//            sheets are loaded and painted (SpotifyBridge.restyled), and Contagion
//            holds until then — never after its script, never on a timer
// LEADS keeps their whole-trip estimates for the fallback: a window no curtain
// covers is told this long before the front reaches it.
const LEADS = { border: 40, kitty: 120, discord: 550, browser: 500, spotify: 1200, steam: 350 }
const SCRIPTED = { discord: true, browser: true, spotify: true, steam: true }
const AFTER = { discord: 450, browser: 350, steam: 20 }

// ── The plan, made at the freeze ──────────────────────────────────────────────
// clients:  `hyprctl clients -j` — asked for fresh at the freeze, because a window
//           in the wrong place would leave a frozen copy of it standing somewhere
//           it isn't
// monitors: [{ id, name, x, y, width, height, scale, transform, activeWorkspace,
//              specialWorkspace }]
// Returns
//   covers   { monitorName: [{ x, y, w, h }] } — every window someone is looking
//            at, monitor-local, grown by `margin` for its border: what the
//            curtain (modules/desktop/WaveCurtain) freezes and the front reveals
//   entries  [{ address, pid, app, at, looked, monitor }] — `at`: ms after the
//            spread starts that the front first touches it
// A looked-at FULLSCREEN window is neither: it sits above the curtain's layer, and
// a game gets left alone (the fan-out reaches its app after the wave).
function plan(clients, monitors, spreadMs, discordClasses, margin) {
    const byId = {}
    for (const m of monitors || []) byId[m.id] = m
    const covers = {}, entries = []
    const pad = Math.max(0, margin || 0)
    for (const c of clients || []) {
        // The address goes into Lua the compositor runs (set_prop): only ever a hex
        // address, whatever the IPC object held.
        if (!c || !/^0x[0-9a-fA-F]+$/.test(String(c.address)) || c.mapped === false) continue
        const at0 = c.at || [0, 0], size = c.size || [0, 0]
        const win = { x: +at0[0] || 0, y: +at0[1] || 0, w: +size[0] || 0, h: +size[1] || 0 }
        const m = byId[c.monitor]
        const ws = c.workspace ? c.workspace.id : undefined
        const looked = !!m && c.hidden !== true
            && (ws === m.activeWorkspace || (!!m.specialWorkspace && ws === m.specialWorkspace))
        // Hyprland's fullscreen modes: 0 none, 1 maximised, 2 fullscreen, 3 both.
        // A MAXIMISED window is an ordinary window under the curtain.
        if (looked && (Number(c.fullscreen) || 0) >= 2) continue
        let at = spreadMs
        if (looked) {
            const L = logical(m)
            at = timeFor(distance(win, m), L.w / Math.max(1, L.h), spreadMs)
            const x = Math.max(0, win.x - L.x - pad), y = Math.max(0, win.y - L.y - pad)
            const r = Math.min(L.w, win.x - L.x + win.w + pad), b = Math.min(L.h, win.y - L.y + win.h + pad)
            if (r > x && b > y)
                (covers[m.name] = covers[m.name] || []).push({ x: x, y: y, w: r - x, h: b - y })
        }
        entries.push({ address: c.address, pid: (c.pid | 0), app: kind(c.class, discordClasses),
                       at: Math.round(at), looked: looked, monitor: m ? m.name : "" })
    }
    return { covers: covers, entries: entries }
}

// ── What to do, and when, once the palette is live ────────────────────────────
// `covered`: { monitorName: true } for each screen whose curtain is up.
// Times are ms after NOW (the palette just read); the spread starts `delay` from
// now at the earliest, so the front reaches a window at delay + at.
//   · under the curtain, or not looked at → now. Hidden until the front passes, so
//     done early is done right.
//   · looked at but uncovered (a curtain that failed) → timed to land as the front
//     touches it: delay + at − lead (LEADS: the estimates).
// `delay` covers the border and kitty: how long the spread waits so they are done by
// the time the front reaches them — never less than `minMs` (the palette's own
// settle), never more than minMs + `capMs`. SCRIPTED apps under the curtain don't
// count towards it: their flip carries `hold` and `atMin` (the soonest the front
// reaches one of their covered windows) and Contagion holds the spread on the real
// thing — go no sooner than (script exit + AFTER[app] − atMin).
// Apps act once: kitty per process, the others per app, at their earliest moment.
// `able`: { app: true } for the scripted apps this machine can reach
// (`reload-theme.sh --probe`); any other is only a border — told nothing, and never
// allowed to hold the wave for a recolour that can't happen (Zen with no Pywalfox).
// Omitted: all of them.
function decide(p, covered, leads, minMs, capMs, able) {
    const L = Object.assign({}, LEADS, leads || {})
    // A border whose fade couldn't be held off takes as long as the fade.
    L.border = Math.max(LEADS.border, (leads && leads.border) || 0)
    const reach = a => !SCRIPTED[a] || !able || able[a] === true
    const entries = ((p && p.entries) || []).map(e =>
        reach(e.app) ? e : Object.assign({}, e, { app: "" }))
    const underCurtain = e => e.looked && !!covered[e.monitor]
    let need = minMs
    for (const e of entries) {
        if (!e.looked) continue
        need = Math.max(need, L.border - e.at)
        if (e.app && !(SCRIPTED[e.app] && underCurtain(e))) need = Math.max(need, (L[e.app] || 0) - e.at)
    }
    const delay = Math.round(Math.min(minMs + capMs, need))
    const when = (e, lead) => (!e.looked || covered[e.monitor]) ? 0 : Math.max(0, delay + e.at - lead)

    const flips = [], apps = {}
    for (const e of entries) {
        flips.push({ t: when(e, L.border), address: e.address, border: true, app: "", pid: 0,
                     hold: false, atMin: 0 })
        if (!e.app || (e.app === "kitty" && e.pid <= 0)) continue
        const key = e.app === "kitty" ? "kitty:" + e.pid : e.app
        const t = when(e, L[e.app] || 0)
        const a = apps[key] || (apps[key] = { t: t, address: "", border: false, app: e.app, pid: e.pid,
                                              hold: false, atMin: Infinity })
        a.t = Math.min(a.t, t)
        if (SCRIPTED[e.app] && underCurtain(e)) {
            a.hold = true
            a.atMin = Math.min(a.atMin, e.at)
        }
    }
    for (const k in apps) {
        const a = apps[k]
        if (!a.hold) a.atMin = 0
        flips.push(a)
    }
    flips.sort((a, b) => a.t - b.t)
    return { delay: delay, flips: flips }
}

// When a held app lets the spread go, in ms after its script EXITED: once what
// happens in the app after the script (AFTER) has had time, less the head start the
// front gives it (it reaches the app's nearest covered window atMin after going).
function releaseAfter(app, atMin) {
    return Math.max(0, (AFTER[app] || 0) - (atMin || 0))
}

// ── Hyprland's border fade, held off for the wave ─────────────────────────────
// A border colour change is a Hyprland animation (the `border` leaf — here 640ms,
// linear), so a border flipped as the front arrived kept fading long after it had
// passed. The wave switches the leaf off and puts back exactly what was there.
// `anim` is that leaf from `hyprctl animations -j`. borderAnim() keeps what's needed
// to put it back, or null when it can't be put back exactly (a leaf that only
// inherits reports no curve of its own; a curve name that isn't a plain word never
// reaches Lua) — then the fade is left alone, and borders get its length as lead.
function borderAnim(anim) {
    if (!anim || anim.name !== "border" || anim.overridden !== true) return null
    const speed = Number(anim.speed)
    const curve = String(anim.bezier || "")
    const style = String(anim.style || "")
    if (!(speed > 0) || !/^[A-Za-z0-9_.-]+$/.test(curve) || !/^[A-Za-z0-9 %._-]*$/.test(style)) return null
    return { enabled: anim.enabled === true, speed: speed, curve: curve, style: style }
}
function borderAnimLua(a, enabled) {
    if (!a) return ""
    return 'hl.animation({ leaf = "border", enabled = ' + (enabled ? "true" : "false")
         + ", speed = " + a.speed + ', bezier = "' + a.curve + '"'
         + (a.style !== "" ? ', style = "' + a.style + '"' : "") + " })"
}
// How long a border takes to settle while the fade is on: speed is in 100ms units.
function borderFadeMs(a) { return a && a.enabled ? Math.round(a.speed * 100) : 0 }

// Hyprland's border colour for a palette slot: "#rrggbb" → "rgba(rrggbbff)", or ""
// for anything that isn't a plain colour (a hand-edited palette must not become a
// Lua string Hyprland is asked to parse).
function borderValue(hex) {
    const s = String(hex || "")
    return /^#[0-9a-fA-F]{6}$/.test(s) ? "rgba(" + s.slice(1).toLowerCase() + "ff)" : ""
}
