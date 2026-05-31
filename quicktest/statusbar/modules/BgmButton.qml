import Quickshell
import QtQuick
import "../../theming" as T
import "../../overlay/modules"  // exposes the Panels singleton

// ── BgmButton ─────────────────────────────────────────────────────────────────
// Status-bar pill that toggles the BGM panel.
// Always shows vinyl.svg — spins while playing.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property bool barShape: false
    property bool bgmOpen:  false

    signal toggleBgm()

    implicitHeight: T.Theme.pillHeight
    implicitWidth:  40
    radius: T.Theme.radius(barShape)
    color:  T.Theme.pillBg

    Behavior on radius { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }

    readonly property bool playing: Panels.bgmIsPlaying

    // Accent tint overlay — mirrors WallpaperButton exactly
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: hov.containsMouse
            ? (root.bgmOpen ? T.Theme.btnPressBg  : T.Theme.btnHoverBg)
            : (root.bgmOpen ? T.Theme.btnActiveBg : "transparent")
        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
    }

    // Vinyl SVG — spins while playing
    Image {
        id: vinylIcon
        anchors.centerIn: parent
        source: "../../theming/icons/vinyl.svg"
        width: 16; height: 16
        fillMode: Image.PreserveAspectFit
        smooth: true

        RotationAnimation on rotation {
            loops:    Animation.Infinite
            from:     0; to: 360
            duration: 3200
            running:  root.playing
        }
    }

    MouseArea {
        id:           hov
        anchors.fill: parent
        hoverEnabled: true
        cursorShape:  Qt.PointingHandCursor
        onClicked:    root.toggleBgm()
    }
}
