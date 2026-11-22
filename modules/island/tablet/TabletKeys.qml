pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"

// ── TabletKeys ────────────────────────────────────────────────────────────────
// The tablet's express keys as a row of discs on the loud card. A key that is held blooms into a shape of its
// own (each a different one) on the accent and bumps; let go and it is a plain disc again. They are pressed on
// the tablet, not here: this only shows them, so there is nothing to click.
//
// The number of keys is what the helper counted from the device, or, until it runs, what sysfs said.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    property color ink: root.palette.fgOnPrimaryContainer

    readonly property int count: Tablet.info ? (Tablet.info.keys | 0) : (Tablet.device ? Tablet.device.keys : 0)
    readonly property var shapes: ["cookie9", "clover", "sunny", "squircle", "pentagon", "burst", "hexagon", "cookie12"]

    implicitHeight: root.count > 0 ? Tokens.iconXl : 0
    implicitWidth: row.implicitWidth
    visible: root.count > 0

    Row {
        id: row
        spacing: Tokens.spacingSm

        Repeater {
            model: root.count

            delegate: Item {
                id: key
                required property int index
                readonly property bool down: Tablet.padDown[key.index] === true

                width: Tokens.iconXl
                height: width

                SpringValue {
                    id: bump
                    target: key.down ? 1.18 : 1
                    spec: Motion.springSpatialFast
                    epsilon: 0.002
                }
                scale: bump.value

                MorphShape {
                    anchors.fill: parent
                    shape: key.down ? root.shapes[key.index % root.shapes.length] : "circle"
                    spec: Motion.springSpatialFast
                    fillColor: key.down ? root.palette.primary : root.palette.alpha(root.ink, 0.16)
                }
                StyledText {
                    anchors.centerIn: parent
                    text: String(key.index + 1)
                    variant: "caption"
                    font.weight: Font.Bold
                    font.features: ({ tnum: 1 })
                    color: key.down ? root.palette.fgOnPrimary : root.palette.alpha(root.ink, 0.72)
                }
            }
        }
    }
}
