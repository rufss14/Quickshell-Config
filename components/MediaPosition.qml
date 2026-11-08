import QtQuick
import Quickshell.Services.Mpris
import "../services"

// ── MediaPosition ─────────────────────────────────────────────────────────────
// Which player is playing, and where in the track it is. Non-visual on purpose — like
// ArmLatch, what repeated between the surfaces was the state machine, not the look.
//
// Three surfaces need this answer: the overlay's media card, the lyrics card, and now the
// desktop widgets. Each computing it separately is how the progress bar and the lyrics end
// up disagreeing about where the song is, which is the exact failure the media card's own
// header warns about.
//
// ── The clock is an ANCHOR plus elapsed wall time ─────────────────────────────
// Never an accumulator. `pos += interval` on a timer loses every millisecond the timer
// fires late, and Qt timers guarantee only "not before" — so the playhead ran slow and the
// authoritative re-read snapped it forward, a sawtooth forever. Deriving it fresh from
// (anchor + real elapsed) cannot accumulate error because nothing is summed.
//
// ── Spotify's own playhead when it is available ───────────────────────────────
// SpotifyBridge reports the number Spotify draws its own progress bar from, which is far
// finer than MPRIS's. It is used as the ANCHOR when live; everything else is unchanged.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    visible: false
    width: 0
    height: 0

    // Gate the per-frame work. A surface nobody is looking at has no business
    // interpolating a playhead sixty times a second — the bar's MediaController shipped
    // that bug once already.
    property bool active: false

    // ── Stubborn while a caller is dragging its own seek bar ──────────────────
    // OverviewNowPlaying kept a private copy of this exact guard (`!seekBar.scrubbing`)
    // because nothing else here dragged a slider yet. MediaPanel is the second
    // consumer that does, so it belongs on the shared clock instead of a second
    // hand-rolled copy: a caller sets this true for as long as its own slider is
    // pressed, and every write to `pos` below holds still until it's false again —
    // otherwise the 500ms re-read or a mid-frame MPRIS `positionChanged` echo
    // fights the drag and the handle visibly snaps back.
    property bool scrubbing: false

    // Pin to one player's `identity` ("Spotify", "Zen Browser"), or "" to follow whatever
    // is playing.
    property string pin: ""

    readonly property var allPlayers: Mpris.players.values

    property var _player: null
    readonly property var player: root._player

    readonly property bool playing:
        root.player?.playbackState === MprisPlaybackState.Playing

    property real pos:    0
    property real length: 1

    readonly property bool live: root.active && root.player !== null

    // ── Player selection is STICKY ────────────────────────────────────────────
    // Hold the last player seen; only switch to a DIFFERENT one that is actually playing.
    // Binding to players[0] means a dead browser tab steals the surface the moment you
    // pause Spotify.
    function _refresh() {
        const all = root.allPlayers

        if (root.pin !== "") {
            for (let p = 0; p < all.length; p++)
                if (all[p].identity === root.pin) { root._player = all[p]; return }
        }

        for (let i = 0; i < all.length; i++) {
            if (all[i].playbackState === MprisPlaybackState.Playing) {
                root._player = all[i]
                return
            }
        }
        for (let j = 0; j < all.length; j++)
            if (all[j] === root._player) return

        root._player = all.length > 0 ? all[0] : null
    }

    Component.onCompleted: root._refresh()

    Connections {
        target: Mpris.players
        function onValuesChanged() { root._refresh() }
    }

    Instantiator {
        model: Mpris.players
        delegate: Connections {
            required property var modelData
            target: modelData
            function onPlaybackStateChanged() { root._refresh() }
        }
    }

    // ── The anchor ────────────────────────────────────────────────────────────
    property real _anchorPos: 0
    property real _anchorMs:  0

    function _anchor(p) {
        root._anchorPos = Math.max(0, p)
        root._anchorMs  = Date.now()
        root.pos        = root._anchorPos
    }

    readonly property real _seekEps:  0.25
    readonly property real _pullRate: 0.12

    // Is Spotify's own playhead available for this player?
    readonly property bool bridged:
        (root.player?.desktopEntry ?? "") === "spotify" && SpotifyBridge.available

    function sync() {
        if (!root.player) { root.length = 1; root._anchor(0); return }
        root.length = root.player.length > 0 ? root.player.length : 1

        // The bridge is already an anchor plus elapsed time. No drift filter on this
        // branch: both sides read the same monotonic clock, so there is no jitter to
        // smooth and filtering would only add lag.
        if (root.bridged) {
            if (SpotifyBridge.duration > 0) root.length = SpotifyBridge.duration
            root._anchor(SpotifyBridge.position())
            return
        }

        const reported = root.player.position ?? 0
        if (!root.playing) { root._anchor(reported); return }

        const expected = root._anchorPos + (Date.now() - root._anchorMs) / 1000
        const drift    = reported - expected

        if (Math.abs(drift) > root._seekEps) {
            root._anchor(reported)          // a real seek — jumping IS the truth
        } else {
            // Do NOT snap: MPRIS positions are coarse and jitter either side of the
            // truth, so snapping to each read reintroduces the stutter the anchor
            // removed. A one-pole pull converges in about a second, invisibly.
            root._anchorPos += drift * root._pullRate
        }
    }

    onPlayerChanged:  root.sync()
    onPlayingChanged: root.sync()

    // Authoritative re-read. Still 500ms, but it is a CORRECTION now, not the update rate.
    Timer {
        interval: 500
        running:  root.live
        repeat:   true
        onTriggered: if (!root.scrubbing) root.sync()
    }

    // A track change resets the playhead. Waiting for the poll let up to half a second of
    // the previous track's tail bleed into the start of the new one.
    Connections {
        target: root.player
        ignoreUnknownSignals: true
        function onTrackChanged()    { root._anchor(root.player?.position ?? 0) }
        function onPositionChanged() { if (!root.scrubbing) root.sync() }
    }

    // Per frame, not every 32ms: a timer beats against the compositor's refresh, so steps
    // land unevenly however exact the arithmetic. FrameAnimation runs in step with the
    // render loop, which is what the lyrics card's word highlight wants.
    FrameAnimation {
        running: root.live && root.playing && !root.scrubbing
        onTriggered: root.pos = Math.min(
            root._anchorPos + (Date.now() - root._anchorMs) / 1000,
            root.length)
    }
}
