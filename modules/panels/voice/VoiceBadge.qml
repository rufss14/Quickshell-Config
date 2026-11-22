import QtQuick
import Quickshell
import "../../../config"
import "../../../components"

// ── VoiceBadge ── a badge on VoiceIslandHero's loud card: the accent with a symbol, in a shape that blooms on a
// spring (IslandBadge's look, kept here so the panels directory does not reach into the islands'). ─────────────
Item {
    id: badge
    property string symbol: ""
    property string shape: "circle"
    property real size: Tokens.iconXl + Tokens.spacingMd
    readonly property var palette: Colors.of(QsWindow.window)

    implicitWidth: badge.size
    implicitHeight: badge.size

    MorphShape {
        anchors.fill: parent
        shape: badge.shape
        spec: Motion.springSpatialFast
        fillColor: badge.palette.primary
    }
    MaterialIcon {
        anchors.centerIn: parent
        name: badge.symbol
        fill: 1
        font.pixelSize: Math.round(badge.size * 0.46)
        color: badge.palette.fgOnPrimary
    }
}
