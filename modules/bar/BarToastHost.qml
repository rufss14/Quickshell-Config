import QtQuick
import Quickshell.Hyprland
import "../../config"
import "../../services"
import "../../state"
import "../notifications"

// ── BarToastHost ──────────────────────────────────────────────────────────────
// The notification deck, hosted INSIDE Bar's own window so the blob can melt the
// front toast out of the bar. Same reason BarPanelDock lives
// there: `Quicktest.Blobs` can only fuse shapes that share one Qt Quick scene
// graph, and two layer-shell surfaces are composited independently by Hyprland.
//
// It is one of TWO hosts for one NotificationStack. This one is live normally;
// NotificationOverlay's own Overlay-layer window takes over while something is
// FULLSCREEN, because Hyprland hides Top-layer surfaces under a fullscreen window
// and the bar is Top. Exactly one is live at a time — `live` gates the MODEL, so
// the idle host holds no delegates, no timers and no image loads.
//
// ── The toasts keep their own cards ───────────────────────────────────────────
// Unlike a docked panel, which drops its outline entirely and lets the blob supply
// the whole silhouette, a toast deck is several overlapping cards receding behind
// one another — merge them all into one mass and the deck stops reading as a
// stack. So only the FRONT toast gets a blob rect, and it sits BEHIND the card as
// a connecting neck: visible in the gap between the bar and the toast, covered by
// the toast's own fill everywhere else. That is exactly the split
// the panel docks use for their melt.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: host

    required property int screenH
    required property var screen

    readonly property string monName: Hyprland.monitorFor(host.screen)?.name ?? ""

    // The monitor the deck was DELIVERED to, not the one the pointer is on — see
    // Notifications.popupMonitor. This also keeps one deck to one output; binding it
    // to focus put a full copy on every screen at once, which showed up as this
    // host's exit handler firing twice for a single dismissal.
    readonly property bool ours: Notifications.popupMonitor === host.monName
    // A plain binding is safe HERE, unlike in NotificationOverlay: this is an Item
    // inside Bar's always-visible window, so nothing downstream of the name drives a
    // window's own `visible` and there is no map/unmap cycle to close.

    // Flush under the bar, so the neck has no gap to cross that the smooth-min
    // cannot reach. The old overlay sat `barExtent + spacingMd` down.
    readonly property int topMargin: Config.barAnchored ? Config.barSurfaceHeight
                                                        : (Config.barExtent + 2)
    readonly property int edgeMargin: (Config.frameFused && Config.screenFrame)
                                        ? Config.frameDepth
                                        : (Config.barInset + Tokens.spacingMd)

    // The widest a toast gets is 400; the surplus is the leftward swipe overshoot,
    // which must not be clipped. Same allowance the old window carried.
    readonly property int deckWidth: 520
    readonly property int maxHeight: Math.max(0, host.screenH - host.topMargin
                                                 - Tokens.spacingMd)

    implicitWidth:  host.deckWidth
    implicitHeight: host.maxHeight

    // Bar reads these: the input mask, and the front toast's box for the blob.
    readonly property Item maskItem: stack

    // The deck's boxes, shifted from the stack's coordinates into Bar's. Plain
    // property reads, never mapToItem() — a mapToItem in a binding does not
    // re-evaluate when an ancestor moves, which BlobBarLayer's own header spells out.
    readonly property var toastRects: {
        const src = stack.toastRects
        const dx = host.x + stack.x
        const dy = host.y + stack.y
        const out = []
        for (let i = 0; i < src.length; i++)
            out.push({ x: src[i].x + dx, y: src[i].y + dy, w: src[i].w, h: src[i].h })
        return out
    }

    NotificationStack {
        id: stack
        anchors.top:   parent.top
        anchors.right: parent.right
        anchors.rightMargin: host.edgeMargin
        // The exact inverse of NotificationOverlay's condition — never both, and
        // never neither. See its note on why this is Fullscreen's job.
        live: host.ours && Fullscreen.byMonitor[host.monName] !== true
        welded: Morph.available
    }
}
