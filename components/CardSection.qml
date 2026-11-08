import QtQuick
import "../config"

// ── CardSection ───────────────────────────────────────────────────────────────
// One section of a sidebar pill's hover card (StatsHost, ClipsHost). The card is
// capped at the pill's length, so what doesn't fit is folded away (sysstats.js
// `fitSections`), and folded by HEIGHT (0, clipped), never by `visible`: an
// invisible parent makes its children invisible, a Column then measures 0, the
// section "fits" and comes back — a loop. `natural` is the height it wants,
// measured on the always-visible inner column; `gap` is the spacing above it,
// counted only while it's shown (fitSections counts it too).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: section
    property bool shown: true
    property real gap: 0
    default property alias content: inner.data
    readonly property real natural: inner.implicitHeight
    width: parent ? parent.width : 0
    height: section.shown ? section.gap + inner.implicitHeight : 0
    clip: true
    opacity: section.shown ? 1 : 0
    Column {
        id: inner
        y: section.gap
        width: section.width
        spacing: Tokens.spacingSm
    }
}
