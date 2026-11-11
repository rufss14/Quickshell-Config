import QtQuick
import Quickshell
import "../../config"
import "../../services"
import "../../components"
import "../../state"

// ── SidePill ──────────────────────────────────────────────────────────────────
// A sidebar surface in the top bar's own recipe, so the two can't drift apart:
// Bar › Style drives both — roundness, opacity, border, the inner pill, the square
// shape. Two roles, each the top bar's equivalent:
//
//   "bar"    the sidebar itself                       ← Bar.qml's unified surface
//   "inner"  the lighter pill round what stands on it ← BarGroup's inner pill
//
// ── Against the edge ──────────────────────────────────────────────────────────
// The "bar" is one of three things there, as the top bar is:
//   welded    a lobe of the frame, drawn by the blob: the frame's own fill and no
//             outline or shadow of its own. The blob draws one continuous stroke
//             round ring, neck and lobe (DockHost says why a card's can't agree),
//             and its smooth-min is the fillet, so every corner stays round.
//   flush     anchored with nothing to weld it (no plugin, or no frame): square
//             where it meets a strip or the screen — the edge side always, and the
//             ends the host says (`squareStart`/`squareEnd`, along the edge). With no
//             frame at all, the edge side's border is pushed past the screen's edge
//             and clipped away (`bleed`) — the top bar's own trick, or it draws a
//             bright rule down the very edge of the display.
//   floating  the top bar floating (barAnchored off): round all round, outlined,
//             casting its shadow.
// An "inner" pill touches no edge, so it's none of those.
//
// ── The top bar's own inner pill ─────────────────────────────────────────────
// Exactly BarGroup's: the nested surface, borderless, the bar's roundness and opacity.
// It was once pulled halfway back toward the bar (`softness`, 2026-10-02), which made
// the sidebar's pills a different colour from the top bar's; that went at the user's
// ask (2026-10-17: "looks nothing like the top bar"). Don't tint it again.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string role: "inner"
    // The screen edge the sidebar stands on: "left" | "right" | "bottom".
    property string edge: "left"
    // A lobe of the frame (Morph + frame + anchored — the hosts' `blobWeld`).
    property bool welded: false
    // Flush only: square at the near / far end along the edge too.
    property bool squareStart: false
    property bool squareEnd: false
    // The pointer is on it: the outline takes the focus tint, as the bar's does.
    property bool focused: false

    readonly property bool inner: root.role === "inner"
    readonly property bool flush: !root.inner && !root.welded && Config.barAnchored
    readonly property bool vertical: root.edge !== "bottom"
    readonly property real bleed: root.flush && !Config.screenFrame ? Config.barBorderWidth : 0

    Surface {
        id: surface

        x: root.edge === "left" ? -root.bleed : 0
        width:  root.width  + (root.vertical ? root.bleed : 0)
        height: root.height + (root.vertical ? 0 : root.bleed)

        elevation:    root.inner ? Tokens.elevationNested : Tokens.elevationBar
        squareMode:   Config.barShape
        cornerRadius: Config.sideRoundness
        squareLeft:   root.flush && (root.edge === "left" || (!root.vertical && root.squareStart))
        squareRight:  root.flush && (root.edge === "right" || (!root.vertical && root.squareEnd))
        squareTop:    root.flush && root.vertical && root.squareStart
        squareBottom: root.flush && (root.edge === "bottom" || (root.vertical && root.squareEnd))
        borderWidth:  root.inner || root.welded ? 0 : Config.barBorderWidth
        castsShadow:  !root.inner && !root.welded && !Config.barAnchored
        focused:      root.focused && !root.inner
        fillOpacity:  Tokens.sideOpacity
        // BarGroup's inner pill keeps the item's default; the bar drives their translucency through the fill alone (Surface.itemOpacity).
        itemOpacity:  root.inner ? Tokens.surfaceOpacity : 1.0
        // Welded, the blob's own fill, so the card and the lobe under it are one.
        // Welded while the blob draws the cookie field (Drift.inBlob), the blob IS this fill — the same
        // frameFill, with the cookies in it — so painting it again would only hide them.
        color: root.welded && Drift.inBlob ? "transparent"
             : root.welded ? Colors.of(QsWindow.window).frameFill
             :               Colors.of(QsWindow.window).fade(Colors.of(QsWindow.window).surfaceFor(surface.elevation), surface.fillOpacity)
    }
}
