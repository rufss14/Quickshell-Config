import QtQuick
import Quickshell
import "../../config"
import "../../services"
import "../../state"
import "../../services/drift.js" as DriftJs

// ── FrameDrift ────────────────────────────────────────────────────────────────
// The cookie field behind the BAR, the SIDEBAR and the screen FRAME — the rest of the shell's
// material, which the panels already wear (an experiment, behind Config.barCookies).
//
// Those are bands, not cards: a strip down each side, one along the bottom, the bar's band across
// the top, the sidebar's lobe. Each is covered by windows onto the SAME shared field the panels use
// (services/Drift), so a shape drifting out from under a panel carries on across the frame, and
// everything lines up by construction. `drift.js` works out the rectangles (`frameRects`) and cuts
// the long ones into pieces a window can show seamlessly (`chunks`); each piece is a DriftBridge —
// a plain rectangle, no corners, no seam line, no fade at its top (the fade belongs to a panel's
// join with the bar, not to every piece of the frame).
//
// ── Where it sits ─────────────────────────────────────────────────────────────
// IN the material, under the controls. The frame's ring is the blob's (z -1), but the bar's band and
// the sidebar's body are Surfaces drawn at default depth, and the first version of this sat at
// z -0.5 — under them, so nothing showed over the bar or the sidebar and only slivers over the
// thin strips. So each layer is declared in Bar.qml directly AFTER the surface it belongs over and
// BEFORE the pills / dock icons / modules (same z, so declaration order is paint order).
//
// ── How strongly ──────────────────────────────────────────────────────────────
// Not decided here. Every piece draws each picture at the strength the FIELD gives that picture
// (drift.js `strength`): what came out of a panel ("panels"), or each shape on its own 70s life
// ("everywhere" — on a surface that is always there, a shape drifting forever would be a permanent
// crowd), rising to a panel's full strength as it nears an open one. One number per picture, the
// same in a panel, a piece of the bar and the strip between them — so nothing changes where they
// meet. These pieces used to set their own (a life and double strength), and the join with a panel,
// drawn at full strength forever, cut every shape that crossed it.
//
// ── What it costs ─────────────────────────────────────────────────────────────
// Unlike a panel, the bar never closes, so this keeps the field's frame loop running for as long
// as it is on — a steady redraw of the bar's window. It stands down for Game mode and while a
// window is fullscreen on this monitor (when the bar's layer is hidden anyway), and `Config.motionEnabled`
// off still freezes it.
//
// Not matched, on purpose for a test: the frame's inner corners are concave arcs and these pieces
// are plain rectangles, so a shape can show a hair into a corner; and the sidebar lobe's rounded
// ends. The shapes are faint, so it reads as a soft edge; if it earns its keep it can be masked
// to the real outline.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property real screenW: 0
    property real screenH: 0
    // The frame's depth (0 with no frame) and the bar band's height (0 for a floating bar).
    property real strip: 0
    property real topH:  0
    // The sidebar lobe, in window coordinates (0 size while it is away).
    property real sideX: 0
    property real sideY: 0
    property real sideW: 0
    property real sideH: 0
    property string screenName: ""
    // Which of the material this layer covers: "ring" (the frame and the bar's band) or "side" (the
    // sidebar's lobe). Two layers, because the bar's surface and the sidebar's are each drawn at
    // the shell's default depth and each hides anything BELOW it — so each layer is declared right
    // after the surface it belongs over (Bar.qml), where a single one could only sit under both.
    property string part: "ring"
    // ── Two ways to have them here (Config.barCookiesFrom) ────────────────────
    //   "panels"      (the default) only what drifts out of a panel, carrying on across the bar until
    //                 it leaves the screen. With no panel open and nothing lit there is nothing to
    //                 show, so it does not hold the field's frame loop (`Drift.alive`).
    //   "everywhere"  a field of their own, each shape coming and going on its life, always running.
    // Not while the blob draws the field itself (Drift.inBlob): it covers everything these pieces do.
    readonly property bool on: Config.barCookies && !PowerSaver.quiet && !Drift.inBlob
                               && Fullscreen.byMonitor[root.screenName] !== true
                               && (Drift.everywhere || Drift.alive)

    // Pieces no wider than the field's repeat can show seamlessly (less a shape and a margin).
    // Built whenever the feature is on, not only while it is showing: tearing down and rebuilding
    // ~300 shape items each time a panel opens or closes would hitch. The whole layer is simply
    // hidden (`visible`) when there is nothing to show, and a hidden window onto the field holds
    // nothing — in particular not the field's frame loop.
    visible: root.on
    // Over everything in the window while Drift.raised (a diagnostic: `drift layers top`).
    z: Drift.raised ? 1000 : 0

    readonly property var pieces: Config.barCookies
        ? DriftJs.framePieces(root.screenW, root.screenH, root.strip, root.topH,
                              { x: root.sideX, y: root.sideY, w: root.sideW, h: root.sideH },
                              Drift.periodW - 120, Drift.periodH - 120).filter(p => p.kind === root.part)
        : []

    // ── The strips between a panel and the surface it is welded to ────────────
    // A welded panel is held a fillet radius off the bar, the frame or the sidebar so the blob can
    // bridge the two — and that strip belongs to neither, so a cookie crossing from a panel onto
    // the sidebar was cut at the strip: the cut at the sidebar's face. Wherever a panel faces one of
    // these surfaces across a gap the blob can bridge (drift.js `gapPieces`), a window onto the same
    // field is laid over the gap. A FIXED pool, bound by index: the rectangles change every frame a
    // panel animates, and a Repeater over a changing array would rebuild its delegates each time.
    // Without the plugin there is nothing to bridge with (the gap is just room), so none.
    readonly property var surfaces: Config.barCookies
        ? DriftJs.frameRects(root.screenW, root.screenH, root.strip, root.topH,
                             { x: root.sideX, y: root.sideY, w: root.sideW, h: root.sideH })
        : []
    readonly property var gaps: (root.on && Morph.available)
        ? DriftJs.gapPieces(Drift.panelsFor(root.screenName), root.surfaces, Morph.smoothing)
                 .filter(g => g.kind === root.part)
        : []

    Repeater {
        model: 8
        delegate: DriftBridge {
            required property int index
            readonly property var g: root.gaps[index] ?? null
            fade: 0
            source: false
            screenKey: root.screenName
            role: "gap"
            gapX: g ? g.x : 0
            gapY: g ? g.y : 0
            gapW: g ? g.w : 0
            gapH: g ? g.h : 0
        }
    }

    Repeater {
        model: root.pieces
        delegate: DriftBridge {
            required property var modelData
            fade: 0
            source: false
            screenKey: root.screenName
            role: root.part
            gapX: modelData.x
            gapY: modelData.y
            gapW: modelData.w
            gapH: modelData.h
        }
    }
}
