pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "../config"
import "musicpulse.js" as MP

// ── MusicPulse ────────────────────────────────────────────────────────────────
// What the music is doing right now, as a handful of 0..1 numbers anything on the desktop
// can move to (2026-10-31): the wallpaper effects (modules/desktop/WallFx) and the
// music-reactive sidebar.
//
//   level · bass · mid · high   envelopes (fast up, slower down)
//   kick                        1 on a kick, heard, decaying; `beats` counts them
//   snare · hat                 the same for a snare/clap and a hi-hat; `snares` counts snares
//   flash                       1 on the hardest hits, at most three a second (the strobe's)
//   bpm · locked                the tempo the beat clock follows, and whether it has the phase
//   loud · sub · heavy          how big this part is against the song (helper only; -1 unknown)
//   song · songView · character what the track is like (hit rates, energy, section, drop) — what
//                               the wallpaper effects adapt to; musicpulse.js songStep
//
// ── A beat clock, not a reaction (2026-10-31) ─────────────────────────────────
// The user, more than once: the effects "feel off or slow compared to the song". So the
// numbers come from scripts/music-pulse.py when it can run (pw-record and numpy, probed once):
// the player's audio read in 5 ms steps, the kick, snare/clap and hi-hat told apart, and the
// tempo and phase tracked so an 808 note between the beats isn't taken for a kick. Nothing
// fires unless it is heard (the user, same day: "shaking and zooming without kicks" — the
// clock used to fire its predicted grid). Measured: the cava detector found 3 beats in 20 s;
// the helper, on the synthetic kit, every kick and snare and none that weren't (python3
// scripts/test-music-pulse.py). `bpm` and `locked` say what it is locked to. Without the
// helper's tools, the cava stream below and musicpulse.js are the fallback.
//
// ── The fallback: its own spectrum, of the player's own audio ─────────────────
// Not the shared one (Cava): that is tuned to be looked at — 32 bars over 50 Hz–10 kHz, the
// default output's mix — and measured, its bass sat at the ceiling half the time, so no kick
// ever read as a jump. This runs a CavaStream tuned for beats (24 bars, 40 Hz–8 kHz, half the
// sensitivity, less smoothing — see musicpulse.js for the measurement) on the PLAYER's node
// (Audio.streamsFor, VisualizerPill's lookup), so a Discord call or a notification sound is
// not part of the music; the default output when PipeWire names no stream for it.
//
// ── Only while it is wanted and music plays ───────────────────────────────────
// Refcounted (acquire/release, paired). The stream runs only while something wants it AND an
// MPRIS player is playing (Discord's call audio is not music — MediaController's rule) AND
// Game Mode is off; otherwise the numbers ease back to 0 on their own frames instead of
// snapping, so an effect winds down with the track.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property int _refs: 0
    function acquire() { root._refs++ }
    function release() { root._refs = Math.max(0, root._refs - 1) }

    // The player worth showing: the first one PLAYING that isn't Discord, else the first that
    // isn't Discord at all, else null — for the sidebar's now-playing cell. `playing` is it
    // being played.
    readonly property var player: {
        const all = Mpris.players.values
        let first = null
        for (let i = 0; i < all.length; i++) {
            const p = all[i]
            const c = (p.desktopEntry || "").toLowerCase()
            if (Discord.windowClasses.some(prefix => c.startsWith(prefix))) continue
            if (p.playbackState === MprisPlaybackState.Playing) return p
            if (first === null) first = p
        }
        return first
    }
    readonly property bool playing: root.player !== null
        && root.player.playbackState === MprisPlaybackState.Playing
    readonly property bool live: root._refs > 0 && root.playing && !PowerSaver.quiet

    property real level: 0
    property real bass: 0
    property real mid: 0
    property real high: 0
    property real kick: 0
    property int beats: 0
    property real snare: 0
    property int snares: 0
    property real hat: 0
    property real boom: 0       // a bass note that isn't a kick; `booms` counts them
    property int booms: 0
    property real impact: 0     // the hardest hit, one a second at most; `impacts` counts them
    property int impacts: 0
    property real flash: 0
    // How big this part of the song is, from the helper only (-1 = not known: the cava
    // fallback can't tell, its levels are renormalised): `loud` and `sub` against the song's
    // loudest, `heavy` the last kick's bass. scripts/music-pulse.py's header has the why.
    property real loud: -1
    property real sub: -1
    property real heavy: -1
    // Backbeat snares — the ones worth a shockwave (the rhythm engine's "back" role); -1 without
    // the helper. `hats` and `drops` count the same way; `kickBoost` is >1 on a drop's or phrase's
    // kick; `barpos` is where in the bar the music is (0..4, -1 unknown).
    property int accents: -1
    property int hats: 0
    property int drops: -1
    property real kickBoost: 1
    property real barpos: -1
    property real section: -1
    // The speakers' latency behind the tap, as the helper measured it (ms): events show then.
    property int latencyMs: 0
    property real bpm: 0
    property bool locked: false

    // ── The helper ────────────────────────────────────────────────────────────
    property bool dspOk: false
    property bool probed: false
    Process {
        id: probe
        running: true
        command: ["sh", "-c", "command -v pw-record >/dev/null && python3 -c 'import numpy' 2>/dev/null"]
        onExited: function (code) { root.dspOk = code === 0; root.probed = true }
    }
    readonly property bool _useDsp: root.dspOk && root.live
    // The rhythm engine's events, scheduled for when they're heard (musicpulse.js schedLine/
    // schedAt): Sync is applied HERE now, not by restarting the helper — a restart relearned the
    // tempo every time the fader moved.
    readonly property var _dspCommand: ["python3", Quickshell.shellPath("scripts/music-pulse.py"),
        "--target", root.sourceNode]
    property var _sched: MP.schedInitial()
    // Restarts dip `_cycling` so `running` stays a binding (CavaStream's reason: assigning it
    // would leave the helper running after the music stops). An exit of its own — PipeWire
    // restarting, the player's node gone — restarts it after 1 s, backing off to 30 s.
    property bool _cycling: false
    property int _backoffMs: 500
    property double _startedAt: 0
    // Set when WE stop it, so that exit isn't taken for a crash; the next start clears it.
    property bool _stopping: false
    on_DspCommandChanged: if (dsp.running) {
        root._stopping = true
        root._cycling = true
        Qt.callLater(() => root._cycling = false)
    }
    on_UseDspChanged: if (!root._useDsp) {
        root._stopping = true; dspRestart.stop(); root._backoffMs = 500
        root.loud = -1; root.sub = -1; root.heavy = -1; root.accents = -1; root.section = -1; root.barpos = -1
        root.drops = -1; root.kickBoost = 1
    }
    Timer {
        id: dspRestart
        onTriggered: if (root._useDsp && !dsp.running) { root._cycling = true; root._cycling = false }
    }
    Process {
        id: dsp
        running: root._useDsp && !root._cycling
        command: root._dspCommand
        onStarted: { root._startedAt = Date.now(); root._stopping = false }
        onExited: function (code) {
            if (root._stopping || !root._useDsp || root._cycling || dsp.running) return
            root._backoffMs = Date.now() - root._startedAt > 30000 ? 1000 : Math.min(30000, root._backoffMs * 2)
            console.warn("MusicPulse: music-pulse.py exited (" + code + ") — restarting in "
                         + Math.round(root._backoffMs / 1000) + "s")
            dspRestart.interval = root._backoffMs
            dspRestart.restart()
        }
        onRunningChanged: {
            if (running) {
                // A new audio clock and empty queues; the counts carry on (they mean "a new hit").
                root._sched = MP.schedRestart(root._sched)
                root._at = 0
            } else root._s = Object.assign(MP.initial(), { level: root.level, bass: root.bass, mid: root.mid,
                                                           high: root.high, kick: root.kick, flash: root.flash,
                                                           beats: root.beats, snare: root.snare,
                                                           snares: root.snares, hat: root.hat,
                                                           boom: root.boom, booms: root.booms,
                                                           impact: root.impact, impacts: root.impacts })
        }
        stdout: SplitParser {
            onRead: function (line) {
                const f = line.split(" ")
                if (f[0] === "error") { console.warn("MusicPulse: " + line.slice(6)); return }
                MP.schedLine(root._sched, f, Date.now(), Config.wallFxSyncMs)
                if (f[0] === "latency") root.latencyMs = root._sched.latency
            }
        }
    }

    // What the music sounds like at wall time `nowMs` (ms): the rhythm engine's pulse, scheduled
    // (musicpulse.js schedAt), or — on the cava fallback — the last published values. WallFx asks
    // once per drawn frame, so each hit lands on the frame it's heard.
    function pulseAt(nowMs) {
        if (root._useDsp && dsp.running) return MP.schedAt(root._sched, nowMs)
        return { level: root.level, bass: root.bass, mid: root.mid, high: root.high, kick: root.kick,
                 beats: root.beats, flash: root.flash, snare: root.snare, snares: root.snares, hat: root.hat,
                 boom: root.boom, booms: root.booms, impact: root.impact, impacts: root.impacts,
                 heavy: root.heavy, accents: root.accents, kickBoost: 1, section: -1, drops: -1 }
    }

    // The properties, for everything that binds rather than asks (the bars' rim, the Effects
    // page's dots, the song profile): published ~60 times a second while the helper plays.
    Timer {
        interval: 16
        repeat: true
        running: root._useDsp && dsp.running
        onTriggered: {
            const p = MP.schedAt(root._sched, Date.now())
            root.level = p.level; root.bass = p.bass; root.mid = p.mid; root.high = p.high
            root.kick = p.kick; root.beats = p.beats; root.heavy = p.heavy; root.kickBoost = p.kickBoost
            root.snare = p.snare; root.snares = p.snares; root.accents = p.accents
            root.hat = p.hat; root.hats = p.hats
            root.impact = p.impact; root.impacts = p.impacts; root.drops = p.drops; root.flash = p.flash
            root.loud = p.loud; root.sub = p.sub; root.section = p.section; root.barpos = p.barpos
            root.bpm = p.locked ? p.bpm : 0; root.locked = p.locked
            root.boom = 0
            root._songStep()
        }
    }

    // ── The song (2026-10-31): what the effects adapt to ──────────────────────
    // A running picture of the track (musicpulse.js `songStep`): how often each drum is heard,
    // how driving it is, whether the drums just dropped out. Stepped per pulse while live (not
    // while winding down: a pause shouldn't make the song look calmer), reset per track.
    // `songView` is what services/wallfx.js weighs the effects by; `character` the Effects
    // page's words for it.
    property var song: MP.songInitial()
    readonly property var songView: MP.songView(root.song)
    readonly property string character: MP.character(root.songView)
    property real _songAt: 0
    function _songStep() {
        const now = Date.now()
        const dt = root._songAt > 0 ? now - root._songAt : 0
        root._songAt = now
        root.song = MP.songStep(root.song, root, dt)
    }
    readonly property string _track: root.player
        ? (root.player.trackTitle ?? "") + "\n" + (root.player.trackArtist ?? "") : ""
    on_TrackChanged: { root.song = MP.songInitial(); root._songAt = 0 }

    property var _s: MP.initial()
    property real _at: 0
    function _publish(s) {
        root._s = s
        root.level = s.level; root.bass = s.bass; root.mid = s.mid; root.high = s.high
        root.kick = s.kick; root.beats = s.beats; root.flash = s.flash
        root.snare = s.snare; root.snares = s.snares; root.hat = s.hat
        root.boom = s.boom; root.booms = s.booms; root.impact = s.impact; root.impacts = s.impacts
    }
    function _dt() {
        const now = Date.now()
        const dt = root._at > 0 ? now - root._at : 0
        root._at = now
        return dt
    }

    onLiveChanged: {
        root._at = 0
        root._songAt = 0
        if (!root.live) { root.bpm = 0; root.locked = false }
    }

    readonly property string sourceNode: {
        const appId = root.player ? (root.player.desktopEntry || "") : ""
        if (!appId) return ""
        const nodes = Audio.streamsFor(appId)
        // (`?? ""`: a node PipeWire hasn't described yet has no name.)
        return nodes.length > 0 ? (nodes[0].name ?? "") : ""
    }

    CavaStream {
        id: stream
        tag: "pulse"
        source: root.sourceNode
        running: root.live && root.probed && !root.dspOk
        barCount: 24
        sensitivity: 100
        noiseReduction: 0.1
        lowerCutoff: 40
        higherCutoff: 8000
        onBarsChanged: if (root.live && stream.bars.length > 0) {
            root._publish(MP.step(root._s, stream.bars, root._dt()))
            root._songStep()
        }
    }

    // Winding down: no cava frames any more, so step toward silence on the display's own,
    // until there is nothing left to move.
    FrameAnimation {
        running: !root.live && (root.level > 0.002 || root.kick > 0.002 || root.bass > 0.002 || root.flash > 0.002
                                || root.snare > 0.002 || root.hat > 0.002 || root.boom > 0.002 || root.impact > 0.002)
        onTriggered: root._publish(MP.rest(root._s, root._dt()))
    }
}
