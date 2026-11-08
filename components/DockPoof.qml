import QtQuick
import Quickshell
import "../config"

// ── DockPoof ──────────────────────────────────────────────────────────────────
// The little burst where an icon dragged off the dock is let go — macOS's "poof"
// — so unpinning reads as a thing that happened, not just an icon fading out of
// a row. The strip reports where (DockIconStrip.unpinnedAt); a host that can
// draw OUTSIDE the dock plays it here. Fill the host with it.
//
// With motion off every duration is 0, so it simply doesn't show.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property real cx: 0
    property real cy: 0
    property string iconPath: ""

    function play(x, y, icon) {
        root.cx = x
        root.cy = y
        root.iconPath = icon
        burst.restart()
    }

    // The icon's size where it left: the dock's own, unless the host's differs
    // (the sidebar's dock is bar-sized).
    property int size: Config.dockIconPx

    // The icon itself, swelling and fading as it goes.
    Image {
        id: puff
        x: root.cx - width / 2
        y: root.cy - height / 2
        width:  root.size
        height: root.size
        sourceSize: Qt.size(root.size, root.size)
        source: root.iconPath
        visible: opacity > 0.01 && root.iconPath !== ""
        opacity: 0
    }

    // A ring breaking outward from where it was.
    Rectangle {
        id: ring
        x: root.cx - width / 2
        y: root.cy - height / 2
        width:  root.size
        height: root.size
        radius: width / 2
        color: "transparent"
        border.width: Tokens.borderChrome
        border.color: Colors.of(QsWindow.window).fgMuted
        visible: opacity > 0.01
        opacity: 0
    }

    ParallelAnimation {
        id: burst
        NumberAnimation { target: puff; property: "opacity"; from: 1; to: 0
                          duration: Motion.emphasized; easing.type: Motion.exitCurve }
        NumberAnimation { target: puff; property: "scale"; from: 1; to: 1.5
                          duration: Motion.emphasized; easing.type: Motion.enter }
        NumberAnimation { target: ring; property: "opacity"; from: 0.8; to: 0
                          duration: Motion.emphasized; easing.type: Motion.exitCurve }
        NumberAnimation { target: ring; property: "scale"; from: 0.6; to: 2.2
                          duration: Motion.emphasized; easing.type: Motion.enter }
    }
}
