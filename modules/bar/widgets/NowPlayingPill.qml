import QtQuick
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"

// ── NowPlayingPill ────────────────────────────────────────────────────────────
// Now playing on the bar (the user's pick, 2026-11-08: "cover and controls"): the
// sidebar's cell — the cover in a cookie that turns with the beat, in its wavy progress
// ring (SideNowPlaying, drawn by SideModulePill at the bar's size) — then previous,
// play/pause and next. The cover is the module; the three buttons are what the sidebar
// does with a middle-click and a scroll, spelled out where a bar has the room.
//
//   cover    click: the media panel   middle: play/pause   right: Settings
//   buttons  previous · play/pause · next (disabled when the player can't)
// ─────────────────────────────────────────────────────────────────────────────
Row {
    id: root

    property var screen: null
    property string moduleId: "nowplaying"

    readonly property var player: MusicPulse.player
    readonly property color accent: Config.moduleAccent("nowplaying", Colors.of(QsWindow.window).primary)

    spacing: 0

    SideModulePill {
        moduleId: "nowplaying"
        screen: root.screen
        anchors.verticalCenter: parent.verticalCenter
    }
    BarIconPill {
        moduleId: "nowplaying"
        anchors.verticalCenter: parent.verticalCenter
        symbol: "skip_previous"
        interactive: root.player?.canGoPrevious ?? false
        opacity: interactive ? 1 : 0.4
        onClicked: root.player?.previous()
    }
    BarIconPill {
        moduleId: "nowplaying"
        anchors.verticalCenter: parent.verticalCenter
        symbol: MusicPulse.playing ? "pause" : "play_arrow"
        symbolFill: 1
        interactive: root.player !== null
        opacity: interactive ? 1 : 0.4
        onClicked: root.player?.togglePlaying()
    }
    BarIconPill {
        moduleId: "nowplaying"
        anchors.verticalCenter: parent.verticalCenter
        symbol: "skip_next"
        interactive: root.player?.canGoNext ?? false
        opacity: interactive ? 1 : 0.4
        onClicked: root.player?.next()
    }
}
