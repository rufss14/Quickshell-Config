pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"
import QtQuick.Layouts

// ── NowplayingWidget ──────────────────────────────────────────────────────────
// The overview's media card, on the desktop.
//
// This replaced a second, smaller implementation of the same idea — its own player
// selection, its own art tile, its own transport row. Two of everything is how the tile
// and the card ended up disagreeing about which player was playing, and every fix to the
// card (the sticky selection rule, the seek bar, the source detection that can tell
// YouTube from "a browser") had to be noticed and copied across or it simply was not here.
// One component, three surfaces: overlay, lockscreen, desktop.
//
// The one thing the old tile had that the card did not was `opts.player`, so the card
// grew a `pin` with the same contract rather than the option being quietly dropped.
//
// ── Material 3 Expressive (2026-10-30): composed, not copied ──────────────────
// The tile now draws its own LAYOUT, out of the same shared pieces the overview's island
// and the media panel are built from — so the rule above still holds: nothing about which
// player, where the song is, how to seek or how the transport behaves exists twice.
//   · MediaPosition   which player (with `opts.player` as its pin), and the playhead
//   · CookieCover     the panel's rotating scallop cover with the spectrum ring round it
//   · MediaSeek       the wave seek bar with the times
//   · MediaTransport  the panel's transport row
// Medium: the cookie on the left, the track and controls beside it. Large: the cookie on
// top, big, everything under it. It is a framed tile now (catalogue: no longer bare) —
// the old card brought its own surface, this layout sits on the tile's.
Item {
    id: root

    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.of(QsWindow.window).primary

    // "album" (default): the cover's own colours lead; "wallpaper": the tile's accent.
    readonly property bool albumColours: (root.opts.colors ?? "album") !== "wallpaper"
    readonly property color tone: root.albumColours && AlbumArt.ready ? AlbumArt.accent : root.accent

    MediaPosition {
        id: media
        active: root.active
        pin: root.opts.player ?? ""
        scrubbing: seek.pressed
    }
    readonly property var player: media.player
    // The player's own PipeWire stream, for the cover's spectrum ring (not the shared
    // output, which would dance to a call).
    readonly property string playerNode: {
        if (!root.active || !root.player) return ""
        const nodes = Audio.streamsFor(root.player.desktopEntry ?? "")
        return nodes.length > 0 ? nodes[0].name : ""
    }

    WidgetEmpty {
        visible: root.player === null
        icon: "music_note"
        text: Translation.tr("Nothing playing")
    }

    GridLayout {
        anchors.fill: parent
        visible: root.player !== null
        columns: root.size === "large" ? 1 : 2
        columnSpacing: Tokens.spacingLg
        rowSpacing: Tokens.spacingSm

        CookieCover {
            Layout.preferredWidth: root.size === "large" ? Math.min(parent.width, parent.height * 0.58)
                                                         : parent.height
            Layout.preferredHeight: Layout.preferredWidth
            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
            source: AlbumArt.hiRes(root.player?.trackArtUrl ?? "")
            playing: media.playing
            live: root.active
            nodeName: root.playerNode
            accent: root.tone
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: root.size !== "large"
            Layout.alignment: Qt.AlignVCenter
            spacing: Tokens.spacingXs

            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: root.size === "large" ? Text.AlignHCenter : Text.AlignLeft
                text: (root.player?.trackTitle ?? "") !== "" ? root.player.trackTitle : (root.player?.identity ?? "")
                variant: "title"
                font.weight: Font.Bold
                color: Colors.of(QsWindow.window).fg
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: root.size === "large" ? Text.AlignHCenter : Text.AlignLeft
                visible: text !== ""
                text: root.player?.trackArtist ?? ""
                variant: "label"
                color: root.tone
                elide: Text.ElideRight
            }
            MediaSeek {
                id: seek
                Layout.fillWidth: true
                track: media
                accent: root.tone
                live: root.active
            }
            MediaTransport {
                Layout.alignment: root.size === "large" ? Qt.AlignHCenter : Qt.AlignLeft
                size: root.size === "large" ? 0.9 : 0.7
                player: root.player
                playing: media.playing
                accent: root.tone
            }
        }
    }
}
