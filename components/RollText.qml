import QtQuick
import Quickshell
import "../config"

// ── RollText ──────────────────────────────────────────────────────────────────
// Text whose characters roll when they change: the old glyph slides up and out
// while the new one rises into its place. Per CHARACTER, so 22:39 → 22:40 moves two
// digits and leaves "22:" standing still.
//
// For figures that change in place — a clock, a temperature. Not for prose: every
// character is its own clipped cell, which is cheap for five and silly for fifty.
//
// ── The motion ────────────────────────────────────────────────────────────────
// The glyph travels HALF a line, not a whole one, and fades as it goes: a full-height
// slide inside a clip shows the clip's edge slicing through the digits (a figure caught
// mid-roll looked cut off at the top), where half a line with a cross-fade never gets
// far enough out for the edge to read. Cells start a beat apart, left to right, so a
// number that changes in several places ripples instead of flipping as one block.
//
// Durations come from Motion, so animations-off is a plain swap.
// ─────────────────────────────────────────────────────────────────────────────
Row {
    id: root

    property string text:      ""
    property color  color:     Colors.of(QsWindow.window).fg
    property string family:    Tokens.fontFamily
    property int    pixelSize: Tokens.fontBody
    property int    weight:    Font.Normal

    Repeater {
        model: root.text.length

        delegate: Item {
            id: cell
            required property int index
            readonly property string ch: root.text.charAt(cell.index)

            width:  front.implicitWidth
            height: front.implicitHeight
            clip: true

            // `front.text` is assigned, never bound: with a binding, the text could
            // update before this handler ran and there'd be nothing left to roll FROM.
            Component.onCompleted: front.text = cell.ch
            onChChanged: {
                if (front.text === cell.ch) return
                back.text  = front.text
                front.text = cell.ch
                // Start state set NOW, not by the animation: the cascade's pause comes
                // first, and the new glyph must not be sitting at rest during it.
                back.y = 0;                 back.opacity = 1
                front.y = cell.height / 2;  front.opacity = 0
                roll.restart()
            }

            StyledText {
                id: back
                opacity: 0
                color: root.color
                font.family:    root.family
                font.pixelSize: root.pixelSize
                font.weight:    root.weight
            }
            StyledText {
                id: front
                color: root.color
                font.family:    root.family
                font.pixelSize: root.pixelSize
                font.weight:    root.weight
            }

            SequentialAnimation {
                id: roll
                PauseAnimation { duration: Math.min(cell.index * Motion.stagger, Motion.staggerCap) }
                ParallelAnimation {
                    NumberAnimation {
                        target: back; property: "y"; to: -cell.height / 2
                        duration: Motion.spatial
                        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel
                    }
                    NumberAnimation { target: back; property: "opacity"; to: 0; duration: Motion.standard }
                    NumberAnimation {
                        target: front; property: "y"; to: 0
                        duration: Motion.spatial
                        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel
                    }
                    NumberAnimation { target: front; property: "opacity"; to: 1; duration: Motion.spatial }
                }
            }
        }
    }
}
