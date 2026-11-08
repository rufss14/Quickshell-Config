import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── OverviewModifiers ─────────────────────────────────────────────────────────
// Shift and Ctrl on screen, top right of the workspaces' card (in the watermark's row; it was the
// bottom left until 2026-10-24, when the user gave that strip to the left face's pages): two chips that are lit while
// the key is on, and ONE "?" after them that explains both in a card, opened by a click
// (OverviewHelpDot) — the chips say nothing themselves, so a lit one is not a sentence on the board. Both are TOGGLES
// (a tap of the key, or a click here — Overview owns the state, this only draws it and says
// "clicked"), and a key held down still works as it always did, so the chip is lit for that too.
//
//   Shift  every workspace of the page gets its cell, and clicking one SENDS your window there
//   Ctrl   clicking a window SELECTS it (the island turns to the selection), dragging one onto
//          another SWAPS their workspaces
// ─────────────────────────────────────────────────────────────────────────────
ChipTray {
    id: root

    property bool shiftOn: false
    property bool ctrlOn: false
    signal shiftClicked()
    signal ctrlClicked()

    // Over the grid it sits beside, so a help card opens over the cells instead of under them.
    z: 10

    property alias helpOpen: help.open

    // The overview's extra panels, folded away until asked for (Config.overviewMore).
    ChipButton {
        symbol: "dashboard"
        label: Config.overviewMore ? Translation.tr("Less") : Translation.tr("More")
        on: Config.overviewMore
        onActivated: Config.overviewMore = !Config.overviewMore
        HoverTip {
            below: true
            text: Config.overviewMore
                ? Translation.tr("Hide the extra panels: replay clips, voice chat, performance, key display, Ask / News and notifications. (Ctrl+M)")
                : Translation.tr("Show the extra panels: replay clips, voice chat, performance, key display, Ask / News and notifications. (Ctrl+M)")
        }
    }
    // Named for what they DO; the key is in the "?" card (and still works held down).
    ChipButton {
        symbol: "arrow_upward"
        label: Translation.tr("All spaces")
        on: root.shiftOn
        onActivated: root.shiftClicked()
        HoverTip { below: true; text: Translation.tr("Show every workspace, and send a window to one with a click. (Shift)") }
    }
    ChipButton {
        symbol: "checklist"
        label: Translation.tr("Select")
        on: root.ctrlOn
        onActivated: root.ctrlClicked()
        HoverTip { below: true; text: Translation.tr("Click windows to select several, drag one onto another to swap their workspaces. (Ctrl)") }
    }
    // One "?" for both (the user, 2026-10-24), opened by a click.
    OverviewHelpDot {
        id: help
        anchors.verticalCenter: parent.verticalCenter
        // Top right of the card: the card opens downward, toward the cells.
        below: true
        title: Translation.tr("Two keys, two modes")
        sections: [
            { title: "Shift — show all workspaces", lines: [
                { symbol: "ads_click",  text: Translation.tr("Tap it, or click its chip, to switch it on or off. Held down it works too, while you hold it.") },
                { symbol: "grid_view",  text: Translation.tr("Every workspace of the page gets a cell, empty ones too.") },
                { symbol: "send",       text: Translation.tr("Click a workspace to send your window there, instead of going to it.") }
            ] },
            { title: "Ctrl — select windows", lines: [
                { symbol: "ads_click",  text: Translation.tr("The same: a tap or a click toggles it, holding works while held.") },
                { symbol: "checklist",  text: Translation.tr("Click a window to select it, as many as you like. The island turns to the selection.") },
                { symbol: "swap_horiz", text: Translation.tr("Drag a window onto another to swap their workspaces.") }
            ] }
        ]
    }
}
