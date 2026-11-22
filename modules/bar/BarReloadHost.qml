import QtQuick
import Quickshell.Hyprland
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── BarReloadHost ─────────────────────────────────────────────────────────────
// The reload card, hosted INSIDE Bar's own window so the blob draws it: it comes out from under
// the bar and goes back into it, one body with the bar while it is out. Same reason BarToastHost
// and BarPanelDock live there: `Quicktest.Blobs` only fuses shapes that share one Qt Quick scene
// graph, and two layer-shell surfaces are composited independently by Hyprland.
//
// It is one of TWO hosts for one ReloadCard. This one is live normally; modules/panels/ReloadPopup
// (its own Overlay window) takes over while something is FULLSCREEN on this monitor, or where the
// plugin is not built. `live` gates which card may open for an event, so exactly one does.
//
// ── The card comes out of the bar, it does not fade ───────────────────────────
// The host clips to its own box, whose top is the bar's underside, and the card slides up into it
// (`reveal`). What the blob is handed is the part of the card that is OUTSIDE the bar, as painted
// (`rects`), so the lobe grows from the bar's edge and retracts into it. A lobe cannot fade, so the
// way out is geometric too.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: host

    required property var screen

    readonly property string monName: Hyprland.monitorFor(host.screen)?.name ?? ""

    // Flush under the bar, so the neck has no gap to cross that the smooth-min cannot reach.
    readonly property int topMargin: Config.barAnchored ? Config.barSurfaceHeight
                                                        : (Config.barExtent + 2)

    width: Math.min(480, parent ? parent.width : 480)
    height: card.height
    clip: true

    // The card's visible part, for the input mask: nothing while it is away.
    readonly property Item maskItem: hit
    Item {
        id: hit
        x: card.x
        y: Math.max(0, card.y)
        width: card.shown ? card.width : 0
        height: card.shown ? Math.max(0, card.y + card.height - hit.y) : 0
    }

    // The part of the card outside the bar, as the blob should draw it, in Bar's coordinates. A
    // plain read of the card's own geometry, never mapToItem(): that does not re-evaluate when an
    // ancestor moves (BlobBarLayer's header spells out why).
    readonly property var rects: {
        if (!card.shown) return []
        const top = Math.max(0, card.y)
        const h = card.y + card.height - top
        if (h <= 1 || card.width <= 1) return []
        return [{ x: host.x + card.x, y: host.y + top, w: card.width, h: h }]
    }

    ReloadCard {
        id: card
        screen: host.screen
        live: Morph.available && Fullscreen.byMonitor[host.monName] !== true
        welded: true
        visible: card.shown
        maxWidth: host.width
        anchors.horizontalCenter: parent.horizontalCenter
        y: -card.height * (1 - card.reveal)
    }
}
