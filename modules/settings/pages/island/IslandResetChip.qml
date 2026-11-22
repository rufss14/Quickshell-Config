pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../../../config"
import "../../../../components"
import "../../../../services"

// ── IslandResetChip ───────────────────────────────────────────────────────────
// A per-island option's way back to the shared value, beside the option on the Island page's Behaviour card:
// there only while the island in scope has its own value. `page` is the IslandPage (own / unset).
// ─────────────────────────────────────────────────────────────────────────────
ChipButton {
    id: root

    property Item page: null
    property string name: ""
    // The shared value as it reads ("180 ms"), for the tip.
    property string shown: ""

    visible: root.page !== null && root.page.own(root.name)
    symbol: "undo"
    Accessible.name: Translation.tr("Back to shared")
    onActivated: root.page.unset(root.name)
    HoverTip { text: Translation.tr("Back to shared: %1").arg(root.shown); alignEnd: true }
}
