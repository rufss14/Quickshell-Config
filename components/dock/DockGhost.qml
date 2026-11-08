pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Pipewire
import "../../config"
import "../../services"
import "../../state"
import "../../services/dock.js" as DockJs
import "../../services/workspaces.js" as Wsp
import ".."
import "."

// DockGhost — DockIconStrip's inline `Ghost`, moved into its own file (2026-11-08).
// ── A leaving app's copy (root._leave) ────────────────────────────────────
// Its icon where the button stood, sinking to 60% and fading on the exit
// curve, then removing itself.
Item {
    id: ghost
    // The DockIconStrip this belongs to (its state and its actions; was `root`).
    required property var strip
    required property int    uid
    required property string iconPath
    required property real   gx
    required property real   gy

    x: ghost.gx
    y: ghost.gy
    width:  strip.button
    height: strip.button

    Image {
        anchors.centerIn: parent
        visible: ghost.iconPath !== ""
        source: ghost.iconPath
        width:  strip.iconPx
        height: strip.iconPx
        sourceSize: Qt.size(strip.iconRaster, strip.iconRaster)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        layer.enabled: strip.tinted
        layer.textureSize: Qt.size(strip.iconRaster, strip.iconRaster)
        layer.smooth: true
        layer.effect: MonoIconEffect {}
    }

    ParallelAnimation {
        running: true
        onFinished: strip._ghostDone(ghost.uid)
        NumberAnimation { target: ghost; property: "opacity"; from: 1; to: 0
                          duration: Motion.exit; easing.type: Motion.exitCurve }
        NumberAnimation { target: ghost; property: "scale"; from: 1; to: 0.6
                          duration: Motion.exit; easing.type: Motion.exitCurve }
    }
}
