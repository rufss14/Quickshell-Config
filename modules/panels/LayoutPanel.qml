pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"

// ── LayoutPanel ───────────────────────────────────────────────────────────────
// Hyprland's tiling layouts as four cards — pick one and it is live at once and kept
// for the next start (services/HyprLayout) — and, under them, the few layout messages
// that matter for the one you're on (dwindle's split, master's master).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property real maxHeight: Infinity

    readonly property int pad: Tokens.spacingLg
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
        spacing: Tokens.spacingMd

        PanelHeader {
            Layout.fillHeight: false
            glyph:     "\u{F0574}"                                   // 󰕴 view-dashboard
            title:     Translation.tr("Window")
            titleTail: "layout"
            accent:    Colors.of(QsWindow.window).primary
            subtitle:  HyprLayout.lastError !== "" ? HyprLayout.lastError
                     : HyprLayout.info.label + " — " + HyprLayout.info.about
        }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            columns: 2
            columnSpacing: Tokens.spacingSm
            rowSpacing: Tokens.spacingSm

            Repeater {
                model: HyprLayout.layouts
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    readonly property bool on: HyprLayout.current === card.modelData.id

                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    implicitHeight: 56
                    radius: Tokens.radiusPill
                    color: card.on ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.22)
                         : cardHover.hovered ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
                         : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.04)
                    border.width: Tokens.borderWidth
                    border.color: card.on ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.55)
                                          : Colors.of(QsWindow.window).outline
                    Behavior on color { ColorAnimation { duration: Motion.respond } }

                    scale: cardTap.pressed ? 0.96 : 1
                    Behavior on scale { NumberAnimation { duration: Motion.respond; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.spacingMd
                        anchors.rightMargin: Tokens.spacingMd
                        spacing: Tokens.spacingMd

                        MaterialIcon {
                            name: card.modelData.symbol
                            fill: card.on ? 1 : 0
                            color: card.on ? Colors.of(QsWindow.window).focus : Colors.of(QsWindow.window).fgMuted
                            font.pixelSize: Tokens.iconLg
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: card.modelData.label
                            variant: "body"
                            font.weight: card.on ? Font.DemiBold : Font.Medium
                            color: card.on ? Colors.of(QsWindow.window).focus : Colors.of(QsWindow.window).fg
                        }
                    }

                    HelpTip { text: card.modelData.about }
                    HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: cardTap; onTapped: HyprLayout.set(card.modelData.id) }
                }
            }
        }

        // The current layout's own moves, on the focused window.
        Flow {
            Layout.fillWidth: true
            visible: root.here.length > 0
            spacing: Tokens.spacingSm

            Repeater {
                model: root.here
                delegate: PanelButton {
                    required property var modelData
                    variant: "normal"
                    symbol: modelData.symbol
                    label: modelData.label
                    onActivated: Hyprland.dispatch(`hl.dsp.layout("${modelData.msg}")`)
                }
            }
        }
    }
}
