import QtQuick
import "../../config"
import "../../components"

// ── BarGroup ──────────────────────────────────────────────────────────────────
// A cluster of related bar widgets. Replaces SplitPill.
//
// In SPLIT mode it draws its own pill and stands apart from its neighbours.
// In MERGED mode it drops its pill (the region draws one behind all the groups)
// and grows a divider on its leading edge instead, so the groups still read as
// distinct clusters inside the shared surface.
//
// The widgets inside never move between parents when the mode changes — only the
// backgrounds cross-fade and the padding animates. That is the whole point: it
// is why every bar widget is now instantiated exactly once instead of twice.
//
// Reads Config directly rather than taking barShape/barMode as properties. They
// are global preferences, and threading them down through every level of the bar
// was pure ceremony.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Keeps the group's pill expanded while its panel is open, even after the
    // pointer leaves — so an open panel visibly belongs to the button you
    // pressed.
    property bool forceExpanded: false

    // Set on every group except the first in its region.
    property bool showDivider: false

    // ── Appear / disappear ────────────────────────────────────────────────────
    // Whether this group belongs on the bar right now. A group whose modules can
    // all hide (the DND bell under "only while DND", the empty tray) doesn't pop
    // in and out — it COLLAPSES: width and opacity ease to zero and its
    // neighbours slide over to close the gap.
    //
    // `reveal` is the animated 0/1 factor; width and opacity multiply by it. This
    // is the same discipline as `pad` and `fuseDrop` and the deliberate absence of
    // a Behavior on implicitWidth — never animate a quantity that already tracks
    // content, animate a factor that moves between two fixed values and scale by
    // it. For a group that never hides, `shown` stays true so reveal is pinned at
    // 1 and implicitWidth tracks content 1:1, exactly as before — so the
    // width-animating widgets (Volume/Wifi/Visualizer) get no new target to chase.
    //
    // `_ready` gates the first frame: a group the layout opens with must be there
    // instantly, not grow in on every reload.
    property bool shown: true
    property bool _ready: false
    property real reveal: shown ? 1 : 0
    Behavior on reveal {
        enabled: root._ready
        NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
    }
    Component.onCompleted: root._ready = true

    visible: reveal > 0.005
    // Only while mid-collapse — a permanently-clipped group would cut off the
    // pill's hover-grow, which deliberately draws outside the group's box.
    clip:    reveal < 0.999
    opacity: reveal

    default property alias content: contentRow.data

    readonly property bool merged: Config.barMerged
    readonly property bool square: Config.barShape

    readonly property bool hovered: hover.hovered || forceExpanded

    // In merged mode the region supplies the outer padding, so each group needs
    // only enough to keep its neighbours off its widgets.
    //
    // `pad` is the animated quantity, NOT implicitWidth — see below.
    property int pad: merged ? Tokens.spacingSm : Tokens.spacingMd
    Behavior on pad { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

    // ── No Behavior on implicitWidth. This is load-bearing. ───────────────────
    // Several children (VolumePill, WifiPill, VisualizerPill) animate their OWN
    // widths. If this width were also animated, it would ease toward a target
    // that is itself easing — re-aiming every frame, chasing rather than
    // tracking. That chase IS the rubber-banding.
    //
    // The old SplitPill.qml carried a comment warning about exactly this, and I
    // reintroduced the bug anyway. Width tracks content 1:1; the content supplies
    // the motion. Only `pad` animates here, because it changes discretely with
    // barMode and so has nothing to chase.
    // Ceil: children may be text-derived and therefore fractional. A group landing
    // off-pixel smears its own 1px border AND every pill inside it.
    //
    // Scaled by `reveal` so a hiding group collapses its width to zero and its
    // neighbours slide in. reveal is 1 for anything that never hides, so this is a
    // no-op there — no Behavior, nothing to chase (see the reveal note above).
    implicitWidth: (Math.ceil(contentRow.implicitWidth) + pad * 2) * root.reveal

    // The PILL's height, not the control's — controls inside are pillHeight (24)
    // and centre within this. Safe to animate: it's a pure function of barShape,
    // a discrete toggle.
    // Derived from the user's bar thickness/inset rather than the Tokens constants —
    // the pill is the bar's height less the margin it floats in.
    implicitHeight: Config.barThickness - (square ? 0 : Config.barInset) * 2
    Behavior on implicitHeight { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

    HoverHandler { id: hover }

    // ── Hover grow, and the room it has to grow into ──────────────────────────
    // The pill grows outward horizontally and downward into the bar's bottom
    // margin (in square mode there is no margin, so it doesn't).
    //
    // Same story as BarRegion: the pill draws OUTSIDE the group's box on hover,
    // and at a screen edge there may be no room for it — the layer-shell surface
    // just clips whatever crosses its boundary. The Bar tells the edge-most groups
    // how much room they actually have.
    property int outerRoomLeft:  9999
    property int outerRoomRight: 9999

    property int growX: (root.hovered && Config.barHoverGrow) ? 3 : 0
    property int growY: (root.hovered && !root.square && Config.barHoverGrow) ? Config.barInset : 0

    Behavior on growX { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
    Behavior on growY { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

    readonly property int extendLeft:  Math.min(growX, outerRoomLeft)
    readonly property int extendRight: Math.min(growX, outerRoomRight)

    // ── Clearing the band, welded or not ──────────────────────────────────────
    // Whenever a band is showing (`screenFrame`/`barFrame`) and this group's
    // natural top would sit inside its depth, the pill's top has to move down to
    // the band's underside — otherwise it simply overlaps the band instead of
    // sitting below it (the "clips through the frame" bug). That clearance is
    // needed regardless of `frameMerge`: a merge-OFF pill still can't overlap the
    // band, it just clears it with a plain square-cornered top instead of a weld.
    // FrameFusion (declared after the pill) draws the weld visuals ONLY when
    // `fused` is true; the position math here is identical either way.
    //
    // `groupOrigin`, not `Config.barInset` directly: in square mode the group
    // itself sits flush at the screen edge (Bar's `inset` is 0 there), so barInset
    // plays no part in its actual position. Subtracting it anyway used to leave a
    // gap between where the math thought the pill's top was and where it really
    // was.
    readonly property bool fused: Config.frameFused
    readonly property bool bandVisible: Config.screenFrame || Config.barFrame
    readonly property int groupOrigin: root.square ? 0 : Config.barInset
    // Not readonly: the Behavior drives it through intermediate values.
    property real fuseDrop: root.bandVisible ? Math.max(0, Config.frameDepth - root.groupOrigin) : 0
    Behavior on fuseDrop { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

    Surface {
        id: pill

        x:      -root.extendLeft
        y:      root.fuseDrop
        width:  parent.width + root.extendLeft + root.extendRight
        height: parent.height + root.growY - root.fuseDrop

        elevation:    Tokens.elevationBar
        squareMode:   root.square
        squareTop:    root.fused
        cornerRadius: Config.barRoundness
        borderWidth:  Tokens.borderChrome
        glass:        Config.barGlass
        focused:    root.hovered

        // Two separate jobs, deliberately no longer conflated: `opacity` is the
        // cross-fade to the region's surface in merged mode, `fillOpacity` is the
        // user's translucency preference. Folded together, barOpacity also dimmed
        // the pill's border and it could never match the screen frame's.
        fillOpacity: Config.barOpacity
        opacity: root.merged ? 0.0 : 1.0
        visible: opacity > 0.005

        // growX/growY moved to the group root (they feed extendLeft/Right), and
        // their Behaviors with them. x/width track those 1:1 — no Behavior here,
        // or they'd chase an already-animating target.
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
    }

    // Declared after the pill so the flares and erasers draw over its border.
    // In merged mode the REGION's fusion takes over, exactly like its pill.
    FrameFusion {
        // Fills the group so FrameFusion can measure its own seam; children still
        // position in the same parent coordinates they always did.
        anchors.fill: parent
        active: Config.frameFused && !root.merged
        focused: root.hovered
        pillLeft: -root.extendLeft
        pillRight: root.width + root.extendRight
    }

    // ── Divider (merged mode) ─────────────────────────────────────────────────
    // Sits in the gap on the group's leading edge, marking where a split-mode
    // pill boundary used to be.
    Rectangle {
        id: divider
        // Spans the group's full height for the same reason the content does: the
        // divider separates two clusters, and those now run band-to-pill.
        anchors.verticalCenter: parent.verticalCenter
        // Centered in the gap between this group and the previous one.
        x: -(Tokens.spacingMd / 2) - width / 2
        width:  2
        height: parent.height - Tokens.spacingMd
        radius: 1
        color:  Colors.fg

        opacity: (root.merged && root.showDivider) ? 0.35 : 0.0
        visible: opacity > 0.005
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
    }

    Row {
        id: contentRow
        // Rounded rather than anchors.centerIn: centring gives a HALF-PIXEL x when
        // (parent.width - row.width) is odd, which puts every inset pill inside on a
        // half pixel and smears their 1px borders into a soft 2px. Snap to whole
        // pixels and the hairlines stay hairlines.
        x: Math.round((parent.width - width) / 2)
        // ── Content does NOT follow the fuse drop ─────────────────────────────
        // It used to re-centre by fuseDrop/2, into the shrunken pill below the
        // band. That works at frameThickness 10 and breaks at 24: the pill is then
        // 12px tall against ~24px of content, so icons and text spilled out of the
        // surface they were supposedly centred in.
        //
        // The band IS the pill's background above the drop — same fill, and
        // FrameFusion erases the border between them — so content is free to sit
        // across the seam. Centring in the group's full height keeps every widget
        // exactly where it is at every frame thickness, and the material behind it
        // just gets taller.
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.spacingMd
    }
}
