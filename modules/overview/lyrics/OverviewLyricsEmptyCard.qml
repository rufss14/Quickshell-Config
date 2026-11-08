import QtQuick
import Quickshell
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/lyricsmotion.js" as LyricMotion
import "../../../services/romajialign.js" as RomajiAlign
import "../../../services/mediasource.js" as MediaSource
import "../../../services/clockfmt.js" as ClockFmt
import "../../../state"
import "../lyrics"

// ── OverviewLyricsEmptyCard ── part of OverviewLyrics.qml; `lyrics` is the OverviewLyrics it belongs to. ──
Item {
    id: emptyCard
    required property var lyrics
    anchors.fill: parent
    visible: lyrics.emptyShown && lyrics.showEmpty

    readonly property bool isSpotify: (lyrics.player?.desktopEntry ?? "") === "spotify"
    readonly property bool failed: Lyrics.state === "error" || Lyrics.state === "none"

    // The reason, held (`vState`) so a change — looking → instrumental, say — fades
    // instead of cutting (SwapFade).
    readonly property var state_: {
        const st = Lyrics.state
        if (st === "loading")      return { text: Lyrics.loadingText, sub: Lyrics.loadingSub }
        if (st === "instrumental") return { text: "Instrumental", sub: "" }
        if (st === "idle")         return { text: "Lyrics off", sub: "" }
        if (lyrics.blocked === "connecting") return { text: "Connecting to Spotify…", sub: "" }
        if (lyrics.blocked === "waiting")
            return { text: "Waiting for Spotify",
                     sub: "Fallback lookup is off, so lyrics come only from the Spotify bridge" }
        return { text: "Unable to fetch lyrics", sub: "" }
    }
    property var vState: ({ text: "", sub: "" })
    Component.onCompleted: vState = state_

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width - Tokens.spacingXl * 2
        spacing: Tokens.spacingMd

        // Spotify's own mark (a brand glyph, QuicktestGlyphs) in the card's accent —
        // the cover's, which AlbumArt turns Spotify green on a colourless cover.
        MaterialIcon {
            Layout.alignment: Qt.AlignHCenter
            glyph: emptyCard.isSpotify ? "\u{F04C7}" : ""                // 󰓇 spotify
            name:  emptyCard.isSpotify ? "" : "music_note"
            fill: 1
            font.pixelSize: Math.round(Tokens.iconXl * 2.2)
            color: lyrics.tintAccent
            opacity: emptyCard.failed ? 0.6 : 1
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: stateCol.implicitHeight
            SwapFade {
                target: stateCol
                key: emptyCard.state_.text
                shownKey: emptyCard.vState.text
                travel: Tokens.spacingXs
                onSwapped: emptyCard.vState = emptyCard.state_
            }
            ColumnLayout {
                id: stateCol
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Tokens.spacingXs
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: emptyCard.vState.text
                    variant: "label"
                    font.weight: Font.Medium
                    color: lyrics.tintFg
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: emptyCard.vState.sub !== ""
                    horizontalAlignment: Text.AlignHCenter
                    text: emptyCard.vState.sub
                    variant: "micro"
                    color: lyrics.tintFgDim
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
