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

// ── OverviewLyricsVideoCard ── part of OverviewLyrics.qml; `lyrics` is the OverviewLyrics it belongs to. ──
Item {
    id: videoCard
    required property var lyrics
    anchors.fill: parent

    // In and out on a spring, like everything else that arrives here.
    property real appear: lyrics.sourceBlocked ? 1 : 0
    Behavior on appear {
        NumberAnimation {
            duration: Motion.spatial
            easing.bezierCurve: Motion.spring
            easing.type: Easing.BezierSpline
        }
    }
    visible: appear > 0.01
    opacity: Math.min(1, appear)

    readonly property var brand: AlbumArt.brandOf(MediaSource.idOf(lyrics.player))
    readonly property color tone: videoCard.brand ? videoCard.brand.accent : lyrics.tintAccent
    readonly property bool playing: lyrics.player?.isPlaying ?? false
    // Show the control while paused, and on hover while playing: always drawn over
    // a video it is a watermark.
    readonly property bool showControl: posterMouse.containsMouse || !videoCard.playing
    // A browser often reports no length, and a position stuck at 0 — a progress
    // line off that would sit empty and mean nothing, so none is drawn then.
    readonly property real len: (lyrics.player?.lengthSupported ?? false) ? (lyrics.player?.length ?? 0) : 0

    // The words are a held copy so a video ending into the next one fades instead
    // of cutting (SwapFade).
    property string vTitle: ""
    property string vChannel: ""
    property string vKey: ""
    function _sync() {
        vTitle   = lyrics.player?.trackTitle  ?? ""
        vChannel = lyrics.player?.trackArtist ?? ""
        vKey     = vTitle + "::" + vChannel
    }
    Component.onCompleted: _sync()

    // ── The poster ────────────────────────────────────────────────────
    // A brand-tinted ground first, so a player that gives no thumbnail still gets a
    // filled tile rather than a hole.
    Rectangle {
        anchors.fill: parent
        color: Colors.of(QsWindow.window).alpha(videoCard.tone, 0.16)
    }
    MaterialIcon {
        anchors.centerIn: parent
        visible: poster.status !== Image.Ready
        glyph: MediaSource.sourceGlyph(lyrics.player)
        font.pixelSize: Tokens.fontNumeralLg * 2
        color: Colors.of(QsWindow.window).alpha(videoCard.tone, 0.25)
    }
    Image {
        id: poster
        anchors.fill: parent
        source: AlbumArt.hiRes(lyrics.player?.trackArtUrl ?? "")
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        // Fills a tile at most a few hundred px wide.
        sourceSize: Qt.size(Tokens.iconXl * 16, Tokens.iconXl * 16)
        visible: status === Image.Ready
        // Pulled back a little under the control so it reads on any frame.
        opacity: videoCard.showControl ? 0.7 : 1
        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
    }

    // The scrim: the card's own colour rising from the bottom, so the text always
    // has something to sit on whatever the frame is.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: parent.height * 0.75
        gradient: Gradient {
            GradientStop { position: 0.0; color: Colors.of(QsWindow.window).alpha(lyrics.tintBg, 0) }
            GradientStop { position: 1.0; color: Colors.of(QsWindow.window).alpha(lyrics.tintBg, 0.94) }
        }
    }
    // …and a light one across the top, behind the logo.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Tokens.iconXl * 2
        gradient: Gradient {
            GradientStop { position: 0.0; color: Colors.of(QsWindow.window).alpha(lyrics.tintBg, 0.6) }
            GradientStop { position: 1.0; color: Colors.of(QsWindow.window).alpha(lyrics.tintBg, 0) }
        }
    }

    // Along the bottom edge, when the player says how far through it is.
    Rectangle {
        visible: videoCard.len > 0
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        height: Tokens.spacingXs
        width: parent.width * Math.max(0, Math.min(1, lyrics.position / videoCard.len))
        color: videoCard.tone
    }

    // ── The mark ──────────────────────────────────────────────────────
    RowLayout {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: Tokens.spacingMd
        anchors.leftMargin: Tokens.spacingLg
        spacing: Tokens.spacingSm

        MaterialIcon {
            glyph: MediaSource.sourceGlyph(lyrics.player)
            font.pixelSize: Tokens.iconXl
            color: videoCard.tone
        }
        StyledText {
            text: MediaSource.resolve(lyrics.player).name
            variant: "label"
            font.bold: true
            color: lyrics.tintFg
        }
    }

    // Why there are no lyrics, as a pill rather than a paragraph.
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Tokens.spacingMd
        anchors.rightMargin: Tokens.spacingLg
        implicitWidth: noLyrics.implicitWidth + Tokens.spacingMd * 2
        implicitHeight: noLyrics.implicitHeight + Tokens.spacingSm * 2
        width: implicitWidth
        height: implicitHeight
        radius: Tokens.corner(Config.barShape, Tokens.radiusSm)
        color: Colors.of(QsWindow.window).alpha(lyrics.tintBg, 0.7)
        RowLayout {
            id: noLyrics
            anchors.centerIn: parent
            spacing: Tokens.spacingXs
            MaterialIcon { name: "lyrics"; variant: "caption"; color: lyrics.tintFgMuted }
            StyledText { text: "No lyrics for videos"; variant: "caption"; color: lyrics.tintFgMuted }
        }
    }

    // ── Play / pause ──────────────────────────────────────────────────
    Rectangle {
        anchors.centerIn: parent
        width: Tokens.iconXl * 2
        height: width
        radius: width / 2
        color: Colors.of(QsWindow.window).alpha(lyrics.tintBg, 0.78)
        border.width: Tokens.borderWidth
        border.color: Colors.of(QsWindow.window).alpha(lyrics.tintFg, 0.2)
        opacity: videoCard.showControl ? 1 : 0
        scale: posterMouse.pressed ? 0.9 : (videoCard.showControl ? 1 : 0.8)
        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
        Behavior on scale {
            NumberAnimation {
                duration: posterMouse.pressed ? Motion.respond : Motion.spatial
                easing.bezierCurve: Motion.spring
                easing.type: Easing.BezierSpline
            }
        }
        MaterialIcon {
            anchors.centerIn: parent
            name: videoCard.playing ? "pause" : "play_arrow"
            fill: 1
            font.pixelSize: Tokens.iconXl
            color: lyrics.tintFg
        }
    }

    // ── What it is ────────────────────────────────────────────────────
    ColumnLayout {
        id: videoText
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Tokens.spacingLg
        anchors.rightMargin: Tokens.spacingLg
        anchors.bottomMargin: Tokens.spacingLg
        spacing: Tokens.spacingXs

        SwapFade {
            target: videoText
            key: (lyrics.player?.trackTitle ?? "") + "::" + (lyrics.player?.trackArtist ?? "")
            shownKey: videoCard.vKey
            onSwapped: videoCard._sync()
        }

        // A video title is a sentence, not a track name: two lines before it gives up.
        StyledText {
            Layout.fillWidth: true
            text: videoCard.vTitle
            variant: "label"
            font.bold: true
            color: lyrics.tintFg
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
        StyledText {
            Layout.fillWidth: true
            visible: videoCard.vChannel !== ""
            text: videoCard.vChannel
            variant: "caption"
            color: lyrics.tintFgMuted
            elide: Text.ElideRight
        }
    }

    // Click anywhere on the poster to play or pause.
    MouseArea {
        id: posterMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: lyrics.player?.togglePlaying()
    }
}
