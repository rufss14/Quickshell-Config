pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import "../../../config"
import "../../../components"
import "../../../services"

// ── MixerHero ─────────────────────────────────────────────────────────────────
// The mixer page's loud card: the OUTPUT, the one thing every other control on the page is relative to. A shape
// that is a plain disc while muted, a cookie at rest and a sunburst while sound comes out, swelling with the
// signal (tap it to mute); the device and what is playing through it; the level as a numeral as large as the
// island's clock; the fader; a disc per output to switch with one tap, and two tools under the fader: mute and boost.
//
// The numeral warns: amber past 100% (boost), red for a beat on a clip. The peak comes from a PwNodePeakMonitor
// on the default sink, so a card that is on screen is a card that meters (the dock's Loader ends it on close).
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    required property var panel
    readonly property var palette: Colors.of(QsWindow.window)
    readonly property color ink: root.palette.fgOnPrimaryContainer
    readonly property color inkDim: root.palette.alpha(root.ink, 0.72)

    radius: Tokens.radiusXl
    color: root.palette.primaryContainer

    readonly property real heard: Audio.meterLevel(sinkPeak.peak)
    // Holds for a beat after the signal drops, so a quiet passage does not flap the shape.
    property bool audible: false
    property bool clip: false
    Timer { id: holdTimer; interval: 1200; onTriggered: root.audible = false }
    Timer { id: clipTimer; interval: 1500; onTriggered: root.clip = false }
    PwNodePeakMonitor {
        id: sinkPeak
        node: Audio.sink
        enabled: Audio.ready && Audio.hasKnownChannels(Audio.sink)
        onPeakChanged: {
            if (Audio.muted) return
            if (sinkPeak.peak > 0.02) { root.audible = true; holdTimer.restart() }
            if (sinkPeak.peak >= 0.95) { root.clip = true; clipTimer.restart() }
        }
    }

    readonly property int playing: root.panel.apps.length

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingLg
        spacing: Tokens.spacingMd

        // ── What it is ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Playing through").toUpperCase()
                variant: "caption"
                font.weight: Font.Bold
                font.letterSpacing: 1
                color: root.inkDim
            }
            Badge {
                visible: Audio.bluetoothCodecOf(Audio.sink) !== ""
                label: Audio.bluetoothCodecOf(Audio.sink)
                tint: root.ink
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd

            // The output as a shape. Tap to mute.
            Item {
                id: orb
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Tokens.iconXl * 2
                Layout.preferredHeight: Tokens.iconXl * 2
                SpringValue { id: press; target: orbTap.pressed ? 1 : 0; spec: Motion.springSpatialFast }
                scale: (1 - press.value * 0.08) + (root.audible && !Audio.muted ? root.heard * 0.14 : 0)
                Behavior on scale { NumberAnimation { duration: Motion.track } }

                MorphShape {
                    anchors.fill: parent
                    shape: Audio.muted ? "circle" : root.audible ? "sunny" : "cookie9"
                    spec: Motion.springSpatialFast
                    fillColor: Audio.muted ? root.palette.alpha(root.ink, 0.16) : root.palette.primary
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    glyph: Audio.glyph(Audio.volume, Audio.muted)
                    fill: Audio.muted ? 0 : 1
                    font.pixelSize: Tokens.iconXl
                    color: Audio.muted ? root.inkDim : root.palette.fgOnPrimary
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { id: orbTap; enabled: Audio.ready; onTapped: Audio.toggleMute() }
                Accessible.role: Accessible.Button
                Accessible.name: Audio.muted ? Translation.tr("Unmute") : Translation.tr("Mute")
                Accessible.onPressAction: Audio.toggleMute()
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: Audio.ready ? Audio.shortLabelFor(Audio.sink) : Translation.tr("No audio")
                    variant: "title"
                    font.weight: Font.DemiBold
                    color: root.ink
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: !Audio.ready ? Translation.tr("PipeWire is not running")
                        : Audio.muted ? Translation.tr("Muted")
                        : root.playing === 0 ? Translation.tr("Nothing playing")
                        : root.playing === 1 ? Translation.tr("1 app playing")
                        : Translation.tr("%1 apps playing").arg(root.playing)
                    variant: "caption"
                    color: root.inkDim
                    elide: Text.ElideRight
                }
            }
        }

        // ── One tap between outputs ───────────────────────────────────────────
        // A disc per output, drawn as what it is (headset, monitor, speaker); the one in use is lit.
        Flow {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: Audio.sinks.length > 1
            spacing: Tokens.spacingSm

            Repeater {
                model: Audio.sinks
                delegate: Rectangle {
                    id: out
                    required property var modelData
                    readonly property bool on: out.modelData === Audio.sink
                    width: Tokens.iconXl + Tokens.spacingMd
                    height: width
                    radius: width / 2
                    color: out.on ? root.palette.primary : root.palette.alpha(root.ink, 0.14)
                    Behavior on color { ColorAnimation { duration: Motion.standard } }
                    SpringValue { id: outLean; target: outTap.pressed ? 0.9 : outHover.hovered ? 1.1 : 1; spec: Motion.springSpatialFast; epsilon: 0.001 }
                    scale: outLean.value

                    MaterialIcon {
                        anchors.centerIn: parent
                        glyph: Audio.deviceGlyph(out.modelData)
                        fill: out.on ? 1 : 0
                        font.pixelSize: Tokens.iconMd
                        color: out.on ? root.palette.fgOnPrimary : root.ink
                    }
                    HoverHandler { id: outHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: outTap; onTapped: Audio.setDefaultSink(out.modelData) }
                    HoverTip { text: Audio.shortLabelFor(out.modelData) }
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: Audio.shortLabelFor(out.modelData)
                    Accessible.checked: out.on
                    Accessible.onPressAction: Audio.setDefaultSink(out.modelData)
                }
            }
        }

        Item { Layout.fillHeight: true }

        // ── The level ─────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm
            RollText {
                Layout.alignment: Qt.AlignBottom
                text: Audio.muted ? Translation.tr("Muted") : Math.round(Audio.volume * 100) + "%"
                family: Tokens.fontMono
                pixelSize: Math.round(Tokens.fontDisplay * 1.7)
                weight: Font.Bold
                color: root.clip ? root.palette.danger
                     : Audio.volume > 1 ? root.palette.warning
                     : root.ink
            }
            Item { Layout.fillWidth: true }
            Badge {
                Layout.alignment: Qt.AlignTop
                visible: Audio.capOf(Audio.sink) > 0
                label: Translation.tr("Limit %1%").arg(Math.round(Audio.capOf(Audio.sink) * 100))
                tint: root.ink
            }
        }

        ValueSlider {
            Layout.fillWidth: true
            Layout.fillHeight: false
            expressive: true
            thickness: Tokens.spacingXl
            value: Audio.volume * 100
            maximum: root.panel.maxLevel
            // A limit shows as the tick, in place of the unity one: that is the point the fader cannot pass.
            notchAt: Audio.capOf(Audio.sink) > 0 ? Audio.capOf(Audio.sink) * 100
                                                  : (root.panel.maxLevel > 100 ? 100 : 0)
            accent: Audio.muted ? root.inkDim : root.palette.primary
            accessibleName: Translation.tr("Output volume")
            onMoved: function (v) { Audio.setVolume(v / 100, root.panel.boost) }
            onScrolled: function (d) { Audio.setVolume(Audio.steppedLevel(Audio.volume, d > 0), root.panel.boost) }
        }

        // ── Tools ─────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm

            LitTool {
                symbol: Audio.muted ? "volume_off" : "volume_up"
                lit: Audio.muted
                ink: root.ink
                tip: Audio.muted ? Translation.tr("Unmute") : Translation.tr("Mute")
                onActivated: Audio.toggleMute()
            }
            LitTool {
                symbol: "bolt"
                lit: Config.mixerBoost
                ink: root.ink
                tip: Config.mixerBoost
                     ? Translation.tr("Boost is on: faders go to %1%").arg(Math.round(Audio.boostCeiling * 100))
                     : Translation.tr("Let faders go past 100%")
                onActivated: Config.mixerBoost = !Config.mixerBoost
            }
        }
    }
}
