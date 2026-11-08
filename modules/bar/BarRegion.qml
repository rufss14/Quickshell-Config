import QtQuick
import "../../config"

// ── BarRegion ─────────────────────────────────────────────────────────────────
// One of the bar's three clusters (left / center / right): a row of BarGroups.
//
// It draws nothing of its own. The bar is ONE surface (Bar.qml's unified one) —
// the per-region and per-group pills went with the pills shapes (Config's
// barLayout) — so a region only lays its groups out, a merged group's gap apart,
// with the padding at its ends each group gave up.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Any of this region's panels is open: the bar's surface reads as pointed at
    // (Bar.qml ORs `hovered` into its `focused`).
    property bool forceExpanded: false

    default property alias groups: row.data

    readonly property bool hovered: hover.hovered || forceExpanded

    readonly property int gap: Tokens.spacingMd
    // INTERNAL padding: the row is inset by it and the region box grows to match.
    readonly property int edgePad: Tokens.spacingSm

    // The box INCLUDES the padding. Its height is the bar's own surface's.
    implicitWidth:  Math.ceil(row.implicitWidth) + edgePad * 2
    implicitHeight: Config.barSurfaceHeight

    Behavior on implicitHeight { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

    HoverHandler { id: hover }

    Row {
        id: row
        x: root.edgePad
        spacing: root.gap
    }
}
