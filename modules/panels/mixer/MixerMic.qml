pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"

// ── MixerMic ──────────────────────────────────────────────────────────────────
// The microphone: its level on the same card an app has, a way to hear what it picks up, and who is using it.
//
//   Microphone     a MixerChannel on the default input (its orb is the meter, a tap mutes).
//   Hear yourself  plays the microphone back through the output for a short while (MicTest, which stops itself
//                  after a minute and when the panel closes). Loud while it runs, with its OWN spectrum on the
//                  input device (the shared one analyses the output and would draw the music, not your voice).
//   Recording      one row per APP holding the microphone, not per stream (Audio.recordingApps), with a meter.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    required property var panel
    readonly property var palette: Colors.of(QsWindow.window)

    visible: root.panel.view === "mic"
    ViewEnter { target: root; active: root.visible }

    CavaStream {
        id: micCava
        source: Audio.source ? Audio.source.name : ""
        running: MicTest.running
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight
        interactive: contentHeight > height + 1
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ColumnLayout {
            id: col
            width: flick.width - Tokens.spacingLg
            spacing: Tokens.spacingMd

            // ══ Microphone ════════════════════════════════════════════════════════
            MixerPlate {
                Layout.fillWidth: true
                symbol: Audio.micMuted ? "mic_off" : "mic"
                shape: "cookie9"
                title: Translation.tr("Microphone")
                note: Audio.micMuted ? Translation.tr("Muted, nobody hears you") : Translation.tr("Tap the picture to mute")

                MixerChannel {
                    Layout.fillWidth: true
                    node: Audio.source
                    mic: true
                    metering: root.visible && Audio.ready
                    symbol: Audio.micMuted ? "mic_off" : "mic"
                    shape: "cookie9"
                    label: Audio.source ? Audio.shortLabelFor(Audio.source) : Translation.tr("No microphone")
                    subLabel: Audio.source ? Audio.profileOf(Audio.source) : ""
                    level: Audio.micVolume * 100
                    muted: Audio.micMuted
                    onToggled: Audio.toggleMicMute()
                    onSetLevel: function (v) { Audio.setMicVolume(v / 100) }
                }
            }

            // ══ Hear yourself ═════════════════════════════════════════════════════
            Rectangle {
                id: hear
                Layout.fillWidth: true
                readonly property color ink: MicTest.running ? root.palette.fgOnPrimaryContainer : root.palette.fg
                readonly property color inkDim: MicTest.running ? root.palette.alpha(root.palette.fgOnPrimaryContainer, 0.72) : root.palette.fgMuted
                implicitHeight: hearCol.implicitHeight + Tokens.spacingLg * 2
                radius: Tokens.radiusXl
                color: MicTest.running ? root.palette.primaryContainer : root.palette.section
                Behavior on color { ColorAnimation { duration: Motion.standard } }

                ColumnLayout {
                    id: hearCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Tokens.spacingLg
                    spacing: Tokens.spacingMd

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingMd

                        Item {
                            Layout.preferredWidth: Tokens.iconXl
                            Layout.preferredHeight: Tokens.iconXl
                            MorphShape {
                                anchors.fill: parent
                                shape: MicTest.running ? "sunny" : "circle"
                                spec: Motion.springSpatialFast
                                fillColor: MicTest.running ? root.palette.primary : root.palette.plate
                            }
                            MaterialIcon {
                                anchors.centerIn: parent
                                name: "headphones"
                                fill: MicTest.running ? 1 : 0
                                font.pixelSize: Tokens.iconMd
                                color: MicTest.running ? root.palette.fgOnPrimary : root.palette.fgMuted
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: 0
                            StyledText {
                                text: Translation.tr("Hear yourself")
                                variant: "label"
                                font.weight: Font.DemiBold
                                color: hear.ink
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: MicTest.running ? Translation.tr("Stops in %1 s").arg(MicTest.remaining)
                                                      : Translation.tr("Play the microphone back through the output")
                                variant: "micro"
                                color: hear.inkDim
                                elide: Text.ElideRight
                            }
                        }
                        ChipButton {
                            symbol: MicTest.running ? "stop" : "headphones"
                            label: MicTest.running ? Translation.tr("Stop") : Translation.tr("Listen")
                            solid: MicTest.running
                            tonal: !MicTest.running
                            enabled: Audio.source !== null
                            onActivated: MicTest.toggle()
                        }
                    }

                    Spectrum {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Tokens.sideCardUnit
                        visible: MicTest.running
                        levels: micCava.bars
                        barCount: micCava.barCount
                        barGap: Tokens.spacingXs + 1
                        accent: root.palette.primary
                    }

                    // Only while it matters: a warning that always stands there is one you stop reading.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        visible: MicTest.running
                        spacing: Tokens.spacingSm
                        MaterialIcon { name: "warning"; font.pixelSize: Tokens.iconMd; color: hear.ink }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("On speakers this will howl. Headphones only.")
                            variant: "caption"
                            color: hear.ink
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            // ══ Recording ═════════════════════════════════════════════════════════
            MixerPlate {
                Layout.fillWidth: true
                symbol: "record_voice_over"
                shape: "clover"
                title: Translation.tr("Recording")
                note: Audio.recordingApps.length === 0 ? Translation.tr("No app is using the microphone")
                    : Audio.recordingApps.length === 1 ? Translation.tr("1 app can hear you")
                    : Translation.tr("%1 apps can hear you").arg(Audio.recordingApps.length)

                // One row per APP, not per stream (see Audio.recordingApps).
                Repeater {
                    model: Audio.recordingApps
                    delegate: Rectangle {
                        id: recRow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: recLine.implicitHeight + Tokens.spacingMd * 2
                        radius: Tokens.radiusSm
                        color: root.palette.plate

                        // Watches every one of the app's streams, so the meter does not read flat when the live one
                        // is the second.
                        PeakGroup {
                            id: recPeaks
                            nodes: recRow.modelData.nodes
                            active: root.visible && Audio.ready
                        }

                        RowLayout {
                            id: recLine
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Tokens.spacingMd
                            spacing: Tokens.spacingMd

                            MaterialIcon { name: "mic"; fill: 1; font.pixelSize: Tokens.iconMd; color: root.palette.primary }
                            StyledText {
                                Layout.fillWidth: true
                                text: Audio.labelFor(recRow.modelData.node)
                                variant: "label"
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            StyledText {
                                visible: recRow.modelData.count > 1
                                text: "×" + recRow.modelData.count
                                variant: "caption"
                                color: root.palette.fgMuted
                            }
                            // A fixed width: a meter that resized with the longest name would jitter as the list changes.
                            Meter {
                                Layout.preferredWidth: Tokens.sideCardUnit * 2
                                implicitHeight: Tokens.spacingMd
                                value: Audio.meterLevel(recPeaks.peak)
                                accent: root.palette.primary
                                fillDuration: Motion.track
                            }
                        }
                    }
                }
            }
        }
    }
    Scrollbar { flickable: flick }
}
