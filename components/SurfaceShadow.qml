import QtQuick
import "../config"

// ── SurfaceShadow ─────────────────────────────────────────────────────────────
// The shadow for a Surface that CLIPS.
//
// Surface normally draws its own shadow as a negative-z child (see Surface.qml).
// A Surface with `clip: true` clips that child away along with everything else,
// so the six popups and cards that clip their content — to keep it inside their
// own corners — silently lost their shadow and nothing said so. They are also
// exactly the surfaces that most need one: popups, floating above everything.
//
// So for those, the shadow becomes an explicit SIBLING declared before the
// Surface, which puts it outside the clip and behind the fill. This exists so
// that is seven lines in one place rather than seven lines copied six times and
// drifting — the fate of every other recipe in this repo that got copied.
//
// Usage — declare it immediately BEFORE the Surface it belongs to:
//
//     SurfaceShadow { surface: card }
//     Surface { id: card; clip: true; ... }
//
// Everything else is mirrored automatically, including the enter/exit transform:
// these cards fade and scale as they arrive, and a shadow that did not follow
// would hang in the air at full size while its card shrank away.
// ─────────────────────────────────────────────────────────────────────────────
Elevation {
    id: root

    // `var`, not `Item`: the target is a Surface, and the properties read below
    // (elevation, radius) live on Surface rather than on Item.
    property var surface: null

    anchors.fill: root.surface

    // Assignments, never redeclarations — Elevation already declares `elevation`
    // and RectangularShadow declares `radius`. Redeclaring either would be
    // "Property value set multiple times", a hard load failure of the whole file.
    elevation: root.surface?.elevation ?? Tokens.elevationCard

    // Takes the radius the Surface actually RESOLVED, so squareMode and the
    // per-corner squaring come along without this having to know about either.
    radius:            root.surface?.radius            ?? 0
    topLeftRadius:     root.surface?.topLeftRadius     ?? root.radius
    topRightRadius:    root.surface?.topRightRadius    ?? root.radius
    bottomLeftRadius:  root.surface?.bottomLeftRadius  ?? root.radius
    bottomRightRadius: root.surface?.bottomRightRadius ?? root.radius

    // No Behaviors here: every one of these mirrors a value that is ALREADY being
    // animated on the Surface. Easing them again would be the chase Motion.qml
    // opens with — a value easing toward a target that is itself easing.
    opacity:         root.surface?.opacity         ?? 1.0
    scale:           root.surface?.scale           ?? 1.0
    transformOrigin: root.surface?.transformOrigin ?? Item.Center
    visible:         (root.surface?.visible ?? true) && root.dp > 0
}
