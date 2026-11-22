import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"

// ── QueueBackdrop ─────────────────────────────────────────────────────────────
// A queue row's ground, as the wallpaper page's cards have it: the song's own cover, blurred and dim, under a
// horizontal scrim of the album's colour (the left, where the words are, is the strongest). Under the cover sits the
// plain tone, so a row is never empty while its cover loads.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property string image: ""
    // The album's colour (QueuePalettes bg); the scrim is drawn in it.
    property color tint: Colors.of(QsWindow.window).plateLow
    property color base: Colors.of(QsWindow.window).plateLow

    color: root.base
    radius: Tokens.radiusSm

    ClippingRectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        Image {
            anchors.fill: parent
            visible: root.image !== ""
            source: root.image
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            sourceSize.width: 160
            opacity: status === Image.Ready ? 0.62 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.spatial } }
            layer.enabled: opacity > 0
            layer.effect: MultiEffect { blurEnabled: true; blur: 0.7; blurMax: 40; saturation: 0.25 }
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Colors.of(QsWindow.window).alpha(root.tint, 0.8) }
                GradientStop { position: 0.6; color: Colors.of(QsWindow.window).alpha(root.tint, 0.6) }
                GradientStop { position: 1.0; color: Colors.of(QsWindow.window).alpha(root.tint, 0.4) }
            }
        }
    }
}
