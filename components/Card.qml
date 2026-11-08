import QtQuick
import Quickshell
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
    // A cast shadow separates a FLOATING surface from what is behind it. A card
    // welded into the bar/frame mass is not floating — it is a lobe of the same
    // material — and a shadow there draws an outline around the join the blob just
    // spent its whole existence dissolving. See BarDock.blobWeld.
    property bool elevated: true

    // The shared cookie field behind this panel's content (services/Drift,
    // components/DriftShapes), with its soft top edge and the seam along it. Opt-in: the
    // bar's and sidebar's panels turn it on; a card that is not a panel (the OSD's) leaves
    // it off.
    property bool drift: false
    // …and which edge of this card is welded to the surface the field carries on across ("top": the bar;
    // a sidebar panel says its sidebar's edge). See DriftShapes.joins.
    property string driftJoin: "top"
    // The blob is this card's material (a welded card while the blob draws the cookie field, see
    // Drift.inBlob): it paints the fill — the same colour — and the cookies in it, exactly to the
    // merged outline. So the card paints neither: only its content, over the blob.
    property bool blobMaterial: false

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

    // NOTE: `clip` is on contentArea below, NOT here. It used to be on this root,
    // which silently clipped away the negative-z shadow child and left every panel
    // in the shell flat. Moving it down one level is behaviour-identical for the
    // content — contentArea fills the root exactly, and `clip` is a rectangular
    // bounding-box clip either way, never the rounded corners (the same thing
    // OverviewLyrics documents). Putting it back here would cost the panels their
    // shadows with no other symptom.

    color:        root.blobMaterial ? "transparent" : Colors.of(QsWindow.window).surface
    border.width: Tokens.borderWidth
    border.color: (hoverFocus && cardHover.hovered) ? Colors.of(QsWindow.window).outlineFocus : Colors.of(QsWindow.window).outline

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

    // The cast shadow. Same z:-1 mechanism as Surface — see Elevation.qml for why
    // that works and what it would look like if it stopped.
    //
    // A Card is what `elevationCard` was named for: a panel floating above the bar.
    // It does not go through Surface (it is its own Rectangle, because its height
    // is animated by its owner rather than anchored), so it needs its own.
    Loader {
        z: -1
        anchors.fill: parent
        active: root.elevated && Tokens.shadowDp(Tokens.elevationCard) > 0

        sourceComponent: Elevation {
            elevation: Tokens.elevationCard
            radius:    root.radius
        }
    }

    Item {
        id: contentArea
        anchors.fill: parent
        clip: true

        // First, so it paints under everything a panel puts in the default slot.
        DriftShapes {
            visible: root.drift && !root.blobMaterial
            anchors.fill: parent
            radius: root.radius
            joins: root.driftJoin
        }
    }
}
