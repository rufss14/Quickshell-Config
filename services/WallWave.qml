pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "../config"

// ── WallWave ──────────────────────────────────────────────────────────────────
// A wallpaper or colour change arrives as ONE wave, spreading from the bottom middle
// of the screen like water — ported from the user's other shell, where it was built
// to make the picture and the palette change "on the same second, together, in
// rhythm, like an infection" instead of a picture swap followed by a colour snap.
//
// One clock drives every picture of it:
//   · the WATER — the new wallpaper spreading over the old (WallpaperView, one slot
//     per channel below);
//   · the INFECTION — each shell window keeps a frozen snapshot of its old look, and
//     the same front eats it away, glowing in the new accent, while the new colours
//     are already live underneath (components/Infection.qml);
//   · the APPS — each window's border and colours flip the moment the front reaches
//     it (services/Contagion.qml).
// Same curve, same wobble (shaders/wavefront.glsl), same `t`.
//
// ── The protocol ──────────────────────────────────────────────────────────────
// Driven by ThemeRunner from the theming scripts' `WAVE=` lines, so every theming
// run (a wallpaper, a scheme, a pin, a rebuild) arrives the same way:
//   prepare(image, output, recolor, keep) → token   ThemeRunner, as the script
//        starts. Loads the new picture into its slot. NOTHING visible changes — the
//        shell stays live while the palette is computed (a first-time pywal run on a
//        big picture takes seconds). `keep`: the shell itself will draw this picture
//        as the wallpaper afterwards, so the water hands over to it instead of
//        fading off it (awww's picture, a scene).
//   freeze(token)    WAVE=ready: the palette is computed and about to be committed.
//        Every shell window snapshots its look NOW; the script waits `freezeMs`.
//   commit(token)    WAVE=go: the palette is committed (one atomic swap). Colors
//        re-reads it (paletteRead — Contagion tells every app, under cover), colour
//        animations are snapped (Motion.snap) and given `settleMs` to be drawn under the snapshots —
//        longer if an app near the start of the front needs it (delayGo) — then
//        go().
//   go(token)        the front spreads, over `Motion.wave`.
//   done(token)      WAVE=done: the real wallpaper is in place under the water.
//   finish(token)    the script exited — go and done, whatever it managed to say.
//   hold / release   something besides the script must finish first: a scene's
//        water stays up until the scene itself is running (WallpaperEngine), not
//        until its palette script exits.
// A change that doesn't recolour (theming off, colours held by a scheme) never
// freezes: its commit goes at once, and only the water moves.
//
// ── Two channels ──────────────────────────────────────────────────────────────
// Used in turn (token % 2), as in the original: a change started while another is
// still spreading floods over it on its own clock instead of cancelling it. The
// infection follows the newest change that FROZE (`infectSeq`) — not the newest
// prepared, which may still be computing its palette while an older one spreads.
// A third overlapping change takes the first one's channel; that one just stops.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: w

    // Animations off means no wave at all: ThemeRunner then runs the scripts the old
    // way (picture first, colours instant), which is what "off" should mean for a
    // hero animation.
    readonly property bool enabled: Config.motionEnabled

    // ── Timing ────────────────────────────────────────────────────────────────
    readonly property int spreadMs: Motion.wave
    // How long the script waits between WAVE=ready and the commit. NOT a motion
    // duration — a synchronisation margin: every window's snapshot has to be taken
    // (two or three frames — Infection counts them) before the palette changes under
    // it. Late is harmless-ish (the colours change a beat before the front); a
    // missed snapshot is not, so this is generous.
    // Only the BASE of a timeout now: the script waits for the shell's word that every
    // snapshot is taken (`snapped`), and gives up after three times this.
    readonly property int freezeMs: 120
    // What the colour animations used to be waited out for (Motion.standard, 150ms): now
    // Motion.snap makes them instant under the snapshots, and this is the frames it takes to
    // DRAW the new colours there before the front leaves — three at 60Hz.
    readonly property int settleMs: 50
    // The most the spread may be held for apps still recolouring under cover
    // (Contagion: delayGo for the fixed leads, holdGo for the scripted apps until
    // each has really repainted). A net for an app that hangs, not a target: past it
    // the wave goes regardless.
    readonly property int appWaitMs: 2500
    // The LONGEST from WAVE=go until the water has finished spreading: the reload +
    // the settle + the most an app may hold it + the spread, plus a margin. Not a
    // sleep — the script waits for the shell's word that the water has landed
    // (ThemeRunner, on `landed`) and only falls back to this as its timeout, so a
    // quick change isn't made to wait as if an app had held it.
    readonly property int landMs: Motion.standard + w.appWaitMs + w.spreadMs + 150

    // ── The newest change ─────────────────────────────────────────────────────
    property int seq: 0
    property string image: ""      // absolute path; "" = colours only, no water
    property string output: ""     // "" = every screen; else one monitor's name
    property bool recolor: false
    property bool keep: false      // the shell draws this picture once the water lands

    // ── Channels ──────────────────────────────────────────────────────────────
    property real p0: 0
    property real p1: 0
    // Plain arrays, read imperatively only: which token owns each channel, whether
    // it recolours, and whether it has gone.
    property var _tok: [-1, -1]
    property var _rec: [false, false]
    property var _gone: [true, true]
    function channel(token) { return token % 2 }
    function progressOf(ch) { return ch === 0 ? w.p0 : w.p1 }
    function tokenOn(ch) { return w._tok[ch] }

    // ── The infection ─────────────────────────────────────────────────────────
    property int infectSeq: -1
    readonly property real infectProgress:
        w.infectSeq < 0 ? 1 : w.progressOf(w.channel(w.infectSeq))
    // infectProgress when the newest freeze came: an Infection already mid-spread
    // keeps drawing THAT while it re-snapshots, so the capture takes exactly it.
    property real lastProgress: 1
    property bool frozen: false        // snapshots up, waiting for the palette
    property bool holding: false       // the newest change waits for `done`
    readonly property bool spreading: spread0.running || spread1.running
    readonly property bool active: w.frozen || w.spreading || w.holding
    readonly property bool settled: !w.active

    signal prepared(int token)         // WallpaperView: load the picture
    signal froze(int token)            // Infection: snapshot now
    signal paletteRead(int token)      // the new palette is live under the snapshots (Contagion)
    signal went(int token)             // a recolouring change started spreading
    signal landed(int token)           // its water covers the screen

    function prepare(img, out, recol, kept) {
        w.seq++
        const t = w.seq, ch = w.channel(t)
        // A third change overlapping two takes the first one's channel. If that one
        // was still frozen, it is abandoned — it must not hold the shell frozen.
        if (w._tok[ch] === w.infectSeq && w.frozen) { w.frozen = false; goGuard.stop() }
        ;(ch === 0 ? spread0 : spread1).stop()
        if (ch === 0) w.p0 = 0; else w.p1 = 0
        w._tok[ch] = t
        w._rec[ch] = recol === true
        w._gone[ch] = false
        w.image = img || ""
        w.output = out || ""
        w.recolor = recol === true
        w.keep = kept === true
        w.holding = true
        w._holds = 0
        w._doneAsked = false
        w._bornAt = Date.now()
        doneGuard.restart()
        console.info("WallWave: prepare #" + t, w.image !== "" ? w.image.split("/").pop() : "(colours only)",
                     w.output || "(all screens)", w.recolor ? "recolour" : "picture only")
        w.prepared(t)
        return t
    }

    property int leadMs: 800

    // When the newest change began (prepare), for the log: every phase says how far in
    // it happened — the one place that shows where a change's time goes, end to end.
    property double _bornAt: 0
    function _since() { return " (+" + (Date.now() - w._bornAt) + " ms)" }

    function _live(t) {
        const ch = w.channel(t)
        return t > 0 && w._tok[ch] === t && !w._gone[ch]
    }

    function freeze(t) {
        if (!w._live(t) || !w._rec[w.channel(t)] || t < w.infectSeq) return
        w.lastProgress = w.infectProgress
        w.infectSeq = t
        w.frozen = true
        goGuard.restart()
        console.info("WallWave: freeze #" + t + w._since())
        w.froze(t)
        // No window took a snapshot (none visible): nothing to wait for.
        if (!(w._snaps[t] > 0)) w.snapped(t)
    }

    // The palette is on disk. Nothing frozen for this change → nothing to wait for.
    property int _pendingGo: -1
    function commit(t) {
        if (!w._live(t)) return
        if (t !== w.infectSeq || !w.frozen) { w.go(t); return }
        w._pendingGo = t
        w._goDelay = 0
        w.readAt = 0
        // Holds Contagion took at the freeze (apps shown the moment the curtain was up)
        // carry over; any older ones don't.
        if (w._holdTok !== t) w._goHolds = 0
        w._goDue = false
        // Under the snapshots from here to the front: colours change, nothing animates.
        Motion.snap = true
        snapGuard.restart()
        Colors.reload()
        reloadGuard.restart()
    }

    // Held by Contagion from the moment it starts an app's recolour until that app has
    // really repainted: the spread goes once the settle has passed AND every hold is
    // released — or `appWaitMs` after the first hold, whatever is left. A hold may be
    // taken from the FREEZE on (a staged app is shown as soon as its curtain is up,
    // before the palette is even committed), so holds belong to a token, not to the
    // pending go.
    property int _goHolds: 0
    property int _holdTok: -1
    property bool _goDue: false        // the settle has passed; waiting on holds
    function holdGo(t) {
        if (t !== w._pendingGo && !(t === w.infectSeq && w.frozen)) return
        if (w._holdTok !== t) { w._holdTok = t; w._goHolds = 0 }
        if (w._goHolds === 0) holdCap.restart()
        w._goHolds++
    }
    function releaseGo(t) {
        if (t !== w._holdTok || w._goHolds <= 0) return
        w._goHolds--
        w._tryGo()
    }
    function _tryGo() {
        if (!w._goDue || w._goHolds > 0) return
        holdCap.stop()
        const t = w._pendingGo
        w._pendingGo = -1
        w._goDue = false
        if (t > 0) w.go(t)
    }
    Timer {
        id: holdCap
        interval: w.appWaitMs
        onTriggered: {
            console.warn("WallWave: an app was still recolouring after", w.appWaitMs, "ms — spreading anyway")
            w._goHolds = 0
            w._tryGo()
        }
    }

    // Asked for from paletteRead, before the settle starts: hold the spread this long
    // (at least settleMs) so what is recolouring under cover is done by the
    // time the front reaches it. Contagion caps what it asks for.
    // Asked for LATE (Contagion waits for its curtain before it decides, holding the
    // spread meanwhile): the settle is already running, or already done and waiting
    // on holds — so it is re-armed to end that long after the palette was READ.
    property int _goDelay: 0
    property double readAt: 0          // when paletteRead fired (epoch ms); 0 = not yet
    function delayGo(t, ms) {
        if (t !== w._pendingGo) return
        w._goDelay = Math.max(w._goDelay, Math.round(ms) || 0)
        if (w.readAt <= 0) return
        const left = w.readAt + Math.max(w.settleMs, w._goDelay) - Date.now()
        if (left <= 0 || !(settle.running || w._goDue)) return
        w._goDue = false
        settle.interval = left
        settle.restart()
    }

    function go(t) {
        if (!w._live(t)) return
        // Before the spread starts, or its own durations (Motion.wave is exempt, but the
        // easing and everything bound to it read the live values) would start at 0.
        w._unsnap()
        // A view still decoding this change's picture: the front would sweep over nothing
        // and "land" on a screen that isn't covered — and whoever stops the old wallpaper
        // on landing (Wallpaper, for a scene) would be leaving the desktop bare. It goes
        // when the last picture is ready (loadRelease), or after loadCap.
        if ((w._loads[t] || 0) > 0) {
            w._goLate = t
            loadCap.restart()
            return
        }
        const ch = w.channel(t)
        w._gone[ch] = true
        // How long a change takes from prepare to its front leaving, measured: whoever wants
        // the front to start at a known moment (a scene, whose picture arrives by its own
        // fade) has to start the change this much earlier. Smoothed; it varies with what
        // the apps do under the curtain.
        if (t === w.seq && w._rec[ch])
            w.leadMs = Math.max(200, Math.min(2500,
                Math.round((w.leadMs + (Date.now() - w._bornAt)) / 2)))
        if (w._pendingGo === t || w._holdTok === t) {
            w._pendingGo = -1
            w._goHolds = 0
            w._holdTok = -1
            w._goDue = false
            reloadGuard.stop()
            settle.stop()
            holdCap.stop()
        }
        ;(ch === 0 ? spread0 : spread1).restart()
        console.info("WallWave: go #" + t + (t === w.seq ? "" : " (under the newest, #" + w.seq + ")") + w._since())
        if (t === w.infectSeq && w.frozen) {
            w.frozen = false
            goGuard.stop()
            w.went(t)
        }
    }

    // ── Pictures still decoding ───────────────────────────────────────────────
    // WallpaperView takes one hold per screen when it starts loading the change's picture
    // (prepare → `prepared`, synchronously, so before any go) and gives it back when that
    // picture is Ready — or has failed. A big picture at the parallax zoom, decoded at
    // physical resolution, outlasts the freeze and the colour settle.
    property var _loads: ({})
    property int _goLate: -1
    function loadHold(t) { w._loads[t] = (w._loads[t] || 0) + 1 }
    function loadRelease(t) {
        if (!(w._loads[t] > 0)) return
        w._loads[t]--
        if (w._loads[t] > 0) return
        delete w._loads[t]
        if (w._goLate === t) { w._goLate = -1; loadCap.stop(); w.go(t) }
    }
    // A picture that never reports (a view torn down mid-load) must not hold the wave.
    Timer {
        id: loadCap
        interval: 6000
        onTriggered: {
            console.warn("WallWave: a picture was still loading after", loadCap.interval, "ms — spreading anyway")
            const t = w._goLate
            w._loads = ({})
            w._goLate = -1
            if (t > 0) w.go(t)
        }
    }

    function done(t) {
        if (t !== w.seq) return
        if (w._holds > 0) { w._doneAsked = true; return }
        if (w.holding) console.info("WallWave: done #" + t + w._since())
        w.holding = false
        doneGuard.stop()
    }

    // Holds on the newest change's `done`: it lands only once every hold is
    // released AND done was asked for.
    property int _holds: 0
    property bool _doneAsked: false
    function hold(t) { if (t === w.seq) w._holds++ }
    function release(t) {
        if (t !== w.seq || w._holds <= 0) return
        w._holds--
        if (w._holds === 0 && w._doneAsked) w.done(t)
    }

    function finish(t) {
        w.go(t)
        w.done(t)
    }

    // ── Waiting for the palette to be READ, then for the colours to settle ────
    // Colors watches colors.json itself, but an inotify event and this script's
    // stdout line race each other; asking again and waiting for the answer is the
    // only way to know the shell is wearing the new palette. Then the colour
    // animations (Motion.respond … standard) play out unseen under the snapshots.
    Connections {
        target: Colors
        function onFileDataChanged() {
            if (w._pendingGo < 0 || !reloadGuard.running) return
            reloadGuard.stop()
            // The demo changes nothing, so no app is told anything.
            console.info("WallWave: palette read #" + w._pendingGo + w._since())
            if (w._pendingGo !== w._demoToken) w.paletteRead(w._pendingGo)
            settle.interval = Math.max(w.settleMs, w._goDelay)
            settle.restart()
            w.readAt = Date.now()
        }
    }
    // A palette that can't be read still has to arrive: the old colours, then.
    Timer {
        id: reloadGuard
        interval: 400
        onTriggered: { settle.interval = w.settleMs; settle.restart() }
    }
    Timer {
        id: settle
        interval: w.settleMs
        onTriggered: { w._goDue = true; w._tryGo() }
    }

    // ── Motion.snap's lifetime ────────────────────────────────────────────────
    // Raised by commit(), dropped by go(). A change that dies in between (its channel taken,
    // a script that hangs) must not leave the whole shell without animation.
    function _unsnap() { Motion.snap = false; snapGuard.stop() }
    Timer {
        id: snapGuard
        interval: 3000
        onTriggered: {
            console.warn("WallWave: animations were snapped for 3s — letting go")
            Motion.snap = false
        }
    }

    // ── Every snapshot taken ──────────────────────────────────────────────────
    // Each Infection takes a hold when it starts its snapshot (on `froze`, synchronously, so
    // all of them before any release) and gives it back once it is drawn and covering. The
    // last release says `snapped`, and ThemeRunner tells the script — which used to sleep a
    // fixed freezeMs and now waits exactly as long as the frames take.
    signal snapped(int token)
    property var _snaps: ({})
    function snapHold(t) { w._snaps[t] = (w._snaps[t] || 0) + 1 }
    function snapRelease(t) {
        if (!(w._snaps[t] > 0)) return
        w._snaps[t]--
        if (w._snaps[t] > 0) return
        delete w._snaps[t]
        w.snapped(t)
    }

    // ── Guards ────────────────────────────────────────────────────────────────
    // ThemeRunner calls finish() when the script exits, so these only catch a script
    // that hangs. A frozen shell is a dead clock on the bar, so the freeze gives up
    // first; the hold is only the water staying up.
    Timer {
        id: goGuard
        interval: 10000
        onTriggered: {
            if (!w.frozen) return
            console.warn("WallWave: #" + w.infectSeq + " froze and never committed — spreading anyway")
            w.go(w.infectSeq)
            w.frozen = false          // even if its channel was taken and go couldn't
        }
    }
    Timer {
        id: doneGuard
        interval: 30000
        onTriggered: {
            console.warn("WallWave: #" + w.seq + " never reported done — letting go")
            w._holds = 0
            w.holding = false
        }
    }

    NumberAnimation {
        id: spread0
        target: w; property: "p0"; from: 0; to: 1
        duration: w.spreadMs
        easing.type: Motion.travel
        onFinished: { console.info("WallWave: landed #" + w._tok[0] + w._since()); w.landed(w._tok[0]) }
    }
    NumberAnimation {
        id: spread1
        target: w; property: "p1"; from: 0; to: 1
        duration: w.spreadMs
        easing.type: Motion.travel
        onFinished: { console.info("WallWave: landed #" + w._tok[1] + w._since()); w.landed(w._tok[1]) }
    }

    // ── The rim's clock, shared so the water and the shell wobble as one ──────
    // Seconds. Ambient (Motion's category 2): a clock the shaders read, not a
    // transition — honoured by not running with animations off, and only while a
    // change is in flight. The long period just keeps it from ever wrapping mid-wave.
    property real t: 0
    NumberAnimation on t {
        running: w.active && Config.motionEnabled
        loops: Animation.Infinite
        from: 0; to: 600; duration: 600000
    }

    // ── Hyprland must not animate the wave's own surfaces in or out ──────────
    // Hyprland eases every layer surface as it maps (here `fadeLayersIn` inherits a
    // 1s fade). The wave maps two for a change — the water over a scene or awww
    // (quickshell-wallpaper) and the app curtain (quickshell-wave) — and both have to
    // be there at once, or the new picture fades in over a second and the curtain's
    // frozen apps half-show the live ones they cover. A layer rule, put in at RUNTIME
    // (as CursorEffects configures its plugin), so it holds on any Hyprland config;
    // a config reload drops runtime rules, so it goes in again on `configreloaded`.
    readonly property string _layerRule:
        'hl.layer_rule({ name = "quickshell-wave", '
        + 'match = { namespace = "^quickshell-(wave|wallpaper)$" }, no_anim = true })'
    Process {
        id: ruleProc
        command: ["hyprctl", "eval", w._layerRule]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = text.trim()
                if (/error|fail|unknown|expected/i.test(out))
                    console.warn("WallWave: Hyprland refused the no-animation layer rule —", out)
            }
        }
    }
    Component.onCompleted: ruleProc.running = true
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "configreloaded") return
            ruleProc.running = false
            ruleProc.running = true
        }
    }

    // ── Diagnostic ────────────────────────────────────────────────────────────
    //   qs ipc -c ~/.config/quicktest call wallwave status
    //   qs ipc -c ~/.config/quicktest call wallwave demo
    // `demo` plays the whole transition with nothing changing: the current wallpaper
    // spreads over itself and the shell burns in its own colours. No script runs,
    // no file is written — it is for looking at the effect.
    IpcHandler {
        target: "wallwave"

        function status(): string {
            return "enabled=" + w.enabled + " seq=" + w.seq + " infect=" + w.infectSeq
                 + " frozen=" + w.frozen + " spreading=" + w.spreading + " holding=" + w.holding
                 + " p0=" + w.p0.toFixed(2) + " p1=" + w.p1.toFixed(2)
                 + " image=" + (w.image !== "" ? w.image.split("/").pop() : "-")
                 + " output=" + (w.output || "-") + " recolor=" + w.recolor
                 + " keep=" + w.keep + " holds=" + w._holds
        }

        function demo(): string {
            if (!w.enabled) return "animations are off"
            if (w.active) return "a change is already in flight"
            demoRun.token = w.prepare(Wallpaper.currentPath, "", true, Config.wallShellRender)
            w._demoToken = demoRun.token
            demoRun.step = 0
            demoRun.restart()
            return "demo #" + demoRun.token
        }
    }
    property int _demoToken: -1
    // The demo walks the same protocol a script does: ready, go, done.
    Timer {
        id: demoRun
        property int token: -1
        property int step: 0
        interval: 250
        onTriggered: {
            if (demoRun.step === 0) {
                w.freeze(demoRun.token)
                demoRun.step = 1
                demoRun.interval = w.freezeMs
                demoRun.restart()
            } else if (demoRun.step === 1) {
                w.commit(demoRun.token)
                demoRun.step = 2
                // Nothing is recolouring, so nothing holds it: the plain spread.
                demoRun.interval = w.settleMs + w.spreadMs + 300
                demoRun.restart()
            } else {
                w.done(demoRun.token)
                demoRun.interval = 250
            }
        }
    }
}
