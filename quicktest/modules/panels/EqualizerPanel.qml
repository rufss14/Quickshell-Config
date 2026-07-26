import QtQuick
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"

// ── EqualizerPanel ────────────────────────────────────────────────────────────
// The audio mixer: output device, input device, and a row per app that's playing.
//
// ── What this used to be ──────────────────────────────────────────────────────
// A 3-second Timer that fired FIVE subprocesses on every tick:
//   wpctl get-volume @DEFAULT_AUDIO_SINK@
//   wpctl get-volume @DEFAULT_AUDIO_SOURCE@
//   pactl -f json list sink-inputs | python3 -c '<20 lines of JSON parsing>'
//   pactl -f json list sinks       | python3 -c '...'
//   pactl -f json list sources     | python3 -c '...'
// — and it ran whether or not the panel was open, because the old OverlayRoot
// instantiated every panel permanently. Two python interpreters, every 3 seconds,
// forever. Moving a slider spawned another process per drag frame, debounced at
// 120ms to keep the spawn rate survivable, which is why the sliders felt laggy.
//
// It is now a view over the Audio service (native PipeWire). Volume is read from
// a property and written by assigning one. There is no timer, no subprocess, no
// debounce, and no staleness — PipeWire pushes.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    implicitWidth:  535
    implicitHeight: col.implicitHeight + Tokens.spacingXl

    // App streams may be boosted past unity; devices are capped at it.
    readonly property int streamMax: 150

    // ── App presentation ──────────────────────────────────────────────────────
    // Icon resolution lives in the Icons service (Audio.iconPathFor delegates to
    // it): declared icon name → desktop-entry lookup by process binary → "".
    // This panel used to keep its own alias table and its own candidate-mangling
    // chain, which duplicated the one the dock already had — the exact
    // duplication the Icons service exists to end.
    //
    // The glyph below is the LAST resort, for an app that resolves to no icon at
    // all. It still names the app rather than saying "audio", which is the point.
    function glyphFor(node) {
        const n = Audio.labelFor(node).toLowerCase()
        if (n.includes("firefox") || n.includes("zen"))                              return "󰈹"
        if (n.includes("chrome") || n.includes("chromium"))                           return "󰊯"
        if (n.includes("spotify"))                                                    return "󰓇"
        if (n.includes("mpv"))                                                        return "󰎁"
        if (n.includes("vlc"))                                                        return "󰕼"
        if (n.includes("discord") || n.includes("vesktop") || n.includes("vencord"))  return "󰙯"
        if (n.includes("telegram"))                                                   return "󰔁"
        if (n.includes("steam"))                                                      return "󰓓"
        if (n.includes("lutris"))                                                     return "󰊗"
        if (n.includes("obs"))                                                        return "󰐋"
        if (n.includes("zoom") || n.includes("teams"))                                return "󰤅"
        return "󰓃"
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    ColumnLayout {
        id: col
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: Tokens.spacingLg + 2 }
        spacing: 0

        // ── Header ────────────────────────────────────────────────────────────
        PanelHeader {
            glyph:     "󰕾"
            title:     "Audio"
            titleTail: "Controller"
            accent:    Colors.focus
            subtitle:  Audio.streams.length === 1 ? "1 active stream"
                                                  : Audio.streams.length + " active streams"
        }

        Divider { Layout.topMargin: Tokens.spacingMd; Layout.bottomMargin: Tokens.spacingMd + 2 }

        // ── Output ────────────────────────────────────────────────────────────
        MixerRow {
            Layout.fillWidth: true
            glyph:  Audio.glyph(Audio.volume, Audio.muted)
            label:  "Output"
            level:  Audio.volume * 100
            muted:  Audio.muted
            onToggled:  Audio.toggleMute()
            onSetLevel: function(v) { Audio.setVolume(v / 100) }
        }

        DeviceChips {
            Layout.fillWidth: true
            Layout.leftMargin: 28
            visible: Audio.sinks.length > 1
            devices: Audio.sinks
            current: Audio.sink
            onPicked: function(node) { Audio.setDefaultSink(node) }
        }

        Divider { Layout.topMargin: Tokens.spacingSm + 2; Layout.bottomMargin: Tokens.spacingSm + 2 }

        // ── Input ─────────────────────────────────────────────────────────────
        MixerRow {
            Layout.fillWidth: true
            glyph:  Audio.micMuted ? "󰍭" : "󰍬"
            label:  "Input"
            level:  Audio.micVolume * 100
            muted:  Audio.micMuted
            accent: Colors.info
            onToggled:  Audio.toggleMicMute()
            onSetLevel: function(v) { Audio.setMicVolume(v / 100) }
        }

        DeviceChips {
            Layout.fillWidth: true
            Layout.leftMargin: 28
            visible: Audio.sources.length > 1
            devices: Audio.sources
            current: Audio.source
            onPicked: function(node) { Audio.setDefaultSource(node) }
        }

        // ── One row per app that's playing ────────────────────────────────────
        Repeater {
            model: Audio.streams

            ColumnLayout {
                id: streamEntry
                required property var modelData

                Layout.fillWidth: true
                spacing: 0

                Divider { Layout.topMargin: Tokens.spacingSm + 2; Layout.bottomMargin: Tokens.spacingSm + 2 }

                MixerRow {
                    Layout.fillWidth: true

                    isApp:    true
                    label:    Audio.labelFor(streamEntry.modelData)
                    iconPath: Audio.iconPathFor(streamEntry.modelData)
                    glyph:    root.glyphFor(streamEntry.modelData)

                    level:  (streamEntry.modelData.audio?.volume ?? 0) * 100
                    muted:  streamEntry.modelData.audio?.muted ?? false
                    maxLevel: root.streamMax

                    // Boosting past unity is a warning state, not a normal one.
                    accent: (streamEntry.modelData.audio?.volume ?? 0) > 1.0
                        ? Colors.warning
                        : Colors.info

                    onToggled:  Audio.toggleNodeMute(streamEntry.modelData)
                    onSetLevel: function(v) {
                        Audio.setNodeVolume(streamEntry.modelData, v / 100, true)
                    }
                }
            }
        }
    }

    // ── Divider ───────────────────────────────────────────────────────────────

    // ── MixerRow ──────────────────────────────────────────────────────────────
    // [icon] [label] [────── slider ──────] [nn%]
    // The icon IS the mute button — there's no separate control.
    component MixerRow: Item {
        id: row
        // implicitHeight, NOT height: these are ColumnLayout children, and a layout
        // sizes its children from implicitHeight — a plain `height` is overridden
        // and the row collapses to nothing.
        implicitHeight: 34

        property string glyph:    ""
        property string label:    ""
        property bool   isApp:    false
        property url    iconPath: ""

        property real level:    100          // 0..maxLevel
        property real maxLevel: 100
        property bool muted:    false
        property color accent:  Colors.focus

        signal toggled()
        signal setLevel(real v)

        readonly property color _tint: muted ? Colors.fgDim : row.accent

        RowLayout {
            anchors.fill: parent
            spacing: Tokens.spacingMd + 2

            // ── Icon / glyph — click to mute ──────────────────────────────────
            Item {
                Layout.preferredWidth:  18
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter

                // Only built when there IS a resolved path — an Image with an
                // empty source resolves to Quickshell's blackhole placeholder and
                // warns.
                Loader {
                    id: appIcon
                    anchors.fill: parent
                    active: row.isApp && String(row.iconPath) !== ""

                    sourceComponent: Image {
                        source: row.iconPath
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        asynchronous: true
                        opacity: row.muted ? 0.30 : 0.85
                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: !appIcon.active
                    text:    row.glyph
                    color:   row._tint
                    variant: "label"
                    font.pixelSize: 14
                    opacity: row.muted ? 0.30 : 1.0
                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.toggled()
                }
            }

            // ── Label ─────────────────────────────────────────────────────────
            StyledText {
                text: row.label
                variant: "caption"
                font.weight: Font.Medium
                elide: Text.ElideRight
                opacity: row.muted ? 0.28 : 0.75
                // Fixed width so every slider in the column starts at the same x.
                Layout.preferredWidth: 62
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
            }

            // ── Slider ────────────────────────────────────────────────────────
            ValueSlider {
                Layout.fillWidth: true
                value:   row.level
                maximum: row.maxLevel
                accent:  row._tint
                // Mark unity on any slider that can exceed it.
                notchAt: row.maxLevel > 100 ? 100 : 0
                onMoved:    function(v) { row.setLevel(v) }
                onScrolled: function(d) { row.setLevel(row.level + d * 5) }
            }

            // ── Level ─────────────────────────────────────────────────────────
            StyledText {
                text:    Math.round(row.level) + "%"
                color:   row._tint
                variant: "caption"
                font.pixelSize: 10
                font.weight: Font.Medium
                opacity: row.muted ? 0.28 : 0.80
                Layout.preferredWidth: 30
                horizontalAlignment: Text.AlignRight
            }
        }
    }

    // ── DeviceChips ───────────────────────────────────────────────────────────
    // Chips to switch the default output/input. Hidden when there's only one.
    component DeviceChips: Item {
        id: chipRow
        // See MixerRow: implicitHeight, not height. This is why the output/input
        // device chips intermittently failed to appear — the layout was giving them
        // zero height regardless of what `height` said.
        implicitHeight: visible ? 20 : 0

        property var devices: []
        property var current: null
        signal picked(var node)

        Flickable {
            anchors.fill: parent
            contentWidth: chips.implicitWidth
            clip: true
            flickableDirection: Flickable.HorizontalFlick

            Row {
                id: chips
                spacing: Tokens.spacingSm

                Repeater {
                    model: chipRow.devices

                    Rectangle {
                        id: chip
                        required property var modelData

                        // "Which device is active" comes from the service, not from
                        // local click state — so it stays right when the default is
                        // changed by something outside this shell.
                        readonly property bool on: chip.modelData === chipRow.current
                        readonly property string name: Audio.labelFor(chip.modelData)

                        height: 18
                        width:  chipLabel.implicitWidth + Tokens.spacingLg
                        radius: height / 2

                        color: chip.on ? Colors.alpha(Colors.focus, 0.18)
                             : hover.containsMouse ? Colors.alpha(Colors.fg, 0.09)
                             : "transparent"
                        border.width: Tokens.borderWidth
                        border.color: chip.on ? Colors.alpha(Colors.focus, 0.38)
                                              : Colors.alpha(Colors.fg, 0.08)

                        Behavior on color        { ColorAnimation { duration: Motion.respond } }
                        Behavior on border.color { ColorAnimation { duration: Motion.respond } }

                        StyledText {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: chip.name.length > 24 ? chip.name.substring(0, 22) + "…" : chip.name
                            color: chip.on ? Colors.focus : Colors.fg
                            opacity: chip.on ? 0.90 : 0.40
                            font.pixelSize: 9
                            font.weight: chip.on ? Font.Medium : Font.Normal
                            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                        }

                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: chipRow.picked(chip.modelData)
                        }
                    }
                }
            }
        }
    }
}
