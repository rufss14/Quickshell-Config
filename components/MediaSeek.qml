import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import "../config"
import "../services"
import "../services/clockfmt.js" as ClockFmt
// ── MediaSeek ─────────────────────────────────────────────────────────────────
// The Now Playing panel's seek: a WaveSlider whose wave swells with what's coming out of
// the speakers, and the time either side under it. Shared with the overview's island so
// the two draw one bar. `track` is the caller's MediaPosition: `onMoved` sets its `pos`
// straight away (the handle tracks a drag 1:1 instead of waiting for MPRIS to echo the
// seek), and the caller binds its `scrubbing` to `pressed`, which holds MediaPosition's
// own re-read off until the drag ends — without that the re-read fights the drag and the
// handle snaps back. `live` gates the speaker meter (a hidden Item still runs).
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root

    required property var track
    property color accent: Colors.of(QsWindow.window).primary
    property bool live: true
    readonly property alias pressed: wave.pressed

    spacing: Tokens.spacingXs

    PwNodePeakMonitor {
        id: peak
        node: Audio.sink
        enabled: root.live && root.track.playing && Audio.ready
    }

    WaveSlider {
        id: wave
        Layout.fillWidth: true
        enabled: root.track.player?.canSeek ?? false
        value: root.track.pos
        maximum: Math.max(1, root.track.length)
        accent: root.accent
        level: root.track.playing ? Audio.meterLevel(peak.peak) : 0
        smoothHandle: false
        onMoved: function (v) {
            root.track.pos = v
            if (root.track.player) root.track.player.position = v
        }
        onScrolled: function (d) {
            const v = Math.max(0, Math.min(root.track.length, root.track.pos + d * 5))
            root.track.pos = v
            if (root.track.player) root.track.player.position = v
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        StyledText {
            text: ClockFmt.clock(root.track.pos)
            variant: "caption"
            emphasis: "dim"
            font.family: Tokens.fontMono
        }
        Item { Layout.fillWidth: true }
        StyledText {
            text: ClockFmt.clock(root.track.length)
            variant: "caption"
            emphasis: "dim"
            font.family: Tokens.fontMono
        }
    }
}
