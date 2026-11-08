pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../config"

// ── DotMatrixSpectrum ─────────────────────────────────────────────────────────
// A segmented LED-style equalizer: each column is a fixed stack of cells, lit
// bottom-up by that bin's level, the look of a hardware graphic-EQ display rather
// than a smooth bar. Deliberately blocky where Spectrum is smooth and Waveform is
// continuous — a third texture, not a third measurement of the same thing.
//
// Segment brightness scales with height rather than a red/amber/green ramp — the
// classic hardware look uses that as a clipping warning, which has no meaning
// here, and colour still only ever comes from `accent` (Colours only from the
// Colors singleton — see CLAUDE.md).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property var  levels:   []
    property int  barCount: 12
    property int  segments: 10
    property color accent:  Colors.of(QsWindow.window).primary

    readonly property real colGap: 4
    readonly property real segGap: 2
    readonly property real colW:
        Math.max(1, (width - root.colGap * (root.barCount - 1)) / Math.max(1, root.barCount))
    readonly property real segH:
        Math.max(1, (height - root.segGap * (root.segments - 1)) / Math.max(1, root.segments))

    Row {
        anchors.fill: parent
        spacing: root.colGap

        Repeater {
            model: root.barCount

            Column {
                id: col
                required property int index

                width:  root.colW
                height: root.height
                spacing: root.segGap

                readonly property real level:
                    col.index < root.levels.length ? Math.max(0, Math.min(1, root.levels[col.index])) : 0
                readonly property int lit: Math.round(col.level * root.segments)

                Repeater {
                    model: root.segments

                    delegate: Rectangle {
                        id: seg
                        required property int index

                        width:  col.width
                        height: root.segH
                        radius: 1

                        // Column order is top-to-bottom (index 0 = top segment), so
                        // "how many segments from the bottom" is what compares against
                        // `lit`, and doubles as how much brighter a lit cell reads —
                        // the top of a tall column glows harder than its base.
                        readonly property int fromBottom: root.segments - 1 - seg.index
                        readonly property bool on: seg.fromBottom < col.lit

                        color: seg.on
                            ? Colors.of(QsWindow.window).alpha(root.accent, 0.65 + 0.35 * (seg.fromBottom / root.segments))
                            : Colors.of(QsWindow.window).alpha(root.accent, 0.14)

                        Behavior on color { ColorAnimation { duration: Motion.fast } }
                    }
                }
            }
        }
    }
}
