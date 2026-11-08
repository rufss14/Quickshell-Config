import QtQuick
import Quickshell
import "../../config"
import "../../components"

// ── HudFace ───────────────────────────────────────────────────────────────────
// One person in a Discord call (a services/Discord `users` entry): their picture, a ring
// that lights (and a second that ripples out) while they talk, the picture leaning in, and
// a small mic-off badge when they can't be heard. The voice card and the over-game voice widget both draw people with it.
//
// The ring is the palette's focus colour, not Discord's green — that green is a brand
// constant scoped to the call bar, and the list of those doesn't grow (CLAUDE.md;
// SideVoice says the same).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property var person: null
    property int size: Tokens.iconXl + Tokens.spacingMd
    // The ripple runs only while the surface showing this is up.
    property bool running: true

    readonly property var pal: Colors.of(QsWindow.window)
    readonly property bool speaking: root.person?.speaking ?? false
    readonly property bool muted: (root.person?.selfMute ?? false) || (root.person?.serverMute ?? false)
                                || (root.person?.selfDeaf ?? false) || (root.person?.serverDeaf ?? false)

    implicitWidth: root.size
    implicitHeight: root.size

    // While they talk: a ring that ripples out and fades, on a steady beat (Discord says only
    // THAT someone talks, not how loud). Hidden, not stopped mid-way, when they stop.
    Rectangle {
        id: ripple
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.width: Tokens.borderChrome
        border.color: root.pal.focus
        visible: root.speaking && root.running && Config.motionEnabled
        opacity: 0
        ParallelAnimation {
            running: ripple.visible
            loops: Animation.Infinite
            NumberAnimation { target: ripple; property: "scale"; from: 1; to: 1.45; duration: Motion.pulse * 2; easing.type: Motion.travel }
            NumberAnimation { target: ripple; property: "opacity"; from: 0.7; to: 0; duration: Motion.pulse * 2; easing.type: Motion.travel }
        }
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: -Tokens.borderChrome - 1
        radius: width / 2
        color: "transparent"
        border.width: Tokens.borderChrome
        border.color: root.pal.focus
        opacity: root.speaking ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
    }

    Avatar {
        anchors.centerIn: parent
        width: root.size
        height: root.size
        source: root.person?.avatar ?? ""
        name: root.person?.name ?? ""
        opacity: root.muted ? 0.5 : 1
        SpringValue { id: speakLean; target: root.speaking ? 1.06 : 1; spec: Motion.springSpatialFast; epsilon: 0.001 }
        scale: speakLean.value
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
    }

    Rectangle {
        visible: root.muted
        width: Math.round(root.size * 0.42)
        height: width
        radius: width / 2
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: -Tokens.spacingXs
        color: root.pal.surfaceHigh
        border.width: Tokens.borderWidth
        border.color: root.pal.outline
        MaterialIcon {
            anchors.centerIn: parent
            name: "mic_off"
            font.pixelSize: Math.max(Tokens.fontMicro, Math.round(parent.width * 0.62))
            color: root.pal.danger
        }
    }
}
