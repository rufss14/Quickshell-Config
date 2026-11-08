pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"

// ── BrightnessPanel ───────────────────────────────────────────────────────────
// Every display the machine can dim, one row each: its name, where it is plugged in, a
// thick slider and its level. The brightness module opens it from the bar or the
// sidebar (the same panel in either dock). All the work — the ddcutil probe, the
// coalescing queue that keeps a drag from flooding a slow I2C bus, the laptop floor —
// is services/Brightness; this only shows it and asks.
//
// A monitor ddcutil found but can't drive (DDC/CI switched off in its menu, a dock that
// doesn't pass I2C through) stays in the list, dimmed, saying so — a missing row reads
// as "the shell doesn't know my monitor".
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // In: the room the dock has, so the list can scroll rather than overflow.
    property real maxHeight: Infinity

    readonly property int pad: Tokens.spacingLg
    implicitWidth: Tokens.sideCardUnit * 8
    implicitHeight: Math.min(root.maxHeight, col.implicitHeight + root.pad * 2)

    Component.onCompleted: Brightness.ensureProbed()

    ColumnLayout {
        id: col
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.pad
        spacing: Tokens.spacingMd

        PanelHeader {
            Layout.fillHeight: false
            glyph:     "\u{F00DF}"                                   // 󰃟 brightness
            title:     Translation.tr("Screen")
            titleTail: "brightness"
            accent:    Colors.of(QsWindow.window).primary
            subtitle:  Brightness.probing ? "Looking for displays…"
                     : Brightness.count === 0 ? "No display can be dimmed from here"
                     : Brightness.count === 1 ? "1 display" : Brightness.count + " displays"

            BusyDot { running: Brightness.probing; tint: Colors.of(QsWindow.window).focus }
        }

        Repeater {
            model: Brightness.monitors

            delegate: ColumnLayout {
                id: row
                required property int index
                required property var model

                readonly property real value: row.model.brightness
                readonly property real min: Brightness.minFor(row.model.type)
                function apply(v) { Brightness.requestBrightness(row.index, Brightness.clampFor(row.model.type, v)) }

                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingXs
                enabled: row.model.controllable
                opacity: row.model.controllable ? 1 : 0.5

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm

                    MaterialIcon {
                        name: row.model.type === "bcl" ? "laptop" : "monitor"
                        color: Colors.of(QsWindow.window).fgDim
                        font.pixelSize: Tokens.iconMd
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: row.model.type === "bcl" ? "Built-in display" : (row.model.label || row.model.name || "Display")
                        variant: "body"
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    StyledText {
                        text: !row.model.controllable ? "can't be dimmed"
                            : (row.model.port || row.model.name || "")
                        variant: "caption"
                        emphasis: "dim"
                    }
                    StyledText {
                        visible: row.model.controllable
                        Layout.preferredWidth: 40
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(row.value) + "%"
                        variant: "body"
                        font.weight: Font.DemiBold
                    }
                }

                ValueSlider {
                    Layout.fillWidth: true
                    thickness: 14
                    accent: Colors.of(QsWindow.window).primary
                    maximum: 100
                    value: row.value
                    onMoved:    function (v) { row.apply(v) }
                    onScrolled: function (d) { row.apply(row.value + d * 5) }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            visible: !Brightness.probing && Brightness.count === 0
            text: Translation.tr("External monitors are dimmed over DDC/CI with ddcutil (and the i2c-dev module); laptop panels with brightnessctl.")
            variant: "caption"
            emphasis: "dim"
            wrapMode: Text.WordWrap
        }
    }
}
