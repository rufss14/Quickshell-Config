import QtQuick

// ── PeakCap ───────────────────────────────────────────────────────────────────
// A spectrum cap's height (2026-10-31, CavaBG's caps): up with its bar at once, a hold,
// then a fall that takes `fallMs` from `full` — less from lower, so every cap lands in about
// the same time. Moves only while `armed`; the caller draws the cap at `peak`.
// (An inline component in CavaBG first: "PeakCap is not a type" on every load, so a file.)
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool armed: false
    property real level: 2
    property real full: 1
    property int  hold: 0
    property int  fallMs: 0
    property real peak: 2

    onLevelChanged: {
        if (!root.armed || root.level < root.peak) return
        fall.stop()
        root.peak = root.level
        fall.restart()
    }

    SequentialAnimation {
        id: fall
        PauseAnimation { duration: root.hold }
        NumberAnimation {
            target: root
            property: "peak"
            to: 2
            duration: Math.max(1, root.fallMs * root.peak / Math.max(1, root.full))
            easing.type: Easing.InQuad
        }
    }
}
