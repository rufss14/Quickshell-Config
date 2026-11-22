pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"

// ── MixerApps ─────────────────────────────────────────────────────────────────
// The mixer's first page: what is making sound, a card to each (MixerChannel), then the apps the mixer remembers.
//
//   Playing now   a MixerChannel per app. An app starting or stopping adds or removes ITS card and nothing else
//                 moves: the list is a ScriptModel keyed by node id. The shell's own sound-effect cues (`pw-play`)
//                 are filtered out by the panel, or every hover would flash a card.
//   Remembered    the apps pinned with the pin tool: each starts at the level and output it was left on
//                 (MixerMemory). Folded away until opened; every row can be forgotten.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    required property var panel
    readonly property var palette: Colors.of(QsWindow.window)

    visible: root.panel.view === "apps"
    ViewEnter { target: root; active: root.visible }

    property bool rememberedFolded: true

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

            // ══ Playing now ═══════════════════════════════════════════════════════
            MixerPlate {
                Layout.fillWidth: true
                symbol: "volume_up"
                shape: "cookie7"
                title: Translation.tr("Playing now")
                note: root.panel.apps.length === 0 ? Translation.tr("Nothing is making sound")
                    : Translation.tr("Tap a picture to mute, hover for more")

                // Nothing playing: a quiet card, not a bare line.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: Audio.ready && root.panel.apps.length === 0
                    spacing: Tokens.spacingLg
                    Item {
                        Layout.preferredWidth: Tokens.iconXl * 2
                        Layout.preferredHeight: Tokens.iconXl * 2
                        MorphShape { anchors.fill: parent; shape: "cookie9"; fillColor: root.palette.plate }
                        MaterialIcon {
                            anchors.centerIn: parent
                            name: "volume_mute"
                            font.pixelSize: Tokens.iconLg
                            color: root.palette.fgMuted
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: 0
                        StyledText { text: Translation.tr("Quiet right now"); variant: "label"; font.weight: Font.DemiBold }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("An app gets its own card here the moment it makes sound.")
                            variant: "caption"
                            color: root.palette.fgMuted
                            wrapMode: Text.WordWrap
                        }
                    }
                }
                StyledText {
                    visible: !Audio.ready
                    text: Translation.tr("PipeWire is not running, so there is nothing to mix.")
                    variant: "caption"
                    color: root.palette.fgMuted
                }

                Repeater {
                    model: ScriptModel { values: root.panel.apps; objectProp: "id" }
                    delegate: MixerChannel {
                        id: ch
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        node: ch.modelData
                        order: ch.index
                        metering: root.visible && Audio.ready
                        label: Audio.labelFor(ch.modelData)
                        subLabel: Audio.sinkOf(ch.modelData) ? Translation.tr("Playing through %1").arg(Audio.shortLabelFor(Audio.sinkOf(ch.modelData))) : ""
                        iconPath: Audio.iconPathFor(ch.modelData)
                        glyph: root.panel.glyphFor(ch.modelData)
                        shape: ch.index % 2 === 0 ? "cookie7" : "clover"
                        level: Audio.levelOf(ch.modelData) * 100
                        muted: ch.modelData.audio?.muted ?? false
                        maximum: root.panel.maxLevel
                        pinnable: MixerMemory.keyOf(ch.modelData) !== ""
                        pinned: MixerMemory.pinned(ch.modelData)
                        sink: Audio.sinkOf(ch.modelData)
                        sinks: Audio.sinks

                        onToggled: {
                            const was = ch.muted
                            Audio.toggleNodeMute(ch.modelData)
                            MixerMemory.note(ch.modelData, { muted: !was })
                        }
                        // The same boost switch as the output: past 100% a stream clips, so it is opt-in here too.
                        onSetLevel: function (v) {
                            Audio.setNodeVolume(ch.modelData, v / 100, root.panel.boost)
                            MixerMemory.note(ch.modelData, { level: v / 100 })
                        }
                        onPinToggled: {
                            if (ch.pinned) MixerMemory.unpin(ch.modelData)
                            else MixerMemory.pin(ch.modelData)
                        }
                        onRouted: function (s) {
                            Audio.moveStream(ch.modelData, s)
                            MixerMemory.note(ch.modelData, { sink: s.name })
                        }
                    }
                }
            }

            // ══ Remembered ════════════════════════════════════════════════════════
            MixerPlate {
                Layout.fillWidth: true
                visible: root.panel.pins.length > 0
                symbol: "push_pin"
                shape: "clover"
                title: Translation.tr("Remembered")
                note: Translation.tr("Start at the level and output you left them on")
                foldable: true
                folded: root.rememberedFolded
                onToggled: root.rememberedFolded = !root.rememberedFolded

                trailing: [
                    Rectangle {
                        implicitWidth: pinCount.implicitWidth + Tokens.spacingMd * 2
                        implicitHeight: pinCount.implicitHeight + Tokens.spacingXs
                        radius: height / 2
                        color: root.palette.plate
                        StyledText {
                            id: pinCount
                            anchors.centerIn: parent
                            text: String(root.panel.pins.length)
                            variant: "micro"
                            font.weight: Font.DemiBold
                            font.features: ({ tnum: 1 })
                            color: root.palette.fgMuted
                        }
                    }
                ]

                Repeater {
                    model: root.panel.pins
                    delegate: Rectangle {
                        id: pinRow
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: pinLine.implicitHeight + Tokens.spacingMd * 2
                        radius: Tokens.radiusSm
                        color: root.palette.plate

                        RowLayout {
                            id: pinLine
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Tokens.spacingMd
                            spacing: Tokens.spacingMd
                            MaterialIcon { name: "push_pin"; fill: 1; font.pixelSize: Tokens.iconMd; color: root.palette.primary }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    text: pinRow.modelData.name !== "" ? pinRow.modelData.name : pinRow.modelData.key
                                    variant: "label"
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.panel.pinLine(pinRow.modelData)
                                    variant: "micro"
                                    color: root.palette.fgMuted
                                    elide: Text.ElideRight
                                }
                            }
                            ChipButton {
                                symbol: "close"
                                label: Translation.tr("Forget")
                                tonal: true
                                onActivated: MixerMemory.forgetKey(pinRow.modelData.key)
                            }
                        }
                    }
                }
            }
        }
    }
    Scrollbar { flickable: flick }
}
