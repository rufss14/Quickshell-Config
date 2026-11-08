import QtQuick
import Quickshell
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "../../config"
import "../../components"
import "../../services"
import "../../services/mediasource.js" as MediaSource
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


    // ── Where this card's colours come from ───────────────────────────────────
    // Defaults to the cover — the whole design of this card is the artwork washing it, so
    // that default is the point, not a convenience. A DESKTOP TILE is the case that needs
    // otherwise: it sits on the wallpaper, where an album palette competes with everything
    // around it instead of belonging to it, and pointing these at the shell's own
    // wallpaper-derived palette makes the tile part of the desktop again.
    //
    // Note this card still WRITES AlbumArt (it owns the extraction, being the one surface
    // that always knows the current cover). Reading its own colours from elsewhere does
    // not change that — the lyrics card and everything else still get their album palette.
    property color tintBg:      Config.albumCardColors ? AlbumArt.bg      : Colors.of(QsWindow.window).surface
    property color tintFg:      Config.albumCardColors ? AlbumArt.fg      : Colors.of(QsWindow.window).fg
    property color tintFgDim:   Config.albumCardColors ? AlbumArt.fgDim   : Colors.of(QsWindow.window).fgDim
    property color tintFgMuted: Config.albumCardColors ? AlbumArt.fgMuted : Colors.of(QsWindow.window).fgMuted
    property color tintAccent:  Config.albumCardColors ? AlbumArt.accent  : Colors.of(QsWindow.window).primary

    // The fill for the secondary transport buttons — the play button's colour,
    // lifted toward the foreground so it reads as a lighter tint of the same hue.
    readonly property color tintChip: Colors.of(QsWindow.window).mix(root.tintAccent, root.tintFg, 0.5)

    // The frame, in pixels. 0 removes it, along with the wash inset and the ring veil that
    // exist only to serve it — both are derived from this, so there is nothing left drawing
    // an edge when it is zero.
    property int frameWidth: 2

    // ── The artwork wash ──────────────────────────────────────────────────────
    // On by default: the cover blurred behind the card is the design, not decoration.
    //
    // It has to be switchable because it OVERRULES the palette. Point the colours at the
    // wallpaper and leave this on and almost nothing changes — the album art is still what
    // you see, and the tint only survives in the text and the gradient over it. That is
    // exactly what "the colourscheme option does nothing" was.
    property bool artWash: Config.albumCardColors

    // ── Which background ──────────────────────────────────────────────────────
    // "cover" is the blurred artwork this card was designed around. "flow" is SpicyFlow:
    // the same colours, drifting, with the photograph's composition thrown away — which
    // is what stops a cover with a bright corner putting a bright corner behind the text.
    // "none" leaves the flat fill.
    //
    // `artWash: false` still overrides all of it, because that is what wallpaper colours
    // set — a cover-derived background of any kind defeats a wallpaper palette.
    property string washStyle: "flow"

    // ── Pin to one player ─────────────────────────────────────────────────────
    // "" keeps the sticky rule below. A name ("Spotify", "Zen Browser") holds the card to
    // that player when it exists — matched by `identity` because MPRIS players carry no id
    // that survives a restart.
    //
    // A pin naming something that is not running falls through to the sticky rule rather
    // than showing nothing: a closed browser silencing the card for whatever else IS
    // playing is the worse failure. Same contract, same spelling, as the tile it replaced.
    property string pin: ""

    implicitWidth:  card.visible ? 400 : 0
    implicitHeight: card.visible ? 148 : 0

    // ── Player selection ──────────────────────────────────────────────────────
    property var _player: null
    readonly property var player: _player

    readonly property var allPlayers: Mpris.players.values

    // The rule itself lives in mediasource.js, because AlbumScheme needs the same
    // answer and this card is inside the lazy-loaded overview — so its copy only
    // existed while the overlay was open. The `pin` stays a per-card property: a
    // desktop tile can be pinned to a different player than the overview, so the rule
    // is shared but the answer is not.
    function _refresh() {
        root._player = MediaSource.pickPlayer(root.allPlayers, root._player, root.pin)
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

    // The pin can change while the card is alive — a settings edit on a desktop tile.
    onPinChanged: root._refresh()

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

    // Transport controls use the shared CookieButton (scalloped shape, wind-on-
    // hover). See components/CookieButton.qml.

    // ── Position ──────────────────────────────────────────────────────────────
    // Two timers, both gated on the overlay being OPEN — a progress bar nobody can see
    // has no business interpolating itself 30 times a second. (Same lesson the bar's
    // MediaController had to learn: its position timers ran permanently, including while
    // it was hidden, which was almost always.)
    property real pos:    0
    property real length: 1

    // ── `active` — is anyone looking at this card? ────────────────────────────
    // Was `UiState.overviewOpen` read directly here. It became a property because the
    // LOCKSCREEN draws this same card, and on that surface the overview is by definition
    // closed — so the position timers below would never run and the progress bar would
    // sit frozen at wherever the song was when the overlay last closed.
    //
    // It still defaults to the overlay's state, so the overview passes nothing and
    // behaves exactly as before. The lock passes `active: true`. What must NOT happen is
    // this defaulting to true: these timers tick 32ms and the card is instantiated per
    // screen whether or not anything is on screen, which is the bug the comment above
    // records MediaController having shipped.
    property bool active: UiState.overviewOpen

    readonly property bool live: root.active && root.player !== null

    // ── The clock is an ANCHOR plus elapsed wall time, never an accumulator ────
    // This was `pos += 0.032` on a 32ms Timer. A Qt Timer guarantees only "not before" —
    // under load it fires late, and every late fire silently LOSES that time. So the
    // playhead ran slow and the 500ms re-read below snapped it forward: a sawtooth,
    // forever, on a half-second cycle. Invisible on a progress bar. Very visible on
    // lyrics, where words run 200–600ms and a 50ms jump lands a syllable off.
    //
    // Anchoring cannot accumulate error because nothing is summed — `pos` is derived
    // fresh every frame from (anchor + real elapsed time).
    property real _anchorPos: 0
    property real _anchorMs:  0

    function _anchor(p) {
        root._anchorPos = Math.max(0, p)
        root._anchorMs  = Date.now()
        root.pos        = root._anchorPos
    }

    // A reported position further than this from ours is a SEEK, not drift.
    readonly property real _seekEps:  0.25
    // How hard an ordinary disagreement pulls the anchor. Small on purpose — see sync().
    readonly property real _pullRate: 0.12

    // ── Is Spotify's own playhead available to us? ────────────────────────────
    // The bridge only ever speaks for Spotify, so it is only trusted when Spotify is also
    // the player MPRIS is showing. `available` on the service covers the app having quit
    // without saying so, and having run off the end of a track we missed the change of.
    readonly property bool bridged:
        root.source.id === "spotify" && SpotifyBridge.available

    function sync() {
        if (!player) { root.length = 1; root._anchor(0); return }
        root.length = player.length > 0 ? player.length : 1

        // ── Spotify's own clock, when we can get it ───────────────────────────
        // The bridge is already an anchor plus elapsed time, so re-anchoring from it just
        // swaps our MPRIS-derived guess for the number Spotify draws its own progress bar
        // from. No drift filter on this branch: both sides read the same monotonic clock,
        // so there is no jitter to smooth — filtering would only add lag.
        if (root.bridged) {
            if (SpotifyBridge.duration > 0) root.length = SpotifyBridge.duration
            root._anchor(SpotifyBridge.position())
            return
        }

        const reported = player.position ?? 0

        // Paused: the player's number is the whole truth, nothing is elapsing.
        if (!root.playing) { root._anchor(reported); return }

        const expected = root._anchorPos + (Date.now() - root._anchorMs) / 1000
        const drift    = reported - expected

        if (Math.abs(drift) > root._seekEps) {
            root._anchor(reported)      // a real seek — jumping IS the truth here
        } else {
            // Ordinary disagreement. Do NOT snap: MPRIS positions are coarse and jitter
            // either side of the truth, so snapping to each read reintroduces exactly the
            // stutter the anchor removed. Pull the anchor part of the way instead — a
            // one-pole filter, converges in about a second, never visible as a step.
            root._anchorPos += drift * root._pullRate
        }
    }

    onPlayerChanged:  sync()
    onPlayingChanged: sync()

    // Authoritative re-read. Still 500ms, but it is a CORRECTION now, not the update rate.
    Timer {
        interval: 500
        running:  root.live
        repeat:   true
        onTriggered: if (!seekBar.scrubbing) root.sync()
    }

    // A track change resets the playhead to 0. Waiting for the poll above let up to half
    // a second of the previous track's tail bleed into the start of the new one.
    Connections {
        target: root.player
        ignoreUnknownSignals: true
        function onTrackChanged()    { root._anchor(root.player?.position ?? 0) }
        function onPositionChanged() { if (!seekBar.scrubbing) root.sync() }
    }

    // ── Per frame, not every 32ms ─────────────────────────────────────────────
    // A 32ms Timer beats against the compositor's refresh, so steps land unevenly however
    // exact the arithmetic is. FrameAnimation fires once per frame in step with the render
    // loop — which is what the lyrics card's word highlight wants too, since it reads
    // `pos` straight off this. (QtQuick 6.4+; Qt here is 6.11.)
    FrameAnimation {
        running: root.live && root.playing && !seekBar.scrubbing
        onTriggered: root.pos = Math.min(
            root._anchorPos + (Date.now() - root._anchorMs) / 1000,
            root.length)
    }

    function timeStr(sec) {
        if (!isFinite(sec) || sec < 0) sec = 0
        const m = Math.floor(sec / 60)
        const s = Math.floor(sec % 60)
        return m + ":" + (s < 10 ? "0" + s : s)
    }

    // ══════════════════════════════════════════════════════════════════════════
    // No cast shadow — the album wash already lifts this card off the scrim, and a
    // drop shadow under a translucent card just reads as grime pooling at its
    // bottom edge. `castsShadow: false` also spares the internal Elevation loader.
    Surface {
        id: card
        anchors.fill: parent
        elevation: Tokens.elevationPopup
        castsShadow: false
        // The expressive corner the overview's other islands use — the internal
        // radii all derive from `card.radius`, so this ripples through for free.
        cornerRadius: Tokens.radiusXl
        visible: root.player !== null
        clip: true

        // The card's fill is the cover's own shadow, not the shell's surface colour.
        color: root.tintBg
        Behavior on color { ColorAnimation { duration: Motion.spatial } }

        // A clearly visible, album-tinted edge — matching the lyrics card and the 2px
        // accent borders already used on the art thumbnail and transport controls inside.
        // The default surface outline washes out against arbitrary cover colours.
        border.width: root.frameWidth
        border.color: root.tintAccent
        Behavior on border.color { ColorAnimation { duration: Motion.spatial } }


        // ── The drifting field ────────────────────────────────────────────────────
        // The alternative background. Gated on `active` as well as on the style: four animated
        // items under a blur pass is real per-frame work, and behind a closed overlay or a
        // covered desktop it must cost nothing.
        SpicyFlow {
            anchors.fill: parent
            anchors.margins: card.border.width
            visible: root.artWash && root.washStyle === "flow"
            running: visible && root.active

            // The cover itself, not colours taken from it. Same URL the "cover" wash
            // uses, so the two styles are two treatments of one picture rather than two
            // sources.
            source: root.player?.trackArtUrl ?? ""
            base:   root.tintBg

            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: cardMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
        }

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
        // ── Inset by the border, so the frame survives it ─────────────────────
        // This card and the lyrics card declare the SAME border — 2px of root.tintAccent —
        // and it still read as thinner and duller here. Nothing was wrong with the border:
        // the wash is 0.85 opaque against the lyrics card's 0.45, and filling the whole
        // rect it painted straight over the frame it was sitting inside. The lyrics card
        // only looked correct because its wash is faint enough to see through.
        //
        // Held off the edge by exactly the border width instead. The mask below is inset
        // identically — a maskSource is sampled across the source item's own bounds, so
        // the two geometries have to agree or the corners round in the wrong place.
        Item {
            anchors.fill: parent
            anchors.margins: card.border.width
            visible: root.artWash && root.washStyle === "cover"
                     && artSource.status === Image.Ready

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

                // ── A BLUR source, so it is capped ────────────────────────────
                // 320 to match SpicyFlow's art copies, which is not a coincidence: the
                // "flow" and "cover" washes are two treatments of THE SAME cover, so
                // they should hold it at the same size. (`art` below is the opposite
                // case and takes the opposite decision — it is the SHARP thumbnail, so
                // it asks AlbumArt.hiRes for the 1400px original and decodes at 2x.)
                //
                // Nothing here survives the blur below (blurMax 48), so decoding at
                // native resolution buys no detail — it only holds the whole cover in
                // memory and makes the blur pass chew through a texture that many
                // times larger. `trackArtUrl` is 640px from Spotify but whatever is
                // embedded in a local file otherwise, regularly 1500px or more.
                //
                // A literal, not a size binding: bound to width/height this re-decodes
                // on every frame of a card resize.
                sourceSize: Qt.size(320, 320)
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
                    GradientStop { position: 0.0; color: Colors.of(QsWindow.window).alpha(root.tintBg, 0.80) }
                    GradientStop { position: 0.6; color: Colors.of(QsWindow.window).alpha(root.tintBg, 0.45) }
                    GradientStop { position: 1.0; color: Colors.of(QsWindow.window).alpha(root.tintBg, 0.15) }
                }
            }
        }

        Item {
            id: cardMask
            anchors.fill: parent
            anchors.margins: card.border.width
            visible: false
            layer.enabled: true
            Rectangle {
                anchors.fill: parent
                // The radius of the hole INSIDE the frame, not of the frame itself. A
                // border shrinks the corner it encloses by its own width; using the outer
                // radius here leaves a sliver of wash outside the curve at each corner.
                radius: Math.max(0, card.radius - card.border.width)
                color: "white"
            }
        }

        // ── The frame belongs to the art, not on top of it ────────────────────
        // The lyrics card gets this for nothing: its wash is faint enough to sit OVER its
        // own border, so the frame picks up whatever the cover is doing behind it and
        // reads as lit rather than drawn. This card's wash is nearly twice as opaque, so
        // holding it off the edge (above) made the border crisp — and crisp turned out to
        // mean a hard, uniform ring, which is the thing that looked wrong.
        //
        // So the same left-heavy tone that keeps the text legible is laid over the frame
        // as well: dimmed where the title sits, full accent where the cover shows through.
        // Masked to the RING alone — an outer rounded rect with the inner one punched out —
        // so nothing here touches the card's contents.
        Item {
            anchors.fill: parent

            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: frameMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: Colors.of(QsWindow.window).alpha(root.tintBg, 0.62) }
                    GradientStop { position: 0.6; color: Colors.of(QsWindow.window).alpha(root.tintBg, 0.28) }
                    GradientStop { position: 1.0; color: Colors.of(QsWindow.window).alpha(root.tintBg, 0.00) }
                }
            }
        }

        Item {
            id: frameMask
            anchors.fill: parent
            visible: false
            layer.enabled: true

            // White outer, black inner — the difference is the 2px ring the border
            // occupies. Painted rather than stroked because a Rectangle's own border is
            // not something a mask can sample on its own.
            Rectangle {
                anchors.fill: parent
                radius: card.radius
                color: "white"
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: card.border.width
                radius: Math.max(0, card.radius - card.border.width)
                color: "black"
            }
        }

        // ── Lyrics provenance ─────────────────────────────────────────────────
        // Left of the source logo. Says where the WORDS came from, which is a different
        // question from where the audio did — and one worth answering, because the two
        // paths are not equivalent: the bridge returns real syllable timings fetched from
        // inside Spotify, the fallback returns word- or line-level from NetEase/LRCLIB.
        //
        // A good share of the bridge's catalogue is community-transcribed rather than
        // licensed, which is exactly why its coverage is better — and exactly why it is
        // worth crediting rather than passing off as official.
        //
        // Hidden entirely when there are no synced lyrics: a permanently dim icon that
        // means "nothing here" is noise on a card this small.
        Item {
            id: lyricsBadge

            anchors.verticalCenter: sourceBadge.verticalCenter
            anchors.right: sourceBadge.left
            anchors.rightMargin: Tokens.spacingSm
            width:  16
            height: 16
            z: 10

            visible: Lyrics.hasSynced

            MaterialIcon {
                anchors.centerIn: parent

                // Check when the bridge provided them, cross when the shell fell back to
                // its own NetEase/LRCLIB lookup. Deliberately a plain pass/fail: the
                // question this answers is "did the good path work", and the fallback is
                // genuinely worse — word- or line-level rather than real syllables.
                glyph: Lyrics.viaBridge ? "󰄬" : "󰅖"
                font.pixelSize: Tokens.iconSm

                // The fixed pass/fail green and red — and the Config.colorizeIcons
                // opt-out to the GLOBAL accent that must accompany them — live in
                // config/Verdict.qml. The bar's VisualizerPill draws this same fact and
                // had a second copy of both; see that file for why the palette is not
                // allowed to restate a pass/fail.
                color:   Verdict.tint(Lyrics.viaBridge)
                opacity: 0.95

                Behavior on color { ColorAnimation { duration: Motion.standard } }
            }

            // A community transcription gets a mark of its own. Small and low-contrast:
            // it is a credit, not a warning — the lyrics are usually better, not worse.
            Rectangle {
                visible: Lyrics.community
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width:  5
                height: 5
                radius: 2.5
                color: root.tintAccent
                opacity: 0.85
                border.width: 1
                border.color: Colors.of(QsWindow.window).alpha(root.tintBg, 0.9)
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
            MaterialIcon {
                anchors.centerIn: parent
                visible: root.sourceIcon === ""
                glyph: "󰎈"
                color: Colors.of(QsWindow.window).fgMuted
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
                color: Colors.of(QsWindow.window).surfaceHigh
                border.width: Tokens.borderWidth
                border.color: Colors.of(QsWindow.window).outlineNested

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
                color:  Colors.of(QsWindow.window).alpha(root.tintAccent, 0.18)

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: art.status !== Image.Ready
                    glyph: "󰝚"
                    color: root.tintAccent
                    font.pixelSize: Tokens.fontNumeralMd
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
                    border.color: root.tintAccent
                    opacity: 0

                    SequentialAnimation on opacity {
                        running: root.playing
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.55; duration: Motion.slow; easing.type: Motion.ambient }
                        NumberAnimation { to: 0.00; duration: Motion.slow; easing.type: Motion.ambient }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: Tokens.spacingXs

                // ── Title row, with the card's controls ───────────────────────
                // Translate and player-switch sit together HERE, not up in the corner.
                // That corner is a STATUS cluster — the lyrics-provenance tick and the
                // source logo, both of which only report — and a pressable control mixed
                // into it read as another badge while also being the loudest thing on the
                // card. Controls belong with the controls.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingXs

                    StyledText {
                        Layout.fillWidth: true
                        text: root.player?.trackTitle ?? ""
                        variant: "title"
                        font.bold: true
                        color: root.tintFg
                        elide: Text.ElideRight
                    }

                    // ── Translate ─────────────────────────────────────────────
                    // Ghost like its neighbour, and the same 22px: it is a peer of the
                    // player switch, not a feature announcement. It tints to the accent
                    // only while translation is actually ON, so it recedes the rest of the
                    // time instead of advertising itself.
                    //
                    // Disabled rather than hidden when the backend cannot run — the
                    // pressBlocker() contract. "Why is there no translate button" has no
                    // answer; a disabled one carrying its reason does.
                    PanelButton {
                        id: translateBtn

                        // ── Always here ───────────────────────────────────────
                        // This was `visible: Lyrics.hasSynced`, which is why it felt
                        // unreliable: every track change calls _clear("loading"), so
                        // hasSynced goes false and the button VANISHES until the new
                        // lyrics land — and never appears at all on a track without synced
                        // lyrics. It was not failing to work, it was not there.
                        //
                        // It sets a persistent preference, not a per-track action, so it
                        // belongs on the card whenever the card is.
                        implicitWidth:  22
                        implicitHeight: 22
                        glyph: "󰗊"

                        readonly property string blocker: LyricsTranslate.blocker()
                        readonly property bool busy:
                            LyricsTranslate.state === "loading"
                            || LyricsTranslate.state === "probing"

                        // ── ALWAYS pressable ──────────────────────────────────
                        // It used to gate on `blocker`, which is what made it feel broken.
                        // Enabling the setting is what STARTS the probe, and the probe sets
                        // the blocker to "checking the translator…" while it runs — so one
                        // press disabled the button, and a probe that failed for any reason
                        // latched that blocker and left it dead for the session.
                        //
                        // The blocker governs whether translation can RUN, which is the
                        // service's business. Whether you may change a setting is not
                        // conditional on the setting currently working.
                        //
                        // `opacity` is deliberately NOT set here either: PanelButton
                        // already binds it to `enabled`, and overriding it threw away the
                        // only feedback the disabled state had.

                        // Ghost throughout. `primary` filled it into a solid disc, which is
                        // the circle that had to go — it made a small toggle the heaviest
                        // object on the card.
                        variant: "ghost"

                        // On and off are carried by the GLYPH instead: album accent when
                        // translation is running, ordinary foreground when it is not, and
                        // dimmed when the backend cannot run at all. Three states, no extra
                        // shape.
                        glyphTint: translateBtn.blocker !== ""
                            ? Colors.of(QsWindow.window).alpha(root.tintFg, 0.40)
                            : Config.lyricsTranslate ? root.tintAccent
                                                     : root.tintFg
                        Behavior on glyphTint { ColorAnimation { duration: Motion.standard } }

                        onActivated: Config.lyricsTranslate = !Config.lyricsTranslate

                        // ── Busy ──────────────────────────────────────────────
                        // A small dot in the corner while the translation is in flight.
                        // The whole button pulsing was tried and read as the control
                        // wobbling rather than working.
                        //
                        // Even at twelve requests in flight a fresh track is a visible
                        // pause; with nothing at all the button looks like it ignored the
                        // press.
                        BusyDot {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: -1
                            running: translateBtn.busy
                            visible: translateBtn.busy
                            tint: root.tintAccent
                        }
                    }

                    // Only rendered when there IS another player to switch to.
                    PanelButton {
                        visible: root.allPlayers.length > 1
                        variant: "ghost"
                        implicitWidth:  22
                        implicitHeight: 22
                        // Swap arrows rather than the old speaker glyph: this cycles which
                        // PLAYER the card is following, and a speaker reads as an audio
                        // output control — which is a different thing that also exists in
                        // this shell.
                        glyph: "󰓦"
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
                    color: root.tintFgMuted
                    elide: Text.ElideRight
                }

                // ── Seek bar — the shared WaveSlider ──────────────────────────
                // Same slider the bar's volume pill uses: the played portion is a
                // travelling sine line whose amplitude follows the sink's real peak
                // (flat at silence), a plain rail for the rest, a thin playhead bar.
                Item {
                    id: seekBar
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacingSm
                    implicitHeight: seekWave.implicitHeight

                    // Consumed by root.sync()'s timers — don't re-anchor the position
                    // while the user is dragging.
                    readonly property bool scrubbing: seekWave.pressed

                    PwNodePeakMonitor {
                        id: mediaPeak
                        node:    Audio.sink
                        enabled: root.active && root.playing && Audio.ready && Audio.hasKnownChannels(Audio.sink)
                    }

                    WaveSlider {
                        id: seekWave
                        anchors.fill: parent
                        enabled: root.seekable
                        value:   root.pos
                        maximum: Math.max(1, root.length)
                        accent:  root.tintAccent
                        level:   root.playing ? Audio.meterLevel(mediaPeak.peak) : 0
                        // `pos` is already frame-interpolated — the handle tracks it
                        // 1:1 rather than easing behind it.
                        smoothHandle: false

                        onMoved: function(v) {
                            root.pos = v
                            if (root.player) root.player.position = v
                        }
                        onScrolled: function(d) {
                            const v = Math.max(0, Math.min(root.length, root.pos + d * 5))
                            root.pos = v
                            if (root.player) root.player.position = v
                        }
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
                        color: root.tintFgDim
                    }

                    Item { Layout.fillWidth: true }

                    // shuffle ↔ loop are one mirrored pair (6-point, tilted ∓18°);
                    // prev ↔ next another (5-point, ∓12°); play is the centre.
                    CookieButton {
                        Layout.alignment: Qt.AlignVCenter
                        visible: root.player?.shuffleSupported ?? false
                        primary: true
                        glyphOnFill: root.tintBg
                        points:  6
                        restTilt: -18
                        implicitWidth:  26
                        implicitHeight: 26
                        glyph: "󰒝"
                        tint: (root.player?.shuffle ?? false) ? root.tintAccent : root.tintChip
                        onActivated: if (root.player) root.player.shuffle = !root.player.shuffle
                    }

                    CookieButton {
                        Layout.alignment: Qt.AlignVCenter
                        primary: true
                        glyphOnFill: root.tintBg
                        points:  5
                        restTilt: -12
                        implicitWidth:  30
                        implicitHeight: 30
                        glyph: "󰒮"
                        tint: root.tintChip
                        enabled: root.player?.canGoPrevious ?? false
                        onActivated: root.player?.previous()
                    }

                    // The one accent-filled control — what the card is FOR.
                    CookieButton {
                        Layout.alignment: Qt.AlignVCenter
                        primary: true
                        glyphOnFill: root.tintBg
                        points:  8
                        tint:    root.tintAccent
                        implicitWidth:  38
                        implicitHeight: 38
                        glyph: root.playing ? "󰏤" : "󰐊"
                        enabled: root.player?.canTogglePlaying ?? false
                        onActivated: root.player?.togglePlaying()
                    }

                    CookieButton {
                        Layout.alignment: Qt.AlignVCenter
                        primary: true
                        glyphOnFill: root.tintBg
                        points:  5
                        restTilt: 12
                        implicitWidth:  30
                        implicitHeight: 30
                        glyph: "󰒭"
                        tint: root.tintChip
                        enabled: root.player?.canGoNext ?? false
                        onActivated: root.player?.next()
                    }

                    // Loop cycles none → playlist → track, and the glyph says which.
                    CookieButton {
                        Layout.alignment: Qt.AlignVCenter
                        visible: root.player?.loopSupported ?? false
                        primary: true
                        glyphOnFill: root.tintBg
                        points:  6
                        restTilt: 18
                        implicitWidth:  26
                        implicitHeight: 26
                        glyph: root.player?.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"
                        tint: (root.player?.loopState ?? MprisLoopState.None) !== MprisLoopState.None
                            ? root.tintAccent : root.tintChip
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
                        color: root.tintFgDim
                    }
                }
            }
        }
    }
}
