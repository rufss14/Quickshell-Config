import QtQuick
import "../config"

// ── BusyDot ───────────────────────────────────────────────────────────────────
// "Something is working in the background." A breathing dot, NOT a spinner.
//
// A spinner implies a task that finishes. Several of these don't: wifi scanning
// runs for as long as its panel is open, so a spinning refresh glyph spun forever
// and read as stuck rather than busy. UpdatePill already used a pulse for exactly
// this; now there is one idiom for it instead of two.
//
// (A spinner IS right where the work genuinely ends — the display probe, the
// shell reload. Those keep theirs.)
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property bool  running: false
    property color tint:    Colors.focus

    implicitWidth:  6
    implicitHeight: 6
    radius: width / 2
    color:  root.tint
    visible: root.running

    SequentialAnimation on opacity {
        running: root.running
        loops: Animation.Infinite
        NumberAnimation { to: 0.15; duration: Motion.slow; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.00; duration: Motion.slow; easing.type: Easing.InOutSine }
    }
}
