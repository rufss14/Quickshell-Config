import QtQuick
import Quickshell.Services.Mpris
import "../../../config"
import "../../../components"
import "../../../services"

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
        property alias glyph: label.text
        property bool  usable: true
        signal activated()

        // Scales with the glyph it holds. Fixed at 20 it clipped the moment the icon
        // scale went past ~1.3, because a 15px glyph at 1.4× is 21px in a 20px box.
        width:  Math.round(20 * Config.barIconScale)
        height: Math.round(20 * Config.barIconScale)
        opacity: usable ? 1.0 : 0.30
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }

        // `glyph` is aliased to this, so despite the id it holds a Nerd Font ICON, not
        // text — it follows barIconScale. It also declared `variant: "label"` and then
        // overrode the size to 14, so the variant was decoration: the type scale had no
        // say here at all.
        StyledText {
            id: label
            anchors.centerIn: parent
            variant:   "title"
            sizeScale: Config.barIconScale
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

    function _refreshPlayer() {
        const all = Mpris.players.values

        for (let i = 0; i < all.length; i++) {
            if (all[i].playbackState === MprisPlaybackState.Playing) {
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

    Component.onCompleted: _refreshPlayer()

    Connections {
        target: Mpris.players
        function onValuesChanged() { root._refreshPlayer() }
    }

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
    // instead of stepping twice a second. Only while visible AND playing.
    Timer {
        interval: 32
        running:  root.shown && root.playing
        repeat:   true
        onTriggered: root.pos = Math.min(root.pos + 0.032, root.length)
    }

    onShownChanged: if (shown) { sync(); resetMarquee() }

    Connections {
        target: root.player ?? null
        function onTrackTitleChanged()    { root.sync(); root.resetMarquee() }
        function onTrackChanged()         { root.sync(); root.resetMarquee() }
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

    function fmt(secs) {
        if (!secs || secs <= 0) return "0:00"
        const m = Math.floor(secs / 60)
        const s = Math.floor(secs % 60)
        return m + ":" + (s < 10 ? "0" : "") + s
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
                glyph:  "󰒮"
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
                glyph:  "󰒭"
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
            StyledText { text: root.fmt(root.pos);    emphasis: "dim"; variant: "micro"
                         sizeScale: Config.barFontScale; font.bold: true }
            StyledText { text: " / ";                 emphasis: "dim"; variant: "micro"
                         sizeScale: Config.barFontScale; font.bold: true }
            StyledText { text: root.fmt(root.length); emphasis: "dim"; variant: "micro"
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
                text: {
                    const artist = root.player?.trackArtist ?? ""
                    const name   = root.player?.trackTitle  ?? "No player"
                    return artist.length > 0 ? artist + " - " + name : name
                }
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
        color:  Colors.alpha(Colors.focus, 0.25)

        Rectangle {
            id: elapsed
            anchors.left:   parent.left
            anchors.top:    parent.top
            anchors.bottom: parent.bottom
            radius: parent.radius
            color:  Colors.focus
            width:  root.length > 0
                ? progress.width * Math.max(0, Math.min(1, root.pos / root.length))
                : 0
            // Linear, and matched to the authoritative re-read interval, so the
            // bar advances at a constant rate instead of easing between samples.
            Behavior on width { NumberAnimation { duration: 500; easing.type: Easing.Linear } }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width:  7
            height: 7
            radius: 3.5
            color:  Colors.focus
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
