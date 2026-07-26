import QtQuick
import "../../config"
import "../../components"

// ── BarRegion ─────────────────────────────────────────────────────────────────
// One of the bar's three clusters (left / center / right): a row of BarGroups,
// plus the single shared pill that appears behind them in merged mode.
//
// Split and merged are the SAME row of the SAME widgets. The only differences
// are which surface is drawn (per-group, or one behind the region), how wide the
// gaps are, and whether dividers show. All three animate, so switching modes is
// a morph rather than a dissolve between two stacked copies of the bar.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Any of this region's panels is open — keeps the merged pill expanded.
    property bool forceExpanded: false

    default property alias groups: row.data

    readonly property bool merged: Config.barMerged
    readonly property bool square: Config.barShape
    readonly property bool hovered: hover.hovered || forceExpanded

    // Merged groups sit closer together (a divider separates them, not a gap in
    // the bar itself); split groups need a real gap so their pills don't touch.
    //
    // Split mode reads barSpacing, which used to be barInset — the same number that
    // decides how far the bar floats off the screen edge. Two jobs, one knob: you could
    // not push the pills apart without also pushing the whole bar inward.
    // (No Behavior here — it's readonly, and `row.spacing` already animates it.)
    readonly property int gap: merged ? Tokens.spacingMd : Config.barSpacing

    // In merged mode the region provides the outer padding each group gave up
    // (BarGroup.pad drops from spacingMd to spacingSm), so the padding at the
    // region's edges stays visually constant across the morph.
    //
    // This is INTERNAL padding — the row is inset by it and the region box grows to
    // match. It used to extend the SURFACE outward instead, which meant a merged
    // pill sat flush against x=0 while a split pill sat 4px in: the two modes
    // didn't line up, and hovering then pushed the merged pill clean off-screen.
    readonly property int edgePad: merged ? Tokens.spacingSm : 0

    // ── How far this region may extend past its own bounds, per side ──────────
    // The pill draws OUTSIDE the region's box while hovered. At a screen edge there
    // may not be room for that, and a layer-shell surface simply CLIPS whatever
    // crosses its boundary — which is why hovering used to slice the edge pills off.
    //
    // The region can't know its own margin, so the Bar tells it. Unlimited by
    // default (the centre region has room on both sides).
    property int outerRoomLeft:  9999
    property int outerRoomRight: 9999

    // Not readonly — the Behavior drives them through intermediate values.
    property int growX: (root.hovered && Config.barHoverGrow) ? 3 : 0
    property int growY: (root.hovered && !root.square && Config.barHoverGrow) ? Config.barInset : 0

    Behavior on growX { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
    Behavior on growY { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

    // What the pill ACTUALLY extends past the region box, clamped to the room
    // available on that side. Only the hover grow extends outward now.
    readonly property int extendLeft:  Math.min(growX, outerRoomLeft)
    readonly property int extendRight: Math.min(growX, outerRoomRight)

    // The box INCLUDES the padding, so the surface spans it exactly.
    implicitWidth:  Math.ceil(row.implicitWidth) + edgePad * 2
    // Same derivation as BarGroup: the bar's user-set thickness, less the margin the
    // pills float in. Tokens.barPillHeight() answered this back when both were constants.
    implicitHeight: Config.barThickness - (square ? 0 : Config.barInset) * 2

    Behavior on implicitHeight { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

    HoverHandler { id: hover }

    // Same fusion drop as BarGroup: the merged pill re-seats against the band's
    // underside and hangs from it. The groups inside shift their own content, so
    // the region moves nothing else.
    // ── Merged into the frame's side strip ────────────────────────────────────
    // Set by the Bar on its outermost regions when fused. The pill runs out past
    // the screen edge by one borderWidth so its own outer border falls OUTSIDE the
    // layer-shell surface and is clipped away — the frame has no stroke on its
    // outer face, and a Rectangle cannot drop a border on one side only. The
    // corners on that side square off for the same reason.
    property bool mergeLeft:  false
    property bool mergeRight: false
    readonly property real bleedLeft:  mergeLeft  ? Tokens.borderChrome : 0
    readonly property real bleedRight: mergeRight ? Tokens.borderChrome : 0

    readonly property bool fused: Config.frameFused
    // Clearing the band applies whether or not the pill actually welds to it —
    // see BarGroup's own comment on the identical property. `frameMerge` off just
    // means FrameFusion never activates and the pill stops short with a plain
    // square top, instead of erasing the seam and flaring into it.
    readonly property bool bandVisible: Config.screenFrame || Config.barFrame
    // Same reasoning as BarGroup.groupOrigin: in square mode the region sits flush
    // at the screen edge, so barInset isn't actually where its top is and must not
    // be subtracted as if it were.
    readonly property int groupOrigin: root.square ? 0 : Config.barInset
    // Not readonly: the Behavior drives it through intermediate values.
    property real fuseDrop: root.bandVisible ? Math.max(0, Config.frameDepth - root.groupOrigin) : 0
    Behavior on fuseDrop { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

    // ── The region's shared pill (merged mode) ────────────────────────────────
    Surface {
        id: pill

        x:      -root.extendLeft - root.bleedLeft
        y:      root.fuseDrop
        width:  parent.width + root.extendLeft + root.extendRight
                + root.bleedLeft + root.bleedRight
        height: parent.height + root.growY - root.fuseDrop

        elevation:    Tokens.elevationBar
        squareMode:   root.square
        squareTop:    root.fused
        squareLeft:   root.mergeLeft
        squareRight:  root.mergeRight
        cornerRadius: Config.barRoundness
        borderWidth:  Tokens.borderChrome
        glass:        Config.barGlass
        focused:      root.hovered

        // Same split as BarGroup: cross-fade in `opacity`, translucency in the fill,
        // so the border stays at full strength and matches the frame's.
        fillOpacity: Config.barOpacity
        opacity: root.merged ? 1.0 : 0.0
        visible: opacity > 0.005

        // growX/growY now live on the region root (they feed extendLeft/Right),
        // so their Behaviors moved there too. x/width just track those 1:1 — no
        // Behavior of their own, or they'd chase an already-animating target.
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
    }

    // Declared after the pill so the flares and erasers draw over its border.
    FrameFusion {
        anchors.fill: parent
        active: Config.frameFused && root.merged
        focused: root.hovered
        pillLeft:  -root.extendLeft - root.bleedLeft
        pillRight: root.width + root.extendRight + root.bleedRight
        // Hover grow pushes the pill below the region's own box.
        pillBottom: root.height + root.growY
        mergeLeft:  root.mergeLeft
        mergeRight: root.mergeRight
    }

    Row {
        id: row
        x: root.edgePad
        spacing: root.gap
        Behavior on spacing { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
    }
}
