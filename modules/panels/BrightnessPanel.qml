pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"

// ── BrightnessPanel ───────────────────────────────────────────────────────────
// Every display the machine can dim. The brightness module opens it from the bar or the sidebar (the same
// panel in either dock). In the shell's Material 3 Expressive panel shape:
//
//   Header  (Settings › Modules › Brightness hides it) the title and the probe's dot
//   Hero    how many displays answer, and four levels that set every one of them at once
//   Rows    one per display: its name, where it is plugged in, its level, a thick slider
//
// All the work (the ddcutil probe, the coalescing queue that keeps a drag from flooding a slow I2C bus, the
// laptop floor) is services/Brightness; this only shows it and asks.
//
// A monitor ddcutil found but can't drive (DDC/CI switched off in its menu, a dock that doesn't pass I2C
// through) stays in the list, dimmed, saying so: a missing row reads as "the shell doesn't know my monitor".
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // In: the room the dock has, so the list can scroll rather than overflow.
    property real maxHeight: Infinity

    readonly property int pad: Tokens.spacingXl
    readonly property color accent: Colors.of(QsWindow.window).primary
    implicitWidth: Tokens.sideCardUnit * 8
    implicitHeight: Math.min(root.maxHeight, col.implicitHeight + root.pad * 2)

    Component.onCompleted: Brightness.ensureProbed()

    // Every display that answers, to one level (each clamped to its own floor).
    function setAll(v) {
        for (let i = 0; i < Brightness.monitors.count; i++) {
            const m = Brightness.monitors.get(i)
            if (m.controllable) Brightness.requestBrightness(i, Brightness.clampFor(m.type, v))
        }
    }

    ColumnLayout {
        id: col
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.pad
        spacing: Tokens.spacingSm

        PanelHeader {
            Layout.fillHeight: false
            visible: Config.panelHeader("brightness")
            symbol:    "brightness_6"
            title:     Translation.tr("Screen")
            titleTail: Translation.tr("brightness")
            accent:    root.accent
            subtitle:  Brightness.probing ? Translation.tr("Looking for displays…")
                     : Brightness.count === 0 ? Translation.tr("No display can be dimmed from here")
                     : Brightness.count === 1 ? Translation.tr("1 display") : Translation.tr("%1 displays").arg(Brightness.count)

            BusyDot { running: Brightness.probing; tint: Colors.of(QsWindow.window).focus }
        }

        PanelHero {
            visible: Brightness.count > 0
            symbol: "brightness_6"
            shape: "sunny"
            active: true
            turning: false
            accent: root.accent
            title: Brightness.count === 1 ? Translation.tr("One display") : Translation.tr("%1 displays").arg(Brightness.count)
            line: Translation.tr("Set every display at once")

            footer: RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                Repeater {
                    model: [25, 50, 75, 100]
                    delegate: ChipButton {
                        required property int modelData
                        Layout.fillWidth: true
                        label: modelData + "%"
                        tint: root.accent
                        onActivated: root.setAll(modelData)
                    }
                }
            }
        }

        Repeater {
            model: Brightness.monitors

            delegate: PanelRow {
                id: row
                required property int index
                required property var model

                readonly property real value: row.model.brightness
                function apply(v) { Brightness.requestBrightness(row.index, Brightness.clampFor(row.model.type, v)) }

                symbol: row.model.type === "bcl" ? "laptop" : "monitor"
                title: row.model.type === "bcl" ? Translation.tr("Built-in display") : (row.model.label || row.model.name || Translation.tr("Display"))
                subtitle: !row.model.controllable ? Translation.tr("Can't be dimmed from here") : (row.model.port || row.model.name || "")
                available: row.model.controllable
                accent: root.accent

                StyledText {
                    visible: row.model.controllable
                    text: Math.round(row.value) + "%"
                    variant: "title"
                    font.weight: Font.DemiBold
                    font.features: ({ tnum: 1 })
                }

                below: ValueSlider {
                    Layout.fillWidth: true
                    visible: row.model.controllable
                    thickness: 14
                    expressive: true
                    accent: root.accent
                    maximum: 100
                    value: row.value
                    accessibleName: row.title
                    onMoved:    function (v) { row.apply(v) }
                    onScrolled: function (d) { row.apply(row.value + d * 5) }
                }
            }
        }

        PanelEmpty {
            visible: !Brightness.probing && Brightness.count === 0
            quiet: true
            symbol: "brightness_6"
            title: Translation.tr("Nothing to dim")
            text: Translation.tr("External monitors are dimmed over DDC/CI with ddcutil (and the i2c-dev module); laptop panels with brightnessctl.")
        }
    }
}
