import QtQuick
import "../config"

// ── MagnetLean ────────────────────────────────────────────────────────────────
// The offset that makes an icon lean toward the pointer while its control is hovered, and
// settle back when it leaves: a magnet, not a drag. Non-visual — the owner reads
// `offsetX/offsetY` into a `transform: Translate { x: …; y: … }` on whatever should lean.
//
// Subtle on purpose: a twentieth of the pointer's distance from the centre, never more than
// a pixel. At that size it is felt before it is seen; anything bigger on a 24px bar button
// reads as the icon wobbling. `strength` and `limit` are the two knobs.
//
// Feed it from the owner's own MouseArea (`pointerX: mouse.mouseX`, `active: mouse.containsMouse`),
// like StateLayer: a second hover handler of its own would take the hover from the button.
QtObject {
    id: root

    property bool active: false
    property real pointerX: 0
    property real pointerY: 0
    // The hovered control's size, for its centre.
    property real extentW: 0
    property real extentH: 0

    property real strength: 0.05
    property real limit: 1

    property real offsetX: root._pull(root.pointerX, root.extentW)
    property real offsetY: root._pull(root.pointerY, root.extentH)

    Behavior on offsetX { NumberAnimation { duration: Motion.standard; easing.type: Motion.respondCurve } }
    Behavior on offsetY { NumberAnimation { duration: Motion.standard; easing.type: Motion.respondCurve } }

    function _pull(p, extent) {
        if (!root.active) return 0
        return Math.max(-root.limit, Math.min(root.limit, (p - extent / 2) * root.strength))
    }
}
