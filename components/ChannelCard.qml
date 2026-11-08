import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import "../config"
import "../services"

// ── ChannelCard ───────────────────────────────────────────────────────────────
// One channel of the audio mixer — an app, the microphone — as a tonal card:
//
//     ( orb )  name ················ [extras] [pin]  72%
//              ═════════ fader ═════════════════════
//
// The orb IS the meter and the mute button. It is a plain disc while nothing comes through; the moment a signal
// does it becomes a cookie (MorphShape, on its spring) and swells with the level, so "playing" and "silent" read
// at a glance without a thin line under every fader. Click it to mute. Muted, it greys and stays still.
// Clipping turns the figure red for a moment.
//
// The peak comes from a PwNodePeakMonitor on `node`, enabled only while `metering` (the page is showing):
// enabling one asks PipeWire to keep streaming peak data. A null node is a fine volume control without it.
// Anything declared inside the card lands between the name and the figure (a route pill, a badge).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string symbol:   ""            // Material Symbols name…
    property string glyph:    ""            // …or a Nerd glyph (Audio.deviceGlyph and friends)
    property url    iconPath: ""            // an app's own icon, when it has one
    property string label:    ""
    property string subLabel: ""

    property real  level:   100             // 0..maximum, in percent
    property real  maximum: 100
    property real  notchAt: root.maximum > 100 ? 100 : 0
    property bool  muted:   false
    property color accent:  Colors.of(QsWindow.window).primary
    property string shape:  "cookie9"       // what the orb becomes while a signal comes through

    property var  node: null
    property bool metering: true

    // The pin: shown when `pinnable`, lit when `pinned`.
    property bool pinnable: false
    property bool pinned:   false

    default property alias extras: extraRow.data

    signal toggled()
    signal setLevel(real v)
    signal pinToggled()

    // ── The signal ────────────────────────────────────────────────────────────
    readonly property real heard: Audio.meterLevel(peak.peak)
    // "Audible" holds for a beat after the signal drops, so a quiet passage does not flap the shape.
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

    readonly property bool _live: root._audible && !root.muted
    readonly property color _tint: root.muted ? Colors.of(QsWindow.window).fgDim : root.accent
    readonly property int pad: Tokens.spacingMd

    implicitHeight: body.implicitHeight + root.pad * 2
    Layout.fillWidth: true

    // Pressed in on a spring, like ShapeTile.
    SpringValue { id: press; target: orbTap.pressed ? 1 : 0; spec: Motion.springSpatialFast }

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radiusCard
        color: root._live ? Colors.of(QsWindow.window).alpha(root.accent, 0.12)
                          : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
        Behavior on color { ColorAnimation { duration: Motion.standard } }
    }

    RowLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: root.pad
        spacing: Tokens.spacingMd

        // ── The orb ───────────────────────────────────────────────────────────
        Item {
            id: orb
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: Tokens.iconXl + Tokens.spacingLg
            Layout.preferredHeight: Tokens.iconXl + Tokens.spacingLg
            // It swells with the signal (a short, flat ease: the peak arrives faster than a spring settles).
            scale: (1 - press.value * 0.08) + (root._live ? root.heard * 0.16 : 0)
            Behavior on scale { NumberAnimation { duration: Motion.track } }

            MorphShape {
                anchors.fill: parent
                shape: root._live ? root.shape : "circle"
                fillColor: root._live ? root.accent : Colors.of(QsWindow.window).surfaceHigh
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
                    // 2x the cell, fixed: binding sourceSize to a live size re-decodes on resize.
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
                fill: root._live ? 1 : 0
                font.pixelSize: Tokens.iconLg
                color: root._live ? Colors.of(QsWindow.window).fgOnPrimary : root._tint
                opacity: root.muted ? 0.5 : 1
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
            }

            // A slash over a muted app's icon, so a muted app does not just look dim.
            MaterialIcon {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: -Tokens.spacingXs
                visible: root.muted
                name: "volume_off"
                fill: 1
                font.pixelSize: Tokens.iconMd
                color: Colors.of(QsWindow.window).fgMuted
            }

            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { id: orbTap; onTapped: root.toggled() }
        }

        // ── Name, figure, fader ───────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.alignment: Qt.AlignVCenter
            spacing: Tokens.spacingXs

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
                        variant: "body"
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        opacity: root.muted ? 0.5 : 1
                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: root.subLabel !== ""
                        text: root.subLabel
                        variant: "caption"
                        emphasis: "dim"
                        elide: Text.ElideRight
                    }
                }

                Row {
                    id: extraRow
                    spacing: Tokens.spacingSm
                    Layout.alignment: Qt.AlignVCenter
                }

                // The pin: this app is kept how it is now (MixerMemory).
                Rectangle {
                    id: pin
                    visible: root.pinnable
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Tokens.iconMd + Tokens.spacingMd
                    implicitHeight: implicitWidth
                    radius: width / 2
                    color: root.pinned ? Colors.of(QsWindow.window).alpha(root.accent, pinHover.hovered ? 0.34 : 0.24)
                                       : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, pinHover.hovered ? 0.12 : 0)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "push_pin"
                        fill: root.pinned ? 1 : 0
                        font.pixelSize: Tokens.iconMd
                        color: root.pinned ? root.accent : Colors.of(QsWindow.window).fgMuted
                        rotation: root.pinned ? 0 : 45
                        Behavior on rotation { NumberAnimation { duration: Motion.respond; easing.type: Motion.enter } }
                    }
                    HoverHandler { id: pinHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.pinToggled() }
                    HelpTip { text: root.pinned ? "Kept as it is — level, mute and output. Tap to forget."
                                                : "Keep this app's level and output the next time it starts" }
                }

                // Digits roll as the level moves; past unity (boost) they warn, on a clip they are red.
                StyledText {
                    visible: root.muted
                    text: "muted"
                    variant: "caption"
                    emphasis: "dim"
                    font.family: Tokens.fontMono
                }
                RollText {
                    visible: !root.muted
                    text: Math.round(root.level) + "%"
                    family: Tokens.fontMono
                    pixelSize: Tokens.fontBody
                    weight: Font.DemiBold
                    color: root._clip ? Colors.of(QsWindow.window).danger
                         : root.level > 100 ? Colors.of(QsWindow.window).warning
                         : Colors.of(QsWindow.window).fg
                }
            }

            ValueSlider {
                Layout.fillWidth: true
                thickness: Tokens.spacingMd
                value: root.level
                maximum: root.maximum
                notchAt: root.notchAt
                accent: root._tint
                onMoved: function (v) { root.setLevel(v) }
                onScrolled: function (d) { root.setLevel(root.level + d * 5) }
            }
        }
    }
}
