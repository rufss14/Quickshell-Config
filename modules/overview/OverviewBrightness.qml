import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── OverviewBrightness ────────────────────────────────────────────────────────
// A vertical LED-meter brightness slider — one per CONTROLLABLE monitor. Sits
// beside the media cards at the top of the overview, and stays there whether or not
// anything is playing (brightness isn't media, so it doesn't vanish with the cards).
//
// ── Segments, not a fill ────────────────────────────────────────────────────
// A hardware level meter's language, not an iOS pill's: ten discrete cells lighting
// bottom-up rather than one continuous rectangle rising. The level is a COUNT you can
// read at a glance ("seven lit") instead of a height you have to estimate, and it
// reads as a control panel rather than a progress bar — nothing else in the shell
// looks like this, which is deliberate: brightness earns a distinct identity, not a
// smaller copy of the volume slider's own fill idiom.
//
// A monitor the shell can't drive (no DDC, no backlight) shows no slider rather than a
// dead one — an invisible delegate takes no room in the Row, so the visible sliders
// still address the model by their REAL index.
//
// The whole thing renders nothing at all when there's no controllable display, so a
// desktop with a fixed external monitor doesn't get an empty stub.
// ─────────────────────────────────────────────────────────────────────────────
Row {
    id: root

    spacing: Tokens.spacingMd

    Component.onCompleted: Brightness.ensureProbed()

    readonly property int controllableCount: {
        let n = 0
        for (let i = 0; i < Brightness.monitors.count; i++)
            if (Brightness.monitors.get(i).controllable) n++
        return n
    }

    visible: controllableCount > 0

    Repeater {
        model: Brightness.monitors

        // ── One slider ────────────────────────────────────────────────────────
        Item {
            id: cell
            required property int index
            required property var model

            visible: cell.model.controllable
            width:  48
            height: 168

            readonly property real value: cell.model.brightness      // 0..100
            readonly property real min:   cell.model.type === "bcl" ? Brightness.laptopMinBrightness : 0
            readonly property real frac:  cell.value / 100

            function apply(v) {
                Brightness.requestBrightness(cell.index, Math.max(cell.min, Math.min(100, v)))
            }

            // The track.
            Surface {
                id: track
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width:  40
                height: 128
                elevation: Tokens.elevationNested
                cornerRadius: Tokens.radiusSm
                focused: drag.pressed

                readonly property int  segCount: 10
                readonly property int  segGap:   3
                readonly property int  segPad:   4
                readonly property real segH:
                    (track.height - track.segPad * 2 - track.segGap * (track.segCount - 1)) / track.segCount

                // Ten cells, bottom-up. `fromBottom` is what the threshold and the
                // brightening-toward-the-top colour both read — a Column lays out
                // top-to-bottom, so the Repeater's own index runs the wrong way for
                // "how many are lit counting from the floor" and gets flipped here
                // once rather than at every call site below.
                Column {
                    anchors.fill: parent
                    anchors.margins: track.segPad
                    spacing: track.segGap

                    Repeater {
                        model: track.segCount

                        Rectangle {
                            id: seg
                            required property int index
                            readonly property int  fromBottom: track.segCount - 1 - index
                            readonly property bool lit: cell.frac >= (seg.fromBottom + 0.5) / track.segCount

                            width:  parent.width
                            height: track.segH
                            radius: 2

                            // Lit cells brighten toward the top — the same "louder near
                            // the ceiling" cue a real VU meter's red zone gives, done in
                            // the accent rather than a second colour. Unlit cells are a
                            // bare outline of themselves: present (so the full ten-cell
                            // shape always reads, even at zero) without competing with
                            // whichever ARE lit.
                            color: seg.lit
                                ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.55 + 0.40 * (seg.fromBottom / track.segCount))
                                : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)

                            // A cell that just crossed its threshold pops rather than
                            // fading in flush — snappier, and it's what makes turning
                            // this up feel like flipping switches rather than watching
                            // a bar redraw.
                            scale: seg.lit ? 1.0 : 0.92
                            Behavior on scale { NumberAnimation { duration: Motion.respond; easing.type: Motion.travel } }
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }
                    }
                }

                MouseArea {
                    id: drag
                    anchors.fill: parent
                    // Drag anywhere on the track, iPhone-style — press sets the value at
                    // the finger, and moving keeps setting it.
                    function fromY(y) {
                        const frac = 1 - Math.max(0, Math.min(1, y / height))
                        cell.apply(frac * 100)
                    }
                    onPressed:         function(m) { fromY(m.y) }
                    onPositionChanged: function(m) { if (pressed) fromY(m.y) }
                    onWheel:           function(w) { cell.apply(cell.value + (w.angleDelta.y > 0 ? 5 : -5)) }
                }
            }

            // ── Readout ──────────────────────────────────────────────────────
            // The level, always on — the restraint the old design's hidden number
            // was reaching for ("no number at rest") stops being the right call once
            // the meter itself is ten discrete cells: "roughly seven of ten" is a
            // headline reading a person still has to convert to a number, so the
            // number is just here. Bold over dim, the same two-line shape ClockPill
            // and every media card in this shell already use for "the current value,
            // then what it's a value OF" — not a new idiom, the shell's usual one.
            StyledText {
                id: percentText
                anchors.top: track.bottom
                anchors.topMargin: Tokens.spacingXs
                anchors.horizontalCenter: parent.horizontalCenter
                text: Math.round(cell.value) + "%"
                variant: "caption"
                font.family: Tokens.fontMono
                font.bold: true
                color: drag.pressed ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fg
                Behavior on color { ColorAnimation { duration: Motion.respond } }
            }

            StyledText {
                anchors.top: percentText.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: cell.model.type === "bcl" ? "Internal"
                    : (cell.model.port || cell.model.label || "Display")
                variant: "caption"
                emphasis: "dim"
            }
        }
    }
}
