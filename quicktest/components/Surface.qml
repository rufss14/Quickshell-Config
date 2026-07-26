import QtQuick
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
    property bool squareLeft:  false
    property bool squareRight: false

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

    // The stroke width. Defaults to the shell-wide hairline; the bar pills pass
    // Tokens.borderChrome so their edge matches the screen frame and the
    // compositor's window borders.
    property real borderWidth: Tokens.borderWidth

    color:        Colors.fade(Colors.surfaceFor(elevation), fillOpacity)
    opacity:      Tokens.surfaceOpacity
    radius:       Tokens.corner(squareMode, cornerRadius)
    topLeftRadius:     (squareTop || squareLeft)  ? 0 : radius
    topRightRadius:    (squareTop || squareRight) ? 0 : radius
    bottomLeftRadius:  squareLeft  ? 0 : radius
    bottomRightRadius: squareRight ? 0 : radius
    border.width: root.borderWidth
    border.color: focused ? Colors.outlineFocus : Colors.outlineFor(elevation)

    // ── Glass ─────────────────────────────────────────────────────────────────
    // Opt-in, off everywhere by default. On, the surface gains GlassOverlay's lit
    // treatment: graded body, sheen, rim. Loaded rather than declared-and-hidden,
    // because every surface in the shell is one of these and most will never want it —
    // an inactive Loader costs nothing, three always-built Rectangles per surface would.
    //
    // The overlay inherits the corner radii INCLUDING the squared-off ones, or glass
    // drawn at a uniform radius over a fused pill misses its square corners and paints
    // a bright arc across them.
    property bool glass: false

    Loader {
        anchors.fill: parent
        active: root.glass
        sourceComponent: GlassOverlay {
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
