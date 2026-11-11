pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../components"
import "../../state"
import "sidecells.js" as SideCells

// ── SideGroupHost ─────────────────────────────────────────────────────────────
// A pill of small sidebar modules — the stats and clips buttons, Power, Shell
// tools… — side by side, the way the top bar's BarGroup holds its modules. Bar.qml
// makes one per group the rail placed (SideRail.smallGroups), keyed on the group's
// ids, so a group that only moves along the edge keeps its delegate. The dock isn't
// one of these: it has a host of its own and stands alone (dock.js sideGroups).
//
// ── Riding the sidebar's own reveal ───────────────────────────────────────────
// It eases nothing of its own: its box is `rail.cross` out of the frame — the
// sidebar's reveal as it moves (SideBarHost) — so it can't drift from the bar or its
// neighbours; the sidebar bar's lobe and input mask cover it. Sunk under a panel in the near corner (SideRail.startCollapsed) it drops
// straight to nothing — the one thing it can't ease.
//
// ── What it draws ─────────────────────────────────────────────────────────────
// The top bar's inner pill round its modules (the sidebar's bar is the surface), and
// each module where the rail put it: a module's length carries its own margin (SideRail.pad), so two
// modules in one pill stand the top bar's gap apart.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: host

    required property SideRail rail
    // The group: its ids, joined (SideRail.smallGroups' `key`).
    required property string groupKey
    // This sidebar's screen, where a module opens what it opens, and its monitor.
    property var screen: null
    property var monitor: null
    // The tray's right-click menu (Bar.qml's BarContextMenu), for SideTray.
    property var contextMenu: null
    // The sidebar bar's spring deformation; identity while the plugin is absent.
    property matrix4x4 deformMatrix

    readonly property var group: host.rail.smallGroup(host.groupKey)
    readonly property var ids: host.groupKey.split(",")
    readonly property real pos: host.group ? host.group.pos : 0
    readonly property real len: host.group ? host.group.len : 0

    readonly property string edge: host.rail.edge
    readonly property bool vertical: host.rail.vertical
    readonly property bool collapsed: host.group !== null && host.group.region === "start"
                                      && host.rail.startCollapsed
    readonly property real cross: host.collapsed ? 0 : host.rail.cross
    readonly property int depth: host.rail.depth
    readonly property real edgePos: host.rail.edgePos(host.width, host.height)

    // The hover plate of the region pill this group stands in (SideRegionPills), for the
    // buttons in it to share (HoverTrack, found by ancestry).
    // An island's own first (Config.sidebarIslands: SideRegionPills keys it "region:ids").
    readonly property var hoverTrack: !host.group ? null
        : host.rail.regionTracks[host.group.region + ":" + host.group.key]
          ?? host.rail.regionTracks[host.group.region] ?? null

    // ── The registry ──────────────────────────────────────────────────────────
    // id → the module's file (sidecells.js, shared with the settings map). Loaded by
    // URL, not as a typed component — sidecells.js says why.
    function moduleUrl(id) {
        const f = SideCells.file(id)
        return f === "" ? "" : Qt.resolvedUrl(f)
    }

    // ── The pointer on it holds the sidebar out ───────────────────────────────
    // Counted on the rail (SideRail.smallHovered), and uncounted if this goes away
    // under the pointer — a group re-keyed, a module taken off.
    property bool _counted: false
    function _count(on) {
        if (on === host._counted) return
        host._counted = on
        // The rail can already be gone when the whole bar is torn down (a reload).
        if (host.rail) host.rail.smallHovered += on ? 1 : -1
    }
    Component.onDestruction: host._count(false)

    // The box as it slides out of the frame, pinned at the surface's screen-edge
    // side (SideRail.edgePos) and `cross` deep.
    Item {
        id: reveal

        x: host.edge === "left"  ? host.edgePos
         : host.edge === "right" ? host.edgePos - host.cross
         :                         host.pos
        y: host.vertical ? host.pos : host.edgePos - host.cross
        width:  host.vertical ? host.cross : host.len
        height: host.vertical ? host.len : host.cross
        // Behind the frame's strip until it's out (DockHost's reveal says why).
        clip: host.rail.strip > 0
        visible: host.group !== null && host.cross > 0.5

        // At rest, riding the box's moving edge (DockHost's band).
        Item {
            id: band

            width:  host.vertical ? host.depth : host.len
            height: host.vertical ? host.len : host.depth
            x: host.edge === "left" ? reveal.width - host.depth : 0
            y: 0

            transform: Matrix4x4 { matrix: host.deformMatrix }

            HoverHandler {
                id: hover
                onHoveredChanged: host._count(hover.hovered)
            }

            // No inner pill of its own any more: the group stands on its region's
            // (SideRegionPills, 2026-10-31 — one pill per region, a divider between groups).

            // The pill between its cells: right-click, the sidebar's settings.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: UiState.openSettingsTo("SidebarPage.qml")
            }

            // Each module at its place along the pill (SideRail.at, less the group's
            // start, past its own margin), centred across it.
            Repeater {
                model: host.ids

                Item {
                    id: slot
                    required property string modelData

                    readonly property real along:
                        (host.rail.at[slot.modelData] ?? host.pos) - host.pos + host.rail.pad

                    x: host.vertical ? Math.round((band.width - moduleItem.width) / 2) : slot.along
                    y: host.vertical ? slot.along : Math.round((band.height - moduleItem.height) / 2)
                    width:  moduleItem.width
                    height: moduleItem.height

                    // Arranging: the module is a thing being moved, not a control
                    // (SideArrange's handles sit over it), and the one in the hand
                    // dims where it came from.
                    enabled: !UiState.sidebarArrange
                    opacity: SideDrag.dragging && SideDrag.dragId === slot.modelData ? 0.25 : 1
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                    Component.onCompleted: host.rail.registerItem(slot.modelData, moduleItem)
                    Component.onDestruction: if (host.rail) host.rail.unregisterItem(slot.modelData, moduleItem)

                    // No size of its own: a Loader sized explicitly resizes its item
                    // (CLAUDE.md, API caution). What every module takes: which way it
                    // runs, and — where it has them — the screen it opens things on,
                    // its monitor, and whether it's on screen (sampling, clocks).
                    Loader {
                        id: moduleItem
                        source: host.moduleUrl(slot.modelData)
                        onLoaded: {
                            const m = moduleItem.item
                            m.vertical = Qt.binding(() => host.vertical)
                            if (m.moduleId !== undefined) m.moduleId = slot.modelData
                            if (m.screen !== undefined)  m.screen  = Qt.binding(() => host.screen)
                            if (m.monitor !== undefined) m.monitor = Qt.binding(() => host.monitor)
                            if (m.contextMenu !== undefined) m.contextMenu = Qt.binding(() => host.contextMenu)
                            if (m.shown !== undefined)
                                m.shown = Qt.binding(() => host.rail.barShown && !host.collapsed)
                        }
                    }
                }
            }
        }
    }
}
