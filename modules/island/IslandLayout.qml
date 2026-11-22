pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import "../../config"
import "../../components"
import "../../services"

// ── IslandLayout ──────────────────────────────────────────────────────────────
// The window layout as an island page: on the left the loud card (the layout this workspace is in, what
// it does, and the moves that layout has); on the right every layout as a card, the current one lit:
// a click switches. An error from Hyprland takes the place of the description.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property int sideW: Tokens.spacingXl * 14 + Tokens.spacingSm

    // What each layout can be told to do, as its own dispatcher message.
    readonly property var actions: ({
        dwindle: [
            { msg: "togglesplit", symbol: "swap_horiz", label: "Toggle split" },
            { msg: "swapsplit",   symbol: "swap_vert",  label: "Swap sides" }
        ],
        master: [
            { msg: "swapwithmaster",  symbol: "star",   label: "Make master" },
            { msg: "addmaster",       symbol: "add",    label: "Add master" },
            { msg: "removemaster",    symbol: "remove", label: "Fewer masters" },
            { msg: "orientationnext", symbol: "cached", label: "Rotate" }
        ],
        scrolling: [],
        monocle: []
    })
    readonly property var here: root.actions[HyprLayout.current] ?? []
    readonly property bool failed: HyprLayout.lastError !== ""

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        IslandPlate {
            id: now
            Layout.fillWidth: false
            Layout.preferredWidth: root.sideW
            Layout.fillHeight: true
            hero: true
            order: 0
            clip: true

            MorphShape {
                width: now.height * 0.8
                height: width
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: -width * 0.25
                anchors.topMargin: -width * 0.22
                shape: "squircle"
                turns: false
                fillColor: root.palette.alpha(now.ink, 0.10)
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingLg
                spacing: Tokens.spacingXs

                StyledText {
                    text: Translation.tr("Layout").toUpperCase()
                    variant: "caption"
                    font.weight: Font.Bold
                    font.letterSpacing: 1
                    color: now.inkDim
                }
                IslandBadge {
                    Layout.topMargin: Tokens.spacingSm
                    size: Tokens.iconXl * 2 + Tokens.spacingSm
                    filled: true
                    shape: "squircle"
                    symbol: HyprLayout.info.symbol ?? "dashboard"
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacingSm
                    text: HyprLayout.info.label
                    variant: "headline"
                    font.weight: Font.DemiBold
                    color: now.ink
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.failed ? HyprLayout.lastError : HyprLayout.info.about
                    variant: "caption"
                    color: root.failed ? root.palette.danger : now.inkDim
                    wrapMode: Text.WordWrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                }

                Item { Layout.fillHeight: true }

                Flow {
                    Layout.fillWidth: true
                    visible: root.here.length > 0
                    spacing: Tokens.spacingSm
                    Repeater {
                        model: root.here
                        delegate: ChipButton {
                            required property var modelData
                            symbol: modelData.symbol
                            Accessible.name: modelData.label
                            onActivated: Hyprland.dispatch(`hl.dsp.layout("${modelData.msg}")`)
                            HoverTip { text: modelData.label }
                        }
                    }
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 2
            columnSpacing: Tokens.spacingMd
            rowSpacing: Tokens.spacingMd
            uniformCellWidths: true
            uniformCellHeights: true

            Repeater {
                model: HyprLayout.layouts
                delegate: IslandTile {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    order: 1 + index
                    symbol: modelData.symbol
                    label: modelData.label
                    sub: modelData.about
                    on: HyprLayout.current === modelData.id
                    onClicked: HyprLayout.set(modelData.id)
                }
            }
        }
    }
}
