import QtQuick
import Quickshell
import "../config"

// ── TypingDots ────────────────────────────────────────────────────────────────
// Three dots rising in sequence — the "still writing" cue every chat uses, because
// it says something a spinner does not: that a REPLY is coming, not that the
// application is busy.
//
// Built rather than played from a gif. A gif would have to be vendored (and the ones
// people mean are somebody's brand asset), it would carry its own colours into a
// wallpaper-derived palette, and it could not follow `Motion.motionEnabled`. Three
// animated dots cost nothing and are the shell's own colour by construction.
//
// The stagger is what makes it read as typing: one phase per dot, a third of the
// cycle apart, so the motion travels left to right instead of pulsing as a block.
// ─────────────────────────────────────────────────────────────────────────────
Row {
    id: root

    property bool running: false
    property color tint: Colors.of(QsWindow.window).fgDim
    property int dotSize: 5

    spacing: root.dotSize - 1
    opacity: root.running ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Motion.standard } }

    Repeater {
        model: 3
        delegate: Rectangle {
            id: dot
            required property int index
            width: root.dotSize
            height: root.dotSize
            radius: width / 2
            color: root.tint

            // ── One driver, three properties ──────────────────────────────────
            // `phase` runs 0 → 1 → 0 and everything else is derived from it, so the
            // rise, the fade and the swell cannot drift out of step. Three separate
            // SequentialAnimations on y, opacity and scale would each carry their own
            // rounding and slowly desynchronise into a shimmer.
            property real phase: 0
            y:       -root.dotSize * 0.9 * dot.phase
            opacity: 0.35 + 0.65 * dot.phase
            scale:   0.85 + 0.25 * dot.phase

            SequentialAnimation on phase {
                running: root.running
                loops: Animation.Infinite
                // A sixth of a cycle apart rather than a third: the wave overlaps, so
                // it reads as one motion travelling across rather than three dots
                // taking turns.
                PauseAnimation { duration: Motion.slow / 6 * dot.index }
                NumberAnimation { to: 1; duration: Motion.slow / 2
                                  easing.type: Motion.ambient }
                NumberAnimation { to: 0; duration: Motion.slow / 2
                                  easing.type: Motion.ambient }
                PauseAnimation { duration: Motion.slow / 6 * (2 - dot.index) }
            }
        }
    }
}
