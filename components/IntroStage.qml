import QtQuick
import "../state"

// ── IntroStage ────────────────────────────────────────────────────────────────
// Puts a whole window's content on the entrance (state/Intro), without that window's
// file being restructured around it.
//
// Declare it as a direct child of a PanelWindow. When it completes, it ADOPTS every
// other child of the window's content item — in their stacking order, so nothing
// changes places — into `inner`, an item exactly the window's size at its origin. So
// for anything adopted, `parent` is still a window-sized item at (0, 0): anchors and
// coordinates resolve exactly as before. What the stage adds on top:
//
//   front   px from the window's top that are shown; the rest is clipped. A moving
//           front is how the frame "traces" down from the bar.
//   lift    px the content sits ABOVE its rest; negative = below (a rise).
//   fade    the content's opacity.
//
// The clip is two items on purpose: `stage` (the clip) changes height, `inner` never
// does. Clipping by resizing the content's own parent would resize everything anchored
// to it — the blob layer, the frame's Shapes, the dock — every frame of the entrance.
//
// Once the entrance is over it is inert: clip off, front at full
// height, lift 0, fade 1. Children created later — a Repeater refilling, a Loader —
// land in `inner` by themselves, since their parent was adopted with them.
//
// Why not one wrapper Item written into the file: Bar.qml interleaves ~40 root
// properties and functions with its children, and a wrapper would have moved those
// onto the wrapper. Why not a layer + MultiEffect mask: it renders the window offscreen
// for the whole entrance, and a scissor clip is free.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: stage

    property real front: stage.parent ? stage.parent.height : 0
    property real lift: 0
    property real fade: 1

    x: 0
    y: 0
    width:  stage.parent ? stage.parent.width : 0
    height: Math.max(0, Math.min(stage.front, stage.parent ? stage.parent.height : 0))
    // Only while the front is actually short of the window: a stage that only lifts or
    // fades (the widget layer's rise) must not shave its bottom edge as content moves.
    clip: Intro.playing && stage.height < (stage.parent ? stage.parent.height : 0)

    Item {
        id: inner
        width:  stage.parent ? stage.parent.width : 0
        height: stage.parent ? stage.parent.height : 0
        y: -stage.lift
        opacity: stage.fade
    }

    Component.onCompleted: {
        const host = stage.parent
        if (!host) return
        const kids = []
        for (let i = 0; i < host.children.length; i++)
            if (host.children[i] !== stage) kids.push(host.children[i])
        for (const k of kids) k.parent = inner
    }
}
