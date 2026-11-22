pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../overview"

// ── IslandAssistant ───────────────────────────────────────────────────────────
// The shell's AI on an island (2026-11-15, one of the user's new pages; the bottom-middle island):
//
//   left    the loud card: who answers (the local model, Claude Pro, or a cloud key; Ai.label), whether it is
//           ready, and one-press asks for what it can do here (warmer colours, a calmer wallpaper, a focus timer,
//           the night light), a new conversation, and Stop while it answers
//   right   the conversation itself: the overview's chat (FeedAssistant: the thread, cards with Undo for each
//           change, the local AI's setup until it is ready, the composer) on a plate
//
// One conversation with the overview's (services/Assistant keeps the thread for the session), so a question
// asked here is there too. Nothing is sent until you ask; services/assistant.js decides what it may change.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property int sideW: Tokens.spacingXl * 14 + Tokens.spacingSm
    readonly property string why: Ai.blocker()

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        // ══ Who answers, loud ═════════════════════════════════════════════════
        IslandPlate {
            id: hero
            Layout.fillWidth: false
            Layout.preferredWidth: root.sideW
            Layout.minimumWidth: root.sideW
            Layout.fillHeight: true
            hero: true
            order: 0
            radius: Tokens.radiusXl

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingLg
                spacing: Tokens.spacingSm

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd
                    IslandBadge {
                        filled: true
                        text: Ai.letter
                        shape: Assistant.busy ? "burst" : root.why === "" ? "cookie9" : "circle"
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Assistant")
                            variant: "title"
                            font.weight: Font.DemiBold
                            color: hero.ink
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.why !== "" ? root.why
                                : Ai.provider === "ollama" && LocalAi.model !== "" ? Translation.tr("%1 · %2").arg(Ai.label).arg(LocalAi.model)
                                : Ai.label
                            variant: "caption"
                            color: hero.inkDim
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacingSm
                    text: Assistant.busy ? Translation.tr("Answering…") : Translation.tr("One press asks")
                    variant: "label"
                    font.weight: Font.DemiBold
                    color: hero.ink
                }
                // One press asks it: a card each, the whole label on it.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Tokens.spacingXs
                    enabled: root.why === "" && !Assistant.busy
                    opacity: enabled ? 1 : 0.5
                    Repeater {
                        model: [
                            { t: Translation.tr("Make my colours warmer"), q: "Make my colour scheme warmer", i: "palette",   s: "sunny" },
                            { t: Translation.tr("Pick a calm wallpaper"),  q: "Pick a calm wallpaper from my library", i: "wallpaper", s: "clover" },
                            { t: Translation.tr("Turn the night light on"), q: "Turn the night light on", i: "bedtime",   s: "squircle" },
                            { t: Translation.tr("Quieter, 30% volume"),    q: "Set the volume to 30%", i: "volume_up", s: "cookie9" }
                        ]
                        delegate: OptionCard {
                            required property var modelData
                            Layout.fillWidth: true
                            label: modelData.t
                            symbol: modelData.i
                            shape: modelData.s
                            onActivated: Assistant.ask(modelData.q)
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    ChipButton {
                        Layout.fillWidth: true
                        visible: !Assistant.busy
                        solid: true
                        symbol: "add"
                        label: Translation.tr("New conversation")
                        enabled: Assistant.hasThread
                        onActivated: Assistant.clear()
                    }
                    ChipButton {
                        Layout.fillWidth: true
                        visible: Assistant.busy
                        solid: true
                        symbol: "stop"
                        label: Translation.tr("Stop")
                        onActivated: Assistant.stop()
                    }
                }
            }
        }

        // ══ The conversation ══════════════════════════════════════════════════
        IslandPlate {
            Layout.fillWidth: true
            Layout.fillHeight: true
            order: 1
            radius: Tokens.radiusXl

            FeedAssistant {
                anchors.fill: parent
                anchors.margins: Tokens.spacingMd
                current: true
            }
        }
    }
}
