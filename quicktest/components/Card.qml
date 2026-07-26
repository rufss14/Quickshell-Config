import QtQuick
import "../config"

// ── Card ──────────────────────────────────────────────────────────────────────
// A panel surface that fades and scales in and out.
//
// OverlayRoot contained six of these written out by hand — identical 20-line
// blocks of radius/clip/color/border/opacity/scale/visible/z plus three
// Behaviors, differing only in which module they wrapped and which corner they
// scaled from. Six copies of a recipe is six chances for one of them to be
// subtly off, and two of them already were (the left panel's cards scaled from
// TopLeft, the right panel's from Top and TopRight — inconsistently).
//
// Scale origin should point at where the card *comes from*: a card anchored to
// the top-left of the screen grows out of its top-left corner, so the motion
// reads as the panel unfolding from its button rather than inflating in place.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    // The card is shown when its owner says so. It stays in the scene while
    // fading out, then removes itself — hence `visible` tracking opacity rather
    // than `shown` directly.
    property bool shown: false
    property bool hoverFocus: true    // outline the card while the pointer is on it

    default property alias content: contentArea.data

    // NOTE: the Card does NOT anchor-fill its window, and its owner animates the
    // Card's HEIGHT rather than the window's.
    //
    // Animating a PanelWindow's implicitHeight animates the actual Wayland
    // surface: a new buffer and a compositor roundtrip on every frame of the
    // animation. That is stuttery no matter how clean the QML above it is, and it
    // was the real cause of the panel jitter — not the QML bindings I fixed first.
    //
    // So the window is a fixed size and this card grows inside it, which is a pure
    // GPU-side transform with no surface resize at all. The window masks its input
    // region to the card (see PanelHost) so the oversized transparent window
    // doesn't swallow clicks.
    radius: Tokens.radiusCard
    clip:   true

    color:        Colors.surface
    border.width: Tokens.borderWidth
    border.color: (hoverFocus && cardHover.hovered) ? Colors.outlineFocus : Colors.outline

    opacity: shown ? 1.0 : 0.0
    scale:   shown ? 1.0 : 0.96
    visible: opacity > 0.005
    z:       shown ? 1 : 0

    // Enter and exit differ in BOTH duration and curve — a surface arriving
    // decelerates into place, a surface leaving accelerates away. Motion's
    // helpers keep the pair in sync so a card can't end up soft on the way in
    // and soft on the way out (which reads as sluggish).
    Behavior on opacity {
        NumberAnimation {
            duration:    Motion.surfaceDuration(root.shown)
            easing.type: Motion.surfaceEasing(root.shown)
        }
    }
    Behavior on scale {
        NumberAnimation {
            duration:    Motion.surfaceDuration(root.shown)
            easing.type: Motion.surfaceEasing(root.shown)
        }
    }
    Behavior on border.color { ColorAnimation { duration: Motion.respond } }

    HoverHandler { id: cardHover }

    Item {
        id: contentArea
        anchors.fill: parent
    }
}
