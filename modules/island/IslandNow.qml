import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../state"
import "../../components"
import "../../services"

// ── IslandNow ─────────────────────────────────────────────────────────────────
// The Dashboard's player, down its right side: the cover in its turning cookie with the ring of level bars round it
// (CookieCover, as the Now Playing panel draws it), the title, the artist, the Media page's wavy seek (draggable), the
// cookie transport and the player's own volume (as the media panel sets it), all sized to the card. The Media page is the full player. The colour is the visualiser's accent,
// never the player's brand. `media` is the page's MediaPosition (one clock for the page; its `scrubbing` follows the
// seek); nothing ticks while nothing plays, and the ring listens only while this is on screen. The edge is lit by the
// music (`rim`).
// ─────────────────────────────────────────────────────────────────────────────
IslandPlate {
    id: root

    required property var media

    readonly property var player: root.media.player
    // A drag on the seek: the page's MediaPosition holds its re-read off while it lasts.
    readonly property bool scrubbing: seekBar.pressed
    // Does this player say where in the track it is? A browser often doesn't: no bar beats a wrong one.
    readonly property bool hasTiming: (root.media.bridged ?? false)
        || ((root.player?.lengthSupported ?? false) && (root.player?.length ?? 0) > 0)
    readonly property color playerAccent: Config.moduleAccent("visualizer", root.palette.primary)
    readonly property string nodeName: {
        const appId = root.player?.desktopEntry ?? ""
        if (!root.visible || !appId) return ""
        const nodes = Audio.streamsFor(appId)
        return nodes.length > 0 ? nodes[0].name : ""
    }

    rim: true
    clickable: true
    Accessible.name: Translation.tr("Media")
    onClicked: UiState.islandGo("media")

    // ── Nothing playing ───────────────────────────────────────────────────────
    ColumnLayout {
        anchors.centerIn: parent
        visible: root.player === null
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
            variant: "label"
            emphasis: "dim"
        }
    }

    // ── A song ────────────────────────────────────────────────────────────────
    // Sized to the card, never past it: the cover box (the ring of bars stays inside it), two lines, the seek and the
    // transport scaled to what the width holds.
    ColumnLayout {
        id: song
        anchors.fill: parent
        anchors.margins: Tokens.spacingMd
        visible: root.player !== null
        spacing: Tokens.spacingXs

        CookieCover {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: true
            Layout.maximumHeight: Tokens.spacingXl * 8
            Layout.preferredWidth: Math.min(song.width, height)
            source: AlbumArt.hiRes(root.player?.trackArtUrl ?? "")
            playing: root.media.playing
            live: root.visible && root.player !== null
            nodeName: root.nodeName
            accent: root.playerAccent
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.player?.trackTitle || Translation.tr("Unknown")
            variant: "label"
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: -Tokens.spacingXs
            horizontalAlignment: Text.AlignHCenter
            text: root.player?.trackArtist ?? ""
            variant: "caption"
            emphasis: "dim"
            elide: Text.ElideRight
        }

        // The Media page's own seek: drag it (it holds the playhead while you do).
        MediaSeek {
            id: seekBar
            Layout.fillWidth: true
            visible: root.hasTiming
            track: root.media
            accent: root.playerAccent
            live: root.visible && root.hasTiming
        }

        MediaTransport {
            Layout.alignment: Qt.AlignHCenter
            player: root.media.player
            playing: root.media.playing
            accent: root.playerAccent
            // At 1 the row is ~200 wide with its gaps; fit it to the card.
            size: Math.min(0.9, song.width / 220)
        }

        // ── The player's own volume ───────────────────────────────────────────
        // As the media panel does it: the PLAYER's volume (Audio.playerLevel — MPRIS `Volume`, the slider inside
        // Spotify, which lasts the song where its stream does not), falling back to its stream for a player without
        // one. Up to 100%: the panel's boost stays the panel's (a lifted level reads full here, and a drag brings it
        // back under). The speaker mutes and restores; the wheel steps 5%. Dimmed while there is nothing to set.
        RowLayout {
            id: vol
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm
            enabled: vol.has
            opacity: vol.has ? 1 : 0.45

            readonly property string appId: root.player?.desktopEntry ?? ""
            readonly property bool has: Audio.hasPlayerVolume(root.player, vol.appId)
            readonly property real level: Math.min(1, Audio.playerLevel(root.player, vol.appId))
            // The level before a mute, for the way back.
            property real before: 0.5
            function apply(v) { Audio.setPlayerLevel(root.player, vol.appId, Math.max(0, Math.min(1, v)), false) }

            MaterialIcon {
                name: vol.level <= 0 ? "volume_off" : vol.level < 0.35 ? "volume_mute" : vol.level < 0.7 ? "volume_down" : "volume_up"
                fill: 1
                font.pixelSize: Tokens.iconMd
                color: hover.hovered ? root.palette.fg : root.palette.fgMuted
                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: {
                        if (vol.level > 0) { vol.before = vol.level; vol.apply(0) }
                        else vol.apply(vol.before > 0 ? vol.before : 0.5)
                    }
                }
                Accessible.role: Accessible.Button
                Accessible.name: vol.level > 0 ? Translation.tr("Mute") : Translation.tr("Unmute")
            }
            ThickSlider {
                Layout.fillWidth: true
                accessibleName: Translation.tr("Player volume")
                maximum: 100
                value: vol.level * 100
                accent: root.playerAccent
                onMoved: v => vol.apply(v / 100)
                onScrolled: d => vol.apply(vol.level + d * 0.05)
            }
            StyledText {
                Layout.preferredWidth: Tokens.spacingXl * 2
                horizontalAlignment: Text.AlignRight
                text: Math.round(vol.level * 100) + "%"
                variant: "micro"
                emphasis: "dim"
                font.features: ({ tnum: 1 })
            }
        }
    }
}
