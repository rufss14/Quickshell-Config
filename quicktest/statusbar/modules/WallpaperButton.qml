import QtQuick
import QtQuick.Layouts
import "../../theming" as T

// ── WallpaperButton ───────────────────────────────────────────────────────────
// Icon-only button (used in both unified and split modes)
// Uses wallpaper.svg + accent overlay when open
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property bool barShape:      false
    property bool wallpaperOpen: false

    signal toggleWallpaper()

    implicitHeight: T.Theme.pillHeight
    implicitWidth:  40
    radius: T.Theme.radius(barShape)
    color:  T.Theme.pillBg

    Behavior on radius { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }

    // Accent tint overlay when open / hovered
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: ma.containsMouse
            ? (root.wallpaperOpen
                ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.30)
                : T.Theme.hoverAccent)
            : (root.wallpaperOpen
                ? T.Theme.pw(T.Theme.pal?.colors?.color9, 0.18)
                : "transparent")
        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
    }

    Image {
        anchors.centerIn: parent
        source: "../../theming/icons/wallpaper.svg"
        width: 16
        height: 16
        fillMode: Image.PreserveAspectFit
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleWallpaper()
    }
}