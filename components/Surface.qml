import QtQuick
import Quickshell
import "../config"

// ── Surface ───────────────────────────────────────────────────────────────────
// Every filled, bordered, rounded thing in the shell is one of these: the bar
// pill, the panel card, the dock, a nested control, a popup menu.
//
// It exists so that "what does a surface look like at this depth" is answered
// once. Before, each widget wrote its own `color: Theme.bg; border.color:
// Theme.barBorder; border.width: 1; radius: <some number>` — which is how the
// dock ended up needing a bespoke `nestedPillBorder` token to fix the fact that
// a border tuned for sitting on a wallpaper is invisible when sitting on another
// surface. Elevation encodes that: ask for the right depth and the border and
// fill follow.
//
//   elevation 0 (Bar)     the bar/dock, sitting on the desktop
//   elevation 1 (Card)    a panel floating above the bar
//   elevation 2 (Nested)  a control inside a card — stronger border, lifted fill
//   elevation 3 (Popup)   a menu floating above a card
//
// `focused` drives the accent outline. That's the `focus` palette role's whole
// job: hovered, open, or keyboard-selected — "this is the thing you're pointing
// at". It is never the fill; a filled accent means *interactive/active*, which
// is `primary`.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property int  elevation:  Tokens.elevationBar
    property bool focused:    false
    property bool squareMode: false          // barShape — collapses all corners
    // A fused bar pill: its top edge merges into the screen frame's band, so the
    // top corners must be square — a rounded top corner would curve away from the
    // band and open a gap in the silhouette FrameFusion's flares close.
    property bool squareTop:  false
    // A pill whose outer side runs INTO the frame's side strip: that edge stops
    // being an edge, so its corners must be square or the fill curves away from
    // the strip and opens a notch at the screen corner.
    property bool squareLeft:   false
    property bool squareRight:  false
    // The bottom edge runs into the frame's bottom strip (the docked settings
    // panel). Squares both bottom corners.
    property bool squareBottom: false

    // Surfaces at rest use the elevation's radius; a control (rather than a
    // container) can opt into the tighter pill corner.
    property int  cornerRadius: elevation >= Tokens.elevationCard
                                    ? Tokens.radiusCard
                                    : Tokens.radiusPill

    // ── Translucency lives in the FILL, not in `opacity` ──────────────────────
    // Item opacity fades the border too, so a pill at 0.97 drew its outline at
    // 0.22 × 0.97 while the screen frame — loose paths, no item opacity — drew the
    // same role at full strength, and the two refused to match no matter which
    // number was tuned. Fading the fill alone keeps the edge crisp at every
    // opacity and leaves `opacity` free for what it's actually for: cross-fades
    // (BarGroup/BarRegion swap pills with it when barMode changes).
    property real fillOpacity: 1.0

    // ── The ITEM's own opacity — a second, separate multiplier ────────────────
    // Defaults to the shell-wide `Tokens.surfaceOpacity` (Settings → Appearance),
    // same as always: a card, popup or panel that never set `fillOpacity` either
    // is untouched by this.
    //
    // A caller that DOES drive its own translucency through `fillOpacity` (the
    // bar's pills, via `Config.barOpacity`) needs this at a flat 1.0, or the two
    // multiply — `fillOpacity` at 100% still rendered at
    // `Tokens.surfaceOpacity` (≈0.97, a DIFFERENT slider on a DIFFERENT settings
    // page), so the Bar page's own "Opacity" control could never actually reach
    // opaque. BarGroup/BarRegion/the unified bar pass 1.0 for exactly this reason.
    property real itemOpacity: Tokens.surfaceOpacity

    // The stroke width. Defaults to the shell-wide hairline; the bar pills pass
    // Tokens.borderChrome so their edge matches the screen frame and the
    // compositor's window borders.
    property real borderWidth: Tokens.borderWidth

    // ── Does this surface cast at all ─────────────────────────────────────────
    // Elevation already answers "how far" — this answers "at all", which is a
    // different question and not one `elevation` can carry. A surface WELDED into
    // another piece of material is still at the bar's depth in every other respect
    // (same fill, same border, same corner language); it simply has nothing to cast
    // onto, because the thing below it is itself.
    //
    // The case, and the reason this exists: an anchored bar is continuous with the
    // screen frame, and BarFrameEdge draws the frame's stubs and concave corners
    // BEHIND it (`z: -1`). So the bar threw a 5px shadow straight down onto the
    // ring it had just merged with — a soft smudge over both top corners, in the
    // one place the join is supposed to be invisible. The ring's other strips are
    // plain rectangles and cast nothing, so the bar was also the only part of the
    // ring shading the rest of it.
    //
    // Default true: every existing caller is a surface that really is floating
    // above something.
    property bool castsShadow: true

    // ── An optional wash over the elevation's own fill ────────────────────────
    // For surfaces that need to be told apart from an identical neighbour rather than
    // lifted off it — the launcher's chat pills, where "who said this" is the whole
    // distinction. Elevation still chooses the base; this only tints it, so a tinted
    // surface stays in the same material family as an untinted one.
    property color tint: "transparent"
    property real  tintAmount: 0

    color: Colors.of(QsWindow.window).fade(root.tintAmount > 0
                         ? Qt.tint(Colors.of(QsWindow.window).surfaceFor(elevation),
                                   Colors.of(QsWindow.window).alpha(root.tint, root.tintAmount))
                         : Colors.of(QsWindow.window).surfaceFor(elevation),
                       fillOpacity)
    opacity:      root.itemOpacity
    radius:       Tokens.corner(squareMode, cornerRadius)
    topLeftRadius:     (squareTop    || squareLeft)  ? 0 : radius
    topRightRadius:    (squareTop    || squareRight) ? 0 : radius
    bottomLeftRadius:  (squareBottom || squareLeft)  ? 0 : radius
    bottomRightRadius: (squareBottom || squareRight) ? 0 : radius
    border.width: root.borderWidth
    // Overridable as a whole, so a caller that needs a specific stroke (the desktop
    // tiles want the shell's shared one, not an elevation-derived one) replaces the
    // binding rather than fighting `focused`. Everything that doesn't override still
    // gets exactly the old behaviour.
    property color borderColor: focused ? Colors.of(QsWindow.window).outlineFocus : Colors.of(QsWindow.window).outlineFor(elevation)
    border.color: root.borderColor

    // ── The cast shadow ───────────────────────────────────────────────────────
    // `z: -1` puts this behind this Rectangle's OWN fill, not merely behind later
    // siblings — verified on Qt 6.11.1, see Elevation.qml. That is what lets the
    // shadow live here instead of being an explicit earlier sibling at every one
    // of the ~113 call sites.
    //
    // Loader-gated rather than `visible: false`, for the reason IconButton gates
    // its Image: a Nested surface (dp 0 by design) or a shell with
    // Config.shadowScale at 0 should allocate nothing at all, and there are a lot
    // of these.
    //
    // ── If this Surface sets `clip: true`, use SurfaceShadow instead ──────────
    // A clipping Surface clips this child away with everything else, and the only
    // symptom is a popup that quietly has no shadow while every other surface does.
    // Six sites hit that (the launcher popup, the cheatsheet, the old emoji picker, the
    // update panel, the screenshot toast, the now-playing card) — they declare a
    // `SurfaceShadow { surface: <id> }` as an earlier SIBLING instead, which is
    // outside the clip. See SurfaceShadow.qml.
    //
    // All FOUR corner radii are mirrored, not just `radius`. A fused bar pill has
    // square top corners so it can merge into the frame's band, and a shadow with
    // round ones would bloom out above the band FrameFusion just welded shut —
    // reopening, in shadow, exactly the seam that machinery exists to close.
    Loader {
        z: -1
        anchors.fill: parent
        active: root.castsShadow && Tokens.shadowDp(root.elevation) > 0

        sourceComponent: Elevation {
            elevation:         root.elevation
            radius:            root.radius
            topLeftRadius:     root.topLeftRadius
            topRightRadius:    root.topRightRadius
            bottomLeftRadius:  root.bottomLeftRadius
            bottomRightRadius: root.bottomRightRadius
        }
    }

    // No Behavior on the top radii: they track `radius`, which is already easing —
    // easing a target that is itself easing is the chase BarGroup warns about.
    // The squareTop flip itself snaps, which is right: it happens alongside the
    // pill re-seating against the band, not as an independent gesture.
    Behavior on radius       { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
    Behavior on color        { ColorAnimation  { duration: Motion.respond } }
    Behavior on border.color { ColorAnimation  { duration: Motion.respond } }
}
