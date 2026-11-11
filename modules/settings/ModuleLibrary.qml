pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../config/modules.js" as Catalogue
import "../bar/sidecells.js" as SideCells

// ── ModuleLibrary ─────────────────────────────────────────────────────────────
// Every module the shell has, on shelves by kind — what replaced the "Not on the bar"
// card (2026-11-08). That card was a flat row of dimmed widgets with one hover caption
// ("Point at one to see what it is"): it showed only what was missing from ONE surface,
// named nothing until you hovered, and said nothing about what a module does. The user
// found it boring and awkward.
//
// A tile says the four things you need to choose: what it LOOKS like (the real widget,
// inert), what it's called, what it does (the catalogue's one-line `blurb`), and where
// it is now (a Bar / Sidebar badge, or "+ Add" when it's nowhere). Placed modules stay
// on their shelf, dimmed — it's the whole catalogue, not a leftovers bin — and the
// Unused chip narrows it to the rest. A module whose tool is missing is greyed out
// with the reason (BarModules.blocker), never failing on click.
//
//   click a tile   pick it — the inspector above edits it
//   + Add          put it where it belongs (its catalogue `native` surface, at home)
//   drag a tile    onto the real bar or sidebar (armed while the page is open)
//   drop on here   take a module off whichever surface it's on
//
// Shelves, search and the filter are pure functions in config/modules.js
// (`shelves`, `matches`; bun scripts/test-modules.js).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The bar's widget factory (PreviewModules.componentFor).
    property var componentFor: null

    property string query: ""
    property string filter: "all"          // "all" | "unused"

    readonly property var shelves: {
        void Config.layout; void Config.sidebarLayout
        return Catalogue.shelves(root.query, root.filter, id => Config.surfaceOf(id) !== "")
    }
    readonly property int unusedCount: {
        void Config.layout; void Config.sidebarLayout
        return Catalogue.MODULES.filter(m => Config.surfaceOf(m.id) === "").length
    }

    readonly property real tileW: 168

    implicitHeight: col.implicitHeight

    // ── Dropping a module here takes it off ───────────────────────────────────
    // The library IS "not on either surface", so the whole card is the target.
    DropArea {
        id: libDrop
        anchors.fill: parent
        keys: [ModuleDrag.mime]
        onDropped: function (d) {
            const id = ModuleDrag.idFromDrop(d)
            if (id === "" || Config.surfaceOf(id) === "") return
            Config.placeModule(id, "")
            ModuleDrag.end()
            d.acceptProposedAction()
        }
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: -Tokens.spacingSm
        z: -1
        visible: libDrop.containsDrag
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).danger, 0.08)
        border.width: Tokens.borderWidth
        border.color: Colors.of(QsWindow.window).danger
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.spacingLg

        // ── Search and filter ─────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd

            InputField {
                Layout.fillWidth: true
                cornerRadius: implicitHeight / 2
                icon: "search"
                placeholder: Translation.tr("Search modules")
                onEdited: function (v) { root.query = v }
            }
            SegmentSwitch {
                implicitWidth: 220
                accent: Colors.of(QsWindow.window).primary
                model: [
                    { value: "all",    label: Translation.tr("All") },
                    { value: "unused", label: Translation.tr("Unused") + "  " + root.unusedCount }
                ]
                current: root.filter
                onPicked: function (v) { root.filter = v }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.shelves.length === 0
            text: root.filter === "unused" && root.query === "" ? Translation.tr("Every module is on the bar or the sidebar")
                                                                 : Translation.tr("No module matches")
            variant: "caption"
            emphasis: "dim"
        }

        // ── The shelves ───────────────────────────────────────────────────────
        Repeater {
            model: root.shelves

            delegate: ColumnLayout {
                id: shelf
                required property var modelData
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    MaterialIcon {
                        name: shelf.modelData.symbol
                        font.pixelSize: Tokens.iconSm
                        color: Colors.of(QsWindow.window).primary
                    }
                    StyledText {
                        text: shelf.modelData.label
                        variant: "label"
                        font.weight: Font.Medium
                    }
                    StyledText {
                        text: String(shelf.modelData.modules.length)
                        variant: "caption"
                        emphasis: "dim"
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: Tokens.borderWidth
                        color: Colors.of(QsWindow.window).outlineFor(Tokens.elevationNested)
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingSm
                    Repeater {
                        model: shelf.modelData.modules
                        delegate: Tile {}
                    }
                }
            }
        }
    }

    // ── One module ────────────────────────────────────────────────────────────
    component Tile: Rectangle {
        id: tile
        required property var modelData

        readonly property string mid: tile.modelData.id
        readonly property string where: {
            void Config.layout; void Config.sidebarLayout
            return Config.surfaceOf(tile.mid)
        }
        readonly property string blocked: tile.where === "" ? BarModules.blocker(tile.mid) : ""
        readonly property bool picked: UiState.barInspectModule === tile.mid
        readonly property bool hot: hit.containsMouse

        width: root.tileW
        height: body.implicitHeight + Tokens.spacingMd * 2
        radius: Tokens.radiusCard
        color: tile.hot ? Colors.of(QsWindow.window).surfaceFor(Tokens.elevationPopup)
                        : Colors.of(QsWindow.window).surfaceFor(Tokens.elevationNested)
        border.width: tile.picked ? 2 : 0
        border.color: Colors.of(QsWindow.window).primary
        Behavior on color { ColorAnimation { duration: Motion.respond } }

        ColumnLayout {
            id: body
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.spacingMd
            spacing: Tokens.spacingXs
            // Placed (it's on a surface already) or blocked: quieter than the rest.
            opacity: tile.blocked !== "" ? 0.5 : tile.where !== "" && !tile.hot ? 0.7 : 1
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }

            // The widget itself, inert, fitted into a fixed well so a wide clock and
            // a lone icon sit the same way.
            Item {
                id: well
                Layout.fillWidth: true
                Layout.fillHeight: false
                implicitHeight: Tokens.pillHeight + Tokens.spacingSm * 2
                clip: true
                Loader {
                    id: widget
                    anchors.centerIn: parent
                    enabled: false
                    readonly property real fit: widget.item && widget.item.width > well.width
                        ? well.width / widget.item.width : 1
                    scale: widget.fit
                    sourceComponent: tile.modelData.bar
                        ? (root.componentFor ? root.componentFor(tile.mid) : null) : null
                    source: tile.modelData.bar ? ""
                          : (SideCells.file(tile.mid) !== "" ? Qt.resolvedUrl("../bar/" + SideCells.file(tile.mid)) : "")
                    onLoaded: {
                        const m = widget.item
                        if (!m) return
                        if (m.vertical !== undefined) m.vertical = false
                        if (m.moduleId !== undefined) m.moduleId = tile.mid
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: tile.modelData.label
                variant: "label"
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: tile.blocked !== "" ? tile.blocked : tile.modelData.blurb
                variant: "caption"
                color: tile.blocked !== "" ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).fgMuted
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                // Two lines' worth always, so tiles on a row line up.
                Layout.preferredHeight: Math.ceil(fontInfo.pixelSize * 1.35) * 2
            }

            // Where it is now — or the way to put it somewhere.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingXs
                StyledText {
                    visible: tile.where !== ""
                    text: tile.where === "bar" ? Translation.tr("On the bar") : Translation.tr("On the sidebar")
                    variant: "caption"
                    color: Colors.of(QsWindow.window).primary
                }
                Item { Layout.fillWidth: true }
                ChipButton {
                    visible: tile.where === "" && tile.blocked === ""
                    symbol: "add"
                    label: Translation.tr("Add")
                    tint: Colors.of(QsWindow.window).primary
                    onActivated: {
                        Config.placeModule(tile.mid, tile.modelData.native)
                        UiState.inspectBarModule(tile.mid)
                    }
                }
            }
        }

        // ── A source: onto the real bar / sidebar ─────────────────────────────
        // BarGroupRow's drag proxy (its comments say why each part is that way).
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
                m[ModuleDrag.mime] = tile.mid
                return m
            }
            Drag.hotSpot: Qt.point(well.width / 2, well.height / 2)
            Drag.onDragFinished: {
                proxy.armed = false
                ModuleDrag.end()
            }
        }

        MouseArea {
            id: hit
            // Under the + Add chip, which takes its own clicks.
            z: -1
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: tile.blocked !== "" ? Qt.ForbiddenCursor : Qt.PointingHandCursor
            drag.target: tile.blocked === "" ? proxy : null
            drag.smoothed: false
            // The real surfaces only take a drop while arranging. The page arms it on
            // open; a drag after Done arms it again rather than landing nowhere.
            drag.onActiveChanged: {
                if (!hit.drag.active) return
                UiState.arrange = true
                ModuleDrag.begin(tile.mid, "settings")
                proxy.armed = true
            }
            onPressed: if (tile.blocked === "") well.grabToImage(function (r) { proxy.Drag.imageSource = r.url })
            onClicked: UiState.inspectBarModule(tile.mid)
        }
    }

}
