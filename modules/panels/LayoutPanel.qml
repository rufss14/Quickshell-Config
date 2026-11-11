pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"

// ── LayoutPanel ───────────────────────────────────────────────────────────────
// Hyprland's tiling layouts. In the shell's Material 3 Expressive panel shape:
//
//   Header  (Settings › Modules › Window layout hides it) the title and the layout's name
//   Hero    the layout you are on and what it does, with its own moves for the focused window as chips
//           (dwindle's split, master's master)
//   Tiles   one per layout: pick one and it is live at once and kept for the next start
//
// Everything real is services/HyprLayout; this shows it and asks.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property real maxHeight: Infinity

    readonly property int pad: Tokens.spacingXl
    readonly property color accent: Colors.of(QsWindow.window).primary
    implicitWidth: Tokens.sideCardUnit * 8
    implicitHeight: Math.min(root.maxHeight, col.implicitHeight + root.pad * 2)

    // Per layout: what its own messages can do to the focused window.
    readonly property var actions: ({
        dwindle: [
            { msg: "togglesplit",
              symbol: "swap_horiz", label: "Toggle split" },
            { msg: "swapsplit",
              symbol: "swap_vert", label: "Swap sides" }
        ],
        master: [
            { msg: "swapwithmaster",
              symbol: "star", label: "Make master" },
            { msg: "addmaster",
              symbol: "add", label: "Add master" },
            { msg: "removemaster",
              symbol: "remove", label: "Fewer masters" },
            { msg: "orientationnext",
              symbol: "cached", label: "Rotate" }
        ],
        scrolling: [],
        monocle: []
    })
    readonly property var here: root.actions[HyprLayout.current] ?? []

    ColumnLayout {
        id: col
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.pad
        spacing: Tokens.spacingSm

        PanelHeader {
            Layout.fillHeight: false
            visible: Config.panelHeader("layout")
            symbol:    "dashboard"
            title:     Translation.tr("Window")
            titleTail: Translation.tr("layout")
            accent:    root.accent
            subtitle:  HyprLayout.info.label
        }

        PanelHero {
            symbol: HyprLayout.info.symbol ?? "dashboard"
            shape: "squircle"
            active: HyprLayout.lastError === ""
            warn: HyprLayout.lastError !== ""
            turning: false
            accent: root.accent
            title: HyprLayout.info.label
            line: HyprLayout.lastError !== "" ? HyprLayout.lastError : HyprLayout.info.about

            // The current layout's own moves, on the focused window.
            footer: Flow {
                Layout.fillWidth: true
                visible: root.here.length > 0
                spacing: Tokens.spacingSm

                Repeater {
                    model: root.here
                    delegate: ChipButton {
                        required property var modelData
                        symbol: modelData.symbol
                        label: modelData.label
                        tint: root.accent
                        onActivated: Hyprland.dispatch(`hl.dsp.layout("${modelData.msg}")`)
                    }
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            columns: 2
            columnSpacing: Tokens.spacingSm
            rowSpacing: Tokens.spacingSm
            uniformCellWidths: true

            Repeater {
                model: HyprLayout.layouts
                delegate: PanelRow {
                    required property var modelData
                    Layout.preferredWidth: 1
                    symbol: modelData.symbol
                    title: modelData.label
                    help: modelData.about
                    shape: "squircle"
                    clickable: true
                    active: HyprLayout.current === modelData.id
                    accent: root.accent
                    onActivated: HyprLayout.set(modelData.id)
                }
            }
        }
    }
}
