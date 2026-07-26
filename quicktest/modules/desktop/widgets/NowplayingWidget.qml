pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import Quickshell.Widgets
import "../../../config"
import "../../../components"

// ── NowplayingWidget ──────────────────────────────────────────────────────────
// What's playing, with working transport. The most interactive tile here, and the one
// that most justifies widgets taking input at all.
//
// Player selection copies OverviewNowPlaying's rule rather than inventing a second one:
// hold the last player seen and only switch to a DIFFERENT one that is actually
// playing. Binding to players[0] means a dead browser tab steals the tile the moment
// you pause Spotify.
Item {
    id: root
    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.primary

    property var _player: null
    readonly property var player: root._player
    readonly property bool playing: root.player?.playbackState === MprisPlaybackState.Playing

    function _pick() {
        const all = Mpris.players.values
        for (let i = 0; i < all.length; i++)
            if (all[i].playbackState === MprisPlaybackState.Playing) { root._player = all[i]; return }
        for (let j = 0; j < all.length; j++) if (all[j] === root._player) return
        root._player = all.length > 0 ? all[0] : null
    }
    Component.onCompleted: root._pick()
    Connections { target: Mpris.players; function onValuesChanged() { root._pick() } }
    Connections {
        target: root.player ?? null
        ignoreUnknownSignals: true
        function onPlaybackStateChanged() { root._pick() }
    }

    readonly property bool wide: root.size !== "small"

    StyledText {
        anchors.centerIn: parent
        visible: !root.player
        text: "Nothing playing"
        variant: "caption"
        emphasis: "dim"
    }

    ColumnLayout {
        anchors.fill: parent
        visible: !!root.player
        spacing: Tokens.spacingMd

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingMd

            // Art in a rounded tile. ClippingRectangle so a square cover gets the
            // widget's corner language rather than sitting in it as a hard rectangle.
            ClippingRectangle {
                Layout.preferredWidth:  root.wide ? 64 : 52
                Layout.preferredHeight: Layout.preferredWidth
                Layout.alignment: Qt.AlignVCenter
                radius: Tokens.radiusSm
                color: Colors.alpha(Colors.fg, 0.08)

                Image {
                    anchors.fill: parent
                    source: root.player?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(160, 160)
                    asynchronous: true
                    smooth: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.player?.trackTitle ?? ""
                    variant: "body"
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: root.wide ? 1 : 2
                    wrapMode: root.wide ? Text.NoWrap : Text.Wrap
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.player?.trackArtist ?? ""
                    variant: "caption"
                    emphasis: "muted"
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.size === "large"
                    text: root.player?.trackAlbum ?? ""
                    variant: "caption"
                    emphasis: "dim"
                    elide: Text.ElideRight
                }
            }
        }

        // ── Transport ─────────────────────────────────────────────────────────
        // Guarded on the player's own `can*` flags — a browser that cannot seek should
        // not offer a button that silently does nothing.
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacingLg

            TransportButton {
                glyph: "󰒮"
                enabled: root.player?.canGoPrevious ?? false
                onTapped: root.player.previous()
            }
            TransportButton {
                glyph: root.playing ? "󰏤" : "󰐊"
                big: true
                enabled: root.player?.canTogglePlaying ?? false
                onTapped: root.player.togglePlaying()
            }
            TransportButton {
                glyph: "󰒭"
                enabled: root.player?.canGoNext ?? false
                onTapped: root.player.next()
            }
        }
    }

    component TransportButton: StyledText {
        id: tb
        property string glyph: ""
        property bool big: false
        signal tapped()
        text: tb.glyph
        font.pixelSize: tb.big ? 26 : 19
        color: !tb.enabled ? Colors.fgDim
             : tbMouse.containsMouse ? root.accent : Colors.fg
        MouseArea {
            id: tbMouse
            anchors.fill: parent
            anchors.margins: -5
            hoverEnabled: true
            enabled: tb.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: tb.tapped()
        }
    }
}
