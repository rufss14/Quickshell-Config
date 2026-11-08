import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── NotificationStack ─────────────────────────────────────────────────────────
// The toast deck itself, with no opinion about what surface it sits on. Extracted
// from NotificationOverlay so it can be mounted in TWO places without becoming two
// implementations that drift:
//
//   • inside Bar's own window (BarToastHost), where the blob melts the front toast
//     out of the bar — metaball fusion only works within one Qt Quick scene graph,
//     so welding REQUIRES living in the bar's window;
//   • inside NotificationOverlay's own Overlay-layer window, which is what still
//     draws while something is FULLSCREEN, because Hyprland hides Top-layer
//     surfaces under a fullscreen window and the bar is Top.
//
// Exactly one host is live at a time; see Hypr.anyFullscreen.
//
// The cells publish their own boxes back up (`toastRects`) for the host that welds.
// What they publish is each card as PAINTED — slide, pop and fade folded in — not as
// laid out, because the blob draws the only border a welded card has and is the only
// thing that can show it leaving. See the lobe block in the delegate for why all
// three matter.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: stackRoot

    // Whose popups to show. False empties the MODEL rather than hiding the item, so
    // the inactive host holds no delegates at all — no timers, no image loads.
    property bool live: false

    // True in the bar host, where the blob supplies the join. Only the FRONT toast
    // changes: it drops its own outline and shadow so the blob's SDF outline is the
    // only stroke at that edge, exactly as BarDock does for a welded panel. Without
    // it the toast goes on drawing its own top border straight across the weld —
    // measured, a 1px line at 136 where the merged material either side reads 12.
    property bool welded: false

    // Every cell's box, in this Item's coordinates, newest first. The welding host
    // hands these to the blob so the WHOLE deck fuses — into each other and, through
    // the top one, into the bar. It used to publish only the front toast, on the
    // theory that merging a receding deck would stop it reading as a stack; in
    // practice one welded card above a pile of ordinary bordered ones just looked
    // like the weld had failed on all but the newest.
    //
    // Rebuilt on a coalesced tick rather than bound per-cell: the cells move every
    // frame during an enter, a reflow and a swipe, and `Qt.callLater` collapses all
    // of a frame's changes into one rebuild.
    property int _tick: 0
    function _touch() { stackRoot._tick++ }

    readonly property var toastRects: {
        stackRoot._tick                       // the dependency that drives the rebuild
        const out = []
        for (let i = 0; i < rep.count; i++) {
            const c = rep.itemAt(i)
            // A lobe collapsing out of the deck is dropped before it goes
            // degenerate: grow() would inflate a sub-pixel rect back into a
            // visible speck, which is the pop this whole derivation removes.
            if (!c || c.lobeW <= 1 || c.lobeH <= 1) continue
            out.push({ x: c.lobeX, y: c.lobeY, w: c.lobeW, h: c.lobeH })
        }
        return out
    }

    implicitWidth:  stack.implicitWidth
    implicitHeight: stack.implicitHeight

    Column {
        id: stack
        anchors.top:   parent.top
        anchors.right: parent.right
        spacing: Tokens.spacingMd

        Repeater {
            id: rep
            // ── Why ScriptModel and not the bare array ────────────────────────
            // A JS array as a Repeater model makes EVERY change destroy and rebuild
            // ALL delegates (QQuickRepeater::regenerate). Under a burst of
            // notifications that rapid teardown-and-reincubate of image-loading,
            // animating toasts segfaults inside incubation — the crash in the
            // report. ScriptModel wraps the same array in a QAbstractListModel that
            // DIFFS it, so only the toast that actually changed is added or removed;
            // the rest are left untouched.
            //
            // Keyed by `psid`, a key Notifications.showPopup mints itself — NOT the
            // notification's own `id`. That freedesktop id is only guaranteed unique
            // when an app deliberately reuses it to replace a notification; plenty of
            // senders leave it at 0 for every fresh one, which would hand ScriptModel
            // the same key for every toast and collapse a burst down to one changing
            // row instead of a real stack.
            model: ScriptModel {
                objectProp: "psid"
                values: stackRoot.live ? Notifications.popups : []
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
                // ── The deck's depth, and why the weld cancels it ─────────────
                // Receding the cards behind the front one is what makes a FLOATING
                // stack read as a stack. Welded, they are not a stack of cards any
                // more — they are one mass hanging off the bar, and scaling members
                // of a single body just makes its silhouette wobble in and out. The
                // blob's own fusion does the "these are related" work instead.
                scale: stackRoot.welded ? 1.0
                     : cell.idx === 0   ? 1.0
                     :                    Math.max(0.9, 1.0 - cell.idx * 0.03)
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

                // ── The lobe: what the card PAINTS, not how it was laid out ───
                // The blob has to be handed the card's PAINTED box. FOUR things sit
                // between the cell's laid-out geometry and the pixels — the `slide`
                // Translate (enter overshoot and the dismiss swipe), the `pop` Scale
                // (enter and exit), the toast's OWN hover scale, and `opacity` — and
                // this used to carry only the first. The rest are why the morph read
                // as unclean:
                //
                //   · `pop` ignored. A welded card draws NO border of its own, so the
                //     blob's stroke IS its edge — and while the enter scaled the card
                //     0.94→1, that stroke sat ~12px outside the card it was supposed
                //     to be bounding, converging over the whole 400ms.
                //   · the hover lift ignored. The toast scales ITSELF to 1.015 under
                //     the pointer, and a `scale` never touches implicitWidth — which
                //     is exactly what this cell's width and height are bound to. So
                //     the one gesture that says "this card is live" grew it ~3px out
                //     past each side of its own outline while the lobe sat still.
                //   · `opacity` ignored — and BlobRect HAS no opacity to give it. The
                //     group rasterises one union out of geometry alone (BlobRectData
                //     is cx/cy/hw/hh + radius, no alpha), so a card could only ever
                //     fade out from under a lobe that stayed at full material and
                //     then blinked out of existence when the delegate died. The exit
                //     slides 140px and the deck is ~400 wide, so what blinked was a
                //     bar-coloured slab still well inside the screen edge.
                //
                // A lobe cannot fade, so its exit has to be GEOMETRIC. Presence
                // follows the card's own alpha but only bites over the last of it:
                // the lobe matches the card exactly while the card is legible, then
                // collapses toward its centre through the final 35% of the fade,
                // where a stroke drawn slightly inside a nearly-invisible card cannot
                // be read. BlobShape::cornerRadii clamps radius to half the shorter
                // side, so a collapsing lobe rounds itself off into a droplet — the
                // neck thins and pinches rather than snapping.
                //
                // All of it is DERIVED from the card's own properties rather than run
                // as a second animation alongside, which is what keeps the two in
                // lockstep on every path: enter, reflow, swipe and exit.
                readonly property real lobePresence: Math.min(1, cell.opacity / 0.35)
                readonly property real lobeW: cell.width  * pop.xScale * toast.scale * cell.lobePresence
                readonly property real lobeH: cell.height * pop.yScale * toast.scale * cell.lobePresence
                // The scales MULTIPLY and the box stays centred: `pop` scales about
                // the cell's centre (see its origin below) and the toast's hover scale
                // about its own, which is the same point — the toast has no explicit
                // size, so it fills the cell exactly. Hence the box is simply inset by
                // half of whatever the combined scale took off.
                readonly property real lobeX: cell.x + slide.x + (cell.width  - cell.lobeW) / 2
                readonly property real lobeY: cell.y           + (cell.height - cell.lobeH) / 2

                // These four ARE the published numbers, and each already depends on
                // x/y/width/height/slide/pop/opacity — so there is nothing left to
                // hook separately, the way the raw geometry used to need.
                onLobeXChanged: Qt.callLater(stackRoot._touch)
                onLobeYChanged: Qt.callLater(stackRoot._touch)
                onLobeWChanged: Qt.callLater(stackRoot._touch)
                onLobeHChanged: Qt.callLater(stackRoot._touch)
                Component.onDestruction: Qt.callLater(stackRoot._touch)

                NotificationToast {
                    id: toast
                    notif: cell.modelData.n

                    // EVERY card, not just the front one: they fuse with each other
                    // as well as with the bar, so any card keeping its own rectangle
                    // would draw a stroke straight through the merged material.
                    readonly property bool meltsIntoBar: stackRoot.welded
                    borderWidth: toast.meltsIntoBar ? 0 : Tokens.borderWidth
                    // Welded while the blob draws the cookie field, the blob paints this fill (the
                    // same Colors.surface) with the cookies in it; painted again it would hide them.
                    fillOpacity: toast.meltsIntoBar && Drift.inBlob ? 0 : 1
                    // A lobe of the bar casts no shadow onto the bar it is made of.
                    castsShadow: !toast.meltsIntoBar

                    // Depth opacity rides on the TOAST; the CELL's opacity is the
                    // enter/exit fade, so the two never fight over one property.
                    opacity: stackRoot.welded ? 1.0
                           : cell.idx === 0     ? 1.0
                           : cell.idx === 1     ? 0.9 : 0.78
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
                        // In from the right and out to the right: one axis, one
                        // direction, so the card's whole life reads as a single move.
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
                // Drag the toast to the RIGHT — it lives ON the right edge, so right is
                // the way off the screen, and the card simply leaves the way it came in.
                // (It used to go left, into the desktop, which meant the dismissal ran
                // AWAY from the nearest edge and had to fade out mid-screen to explain
                // itself.) It follows your finger and fades as it goes; past the
                // threshold it leaves, short of it, it springs back. This is why toasts
                // have no close button — the whole card IS the affordance.
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
                        if (slide.x > cell.dismissDist * 0.5) cell.close(false)
                        else releaseAnim.start()
                    }
                    onTranslationChanged: {
                        if (cell.closing || !swipe.active) return
                        // Rightward only (slide.x ≥ 0); a leftward pull does nothing.
                        slide.x = Math.max(0, swipe.translation.x)
                        cell.opacity = Math.max(0, 1 - slide.x / cell.dismissDist)
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
                // Where the exit slides TO — rightward, matching the swipe. A
                // drag-dismiss is already partway out, so it continues from there
                // rather than snapping back first. Paint stops at the screen edge, so
                // "off the right" and "gone" are the same pixel — the card does not
                // have to fade to explain where it went.
                property real _exitX: 108
                function close(expire) {
                    if (cell.closing) return
                    cell.closing = true
                    cell._expire = expire
                    cell._exitX = Math.max(140, slide.x + 120)
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
                        // Closed by `psid` — the cell's OWN key — not by the
                        // notification it wraps. By the time this runs the exit
                        // animation has been going for ~200ms, and the notification can
                        // have been destroyed in that window; the old
                        // `expirePopup(modelData.n)` then passed null, matched nothing,
                        // and left a blank card wedged in the stack forever. See
                        // Notifications.closePopup() for the full account.
                        script: Notifications.closePopup(cell.modelData.psid,
                                                        cell._expire)
                    }
                }
            }
        }
    }
}
