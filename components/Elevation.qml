import QtQuick
import Quickshell
import QtQuick.Effects
import "../config"

// ── Elevation ─────────────────────────────────────────────────────────────────
// The shadow a surface casts. One of these sits behind every Surface and Card
// that is actually floating above something.
//
// It takes the shell's SEMANTIC elevation (elevationBar/Card/Nested/Popup), not
// Material 3's dp level — Tokens.shadowDp is the translation, and it is the only
// place that knows a card casts further than a bar pill and a nested control
// casts nothing at all. A caller passes what the surface IS; it never picks a
// blur radius.
//
// ── Why this is a component and not four properties on Surface ────────────────
// RectangularShadow is a real scene-graph item with its own geometry, and gating
// it behind a Loader (which Surface does) means a Nested surface or a shell with
// Config.shadowScale 0 allocates nothing whatsoever. Inlining it would leave the
// item constructed-but-invisible ~113 times.
//
// ── Verified before this was written ──────────────────────────────────────────
// A child with `z: -1` paints behind its PARENT'S OWN FILL, not merely behind
// later siblings — measured offscreen on Qt 6.11.1: an opaque parent over an
// oversized negative-z child showed the parent's fill at the centre and the
// child only where it stuck out. That is what lets the shadow live INSIDE
// Surface rather than having to be an explicit earlier sibling at every call
// site. If that ever stops holding, the symptom is a black rectangle painted
// over every surface in the shell.
// ─────────────────────────────────────────────────────────────────────────────
RectangularShadow {
    id: root

    property int  elevation: Tokens.elevationCard
    property real dp:        Tokens.shadowDp(root.elevation)

    color:  Colors.of(QsWindow.window).shadowCast
    blur:   Tokens.shadowBlur(root.dp)
    spread: Tokens.shadowSpread(root.dp)
    offset: Qt.vector2d(0, Tokens.shadowOffsetY(root.dp))

    // Not `cached`. Caching bakes the shadow to a texture, which is right for a
    // static one and wrong for anything whose geometry moves — and Surface.radius
    // eases on every barShape flip, while dp eases whenever shadowScale moves.
    // A cached shadow would hold the old corner through the whole animation.

    visible: root.dp > 0

    // Behavior on `dp` ALONE. blur/spread/offset are pure functions of it, so
    // easing the input keeps all three consistent frame by frame; easing them
    // separately would be three animations chasing one target — the exact
    // "easing toward a target that is itself easing" failure Motion.qml opens with.
    Behavior on dp    { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
    Behavior on color { ColorAnimation  { duration: Motion.respond } }
}
