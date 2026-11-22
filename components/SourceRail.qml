pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../config"

// ── SourceRail ────────────────────────────────────────────────────────────────
// The island's way to choose between a few destinations of one page, as one rail in the island's own dialect
// (IslandRail): a single filled pill that SLIDES between the rows on a spring, with a little overshoot, and the
// badge of the row it lands on blooms into a shape of its own while the one it leaves goes back to a disc. Each
// row may carry a figure at the right (a count in numerals as large as the Dashboard's clock, or a short state
// word a size smaller), and a dot by a name that is not the one on show says its source is what is live.
//
// `model`: [{ value, label, icon, shape, figure: "12", big: true, live: false }]. `current` is the chosen
// value; `picked(value)` is the caller's to act on (the wallpaper page's, the colour scheme page's).
// The wallpaper page's sources and the colour scheme page's views are both this.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property var model: []
    property string current: ""
    signal picked(string value)

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property var sources: root.model
    readonly property int currentIndex: Math.max(0, root.sources.findIndex(s => s.value === root.current))

    readonly property real pad: Tokens.spacingSm
    readonly property real gap: Tokens.spacingXs
    readonly property real rowH: Math.max(1, (root.height - root.pad * 2 - root.gap * (root.sources.length - 1)) / root.sources.length)

    radius: Tokens.radiusCard
    color: root.palette.section

    // The pill that says which. A touch of overshoot on its travel, as Material 3 Expressive's selections do.
    SpringValue {
        id: slide
        target: root.currentIndex * (root.rowH + root.gap)
        spec: Motion.springSpatial
        epsilon: 0.1
    }
    Rectangle {
        x: root.pad
        y: root.pad + slide.value
        width: root.width - root.pad * 2
        height: root.rowH
        radius: height / 2
        color: root.palette.primaryContainer
    }

    Column {
        x: root.pad
        y: root.pad
        width: root.width - root.pad * 2
        spacing: root.gap

        Repeater {
            model: root.sources

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool on: root.current === row.modelData.value
                readonly property color ink: row.on ? root.palette.fgOnPrimaryContainer : root.palette.fg

                width: parent.width
                height: root.rowH

                PopIn { id: pop; active: true; index: row.index; cap: 3 }
                opacity: pop.opacity
                SpringValue { id: lean; target: tap.pressed ? 0.96 : 1; spec: Motion.springSpatialFast; epsilon: 0.001 }
                scale: lean.value * pop.scale

                Accessible.role: Accessible.RadioButton
                Accessible.name: row.modelData.label
                Accessible.checkable: true
                Accessible.checked: row.on
                Accessible.onPressAction: root.picked(row.modelData.value)

                StateLayer {
                    anchors.fill: parent
                    radius: height / 2
                    hovered: hover.hovered && !row.on
                    layerColor: row.ink
                }

                Item {
                    id: badge
                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.spacingSm
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(Tokens.iconXl, row.height - Tokens.spacingSm)
                    height: width
                    MorphShape {
                        anchors.fill: parent
                        shape: row.on ? row.modelData.shape : "circle"
                        spec: Motion.springSpatialFast
                        fillColor: row.on ? root.palette.primary : root.palette.plate
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: row.modelData.icon
                        fill: row.on ? 1 : 0
                        font.pixelSize: Tokens.iconMd
                        color: row.on ? root.palette.fgOnPrimary : root.palette.fgMuted
                        Behavior on fill  { NumberAnimation { duration: Motion.standard } }
                        Behavior on color { ColorAnimation { duration: Motion.standard } }
                    }
                }

                StyledText {
                    anchors.left: badge.right
                    anchors.leftMargin: Tokens.spacingMd
                    anchors.right: figure.left
                    anchors.rightMargin: Tokens.spacingSm
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.label
                    variant: "label"
                    font.weight: row.on ? Font.DemiBold : Font.Medium
                    color: row.ink
                    elide: Text.ElideRight
                }
                // Its source is what is on screen right now.
                Rectangle {
                    anchors.left: badge.right
                    anchors.top: badge.top
                    anchors.leftMargin: -Tokens.spacingXs
                    anchors.topMargin: -Tokens.spacingXs
                    width: Tokens.spacingMd
                    height: width
                    radius: width / 2
                    visible: (row.modelData.live ?? false) && !row.on
                    color: root.palette.primary
                    border.width: Tokens.borderWidth * 2
                    border.color: root.palette.section
                }

                StyledText {
                    id: figure
                    anchors.right: parent.right
                    anchors.rightMargin: Tokens.spacingLg
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.modelData.figure ?? ""
                    font.pixelSize: (row.modelData.big ?? true) ? Tokens.fontDisplay : Tokens.fontTitle
                    font.weight: Font.Bold
                    font.features: ({ tnum: 1 })
                    color: row.ink
                }

                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler { id: tap; onTapped: root.picked(row.modelData.value) }
            }
        }
    }
}
