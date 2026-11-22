import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── StreamPill ────────────────────────────────────────────────────────────────
// "Streaming", with the icon of the app that is capturing the screen. Present only
// while a capture is running (StreamMode.live): an indicator that is always there
// stops being read, and this one exists to say "what you do now is being seen".
//
// Manual stream mode (Config.streamMode, from the launcher or settings) hides the pill
// like everything else about it: the switch lives where it is set.
//
// Click turns stream mode OFF (StreamMode.suspended = Config.streamOff): the capture goes on, the
// hiding stops, so viewers can see a notification you need to show. It is remembered, across
// captures and shell loads, so the next stream does not turn it back on by itself; the pill still
// shows while a capture runs. The text is struck through and the label goes grey; click again to
// turn it on. The app icon follows Config.colorizeIcons (grey when on), like the tray's and the dock's. The tooltip (ModuleGlance) says what is
// hidden, or that it is paused, and whether the Hyprland rules are installed.
//
// Shaped like WindowPill: an app icon, a label, one row centred in a BarIconPill.
// ─────────────────────────────────────────────────────────────────────────────
BarIconPill {
    id: root

    moduleId: "stream"
    iconColor: StreamMode.suspended ? Colors.of(QsWindow.window).stateIdleFg : accent
    visible: StreamMode.live
    active: !StreamMode.suspended
    onClicked: StreamMode.toggleSuspend()
    implicitWidth: Math.ceil(row.implicitWidth) + Tokens.pillPadding * 2

    readonly property string iconPath: StreamMode.sourceNode ? Audio.iconPathFor(StreamMode.sourceNode) : ""

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Tokens.spacingSm

        Image {
            Layout.alignment: Qt.AlignVCenter
            visible: root.iconPath !== ""
            source: root.iconPath
            sourceSize: Qt.size(root.iconSize, root.iconSize)
            Layout.preferredWidth: root.iconSize
            Layout.preferredHeight: root.iconSize
            fillMode: Image.PreserveAspectFit
            smooth: true
            asynchronous: true
            layer.enabled: Config.colorizeIcons
            layer.effect: MonoIconEffect {}
        }
        // No resolvable app icon (an app with no desktop entry): the stream glyph instead.
        MaterialIcon {
            visible: root.iconPath === ""
            name: "videocam"
            color: root.iconColor
            font.pixelSize: root.iconSize
        }
        Text {
            Layout.alignment: Qt.AlignVCenter
            text: Translation.tr("Streaming")
            color: root.iconColor
            font.family: Tokens.fontFamily
            font.pixelSize: root.labelSize
            font.weight: Font.Medium
            font.strikeout: StreamMode.suspended
            Behavior on color { ColorAnimation { duration: Motion.respond } }
        }
    }
}
