pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "../config"
import "contagion.js" as Logic

// ── Contagion ─────────────────────────────────────────────────────────────────
// Every app rides the wave (services/WallWave.qml) — ported from the user's other
// shell, where it was asked for as "if I have anything like the terminal open I want
// it to also change with the colour like the frame, so it's not just the shell".
//
// ── Apps change UNDER A CURTAIN, and the front reveals them ────────────────────
// The first port flipped each app as the front touched its window. On a real
// desktop that read as late and as wrong: a border change is Hyprland's 640ms fade,
// a browser or Spotify takes hundreds of ms to repaint, and a near-full-screen
// window flipped whole the instant the front touched its bottom edge — the wave
// never visibly crossed an app. So now:
//   1. FREEZE   the windows' places are asked for fresh (`hyprctl clients -j`;
//               Quickshell only refreshes toplevels when told, and doesn't say when
//               it's done), and each screen's curtain (modules/desktop/WaveCurtain)
//               covers every looked-at window with a copy of the screen as it is.
//               Hyprland's border fade is switched off for the wave.
//   1b. CURTAIN UP  an app whose windows are all covered (or off-screen) is shown its
//               STAGED recolour at once (`reload-theme.sh --app … --staged`): the run
//               prepared it before the freeze (scripts/apps-lib.sh), so all that's
//               left is a rename (Discord) or a POST (Spotify), and the app's own
//               work — Vencord's 300ms debounce, Spotify's sheet fetch — overlaps
//               the commit and the colours' settle instead of following them.
//               Nothing staged (exit 3) → step 2, as before.
//   2. PALETTE  (WallWave.paletteRead) every app is told at once, underneath:
//               borders (per window, from the slots blend.lua names for them),
//               kitty (SIGUSR1 per process — the commit wrote its theme),
//               Discord / browsers / Spotify (reload-theme.sh --app …). The spread
//               waits until they are DONE by the time it reaches them: a fixed
//               lead for borders and kitty (WallWave.delayGo), and for the scripted
//               three a hold on the real thing — from starting the script until
//               it has exited plus what the app does after (contagion.js AFTER:
//               Vencord's 300ms debounce, Spotify's stylesheet re-fetch), less the
//               front's head start (WallWave.holdGo/releaseGo). Guessed leads were
//               wrong both ways; each app's time is logged ("Contagion: spotify
//               recoloured in N ms") so AFTER can be tuned.
//   3. SPREAD   the same front that eats the shell's old look eats the curtain:
//               each app is revealed already recoloured, pixel by pixel.
//   4. SETTLED  the border fade goes back exactly as it was.
// A screen whose curtain couldn't cover (no capture) falls back to timed flips —
// each window as the front touches it, less its app's lead (services/contagion.js).
// Windows nobody is looking at change at once. The fan-out after the wave still
// runs for every app; the ones done here are skipped (reload-theme.sh stamps them).
//
// ── Known trade-off: the border is a per-window property ──────────────────────
// Hyprland's set_prop outranks window rules and lasts for the window's life, so a
// window whose border colour comes from a rule of its own takes the palette's
// border while it stays open. This config sets none.
Singleton {
    id: c

    // ── For the curtains ──────────────────────────────────────────────────────
    // { monitorName: [{ x, y, w, h }] } — the windows each screen's curtain freezes,
    // monitor-local, borders included. {} between waves.
    property var covers: ({})
    // { monitorName: true } for each curtain whose copy is up. WaveCurtain reports.
    property var _covered: ({})
    function setCovered(name, yes) {
        const m = Object.assign({}, c._covered)
        if (yes) m[name] = true
        else delete m[name]
        c._covered = m
        if (c._waitTok >= 0 && c._curtainsUp()) c._stopWaiting("up")
        c._tryEarly()
    }


    property var _plan: null
    property var _flips: []          // [{ t, address, border, app, pid, hold, atMin }], soonest first
    property double _t0: 0
    property int _token: -1          // the change this is acting for
    property string _active: ""     // Hyprland colours, from the palette just read
    property string _inactive: ""

    Connections {
        target: WallWave
        function onFroze(token) { c._freeze(token) }
        function onPaletteRead(token) { c._act(token) }
        function onSettledChanged() { if (WallWave.settled) c._end() }
    }

    // ── 1. The freeze ─────────────────────────────────────────────────────────
    function _freeze(token) {
        c._freezeTok = token
        c._early = ({})
        c._decidedTok = -1
        c._waitTok = -1
        curtainWait.stop()
        c._plan = null
        c._flips = []
        tick.stop()
        c.covers = ({})
        clientsProc.running = false
        clientsProc.running = true
        c._probeApps()
        c._muteBorders()
    }

    // Which scripted apps this machine can reach at all (`reload-theme.sh --probe`
    // — the one place that knows how each is reached). Asked again at every freeze,
    // since an app can be set up mid-session; the answer is in long before the
    // palette lands. Only a reachable app may hold the wave.
    property var _able: ({})
    property bool _probed: false       // never answered: assume every app, as before
    function _probeApps() {
        probeProc.running = false
        probeProc.running = true
    }
    Process {
        id: probeProc
        command: ["bash", Quickshell.shellPath("scripts/reload-theme.sh"), "--probe"]
        stdout: SplitParser {
            onRead: function(line) {
                if (line.indexOf("APPS=") !== 0) return
                const able = {}
                for (const a of line.substring(5).trim().split(/\s+/))
                    if (a === "discord" || a === "browser" || a === "spotify") able[a] = true
                c._able = able
                c._probed = true
            }
        }
    }

    Process {
        id: clientsProc
        command: ["hyprctl", "clients", "-j"]
        stdout: StdioCollector { onStreamFinished: c._planFrom(text) }
    }

    function _planFrom(json) {
        // The moment has passed (the change went already, or was abandoned): a late
        // plan would freeze windows under a curtain nothing is going to eat.
        if (!WallWave.frozen) return
        let list
        try { list = JSON.parse(json) } catch (e) {
            console.warn("Contagion: unreadable window list —", e)
            return
        }
        const mons = Hyprland.monitors.values.map(m => {
            const ipc = m.lastIpcObject || {}
            return {
                id: m.id, name: m.name, x: m.x, y: m.y, width: m.width, height: m.height,
                scale: m.scale, transform: ipc.transform || 0,
                activeWorkspace: m.activeWorkspace ? m.activeWorkspace.id : -1,
                specialWorkspace: (ipc.specialWorkspace && ipc.specialWorkspace.id) || 0
            }
        })
        // Grown by the border and a pixel of its anti-aliasing, so the border's
        // change is under the curtain too.
        c._plan = Logic.plan(list, mons, WallWave.spreadMs, Discord.windowClasses,
                             (Blend.v.border_size || 0) + 1)
        c.covers = c._plan.covers
        c._tryEarly()
    }

    // ── 1b. The curtain is up: show what the run staged ───────────────────────
    // { app: "running" | "done" | "none" } for this freeze. Only the apps with a
    // staging (apps-lib.sh); the browser has none and waits for the palette.
    property int _freezeTok: -1
    property int _decidedTok: -1
    property var _early: ({})
    function _tryEarly() {
        if (!c._plan || c._freezeTok < 0 || !WallWave.frozen || c._freezeTok !== WallWave.infectSeq) return
        for (const app of ["discord", "spotify"]) {
            if (c._early[app]) continue
            if (c._probed && !c._able[app]) continue
            const mine = c._plan.entries.filter(e => e.app === app)
            if (mine.length === 0) continue
            // Every window hidden under an up curtain or not on screen at all.
            if (!mine.every(e => !e.looked || c._covered[e.monitor])) continue
            const seen = mine.filter(e => e.looked)
            const e = Object.assign({}, c._early); e[app] = "running"; c._early = e
            c._runJob(app, { hold: seen.length > 0, staged: true, token: c._freezeTok,
                             atMin: seen.length > 0 ? Math.min(...seen.map(x => x.at)) : 0 })
        }
    }

    // ── 2. The palette is live ────────────────────────────────────────────────
    // A fast change (a cached palette, colours only) reads its palette before the
    // curtain's copy of the screen exists, and an app with no curtain over it can only
    // be guessed at — Discord flipped late on exactly those. So the decision waits for
    // every curtain the plan asked for, holding the spread meanwhile; a curtain that
    // never comes (no screencopy) costs curtainWait, then the guess as before.
    property int _waitTok: -1
    property double _waitFrom: 0
    function _act(token) {
        // No plan in time (hyprctl slow or failing): the fan-out after the wave
        // reaches the apps, as it did before this existed.
        if (!c._plan) return
        if (c._curtainsUp()) { c._decide(token); return }
        c._waitTok = token
        c._waitFrom = Date.now()
        WallWave.holdGo(token)
        curtainWait.restart()
    }
    function _curtainsUp() {
        for (const name in (c._plan ? c._plan.covers : {}))
            if (!c._covered[name]) return false
        return true
    }
    function _stopWaiting(why) {
        const t = c._waitTok
        c._waitTok = -1
        curtainWait.stop()
        console.info("Contagion: curtain", why, "after", Date.now() - c._waitFrom, "ms")
        c._decide(t)
        // After _decide, whose own holds are already taken: the count never touches 0.
        WallWave.releaseGo(t)
    }
    Timer { id: curtainWait; interval: 400; onTriggered: c._stopWaiting("not up") }

    function _decide(token) {
        if (!c._plan) return
        // The palette ON DISK — what every app is about to be given — never the
        // album overlay the shell may be wearing on top of it.
        const pal = (Colors.fileData && Colors.fileData.colors) || {}
        c._active   = Logic.borderValue(pal["color" + Blend.v.border_active_wal])
        c._inactive = Logic.borderValue(pal["color" + Blend.v.border_inactive_wal])

        const leads = c._borderMuted ? ({}) : ({ border: Logic.borderFadeMs(c._borderAnim) })
        const d = Logic.decide(c._plan, c._covered, leads, WallWave.settleMs, WallWave.appWaitMs,
                               c._probed ? c._able : undefined)
        WallWave.delayGo(token, d.delay)
        c._token = token
        c._decidedTok = token
        // Apps already shown (or being shown) from their staging aren't told again.
        d.flips = d.flips.filter(f => !(f.app && (c._early[f.app] === "running" || c._early[f.app] === "done")))
        // Flip times count from `delay` before the go. Decided at paletteRead, that's
        // now; decided after waiting for a curtain, the go is still due `delay` after
        // the READ (WallWave re-arms its settle), or now if the wait outran it.
        const now = Date.now()
        c._t0 = WallWave.readAt > 0
            ? Math.max(WallWave.readAt + Math.max(WallWave.settleMs, d.delay), now) - d.delay
            : now
        c._flips = d.flips
        c._next()
    }

    // One timer, re-armed for the next moment — not a fast repeating tick. Under a
    // curtain everything is due at once; only uncovered screens leave timed flips.
    function _next() {
        const now = Date.now() - c._t0
        const due = c._flips
        while (due.length > 0 && due[0].t <= now) c._flip(due.shift())
        c._flips = due
        if (due.length > 0) {
            tick.interval = Math.max(1, due[0].t - now)
            tick.restart()
        }
    }
    Timer { id: tick; onTriggered: c._next() }

    function _flip(f) {
        if (f.border) {
            const sel = "address:" + f.address
            if (c._active !== "")
                Hyprland.dispatch(`hl.dsp.window.set_prop({ prop = "active_border_color", value = "${c._active}", window = "${sel}" })`)
            if (c._inactive !== "")
                Hyprland.dispatch(`hl.dsp.window.set_prop({ prop = "inactive_border_color", value = "${c._inactive}", window = "${sel}" })`)
        }
        if (f.app === "kitty")
            Quickshell.execDetached(["kill", "-USR1", String(f.pid)])
        else if (f.app === "discord" || f.app === "browser" || f.app === "spotify")
            c._runApp(f)
    }

    // ── The scripted apps, watched to the end ─────────────────────────────────
    // One Process each, so the shell knows when the script is done — the start of
    // the part that happens in the app (AFTER). Never restarted mid-run: killing
    // reload-theme.sh while Vencord's theme is half-written would leave Discord a
    // broken stylesheet. A request that arrives mid-run runs again after it.
    function _procFor(app) {
        return app === "discord" ? discordProc : app === "spotify" ? spotifyProc : browserProc
    }
    function _runApp(f) {
        c._runJob(f.app, { hold: f.hold, atMin: f.atMin, token: c._token, staged: false })
    }
    function _runJob(app, job) {
        const p = c._procFor(app)
        if (job.hold) WallWave.holdGo(job.token)
        if (p.running) { p.queued = job; return }
        c._start(p, job)
    }
    function _start(p, job) {
        p.job = job
        p.started = Date.now()
        p.command = ["bash", Quickshell.shellPath("scripts/reload-theme.sh"), "--app", p.app]
                    .concat(job.staged ? ["--staged"] : [])
        p.running = true
    }
    function _appDone(p, code) {
        const job = p.job
        p.job = null
        if (job && job.staged) {
            const e = Object.assign({}, c._early)
            e[p.app] = code === 0 ? "done" : "none"
            c._early = e
        }
        if (job && job.staged && code !== 0) {
            // Nothing staged: recolour from the palette instead — now, if the palette
            // was already read and the decision made without it, else at that decision.
            console.info("Contagion:", p.app, "had nothing staged (" + code + ") — recolouring from the palette")
            if (job.hold) WallWave.releaseGo(job.token)
            if (c._decidedTok === job.token && c._decidedTok === c._token)
                c._runApp({ app: p.app, hold: job.hold, atMin: job.atMin })
        } else if (job && p.app === "spotify") c._spotifyExited(p, job)
        else if (job) {
            const more = Logic.releaseAfter(p.app, job.atMin)
            console.info("Contagion:", p.app, (job.staged ? "shown from its staging in" : "recoloured in"),
                         Date.now() - p.started, "ms"
                         + (job.hold ? "; the wave waits " + more + " ms more for it" : ""))
            if (job.hold) c._releaseIn(job.token, more)
        }
        if (p.queued) {
            const next = p.queued
            p.queued = null
            c._start(p, next)
        }
    }

    Process {
        id: discordProc
        readonly property string app: "discord"
        property var job: null
        property var queued: null
        property double started: 0
        onExited: function(exitCode) { c._appDone(discordProc, exitCode) }
    }
    Process {
        id: spotifyProc
        readonly property string app: "spotify"
        property var job: null
        property var queued: null
        property double started: 0
        onExited: function(exitCode) { c._appDone(spotifyProc, exitCode) }
    }
    Process {
        id: browserProc
        readonly property string app: "browser"
        property var job: null
        property var queued: null
        property double started: 0
        onExited: function(exitCode) { c._appDone(browserProc, exitCode) }
    }

    // ── Spotify says when it's done ─────────────────────────────────────────────
    // Its script ends by asking the bridge for a repaint; the shell's Spicetify
    // extension does it and reports `restyled` once the new sheets are loaded and
    // painted. That word releases the spread — no AFTER, no guess. Nobody listening
    // (or the script never got as far as asking) releases it at the script's exit,
    // and a word that never comes costs spotifyGuard.
    property var _spotifyHold: null      // { token, exited } while waiting for the word
    property double _spotifyAskedAt: 0
    property bool _spotifyListening: false
    property double _spotifyPaintedAt: 0
    Connections {
        target: SpotifyBridge
        function onRestyleAsked(listening) {
            c._spotifyAskedAt = Date.now()
            c._spotifyListening = listening
            if (c._spotifyHold && !listening) c._spotifyRelease("no extension listening — not repainted live")
        }
        function onRestyled(sheets, loaded, ms) {
            c._spotifyPaintedAt = Date.now()
            if (c._spotifyHold)
                c._spotifyRelease("repainted (" + loaded + "/" + sheets + " sheets, " + ms + " ms in Spotify)")
        }
    }
    function _spotifyExited(p, job) {
        const took = Date.now() - p.started
        const asked = c._spotifyAskedAt >= p.started
        const painted = c._spotifyPaintedAt >= p.started
        console.info("Contagion: spotify script done in", took, "ms"
                     + (!asked ? "; it asked for no repaint"
                        : !c._spotifyListening ? "; no extension listening"
                        : painted ? "; already repainted" : "; waiting for Spotify to repaint"))
        if (!job.hold) return
        if (asked && c._spotifyListening && !painted) {
            c._spotifyHold = { token: job.token, exited: Date.now() }
            spotifyGuard.restart()
        } else {
            WallWave.releaseGo(job.token)
        }
    }
    function _spotifyRelease(why) {
        const h = c._spotifyHold
        c._spotifyHold = null
        spotifyGuard.stop()
        if (!h) return
        console.info("Contagion: spotify", why, "—", Date.now() - h.exited, "ms after its script")
        WallWave.releaseGo(h.token)
    }
    Timer {
        id: spotifyGuard
        interval: 1500
        onTriggered: c._spotifyRelease("never said it repainted; going anyway")
    }

    // Releases of the spread, each at its own moment: [{ at: epoch ms, token }].
    property var _releases: []
    function _releaseIn(token, ms) {
        const r = c._releases.concat([{ at: Date.now() + ms, token: token }])
        r.sort((a, b) => a.at - b.at)
        c._releases = r
        c._nextRelease()
    }
    function _nextRelease() {
        const now = Date.now()
        const r = c._releases
        while (r.length > 0 && r[0].at <= now) WallWave.releaseGo(r.shift().token)
        c._releases = r
        if (r.length > 0) {
            releaseTick.interval = Math.max(1, r[0].at - now)
            releaseTick.restart()
        }
    }
    Timer { id: releaseTick; onTriggered: c._nextRelease() }

    // ── 4. Settled ────────────────────────────────────────────────────────────
    function _end() {
        c._freezeTok = -1
        c._decidedTok = -1
        c._early = ({})
        c._waitTok = -1
        curtainWait.stop()
        c._spotifyHold = null
        spotifyGuard.stop()
        // Anything still timed is overdue by now — the front is long past.
        tick.stop()
        const left = c._flips
        c._flips = []
        for (const f of left) c._flip(f)
        c._restoreBorders()
        c.covers = ({})
        c._covered = ({})
        c._plan = null
    }

    // ── Hyprland's border fade, off for the wave ──────────────────────────────
    // A border colour change is Hyprland's `border` animation (here 640ms, linear),
    // so a border changed under the curtain would still be fading when the front
    // revealed it. The leaf is read from Hyprland itself — at start and after every
    // config reload, which also puts it back on its own — switched off at the freeze
    // and restored, exactly, when the wave settles. A leaf that only inherits can't
    // be restored exactly, so it's left alone and borders get its length as lead.
    property var _borderAnim: null
    property bool _borderMuted: false

    Process {
        id: animProc
        command: ["hyprctl", "animations", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                let leaf = null
                try {
                    const all = JSON.parse(text)
                    const leaves = Array.isArray(all) && Array.isArray(all[0]) ? all[0] : []
                    leaf = leaves.find(a => a && a.name === "border") || null
                } catch (e) { leaf = null }
                c._borderAnim = Logic.borderAnim(leaf)
            }
        }
    }
    Component.onCompleted: {
        animProc.running = true
        c._probeApps()
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "configreloaded") return
            // The reload has put the fade back from the config already.
            c._borderMuted = false
            animProc.running = false
            animProc.running = true
        }
    }

    function _muteBorders() {
        const a = c._borderAnim
        if (!a || !a.enabled || c._borderMuted) return
        c._borderMuted = true
        c._eval(Logic.borderAnimLua(a, false))
    }
    function _restoreBorders() {
        if (!c._borderMuted) return
        c._borderMuted = false
        c._eval(Logic.borderAnimLua(c._borderAnim, true))
    }

    // `hyprctl eval` runs Lua in the compositor; this one only ever gets the two
    // strings above, built from a whitelisted leaf (contagion.js borderAnim).
    function _eval(lua) {
        if (lua === "") return
        evalProc.command = ["hyprctl", "eval", lua]
        evalProc.running = false
        evalProc.running = true
    }
    Process {
        id: evalProc
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim()
                if (/error|fail|unknown|expected/i.test(out))
                    console.warn("Contagion: Hyprland refused the border fade change —", out)
            }
        }
    }

    // ── Diagnostic ────────────────────────────────────────────────────────────
    //   qs ipc -c ~/.config/quicktest call contagion status
    // Counts and states only.
    IpcHandler {
        target: "contagion"
        function status(): string {
            const entries = c._plan ? c._plan.entries : []
            return "planned=" + (c._plan !== null) + " windows=" + entries.length
                 + " looked=" + entries.filter(e => e.looked).length
                 + " covers=" + JSON.stringify(Object.keys(c.covers).map(k => k + ":" + c.covers[k].length))
                 + " covered=" + JSON.stringify(Object.keys(c._covered))
                 + " pending=" + c._flips.length
                 + " reachable=" + JSON.stringify(Object.keys(c._able))
                 + " running=" + JSON.stringify(["discord", "spotify", "browser"].filter(a => c._procFor(a).running))
                 + " early=" + JSON.stringify(c._early)
                 + " borderFade=" + (c._borderAnim ? (c._borderAnim.enabled ? c._borderAnim.speed * 100 + "ms" : "off") : "unknown")
                 + " muted=" + c._borderMuted
        }
    }
}
