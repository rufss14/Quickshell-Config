pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"
import "../../overview"

// ── LyricsWidget ──────────────────────────────────────────────────────────────
// The overview's lyrics card, on the desktop.
//
// It is the SAME component, not a second implementation of it. Everything that card
// learned the hard way — one function owning a row's height, the rendered row correcting
// the layout, glyph positions coming from Qt rather than from measuring text, the wave
// riding one shared animator — would have to be learned again by a copy, and the copy
// would drift from the original the first time either was touched.
//
// ── What a tile has to supply that the overlay did not ────────────────────────
// The card is handed a player and a playhead; in the overview those come from the media
// card sitting next to it, so the two cannot disagree about where the song is. Nothing
// sits next to it here, which is what MediaPosition is for — the same anchor-plus-elapsed
// clock, non-visual, so a lyric and a progress bar on the same desktop still agree.
//
// ── Gated on the tile being LIVE ──────────────────────────────────────────────
// `active` reaches the card and the clock alike. A lyrics card interpolates a playhead
// and animates every letter on screen, per frame — behind a fullscreen window, with the
// desktop not visible, that is pure waste. `frame.live` is already the answer the layer
// computes; this only has to pass it on.
Item {
    id: root

    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.of(QsWindow.window).primary

    // ── Pinning to one player ─────────────────────────────────────────────────
    // Same option, same spelling and same fallback as the Now playing tile: a pin that
    // is not currently running falls through to "whatever is playing" rather than going
    // silent, because a closed browser muting the tile for something else that IS
    // playing is the worse failure.
    MediaPosition {
        id: media
        active: root.active
        pin: root.opts.player ?? ""
        // Held still while the card's seek bar is being dragged, or its 500ms re-read
        // fights the drag and the handle snaps back.
        scrubbing: lyricsCard.scrubbing
    }

    // ── Which palette ─────────────────────────────────────────────────────────
    // "album" (the default, matching the overlay) or "wallpaper". Both are defensible:
    // the album palette makes the tile part of what is PLAYING, the wallpaper palette
    // makes it part of the DESKTOP. On a busy wallpaper the second usually wins, because
    // a cover's colours have nothing to do with what is behind the tile.
    readonly property bool albumColours: (root.opts.colors ?? "album") !== "wallpaper"


    // ── Nothing to read: show the empty state ────────────────────────────────
    // Show "No lyrics found" with Spotify logo when there's no lyrics for the track.
    property bool hidden: media.player === null

    // The cards render NOTHING when no player exists — right for the overlay, where an
    // empty card would be a hole in the layout, but a tile has a frame that stays either
    // way and would just sit blank. The old tile said so; this keeps saying so.
    WidgetEmpty {
        visible: media.player === null
        glyph: "󰲹"
        text: Translation.tr("Nothing playing")
    }

    OverviewLyrics {
        id: lyricsCard
        anchors.fill: parent
        visible: media.player !== null

        player:   media.player
        position: media.pos

        // NOT the overlay's state. The card defaults `active` to UiState.overviewOpen,
        // which for a desktop tile is exactly backwards — the overview being open means
        // this tile is COVERED.
        active: root.active

        // ── The tile's own background (2026-10-30) ────────────────────────────
        // The card no longer brings a surface: it was a bare tile wearing the overview
        // card's fill (the cover's shadow, the art wash, its own accent rim and radius),
        // so it never matched the tiles around it. Now the tile is framed like every other
        // (catalogue: not bare) and the card draws nothing behind the words — the media
        // panel's lyrics already work this way (PanelLyrics), and the colours stay the
        // cover's MATCHED set over it: text and lit word from one palette, never the
        // palette's text with the album's accent (that mix is what came out wrong there).
        //
        // `tintBg` is still the tile's tone, because the card uses it as the ground of its
        // track card; its own fill is turned off with `color`.
        color:       "transparent"
        tintBg:      Colors.of(QsWindow.window).surfaceContainer
        tintFg:      root.albumColours ? AlbumArt.fg      : Colors.of(QsWindow.window).fg
        tintFgDim:   root.albumColours ? AlbumArt.fgDim   : Colors.of(QsWindow.window).fgDim
        tintFgMuted: root.albumColours ? AlbumArt.fgMuted : Colors.of(QsWindow.window).fgMuted
        // The accent comes from the FRAME in wallpaper mode, so a tile given its own accent
        // in Settings keeps it rather than being overruled by the shell primary.
        tintAccent:  root.albumColours ? AlbumArt.accent  : root.accent
        artWash:     false
        frameWidth:  0
        castsShadow: false
        cornerRadius: 0

        // The card's optional dressing, per tile (Settings › Desktop › Widgets).
        showTrack: root.opts.track ?? true
        // Show the "No lyrics found" empty state when a track has no lyrics.
        showEmpty: true
        // The card's own edge fade paints `tintBg` over the rows, which can't match a
        // translucent or glass tile. Dissolved by transparency instead — PanelLyrics' mask.
        edgeFade:  false
        layer.enabled: root.opts.fade ?? true
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: fadeMask
        }
    }

    // The fade: opaque in the middle, clear at the top and bottom edges.
    Item {
        id: fadeMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        readonly property real edge: Math.min(0.45, (Tokens.spacingXl * 2) / Math.max(1, height))
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0;                 color: "transparent" }
                GradientStop { position: fadeMask.edge;       color: "white" }
                GradientStop { position: 1.0 - fadeMask.edge; color: "white" }
                GradientStop { position: 1.0;                 color: "transparent" }
            }
        }
    }
}
