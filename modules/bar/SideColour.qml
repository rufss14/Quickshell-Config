pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/sidemodules.js" as Side

// ── SideColour ────────────────────────────────────────────────────────────────
// The sidebar's colour picker: an eyedropper cell, then the last few colours picked
// as swatches (services/ColorPicker). A pick copies its "#rrggbb" to the clipboard
// on the way in; clicking a swatch copies it again, and a check badge says it took.
// Right-click a swatch to forget it; right-click the eyedropper for the settings.
//
// Without hyprpicker the eyedropper stands down, dimmed — the Sidebar page's tile
// says why (ColorPicker.blocker()). The swatches it already has still copy.
//
// The swatches wear the colours picked, which aren't the palette's: they're data,
// the way a colour picker's input is (CLAUDE.md's sanctioned colours) — each with
// the pill's own outline, so one the colour of the pill doesn't vanish into it.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Along the edge: a column on a side, a row along the bottom (SideGroupHost).
    property bool vertical: true

    // Config's module list says "colour" is small; its cells are these —
    // SideRail.cellsFor asks sidemodules.js the same question.
    readonly property var swatches: ColorPicker.history.slice(0, Side.MAX_SWATCHES)
    readonly property int cells: Side.colourCells(ColorPicker.history.length)

    // The swatch just copied, for its check badge; "" once it's gone. How long it
    // stays is an interaction timing, not a Motion duration: with motion off those
    // are 0, and a badge that never shows says nothing.
    property string copied: ""
    readonly property int copiedMs: 1200
    Timer { id: copiedTimer; interval: root.copiedMs; onTriggered: root.copied = "" }
    function flash(hex) {
        root.copied = hex
        copiedTimer.restart()
    }
    Connections {
        target: ColorPicker
        function onLastPickedChanged() {
            if (ColorPicker.lastPicked === "") return
            root.flash(ColorPicker.lastPicked)
            if (Config.peekColour) peek.fire("colour")
        }
    }
    // A pick: its swatch and hex in a peek beside it (modules/panels/EventPeek). The copy it
    // makes finds the slot taken, so it doesn't peek a second time.
    SidePeek { id: peek; from: "colour"; screen: QsWindow.window ? QsWindow.window.screen : null }

    implicitWidth:  root.vertical ? Config.sidebarCell : Config.sidebarRun(root.cells)
    implicitHeight: root.vertical ? Config.sidebarRun(root.cells) : Config.sidebarCell

    Grid {
        columns: root.vertical ? 1 : root.cells
        spacing: Config.sidebarCellGap

        SideCell {
            glyph: "\u{F020A}"                                          // 󰈊 eyedropper
            active: ColorPicker.picking
            hoverKind: "colour"
            opacity: ColorPicker.installed ? 1 : 0.4
            onClicked: ColorPicker.pick()
            onRightClicked: UiState.openSettingsTo("SidebarPage.qml")
        }

        Repeater {
            model: root.swatches

            Item {
                id: swatch
                required property string modelData

                width:  Config.sidebarCell
                height: Config.sidebarCell

                CellFeedback {
                    id: feedback
                    anchors.fill: parent
                    hovered: swatchMouse.containsMouse
                }

                // A glyph's size, so a swatch stands no taller than the eyedropper.
                Rectangle {
                    anchors.centerIn: parent
                    width:  Config.sidebarGlyphPx
                    height: Config.sidebarGlyphPx
                    radius: Tokens.corner(Config.barShape, Tokens.radiusSm)
                    color: swatch.modelData
                    border.width: Tokens.borderWidth
                    border.color: Colors.of(QsWindow.window).outlineFor(Tokens.elevationNested)
                }

                Badge {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    visible: root.copied === swatch.modelData
                    label: "\u{F012C}"                                  // 󰄬 check
                    tint: Colors.of(QsWindow.window).primary
                    filled: true
                }

                MouseArea {
                    id: swatchMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onPressed: function (m) { feedback.press(m.x, m.y) }
                    onReleased: feedback.release()
                    onCanceled: feedback.release()
                    onClicked: function (m) {
                        if (m.button === Qt.RightButton) {
                            ColorPicker.forget(swatch.modelData)
                            return
                        }
                        ColorPicker.copy(swatch.modelData)
                        root.flash(swatch.modelData)
                    }
                }
            }
        }
    }
}
