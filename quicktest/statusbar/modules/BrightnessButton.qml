import QtQuick
import QtQuick.Layouts
import "../../theming" as T

// ── BrightnessButton ──────────────────────────────────────────────────────────
// Icon-only pill button (consistent with WallpaperButton)
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property bool barShape:       false
    property bool brightnessOpen: false

    signal toggleBrightness()

    implicitHeight: T.Theme.pillHeight
    implicitWidth:  40
    radius: T.Theme.radius(barShape)
    color:  T.Theme.pillBg

    Behavior on radius { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }

    // Accent overlay (open/hover)
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: ma.containsMouse
            ? (root.brightnessOpen ? T.Theme.btnPressBg  : T.Theme.btnHoverBg)
            : (root.brightnessOpen ? T.Theme.btnActiveBg : "transparent")
        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
    }

    Image {
        anchors.centerIn: parent
        source: "../../theming/icons/monitorsmall.svg"
        width: 16; height: 16
        fillMode: Image.PreserveAspectFit
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleBrightness()
    }
}
