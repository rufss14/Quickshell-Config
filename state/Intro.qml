pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

// ── Intro ─────────────────────────────────────────────────────────────────────
// The shell arriving: on launch, and on every reload. The bar drops out of the top
// edge, the screen frame traces down the sides from it, the bar's pills fade in left
// to right, and the desktop widgets rise last. On a reload (scripts/reload-quickshell.sh)
// the old shell plays the same thing backwards before it is killed.
//
// ── One clock, a table of windows ─────────────────────────────────────────────
// `t` runs 0 → 1 once. Each part of the shell reads its OWN window of it — `bar`,
// `frame`, `widgets`, `pill(pos)` — so the whole choreography is the four ranges
// below, in one file. Separate timers in Bar, ScreenFrame, BarGroupRow and WidgetLayer
// would drift the moment one of them was retuned. Leaving runs the same clock back
// down, so everything leaves in the reverse order it arrived without a second table.
//
// Consumers: components/IntroStage (the bar window, the frame overlay, the widget
// layer) and BarGroupRow's slot loader (each pill).
//
// ── It must never strand the shell invisible ──────────────────────────────────
// Until it plays, t is 0 and the shell is hidden. So: motion switched off is t = 1 at
// once (Motion.intro is 0); and a failsafe forces t = 1 if nothing has started it a few
// seconds in, whatever went wrong. A shell that skipped its entrance is a cosmetic
// bug; one that never appears is not.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property real t: 0
    readonly property bool playing: root.t < 1
    property bool leaving: false

    // ── The choreography: [start, end] windows of t ───────────────────────────
    readonly property var _barWin:     [0.00, 0.40]   // the band drops out of the top edge
    readonly property var _frameWin:   [0.25, 0.85]   // the ring's sides trace to the bottom
    readonly property var _pillsWin:   [0.35, 0.85]   // the pills, left to right
    readonly property var _widgetsWin: [0.60, 1.00]   // the desktop widgets rise

    // OutCubic — Motion.enter's curve — applied per window: each part decelerates into
    // place on its own, which is what makes overlapping windows read as a sequence and
    // not as one long linear fade.
    function _win(w) {
        const x = Math.max(0, Math.min(1, (root.t - w[0]) / (w[1] - w[0])))
        return 1 - Math.pow(1 - x, 3)
    }

    readonly property real bar:     root._win(root._barWin)
    readonly property real frame:   root._win(root._frameWin)
    readonly property real widgets: root._win(root._widgetsWin)

    // One pill at `pos` along the bar (0 = its left end, 1 = its right end). Each gets
    // 40% of the pills window, starting further in the further right it sits — so they
    // overlap and the row reads as a sweep rather than a queue.
    function pill(pos) {
        const span = root._pillsWin[1] - root._pillsWin[0]
        const len = span * 0.4
        const a = root._pillsWin[0] + Math.max(0, Math.min(1, pos)) * (span - len)
        return root._win([a, a + len])
    }

    // Where the frame's front is, in px from the top of the screen: hidden at t = 0, the
    // bar's band (`band` px) once the entrance starts, then down to `total` as the frame
    // traces. The bar window and ScreenFrame's overlay both clip to this, with the same
    // arguments, so their two fronts are one edge.
    function front(band, total) {
        return root.t > 0 ? band + (total - band) * root.frame : 0
    }

    // ── Playing ───────────────────────────────────────────────────────────────
    function play() {
        root.leaving = false
        clock.stop()
        if (Motion.intro <= 0) { root.t = 1; return }
        root.t = 0
        clock.to = 1
        clock.duration = Motion.intro
        clock.start()
    }

    // Runs the clock back to 0 and returns how long that takes, in ms. Not undone by
    // anything: the shell that calls this is about to be killed.
    function leave() {
        root.leaving = true
        clock.stop()
        const ms = Math.round(Motion.introExit * root.t)
        if (ms <= 0) { root.t = 0; return 0 }
        clock.to = 0
        clock.duration = ms
        clock.start()
        return ms
    }

    property NumberAnimation _clock: NumberAnimation {
        id: clock
        target: root
        property: "t"
        // Linear on purpose: the easing lives in each window (_win), and easing the
        // clock as well would compound the two.
        easing.type: Easing.Linear
    }

    // ── Starting ──────────────────────────────────────────────────────────────
    // After the preferences, because motionEnabled / motionScale are the user's: started
    // on the defaults, it would animate for someone who turned motion off. Then a short
    // beat, so the surfaces have mapped and the first frames aren't spent on a jump.
    property bool _started: false
    function _maybeStart() {
        if (root._started || !Config.prefsLoaded) return
        root._started = true
        beat.start()
    }
    property Timer _beat: Timer {
        id: beat
        interval: 120
        onTriggered: root.play()
    }
    Component.onCompleted: root._maybeStart()
    property Connections _prefs: Connections {
        target: Config
        function onPrefsLoadedChanged() { root._maybeStart() }
    }

    property Timer _failsafe: Timer {
        interval: 4000
        running: true
        onTriggered: if (!root.leaving && !clock.running && root.t < 1) {
            console.warn("Intro: the entrance never started — showing the shell as it is")
            root.t = 1
        }
    }

    // ── IPC ───────────────────────────────────────────────────────────────────
    //     qs ipc -p <repo> call intro play     replay the entrance (to look at it)
    //     qs ipc -p <repo> call intro leave    the exit; answers its length in ms
    property var _ipc: IpcHandler {
        target: "intro"
        function play(): void { root.play() }
        function leave(): int { return root.leave() }
    }
}
