pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import "../../../config"
import "../../../components"
import "../../../services"

// ── MixerChannel ──────────────────────────────────────────────────────────────
// One channel of the mixer, an app or the microphone, as a card on the page's plate:
//
//     ( orb )  name ··························· 72%
//              → where it plays        ═══ fader ═══
//
// The orb IS the meter and the mute button: a plain disc while nothing comes through, a cookie that swells with
// the signal while it does (the peak comes from a PwNodePeakMonitor, enabled only while the page shows). Under
// the pointer a capsule opens at the corner with the card's tools: keep it as it is (the pin, MixerMemory), play
// it somewhere else, mute. "Somewhere else" unfolds INLINE: a row of the outputs under the fader (no popup),
// the one in use lit, a tap moves the stream.
//
// An `app` card is for a playback stream; the microphone card (`mic`) has no pin and no route.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    required property var node
    property bool mic: false
    property bool metering: true
    property string label: ""
    property string subLabel: ""
    property url iconPath: ""
    property string glyph: ""
    property string symbol: ""
    property string shape: "cookie7"
    property real level: 100
    property real maximum: 100
    property bool muted: false
    property bool pinnable: false
    property bool pinned: false
    // Where it plays now, and the outputs it could play on (an app card only).
    property var sink: null
    property var sinks: []
    property int order: 0

    signal toggled()
    signal setLevel(real v)
    signal pinToggled()
    signal routed(var sink)

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property bool canRoute: !root.mic && root.sinks.length > 1
    property bool routing: false

    // ── The signal ────────────────────────────────────────────────────────────
    readonly property real heard: Audio.meterLevel(peak.peak)
    property bool _audible: false
    property bool _clip: false
    Timer { id: audibleHold; interval: 1200; onTriggered: root._audible = false }
    Timer { id: clipHold; interval: 1500; onTriggered: root._clip = false }
    PwNodePeakMonitor {
        id: peak
        node: root.node
        enabled: root.metering && root.node !== null && Audio.ready && Audio.hasKnownChannels(root.node)
        onPeakChanged: {
            if (root.muted) return
            if (peak.peak > 0.02) { root._audible = true; audibleHold.restart() }
            if (peak.peak >= 0.95) { root._clip = true; clipHold.restart() }
        }
    }
    readonly property bool live: root._audible && !root.muted
    readonly property color tint: root.muted ? root.palette.fgDim : root.palette.primary

    // A card that is making sound rises one tone (the island's own "this one is on" move), not a colour.
    radius: Tokens.radiusCard
    color: root.live ? root.palette.surfaceHigh : root.palette.alpha(root.palette.surfaceHigh, 0.7)
    Behavior on color { ColorAnimation { duration: Motion.standard } }

    readonly property real pad: Tokens.spacingLg
    implicitHeight: col.implicitHeight + root.pad * 2

    PopIn { id: pop; active: root.visible; index: root.order; cap: 4 }
    opacity: pop.opacity * (root.muted ? 0.8 : 1)
    scale: pop.scale

    HoverHandler { id: cardHover }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.pad
        spacing: Tokens.spacingMd

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingLg

            // ── The orb ───────────────────────────────────────────────────────
            Item {
                id: orb
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Tokens.iconXl + Tokens.spacingXl
                Layout.preferredHeight: Tokens.iconXl + Tokens.spacingXl
                SpringValue { id: press; target: orbTap.pressed ? 1 : 0; spec: Motion.springSpatialFast }
                scale: (1 - press.value * 0.08) + (root.live ? root.heard * 0.16 : 0)
                Behavior on scale { NumberAnimation { duration: Motion.track } }

                MorphShape {
                    anchors.fill: parent
                    shape: root.live ? root.shape : "circle"
                    spec: Motion.springSpatialFast
                    fillColor: root.live ? root.palette.primary : root.palette.section
                }
                // The app's own icon when it has one. Loader-gated: an Image with an empty source resolves to
                // Quickshell's blackhole placeholder and warns.
                Loader {
                    id: appIcon
                    anchors.centerIn: parent
                    width: Tokens.iconLg
                    height: Tokens.iconLg
                    active: String(root.iconPath) !== ""
                    sourceComponent: Image {
                        source: root.iconPath
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        asynchronous: true
                        sourceSize: Qt.size(Tokens.iconLg * 2, Tokens.iconLg * 2)
                        opacity: root.muted ? 0.35 : 1
                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                    }
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    visible: !appIcon.active
                    name: root.symbol
                    glyph: root.symbol === "" ? root.glyph : ""
                    fill: root.live ? 1 : 0
                    font.pixelSize: Tokens.iconLg
                    color: root.live ? root.palette.fgOnPrimary : root.tint
                    opacity: root.muted ? 0.5 : 1
                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                }
                // A slash on a muted app, so muted does not only look dim.
                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: -Tokens.spacingXs
                    width: Tokens.iconMd + Tokens.spacingSm
                    height: width
                    radius: width / 2
                    visible: root.muted
                    color: root.palette.plate
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: root.mic ? "mic_off" : "volume_off"
                        fill: 1
                        font.pixelSize: Tokens.iconMd
                        color: root.palette.fgMuted
                    }
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { id: orbTap; onTapped: root.toggled() }
                Accessible.role: Accessible.Button
                Accessible.name: root.muted ? Translation.tr("Unmute") : Translation.tr("Mute")
                Accessible.onPressAction: root.toggled()
            }

            // ── Name and fader ────────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter
                spacing: Tokens.spacingSm

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: root.label
                            variant: "label"
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: root.subLabel !== ""
                            text: root.subLabel
                            variant: "micro"
                            color: root.palette.fgMuted
                            elide: Text.ElideRight
                        }
                    }

                    // The pin, as a small persistent mark when it is held (the capsule has the tool).
                    MaterialIcon {
                        Layout.alignment: Qt.AlignVCenter
                        visible: root.pinned && !tools.shown
                        name: "push_pin"
                        fill: 1
                        font.pixelSize: Tokens.iconMd
                        color: root.palette.primary
                    }

                    // The numeral, as large as a card can carry. Digits roll; past unity they warn, on a clip red.
                    RollText {
                        Layout.alignment: Qt.AlignVCenter
                        text: root.muted ? Translation.tr("Muted") : Math.round(root.level) + "%"
                        family: Tokens.fontMono
                        pixelSize: Tokens.fontTitle + Tokens.spacingSm
                        weight: Font.Bold
                        color: root._clip ? root.palette.danger
                             : root.level > 100 ? root.palette.warning
                             : root.muted ? root.palette.fgMuted
                             : root.palette.fg
                        // The tools stand in this corner while the pointer is on the card.
                        opacity: tools.shown ? 0 : 1
                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                    }
                }

                ValueSlider {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    expressive: true
                    thickness: Tokens.spacingLg
                    value: root.level
                    maximum: root.maximum
                    notchAt: root.maximum > 100 ? 100 : 0
                    accent: root.tint
                    accessibleName: root.label
                    onMoved: function (v) { root.setLevel(v) }
                    onScrolled: function (d) { root.setLevel(root.level + d * 5) }
                }
            }
        }

        // ── Play it somewhere else ────────────────────────────────────────────
        // Unfolds inline: a row of the outputs, the one in use lit. A critically damped height, so the card
        // below gives way without a wobble.
        Item {
            id: routeBox
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: routeK.value * routeFlow.implicitHeight
            visible: routeK.value > 0.005
            clip: true
            SpringValue { id: routeK; target: root.routing && root.canRoute ? 1 : 0; spec: Motion.springSpatial; epsilon: 0.002 }

            Flow {
                id: routeFlow
                width: parent.width
                spacing: Tokens.spacingSm
                opacity: routeK.value

                Repeater {
                    model: root.sinks
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        readonly property bool on: chip.modelData === root.sink
                        implicitHeight: Tokens.iconXl
                        implicitWidth: Math.min(chipRow.implicitWidth + Tokens.spacingLg * 2, routeFlow.width)
                        radius: height / 2
                        color: chip.on ? root.palette.primaryContainer : root.palette.section
                        Behavior on color { ColorAnimation { duration: Motion.standard } }

                        StateLayer {
                            anchors.fill: parent
                            radius: parent.radius
                            hovered: chipHover.hovered && !chip.on
                            layerColor: root.palette.fg
                        }
                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            width: Math.min(implicitWidth, chip.width - Tokens.spacingLg * 2)
                            spacing: Tokens.spacingSm
                            MaterialIcon {
                                glyph: Audio.deviceGlyph(chip.modelData)
                                font.pixelSize: Tokens.iconMd
                                color: chip.on ? root.palette.fgOnPrimaryContainer : root.palette.fgMuted
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Audio.shortLabelFor(chip.modelData)
                                variant: "caption"
                                font.weight: chip.on ? Font.DemiBold : Font.Medium
                                color: chip.on ? root.palette.fgOnPrimaryContainer : root.palette.fg
                                elide: Text.ElideRight
                            }
                        }
                        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { root.routed(chip.modelData); root.routing = false } }
                    }
                }
            }
        }
    }

    // ── The tools: a capsule under the pointer ────────────────────────────────
    Rectangle {
        id: tools
        readonly property bool shown: cardHover.hovered || root.routing
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.spacingMd
        width: toolRow.implicitWidth + Tokens.spacingSm * 2
        height: Tokens.iconXl + Tokens.spacingSm
        radius: height / 2
        color: root.palette.alpha(root.palette.section, 0.96)
        opacity: Math.min(1, Math.max(0, toolsK.value))
        visible: tools.shown || toolsK.value > 0.005
        scale: 0.7 + 0.3 * Math.max(0, toolsK.value)
        transformOrigin: Item.TopRight
        SpringValue { id: toolsK; target: tools.shown ? 1 : 0; spec: Motion.springSpatialFast; epsilon: 0.002 }

        Row {
            id: toolRow
            anchors.centerIn: parent
            spacing: 0
            LitTool {
                id: pinTool
                visible: root.pinnable
                symbol: "push_pin"
                lit: root.pinned
                tip: root.pinned ? Translation.tr("Kept as it is: level, mute and output. Tap to forget.")
                                 : Translation.tr("Keep its level and output for next time")
                tipBelow: true
                onActivated: { root.pinToggled(); pinTool.bump() }
            }
            LitTool {
                visible: root.canRoute
                symbol: "swap_horiz"
                lit: root.routing
                tip: Translation.tr("Play it through another output")
                tipBelow: true
                onActivated: root.routing = !root.routing
            }
            LitTool {
                symbol: root.muted ? (root.mic ? "mic_off" : "volume_off") : (root.mic ? "mic" : "volume_up")
                lit: root.muted
                tip: root.muted ? Translation.tr("Unmute") : Translation.tr("Mute")
                tipBelow: true
                onActivated: root.toggled()
            }
        }
    }
}
