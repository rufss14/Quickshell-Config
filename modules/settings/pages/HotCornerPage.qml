pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"
import "../../../services/deskmenu.js" as Menus
import "../../desktop/widgets/toggles.js" as Toggles

// ── HotCornerPage — Desktop › Hot corner ──────────────────────────────────────
// Which corner opens the panel, what the panel holds, and which switches it carries
// (modules/panels/HotCorner). The loud card is the screen in small, with the master switch: press a corner
// and the panel slides there, so the choice is seen, not described. It is the corner PICKER (each puck is
// the control), not a picture of a panel to compare against. The rest are grouped rows
// (docs/settings-style.md 1.6): Feel as sliders, Panel and Switches as the order pickers.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)

    readonly property var corners: [
        { value: "topLeft",     label: "Top left",     top: true,  left: true },
        { value: "topRight",    label: "Top right",    top: true,  left: false },
        { value: "bottomLeft",  label: "Bottom left",  top: false, left: true },
        { value: "bottomRight", label: "Bottom right", top: false, left: false }
    ]
    readonly property var current: root.corners.find(c => c.value === Config.hotCornerEdge) ?? root.corners[3]

    // The sections shown, in order (the stage draws one bar for each).
    readonly property var shown: Menus.known(Config.hotCornerParts, Menus.PARTS)

    SettingsPage {
        anchors.fill: parent

        grouped:   true
        glyph:     "󰕮"
        title:     Translation.tr("Hot")
        titleTail: Translation.tr("corner")
        accent:    root.palette.primary
        subtitle:  Config.hotCorner ? Translation.tr("Rest the pointer in a corner and the panel slides out")
                                    : Translation.tr("Off, so the corner does nothing")

        // ══ The corner ════════════════════════════════════════════════════════
        // The loud card is the screen in small, with the page's one master switch: press a corner puck
        // and the panel moves there, so the choice is seen, not described.
        Section {
            id: heroCard
            hero:  true

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                columns: width >= 560 ? 2 : 1
                columnSpacing: Tokens.spacingLg
                rowSpacing: Tokens.spacingMd

                Rectangle {
                    id: stage
                    Layout.fillWidth: true
                    Layout.maximumWidth: 520
                    Layout.preferredWidth: 360
                    Layout.preferredHeight: Math.round(width * 0.4)
                    Layout.alignment: Qt.AlignTop
                    // Concentric with the card: its radius less the card's padding.
                    radius: Tokens.radiusXl - heroCard.padding
                    color: root.palette.surface
                    opacity: Config.hotCorner ? 1 : 0.5
                    Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                    readonly property real inset: Tokens.spacingLg
                    readonly property real pw: Math.round(width * 0.24)
                    readonly property real ph: Math.round(height * 0.7)

                    // The panel, where it will open.
                    Rectangle {
                        id: mockPanel
                        width: stage.pw
                        height: stage.ph
                        radius: Math.max(Tokens.spacingMd, stage.radius - stage.inset)
                        color: root.palette.primaryContainer
                        x: root.current.left ? stage.inset : stage.width - width - stage.inset
                        y: root.current.top ? stage.inset : stage.height - height - stage.inset
                        Behavior on x { NumberAnimation { duration: Motion.emphasized; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
                        Behavior on y { NumberAnimation { duration: Motion.emphasized; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }

                        Column {
                            anchors.fill: parent
                            anchors.margins: Tokens.spacingMd
                            spacing: Tokens.spacingSm
                            // One bar per section shown: the stage follows the choices below it.
                            Repeater {
                                id: bars
                                model: Math.max(1, root.shown.length)
                                Rectangle {
                                    required property int index
                                    width: parent.width
                                    height: (mockPanel.height - Tokens.spacingMd * 2 - Tokens.spacingSm * (bars.count - 1)) / bars.count
                                    radius: Tokens.spacingSm
                                    color: root.palette.alpha(root.palette.fgOnPrimaryContainer, index === 0 ? 0.28 : 0.14)
                                }
                            }
                        }
                    }

                    // The four corners to press.
                    Repeater {
                        model: root.corners
                        delegate: Item {
                            id: puck
                            required property var modelData
                            readonly property bool chosen: Config.hotCornerEdge === puck.modelData.value
                            width: Tokens.iconXl
                            height: Tokens.iconXl
                            x: puck.modelData.left ? Tokens.spacingSm : stage.width - width - Tokens.spacingSm
                            y: puck.modelData.top ? Tokens.spacingSm : stage.height - height - Tokens.spacingSm
                            visible: !puck.chosen

                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: root.palette.alpha(root.palette.fg, puckMouse.containsMouse ? Tokens.stateDrag : Tokens.stateHover)
                                Behavior on color { ColorAnimation { duration: Motion.respond } }
                            }
                            MaterialIcon {
                                anchors.centerIn: parent
                                name: "add"
                                font.pixelSize: Tokens.iconSm
                                color: root.palette.fgMuted
                            }
                            MouseArea {
                                id: puckMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Config.hotCornerEdge = puck.modelData.value
                            }
                            HoverTip { text: Translation.tr(puck.modelData.label) }
                        }
                    }
                }

                // The name, the state and the master switch.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 220
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Tokens.spacingMd

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingMd

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: 0
                            StyledText {
                                text: Translation.tr("Hot corner")
                                variant: "title"
                                font.weight: Font.Bold
                                color: heroCard.ink
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Config.hotCorner ? Translation.tr(root.current.label) : Translation.tr("Switched off")
                                variant: "caption"
                                color: heroCard.inkDim
                                elide: Text.ElideRight
                            }
                        }
                        Toggle {
                            Layout.alignment: Qt.AlignVCenter
                            accent: root.palette.primary
                            accessibleName: Translation.tr("Hot corner")
                            checked: Config.hotCorner
                            onToggled: Config.hotCorner = !Config.hotCorner
                        }
                    }

                    // Only while it is on: with the corner off there is nothing to try.
                    ChipButton {
                        visible: Config.hotCorner
                        symbol: "play_arrow"
                        label: Translation.tr("Try it")
                        solid: true
                        onActivated: {
                            UiState.hotCornerByKey = true
                            UiState.hotCornerScreen = ""
                            UiState.hotCornerOpen = true
                        }
                    }
                }
            }
        }

        // ══ What the panel holds ══════════════════════════════════════════════
        Section {
            grouped:  true
            symbol:   "view_quilt"
            title:    Translation.tr("Panel")
            help:     Translation.tr("Tap a section to show it; the arrows set the order.")

            PickOrderList {
                Layout.fillWidth: true
                table: Menus.PARTS
                allIds: Menus.PART_ORDER
                shown: Config.hotCornerParts
                onPicked: list => Config.hotCornerParts = list
            }
        }

        // ══ Switches ══════════════════════════════════════════════════════════
        Section {
            grouped:  true
            visible:  Config.hotCornerParts.indexOf("toggles") >= 0
            symbol:   "dashboard"
            title:    Translation.tr("Switches")
            help:     Translation.tr("Up to eight, shown in the order you pick them.")

            PickOrderList {
                Layout.fillWidth: true
                table: Toggles.PICKABLE
                allIds: Toggles.ALL
                shown: Config.hotCornerToggles
                max: 8
                onPicked: list => Config.hotCornerToggles = list
            }
        }

        // ══ How it behaves ════════════════════════════════════════════════════
        Section {
            grouped: true
            symbol:  "tune"
            title:   Translation.tr("Feel")
            help:    Translation.tr("Nothing opens while a fullscreen window is on that screen. A key opens it too: qs ipc call hotcorner toggle.")

            SliderRow {
                label: Translation.tr("Opens after")
                help:  Translation.tr("How long the pointer rests in the corner before the panel opens. Short is quick; longer keeps a pointer that is only passing through from opening it.")
                from: 0
                to: 600
                step: 20
                value: Config.hotCornerDelay
                readout: Config.hotCornerDelay + " ms"
                numberWidth: 72
                onCommit: function (v) { Config.hotCornerDelay = Math.round(v) }
            }
            SliderRow {
                label: Translation.tr("Closes after")
                help:  Translation.tr("How long the pointer must be away from the panel before it goes. Longer forgives a slip off the edge.")
                from: 150
                to: 1500
                step: 50
                value: Config.hotCornerLinger
                readout: Config.hotCornerLinger + " ms"
                numberWidth: 72
                onCommit: function (v) { Config.hotCornerLinger = Math.round(v) }
            }
            SliderRow {
                label: Translation.tr("Size")
                help:  Translation.tr("The whole panel, text and icons together.")
                from: 80
                to: 130
                step: 5
                value: Math.round(Config.hotCornerScale * 100)
                readout: Math.round(Config.hotCornerScale * 100) + " %"
                numberWidth: 64
                onCommit: function (v) { Config.hotCornerScale = Math.round(v) / 100 }
            }
        }
    }
}
