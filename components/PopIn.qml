import QtQuick
import "../config"

// ── PopIn ─────────────────────────────────────────────────────────────────────
// A spring entrance for ONE item of a set: it rises from 90% size and fades up, a few beats
// after the item before it (`index`, capped so a long list does not queue). Non-visual, like
// ViewEnter and SwapFade — it owns no item, it hands the caller three numbers to bind:
//
//     PopIn { id: pop; active: pane.visible; index: card.index }
//     opacity: pop.opacity
//     scale:   card.lean * pop.scale          // the caller's own scale keeps its say
//
// Why not `target:` like ViewEnter: the wallpaper tiles, the presets cards and the editor's
// swatches ALL already drive `scale` themselves (a lean toward the pointer, a dip on a press),
// and two writers on one property is the chase Motion warns about. So the entrance is a value
// to fold in, not a property it takes over.
//
// ── Plays every time `active` turns true ──────────────────────────────────────
// Not once when the delegates were built behind a hidden page: it snaps back to 0 without
// animating (the item is hidden when it does) and springs up from there. Motion off: it sits at 1.
// ─────────────────────────────────────────────────────────────────────────────
QtObject {
    id: root

    property bool active: false
    property int  index:  0
    property int  cap:    10
    // ms between neighbours.
    property real step:   Motion.stagger * 1.5
    // ms before the FIRST one, on top of the stagger — a whole set held back (a panel waiting out
    // its dock's opening pause).
    property int  delay:  0

    readonly property real arrive:  root._arrive
    readonly property real opacity: Math.min(1, root._arrive * 1.6)
    readonly property real scale:   0.9 + 0.1 * root._arrive

    property real _arrive: Config.motionEnabled ? 0 : 1
    property bool _snap: false
    Behavior on _arrive {
        enabled: Config.motionEnabled && !root._snap
        SpringAnimation { spring: 2.8; damping: 0.34; epsilon: 0.005 }
    }

    property Timer _delay: Timer {
        interval: root.delay + Math.min(root.index, root.cap) * root.step
        onTriggered: root._arrive = 1
    }

    function replay() {
        if (!Config.motionEnabled) return
        root._snap = true
        root._arrive = 0
        root._snap = false
        root._delay.restart()
    }

    onActiveChanged: if (root.active) root.replay()
    Component.onCompleted: if (root.active) root.replay()
}
