pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── SideModuleTray ────────────────────────────────────────────────────────────
// ModuleTray's twin for the sidebar: every sidebar module that isn't on it. Drag
// one straight onto the sidebar — it lands exactly where you let go (SideArrange's
// targets) — or click it to put it at its home. Drag one off the sidebar onto this
// card and it comes off. The drag is a PLATFORM drag in both directions (SideDrag):
// this window is an ordinary toplevel and the sidebar a layer surface.
//
// A chip each — the module's glyph and name — rather than a live copy of it: the
// modules sample, count and listen for as long as they exist, and a catalogue
// shouldn't run a second stats sampler to draw a picture.
//
// A module with a missing tool (the colour picker without hyprpicker) is here but
// can't be placed: disabled, and the line below says why (a blocker, never a
// control that fails on use).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    implicitHeight: col.implicitHeight

    readonly property var spare: Config.sidebarModuleList.filter(m => !Config.sidebarPlaced(m.id))
    property string hovered: ""

    function blocker(id) { return id === "colour" ? ColorPicker.blocker() : "" }

    // ── Dropping one here takes it off ────────────────────────────────────────
    DropArea {
        id: trayDrop
        anchors.fill: parent
        keys: [SideDrag.mime]
        onDropped: function (d) {
            const id = SideDrag.idFromDrop(d)
            if (id === "" || !Config.sidebarPlaced(id)) return
            SideDrag.dropExternal(id, { kind: "off" })
            d.acceptProposedAction()
        }
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: -Tokens.spacingSm
        z: -1
        visible: trayDrop.containsDrag
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.12)
        border.width: Tokens.borderWidth
        border.color: Colors.of(QsWindow.window).focus
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Tokens.spacingSm

        StyledText {
            Layout.fillWidth: true
            visible: root.spare.length === 0
            text: Translation.tr("Everything is on the sidebar. Drag one off it onto this card to take it off.")
            variant: "caption"
            emphasis: "dim"
            wrapMode: Text.WordWrap
        }

        Flow {
            Layout.fillWidth: true
            visible: root.spare.length > 0
            spacing: Tokens.spacingSm

            Repeater {
                model: root.spare

                Item {
                    id: tile
                    required property var modelData
                    readonly property string blocked: root.blocker(tile.modelData.id)
                    readonly property bool isHovered: root.hovered === tile.modelData.id

                    implicitWidth:  chip.implicitWidth
                    implicitHeight: chip.implicitHeight
                    opacity: tile.blocked !== "" ? 0.5 : 1

                    // What the pointer carries, too (grabbed on press).
                    Surface {
                        id: chip
                        readonly property int pad: Tokens.spacingMd
                        implicitWidth: chipRow.implicitWidth + chip.pad * 2
                        implicitHeight: Math.max(Config.sidebarCell, chipRow.implicitHeight + chip.pad)
                        elevation: Tokens.elevationNested
                        cornerRadius: Config.sidebarRadius
                        focused: tile.isHovered
                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: Tokens.spacingSm
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: tile.modelData.glyph ?? ""
                                font.family: Tokens.glyphFamily(text)
                                font.pixelSize: Config.sidebarGlyphPx
                                color: tile.isHovered ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).stateIdleFg
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: tile.modelData.label
                                variant: "label"
                            }
                        }
                    }

                    Item {
                        id: proxy
                        width: 1
                        height: 1
                        property bool armed: false
                        Drag.active: proxy.armed
                        Drag.dragType: Drag.Automatic
                        Drag.supportedActions: Qt.MoveAction
                        Drag.proposedAction: Qt.MoveAction
                        Drag.mimeData: {
                            const m = {}
                            m[SideDrag.mime] = tile.modelData.id
                            return m
                        }
                        Drag.hotSpot: Qt.point(tile.width / 2, tile.height / 2)
                        Drag.onDragFinished: {
                            proxy.armed = false
                            SideDrag.cancel()
                        }
                    }

                    MouseArea {
                        id: hit
                        anchors.fill: parent
                        hoverEnabled: true
                        // Blocked, it still answers hover — that's how you learn why.
                        cursorShape: tile.blocked === "" ? Qt.OpenHandCursor : Qt.ForbiddenCursor
                        drag.target: tile.blocked === "" ? proxy : null
                        drag.smoothed: false
                        onEntered: root.hovered = tile.modelData.id
                        onExited: if (root.hovered === tile.modelData.id) root.hovered = ""
                        drag.onActiveChanged: {
                            if (!hit.drag.active) return
                            // Arranging is what gives the sidebar its targets.
                            UiState.sidebarArrange = true
                            SideDrag.dragging = true
                            SideDrag.dragId = tile.modelData.id
                            proxy.armed = true
                        }
                        onPressed: if (tile.blocked === "") chip.grabToImage(function (result) { proxy.Drag.imageSource = result.url },
                                                    Qt.size(Math.max(1, chip.width), Math.max(1, chip.height)))
                        onClicked: if (tile.blocked === "") Config.sidebarAdd(tile.modelData.id)
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacingXs
            visible: root.spare.length > 0
            wrapMode: Text.WordWrap
            variant: "caption"
            emphasis: (root.hovered !== "" || trayDrop.containsDrag) ? "muted" : "dim"
            text: {
                if (trayDrop.containsDrag) return "Let go to take it off the sidebar"
                const m = root.spare.find(x => x.id === root.hovered)
                const why = m ? root.blocker(m.id) : ""
                return why !== "" ? m.label + " — " + why
                     : m ? m.label + " — drag it onto the sidebar, or click to put it at its home"
                     : "Not on the sidebar. Drag one onto it, or drop one here to take it off."
            }
        }
    }
}
