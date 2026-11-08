import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import "../../theming" as T

// Sound — PipeWire / WirePlumber. Pick the default output and input device,
// adjust per-device volume + mute, and control per-application playback volume.
// Node audio is kept live via PwObjectTracker on everything we display.
Item {
    id: root

    readonly property var allNodes: Pipewire.nodes ? Pipewire.nodes.values : []
    function cls(n) { return (n && n.properties) ? (n.properties["media.class"] || "") : "" }
    function nm(n)  { return n ? (n.description || n.nickname || n.name || "Unknown") : "Unknown" }

    readonly property var sinks:   allNodes.filter(function(n){ return cls(n) === "Audio/Sink" })
    readonly property var sources: allNodes.filter(function(n){ return cls(n) === "Audio/Source" })
    readonly property var streams: allNodes.filter(function(n){ return cls(n) === "Stream/Output/Audio" })

    // Bind EVERY node: a PwNode's `properties` (media.class) and `audio`
    // (volume/mute) are only populated once it is tracked — so we must track all
    // nodes before we can even classify them. (Filtering first would track
    // nothing, because the classes wouldn't be readable yet.)
    PwObjectTracker { objects: root.allNodes }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true

        ColumnLayout {
            id: col
            width: parent.width
            spacing: 18

            Text {
                text: "Sound"
                color: T.Theme.ink
                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 8; bold: true }
            }

            // ── Output ─────────────────────────────────────────────────────────────
            Section { title: "Output" }
            Repeater {
                model: root.sinks
                delegate: VolRow {
                    required property var modelData
                    node: modelData
                    selectable: true
                    isDefault: Pipewire.defaultAudioSink === modelData
                    onMakeDefault: Pipewire.preferredDefaultAudioSink = modelData
                }
            }

            // ── Input ──────────────────────────────────────────────────────────────
            Section { title: "Input" }
            Repeater {
                model: root.sources
                delegate: VolRow {
                    required property var modelData
                    node: modelData
                    selectable: true
                    isDefault: Pipewire.defaultAudioSource === modelData
                    onMakeDefault: Pipewire.preferredDefaultAudioSource = modelData
                }
            }

            // ── Applications ───────────────────────────────────────────────────────
            Section { title: "Applications"; visible: root.streams.length > 0 }
            Text {
                visible: root.streams.length === 0
                text: "No apps are playing audio."
                color: T.Theme.inkDim
                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 2; italic: true }
            }
            Repeater {
                model: root.streams
                delegate: VolRow {
                    required property var modelData
                    node: modelData
                    selectable: false
                }
            }
        }
    }

    component Section: Text {
        property string title: ""
        Layout.fillWidth: true
        Layout.topMargin: 4
        text: title
        color: T.Theme.accent
        font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1; bold: true }
    }

    // One node row: optional default-selector, name, %, slider and mute.
    component VolRow: Rectangle {
        property var node: null
        property bool selectable: false
        property bool isDefault: false
        signal makeDefault()

        readonly property var audio: node ? node.audio : null
        readonly property bool muted: audio ? audio.muted : false
        readonly property real vol: audio ? audio.volume : 0

        Layout.fillWidth: true
        implicitHeight: 58
        radius: T.Theme.moduleRadius
        color: isDefault ? T.Theme.surfaceActive : T.Theme.surfaceAlt
        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12; anchors.rightMargin: 12
            spacing: 12

            // Default-device selector.
            Rectangle {
                visible: selectable
                implicitWidth: 16; implicitHeight: 16; radius: T.Theme.radiusFull
                color: "transparent"
                border.width: 2
                border.color: isDefault ? T.Theme.accent : T.Theme.border
                Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: T.Theme.radiusFull; color: T.Theme.accent; visible: isDefault }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; enabled: selectable; onClicked: makeDefault() }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 5
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: root.nm(node)
                        color: T.Theme.ink
                        elide: Text.ElideRight
                        font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1; bold: isDefault }
                    }
                    Text {
                        text: Math.round(vol * 100) + "%"
                        color: T.Theme.inkDim
                        font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 3 }
                    }
                }
                // Slider.
                Rectangle {
                    id: bar
                    Layout.fillWidth: true
                    implicitHeight: 6
                    radius: T.Theme.radiusFull
                    color: T.Theme.surfaceHover
                    Rectangle {
                        height: parent.height; radius: T.Theme.radiusFull
                        width: parent.width * Math.max(0, Math.min(1, vol))
                        color: muted ? T.Theme.inkDim : T.Theme.accent
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.topMargin: -6; anchors.bottomMargin: -6   // easier grab target
                        cursorShape: Qt.PointingHandCursor
                        enabled: audio !== null
                        function apply(mx) { if (audio) audio.volume = Math.max(0, Math.min(1, mx / width)) }
                        onPressed: function(m){ apply(m.x) }
                        onPositionChanged: function(m){ if (pressed) apply(m.x) }
                    }
                }
            }

            // Mute.
            Rectangle {
                implicitWidth: 32; implicitHeight: 32; radius: T.Theme.moduleRadius
                color: mma.containsMouse ? T.Theme.surfaceHover : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: String.fromCodePoint(muted ? 0xF075F : vol < 0.34 ? 0xF057F : vol < 0.67 ? 0xF0580 : 0xF057E)
                    color: muted ? T.Theme.accentAlt : T.Theme.ink
                    font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 2 }
                }
                MouseArea { id: mma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; enabled: audio !== null; onClicked: audio.muted = !audio.muted }
                Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
            }
        }
    }
}
