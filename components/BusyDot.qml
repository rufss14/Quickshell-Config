import QtQuick
import Quickshell
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
    property color tint:    Colors.of(QsWindow.window).focus

    implicitWidth:  6
    implicitHeight: 6
    radius: width / 2
    color:  root.tint
    visible: root.running

    // `Motion.pulse`, not `Motion.slow` — the same tempo, but exempt from the
    // animations toggle. `slow` collapses to 0 when animations are off, which would
    // leave this dot sitting at a constant opacity: precisely the "reads as stuck
    // rather than busy" failure this component exists to replace, reintroduced at
    // all 28 call sites at once. Worst where it is the ONLY feedback — LockScreen
    // and GreetScreen show one while checking a password. See Motion.pulse.
    SequentialAnimation on opacity {
        running: root.running
        loops: Animation.Infinite
        NumberAnimation { to: 0.15; duration: Motion.pulse; easing.type: Motion.ambient }
        NumberAnimation { to: 1.00; duration: Motion.pulse; easing.type: Motion.ambient }
    }
}
