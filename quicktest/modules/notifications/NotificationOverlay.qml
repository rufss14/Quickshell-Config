import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../config"
import "../../services"

// ── NotificationOverlay ───────────────────────────────────────────────────────
// The toasts, stacked top-right on the focused monitor. One of these exists per
// screen; only the focused one draws, so a notification doesn't appear on every
// monitor at once. The window is click-through except where a toast actually is
// (`mask`), so the rest of that corner stays usable.
//
// ── The motion ─────────────────────────────────────────────────────────────────
// Each toast lives in a `cell` wrapper that owns three animations, because a
// Positioner (Column) can animate items ARRIVING and MOVING but not LEAVING:
//
//   enter   slide in from the right + fade, as the newest lands on top.
//   exit    the toast decides it's done (dwell expired, dismissed) → it slides
//           out and fades BEFORE telling the service to drop it, so it animates
//           away instead of blinking out. Only once that finishes does the model
//           lose the item.
//   reflow  `Behavior on y` — when a toast above is added or removed, this one's
//           slot in the Column changes, and it glides to the new position rather
//           than teleporting. A single discrete change, never a chase.
//
// Depth: the newest toast is front-and-centre; the ones behind recede in scale and
// opacity, so a stack reads as a deck rather than a wall. As the front one leaves,
// the next scales up into its place.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: root

    required property var screen

    readonly property bool onFocused:
        Hyprland.focusedMonitor?.name === (Hyprland.monitorFor(root.screen)?.name ?? "")

    readonly property bool active: root.onFocused && Notifications.popups.length > 0

    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "quickshell-notifications"
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None   // toasts never grab the keyboard

    anchors.top:   true
    anchors.right: true
    margins.top:   Config.barThickness + Tokens.spacingMd
    margins.right: Tokens.spacingMd

    // Wider than the widest toast (a preview toast is 400), so the enter overshoot,
    // the deck's depth scale, and the leftward swipe all have room before the window
    // edge clips them.
    implicitWidth:  520
    implicitHeight: Math.max(1, stack.implicitHeight + Tokens.spacingSm)

    color: "transparent"
    visible: root.active
    mask: Region { item: stack }

    Column {
        id: stack
        anchors.top:   parent.top
        anchors.right: parent.right
        spacing: Tokens.spacingMd

        Repeater {
            // ── Why ScriptModel and not the bare array ────────────────────────
            // A JS array as a Repeater model makes EVERY change destroy and rebuild
            // ALL delegates (QQuickRepeater::regenerate). Under a burst of
            // notifications that rapid teardown-and-reincubate of image-loading,
            // animating toasts segfaults inside incubation — the crash in the
            // report. ScriptModel wraps the same array in a QAbstractListModel that
            // DIFFS it, so only the toast that actually changed is added or removed;
            // the rest are left untouched. Keyed by notification id, which is unique
            // in `popups` (showPopup de-dupes by it).
            model: ScriptModel {
                objectProp: "id"
                values: root.onFocused ? Notifications.popups : []
            }

            delegate: Item {
                id: cell
                required property var modelData
                required property int index

                // Where this toast sits in the stack — 0 is newest, on top. The
                // model hands us the row directly now.
                readonly property int idx: cell.index

                width:  toast.implicitWidth
                height: toast.implicitHeight
                anchors.right: parent.right

                // Depth: recede the cards behind the front one. transformOrigin
                // Right keeps them pinned to the margin as they shrink.
                transformOrigin: Item.Right
                scale: cell.idx === 0 ? 1.0 : Math.max(0.9, 1.0 - cell.idx * 0.03)
                Behavior on scale {
                    NumberAnimation {
                        duration: Motion.spatial
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.emphasizedDecel
                    }
                }

                // Reflow: the Column assigns y directly, so a Behavior catches the
                // jump when a sibling is added or removed and glides instead.
                Behavior on y {
                    enabled: !cell.closing
                    NumberAnimation {
                        duration: Motion.spatial
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.emphasizedDecel
                    }
                }

                NotificationToast {
                    id: toast
                    notif: cell.modelData

                    // Depth opacity rides on the TOAST; the CELL's opacity is the
                    // enter/exit fade, so the two never fight over one property.
                    opacity: cell.idx === 0 ? 1.0 : (cell.idx === 1 ? 0.9 : 0.78)
                    Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                    // The toast asks to go; the cell animates it out first, then the
                    // service actually drops it (see close()).
                    onExpired:   cell.close(true)
                    onDismissed: cell.close(false)
                }

                // ── Enter ─────────────────────────────────────────────────────
                // Slides in from the right on the SPRING curve (a slight overshoot
                // past its resting place, then settle — a toast that lands rather
                // than glides to a stop), with a small scale-pop so it grows into
                // place. The Scale transform is separate from the depth `scale` and
                // the toast's own hover scale, so none of the three fight.
                transform: [
                    Translate { id: slide },
                    Scale {
                        id: pop
                        origin.x: cell.width / 2
                        origin.y: cell.height / 2
                    }
                ]
                opacity: 0
                Component.onCompleted: enterAnim.start()
                ParallelAnimation {
                    id: enterAnim
                    NumberAnimation {
                        target: slide; property: "x"
                        from: 84; to: 0
                        duration: Motion.spatial
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.spring
                    }
                    NumberAnimation {
                        target: cell; property: "opacity"
                        from: 0; to: 1
                        duration: Motion.emphasized
                    }
                    NumberAnimation {
                        target: pop; property: "xScale"
                        from: 0.94; to: 1.0
                        duration: Motion.spatial
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.emphasizedDecel
                    }
                    NumberAnimation {
                        target: pop; property: "yScale"
                        from: 0.94; to: 1.0
                        duration: Motion.spatial
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.emphasizedDecel
                    }
                }

                // ── Swipe to dismiss ──────────────────────────────────────────
                // Drag the toast to the LEFT — it lives at the right edge, so left is
                // the way "away" lies. It follows your finger and fades as it goes;
                // past the threshold it leaves (the exit continues the motion out),
                // short of it, it springs back. This is why toasts have no close
                // button — the whole card IS the affordance.
                readonly property real dismissDist: 380      // fully faded here
                DragHandler {
                    id: swipe
                    target: null                              // we drive slide.x by hand
                    enabled: !cell.closing
                    yAxis.enabled: false
                    xAxis.enabled: true
                    onActiveChanged: {
                        if (swipe.active) { releaseAnim.stop(); return }
                        if (cell.closing) return
                        if (-slide.x > cell.dismissDist * 0.5) cell.close(false)
                        else releaseAnim.start()
                    }
                    onTranslationChanged: {
                        if (cell.closing || !swipe.active) return
                        // Leftward only (slide.x ≤ 0); a rightward pull does nothing.
                        slide.x = Math.min(0, swipe.translation.x)
                        cell.opacity = Math.max(0, 1 + slide.x / cell.dismissDist)
                    }
                }

                // Spring back when a drag is released short of the threshold.
                ParallelAnimation {
                    id: releaseAnim
                    NumberAnimation {
                        target: slide; property: "x"
                        to: 0
                        duration: Motion.standard
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.spring
                    }
                    NumberAnimation {
                        target: cell; property: "opacity"
                        to: 1
                        duration: Motion.standard
                    }
                }

                // ── Exit ──────────────────────────────────────────────────────
                // Slides out + fades + shrinks a touch, THEN hands the removal to the
                // service. Only when it's gone from `popups` does the Repeater destroy
                // this delegate, so nothing is torn out mid-animation; the siblings
                // then close the gap via their own Behavior on y. It GLIDES rather
                // than snaps — the swipe felt too abrupt on an accelerate curve, so
                // it's a longer decelerate now.
                property bool closing: false
                property bool _expire: true
                // Where the exit slides TO — leftward, matching the swipe. A
                // drag-dismiss is already partway out, so it continues from there
                // rather than snapping back first.
                property real _exitX: -108
                function close(expire) {
                    if (cell.closing) return
                    cell.closing = true
                    cell._expire = expire
                    cell._exitX = Math.min(-140, slide.x - 120)
                    exitAnim.start()
                }
                SequentialAnimation {
                    id: exitAnim
                    ParallelAnimation {
                        NumberAnimation {
                            target: slide; property: "x"
                            to: cell._exitX
                            duration: Motion.emphasized
                            easing.type: Motion.travel
                        }
                        NumberAnimation {
                            target: cell; property: "opacity"
                            to: 0
                            duration: Motion.emphasized
                            easing.type: Motion.travel
                        }
                        NumberAnimation {
                            target: pop; property: "xScale"
                            to: 0.94
                            duration: Motion.emphasized
                            easing.type: Motion.travel
                        }
                        NumberAnimation {
                            target: pop; property: "yScale"
                            to: 0.94
                            duration: Motion.emphasized
                            easing.type: Motion.travel
                        }
                    }
                    ScriptAction {
                        script: {
                            if (cell._expire) Notifications.expirePopup(cell.modelData)
                            else              Notifications.dismiss(cell.modelData)
                        }
                    }
                }
            }
        }
    }
}
