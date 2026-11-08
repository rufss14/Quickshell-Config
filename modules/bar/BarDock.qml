import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── BarDock ───────────────────────────────────────────────────────────────────
// One panel slot hanging off the bar, living INSIDE Bar's own window.
//
// ── Why it can't be its own window ────────────────────────────────────────────
// `Quicktest.Blobs`' metaball shader fuses shapes by sampling them in a single
// Qt Quick scene graph. Two layer-shell surfaces are composited independently by
// Hyprland — there is no way for one surface to blend pixels with a neighbour's.
// So a panel that genuinely MELTS out of the bar has to share the bar's window,
// which is why PanelHost's three separate PanelWindows moved in here. See Bar.qml
// for how the window reserves the room, masks it, and hands over keyboard focus.
//
// ── The melt is not in here ───────────────────────────────────────────────────
// This dock owns no blob of its own. Its card's geometry goes UP to the single
// BlobBarLayer mounted in Bar.qml, which holds one BlobGroup containing the bar
// itself plus every panel — because a metaball union needs two real shapes, and a
// panel can only melt into the bar if the bar is in the same group. See
// components/blob/BlobBarLayer.qml.
//
// What comes back down is `deformMatrix`: the spring deformation the blob computed
// from the card's own velocity, applied to the card so its CONTENT squashes and
// stretches with the shape behind it rather than riding on top of it rigidly.
// caelestia-dots/shell wires exactly this, at the bottom of ContentWindow.qml.
//
// ── The card grows, the window never does ─────────────────────────────────────
// Same discipline PanelHost had, kept verbatim: this Item is sized once to a
// fixed ceiling and only `card` animates inside it. Animating a PanelWindow's
// implicitHeight resizes the real Wayland surface every frame (new buffer +
// compositor roundtrip) and stutters however clean the QML is.
//
// ── Height comes from the caller, not from `shown` ────────────────────────────
// `cardHeight` is 0 when the slot is closed and `shown` only drives the fade.
// They are deliberately separate: Accordion's sibling-to-sibling swap fades the
// old card out (`shown` false) while the card is still mid-resize toward the new
// panel's height, and folding the two together would collapse the card to zero in
// the middle of that swap.
//
// ── The slide, and why it needs a clip ───────────────────────────────────────
// The card doesn't just grow — it SLIDES out from under the bar, starting
// `slideDistance` px higher than it lands. `reveal` clips at the bar's underside,
// so the part still travelling is genuinely hidden behind the bar rather than
// drawn over its pills, which is what makes it read as emerging from the bar
// instead of appearing next to it.
//
// The clip is on `reveal` and NOT on this Item, because the melt has to reach UP
// past y=0 into the bar strip — that's where its notch lives. Clipping the dock
// would erase exactly the half of the blob that does the welding. (Card.qml
// documents the same mistake made one level down: `clip` on the card root ate the
// negative-z shadow child and flattened every panel in the shell.)
//
// ── Erasing the frame's underline ────────────────────────────────────────────
// In unified+anchored+screenFrame, `Config.barDrawsUnderline` is FALSE — the bar
// draws no bottom border and BarFrameEdge's "line" mount carries one unbroken
// stroke under it instead, on top of everything in the window. Measured against a
// (21,39,58) bar it lands at (155,163,169): a bright 2px rule running the full
// width of the screen, straight across the join. Fills either side of it already
// match to within 1/255, so that stroke was the ENTIRE seam.
//
// It is not reachable from here except by covering it, which is the same answer
// FrameFusion gives for the band strokes it has to remove. See Bar.qml for why
// this dock is declared after that mount.
//
// ── Falls back cleanly when the plugin isn't built ────────────────────────────
// Without the C++ plugin, Bar.qml simply never mounts the layer and `deformMatrix`
// stays identity — this is exactly the plain slide-and-fade dropdown it has always
// been, with no import of Quicktest.Blobs anywhere in the bar's own chain.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: dock

    required property int screenH

    // Which side of the bar this slot hangs from. Decides the anchored corner —
    // which is both where the card grows from and where the blob's neck attaches.
    property string edge: "left"          // "left" | "right" | "center"

    property bool shown: false            // fade the card in (opacity only)
    property int  cardWidth:  0
    property int  cardHeight: 0           // 0 = closed; the caller's live content height

    // The widest this slot can ever get. The Item is sized to it once, so the
    // dock's own footprint never moves when a wider panel opens inside it.
    property int  maxCardWidth: dock.cardWidth

    // ── contentZoom ───────────────────────────────────────────────────────────
    // The panel's size multiplier (Config.panelZoom, via BarPanelDock.zoomFor).
    // `cardWidth`/`cardHeight` arrive ALREADY multiplied by it; this is the same
    // number again so the content can be drawn at the size the box was given.
    //
    // The content is laid out at its NATURAL size and scaled — not laid out at the
    // zoomed size. That is the whole point of the feature: a relayout would rewrap
    // text and reflow the wallpaper grid into a different number of columns, so the
    // panel would change SHAPE as it resized. One render transform can't; both axes
    // carry the same factor, so the silhouette is preserved exactly and the blob
    // sees a card that is simply bigger.
    //
    // (This is deliberately NOT StyledText.sizeScale, which asks for a bigger glyph
    // and reflows. See the note there, and Config.panelZoom.)
    property real contentZoom: 1.0

    // ── Resizing ──────────────────────────────────────────────────────────────
    // The grips in the card's bottom corners. `resizable` is the caller's gate (a
    // panel has to be open to be resized); `resizeRequested` carries the multiplier
    // the drag is asking for, and BarPanelDock is what decides to write it. This
    // file detects the gesture and draws the handle; it owns no preference.
    property bool resizable: false
    property bool resizing:  false
    signal resizeRequested(real zoom)

    // ── Only the corners that can actually MOVE get a grip ────────────────────
    // The card is anchored — left dock to the left edge, right dock to the right,
    // centre to the middle — and it hangs from the bar, so the top edge is pinned
    // too. That leaves exactly one free corner on a side dock: the one diagonally
    // opposite its anchor. Putting a grip on the pinned corner of a side dock would
    // be a handle that cannot follow the pointer, which reads as broken rather than
    // as a limit.
    //
    // The centre dock is anchored by its CENTRE, so both bottom corners move — and
    // both move at half rate, since width is shared between the two sides. That is
    // what `gripGain` corrects for; without it the centre panel resizes at half the
    // speed of the pointer and feels heavy.
    readonly property var gripCorners: !dock.resizable ? []
                                     : dock.edge === "left"  ? ["right"]
                                     : dock.edge === "right" ? ["left"]
                                                             : ["left", "right"]
    readonly property real gripGain: dock.edge === "center" ? 2 : 1

    default property alias content: cardBody.data

    // The same box `content` lands in, for a panel that is REPARENTED in rather than
    // declared as a child — BarPanelDock's always-mounted MediaPanel.
    readonly property Item body: cardBody

    // ── Hugging the bar and the frame ─────────────────────────────────────────
    // The melt bridges a GAP, and has nothing to say about a card with no gap to
    // bridge. When the bar is anchored (flush at the screen's top edge) the card
    // sits flush against the bar's own bottom edge: no margin, square top corners,
    // top border erased — the same "erase the seam, the fill already matches"
    // trick FrameFusion uses for pills welding into the frame band. Gated rather
    // than unconditional: in FLOATING bar mode there is no continuous surface to
    // hug, so a flush weld would connect the card to nothing.
    readonly property bool hugBar: Config.barAnchored
    // Only an edge-anchored dock can weld into the frame's side strip; a centred
    // one is nowhere near it.
    readonly property bool hugFrame: Config.frameFused && Config.screenFrame
                                     && dock.edge !== "center"

    readonly property int topMargin:  dock.hugBar ? Config.barSurfaceHeight : (Config.barExtent + 2)

    // ── The unified sidebar's face, when it holds this side ───────────────────
    // From the screen edge (SideRail.panelFace, handed down through BarPanelDock);
    // 0 when no sidebar holds this side's panels. The sidebar is the frame's inner
    // edge here then, so the card hangs off ITS face the way it hangs off the
    // bar's underside, and the blob melts it out of the corner the two make.
    property int sideFace: 0

    // ── Inset to the frame's inner edge, never ON it ──────────────────────────
    // This was 0 — the card ran flush to the screen edge and covered the strip. It
    // covered BarFrameEdge's left/right STUB too, for the whole `frameApron`: the
    // strip's stroke visibly restarted at `barExtent + frameApron` (measured: it
    // resumed at y=75 with barBottom=72) and the gap above read as the panel
    // clipping the frame.
    //
    // caelestia never overlaps its border either — Panels.qml is `anchors.margins:
    // borderThickness`, so every panel stops at the ring's inner edge and the blob
    // does the joining. Same here, and the sidebar's face is that edge when there
    // is one: flush against it when welded, the usual margin off it when floating,
    // as off the screen edge.
    readonly property int edgeMargin:
          dock.sideFace > 0 ? dock.sideFace + (dock.hugFrame ? 0 : Config.barInset + Tokens.spacingMd)
        : dock.hugFrame     ? Config.frameDepth
        :                     (Config.barInset + Tokens.spacingMd)
    readonly property int bottomSafe: Tokens.spacingMd
    readonly property int maxHeight:  Math.max(0, dock.screenH - dock.topMargin - dock.bottomSafe)

    // The card's live inset: `edgeMargin`, eased when the sidebar sinks or rises
    // under an open panel (SUPER+SHIFT+D), on the sidebar's own reveal curve, so
    // the panel rides back to the strip with it instead of jumping.
    property real edgeInset: dock.edgeMargin
    Behavior on edgeInset {
        NumberAnimation {
            duration: Motion.surfaceDuration(dock.sideFace > 0)
            easing.bezierCurve: Motion.emphasizedDecel
            easing.type: dock.sideFace > 0 ? Easing.BezierSpline : Motion.exitCurve
        }
    }

    // ── Shadow room ───────────────────────────────────────────────────────────
    // Paint stops at the window edge — and at `reveal`'s clip, which is this Item
    // — so the Item reaches past the card by the room its shadow needs to fall
    // into: `shadowRoom` on the far side, and the inset on the near one, which is
    // all there is before the screen edge. Tokens.shadowRoom is the single source —
    // the side that RESERVES the room and the side that DRAWS the shadow must call
    // the same function or they disagree by a pixel and it reads as clipping.
    //
    // The card used to sit at min(shadowRoom, edgeMargin), which is the margin only
    // while the margin is under the room (12 against 14 at the defaults). With
    // shadows turned down, or a frame deeper than the room, the card slid onto the
    // strip, and a sidebar's face was out of reach entirely.
    readonly property int shadowRoom: Tokens.shadowRoom(Tokens.elevationCard)

    implicitWidth:  Math.max(dock.edgeMargin, dock.edgeInset) + dock.maxCardWidth + dock.shadowRoom
    implicitHeight: dock.maxHeight

    // Bar.qml reads this to add the card to the window's input mask — the reserved
    // room around it must not swallow clicks meant for the desktop below.
    // ── Welded, and what that changes about the outline ───────────────────────
    // A welded card is not a floating panel that happens to touch the bar — it is
    // a lobe of the same mass. So it stops drawing a PANEL outline (Colors.outline,
    // 1px, the recipe every free-floating card uses) and draws the RING's instead:
    // Colors.frameLine at Config.frameBorderWidth, the same stroke BarFrameEdge and
    // ScreenFrame carry. Measured against the old code, those two were (56,68,80)
    // at 1px and (162,170,176) at 2px — nearly 3× apart in brightness, which is
    // what read as "the border from the panels doesn't match".
    readonly property bool welded: dock.hugBar || dock.hugFrame

    // ── The one rule that makes a join blend ──────────────────────────────────
    // The bar and the frame merge cleanly because NEITHER draws a border at the
    // join — BarFrameEdge carries one continuous stroke around the whole ring and
    // there is no second outline anywhere to align with it. A panel with its own
    // rectangular border can never do that: its stroke is a closed rectangle and
    // the blob's silhouette is organic, so the two disagree by construction. Three
    // rounds of fillet-tuning were spent trying to reconcile them.
    //
    // So a blob-welded panel draws no outline at all. It is material extruded from
    // the ring, exactly as the bar is, and the blob's smooth-min supplies the whole
    // visible shape. This is what caelestia does — none of their panels stroke
    // anything; the "border" in that shell is the ring's own mass.
    //
    // Gated on the plugin: with no blob there is nothing to supply a silhouette, so
    // an unstroked panel would be a shapeless slab and the old outline is correct.
    readonly property bool blobWeld: dock.welded && Morph.available
    readonly property color lineColor: dock.welded ? Colors.of(QsWindow.window).frameLine : Colors.of(QsWindow.window).outline
    readonly property int   lineWidth: dock.welded ? Config.frameBorderWidth : Tokens.borderWidth

    // How far the blob's smooth-min reaches out past the card's own box. Only used
    // to size the underline erase — the fillet itself is drawn by the shader now.
    readonly property int filletRadius: Morph.available ? Math.round(Morph.smoothing)
                                                        : Tokens.radiusSm

    // ── shown vs wanted ───────────────────────────────────────────────────────
    // `shown` is the Accordion's contentVisible — it goes false at the START of a
    // close and stays false across a sibling-to-sibling SWAP, because the swap
    // hides the card while the container resizes under it.
    //
    // `wanted` is whether a panel is meant to be open at all. The two differ for
    // exactly the 140ms of a close, and the card's BOX has to follow this one: the
    // blob lobe is bound to card.height, so a box that waits for the swap to finish
    // leaves an empty lobe sitting in the bar after the content has already gone.
    property bool wanted: dock.shown

    // ── Holding the card through a SWAP ───────────────────────────────────────
    // A swap (one panel replacing another in this slot) sets `shown` false, changes the content,
    // and sets it true again; the card used to fade out and back, scale to 0.96 and slide up
    // `slideDistance` and back, around the content change. With the cookie field in the card that
    // is two faults. The field blinked out and back, while the bar's layer (a separate window)
    // went on showing what had left the panel. And it was CUT inside the panel's real edges: the
    // card shrinks and rises while its box — the blob lobe — stays full size and merely resizes, so
    // the field, clipped to the card, was clipped to a smaller, higher rectangle than the panel
    // occupies. So while cookies are on, a card that has been open stays up (full opacity, full
    // size, in place) across a swap, and only its CONTENT changes (the Loader has its own fade).
    // `_open` is set once the card has been shown and cleared when the slot closes, so the FIRST
    // opening — which fades in after the box has grown — is unchanged, and so is a close.
    property bool _open: false
    onShownChanged:  if (dock.shown) dock._open = true
    onWantedChanged: if (!dock.wanted) dock._open = false
    readonly property bool holding: Config.panelCookies && dock.wanted && dock._open && !dock.shown

    // How far the card travels on its way in. Enough to read as motion, small
    // enough that the whole trip stays behind the bar strip.
    readonly property int slideDistance: Tokens.spacingXxl

    readonly property Item maskItem: card

    // The card's live box, for BlobBarLayer's matching BlobRect. Read up through
    // BarPanelDock and Bar.qml, which add their own offsets to reach window space.
    readonly property real cardX: card.x
    readonly property real cardY: card.y
    readonly property real cardW: card.width
    readonly property real cardH: card.height
    // How far the card has faded in, for the cookie field (Drift.setPanels): its pull on the field
    // around it comes and goes with the card's own cookies.
    readonly property real cardOpacity: card.opacity

    // Identity until the layer supplies one. Assigned, never bound the other way —
    // the blob computes it from the card's motion, so binding the card's geometry
    // back to it would close the loop.
    property matrix4x4 deformMatrix

    // ── The real content ──────────────────────────────────────────────────────
    // Declared BEFORE the blob Loader on purpose: QML constructs children in
    // declaration order, and the Loader's onLoaded assigns `card` by id.
    Item {
        id: reveal
        anchors.fill: parent
        clip: true

        Card {
            id: card

            anchors.left:             dock.edge === "left"   ? parent.left   : undefined
            anchors.right:            dock.edge === "right"  ? parent.right  : undefined
            anchors.horizontalCenter: dock.edge === "center" ? parent.horizontalCenter : undefined
            anchors.leftMargin:  dock.edgeInset
            anchors.rightMargin: dock.edgeInset

            width:  dock.cardWidth
            // Zero the moment the panel stops being wanted, not when the Accordion
            // gets around to clearing activeKey — see dock.wanted. The Loader stays
            // active across the fade, so the content is still there to fade OUT; it
            // is only the box that leaves early, and it clips.
            height: dock.wanted ? Math.min(dock.cardHeight, dock.maxHeight) : 0

            // The slide. Plain `y`, not an anchor with a margin: a Behavior cannot be
            // declared on a grouped property's member, and an anchor would be fighting
            // the animation for the same value anyway. The horizontal anchors below are
            // untouched — they set x, not y.
            //
            // ── An ENTRANCE gesture only ──────────────────────────────────────
            // It used to be `dock.shown ? 0 : -slideDistance`, which also slid the card
            // UP on the way out. `reveal` clips the card to the bar's edge, but the blob
            // lobe is a shader shape outside that clip and follows the card's raw y — so
            // on close the lobe travelled up PAST the border into the bar band, and the
            // smooth-min smeared it there instead of letting it retract to the edge and
            // stop. Resting at 0 whenever the panel is not wanted means a close is pure
            // collapse: the lobe shortens to nothing exactly at the bar's underside.
            //
            // A sibling SWAP still slides (wanted stays true across it), so the
            // out-and-back between two panels is unchanged.
            y: (dock.wanted && !dock.shown && !dock.holding) ? -dock.slideDistance : 0

            // Keyed on `wanted`, so a closing box uses the EXIT pair — 140ms and an
            // accelerating curve — and lands with the fade and the slide instead of
            // after them. It used to be Motion.emphasized/enter unconditionally:
            // 220ms of OutCubic, a DECELERATING curve on a departure, starting only
            // once the card was already invisible. The blob lobe inherits this box,
            // so what that actually looked like was the panel vanishing and then a
            // blank lump of bar material creeping shut behind it.
            // ── The box's own curve ───────────────────────────────────────────
            // Growing, this rides `emphasizedDecel` — the house spatial curve, which
            // sprints out of the gate and glides into rest — rather than the plain
            // OutCubic `surfaceEasing` hands out. This box IS the blob: its edge is
            // what the smooth-min stretches from, so the curve it moves on is the
            // curve the melt appears to have. OutCubic decelerates evenly and the
            // melt looked mechanical for it.
            //
            // Leaving keeps the accelerating exit curve. An exit that eased out would
            // be the panel hesitating on its way through a decision already made.
            //
            // ── Why `bezierCurve` is set before `type`, and never left undefined ──
            // `easing.bezierCurve` is a QList<double>; binding it to `undefined` on the
            // exit branch logged "Unable to assign [undefined] to QList<double>" on
            // every close. It stays a valid list on BOTH branches now — assigning a
            // list forces the curve to BezierSpline, so `type` is written AFTER it and
            // is what actually switches open↔close (measured: the type binding wins on
            // every change AND at construction when the list is assigned first; a plain
            // InCubic on the exit branch simply ignores the list).
            //
            // ── Off while a grip is held ──────────────────────────────────────
            // These animate the box TOWARD a new size over surfaceDuration. That is
            // right for an open, a close and a swap, and wrong for a drag: the card
            // would trail the pointer by a fifth of a second and keep moving after
            // the pointer stopped, which is the difference between dragging an
            // object and dragging an elastic band. Disabled for the duration of the
            // gesture so the box is exactly where the hand is, and re-enabled on
            // release so the next open still animates. (cardBody's `scale` Behavior
            // below is gated on the same flag, for the same reason.)
            //
            // ── Springy while a grip is held ──────────────────────────────────
            // Not disabled during a drag, and not left on the surface curve either.
            // Both were wrong in opposite directions: surfaceDuration made the card
            // trail the pointer by a fifth of a second and keep moving after it
            // stopped, and disabling the Behavior outright pinned the box exactly to
            // the pointer — correct, and completely inert.
            //
            // A SHORT SPRING is the middle. Motion.respond is brief enough that the
            // card still reads as attached to your hand, and Motion.spring carries
            // the 1.21 overshoot, so the box lags slightly while you pull and — on
            // release, when the last animation is finally allowed to finish — passes
            // its resting size and settles back. That settle is the wobble.
            //
            // It also gives the blob something to work with. With the box pinned to
            // the pointer, the card's velocity was the pointer's velocity and the
            // deform matrix had nothing of its own to say; springing the box hands
            // the smooth-min a real velocity signal, so the material squashes and
            // stretches around the drag instead of merely following it.
            //
            // Motion.respond already routes through Motion._d(), so a shell with
            // motion turned off gets 0 here and the old exact tracking back.
            Behavior on width  { NumberAnimation {
                                     duration: dock.resizing ? Motion.respond
                                                             : Motion.surfaceDuration(dock.wanted)
                                     easing.bezierCurve: dock.resizing ? Motion.spring
                                                                       : Motion.emphasizedDecel
                                     easing.type: (dock.resizing || dock.wanted) ? Easing.BezierSpline
                                                                                 : Motion.exitCurve } }
            Behavior on height { NumberAnimation {
                                     duration: dock.resizing ? Motion.respond
                                                             : Motion.surfaceDuration(dock.wanted)
                                     easing.bezierCurve: dock.resizing ? Motion.spring
                                                                       : Motion.emphasizedDecel
                                     easing.type: (dock.resizing || dock.wanted) ? Easing.BezierSpline
                                                                                 : Motion.exitCurve } }
            Behavior on y {
                NumberAnimation {
                    // Motion.spring IS caelestia's expressiveDefaultSpatial, control
                    // point for control point: [0.38, 1.21, 0.22, 1.0]. The 1.21 is
                    // the overshoot — the panel passes its resting place and settles
                    // back, which is what gives the blob a velocity reversal to
                    // spring against. OutCubic had none, so the deformation only ever
                    // pulled one way and the arrival read as a stop, not a landing.
                    duration: dock.shown ? Motion.spatial : Motion.exit
                    easing.bezierCurve: Motion.spring
                    easing.type: dock.shown ? Easing.BezierSpline : Motion.exitCurve
                }
            }

            // Blob-welded, every corner stays ROUND: the smooth-min bulges material
            // into the gap between this rounded box and the ring, and that bulge IS
            // the fillet. Squaring a corner there would give the blob a hard edge to
            // blend from and the join would read as a box pushed against a strip.
            // Without the blob, the old squaring is still right — a rounded corner
            // meeting a flush surface reads as two shapes stacked.
            topLeftRadius:  dock.blobWeld ? radius
                          : (dock.hugBar || (dock.hugFrame && dock.edge === "left"))  ? 0 : radius
            topRightRadius: dock.blobWeld ? radius
                          : (dock.hugBar || (dock.hugFrame && dock.edge === "right")) ? 0 : radius
            bottomLeftRadius:  dock.blobWeld ? radius : (dock.hugFrame && dock.edge === "left")  ? 0 : radius
            bottomRightRadius: dock.blobWeld ? radius : (dock.hugFrame && dock.edge === "right") ? 0 : radius

            // The ring's stroke, not a panel's. See dock.welded. `hoverFocus` off
            // with it: a welded lobe brightening its outline on hover would light up
            // one segment of what is meant to read as a single continuous ring.
            border.color: dock.lineColor
            border.width: dock.blobWeld ? 0 : dock.lineWidth
            hoverFocus:   !dock.welded
            // The shared cookie field behind the panel (Card.drift) — or, welded while the blob can draw
            // it, the blob's own material, fill and cookies alike (Card.blobMaterial).
            drift:      true
            blobMaterial: dock.blobWeld && Drift.inBlob
            // Welded to the bar along its top (anchored), and — a left or right panel — to the frame's
            // strip or the sidebar's face on its outer side: those edges carry the field on (see
            // DriftShapes.joins). A floating bar's panel joins nothing; its corners stay round.
            driftJoin:  (dock.hugBar ? "top" : "")
                        + (dock.hugFrame && dock.edge === "left"  ? " left"  : "")
                        + (dock.hugFrame && dock.edge === "right" ? " right" : "")
            // Same reasoning as the border above: a lobe of the ring casts no shadow
            // onto the ring. The shadow ROOM stays reserved either way — it also
            // positions the card, and giving it back would shift the weld.
            elevated:     !dock.blobWeld

            // The blob's spring deformation, applied to the real content. Same
            // wiring caelestia uses. `transformOrigin` below still governs the
            // scale-in; this rides on top of it.
            transform: Matrix4x4 { matrix: dock.deformMatrix }

            shown: dock.shown || dock.holding
            // Points at where the card comes from, so the growth reads as unfolding
            // out of the bar rather than inflating in place.
            transformOrigin: dock.edge === "left"  ? Item.TopLeft
                           : dock.edge === "right" ? Item.TopRight
                                                   : Item.Top

            // Natural size, scaled up to fill the card. NOT anchors.fill — that
            // would lay the content out at the ZOOMED size, which is the reflow this
            // avoids. Dividing the (already-zoomed) card box back down hands the
            // panel exactly the box it sized itself for, and `scale` does the rest.
            //
            // TopLeft origin because the box it must cover starts there; the card's
            // own `transformOrigin` (the edge it grows from) is a separate transform
            // on the card itself and is unaffected.
            //
            // Guarded against a zero divisor: contentZoom is clamped well above 0 by
            // Config, but a card whose zoom hasn't arrived yet would otherwise size
            // its content to Infinity for a frame.
            Item {
                id: cardBody
                // Off the LIVE scale, not off dock.contentZoom — see the Behavior
                // below. Reading the target while `scale` is mid-animation would
                // reintroduce exactly the mismatch that Behavior exists to remove,
                // just pointing the other way.
                width:  cardBody.scale > 0 ? card.width  / cardBody.scale : card.width
                height: cardBody.scale > 0 ? card.height / cardBody.scale : card.height
                transformOrigin: Item.TopLeft
                scale: dock.contentZoom

                // ── The content has to travel on the box's own curve ───────
                // `card.width`/`height` are animated by the Behaviors above, so a
                // zoom that changed while the panel is open — Settings → Bar →
                // Reset — would slide the BOX over surfaceDuration while the
                // content snapped to its new scale on the first frame. For that
                // whole animation the panel would be the wrong size inside its own
                // outline: content overhanging the card, or floating short of it.
                //
                // Same duration and same curve as the width/height pair, so the two
                // are the same motion rather than two that happen to end together.
                // `wanted` is true for every case this fires on (a live resize of an
                // open panel); a closed dock's zoom change is invisible either way.
                // The SAME duration and curve as the box above, including the
                // resizing branch. It has to be identical, not merely similar: the
                // content box is card.width / this scale, so if the two wobbled at
                // different rates that quotient would breathe and the content would
                // be relaid out a few pixels either way on every frame of the drag.
                // Matched, they cancel and the content simply rides the box.
                Behavior on scale {
                    NumberAnimation {
                        duration: dock.resizing ? Motion.respond
                                                : Motion.surfaceDuration(dock.wanted)
                        easing.bezierCurve: dock.resizing ? Motion.spring : Motion.emphasizedDecel
                        easing.type: (dock.resizing || dock.wanted) ? Easing.BezierSpline
                                                                    : Motion.exitCurve
                    }
                }
            }

            // ── Erasing the seam ──────────────────────────────────────────────────
            // Card's border is one Rectangle stroke on all four sides and can't drop a
            // single edge, so paint the fill over the stroke exactly where it
            // shouldn't be. Qt Quick insets a Rectangle's border rather than
            // straddling the edge, which is what lets these live inside the card.
            //
            // Only while the card draws that border itself. Welded to the blob (`blobWeld`) its
            // border is 0 — the blob strokes the merged silhouette — so there is nothing to erase,
            // and these are then a 1px OPAQUE line along the bar-facing and frame-facing edges, over
            // the cookies the blob draws: a divider exactly where two surfaces meet, cutting every
            // cookie that crosses from the bar (or the frame, or the sidebar) into the panel.
            // `underlineErase` below is gated the same way, for the same reason.
            Rectangle {
                visible: dock.hugBar && !dock.blobWeld
                width:  card.width
                height: Tokens.borderWidth
                color:  Colors.of(QsWindow.window).surface
            }
            Rectangle {
                visible: dock.hugFrame && dock.edge !== "center" && !dock.blobWeld
                x: dock.edge === "right" ? card.width - Tokens.borderWidth : 0
                width:  Tokens.borderWidth
                height: card.height
                color:  Colors.of(QsWindow.window).surface
            }

            // ── The resize grips ──────────────────────────────────────────────
            // Siblings of cardBody, NOT children of it: cardBody carries the zoom
            // scale, so a grip inside it would grow with the panel and a 1.5×
            // panel would have a 1.5× handle. In card coordinates it stays the
            // same size at every zoom, which is what a handle should do.
            //
            // Declared last, so it is above the panel's own content and wins the
            // press in the corner it occupies.
            Repeater {
                model: dock.gripCorners

                delegate: MouseArea {
                    id: grip

                    required property string modelData
                    readonly property bool isRight: grip.modelData === "right"

                    // Which way is BIGGER for this corner. A right-hand grip grows
                    // the card by moving right; a left-hand one by moving left.
                    readonly property real sx: (grip.isRight ? 1 : -1) * dock.gripGain

                    // Drag origin, in the DOCK's coordinates — a fixed frame. Using
                    // the grip's own coordinates would feed back: the grip moves as
                    // the card resizes, so every delta would be measured from a
                    // ruler the drag itself is dragging.
                    property real startX: 0
                    property real startY: 0
                    property real startZoom: 1
                    // The panel's natural (unzoomed) box, captured once at press.
                    property real w0: 1
                    property real h0: 1

                    width:  Tokens.iconLg + Tokens.spacingSm
                    height: grip.width
                    anchors.bottom: parent.bottom
                    anchors.left:   grip.isRight ? undefined : parent.left
                    anchors.right:  grip.isRight ? parent.right : undefined

                    hoverEnabled: true
                    cursorShape: grip.isRight ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    onPressed: mouse => {
                        // Right-click is the way back to 1.0 without hunting for
                        // the settings page — the same "the control that set it can
                        // unset it" shape the bar's own right-click toggles use.
                        if (mouse.button === Qt.RightButton) {
                            dock.resizeRequested(1)
                            return
                        }
                        const p = grip.mapToItem(dock, mouse.x, mouse.y)
                        grip.startX = p.x
                        grip.startY = p.y
                        grip.startZoom = dock.contentZoom
                        grip.w0 = dock.contentZoom > 0 ? dock.cardWidth  / dock.contentZoom : dock.cardWidth
                        grip.h0 = dock.contentZoom > 0 ? dock.cardHeight / dock.contentZoom : dock.cardHeight
                        dock.resizing = true
                    }

                    onPositionChanged: mouse => {
                        if (!dock.resizing || !(grip.w0 > 0) || !(grip.h0 > 0)) return
                        const p = grip.mapToItem(dock, mouse.x, mouse.y)
                        const dx = (p.x - grip.startX) * grip.sx
                        const dy = (p.y - grip.startY)

                        // One scalar out of a two-axis drag. Averaging what each
                        // axis asks for — rather than taking the larger, or using
                        // the vertical alone — is what makes the handle track the
                        // pointer diagonally: pull sideways and it grows, pull down
                        // and it grows, pull along the diagonal and it grows at the
                        // rate of both. The ratio is preserved regardless, because
                        // the result is a single multiplier.
                        const zw = (grip.w0 * grip.startZoom + dx) / grip.w0
                        const zh = (grip.h0 * grip.startZoom + dy) / grip.h0

                        // Clamped to the SCREEN as well as the preference range —
                        // BarPanelDock.zoomFor would cap the drawn size anyway, but
                        // an unclamped request keeps inflating a stored number that
                        // no longer moves anything, and you would then have to drag
                        // all of it back before the panel responded again.
                        const ceiling = Math.min(Config.panelZoomMax, dock.maxHeight / grip.h0)
                        const want = Math.max(Config.panelZoomMin,
                                              Math.min((zw + zh) / 2, ceiling))
                        dock.resizeRequested(want)
                    }

                    onReleased:  dock.resizing = false
                    onCanceled:  dock.resizing = false

                    // ── The handle ────────────────────────────────────────────
                    // Three dots in a corner cluster, not the two diagonal bars
                    // this started as. The bars read as a direction — an arrow
                    // pointing out of the corner — which says "drag away" and not
                    // "grab me", and hard parallel strokes are the one texture
                    // nothing else in this shell wears. Round dots are the same
                    // vocabulary as the blob, the pills and every radius here, and
                    // a dotted corner is the oldest unambiguous grip there is.
                    //
                    // A diagonal lattice: one dot in the corner, one above it, one
                    // beside it. Everything derives from the box, so the mark keeps
                    // its proportions if the grip size is ever retuned.
                    Item {
                        id: gripMark
                        anchors.fill: parent
                        anchors.margins: Tokens.spacingSm
                        // Maps the bottom-right cluster onto the bottom-LEFT corner
                        // for a left-hand grip. Rotating the whole mark rather than
                        // mirroring each dot keeps one set of positions.
                        rotation: grip.isRight ? 0 : 90
                        opacity: (grip.containsMouse || dock.resizing) ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation { duration: Motion.fast; easing.type: Motion.enter }
                        }

                        Repeater {
                            model: [{ i: 0, j: 0 }, { i: 0, j: 1 }, { i: 1, j: 0 }]

                            delegate: Rectangle {
                                required property var modelData
                                readonly property real step: gripMark.width / 3

                                width:  Math.max(2, Math.round(gripMark.width / 6))
                                height: width
                                radius: width / 2
                                // Brightens under the hand, so the grip confirms it
                                // has the drag rather than only the cursor shape
                                // saying so.
                                color: dock.resizing ? Colors.of(QsWindow.window).fgMuted : Colors.of(QsWindow.window).fgDim
                                Behavior on color {
                                    ColorAnimation { duration: Motion.fast }
                                }

                                x: gripMark.width  - width  - modelData.i * step
                                y: gripMark.height - height - modelData.j * step
                            }
                        }
                    }
                }
            }
        }

    }   // reveal

    // ── Erasing the frame's underline ─────────────────────────────────────────
    // Outside `reveal`, because the whole point is to paint ABOVE y=0 — into the
    // bar strip, over a stroke drawn by BarFrameEdge. See the header.
    //
    // The colour is the BAR SURFACE's own recipe, not Colors.frameFill: what sits
    // behind that stroke at this y is the bar's fill (the bar is drawn over the
    // frame's), so matching the frame instead would swap one visible patch for
    // another.
    //
    // Overshoots the stroke by a couple of px in both directions. Upward that is
    // bar fill painted over bar fill and costs nothing; downward it lands on the
    // card's own top border, which `hugBar` has already erased.
    Rectangle {
        id: underlineErase
        // Only when the blob is NOT drawing the outline. With it, the ring's stroke
        // is part of the merged silhouette and breaks at the weld on its own — there
        // is nothing left to erase, and erasing would punch a hole in it.
        visible: dock.hugBar && card.height > 0 && !dock.blobWeld
        opacity: card.opacity
        // ── Exactly the blob's own width, and no wider ────────────────────────
        // This used to clear the whole blend radius (20px past each edge). The blob
        // cannot stroke that zone — it is fused there, so the merged silhouette has
        // no surface and the shader draws nothing — so all the extra erase did was
        // leave the outline broken: measured, the underline stopped at x=88 and the
        // panel's outline began at x=107, a 20px gap with nothing in it. That gap
        // IS the choppy corner.
        //
        // Held to the blob rect's own extent (the card grown by one border width,
        // see BlobBarLayer.grow) the underline now runs right up to where the blob's
        // outline takes over, and the two butt instead of leaving a hole.
        x:      card.x     - dock.lineWidth
        width:  card.width + dock.lineWidth * 2
        // Measured: with barSurfaceHeight 50 the stroke lands on row 51, and the
        // old -4/height-5 covered rows 46..50 — one pixel short, so the fillet arc
        // butted against a rule that was still there and the join read as unblended.
        // Spans the boundary generously in both directions instead of trying to
        // predict which side of it a Shape stroke rounds onto. Downward it lands on
        // the card's own already-erased top border.
        y:      -(Config.frameBorderWidth * 2 + 1)
        height: Config.frameBorderWidth * 3 + 3
        color:  Colors.of(QsWindow.window).fade(Colors.of(QsWindow.window).surfaceFor(Tokens.elevationBar), Config.barOpacity)
    }

}
