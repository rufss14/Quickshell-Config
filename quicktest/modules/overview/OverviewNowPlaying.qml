import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Services.Mpris
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── OverviewNowPlaying ────────────────────────────────────────────────────────
// The media card at the top of the overlay: art, track, a seekable progress bar,
// full transport, and a player switcher.
//
// ── The album art is the design ───────────────────────────────────────────────
// The card is backed by the artwork itself — blurred, darkened, and masked to the
// card's corners. That single decision is what stops it reading as a grey box with
// text in it.
//
// It also solves a problem this palette has: the wallpaper is monochrome, so every
// accent in the shell is a shade of grey. The album art is the one place real colour
// enters the overlay, and letting it wash the card means the media surface is alive
// even when nothing else can be. It re-tints itself with every track, for free.
//
// ── Player selection is STICKY ────────────────────────────────────────────────
// It holds the last player it saw and only switches away when a *different* one
// starts playing. Without that, pausing Spotify would drop the display back to
// players[0], so a dead browser tab could steal the card the moment you hit pause.
// (The bar's MediaController learned this the hard way; same rule, same reason.)
//
// It renders nothing at all when no player exists, rather than showing an empty shell.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    implicitWidth:  card.visible ? 400 : 0
    implicitHeight: card.visible ? 148 : 0

    // ── Player selection ──────────────────────────────────────────────────────
    property var _player: null
    readonly property var player: _player

    readonly property var allPlayers: Mpris.players.values

    function _refresh() {
        const all = root.allPlayers

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
        _player = all.length > 0 ? all[0] : null
    }

    // Step to the next player. Only reachable when there's more than one, so it never
    // presents a control that does nothing.
    function cyclePlayer() {
        const all = root.allPlayers
        if (all.length < 2) return
        const i = all.indexOf(root._player)
        root._player = all[(i + 1) % all.length]
    }

    Component.onCompleted: {
        _refresh()
        AlbumArt.sourceId = root.source.id
        AlbumArt.source   = root.artUrl
    }

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

    readonly property bool playing: player?.playbackState === MprisPlaybackState.Playing
    readonly property bool seekable: (player?.canSeek ?? false) && (player?.lengthSupported ?? false)

    // This card owns the album palette: it's the one that always knows the current cover,
    // and every other media surface (the lyrics) reads the singleton rather than
    // extracting a second time.
    readonly property string artUrl: player?.trackArtUrl ?? ""
    onArtUrlChanged: {
        // sourceId BEFORE source: the brand fallback the extraction may apply keys off
        // sourceId, and setting the url is what kicks the extraction off.
        AlbumArt.sourceId = root.source.id
        AlbumArt.source   = root.artUrl
    }
    onSourceChanged: AlbumArt.sourceId = root.source.id

    // ── Where is this actually coming from? ───────────────────────────────────
    // The URL first, and that ordering is the whole point. A browser playing YouTube
    // identifies itself as THE BROWSER — desktopEntry "zen", identity "Zen Browser" —
    // so app identity can only ever tell you the window, never the source. `xesam:url`
    // is the one field that knows the difference between "a browser" and "YouTube".
    //
    // (Spotify, for comparison, reports desktopEntry "spotify" AND
    // xesam:url "https://open.spotify.com/track/…" — either would do. The browser case
    // is the one that needs this.)
    readonly property var _hosts: ({
        "open.spotify.com":   { id: "spotify",       name: "Spotify"       },
        "music.youtube.com":  { id: "youtube-music", name: "YouTube Music" },
        "www.youtube.com":    { id: "youtube",       name: "YouTube"       },
        "youtube.com":        { id: "youtube",       name: "YouTube"       },
        "youtu.be":           { id: "youtube",       name: "YouTube"       },
        "soundcloud.com":     { id: "soundcloud",    name: "SoundCloud"    },
        "bandcamp.com":       { id: "bandcamp",      name: "Bandcamp"      }
    })

    readonly property var source: {
        const url = root.player?.metadata?.["xesam:url"] ?? ""

        if (url) {
            // Pull the host out without a URL parser: everything between "//" and the
            // next "/". A local file (file:///…) yields nothing and falls through, which
            // is correct — a local file's source IS the app playing it.
            const after = url.indexOf("//")
            if (after >= 0) {
                const rest = url.substring(after + 2)
                const end  = rest.indexOf("/")
                const host = (end >= 0 ? rest.substring(0, end) : rest).toLowerCase()

                if (root._hosts[host]) return root._hosts[host]

                // bandcamp serves from <artist>.bandcamp.com.
                for (const h in root._hosts)
                    if (host.endsWith("." + h)) return root._hosts[h]
            }
        }

        // Otherwise the app itself is the source.
        const entry = root.player?.desktopEntry ?? ""
        const ident = root.player?.identity ?? ""
        return { id: entry || ident, name: ident || entry }
    }

    readonly property string sourceIcon: Icons.pathForAppId(root.source.id)

    // ── Position ──────────────────────────────────────────────────────────────
    // Two timers, both gated on the overlay being OPEN — a progress bar nobody can see
    // has no business interpolating itself 30 times a second. (Same lesson the bar's
    // MediaController had to learn: its position timers ran permanently, including while
    // it was hidden, which was almost always.)
    property real pos:    0
    property real length: 1

    readonly property bool live: UiState.overviewOpen && root.player !== null

    function sync() {
        if (!player) { pos = 0; length = 1; return }
        pos    = player.position ?? 0
        length = player.length > 0 ? player.length : 1
    }

    onPlayerChanged: sync()

    // Authoritative re-read.
    Timer {
        interval: 500
        running:  root.live
        repeat:   true
        onTriggered: if (!seekBar.scrubbing) root.sync()
    }

    // Smooth interpolation between reads, so the bar creeps instead of stepping.
    Timer {
        interval: 32
        running:  root.live && root.playing && !seekBar.scrubbing
        repeat:   true
        onTriggered: root.pos = Math.min(root.pos + 0.032, root.length)
    }

    function timeStr(sec) {
        if (!isFinite(sec) || sec < 0) sec = 0
        const m = Math.floor(sec / 60)
        const s = Math.floor(sec % 60)
        return m + ":" + (s < 10 ? "0" + s : s)
    }

    // ══════════════════════════════════════════════════════════════════════════
    Surface {
        id: card
        anchors.fill: parent
        elevation: Tokens.elevationPopup
        visible: root.player !== null
        clip: true

        // The card's fill is the cover's own shadow, not the shell's surface colour.
        color: AlbumArt.bg
        Behavior on color { ColorAnimation { duration: Motion.spatial } }

        // A clearly visible, album-tinted edge — matching the lyrics card and the 2px
        // accent borders already used on the art thumbnail and transport controls inside.
        // The default surface outline washes out against arbitrary cover colours.
        border.width: 2
        border.color: Colors.alpha(AlbumArt.accent, 0.60)
        Behavior on border.color { ColorAnimation { duration: Motion.spatial } }

        // ── Art wash ──────────────────────────────────────────────────────────
        // The artwork, blown up and blurred behind everything. Masked to the card's
        // radius — a blurred image has no corners of its own, and without the mask it
        // would square off the card it's sitting in.
        //
        // ── No grey ───────────────────────────────────────────────────────────
        // This used to be dimmed hard (brightness -0.35, saturation 0.25) and then buried
        // under a `Colors.surface` scrim at 0.82 alpha. On this palette `base` is
        // #000000, so that scrim was a near-opaque neutral sheet: it flattened the album
        // art into the same grey as everything else, which defeated the entire point of
        // putting the art there.
        //
        // The art now comes through — saturation LIFTED, not crushed — and the only thing
        // over it is a gradient of the album's OWN dark tone, which is what keeps the text
        // legible without introducing a colour the cover doesn't have.
        Item {
            anchors.fill: parent
            visible: artSource.status === Image.Ready

            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: cardMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            Image {
                id: artSource
                anchors.fill: parent
                source: root.player?.trackArtUrl ?? ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                visible: false
            }

            MultiEffect {
                anchors.fill: parent
                source: artSource
                blurEnabled: true
                blur: 1.0
                blurMax: 48
                autoPaddingEnabled: false
                brightness: -0.12
                saturation: 1.25
                opacity: 0.85
            }

            // Legibility, in the album's own colour. Heaviest on the left, where the text
            // sits; the right side is left open so the cover actually shows.
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Colors.alpha(AlbumArt.bg, 0.80) }
                    GradientStop { position: 0.6; color: Colors.alpha(AlbumArt.bg, 0.45) }
                    GradientStop { position: 1.0; color: Colors.alpha(AlbumArt.bg, 0.15) }
                }
            }
        }

        Item {
            id: cardMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            Rectangle {
                anchors.fill: parent
                radius: card.radius
                color: "white"
            }
        }

        // ── Source badge ──────────────────────────────────────────────────────
        // Top-right, above the content. Says where the audio is coming FROM — Spotify,
        // YouTube, SoundCloud — which for anything played in a browser is not the same
        // question as "which app is this".
        Item {
            id: sourceBadge

            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Tokens.spacingMd
            width:  20
            height: 20
            z: 10

            Image {
                anchors.fill: parent
                visible: root.sourceIcon !== ""
                source: root.sourceIcon
                sourceSize: Qt.size(20, 20)
                fillMode: Image.PreserveAspectFit
                smooth: true
                opacity: 0.9
            }

            // A glyph when the icon theme has nothing — never hand an Image an empty
            // url, which becomes the qs-blackhole placeholder and warns.
            StyledText {
                anchors.centerIn: parent
                visible: root.sourceIcon === ""
                text: "󰎈"
                color: Colors.fgMuted
                font.pixelSize: 15
            }

            HoverHandler { id: sourceHover }

            Rectangle {
                visible: sourceHover.hovered && root.source.name !== ""
                anchors.top: parent.bottom
                anchors.right: parent.right
                anchors.topMargin: Tokens.spacingXs

                width:  sourceName.implicitWidth + Tokens.spacingMd
                height: 20
                radius: Tokens.radiusXs
                color: Colors.surfaceHigh
                border.width: Tokens.borderWidth
                border.color: Colors.outlineNested

                StyledText {
                    id: sourceName
                    anchors.centerIn: parent
                    text: root.source.name
                    variant: "caption"
                }
            }
        }

        // ── Content ───────────────────────────────────────────────────────────
        RowLayout {
            anchors.fill: parent
            anchors.margins: Tokens.spacingLg
            anchors.rightMargin: Tokens.spacingLg + sourceBadge.width
            spacing: Tokens.spacingLg

            // ── Cover ─────────────────────────────────────────────────────────
            // The image is MASKED to the rounded rect, not clipped to it.
            //
            // This was `Rectangle { radius; clip: true }` with the Image inside, which
            // does not work: `clip` is RECTANGULAR. It clips to the bounding box and knows
            // nothing about `radius`, so the artwork kept its square corners and stuck out
            // past the rounded ones.
            //
            // Third time this exact bug has turned up — window previews poking out of the
            // workspace cells, lyrics showing through the card's corners, and now this.
            // The fix is the same one every time: a mask, not a clip.
            Rectangle {
                id: cover
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth:  96
                Layout.preferredHeight: 96
                radius: Tokens.radiusSm
                color:  Colors.alpha(AlbumArt.accent, 0.18)

                StyledText {
                    anchors.centerIn: parent
                    visible: art.status !== Image.Ready
                    text: "󰝚"
                    color: AlbumArt.accent
                    font.pixelSize: 34
                }

                Item {
                    anchors.fill: parent

                    layer.enabled: true
                    layer.smooth: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: coverMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }

                    Image {
                        id: art
                        anchors.fill: parent

                        // The 1400px original rather than the 640px one MPRIS reports.
                        source: AlbumArt.hiRes(root.player?.trackArtUrl ?? "")

                        // Without an explicit sourceSize Qt decodes at native resolution
                        // and then point-samples the downscale — which is most of why this
                        // looked soft. Decoding straight to 2× the drawn size (for HiDPI)
                        // and mipmapping the rest gives a clean, sharp thumbnail.
                        sourceSize: Qt.size(cover.width * 2, cover.height * 2)
                        mipmap: true

                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        asynchronous: true
                        cache: true
                        visible: status === Image.Ready
                    }
                }

                Item {
                    id: coverMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    Rectangle {
                        anchors.fill: parent
                        radius: cover.radius
                        color: "white"
                    }
                }

                // A quiet pulse on the cover while playing — the one ambient cue that
                // says "this is live" without a spinner.
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: 2
                    border.color: AlbumArt.accent
                    opacity: 0

                    SequentialAnimation on opacity {
                        running: root.playing
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.55; duration: Motion.slow; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 0.00; duration: Motion.slow; easing.type: Easing.InOutSine }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: Tokens.spacingXs

                // ── Title row, with the player switcher ───────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingSm

                    StyledText {
                        Layout.fillWidth: true
                        text: root.player?.trackTitle ?? ""
                        variant: "title"
                        font.bold: true
                        color: AlbumArt.fg
                        elide: Text.ElideRight
                    }

                    // Only rendered when there IS another player to switch to.
                    PanelButton {
                        visible: root.allPlayers.length > 1
                        variant: "ghost"
                        implicitWidth:  22
                        implicitHeight: 22
                        glyph: "󰓃"
                        onActivated: root.cyclePlayer()
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: {
                        const a = root.player?.trackArtist ?? ""
                        const b = root.player?.trackAlbum  ?? ""
                        return (a && b) ? a + "  ·  " + b : (a || b)
                    }
                    variant: "caption"
                    color: AlbumArt.fgMuted
                    elide: Text.ElideRight
                }

                // ── Seek bar ──────────────────────────────────────────────────
                Item {
                    id: seekBar
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacingXs
                    implicitHeight: 14

                    property bool scrubbing: false
                    readonly property real ratio:
                        root.length > 0 ? Math.max(0, Math.min(1, root.pos / root.length)) : 0

                    function seekTo(px) {
                        if (!root.seekable || !root.player) return
                        const r = Math.max(0, Math.min(1, px / seekBar.width))
                        root.pos = r * root.length
                        root.player.position = root.pos     // position is writable — this IS the seek
                    }

                    Rectangle {
                        id: track
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: seekBar.scrubbing || seekHover.hovered ? 6 : 4
                        radius: height / 2
                        color: Colors.alpha(AlbumArt.fg, 0.20)

                        Behavior on height { NumberAnimation { duration: Motion.respond } }

                        Rectangle {
                            width: parent.width * seekBar.ratio
                            height: parent.height
                            radius: parent.radius
                            color: AlbumArt.accent
                        }
                    }

                    // The grab handle only appears when the bar is actually seekable and
                    // you're pointing at it — a knob you can't drag is a lie.
                    Rectangle {
                        visible: root.seekable && (seekHover.hovered || seekBar.scrubbing)
                        x: track.width * seekBar.ratio - width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width:  12
                        height: 12
                        radius: 6
                        color: AlbumArt.accent
                        border.width: 2
                        border.color: AlbumArt.bg
                    }

                    HoverHandler { id: seekHover }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4          // a 4px bar is a small target; widen it
                        enabled: root.seekable
                        cursorShape: root.seekable ? Qt.PointingHandCursor : Qt.ArrowCursor
                        preventStealing: true

                        onPressed:  function(m) { seekBar.scrubbing = true;  seekBar.seekTo(m.x) }
                        onPositionChanged: function(m) { if (seekBar.scrubbing) seekBar.seekTo(m.x) }
                        onReleased: function(m) { seekBar.seekTo(m.x); seekBar.scrubbing = false }
                        onCanceled: seekBar.scrubbing = false
                    }
                }

                // ── Times + transport ─────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingSm

                    StyledText {
                        text: root.timeStr(root.pos)
                        font.family: Tokens.fontMono
                        variant: "caption"
                        color: AlbumArt.fgDim
                    }

                    Item { Layout.fillWidth: true }

                    PanelButton {
                        visible: root.player?.shuffleSupported ?? false
                        variant: "ghost"
                        implicitWidth:  24
                        implicitHeight: 24
                        glyph: "󰒝"
                        glyphTint: (root.player?.shuffle ?? false) ? AlbumArt.accent : AlbumArt.fgDim
                        onActivated: if (root.player) root.player.shuffle = !root.player.shuffle
                    }

                    PanelButton {
                        variant: "ghost"
                        implicitWidth:  26
                        implicitHeight: 26
                        glyph: "󰒮"
                        enabled: root.player?.canGoPrevious ?? false
                        onActivated: root.player?.previous()
                    }

                    // The one filled control on the card: it's what the card is FOR.
                    PanelButton {
                        variant: "primary"
                        accent:  AlbumArt.accent
                        implicitWidth:  34
                        implicitHeight: 34
                        radius: 17
                        glyph: root.playing ? "󰏤" : "󰐊"
                        enabled: root.player?.canTogglePlaying ?? false
                        onActivated: root.player?.togglePlaying()
                    }

                    PanelButton {
                        variant: "ghost"
                        implicitWidth:  26
                        implicitHeight: 26
                        glyph: "󰒭"
                        enabled: root.player?.canGoNext ?? false
                        onActivated: root.player?.next()
                    }

                    // Loop cycles none → playlist → track, and the glyph says which.
                    PanelButton {
                        visible: root.player?.loopSupported ?? false
                        variant: "ghost"
                        implicitWidth:  24
                        implicitHeight: 24
                        glyph: root.player?.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"
                        glyphTint: (root.player?.loopState ?? MprisLoopState.None) !== MprisLoopState.None
                                 ? AlbumArt.accent : AlbumArt.fgDim
                        onActivated: {
                            if (!root.player) return
                            switch (root.player.loopState) {
                                case MprisLoopState.None:     root.player.loopState = MprisLoopState.Playlist; break
                                case MprisLoopState.Playlist: root.player.loopState = MprisLoopState.Track;    break
                                default:                      root.player.loopState = MprisLoopState.None;     break
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    StyledText {
                        text: root.player?.lengthSupported ? root.timeStr(root.length) : "--:--"
                        font.family: Tokens.fontMono
                        variant: "caption"
                        color: AlbumArt.fgDim
                    }
                }
            }
        }
    }
}
