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

// ── OverviewLyricsTrackCard ── part of OverviewLyrics.qml; `lyrics` is the OverviewLyrics it belongs to. ──
Rectangle {
    id: trackCard
    required property var lyrics
    readonly property bool shown: lyrics._trackOn && (lyrics.content._announce || lyrics.cardHover.hovered)
    z: 4
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.topMargin: Tokens.spacingMd
    anchors.leftMargin: Tokens.spacingMd
    width: Math.min(trackRow.implicitWidth + Tokens.spacingSm * 2 + Tokens.spacingXs,
                    parent.width - Tokens.spacingMd * 2)
    height: trackRow.implicitHeight + Tokens.spacingSm * 2
    radius: Tokens.corner(Config.barShape, Tokens.radiusSm)
    color: Colors.of(QsWindow.window).alpha(lyrics.tintBg, 0.86)
    border.width: Tokens.borderWidth
    border.color: Colors.of(QsWindow.window).alpha(lyrics.tintFg, 0.12)

    // Arrives in a small spring from above and leaves faster than it came, so it
    // never lingers over the line you are reading.
    property real rise: shown ? 1 : 0
    Behavior on rise {
        NumberAnimation {
            duration: trackCard.shown ? Motion.spatial : Motion.fast
            easing.bezierCurve: trackCard.shown ? Motion.spring : Motion.emphasizedDecel
            easing.type: Easing.BezierSpline
        }
    }
    opacity: Math.min(1, rise)
    visible: rise > 0.01
    transform: Translate { y: (1 - trackCard.rise) * -Tokens.spacingMd }

    RowLayout {
        id: trackRow
        anchors.fill: parent
        anchors.margins: Tokens.spacingSm
        spacing: Tokens.spacingSm

        // The cover, when there is one; a note when there is not.
        Rectangle {
            Layout.preferredWidth: Tokens.iconXl
            Layout.preferredHeight: Tokens.iconXl
            radius: Tokens.corner(Config.barShape, Tokens.radiusXs + 2)
            color: Colors.of(QsWindow.window).alpha(lyrics.tintAccent, 0.18)
            clip: true
            Image {
                id: trackArt
                anchors.fill: parent
                source: lyrics.player?.trackArtUrl ?? ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                // Drawn at 28px; there is no reason to decode a 640px cover for it.
                sourceSize: Qt.size(Tokens.iconXl * 2, Tokens.iconXl * 2)
                visible: status === Image.Ready
            }
            MaterialIcon {
                anchors.centerIn: parent
                visible: trackArt.status !== Image.Ready
                name: "music_note"
                variant: "caption"
                color: lyrics.tintAccent
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                Layout.maximumWidth: Tokens.iconXl * 7
                text: lyrics.player?.trackTitle ?? ""
                variant: "caption"
                font.bold: true
                color: lyrics.tintFg
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                Layout.maximumWidth: Tokens.iconXl * 7
                visible: text !== ""
                text: lyrics.player?.trackArtist ?? ""
                variant: "caption"
                color: lyrics.tintFgDim
                elide: Text.ElideRight
            }
        }
    }
}
