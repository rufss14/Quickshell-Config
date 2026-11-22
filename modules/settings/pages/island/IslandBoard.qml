pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../../config"
import "../../../../components"
import "../../../../services"
import "../../../../state"
import "../../../../config/islands.js" as Islands

// ── IslandBoard ───────────────────────────────────────────────────────────────
// The Island page's board: every island side by side (one IslandBoardColumn per Islands.SIDES, so a new
// island is a new column): the bar's three in a row, each showing its rail in order and the panels that open
// alone in its column, the bottom edge's three under them (rails only: the bottom has no plain column), and
// under those the island's own pages taken off every rail. Drag a page to move it; right-click (or long-press)
// for the same moves as a menu.
//
// It reads UiState.islandLayout and writes only through config/islands.js `move()`: Config.islandRails, plus
// Config.panelPlacement for a panel sent to open alone in another column. With the islands switched off there
// are no rails, and a drag between columns only sets the column (Config.setPanelSide).
//
// The drag is the board's own, not Qt's Drag/DropArea: one page at a time inside one window, and the drop
// index has to come from the rail's slot maths anyway. A copy of the chip follows the pointer; columns open a
// gap where it would land.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The island whose own options the Behaviour card shows ("all" = the shared ones); the page binds it.
    property string scope: "all"
    signal tuned(string side)
    function tune(side) { root.tuned(root.scope === side ? "all" : side) }

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property var layout: UiState.islandLayout
    readonly property bool islands: Config.island
    readonly property int slot: Tokens.iconXl + Tokens.spacingMd

    // Every panel with a column, per side, for the islands-off board.
    function columnPages(side) {
        return Islands.placeable().concat(["launcher", "update"]).filter(k => Config.panelSide(k) === side)
    }

    implicitHeight: body.implicitHeight

    // The tallest natural column of a row (IslandBoardColumn.naturalHeight), so every column of the row can
    // end at the same line.
    function tallest(rep) {
        let m = 0
        for (let i = 0; i < rep.count; i++) {
            const c = rep.itemAt(i)
            if (c) m = Math.max(m, c.naturalHeight)
        }
        return m
    }
    readonly property real topNatural: root.tallest(columns)
    readonly property real bottomNatural: root.tallest(bottomColumns)

    // ── The drag ──────────────────────────────────────────────────────────────
    property string dragKey: ""
    property string overSide: ""
    property string overZone: ""
    property int    overIndex: -1
    property point  grab: Qt.point(0, 0)
    property point  at: Qt.point(0, 0)
    property real   dragW: 0

    function beginDrag(key, chip, scenePos) {
        root.grab = chip.mapFromItem(null, scenePos.x, scenePos.y)
        root.dragW = chip.width
        root.dragKey = key
        root.moveDrag(scenePos)
    }
    function moveDrag(scenePos) {
        root.at = root.mapFromItem(null, scenePos.x, scenePos.y)
        const hit = root.hitAt(scenePos)
        root.overSide = hit ? hit.side : ""
        root.overZone = hit ? hit.zone : ""
        root.overIndex = hit ? hit.index : -1
    }
    function endDrag() {
        const key = root.dragKey, side = root.overSide, zone = root.overZone, index = root.overIndex
        root.dragKey = ""
        root.overSide = ""
        root.overZone = ""
        root.overIndex = -1
        // Later, not now: the move rebuilds the list the dragged chip is in, from inside that chip's handler.
        if (key !== "" && zone !== "") Qt.callLater(root.place, key, zone, side, index)
    }

    // Which list a scene point is over: { side, zone, index } or null.
    function hitAt(scenePos) {
        if (root.islands && hiddenTray.visible) {
            const t = hiddenTray.mapFromItem(null, scenePos.x, scenePos.y)
            if (t.x >= 0 && t.x <= hiddenTray.width && t.y >= 0 && t.y <= hiddenTray.height)
                return { side: "", zone: "hidden", index: 0 }
        }
        for (const rep of [columns, bottomColumns]) {
            for (let i = 0; i < rep.count; i++) {
                const c = rep.itemAt(i)
                if (!c || !c.visible) continue
                const p = c.mapFromItem(null, scenePos.x, scenePos.y)
                const z = c.zoneAt(p.x, p.y)
                if (z) return { side: c.side, zone: z.zone, index: z.index }
            }
        }
        return null
    }

    // Puts a page somewhere. The index on its own rail counts the page itself, which leaves first.
    function place(key, zone, side, index) {
        if (Islands.LOCKED[key]) return
        if (!root.islands) {
            if (zone === "alone" && side !== "") Config.setPanelSide(key, side)
            return
        }
        let i = index
        if (zone === "rail" && Islands.railOf(key, root.layout) === side) {
            const cur = root.layout.rails[side].indexOf(key)
            if (cur >= 0 && i > cur) i--
        }
        const r = Islands.move(root.layout, key, zone, side, i)
        if (!r) return
        Config.islandRails = r.rails
        if (r.column !== "") Config.setPanelSide(key, r.column)
    }

    // ── The menu ──────────────────────────────────────────────────────────────
    property string menuKey: ""
    function _label(side) { return Translation.tr(Islands.sideMeta(side).label) }
    function menuItems(key) {
        const out = []
        if (!root.islands) {
            const here = Config.panelSide(key)
            for (const s of Islands.COLUMNS)
                if (s !== here) out.push({ key: "col:" + s, label: Translation.tr("Open in the %1 column").arg(root._label(s).toLowerCase()) })
            return out
        }
        const rail = Islands.railOf(key, root.layout)
        for (const s of Islands.SIDES)
            if (s !== rail) out.push({ key: "rail:" + s, label: Translation.tr("Put on the %1 island").arg(root._label(s).toLowerCase()) })
        if (rail !== "") {
            const list = root.layout.rails[rail], at = list.indexOf(key)
            if (at > 0 || at < list.length - 1) out.push({ separator: true })
            if (at > 0) out.push({ key: "up", label: Translation.tr("Move up") })
            if (at < list.length - 1) out.push({ key: "down", label: Translation.tr("Move down") })
            out.push({ separator: true })
            out.push(Islands.hasColumn(key) ? { key: "alone", label: Translation.tr("Open alone instead") }
                                            : { key: "hide", label: Translation.tr("Take off every island") })
        } else if (Islands.hasColumn(key)) {
            const here = Config.panelSide(key)
            const cols = Islands.COLUMNS.filter(s => s !== here)
            if (cols.length > 0) out.push({ separator: true })
            for (const s of cols)
                out.push({ key: "col:" + s, label: Translation.tr("Open alone in the %1 column").arg(root._label(s).toLowerCase()) })
        }
        return out
    }
    function openMenu(key, item, x, y) {
        root.menuKey = key
        menu.items = root.menuItems(key)
        const p = item.mapToItem(null, x, y)
        menu.openAt(p.x, p.y)
    }
    function onMenu(action) {
        const key = root.menuKey
        if (key === "") return
        const parts = action.split(":")
        const rail = Islands.railOf(key, root.layout)
        if (parts[0] === "rail") root.place(key, "rail", parts[1], 1e9)
        else if (parts[0] === "col") root.place(key, "alone", parts[1], 0)
        else if (action === "up" || action === "down") {
            const at = root.layout.rails[rail].indexOf(key)
            // `place` counts the page itself on its own rail: one further down is two slots on.
            root.place(key, "rail", rail, action === "up" ? at - 1 : at + 2)
        }
        else if (action === "alone") root.place(key, "alone", Config.panelSide(key), 0)
        else if (action === "hide") root.place(key, "hidden", "", 0)
    }

    ColumnLayout {
        id: body
        width: root.width
        spacing: Tokens.spacingMd

        // ── The islands ───────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingLg
            uniformCellSizes: true

            Repeater {
                id: columns
                model: Islands.COLUMNS
                delegate: IslandBoardColumn {
                    required property string modelData
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    side: modelData
                    board: root
                    islands: root.islands
                    stretchTo: root.topNatural
                    railPages: root.islands ? (root.layout.rails[modelData] || []) : []
                    alonePages: root.islands ? (root.layout.alone[modelData] || []) : root.columnPages(modelData)
                }
            }
        }

        // ── The bottom edge ───────────────────────────────────────────────────
        // The sidebar's buttons open these (and their handles on the screen's bottom edge). No plain column
        // down there: a page sent "alone" from here opens in its bar column.
        StyledText {
            visible: root.islands
            Layout.topMargin: Tokens.spacingSm
            leftPadding: Tokens.spacingSm
            text: Translation.tr("Along the bottom")
            variant: "caption"
            emphasis: "muted"
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.islands
            spacing: Tokens.spacingLg
            uniformCellSizes: true

            Repeater {
                id: bottomColumns
                model: Islands.BOTTOM
                delegate: IslandBoardColumn {
                    required property string modelData
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    side: modelData
                    board: root
                    islands: root.islands
                    hasColumn: false
                    stretchTo: root.bottomNatural
                    railPages: root.islands ? (root.layout.rails[modelData] || []) : []
                }
            }
        }

        // ── Taken off every island ────────────────────────────────────────────
        // The island's own pages with no bar panel to fall back on (Dashboard, Performance, Weather): off every
        // rail they are nowhere, so they wait here. Media off every rail opens alone as Now Playing instead.
        Rectangle {
            id: hiddenTray
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.islands
            implicitHeight: trayRow.implicitHeight + Tokens.spacingSm * 2
            radius: Tokens.radiusCard
            readonly property bool over: root.dragKey !== "" && root.overZone === "hidden"
            color: over ? root.palette.alpha(root.palette.primary, 0.1) : root.palette.alpha(root.palette.fg, 0.04)
            // An outline only as a drop target lights; at rest the well is a tone, not a box.
            border.width: over ? Tokens.borderWidth : 0
            border.color: root.palette.alpha(root.palette.primary, 0.6)
            Behavior on color { ColorAnimation { duration: Motion.respond } }

            Flow {
                id: trayRow
                x: Tokens.spacingMd
                y: Tokens.spacingSm
                width: parent.width - Tokens.spacingMd * 2
                spacing: Tokens.spacingSm

                StyledText {
                    height: root.slot
                    verticalAlignment: Text.AlignVCenter
                    rightPadding: Tokens.spacingMd
                    text: root.layout.hidden.length > 0 ? Translation.tr("On no island")
                                                        : Translation.tr("On no island: drop a page here to take it off")
                    variant: "caption"
                    emphasis: "muted"
                }
                Repeater {
                    model: root.layout.hidden
                    delegate: IslandPageChip {
                        required property string modelData
                        width: Tokens.iconXl * 6
                        height: root.slot
                        key: modelData
                        lifted: root.dragKey === modelData
                        board: root
                    }
                }
            }
        }
    }

    // ── The carried page ──────────────────────────────────────────────────────
    // Outside the layout (a layout places its children and would overrule x and y), over everything.
    IslandPageChip {
        visible: root.dragKey !== ""
        z: 100
        x: root.at.x - root.grab.x
        y: root.at.y - root.grab.y
        width: root.dragW
        height: root.slot
        key: root.dragKey
        lead: true
        scale: 1.04

        Rectangle {
            z: -1
            anchors.fill: parent
            radius: height / 2
            color: root.palette.surfaceHigh
        }
    }

    ContextMenu {
        id: menu
        anchors.fill: parent
        menuWidth: 260
        onTriggered: key => root.onMenu(key)
    }
}
