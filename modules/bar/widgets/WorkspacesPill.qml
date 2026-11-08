import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"
import "../../../services/workspaces.js" as Wsp

// ── WorkspacesPill ────────────────────────────────────────────────────────────
// Five workspace slots, paging as the focused workspace crosses a page boundary.
//
// ── Fixed slots, not a Row that reflows ───────────────────────────────────────
// This used to be a Row of five dots where the focused one stretched from 10px to
// 26px IN PLACE, shoving its neighbours sideways as it went. That reads as the
// dots rearranging themselves rather than as one thing moving: nothing travels,
// everything just resizes.
//
// Now the slots never move. An indicator TRAVELS between them, and — this is the
// part that makes it read as one object rather than a jump — its two edges move
// at different speeds, so it stretches on the way and contracts as it arrives.
// See the `lead`/`trail` springs below.
//
// ── Occupied workspaces merge ─────────────────────────────────────────────────
// Adjacent occupied slots are drawn as ONE pill, not as separate dots. The
// occupied-run Repeater below is keyed on the five FIXED slot indices, same as
// the empty-dot layer — never on the runs themselves (a Repeater fed a freshly
// computed run list resets its entire delegate set on every recompute, which is
// what used to make an unrelated Hyprland event, or even a real merge, look like
// the whole pill flickering back into existence). Each slot decides for itself
// whether it is the head of a run and, if so, how long that run is; a merge is
// just the head's `width` Behavior growing across the gap, and the slot it
// swallows shrinks away via the same `scale` Behavior a genuinely new run grows
// in with — see the Repeater's own comment for the detail.
//
// ── Colours still follow the accent contract ──────────────────────────────────
// The focused workspace is `primary` (it is the active one); occupied — on this
// monitor or any other — is the same accent at 30%. No separate "other monitor"
// tint: which monitor a workspace happens to live on isn't something this pill
// distinguishes any more. Empty is 10%. (Since 2026-10-31, empty is a small dot at 40%
// instead — Material's page indicator; a full-size disc at 10% read as a hole.)
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property var monitor: null

    property color accent: Colors.of(QsWindow.window).primary

    // How many slots the pill shows at once. Not a literal at the use sites any
    // more: `Wsp.page()` takes it, so changing it here changes the paging too.
    // The old code encoded "two pages of five" as `currentWs <= 5 ? 1 : 6`, which
    // looked general and was not.
    readonly property int shown: 5

    readonly property int currentWs: monitor?.activeWorkspace?.id ?? 1
    readonly property var pageInfo:  Wsp.page(root.currentWs, root.shown)
    readonly property int wsStart:   root.pageInfo.start
    readonly property int activeIndex: root.pageInfo.index

    // ── Slot geometry ─────────────────────────────────────────────────────────
    // Sized off `Config.barPillHeight` (the same number every other pill in the
    // bar sizes itself to) rather than a separate `Tokens.spacingLg * iconScale`
    // formula — that one grew slower than the pill around it, so at the Big
    // preset the dots read as small and adrift in a much taller box. Square
    // slots: a numeral off-centre in a tall, narrow dot is the "digit pushed
    // out" failure the old comment warned about, just from the other axis.
    //
    // Width is wider than tall on purpose — a square slot read as cramped next
    // to the bar's other pills once height started tracking barPillHeight, so
    // width scales from the same number rather than matching it 1:1.
    readonly property int dotH:  Config.barPillHeight - Tokens.spacingXs * 2
    readonly property int slotW: Math.round(root.dotH * 1.35)
    // The corner of everything that spans a slot (the indicator, an occupied run, the drop
    // mark): concentric with the inner pill round the module, which sits spacingSm off it
    // (its own spacingXs past the pill's height, plus the slots' spacingXs inset) — so at a
    // low bar roundness the indicator follows the pill's curve instead of staying a capsule
    // inside a rounder-cornered box. The empty dots stay round: they are dots.
    readonly property real slotRadius: Tokens.corner(Config.barShape,
        Math.min(root.dotH / 2, Math.max(0, Config.barRoundness - Tokens.spacingSm)))
    // An empty workspace: a small dot centred in its slot, Material's page indicator (the
    // user's pick, 2026-10-31 — a full-size faint disc read as a hole in the pill).
    readonly property int emptyDot: Math.max(Tokens.spacingSm, Math.round(root.dotH / 4))

    // Occupancy is global (`Hyprland.workspaces.values`, not scoped to this
    // monitor), so a workspace appearing/disappearing on the OTHER monitor
    // changes THIS pill's rendering without any property of ITS OWN monitor
    // changing. Same fix as Keyboard.qml: every raw Hyprland event forces a
    // fresh look, cheap here since `slots` is five array scans, not a
    // subprocess. `Qt.callLater`, not a direct `_tick++` — `rawEvent` is the
    // socket line arriving, not "Hyprland's objects finished updating"; bumping
    // synchronously could re-read a tick early and sit on that stale read
    // until the next event papered over it.
    property int _tick: 0
    Connections {
        target: Hyprland
        function onRawEvent(event) { Qt.callLater(() => root._tick++) }
    }

    // ── Occupancy, computed ONCE ──────────────────────────────────────────────
    // This was five independent `Hyprland.workspaces.values.find()` calls, one per
    // dot, each walking the whole model. One pass builds what every layer below
    // needs.
    //
    // If this ever shows up as a binding loop, the documented remedy (CLAUDE.md,
    // the CavaBG.suppressed case) is to promote it to a plain notifying property
    // on the Hypr service rather than to guard it here.
    readonly property var slots: {
        const _dep = root._tick
        const out = []
        for (let i = 0; i < root.shown; i++) {
            const id = root.wsStart + i
            const ws = Hyprland.workspaces.values.find(w => w.id === id)
            out.push({ id: id, occupied: ws !== undefined })
        }
        return out
    }


    // ── Dropping a dragged window ─────────────────────────────────────────────
    // Which slot a point in this window's scene falls on, or -1. The bar sits at
    // its monitor's origin, so monitor-local coordinates ARE scene coordinates.
    // The pill's whole height counts, not just the dots: it's a drop made while
    // dragging a whole window, not an aimed click.
    function slotAt(x, y) {
        const p = slotRow.mapFromItem(null, x, y)
        const top = slotRow.mapFromItem(root, 0, 0).y
        if (p.y < top || p.y > top + root.height || p.x < 0) return -1
        const i = Math.floor(p.x / root.slotW)
        return i < root.shown ? i : -1
    }

    // While Hyprland carries a window (UiState.windowDrag), follow the pointer so
    // the slot a release would pick lights up. Hyprland emits nothing mid-drag, so
    // this is Pointer's fast poll, held only for the drag.
    readonly property bool tracking: UiState.windowDrag !== "" && root.monitor !== null && root.visible
    property bool _tracked: false
    onTrackingChanged: {
        if (root.tracking === root._tracked) return
        if (root.tracking) Pointer.acquireFast(); else Pointer.releaseFast()
        root._tracked = root.tracking
    }
    Component.onDestruction: if (root._tracked) Pointer.releaseFast()

    readonly property int dropIndex: root.tracking
        ? root.slotAt(Pointer.pos.x - (root.monitor?.x ?? 0), Pointer.pos.y - (root.monitor?.y ?? 0))
        : -1

    implicitWidth:  root.slotW * root.shown + Tokens.pillPadding * 2
    implicitHeight: Config.barPillHeight

    // No pill of its own — the enclosing BarGroup already draws one around
    // every module in it (see BarGroup.qml / IconButton.container).

    Item {
        id: slotRow
        anchors.centerIn: parent
        width:  root.slotW * root.shown
        height: root.dotH

        // ── Occupied runs ─────────────────────────────────────────────────────
        // One pill per contiguous run, drawn by the run's HEAD slot (the first
        // occupied slot that isn't preceded by another occupied one) spanning its
        // own width across however many slots the run covers.
        //
        // ── Fixed identity, not a Repeater over the runs themselves ───────────
        // That was the earlier shape here, and it looked right on paper: `Wsp.runs()`
        // collapses occupancy into a list of runs, a Repeater draws one Rectangle per
        // run, Behaviors on x/width carry a merge smoothly. It wasn't right in
        // practice — every recompute of that list is a BRAND NEW array of brand new
        // objects (this property is a plain JS expression, not a model with any
        // notion of "this is the same run as before"), and Repeater has no way to
        // tell a merged run apart from an unrelated one. It resets: EVERY delegate is
        // destroyed and recreated, including ones nothing happened to, and each new
        // one starts from `scale: 0` and grows in — which is "it refreshes the whole
        // pill" exactly as reported, on every Hyprland event that touches occupancy,
        // not only on an actual merge.
        //
        // This Repeater's model is `root.shown` instead — a constant, never a value
        // that changes shape — so it behaves exactly like the empty-slot layer below:
        // five delegates, created once, that live for the pill's whole lifetime.
        // Which slot is a run's head, and how long that run is, are read back out of
        // `root.slots` per-delegate instead of being handed in as the model. A slot
        // that stops being a head (absorbed into a run growing over it from the left)
        // shrinks to nothing via the same `scale` Behavior a genuinely new run grows
        // in with, rather than vanishing on the same frame its neighbour's Behavior
        // starts animating — so a two-run merge reads as one pill sliding over and
        // swallowing the other, not as a flicker.
        Repeater {
            model: root.shown

            Rectangle {
                id: runRect
                required property int index
                readonly property var slot: root.slots[index]

                readonly property bool isHead:
                    slot.occupied && (index === 0 || !root.slots[index - 1].occupied)

                readonly property int runLength: {
                    if (!runRect.isHead) return 1
                    let n = 0
                    for (let i = index; i < root.shown && root.slots[i].occupied; i++) n++
                    return n
                }

                x:      index * root.slotW
                width:  runRect.runLength * root.slotW
                height: root.dotH
                radius: root.slotRadius
                color:  Colors.of(QsWindow.window).alpha(root.accent, 0.30)

                // 0 for anything that isn't currently a run's head — covers both "was
                // never occupied" and "got absorbed into the run growing over it".
                // Either way this is the ONE property that decides whether the run
                // pill reads as present, so it's what both the entrance and the
                // absorbed-into-a-merge exit ride on.
                scale: runRect.isHead ? 1 : 0

                Behavior on scale {
                    NumberAnimation {
                        duration: Motion.standard
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Motion.emphasizedDecel
                    }
                }
                Behavior on x      { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                Behavior on width  { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                Behavior on radius { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                Behavior on color  { ColorAnimation  { duration: Motion.fast } }
            }
        }

        // ── Per-slot marks: empty ───────────────────────────────────────────
        // Occupied slots are covered by the run pills above; this only draws
        // the faint dot for a workspace with nothing on it.
        Repeater {
            model: root.shown

            Rectangle {
                required property int index
                readonly property var slot: root.slots[index]

                x: index * root.slotW + (root.slotW - root.emptyDot) / 2
                y: (root.dotH - root.emptyDot) / 2
                width:  root.emptyDot
                height: root.emptyDot
                radius: Tokens.corner(Config.barShape, root.emptyDot / 2)

                visible: !slot.occupied
                color:   Colors.of(QsWindow.window).alpha(root.accent, 0.40)

                Behavior on radius { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                Behavior on color  { ColorAnimation  { duration: Motion.fast } }
            }
        }

        // ── The active indicator ──────────────────────────────────────────────
        // Two edges heading for the SAME target at different speeds. The fast one
        // arrives first, so the pill stretches across the ground it is covering;
        // the slow one catches up and it contracts into place.
        //
        // Both aim at the same target — the difference is entirely in the two springs
        // (Material 3 Expressive's: the lead on the fast spatial one, which overshoots the
        // slot a little, the trail on the standard one). That is why there is no direction
        // latch: travelling left, the lead is simply the smaller of the two, and `Math.min`
        // picks it up without anyone having to know which way we went. (An earlier version
        // tracked direction explicitly and had the two edges CROSS on a reversal, which
        // collapsed the indicator to zero width mid-flight.) A spring keeps its speed when
        // the target moves, so switching again mid-flight carries on rather than restarting.
        //
        // `x` and `width` carry NO Behavior of their own: they track lead/trail 1:1.
        // Easing them too would be a value easing toward a target that is itself
        // easing — the chase Motion.qml opens with.
        Rectangle {
            id: indicator

            SpringValue { id: lead;  spec: Motion.springSpatialFast; epsilon: 0.1; target: root.activeIndex * root.slotW }
            SpringValue { id: trail; spec: Motion.springSpatial;     epsilon: 0.1; target: root.activeIndex * root.slotW }

            x:      Math.min(lead.value, trail.value)
            width:  Math.abs(lead.value - trail.value) + root.slotW
            height: root.dotH
            radius: root.slotRadius
            color:  root.accent

            Behavior on radius { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
            Behavior on color  { ColorAnimation  { duration: Motion.fast } }
        }

        // ── Drop target ───────────────────────────────────────────────────────
        // The slot a dragged window would land on if let go now: the accent's
        // outline around it, and a fill that grows in. Drawn under the numerals so
        // the digit stays legible.
        Rectangle {
            id: dropMark
            property int held: 0
            // Where it last pointed, kept while it fades out.
            readonly property bool lit: root.dropIndex >= 0
            Connections {
                target: root
                function onDropIndexChanged() { if (root.dropIndex >= 0) dropMark.held = root.dropIndex }
            }

            x:      dropMark.held * root.slotW
            width:  root.slotW
            height: root.dotH
            radius: root.slotRadius
            color:  Colors.of(QsWindow.window).alpha(root.accent, 0.45)
            border.width: Tokens.borderChrome
            border.color: root.accent
            opacity: dropMark.lit ? 1 : 0
            scale:   dropMark.lit ? 1 : 0.6

            Behavior on x       { NumberAnimation { duration: Motion.fast; easing.type: Motion.travel } }
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            Behavior on scale   { NumberAnimation { duration: Motion.fast; easing.type: Motion.travel } }
        }

        // ── Numerals ──────────────────────────────────────────────────────────
        // Above everything, so the active one reads against the indicator.
        //
        // A flat colour swap, not the masked/clipped recolour caelestia does. Theirs
        // flips each digit progressively as the indicator's edge sweeps over it,
        // which costs two live render targets per bar per monitor, permanently, on a
        // surface that redraws on every hover. At this size the animated swap is
        // indistinguishable — revisit only if the flip actually reads as a pop.
        // A workspace with its own icon (WorkspaceLabels, set from the overview) shows that
        // in place of its number.
        Repeater {
            model: root.shown

            Item {
                id: numeral
                required property int index
                readonly property bool isActive: index === root.activeIndex
                readonly property string icon: WorkspaceLabels.iconOf(root.slots[index].id)
                readonly property color ink: isActive ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fg

                x: index * root.slotW
                width: root.slotW
                height: root.dotH
                visible: root.slots[index].occupied || isActive || index === root.dropIndex

                // The bar's label style at the slot's own size (it scales with the icons).
                BarLabel {
                    anchors.fill: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment:   Text.AlignVCenter
                    visible: numeral.icon === ""
                    text:    root.slots[numeral.index].id
                    color:   numeral.ink
                    variant:   "micro"
                    sizeScale: Config.barIconScale
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    visible: numeral.icon !== ""
                    name: visible ? numeral.icon : "star"
                    fill: 1
                    color: numeral.ink
                    font.pixelSize: Math.round(Tokens.fontMicro * Config.barIconScale)
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }
            }
        }

        // One MouseArea over the row rather than one per slot: the slots are a fixed
        // grid now, so which one was hit is arithmetic.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor

            // Through the service, not a hand-rolled dispatch string. Hyprland
            // silently drops a dispatch with an unrecognised key, so a second copy
            // of that syntax is a second thing that can rot without ever saying so.
            onClicked: function (m) {
                const i = Math.floor(m.x / root.slotW)
                if (i >= 0 && i < root.shown) Hypr.focusWorkspace(root.slots[i].id)
            }
        }

        // A window dragged here with SUPER+drag goes to the workspace it's let go
        // on. Hyprland owns that drag, so this only hears the release (UiState.
        // windowDropped, from hypr/binds.lua) in monitor-local coordinates — which
        // are this window's scene coordinates, since the bar sits at the monitor's
        // origin. `follow = false`: the window goes, you stay.
        Connections {
            target: UiState
            function onWindowDropped(address, monitor, x, y) {
                if (monitor !== (root.monitor?.name ?? "") || !slotRow.visible) return
                const i = root.slotAt(x, y)
                if (i < 0) return
                UiState.claimWindowDrop()       // it's ours: no snap zone takes it too
                Hypr.moveWindowToWorkspace(address, root.slots[i].id)
            }
        }
    }
}
