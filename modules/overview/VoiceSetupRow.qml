import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── VoiceSetupRow ─────────────────────────────────────────────────────────────
// "Hey Claude" on the Ask page's tune panel (services/VoiceAssistant): what it is, where it stands, and
// the one button that moves it on — get the speech model (~40 MB, once), then on/off. Says plainly that
// the microphone stays open while it's on.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property color accent: Colors.of(QsWindow.window).primary

    readonly property string line:
          VoiceAssistant.downloading ? Translation.tr("Getting the speech model…")
        : !VoiceAssistant.modelPresent ? Translation.tr("Needs the English speech model (about 40 MB, once)")
        : VoiceAssistant.state === "error" ? VoiceAssistant.reason
        : !Config.aiVoice ? Translation.tr("Off — the microphone stays closed")
        : Translation.tr("Listening for “%1” — the mic stays open, nothing is recorded").arg(VoiceAssistant.wakeWords[0] || "hey claude")

    // Shown = someone's looking: the model may have arrived since the shell started.
    onVisibleChanged: if (root.visible) VoiceAssistant.recheck()
    Component.onCompleted: VoiceAssistant.recheck()

    implicitHeight: row.implicitHeight + Tokens.spacingMd * 2
    radius: Tokens.radiusCard - Tokens.spacingXs
    color: Colors.of(QsWindow.window).fade(Config.aiVoice && VoiceAssistant.state !== "error"
               ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceContainer, root.accent, 0.12)
               : Colors.of(QsWindow.window).surfaceContainer, 0.9)
    Behavior on color { ColorAnimation { duration: Motion.standard } }

    Item {
        id: row
        x: Tokens.spacingMd
        y: Tokens.spacingMd
        width: root.width - Tokens.spacingMd * 2
        implicitHeight: Math.max(chip.height, words.implicitHeight, button.height)

        ScallopChip {
            id: chip
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: 30
            implicitHeight: 30
            symbol: "mic"
            tint: VoiceAssistant.state === "error" ? Colors.of(QsWindow.window).danger : root.accent
            hot: VoiceAssistant.state === "listening"
        }
        Column {
            id: words
            anchors.left: chip.right
            anchors.leftMargin: Tokens.spacingSm
            anchors.right: button.left
            anchors.rightMargin: Tokens.spacingSm
            anchors.verticalCenter: parent.verticalCenter
            StyledText {
                text: Translation.tr("“Hey Claude”")
                variant: "caption"
                font.weight: Font.DemiBold
            }
            StyledText {
                width: parent.width
                text: root.line
                variant: "micro"
                color: VoiceAssistant.state === "error" ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgMuted
                wrapMode: Text.Wrap
            }
        }
        ChipButton {
            id: button
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            symbol: !VoiceAssistant.modelPresent ? "download" : Config.aiVoice ? "mic" : "mic_off"
            label: !VoiceAssistant.modelPresent ? (VoiceAssistant.downloading ? Translation.tr("Getting…") : Translation.tr("Get it"))
                 : Config.aiVoice ? Translation.tr("On") : Translation.tr("Off")
            on: VoiceAssistant.modelPresent && Config.aiVoice
            solid: !VoiceAssistant.modelPresent
            tint: root.accent
            enabled: !VoiceAssistant.downloading
            onActivated: VoiceAssistant.modelPresent ? (Config.aiVoice = !Config.aiVoice) : VoiceAssistant.getModel()
        }
    }
}
