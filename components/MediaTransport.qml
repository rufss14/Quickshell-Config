import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import "../config"

// ── MediaTransport ────────────────────────────────────────────────────────────
// Shuffle · previous · play/pause · next · loop, as scalloped CookieButtons — the Now
// Playing panel's transport, shared so the overview's island draws the SAME controls
// (2026-10-20: "the media panel should look more like the one from the Now Playing
// panel"). shuffle ↔ loop are one mirrored pair (6-point, tilted ∓18°); prev ↔ next
// another (5-point, ∓12°); play is the centre, the one accent-filled control, turning
// while a track plays. `size` scales the whole row (1 = the panel's 32/36/46).
// ─────────────────────────────────────────────────────────────────────────────
RowLayout {
    id: root

    property var player: null
    property bool playing: false
    property color accent: Colors.of(QsWindow.window).primary
    property color chipTint: Colors.of(QsWindow.window).mix(root.accent, Colors.of(QsWindow.window).fg, 0.5)
    property real size: 1

    function _px(n) { return Math.round(n * root.size) }

    spacing: Tokens.spacingSm

    CookieButton {
        Layout.alignment: Qt.AlignVCenter
        visible: root.player?.shuffleSupported ?? false
        primary: true
        glyphOnFill: Colors.of(QsWindow.window).surface
        points: 6
        restTilt: -18
        implicitWidth: root._px(32)
        implicitHeight: root._px(32)
        name: "shuffle"
        checked: root.player?.shuffle ?? false
        tint: (root.player?.shuffle ?? false) ? root.accent : root.chipTint
        onActivated: if (root.player) root.player.shuffle = !root.player.shuffle
    }
    CookieButton {
        Layout.alignment: Qt.AlignVCenter
        primary: true
        glyphOnFill: Colors.of(QsWindow.window).surface
        points: 5
        restTilt: -12
        implicitWidth: root._px(36)
        implicitHeight: root._px(36)
        name: "skip_previous"
        tint: root.chipTint
        enabled: root.player?.canGoPrevious ?? false
        onActivated: root.player?.previous()
    }
    CookieButton {
        Layout.alignment: Qt.AlignVCenter
        primary: true
        glyphOnFill: Colors.of(QsWindow.window).surface
        points: 8
        tint: root.accent
        implicitWidth: root._px(46)
        implicitHeight: root._px(46)
        name: root.playing ? "pause" : "play_arrow"
        spinning: root.playing
        enabled: root.player?.canTogglePlaying ?? false
        onActivated: {
            if (!root.player) return
            if (root.playing) root.player.pause()
            else root.player.play()
        }
    }
    CookieButton {
        Layout.alignment: Qt.AlignVCenter
        primary: true
        glyphOnFill: Colors.of(QsWindow.window).surface
        points: 5
        restTilt: 12
        implicitWidth: root._px(36)
        implicitHeight: root._px(36)
        name: "skip_next"
        tint: root.chipTint
        enabled: root.player?.canGoNext ?? false
        onActivated: root.player?.next()
    }
    // Loop cycles none → playlist → track, and the glyph says which.
    CookieButton {
        Layout.alignment: Qt.AlignVCenter
        visible: root.player?.loopSupported ?? false
        primary: true
        glyphOnFill: Colors.of(QsWindow.window).surface
        points: 6
        restTilt: 18
        implicitWidth: root._px(32)
        implicitHeight: root._px(32)
        name: root.player?.loopState === MprisLoopState.Track ? "repeat_one" : "repeat"
        checked: (root.player?.loopState ?? MprisLoopState.None) !== MprisLoopState.None
        tint: (root.player?.loopState ?? MprisLoopState.None) !== MprisLoopState.None ? root.accent : root.chipTint
        onActivated: {
            if (!root.player) return
            switch (root.player.loopState) {
                case MprisLoopState.None:     root.player.loopState = MprisLoopState.Playlist; break
                case MprisLoopState.Playlist: root.player.loopState = MprisLoopState.Track;    break
                default:                      root.player.loopState = MprisLoopState.None;    break
            }
        }
    }
}
