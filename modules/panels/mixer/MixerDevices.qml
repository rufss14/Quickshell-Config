pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"

// ── MixerDevices ──────────────────────────────────────────────────────────────
// Where sound comes out and where it goes in: two plates of MixerDevice cards. The one in use is the loud card of
// its plate; a tap on another makes it the default. Under the pointer an output offers "play every app here" and
// its options (a volume limit, the balance), unfolded inline on the card.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    required property var panel
    readonly property var palette: Colors.of(QsWindow.window)

    visible: root.panel.view === "devices"

    // The one in use first, the rest in the order PipeWire lists them. Keyed by node id, so a change of default
    // moves a card and does not rebuild them.
    readonly property var sinkList: Audio.sinks.slice().sort((a, b) => (b === Audio.sink) - (a === Audio.sink))
    readonly property var sourceList: Audio.sources.slice().sort((a, b) => (b === Audio.source) - (a === Audio.source))
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
                symbol: "output"
                shape: "cookie9"
                title: Translation.tr("Output")
                note: Translation.tr("Where sound comes out")

                Repeater {
                    model: ScriptModel { values: root.sinkList; objectProp: "id" }
                    delegate: MixerDevice {
                        id: dev
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        node: dev.modelData
                        order: dev.index
                        current: Audio.sink
                        isSink: true
                        canMove: root.panel.apps.some(s => Audio.sinkOf(s) !== dev.modelData)
                        onPicked: Audio.setDefaultSink(dev.modelData)
                        onMoveHere: Audio.moveAllStreams(dev.modelData)
                    }
                }
                StyledText {
                    visible: Audio.sinks.length === 0
                    text: Translation.tr("No output devices.")
                    variant: "caption"
                    color: root.palette.fgMuted
                }
            }

            MixerPlate {
                Layout.fillWidth: true
                symbol: "input"
                shape: "squircle"
                title: Translation.tr("Input")
                note: Translation.tr("Where sound goes in")

                Repeater {
                    model: ScriptModel { values: root.sourceList; objectProp: "id" }
                    delegate: MixerDevice {
                        id: src
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        node: src.modelData
                        order: src.index
                        current: Audio.source
                        onPicked: Audio.setDefaultSource(src.modelData)
                    }
                }
                StyledText {
                    visible: Audio.sources.length === 0
                    text: Translation.tr("No input devices.")
                    variant: "caption"
                    color: root.palette.fgMuted
                }
            }
        }
    }
    Scrollbar { flickable: flick }
}
