import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/clockfmt.js" as ClockFmt

// ── MediaController ───────────────────────────────────────────────────────────
// Scrolling title, transport buttons, and a seekable progress strip. Lives
// inside VisualizerPill, revealed on right-click.
//
// Extracted from AudioVisualizer, where it was tangled up with the spectrum in
// one 526-line file.
//
// Its position timers used to run whenever a player existed — including while
// the controller was hidden, which was almost always. That meant a **32ms timer
// (≈31 wakeups a second) ticking permanently**, twice over, to interpolate a
// progress bar nobody could see. They are now gated on `shown`, so the
// controller costs nothing until you open it.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool shown: false

    // Prev / next. `usable`, not `enabled` — Item already has an `enabled`, and
    // redeclaring it would shadow the one QML uses to gate input.
    component TransportButton: Item {
        property url   icon: ""
        property bool  usable: true
        signal activated()

        // Scales with the icon it holds. Fixed at 20 it clipped the moment the icon
        // scale went past ~1.3, because a 15px icon at 1.4× is 21px in a 20px box.
        width:  Math.round(20 * Config.barIconScale)
        height: Math.round(20 * Config.barIconScale)
        opacity: usable ? 1.0 : 0.30
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }

        TintedIcon {
            anchors.centerIn: parent
            source: parent.icon
            size:   Math.round(14 * Config.barIconScale)
            color:  Colors.of(QsWindow.window).fg
        }

        MouseArea {
            anchors.fill: parent
            enabled: parent.usable
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.activated()
        }
    }

    // What the pill should widen to when this is revealed.
    //
    // The overhead was written down as `4 + 8 + 60 + 72 + 8` — the timestamps and the
    // transport buttons, measured once by hand and pasted in. Both scale with the Icon
    // and Text sliders now, so a constant is a guess that's correct at exactly one scale.
    // Asking the items how wide they are can't drift: no binding loop either, since these
    // are natural content widths and don't depend on the width being computed.
    readonly property int preferredWidth: {
        const overhead = Tokens.spacingMd * 2       // topRow's margins
                       + times.implicitWidth
                       + transport.implicitWidth
                       + Tokens.spacingSm * 2       // the seams around the title
        // The clamps ride the icon scale too — a 1.4× bar that still refused to go past
        // 210px would just clip the thing it had been asked to enlarge.
        return Math.min(Math.round(210 * Config.barIconScale),
                        Math.max(Math.round(170 * Config.barIconScale),
                                 (title.implicitWidth || 0) + overhead))
    }

    opacity: shown ? 1.0 : 0.0
    visible: opacity > 0.005
    Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

    // ── Player selection ──────────────────────────────────────────────────────
    // Sticky: we hold on to the last player we saw and only switch away when a
    // *different* one starts playing. Without this, pausing would drop us back
    // to players[0] — so pausing Spotify while Firefox had a dead tab open would
    // swap the display to Firefox.
    property var _player: null
    readonly property var player: _player

    // Discord shows up here too — it registers an MPRIS player of its own (a
    // soundboard hit, an embedded video link) and, being Electron, is happy to report
    // `Playing` for it. That's not "now playing" in the sense this pill means: a call
    // notification stealing the sticky slot from actual music is worse than showing
    // nothing. Filtered with the SAME prefix list Discord.qml uses to find its own
    // window (`discord-rpc.json`'s windowClasses) rather than a literal "discord" here
    // — one list, one place it can go stale, and it already covers every client
    // (Vesktop, WebCord, …) plus the canary/ptb suffix via prefix match.
    function _isDiscord(p) {
        const c = ((p && p.desktopEntry) || "").toLowerCase()
        return Discord.windowClasses.some(prefix => c.startsWith(prefix))
    }

    function _refreshPlayer() {
        const all = Mpris.players.values

        for (let i = 0; i < all.length; i++) {
            if (all[i].playbackState === MprisPlaybackState.Playing && !_isDiscord(all[i])) {
                _player = all[i]
                return
            }
        }
        // Nothing playing — keep the current one if it still exists.
        for (let j = 0; j < all.length; j++) {
            if (all[j] === _player) return
        }
        // It's gone (app closed). Null it so the timers stop and we never touch
        // a dead D-Bus object.
        _player = null
    }

    // ── The title swaps through a fade on a new track ─────────────────────────
    // `shownText` is the held copy `title` draws (see SwapFade). The marquee restarts at
    // the swap's midpoint, not when the track changes: resetting it then would snap the
    // OLD title back to the start while it is still fading out.
    readonly property string trackText: {
        const artist = root.player?.trackArtist ?? ""
        const name   = root.player?.trackTitle  ?? "No player"
        return artist.length > 0 ? artist + " - " + name : name
    }
    property string shownText: ""

    Component.onCompleted: { _refreshPlayer(); root.shownText = root.trackText }

    SwapFade {
        target:   title
        key:      root.trackText
        shownKey: root.shownText
        onSwapped: { root.shownText = root.trackText; root.resetMarquee() }
    }

    Connections {
        target: Mpris.players
        function onValuesChanged() { root._refreshPlayer() }
    }

    // A re-pick once start-up has settled. The model announces players as they become
    // ready and each one's state change has its own handler below, so this should never
    // find anything — but a player already playing when the shell (re)loads that is
    // missed by those leaves the pill on "No player" until the next play/pause. Not
    // reproduced; a no-op when the pick is already right.
    Timer { interval: 2500; running: true; onTriggered: root._refreshPlayer() }

    Instantiator {
        model: Mpris.players
        delegate: Connections {
            required property var modelData
            target: modelData
            function onPlaybackStateChanged() { root._refreshPlayer() }
        }
    }

    readonly property bool playing: player?.playbackState === MprisPlaybackState.Playing

    // ── Position ──────────────────────────────────────────────────────────────
    property real pos:    0
    property real length: 1

    function sync() {
        if (!player) { pos = 0; length = 1; return }
        pos    = player.position ?? 0
        length = player.length > 0 ? player.length : 1
    }

    // Authoritative re-read. Only while visible.
    Timer {
        interval: 500
        running:  root.shown && root.player !== null
        repeat:   true
        onTriggered: root.sync()
    }

    // Smooth interpolation between authoritative reads, so the bar creeps
    // instead of stepping twice a second. Only while visible AND playing. 4Hz is plenty
    // for a bar that is a few hundred pixels wide; 32ms was 30 repaints a second for nothing.
    Timer {
        interval: 250
        running:  root.shown && root.playing
        repeat:   true
        onTriggered: root.pos = Math.min(root.pos + 0.25, root.length)
    }

    onShownChanged: if (shown) { sync(); resetMarquee() }

    Connections {
        target: root.player ?? null
        function onTrackTitleChanged()    { root.sync() }
        function onTrackChanged()         { root.sync() }
        function onPlaybackStateChanged() { root.sync() }
        function onLengthChanged()        { root.sync() }
        function onPositionChanged()      { root.sync() }
    }
    onPlayerChanged: { sync(); resetMarquee() }

    function resetMarquee() {
        marquee.stop()
        title.x = 0
        marquee.restart()
    }


    // ── Top row: title · timestamps · transport ───────────────────────────────
    Item {
        id: topRow
        anchors.left:        parent.left
        anchors.right:       parent.right
        anchors.top:         parent.top
        anchors.bottom:      progress.top
        anchors.leftMargin:  Tokens.spacingMd
        anchors.rightMargin: Tokens.spacingMd

        Row {
            id: transport
            anchors.right:          parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.spacingSm

            TransportButton {
                icon:   Icons.fluent("previous")
                usable: root.player?.canGoPrevious ?? false
                onActivated: root.player?.previous()
            }

            Item {
                // Sibling of the TransportButtons, so it scales with them — otherwise
                // prev/next grow and play/pause stays put.
                width:  Math.round(20 * Config.barIconScale)
                height: Math.round(20 * Config.barIconScale)

                Image {
                    anchors.centerIn: parent
                    source: root.playing
                        ? Icons.asset("pause")
                        : Icons.asset("play")
                    sourceSize: Qt.size(Math.round(14 * Config.barIconScale),
                                        Math.round(14 * Config.barIconScale))
                    width:  Math.round(14 * Config.barIconScale)
                    height: Math.round(14 * Config.barIconScale)
                    fillMode: Image.PreserveAspectFit
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!root.player) return
                        if (root.playing) root.player.pause()
                        else              root.player.play()
                    }
                }
            }

            TransportButton {
                icon:   Icons.fluent("next")
                usable: root.player?.canGoNext ?? false
                onActivated: root.player?.next()
            }
        }

        Row {
            id: times
            anchors.right:          transport.left
            anchors.rightMargin:    5
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            // Timestamps are read, so they follow the font scale — unlike the transport
            // glyphs above them.
            StyledText { text: ClockFmt.clock(root.pos);    emphasis: "dim"; variant: "micro"
                         sizeScale: Config.barFontScale; font.bold: true }
            StyledText { text: " / ";                 emphasis: "dim"; variant: "micro"
                         sizeScale: Config.barFontScale; font.bold: true }
            StyledText { text: ClockFmt.clock(root.length); emphasis: "dim"; variant: "micro"
                         sizeScale: Config.barFontScale; font.bold: true }
        }

        Item {
            id: titleClip
            anchors.left:        parent.left
            anchors.right:       times.left
            anchors.top:         parent.top
            anchors.bottom:      parent.bottom
            anchors.leftMargin:  Tokens.spacingSm
            anchors.rightMargin: Tokens.spacingSm
            clip: true

            StyledText {
                id: title
                anchors.verticalCenter: parent.verticalCenter
                variant:   "caption"
                sizeScale: Config.barFontScale
                font.bold: true
                text: root.shownText
            }

            NumberAnimation {
                id: marquee
                target:   title
                property: "x"
                from:     0
                to:       -(title.implicitWidth + 32)
                duration: Math.max(9000, title.implicitWidth * 65)
                loops:    Animation.Infinite
                running:  root.shown && title.implicitWidth > titleClip.width
                onStopped: title.x = 0
            }
        }
    }

    // ── Progress strip ────────────────────────────────────────────────────────
    Rectangle {
        id: progress
        anchors.left:         parent.left
        anchors.right:        parent.right
        anchors.bottom:       parent.bottom
        anchors.leftMargin:   Tokens.spacingMd
        anchors.rightMargin:  Tokens.spacingMd
        anchors.bottomMargin: 3
        height: 2
        radius: 1
        color:  Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.25)

        Rectangle {
            id: elapsed
            anchors.left:   parent.left
            anchors.top:    parent.top
            anchors.bottom: parent.bottom
            radius: parent.radius
            color:  Colors.of(QsWindow.window).focus
            width:  root.length > 0
                ? progress.width * Math.max(0, Math.min(1, root.pos / root.length))
                : 0
            // Linear, and matched to the authoritative re-read interval, so the
            // bar advances at a constant rate instead of easing between samples.
            //
            // Category 1, live tracking (see Motion.qml): this is smoothing over
            // incoming samples, not something moving on its own, so it is exempt
            // from motionScale AND from the animations toggle — exactly as `track`
            // is. It is a literal rather than `Motion.track` only because the number
            // that matters is the SAMPLING interval, not a UI tempo.
            Behavior on width { NumberAnimation { duration: Motion.spatialSlow; easing.type: Easing.Linear } }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width:  7
            height: 7
            radius: 3.5
            color:  Colors.of(QsWindow.window).focus
            x: Math.max(0, Math.min(progress.width - width, elapsed.width - width / 2))
            opacity: seek.containsMouse || seek.pressed ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
        }

        MouseArea {
            id: seek
            anchors.fill: parent
            // A 2px-tall strip is not a clickable target; widen the hit area
            // well beyond the visible line.
            anchors.topMargin:    -10
            anchors.bottomMargin: -10
            hoverEnabled: true
            cursorShape:  Qt.PointingHandCursor
            enabled: (root.player?.canSeek ?? false) && root.shown

            function seekTo(mx) {
                if (!root.player || root.player.length <= 0) return
                const ratio = Math.max(0, Math.min(1, mx / progress.width))
                const target = ratio * root.player.length
                root.player.position = target
                root.pos = target
            }
            onClicked:         function(m) { seekTo(m.x) }
            onPositionChanged: function(m) { if (pressed) seekTo(m.x) }
        }
    }
}
