import QtQuick
import QtQuick.Layouts
import "../services/bentopack.js" as Pack

// ── BentoGrid ─────────────────────────────────────────────────────────────────
// The grid a settings page's tiles live in: a GridLayout that FILLS its rows.
//
// ── Why not a plain GridLayout ────────────────────────────────────────────────
// A GridLayout wraps an item that doesn't fit in what is left of a row and leaves the
// rest blank, and it centres a short item beside a tall one. On a page of tiles those
// two are the "empty spaces": a lone tile on the last row, a 1-wide card that wouldn't
// squeeze in beside a 2-wide one. This grid works out the rows it will make
// (services/bentopack.js, tested) and widens the items in each row until the row is
// flush; items stretch to the row's height, so a short card beside a tall one has the
// same edges.
//
// ── Sub-columns ───────────────────────────────────────────────────────────────
// The page has 1–3 columns, but the grid underneath has SIX, so sharing a row's
// leftovers is exact for every row 1, 2 or 3 columns can make (two tiles on a
// three-column page are 3|3, not 2|2|gap). `bentoCols` is the page's column count;
// `columns` is the six. Children never touch either: they ask `spanFor(item)`, which
// is what `Section`, `QuickToggleTile` and `GroupHeader` bind `Layout.columnSpan` to.
//
// ── A child opts in by having `span` ──────────────────────────────────────────
// `span` = how many PAGE columns it wants (1–3), default 1. Hidden children take no
// cell (the grid skips what isn't visible, as the layout does) and Repeaters are
// skipped. Anything else with no `span` is a one-column tile.
//
// ── No config imports ─────────────────────────────────────────────────────────
// Deliberately: spacing arrives from the page. That keeps this file loadable on its
// own, which is how its placement was measured.
//
// `pack: false` is the old behaviour (columns = the page's, spans clamped) for a page
// that hand-groups SectionColumns instead of tiling.
// ─────────────────────────────────────────────────────────────────────────────
GridLayout {
    id: root

    // The page's column count, 1–3.
    property int bentoCols: 1
    property bool pack: true
    readonly property int sub: 6

    columns: root.pack ? root.sub : root.bentoCols
    // Cell widths: every column the same. (Without this a column is as wide as the
    // widest thing that sits in it alone.)
    uniformCellWidths: root.pack

    // One zero-height cell per sub-column, in a row of their own at the top. A grid
    // sizes a column from the items that sit in it alone; with only spanning items
    // (3|3 above 2|2|2) the columns come out uneven and rows stop lining up (measured:
    // a three-tile row of 216|444|216 instead of 292 each). These give every column a
    // single-cell item to be sized by. `isAnchor` keeps them out of the packing.
    //
    // They are a real row, and the row spacing under it is real too: `topTrim` is that
    // gap, for a page body to offset so its first tile still starts at the top.
    readonly property real topTrim: root.pack ? root.rowSpacing : 0

    Repeater {
        model: root.pack ? root.sub : 0
        delegate: Item {
            required property int index
            readonly property bool isAnchor: true
            // Placed, not auto-flowed: a Repeater's delegates can be created after the
            // page's own children, which would put this row at the bottom.
            Layout.row: 0
            Layout.column: index
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            Layout.preferredHeight: 0
            Layout.maximumHeight: 0
        }
    }

    // Effective span of every child, aligned with `children`. A binding, so it
    // re-runs when a child appears, hides, or changes its `span`.
    readonly property var _eff: {
        const kids = root.children
        const spans = []
        for (let i = 0; i < kids.length; i++) {
            const c = kids[i]
            // A Repeater is an Item the layout ignores; its delegates are the cells.
            const isRepeater = c.model !== undefined && c.delegate !== undefined
            if (c.isAnchor === true) { spans.push(0); continue }
            spans.push(c.visible && !isRepeater ? Pack.baseSpan(c.span, root.bentoCols, root.sub) : 0)
        }
        return root.pack ? Pack.pack(spans, root.sub) : spans
    }

    // What `Layout.columnSpan` of `item` should be.
    function spanFor(item) {
        if (!root.pack)
            return Math.max(1, Math.min(item.span === undefined ? 1 : item.span, root.bentoCols))
        const kids = root.children
        for (let i = 0; i < kids.length; i++)
            if (kids[i] === item)
                return root._eff[i] > 0 ? root._eff[i] : Pack.baseSpan(item.span, root.bentoCols, root.sub)
        return Pack.baseSpan(item.span, root.bentoCols, root.sub)
    }
}
