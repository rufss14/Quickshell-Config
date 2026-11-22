pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"

// ── MixerOptions ──────────────────────────────────────────────────────────────
// How the mixer behaves, and the one thing to try when the sound is broken.
//
//   Behaviour       two switches as option cards (lit while on): boost past 100%, and putting each output back
//                   at the level it was left on.
//   Trouble         restarting the audio stack. It drops sound for a second or two and an app holding a stream may
//                   not recover, so it is confirmed on a layer over the card (Cancel / Restart), never by pressing
//                   the same button twice. The pointer leaving calls it off.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    required property var panel
    readonly property var palette: Colors.of(QsWindow.window)

    visible: root.panel.view === "options"
    ViewEnter { target: root; active: root.visible }

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

            MixerPlate {
                Layout.fillWidth: true
                symbol: "tune"
                shape: "squircle"
                title: Translation.tr("Behaviour")
                note: Translation.tr("How faders and outputs act")

                OptionCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.iconXl * 2
                    symbol: "bolt"
                    shape: "sunny"
                    label: Translation.tr("Boost past 100%")
                    detail: Config.mixerBoost
                        ? Translation.tr("Faders go to %1% and can distort").arg(Math.round(Audio.boostCeiling * 100))
                        : Translation.tr("Faders stop at 100%")
                    on: Config.mixerBoost
                    enabled: Audio.ready
                    onActivated: Config.mixerBoost = !Config.mixerBoost
                }
                OptionCard {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.iconXl * 2
                    symbol: "speaker"
                    shape: "cookie9"
                    label: Translation.tr("Remember each output's volume")
                    detail: Config.audioRememberLevels
                        ? Translation.tr("Switching outputs puts each one back")
                        : Translation.tr("The level carries over")
                    on: Config.audioRememberLevels
                    onActivated: Config.audioRememberLevels = !Config.audioRememberLevels
                }
            }

            MixerPlate {
                Layout.fillWidth: true
                symbol: "restart_alt"
                shape: "cookie6"
                title: Translation.tr("Trouble")
                note: Translation.tr("A device missing, a stream stuck silent")

                Rectangle {
                    id: restart
                    Layout.fillWidth: true
                    implicitHeight: restartRow.implicitHeight + Tokens.spacingLg * 2
                    radius: Tokens.radiusCard
                    color: root.palette.plate
                    property bool armed: false

                    RowLayout {
                        id: restartRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingLg

                        Item {
                            Layout.preferredWidth: Tokens.iconXl + Tokens.spacingMd
                            Layout.preferredHeight: Tokens.iconXl + Tokens.spacingMd
                            MorphShape {
                                anchors.fill: parent
                                shape: Audio.restarting ? "burst" : "circle"
                                fillColor: Audio.restarting ? root.palette.primary : root.palette.section
                            }
                            MaterialIcon {
                                anchors.centerIn: parent
                                name: "restart_alt"
                                fill: Audio.restarting ? 1 : 0
                                font.pixelSize: Tokens.iconMd
                                color: Audio.restarting ? root.palette.fgOnPrimary : root.palette.fgMuted
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: 0
                            StyledText { text: Translation.tr("Restart audio"); variant: "label"; font.weight: Font.DemiBold }
                            StyledText {
                                Layout.fillWidth: true
                                text: Audio.restarting ? Translation.tr("Restarting…")
                                                       : Translation.tr("Restarts PipeWire, its session manager and the screen-share portals")
                                variant: "micro"
                                color: root.palette.fgMuted
                                elide: Text.ElideRight
                            }
                        }
                        ChipButton {
                            symbol: "restart_alt"
                            label: Translation.tr("Restart")
                            tonal: true
                            enabled: Audio.ready && !Audio.restarting
                            onActivated: restart.armed = true
                        }
                    }

                    // ── Restart? ──────────────────────────────────────────────────────
                    Item {
                        anchors.fill: parent
                        opacity: restart.armed ? 1 : 0
                        visible: opacity > 0.005
                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }

                        Rectangle {
                            anchors.fill: parent
                            radius: restart.radius
                            color: root.palette.alpha(root.palette.surface, 0.95)
                        }
                        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Tokens.spacingLg
                            spacing: Tokens.spacingMd
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                spacing: 0
                                StyledText { text: Translation.tr("Restart audio?"); variant: "label"; font.weight: Font.DemiBold }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Sound cuts out for a second or two.")
                                    variant: "micro"
                                    color: root.palette.fgMuted
                                    elide: Text.ElideRight
                                }
                            }
                            ChipButton {
                                label: Translation.tr("Cancel")
                                tonal: true
                                onActivated: restart.armed = false
                            }
                            ChipButton {
                                symbol: "restart_alt"
                                label: Translation.tr("Restart")
                                solid: true
                                onActivated: { restart.armed = false; Audio.restartStack() }
                            }
                        }
                    }
                    HoverHandler { onHoveredChanged: if (!hovered) restart.armed = false }
                }
            }
        }
    }
    Scrollbar { flickable: flick }
}
