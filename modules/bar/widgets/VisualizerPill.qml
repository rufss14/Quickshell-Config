import QtQuick
import Quickshell
import QtQuick.Effects
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/mediasource.js" as MediaSource

// ── VisualizerPill ────────────────────────────────────────────────────────────
// A media module — nucleus-shell's, in shape: album art beside the track. Two
// differences from theirs, both requested: the art sits still (theirs spins the
// cover continuously; this shell already reserves motion for things that are
// actually changing, not decoration), and the spectrum stays, so this reads as
// "now playing" AND "audio is happening" at once instead of picking one.
//
// The track line is two rows the same way ClockPill's is — a bold line over a
// dim one — rather than nucleus's single truncated line, because that's the
// shape the rest of this bar's pills already speak.
//
//   left-click   → open the Now Playing panel (media, lyrics, translation)
//   right-click  → toggle the desktop cava background
//
// The panel replaces what used to be left-click's job (Config.cavaBg), which
// moved to right-click — a real feature, not dropped, just no longer the
// pill's ONE action now that it opens something. MediaController is still
// instantiated, `shown` permanently false, purely as the source of
// `controller.player`: it already does the sticky current-player pick (don't
// fall back to players[0] just because the current one paused), and
// re-deriving that a third time here would be a second copy of a rule
// OverviewNowPlaying also carries.
//
// Was AudioVisualizer: 526 lines that were really two widgets, and it started a
// `cava` process at 60fps with `running: true` and *never stopped it* — not
// when hidden. The bar built both its layouts, so there were two of them, plus
// a third inside CavaBG. Three cava processes analyzing the same audio to draw
// the same spectrum.
//
// Now: one shared Cava service, refcounted, running only while this pill is
// actually on screen.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // ── accent ────────────────────────────────────────────────────────────────
    // Settable per module (Settings → Bar → pick a module). Defaults to the role this
    // widget already used, so an untouched module is unchanged.
    property color accent: Colors.of(QsWindow.window).primary

    // Whether the Now Playing panel this pill opens is currently up — set by
    // Bar.qml (UiState.isOpen("media")), same as every other panel-opening pill.
    property bool active: false
    // The bar's hero (Config.moduleHero; BarGroupRow sets it): its chip is primaryContainer,
    // so the track lines go to the colour made for that ground. The spectrum keeps the accent.
    property bool hero: false
    readonly property color _onHero: Colors.of(QsWindow.window).fgOnPrimaryContainer

    signal toggled()

    readonly property int barCount: 6
    readonly property int barW:     3
    readonly property int barGap:   3
    readonly property int maxBarH:  Config.barPillHeight - 6

    // ── The cover, in its progress ring ───────────────────────────────────────
    // Material 3 Expressive's wavy progress (2026-10-31, the user's pick over a line under
    // the text, which the two text lines leave no height for): the cover is a circle inside
    // a wavy ring that fills as the track plays and lies flat while it's paused. The ring
    // takes the pill's whole height; the cover is what is left inside the wave's trough
    // and a hairline gap (a 2px ring's wave reaches a stroke in: RadialGauge's 1px floor
    // either side). Never rotates. (Nucleus-shell's does; asked for explicitly NOT to here.)
    readonly property int ringSize:      Config.barPillHeight
    readonly property int ringThickness: Tokens.spacingXs
    readonly property int artSize: root.ringSize - (root.ringThickness * 2 + Tokens.borderWidth) * 2

    // Where in the track, read once a second while it plays and the pill is on screen —
    // MediaController's own sync (the player's position), not a per-frame playhead — and
    // rounded to the ring's pixels, so the ring and its wave redraw only when the arc would
    // grow by one: every couple of seconds on a three-minute song.
    Timer {
        interval: 1000
        repeat: true
        running: root.visible && controller.playing
        onTriggered: controller.sync()
    }
    readonly property real progress: {
        const steps = Math.max(1, Math.round(Math.PI * root.ringSize))
        return Math.round(Math.max(0, Math.min(1, controller.pos / controller.length)) * steps) / steps
    }

    // A CAP, not a reserved slot: a title/artist wider than this elides instead of
    // stretching the pill out indefinitely. Below the cap the text (and the pill
    // around it) sizes to content — see mediaWidth — so a short title like "アイドル"
    // doesn't leave a dead gap in front of the spectrum. The pill's width Behavior
    // below is what keeps that resize from ever feeling like a jump cut.
    readonly property int maxTextWidth: Math.round(112 * Config.barFontScale)

    implicitWidth:  pill.width
    implicitHeight: Config.barPillHeight

    // `controller` isn't declared until further down, inside `pill` — fine, QML
    // resolves ids across the whole file regardless of where a binding sits relative
    // to the id it names, the same way `mediaWidth` below already leans on
    // `mediaContent` before its own declaration.
    readonly property bool hasPlayer: !!controller.player

    // ── The track lines swap through a fade on a new track ────────────────────
    // `shown*` is the held copy the Column draws (see SwapFade): the old title eases
    // out and the new one in, with the pill's own width Behavior carrying the resize.
    // Keyed on title + artist, so a track whose metadata arrives in two steps (title,
    // then artist) swaps at most twice and settles on the last.
    readonly property string trackTitle:  controller.player ? (controller.player.trackTitle || "Unknown") : "No player"
    readonly property string trackArtist: controller.player ? (controller.player.trackArtist || "") : ""
    property string shownTitle:  ""
    property string shownArtist: ""

    // ── Which PipeWire node is actually "the player" ──────────────────────────
    // Resolved through Audio.streamsFor(), the same appId-based lookup the per-app
    // volume scroll uses — not the shared default-output signal. This pill used to
    // point at "whatever's coming out of the speakers", which is every app sharing
    // them: a Discord call, a notification chime. Targeting the player's OWN node
    // is what keeps the bars reacting to Spotify and nothing else.
    readonly property string playerNodeName: {
        if (!root.hasPlayer) return ""
        const appId = controller.player.desktopEntry ?? ""
        if (!appId) return ""
        const nodes = Audio.streamsFor(appId)
        return nodes.length > 0 ? nodes[0].name : ""
    }

    // ── Cava lifecycle ────────────────────────────────────────────────────────
    // Held only while this pill is on screen AND there's an actual node to point
    // at — a player with no matching PipeWire stream yet (paused before it opened
    // one) has nothing worth analysing, so there's no point starting a process for
    // it. See services/Cava.qml for why this is `acquireSource`, refcounted and
    // pooled, rather than a private CavaStream of this pill's own.
    //
    // Game mode's "Hide the visualiser" reaches here too, not only CavaBG: this pill is a
    // visualiser, and a cava process analysing audio at 60fps (plus the bar redrawing
    // to show it) is exactly the background work that toggle exists to stop while
    // playing. The pill keeps its art and title; the spectrum rests on the idle wave.
    readonly property bool frozen: Gamemode.hidesVisualizer
    readonly property bool wantsCava: root.visible && root.playerNodeName !== "" && !root.frozen
    property bool _cavaHeld: false

    function _syncCava() {
        if (root.wantsCava) {
            if (!root._cavaHeld) { Cava.acquireSource(root.playerNodeName); root._cavaHeld = true }
            else                 Cava.sourceName = root.playerNodeName
        } else if (root._cavaHeld) {
            Cava.releaseSource()
            root._cavaHeld = false
        }
    }

    onWantsCavaChanged:      root._syncCava()
    onPlayerNodeNameChanged: root._syncCava()
    Component.onCompleted: {
        root._syncCava()
        root.shownTitle = root.trackTitle      // the held copy — see SwapFade, above
        root.shownArtist = root.trackArtist
    }
    // Without this, a destroyed pill (e.g. a monitor unplugged) leaks its
    // reference and pins cava on forever.
    Component.onDestruction: if (root._cavaHeld) Cava.releaseSource()

    // 14 bars from the service's 32, averaged rather than sampled — sampling drops
    // transients, which is the content a visualizer exists to show. Empty (reads as
    // silence — see Spectrum's own comment) whenever there's nothing being targeted,
    // rather than falling back to the shared default-output spectrum: that fallback
    // is exactly the Discord-bleed-through this was built to stop.
    readonly property var bars: root.wantsCava ? Cava.resample(Cava.sourceBars, root.barCount) : []

    // ── The idle wave ────────────────────────────────────────────────────────
    // Cava reflects the SYSTEM'S audio output, not "this player" — it has no idea
    // whether an MPRIS session exists at all, so silence and "nothing is playing"
    // look identical to it. With no player the art and text collapse (below), and
    // real cava data would just be a flat near-empty row sitting where a track used
    // to be — dead-looking, not "waiting". A gentle sine takes its place: a per-bar
    // phase offset so it reads as one wave across the row rather than every bar at
    // one height.
    //
    // It holds STILL, crest centred on the row. It used to travel (a 2.4s loop on the
    // phase), and with no player that loop never ended: this pill lives in the bar's
    // full-screen surface, so moving six 3px bars redrew the whole window at the
    // panel's refresh rate — 165 fps, all day, whenever nothing was playing. Measured
    // as one of the two render threads that kept the shell busy at idle.
    readonly property var waveLevels: Cava.idleWave(root.barCount)

    readonly property var displayBars: root.hasPlayer && !root.frozen ? root.bars : root.waveLevels

    // Content-driven, same as ClockPill — the track line's own width is capped
    // (maxTextWidth above) but not pinned, so a short title doesn't drag the
    // spectrum away from it. The pill resizes with the Row (Behavior above softens
    // it), the same way it already does when the lyrics badge appears or vanishes.
    readonly property int mediaWidth: Math.ceil(mediaContent.implicitWidth) + Tokens.pillPadding * 2

    IconButton {
        id: pill
        container: false
        height: Config.barPillHeight
        width:  root.mediaWidth
        Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

        squareMode: Config.barShape
        active:     root.active
        clip:       true

        // Opens the Now Playing panel — see Bar.qml's onToggled wiring.
        onClicked: root.toggled()

        // The desktop cava background, relocated here from left-click now that
        // left-click opens the panel. Still a real, reachable feature — and the
        // panel's own header carries the same toggle for anyone who'd rather not
        // remember a right-click.
        onRightClicked: Config.cavaBg = !Config.cavaBg

        // Scroll to nudge THIS PLAYER's own volume — not the whole sink. A media pill
        // scrolled at 2am to turn Spotify down should not also turn down whatever else
        // is making noise, and stepping the master was the wrong verb for a widget whose
        // entire premise is "this one app."
        //
        // Matched via Audio.streamsFor(desktopEntry): the MPRIS player and the PipeWire
        // stream are two different objects for the same process, so there's no volume
        // signal to observe here the way Osd normally works — it only watches the
        // default sink. Told directly instead, with this player's own icon — the real
        // app icon (Icons.pathForAppId, same resolver the per-app mixer rows use) when
        // one resolves, the brand glyph as the fallback Osd already knows how to draw.
        //
        // Falls back to the sink when there's no player, or a player exists but nothing
        // matching is actually in PipeWire yet (paused before its stream opened) — same
        // step VolumePill uses, hinted with the same icon/glyph pair so the fallback OSD
        // still says who it would have been for.
        onScrolled: function(delta) {
            const step = delta > 0 ? 0.05 : -0.05
            const appId = controller.player?.desktopEntry ?? ""
            const nodes = appId ? Audio.streamsFor(appId) : []
            const glyph = controller.player ? MediaSource.sourceGlyph(controller.player) : ""
            const icon  = appId ? Icons.pathForAppId(appId) : ""

            if (nodes.length > 0) {
                for (let i = 0; i < nodes.length; i++)
                    Audio.setNodeVolume(nodes[i], Audio.steppedLevel(Audio.levelOf(nodes[i]), step > 0), false)
                const level = Audio.levelOf(nodes[0])
                const muted = nodes[0].audio ? nodes[0].audio.muted : false
                Osd.show("volume", level, muted || level <= 0,
                         glyph, muted ? "Muted" : Math.round(level * 100) + "%",
                         icon)
                return
            }

            if (controller.player) Osd.hintNextVolume(glyph, icon)
            Audio.stepVolume(step)
        }

        // ── Track + art + spectrum ──────────────────────────────────────────────
        // Album art, the two-line track, then the spectrum — art and spectrum
        // flanking the text the way nucleus's module flanks its one line, but
        // with ClockPill's two-line shape in the middle instead of a single
        // truncated line.
        Row {
            id: mediaContent
            anchors.centerIn: parent
            spacing: Tokens.spacingSm

            // ── Album art ────────────────────────────────────────────────────────
            // Static — see the header comment for why not spinning. Frame +
            // fallback glyph: a faint tile, the cover masked into it once it loads, a music-note glyph in
            // its place until then (or when there's no art at all).
            //
            // A MASK, not `clip: true` — `clip` on a Rectangle clips to its bounding
            // BOX and knows nothing about `radius`, so the artwork kept square
            // corners poking out past the rounded frame. Same bug, same fix, as
            // OverviewNowPlaying's cover (that file's comment calls it the third
            // time it turned up; this is at least the fourth).
            Item {
                id: artFrame
                anchors.verticalCenter: parent.verticalCenter
                // Collapses with the Row (and the pill's width Behavior) the same way
                // the lyrics badge already does when it has nothing to report — no
                // player means no art to show, and a faint empty tile sitting in front
                // of an idle wave would read as broken rather than as "nothing playing".
                visible: root.hasPlayer
                width:  root.ringSize
                height: root.ringSize

                RadialGauge {
                    anchors.fill: parent
                    thickness: root.ringThickness
                    wavy: true
                    flat: !controller.playing
                    accent: root.accent
                    value: root.progress
                }

                Rectangle {
                    id: cover
                    anchors.centerIn: parent
                    width:  root.artSize
                    height: root.artSize
                    radius: width / 2
                    color:  Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)

                    Item {
                        anchors.fill: parent
                        layer.enabled: true
                        layer.smooth: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: artMask
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1.0
                        }

                        Image {
                            anchors.fill: parent
                            source: AlbumArt.hiRes(controller.player?.trackArtUrl ?? "")
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            // Fades in once decoded, so a new cover eases in rather than
                            // popping when its load finishes (it is async, and a remote
                            // cover takes a moment). A Behavior on a discrete status flip
                            // has nothing to chase.
                            opacity: status === Image.Ready ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.enter } }
                            // Without an explicit sourceSize Qt decodes at native resolution and
                            // point-samples the downscale, which is most of why this looked soft
                            // at ~30px — same fix, same reasoning, as OverviewNowPlaying's cover.
                            sourceSize: Qt.size(cover.width * 2, cover.height * 2)
                            mipmap: true
                        }
                    }

                    Item {
                        id: artMask
                        anchors.fill: parent
                        visible: false
                        layer.enabled: true
                        Rectangle {
                            anchors.fill: parent
                            radius: cover.radius
                            color: "white"
                        }
                    }

                    MaterialIcon {
                        anchors.centerIn: parent
                        visible: (controller.player?.trackArtUrl ?? "") === ""
                        name:  "music_note"
                        fill:  0
                        font.pixelSize: Math.round(root.artSize * 0.55)
                        color: Colors.of(QsWindow.window).fgDim
                    }
                }
            }

            // ── Track lines ──────────────────────────────────────────────────────
            // ClockPill's shape: a bold line over a dim one. Width is PINNED to
            // maxTextWidth (not sized to content) — see that property's comment —
            // so a long title elides instead of stretching the pill.
            SwapFade {
                target:   trackLines
                key:      root.trackTitle + "\n" + root.trackArtist
                shownKey: root.shownTitle + "\n" + root.shownArtist
                onSwapped: { root.shownTitle = root.trackTitle; root.shownArtist = root.trackArtist }
            }
            Column {
                id: trackLines
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                visible: root.hasPlayer

                BarLabel {
                    width:   Math.min(implicitWidth, root.maxTextWidth)
                    elide:   Text.ElideRight
                    text:    root.shownTitle
                    color:   root.hero ? root._onHero : root.accent
                }
                StyledText {
                    width:   Math.min(implicitWidth, root.maxTextWidth)
                    elide:   Text.ElideRight
                    text:    root.shownArtist
                    variant: "micro"
                    sizeScale: Config.barFontScale
                    color:   root.hero ? Colors.of(QsWindow.window).alpha(root._onHero, 0.78)
                                       : Colors.of(QsWindow.window).fgDim
                }
            }

            // ── Spectrum ─────────────────────────────────────────────────────────
            // Shared renderer (components/Spectrum.qml). Sized to `barCount * (barW +
            // barGap) - barGap`, which is exactly what Spectrum's derived bar width solves
            // back to `barW` — so these stay 3px bars without the component needing a
            // fixed-width mode.
            Spectrum {
                anchors.verticalCenter: parent.verticalCenter
                width:  root.barCount * (root.barW + root.barGap) - root.barGap
                height: root.maxBarH

                // Grows from the middle both ways — the Dynamic-Island shape — rather
                // than bottom-up. `displayBars` is real cava while something's playing,
                // the idle wave otherwise; the bars don't know or care which.
                centered: true
                levels:   root.displayBars
                barCount: root.barCount
                barGap:   root.barGap
                accent:   root.accent
            }

            // ── Lyrics badge ─────────────────────────────────────────────────────
            // Its own slot in the Row, after the spectrum — not overlaid on a pill
            // corner, which used to clip straight into the bars (the pill's
            // top-right corner was empty chrome back when this was spectrum-only;
            // it's the spectrum's own top edge now). A slot in the flow can't clip
            // into a neighbour that also has a slot in the flow.
            //
            // Check when the lyrics came from the bridge (real syllable timing),
            // cross when the shell fell back to its own NetEase/LRCLIB lookup —
            // identical reasoning and colours to OverviewNowPlaying's lyricsBadge.
            // Reads `Lyrics` straight off the singleton rather than fetching:
            // OverviewLyrics already keeps it live for whatever's playing
            // regardless of whether the overview is open, so this is a free read,
            // not a second lookup. Hidden entirely (and the Row closes the gap
            // around it) whenever there's nothing synced to report.
            Item {
                id: lyricsBadge
                anchors.verticalCenter: parent.verticalCenter
                width:  Math.round(12 * Config.barIconScale)
                height: Math.round(12 * Config.barIconScale)
                visible: Lyrics.hasSynced

                MaterialIcon {
                    anchors.centerIn: parent
                    name: Lyrics.viaBridge ? "check" : "close"
                    font.pixelSize: Math.round(parent.height * 0.9)
                    // The pass/fail green and red, and the Config.colorizeIcons opt-out
                    // that goes with them, live in config/Verdict.qml — OverviewNowPlaying
                    // draws this same fact and had its own copy of both. See that file for
                    // why these two colours must not follow the wallpaper.
                    color:   Verdict.tint(Lyrics.viaBridge)
                    opacity: 0.95
                }
            }
        }

        // Never shown — see the header comment. Only its `player` is used, for
        // the sticky current-player pick.
        MediaController {
            id: controller
            shown: false
        }
    }
}
