import QtQuick
import "../../config"
import "../../components"
import "../../services"

// ── DriftBridge ───────────────────────────────────────────────────────────────
// The cookie field across the SEAM between two welded panels.
//
// Two open panels are held `mergeGap` apart (BarPanelDock) so the blob can bridge them into
// one mass — which means the cards themselves are two rectangles with a strip of bridge
// material between them, and each card's own DriftShapes stops at its own edge. A cookie
// crossing from one panel to the next was therefore cut hard at both edges and absent in the
// strip: the join read as a cut through the shape.
//
// This is one more window onto the same shared field (services/Drift), laid over that strip.
// Every window maps the field through screen coordinates, so what it draws lines up with both
// neighbours by construction — there is nothing to keep in step. It is a plain rectangle (no
// corner radius, no seam line) with the same fade at the top as the cards', so the three read
// as one surface.
//
// `gapX/Y/W/H` are in BarPanelDock's coordinates; an empty one (W or H ≈ 0: not both open, not
// close enough for the blob to bridge) hides it, and a hidden DriftShapes holds nothing.
// A pixel of overscan each side tucks its edge under the cards', so no hairline shows between.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property real gapX: 0
    property real gapY: 0
    property real gapW: 0
    property real gapH: 0
    // How far down from its top the shapes take to arrive. A panel's seam keeps the cards' fade;
    // a piece of the frame (FrameDrift) has none.
    // (The same default as a card's, or the strip between two panels would fade where they do not.)
    property real fade: Drift.flows ? 0 : Tokens.spacingXl * 2
    // Between two panels this is panel material, and draws the field as they do. A piece of the bar,
    // the frame or the sidebar (FrameDrift) is not: it draws each picture at the field's own strength
    // for it. See DriftShapes.source.
    property bool source: true
    property string screenKey: ""
    property string role: "bridge"

    readonly property real _over: 1

    x: root.gapX - root._over
    y: root.gapY
    width:  root.gapW + root._over * 2
    height: root.gapH
    // The blob draws the field across every strip itself while it can (Drift.inBlob).
    visible: root.gapW > 0.5 && root.gapH > 1 && !Drift.inBlob

    DriftShapes {
        anchors.fill: parent
        radius: 0
        fade: root.fade
        source: root.source
        screenKey: root.screenKey
        role: root.role
        seam: false
    }
}
