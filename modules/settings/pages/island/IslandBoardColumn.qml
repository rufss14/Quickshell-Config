pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../../../config"
import "../../../../components"
import "../../../../services"
import "../../../../config/islands.js" as Islands

// ── IslandBoardColumn ─────────────────────────────────────────────────────────
// One island on the Island page's board (IslandBoard): its name and handle mark, its RAIL (the pages in the
// order the island's rail shows them) and, under it, the panels that OPEN ALONE in that side's plain column.
// While the islands are switched off there are no rails: the column is only that side's plain column.
// The board does the dragging; a column says where a point lands (`zoneAt`) and opens a gap there.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string side: "center"
    property Item board: null
    // Islands on: a rail and the alone list. Off: only the column.
    property bool islands: true
    property var railPages: []
    property var alonePages: []
    // A bottom-row island has no plain column under it: no "Opens alone" list.
    property bool hasColumn: true
    // The tallest natural height among the columns of this row (the board sets it): the last well here
    // grows to meet it, so a short island ends flush with its neighbours instead of leaving a hole below.
    property real stretchTo: 0

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property var sideMeta: Islands.sideMeta(root.side)
    readonly property int slot: Tokens.iconXl + Tokens.spacingMd
    readonly property int gap: Tokens.spacingXs
    readonly property int pad: Tokens.spacingSm
    readonly property int step: root.slot + root.gap

    // Where a page being carried would land on this column, -1 for nowhere.
    readonly property bool overMe: root.board !== null && root.board.dragKey !== "" && root.board.overSide === root.side
    readonly property int railInsert: root.overMe && root.board.overZone === "rail" ? root.board.overIndex : -1
    readonly property bool aloneOver: root.overMe && root.board.overZone === "alone"
    readonly property int overrides: Islands.overrideCount(root.side, Config.islandOverrides)

    implicitHeight: col.implicitHeight
    // Where this column ends with no stretch. Read from the last well's own y and its spring, never from its
    // stretched height, so the stretch cannot feed back into the height it stretches to.
    readonly property real naturalHeight: root.hasColumn ? alonePlate.y + aloneH.value : railPlate.y + railH.value

    // Rows a list needs: its pages, one more while a page is about to drop in from elsewhere, never less than one.
    function rowsFor(list, inserting) {
        const extra = inserting && list.indexOf(root.board.dragKey) < 0 ? 1 : 0
        return Math.max(1, list.length + extra)
    }

    // { zone, index } for a point in this column's coordinates; null when it is on neither list.
    function zoneAt(px, py) {
        if (px < 0 || px > root.width) return null
        if (root.islands) {
            const r = railPlate.mapFromItem(root, px, py)
            if (r.y >= -root.gap && r.y <= railPlate.height + root.gap) {
                const n = root.railPages.length
                const i = Math.floor((r.y - root.pad - root.slot / 2) / root.step) + 1
                return { zone: "rail", index: Math.max(0, Math.min(n, i)) }
            }
        }
        if (!root.hasColumn) return null
        const a = alonePlate.mapFromItem(root, px, py)
        if (a.y >= -root.gap && a.y <= alonePlate.height + root.gap * 4) return { zone: "alone", index: 0 }
        return null
    }

    Column {
        id: col
        width: root.width
        spacing: Tokens.spacingSm

        // ── The island's name ────────────────────────────────────────────────
        Item {
            width: col.width
            height: Tokens.iconXl + Tokens.spacingXs

            // The handle as it sits on the bar: lit while the island has pages, gone with them.
            Rectangle {
                id: handleMark
                anchors.verticalCenter: parent.verticalCenter
                x: Tokens.spacingSm
                width: Tokens.spacingXl
                height: Tokens.spacingXs + 1
                radius: height / 2
                color: !root.islands ? root.palette.fgDim
                     : root.railPages.length > 0 ? root.palette.primary : root.palette.alpha(root.palette.fg, 0.15)
                Behavior on color { ColorAnimation { duration: Motion.standard } }
            }
            StyledText {
                id: name
                anchors.left: handleMark.right
                anchors.leftMargin: Tokens.spacingMd
                anchors.verticalCenter: parent.verticalCenter
                text: root.islands ? Translation.tr(root.sideMeta.label) : Translation.tr(root.sideMeta.label) + " " + Translation.tr("column")
                variant: "title"
                font.weight: Font.DemiBold
            }
            StyledText {
                anchors.left: name.right
                anchors.leftMargin: Tokens.spacingSm
                anchors.verticalCenter: parent.verticalCenter
                visible: root.islands
                text: String(root.railPages.length)
                variant: "caption"
                emphasis: "muted"
            }
            ChipButton {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.islands
                symbol: "tune"
                on: root.board !== null && root.board.scope === root.side
                dot: root.overrides > 0 ? root.palette.primary : "transparent"
                Accessible.name: Translation.tr("This island's own options")
                onActivated: if (root.board) root.board.tune(root.side)
                HoverTip {
                    text: root.overrides > 0 ? Translation.tr("Own options: %1 changed").arg(root.overrides)
                                             : Translation.tr("Own options for this island")
                    alignEnd: true
                }
            }
        }

        // ── The rail ─────────────────────────────────────────────────────────
        Rectangle {
            id: railPlate
            visible: root.islands
            width: col.width
            height: root.hasColumn ? railH.value : Math.max(railH.value, root.stretchTo - railPlate.y)
            radius: Tokens.radiusCard
            // A well one step off the group's segment, so the rail reads as a place.
            color: root.palette.alpha(root.palette.fg, 0.05)
            border.width: root.railInsert >= 0 ? Tokens.borderWidth : 0
            border.color: root.palette.alpha(root.palette.primary, 0.6)

            SpringValue {
                id: railH
                target: root.rowsFor(root.railPages, root.railInsert >= 0) * root.step - root.gap + root.pad * 2
                spec: Motion.springSpatial
                epsilon: 0.2
            }

            StyledText {
                anchors.centerIn: parent
                width: parent.width - Tokens.spacingXl * 2
                visible: root.railPages.length === 0 && root.railInsert < 0
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("Empty: this island has no handle")
                variant: "caption"
                emphasis: "muted"
                elide: Text.ElideRight
            }

            Repeater {
                model: root.railPages
                delegate: IslandPageChip {
                    required property string modelData
                    required property int index
                    x: root.pad
                    y: root.pad + index * root.step
                    width: railPlate.width - root.pad * 2
                    height: root.slot
                    key: modelData
                    lead: index === 0
                    lifted: root.board !== null && root.board.dragKey === modelData
                    shift: root.railInsert >= 0 && index >= root.railInsert ? root.step : 0
                    board: root.board
                }
            }
        }

        // ── Opens alone ──────────────────────────────────────────────────────
        StyledText {
            visible: root.islands && root.hasColumn
            leftPadding: Tokens.spacingSm
            topPadding: Tokens.spacingXs
            text: Translation.tr("Opens alone")
            variant: "caption"
            emphasis: "muted"
        }
        Rectangle {
            id: alonePlate
            visible: root.hasColumn
            width: col.width
            height: Math.max(aloneH.value, root.stretchTo - alonePlate.y)
            radius: Tokens.radiusCard
            color: root.aloneOver ? root.palette.alpha(root.palette.primary, 0.1) : root.islands ? root.palette.alpha(root.palette.fg, 0.04) : root.palette.section
            // An outline only as a drop target lights; at rest the well is a tone, not a box.
            border.width: root.aloneOver ? Tokens.borderWidth : 0
            border.color: root.palette.alpha(root.palette.primary, 0.6)
            Behavior on color { ColorAnimation { duration: Motion.respond } }

            SpringValue {
                id: aloneH
                target: root.rowsFor(root.alonePages, root.aloneOver) * root.step - root.gap + root.pad * 2
                spec: Motion.springSpatial
                epsilon: 0.2
            }

            StyledText {
                anchors.centerIn: parent
                width: parent.width - Tokens.spacingXl * 2
                visible: root.alonePages.length === 0 && !root.aloneOver
                horizontalAlignment: Text.AlignHCenter
                text: root.islands ? Translation.tr("Nothing opens alone here") : Translation.tr("Nothing opens here")
                variant: "caption"
                emphasis: "muted"
                elide: Text.ElideRight
            }

            Repeater {
                model: root.alonePages
                delegate: IslandPageChip {
                    required property string modelData
                    required property int index
                    x: root.pad
                    y: root.pad + index * root.step
                    width: alonePlate.width - root.pad * 2
                    height: root.slot
                    key: modelData
                    locked: Islands.LOCKED[modelData] === true
                    lifted: root.board !== null && root.board.dragKey === modelData
                    board: root.board
                }
            }
        }
    }
}
