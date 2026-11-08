import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../config"
import "../../components"
import "../../services"

// ── LocalAiSetup ──────────────────────────────────────────────────────────────
// The Ask page's setup card for the local AI (services/LocalAi), shown while it isn't ready: three
// steps, each a numbered stop that turns into a tick when done, with the one button that does it.
//
//   1  Install   ollama (+ ollama-vulkan with a GPU) through the update panel — the overview steps
//                aside so its password prompt and progress can be seen
//   2  Start     `ollama serve`, in the background; afterwards it starts with the shell
//   3  A model   the catalogue (LocalModelList): Get, a progress bar, and it's the one in use
//
// "Use a cloud AI instead" hands over to the page's provider picker (`cloudAsked`).
// ─────────────────────────────────────────────────────────────────────────────
ClippingRectangle {
    id: root

    property color accent: Colors.of(QsWindow.window).primary
    signal cloudAsked()

    readonly property int step: !LocalAi.installed ? 1 : !LocalAi.running ? 2 : 3
    readonly property string gpuName: LocalAi.gpu === "amd" ? "AMD" : LocalAi.gpu === "nvidia" ? "NVIDIA" : LocalAi.gpu === "intel" ? "Intel" : ""

    implicitHeight: col.implicitHeight + Tokens.spacingLg * 2
    radius: Tokens.radiusCard
    color: Colors.of(QsWindow.window).fade(Colors.of(QsWindow.window).surfaceContainer, 0.92)
    border.width: Tokens.borderWidth
    border.color: Colors.of(QsWindow.window).alpha(root.accent, 0.4)

    Column {
        id: col
        x: Tokens.spacingLg
        y: Tokens.spacingLg
        width: root.width - Tokens.spacingLg * 2
        spacing: Tokens.spacingMd

        // ── What this is ──────────────────────────────────────────────────────
        Row {
            spacing: Tokens.spacingMd
            ScallopChip {
                id: introChip
                anchors.verticalCenter: parent.verticalCenter
                symbol: "memory"
                tint: root.accent
                hot: LocalAi.starting || LocalAi.pulling !== ""
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: col.width - introChip.width - Tokens.spacingMd
                StyledText {
                    text: Translation.tr("Your own AI")
                    variant: "body"
                    font.weight: Font.DemiBold
                }
                StyledText {
                    width: parent.width
                    text: Translation.tr("Runs on this computer — free, private, and it works offline.")
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.Wrap
                }
            }
        }

        // ── The steps ─────────────────────────────────────────────────────────
        Repeater {
            model: [
                { n: 1, title: Translation.tr("Install Ollama"),
                  text: LocalAi.packages.join(" + ") + (root.gpuName !== "" ? "  ·  " + Translation.tr("uses your %1 graphics card").arg(root.gpuName) : "  ·  " + Translation.tr("runs on the processor")) },
                { n: 2, title: Translation.tr("Start it"),
                  text: Translation.tr("In the background; after this it starts with the shell") },
                { n: 3, title: Translation.tr("Pick a model"),
                  text: Translation.tr("Downloaded once — the first one becomes the one in use") }
            ]
            delegate: Column {
                id: stepRow
                required property var modelData
                readonly property bool done: root.step > stepRow.modelData.n
                readonly property bool now: root.step === stepRow.modelData.n
                width: col.width
                spacing: Tokens.spacingSm
                opacity: stepRow.done || stepRow.now ? 1 : 0.5
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                Item {
                    width: stepRow.width
                    height: Math.max(dot.height, stepText.implicitHeight, stepBtn.visible ? stepBtn.height : 0)

                    // The stop: its number, a tick once done, a ring while it's the one to do.
                    Rectangle {
                        id: dot
                        anchors.verticalCenter: parent.verticalCenter
                        width: Tokens.iconLg + 2
                        height: width
                        radius: width / 2
                        color: stepRow.done ? root.accent : "transparent"
                        border.width: stepRow.done ? 0 : 2
                        border.color: stepRow.now ? root.accent : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.3)
                        SpringValue { id: stepPop; target: stepRow.done ? 1 : 0.92; spec: Motion.springSpatial; epsilon: 0.001 }
                        scale: stepPop.value
                        Behavior on color { ColorAnimation { duration: Motion.standard } }
                        StyledText {
                            anchors.centerIn: parent
                            visible: !stepRow.done
                            text: stepRow.modelData.n
                            variant: "caption"
                            font.weight: Font.Bold
                            color: stepRow.now ? root.accent : Colors.of(QsWindow.window).fgMuted
                        }
                        MaterialIcon {
                            anchors.centerIn: parent
                            visible: stepRow.done
                            name: "check"
                            color: root.accent.hslLightness > 0.5 ? Colors.of(QsWindow.window).base : Colors.of(QsWindow.window).fg
                            font.pixelSize: Tokens.iconSm
                        }
                    }
                    Column {
                        id: stepText
                        anchors.left: dot.right
                        anchors.leftMargin: Tokens.spacingMd
                        anchors.right: stepBtn.visible ? stepBtn.left : parent.right
                        anchors.rightMargin: Tokens.spacingSm
                        anchors.verticalCenter: parent.verticalCenter
                        StyledText {
                            text: stepRow.modelData.title
                            variant: "caption"
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            width: parent.width
                            text: stepRow.modelData.text
                            variant: "micro"
                            emphasis: "dim"
                            wrapMode: Text.Wrap
                        }
                    }
                    ChipButton {
                        id: stepBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: stepRow.now && stepRow.modelData.n < 3
                        symbol: stepRow.modelData.n === 1 ? "download" : "play_arrow"
                        label: stepRow.modelData.n === 1 ? (Updates.runBusy ? Translation.tr("Installing…") : Translation.tr("Install"))
                             : LocalAi.starting ? Translation.tr("Starting…") : Translation.tr("Start")
                        solid: true
                        tint: root.accent
                        enabled: stepRow.modelData.n === 1 ? !Updates.runBusy : !LocalAi.starting
                        onActivated: stepRow.modelData.n === 1 ? LocalAi.install() : LocalAi.start()
                    }
                }

                LocalModelList {
                    visible: stepRow.modelData.n === 3 && stepRow.now
                    x: dot.width + Tokens.spacingMd
                    width: stepRow.width - x
                    accent: root.accent
                }
            }
        }

        StyledText {
            width: col.width
            visible: LocalAi.error !== ""
            text: LocalAi.error
            variant: "caption"
            color: Colors.of(QsWindow.window).danger
            wrapMode: Text.Wrap
        }

        StyledText {
            text: Translation.tr("Use a cloud AI instead")
            variant: "caption"
            font.weight: Font.DemiBold
            color: cloudHover.hovered ? root.accent : Colors.of(QsWindow.window).fgMuted
            font.underline: cloudHover.hovered
            HoverHandler { id: cloudHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.cloudAsked() }
        }
    }
}
