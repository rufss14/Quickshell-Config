import QtQuick
import QtQuick.Layouts
import "../../../config"

// The toolbar a sub-view (browser, renderer options, scene properties) puts where the gallery's search
// row was. It slides in from the side the view goes deeper from and fades up when it appears, so a view
// change is a move and not a cut (the body below does the same: WallpaperPanel `_enterBody`).
RowLayout {
    id: bar

    // 1 = deeper (comes in from the right), -1 = back (from the left).
    property int dir: 1

    Layout.fillWidth: true
    Layout.fillHeight: false
    spacing: Tokens.spacingSm

    transform: Translate { id: shift }

    onVisibleChanged: if (bar.visible && Config.motionEnabled) enter.restart()
    ParallelAnimation {
        id: enter
        NumberAnimation { target: bar; property: "opacity"; from: 0; to: 1; duration: Motion.spatial; easing.type: Motion.travel }
        NumberAnimation { target: shift; property: "x"; from: bar.dir * 28; to: 0; duration: Motion.spatial; easing.type: Motion.overshoot; easing.overshoot: 1.1 }
    }
}
