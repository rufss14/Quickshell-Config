import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import "../../config"
import "../../state"
import "../../components"
import "../../services"
import "../../services/mediasource.js" as MediaSource
import "../../services/volumeprofiles.js" as ProfileData
import "../panels"
import "media"
import "../../services/medialinks.js" as Links

// ── IslandMedia ───────────────────────────────────────────────────────────────
// The card's second page, after Caelestia's media tab and in the media panel's dialect: the cover in its turning cookie
// with the ring of level bars on the left, the song in the middle (title, artist, the album as an accent pill, a wavy
// seek line with its times, the transport) and the lyrics on a flat card on the right, over a few soft shapes that
// breathe with the music. The colour is the visualiser's accent, never the player's brand. All the shell's own pieces
// (CookieCover, MediaSeek, MediaTransport, PanelLyrics, MediaPosition); the lyrics are asked for here, and the playhead,
// the ring and the pulse are live only while this page is on screen.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property var player: tp.player

    MediaPosition {
        id: tp
        active: root.visible
        scrubbing: seek.pressed
        // Spotify first when several play; a player chosen in the source pill is held (its identity).
        prefer: "spotify"
        pin: root.pinned
    }

    // The player the page follows: "" = automatic (Spotify first). Chosen in the source pill; not persisted.
    property string pinned: ""
    readonly property var allPlayers: Mpris.players.values
    readonly property var extraDetail: root.isSpotify && SpotifyBridge.available ? {
        trackUri: SpotifyBridge.trackUri,
        albumUri: SpotifyBridge.albumUri,
        artists: SpotifyBridge.artists
    } : null
    readonly property bool isSpotify: (root.player?.desktopEntry ?? "") === "spotify"
    // Where the title, artists, album and cover take you (medialinks.js).
    readonly property var links: Links.linksFor({
        isSpotify: root.isSpotify,
        url: root.player?.metadata ? (root.player.metadata["xesam:url"] || "") : "",
        artist: root.player?.trackArtist ?? "",
        album: root.player?.trackAlbum ?? ""
    }, root.extraDetail)
    // Spotify's Canvas, the looping clip, played in the cover's cookie in place of the cover, ring of bars and all.
    // A click on the cookie turns it on and off. The choice outlives the track (next song with a clip plays it; one without shows the cover) and is not persisted. Decoration, so it
    // follows the island's effects switch and reduced motion like the shapes. Needs the bridge's cached copy of the
    // clip and qt6-multimedia (Media).
    property bool canvasOn: false
    readonly property bool hasCanvas: root.isSpotify && Media.available && SpotifyBridge.canvasPath !== ""
                                      && Motion.ambientOn && UiState.islandEffectsOn
    readonly property bool canvasShown: root.canvasOn && root.hasCanvas
    // Where the clip sits up and down in the cookie (-1 to 1), set by dragging the cookie and remembered PER SONG
    // (Config.canvasPans, by track uri); a song never dragged is centred.
    property real canvasPan: 0
    function _savedPan() { return Config.canvasPans[SpotifyBridge.trackUri] ?? 0 }
    // Saved on release, never during the drag: the preferences document is rewritten on every change. Newest last, capped.
    function _savePan() {
        const k = SpotifyBridge.trackUri
        if (k === "") return
        const m = Object.assign({}, Config.canvasPans)
        delete m[k]
        if (Math.abs(root.canvasPan) >= 0.02) m[k] = Math.round(root.canvasPan * 1000) / 1000
        const keys = Object.keys(m)
        for (const d of keys.slice(0, Math.max(0, keys.length - 300))) delete m[d]
        Config.canvasPans = m
    }
    Connections {
        target: SpotifyBridge
        function onTrackUriChanged() { root.canvasPan = root._savedPan() }
        function onCanvasPathChanged() { root.canvasPan = root._savedPan() }
    }
    Connections {
        target: Config
        function onCanvasPansChanged() { root.canvasPan = root._savedPan() }
    }
    // The right plate: lyrics, or the queue (Spotify only).
    property string side: "lyrics"

    // The visualiser's accent (Settings › Bar › Visualizer), never the player's brand colour.
    readonly property color accent: Config.moduleAccent("visualizer", root.palette.primary)
    // Does this player say where in the track it is? A browser often doesn't: no bar beats a wrong one.
    readonly property bool hasTiming: tp.bridged
        || ((root.player?.lengthSupported ?? false) && (root.player?.length ?? 0) > 0)
    // Lyrics are keyed on the track and trusted only for sources that name artist and title.
    readonly property bool showLyrics: MediaSource.lyricsTrusted(root.player)
    // The player's own PipeWire node, so the ring answers THIS player and not whatever shares the speakers.
    readonly property string nodeName: {
        const appId = root.player?.desktopEntry ?? ""
        if (!root.visible || !appId) return ""
        const nodes = Audio.streamsFor(appId)
        return nodes.length > 0 ? nodes[0].name : ""
    }

    // The lyrics service is asked per track, by whoever shows them.
    // ── The extras, kept quiet ────────────────────────────────────────────────
    // One row of small chips under the volume: name this song (SongRec), translate the lyrics,
    // Latin letters under another script, sing along (Karaoke). The speaker beside the volume opens
    // its named levels. What they
    // are doing is one line under the artist, only while there is something to say.
    readonly property string appId: root.player?.desktopEntry ?? ""
    property bool profilesOpen: false
    property bool boostUnlocked: false
    readonly property bool hasVolume: Audio.hasPlayerVolume(root.player, root.appId)
    readonly property real level: Audio.playerLevel(root.player, root.appId)
    readonly property string status: {
        if (SongRec.listening) return SongRec.usingMic ? Translation.tr("Listening to the microphone…")
                                                       : Translation.tr("Listening to the desktop…")
        if (SongRec.phase === "found")
            return Translation.tr("Found: %1").arg(SongRec.track.title + (SongRec.track.artist !== "" ? " — " + SongRec.track.artist : ""))
        if (SongRec.phase === "missed") return Translation.tr("Couldn't recognise it")
        if (Karaoke.headline !== "") return Karaoke.headline
        if (Config.lyricsRomanize && LyricsRomanize.romanizable && LyricsRomanize.failed)
            return Translation.tr("Romanization: %1").arg(LyricsRomanize.status)
        if (Config.lyricsTranslate && root.showLyrics) {
            if (LyricsTranslate.state === "probing" || LyricsTranslate.state === "loading") return Translation.tr("Translating…")
            if (LyricsTranslate.state === "error") return Translation.tr("Translation failed: %1").arg(LyricsTranslate.lastError)
        }
        return ""
    }

    readonly property string trackKey: (root.player?.trackArtist ?? "") + "\u0001" + (root.player?.trackTitle ?? "")
    onTrackKeyChanged: if (root.player && root.showLyrics) Lyrics.loadFor(root.player)
    Component.onCompleted: {
        root.canvasPan = root._savedPan()
        if (root.player && root.showLyrics) Lyrics.loadFor(root.player)
    }

    // The shapes breathe with the music while it plays (MusicPulse listens only while music plays and this is on screen).
    property bool _pulse: false
    readonly property bool wantPulse: root.visible && root.player !== null && Motion.ambientOn && UiState.islandEffectsOn
    onWantPulseChanged: {
        if (root.wantPulse && !root._pulse) { MusicPulse.acquire(); root._pulse = true }
        else if (!root.wantPulse && root._pulse) { MusicPulse.release(); root._pulse = false }
    }
    Component.onDestruction: if (root._pulse) MusicPulse.release()

    // ── Soft shapes behind it all ─────────────────────────────────────────────
    // Off with the island's effects (UiState.islandEffectsOn).
    Repeater {
        model: UiState.islandEffectsOn ? [
            { x: 0.01, y: 0.04, s: 0.30, shape: "cookie9"  },
            { x: 0.40, y: 0.66, s: 0.20, shape: "squircle" },
            { x: 0.50, y: 0.00, s: 0.18, shape: "clover"   },
            { x: 0.66, y: 0.56, s: 0.34, shape: "cookie9"  }
        ] : []
        delegate: MorphShape {
            required property var modelData
            x: root.width * modelData.x
            y: root.height * modelData.y
            width: root.height * modelData.s
            height: width
            shape: modelData.shape
            turns: false
            fillColor: root.palette.alpha(root.accent, 0.07 + 0.07 * (root._pulse ? MusicPulse.level : 0))
            scale: 1 + (root._pulse ? 0.22 * MusicPulse.bass : 0)
            NumberAnimation on rotation {
                from: 0
                to: 360
                duration: 120000
                loops: Animation.Infinite
                running: Motion.ambientOn && root.visible
            }
        }
    }

    // ── Nothing playing ───────────────────────────────────────────────────────
    IslandPiece {
        anchors.centerIn: parent
        width: emptyCol.implicitWidth
        height: emptyCol.implicitHeight
        visible: root.player === null
        order: 0
        ColumnLayout {
            id: emptyCol
            anchors.fill: parent
            spacing: Tokens.spacingMd
            IslandBadge {
                Layout.alignment: Qt.AlignHCenter
                size: Tokens.iconXl * 3
                shape: "cookie9"
                symbol: "music_note"
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("Nothing playing")
                variant: "title"
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Translation.tr("Start a song and it lands here")
                variant: "caption"
                emphasis: "dim"
            }
        }
    }

    // ── A song ────────────────────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        visible: root.player !== null
        spacing: Tokens.spacingLg

        IslandPiece {
            Layout.preferredWidth: Math.min(root.height, Tokens.spacingXl * 16)
            Layout.preferredHeight: Layout.preferredWidth
            Layout.alignment: Qt.AlignVCenter
            order: 0
            CookieCover {
                id: coverCookie
                anchors.fill: parent
                panY: root.canvasPan
                source: AlbumArt.hiRes(root.player?.trackArtUrl ?? "")
                canvas: root.canvasShown ? SpotifyBridge.canvasPath : ""
                grown: root.canvasShown
                playing: tp.playing
                live: root.visible && root.player !== null
                nodeName: root.nodeName
                accent: root.accent
            }
            // This song has a Canvas: a small video mark in the slot's empty bottom-right corner (the ring is round, so
            // the corner is free). Lit while the clip plays. The cookie's own click toggles it, so this only says so.
            Rectangle {
                readonly property bool lit: root.canvasShown
                visible: scale > 0.01
                scale: root.isSpotify && Media.available && SpotifyBridge.canvasPath !== "" ? 1 : 0
                Behavior on scale { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                transformOrigin: Item.BottomRight
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: Tokens.iconXl + Tokens.spacingSm * 2
                height: width
                radius: height / 2
                color: lit ? root.palette.primary : root.palette.primaryContainer
                Behavior on color { ColorAnimation { duration: Motion.respond } }
                MaterialIcon {
                    anchors.centerIn: parent
                    name: "videocam"
                    fill: 1
                    font.pixelSize: Tokens.iconMd
                    color: parent.lit ? root.palette.fgOnPrimary : root.palette.fgOnPrimaryContainer
                }
            }
            // A track with a Canvas: the cookie turns it on and off (the album pill still opens the album). Without one
            // it opens the album (or the page of the track) when there is one, as it always did.
            MouseArea {
                id: coverArea
                anchors.fill: parent
                enabled: root.hasCanvas || Links.openCommand(root.links.cover).length > 0
                cursorShape: coverArea.dragged ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                // Holding and dragging up or down moves the clip in the cookie (only while it plays); a press that moves
                // less than a few pixels is still a click.
                property real _y0: 0
                property real _pan0: 0
                property bool dragged: false
                onPressed: function (m) {
                    coverArea._y0 = m.y
                    coverArea._pan0 = root.canvasPan
                    coverArea.dragged = false
                }
                onPositionChanged: function (m) {
                    if (!coverArea.pressed || !root.canvasShown) return
                    const dy = m.y - coverArea._y0
                    if (!coverArea.dragged && Math.abs(dy) < Tokens.spacingSm) return
                    coverArea.dragged = true
                    root.canvasPan = Math.max(-1, Math.min(1, coverArea._pan0 + dy / coverCookie.canvasSlack))
                }
                onReleased: { if (coverArea.dragged) root._savePan() }
                onClicked: {
                    if (coverArea.dragged) return
                    if (root.hasCanvas) root.canvasOn = !root.canvasOn
                    else Quickshell.execDetached(Links.openCommand(root.links.cover))
                }
                Accessible.role: root.hasCanvas ? Accessible.Button : Accessible.Link
                Accessible.name: root.hasCanvas ? (root.canvasOn ? Translation.tr("Turn the Canvas off") : Translation.tr("Play the Canvas"))
                                                : Translation.tr("Open the album")
            }
        }

        IslandPiece {
            Layout.fillWidth: true
            Layout.preferredWidth: 3
            Layout.fillHeight: true
            order: 1
            ColumnLayout {
                anchors.fill: parent
                spacing: Tokens.spacingXs

                Item { Layout.fillHeight: true }

                MediaLink {
                    Layout.fillWidth: true
                    text: root.player?.trackTitle || Translation.tr("Unknown")
                    link: root.links.title
                    font.pixelSize: Tokens.fontHeadline + Tokens.spacingSm
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                MediaArtists {
                    Layout.fillWidth: true
                    artists: root.links.artists
                    variant: "body"
                    ink: root.palette.fgMuted
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.status !== ""
                    text: root.status
                    variant: "caption"
                    color: root.accent
                    elide: Text.ElideRight
                }
                // The album as a pill in the accent container.
                Rectangle {
                    Layout.alignment: Qt.AlignLeft
                    Layout.topMargin: Tokens.spacingXs
                    visible: albumText.text !== ""
                    implicitWidth: Math.min(albumText.implicitWidth + Tokens.spacingLg * 2, parent.width)
                    implicitHeight: albumText.implicitHeight + Tokens.spacingSm * 2
                    radius: height / 2
                    color: root.palette.primaryContainer
                    MediaLink {
                        id: albumText
                        anchors.centerIn: parent
                        width: parent.width - Tokens.spacingLg * 2
                        text: root.player?.trackAlbum ?? ""
                        link: root.links.album
                        variant: "caption"
                        font.weight: Font.DemiBold
                        base: root.palette.fgOnPrimaryContainer
                        elide: Text.ElideRight
                    }
                }

                MediaSeek {
                    id: seek
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacingMd
                    visible: root.hasTiming
                    track: tp
                    accent: root.accent
                    live: root.visible && root.hasTiming
                }

                MediaTransport {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Tokens.spacingXs
                    player: tp.player
                    playing: tp.playing
                    accent: root.accent
                    size: 0.95
                }

                // The system volume, with its speaker as a badge that mutes.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.topMargin: Tokens.spacingXs
                    spacing: Tokens.spacingMd
                    // The speaker folds the bar into the named levels and back; it does not mute.
                    IslandBadge {
                        size: Tokens.iconXl
                        opacity: root.hasVolume ? 1 : 0.45
                        filled: root.profilesOpen
                        shape: root.profilesOpen ? "cookie9" : "circle"
                        symbol: root.level <= 0 ? "volume_off" : root.level < 0.35 ? "volume_mute"
                              : root.level < 0.7 ? "volume_down" : "volume_up"
                        MouseArea {
                            anchors.fill: parent
                            enabled: root.hasVolume
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.profilesOpen = !root.profilesOpen
                            Accessible.role: Accessible.Button
                            Accessible.name: Translation.tr("Volume levels")
                            Accessible.onPressAction: root.profilesOpen = !root.profilesOpen
                        }
                    }
                    // The bar and the named levels share the slot and cross-fade.
                    Item {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        implicitHeight: profiles.implicitHeight
                        // The PLAYER's own volume (its stream, not the master), as a level you see.
                        ThickSlider {
                            id: volBar
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            readonly property bool unlocked: root.boostUnlocked || root.level > 1.001
                            accessibleName: Translation.tr("Volume")
                            enabled: root.hasVolume
                            maximum: volBar.unlocked ? Math.round(Audio.boostCeiling * 100) : 100
                            value: Math.min(volBar.maximum, root.level * 100)
                            notchAt: volBar.unlocked ? 100 : -1
                            notchColor: root.palette.warning
                            accent: root.accent
                            opacity: root.profilesOpen ? 0 : 1
                            visible: opacity > 0.005
                            Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                            onMoved: function (v) { Audio.setPlayerLevel(root.player, root.appId, v / 100, volBar.unlocked) }
                        }
                        VolumeProfiles {
                            id: profiles
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            enabled: root.hasVolume
                            profiles: ProfileData.PROFILES
                            current: Audio.volumeProfileOf(root.player, root.appId)
                            accent: root.accent
                            opacity: root.profilesOpen ? 1 : 0
                            visible: opacity > 0.005
                            Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                            // Boost is a different gesture: left unlocks the bar past 100% and shows
                            // it, right unlocks it and sets the boost. Any other level locks it again.
                            onPicked: function (i) {
                                if (ProfileData.PROFILES[i].boost) {
                                    root.boostUnlocked = true
                                    root.profilesOpen = false
                                    return
                                }
                                root.boostUnlocked = false
                                Audio.applyProfile(root.player, root.appId, i)
                            }
                            onAlternated: function (i) {
                                Audio.applyProfile(root.player, root.appId, i)
                                root.boostUnlocked = !!ProfileData.PROFILES[i].boost
                                if (root.boostUnlocked) root.profilesOpen = false
                            }
                        }
                    }
                }

                ChipTray {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Tokens.spacingXs
                    // Liked Songs, as Spotify has it: a check when this song is saved, and a tap saves or unsaves it.
                    ChipButton {
                        visible: root.isSpotify && SpotifyBridge.available
                        symbol: "check"
                        on: SpotifyBridge.queue ? SpotifyBridge.queue.liked : false
                        tint: root.accent
                        Accessible.name: on ? Translation.tr("Remove from Liked Songs") : Translation.tr("Save to Liked Songs")
                        onActivated: SpotifyBridge.queueLike(SpotifyBridge.trackUri, !on)
                        HoverTip { text: on ? Translation.tr("Remove from Liked Songs") : Translation.tr("Save to Liked Songs") }
                    }
                    // Spotify's DJ, beside the others: starts the DJ station. Only with the Spotify extension.
                    ChipButton {
                        visible: root.isSpotify && SpotifyBridge.available
                        label: "DJ"
                        labelWeight: Font.Bold
                        on: SpotifyBridge.queue ? SpotifyBridge.queue.dj : false
                        tint: root.accent
                        Accessible.name: on ? Translation.tr("The DJ is on") : Translation.tr("Start the DJ")
                        HoverTip { text: on ? Translation.tr("The DJ is on") : Translation.tr("Start the DJ") }
                        onActivated: { if (!on) SpotifyBridge.queuePlay() }
                    }
                    ChipButton {
                        symbol: "music_note"
                        on: SongRec.listening && !SongRec.usingMic
                        tint: root.accent
                        enabled: SongRec.blocker(false) === "" || (SongRec.listening && !SongRec.usingMic)
                        Accessible.name: Translation.tr("What is this song?")
                        onActivated: SongRec.toggle(false)
                        HoverTip { text: SongRec.blocker(false) !== "" ? SongRec.blocker(false) : Translation.tr("What is this song?") }
                    }
                    ChipButton {
                        visible: root.showLyrics
                        symbol: "translate"
                        on: Config.lyricsTranslate
                        tint: root.accent
                        Accessible.name: Translation.tr("Translate the lyrics")
                        onActivated: Config.lyricsTranslate = !Config.lyricsTranslate
                        HoverTip { text: Translation.tr("Translate the lyrics") }
                    }
                    // Only on a song that has something to romanize.
                    ChipButton {
                        visible: root.showLyrics && LyricsRomanize.romanizable
                        symbol: "record_voice_over"
                        on: Config.lyricsRomanize
                        tint: Config.lyricsRomanize && LyricsRomanize.failed ? root.palette.warning : root.accent
                        Accessible.name: Translation.tr("Latin letters under the lyrics")
                        onActivated: Config.lyricsRomanize = !Config.lyricsRomanize
                        HoverTip { text: Translation.tr("Latin letters under the lyrics") }
                    }
                    // Never disabled: a start that cannot happen says why in the line under the artist.
                    ChipButton {
                        visible: root.showLyrics
                        symbol: "mic"
                        on: Karaoke.active
                        tint: root.accent
                        Accessible.name: Translation.tr("Sing along")
                        onActivated: Karaoke.toggle()
                        HoverTip { text: Translation.tr("Sing along") }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }

        // ── The lyrics ────────────────────────────────────────────────────────
        IslandPlate {
            Layout.preferredWidth: Tokens.spacingXl * 18
            Layout.fillHeight: true
            visible: root.showLyrics
            order: 2

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingMd
                spacing: Tokens.spacingSm

                // Lyrics | Queue. The queue is Spotify's; with another player it has nothing to show.
                SegmentSwitch {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    model: [
                        { value: "lyrics", label: Translation.tr("Lyrics"), icon: "lyrics" },
                        { value: "queue",  label: Translation.tr("Queue"),  icon: "queue_music" }
                    ]
                    current: root.side
                    accent: root.accent
                    onPicked: function (v) { root.side = v }
                }
                PanelLyrics {
                    visible: root.side === "lyrics"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    player: tp.player
                    position: tp.pos
                    active: root.visible && root.side === "lyrics"
                    accent: root.accent
                }
                ColumnLayout {
                    visible: root.side === "queue"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Tokens.spacingSm
                    QueueList {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                    }
                }
                // Which player the page shows. With one, it just says so.
                MediaSourcePill {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    players: root.allPlayers
                    current: root.player
                    pinned: root.pinned
                    accent: root.accent
                    onPicked: function (id) { root.pinned = id }
                }
            }
        }
    }

    // ── Karaoke's two moments ─────────────────────────────────────────────────
    // Joined mid-song (the run won't be ranked; a restart with a 3-2-1), and the result when a song
    // has played out. Over the page, built only while it is on screen.
    Loader {
        anchors.fill: parent
        z: 60
        active: (Karaoke.joinNotice || Karaoke.countdown > 0 || Karaoke.countdownGo) && root.visible
        sourceComponent: KaraokeJoin { accent: root.accent }
    }
    Loader {
        anchors.fill: parent
        z: 50
        active: Karaoke.result !== null && root.visible
        sourceComponent: KaraokeResults {
            result: Karaoke.result
            accent: root.accent
            onClosed: Karaoke.dismissResult()
            onOpenScores: Karaoke.dismissResult()
        }
    }
}
