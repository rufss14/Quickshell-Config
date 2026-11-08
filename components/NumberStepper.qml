import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"

// ── NumberStepper ─────────────────────────────────────────────────────────────
// [−] value [+]. The CONTROL only — no label, no detail.
//
// That split is the difference between this and the reference's component of the
// same name, which carries its own label and description. Here `SettingRow` and
// `SliderRow` already own that half, and a stepper that also drew a label would give
// every page two ways to write the same row that lay out one pixel apart. This drops
// into a `SettingRow`'s control slot, or sits beside the slider in a `SliderRow`.
//
// ── Why a stepper exists beside the slider at all ─────────────────────────────
// A slider cannot hit an exact value on purpose. Most of the numbers on these pages
// are pixel radii, border widths and counts where the difference between 16 and 17 is
// visible and a drag lands on whichever of them the pointer happened to be over. The
// slider is for finding the neighbourhood; this is for landing on the number.
//
// ── Hold to repeat ────────────────────────────────────────────────────────────
// Press-and-hold accelerates rather than firing once. Without it, walking a radius
// from 10 to 64 is fifty-four clicks, at which point the stepper is decorative and
// the slider is the only real control — which defeats having both.
// ─────────────────────────────────────────────────────────────────────────────
RowLayout {
    id: root

    property real from: 0
    property real to:   100
    property real step: 1
    property real value: 0

    // What the middle shows. Defaults to the raw number, overridden for units or for
    // a value whose zero means something else ("auto" rather than "0 cells").
    property string readout: String(root.value)

    // The value display's width. Pinned rather than derived, so the two buttons do
    // not shuffle sideways every time the number gains or loses a digit — which they
    // did while it was sized to its content, and which reads as the control twitching
    // under the pointer.
    property real numberWidth: 52

    // Smaller buttons and no box behind the number: the stepper that rides on a
    // slider's label line (SliderRow), where the rail under it is the real control.
    property bool compact: false

    signal commit(real v)

    // Rounded to the step's own precision. Floating-point steps (0.05 opacity, 0.1
    // zoom) otherwise accumulate into values like 1.3000000000000003, which the
    // readout then prints in full.
    function _quantise(v) {
        const q = Math.round(v / root.step) * root.step
        return Math.round(q * 1e6) / 1e6
    }

    function _nudge(dir) {
        const next = Math.max(root.from, Math.min(root.to, root._quantise(root.value + dir * root.step)))
        if (next !== root.value) root.commit(next)
    }

    readonly property bool _atMin: root.value <= root.from
    readonly property bool _atMax: root.value >= root.to

    spacing: Tokens.spacingXs
    opacity: root.enabled ? 1.0 : 0.4
    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

    // ── The two buttons ───────────────────────────────────────────────────────
    // A Component reused twice rather than two near-identical blocks: they differ by
    // a glyph and a direction, and the last time this shape was written out twice in
    // this repo the two copies drifted (see the ArmLatch note in CLAUDE.md).
    //
    // It talks to its parent through `blocked` in and `activated()` out, and reads NO
    // id from the enclosing file. An inline component is its own type with its own
    // scope, so reaching out to `root` from in here is the kind of thing that parses
    // perfectly and then throws at runtime — the exact failure class CLAUDE.md's note
    // about the syntax check being weaker than it feels is about.
    // ── Outlined, not filled ──────────────────────────────────────────────────
    // The buttons were solid accent squares, two per stepper — on a page of sliders
    // that was a column of filled accents, which is exactly what "one filled accent
    // per region" (docs/settings-style.md §1.4) is there to stop: the fill should mean
    // "this is the value", and a button is not one. Now they are drawn like an
    // unselected chip: an outline that warms on hover and fills only under the press.
    component StepButton: Rectangle {
        id: btn

        property string glyph: ""
        property bool   blocked: false
        property int    size: 28

        signal activated()

        implicitWidth:  btn.size
        implicitHeight: btn.size
        // Soft rectangle, not a disc — the shell's corner language (Section.qml).
        radius: Tokens.radiusSm

        color: btn.blocked            ? "transparent"
             : btnHover.pressed       ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.30)
             : btnHover.containsMouse ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
                                      : "transparent"
        border.width: Tokens.borderWidth
        border.color: btn.blocked            ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).outline, 0.5)
                    : btnHover.containsMouse ? Colors.of(QsWindow.window).outlineFocus
                                             : Colors.of(QsWindow.window).outline
        Behavior on color        { ColorAnimation { duration: Motion.respond } }
        Behavior on border.color { ColorAnimation { duration: Motion.respond } }

        scale: btnHover.pressed ? 0.9 : 1.0
        Behavior on scale {
            NumberAnimation { duration: Motion.respond; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring }
        }

        MaterialIcon {
            anchors.centerIn: parent
            glyph:  btn.glyph
            color: btn.blocked ? Colors.of(QsWindow.window).fgDim : Colors.of(QsWindow.window).fg
            font.pixelSize: btn.size <= 22 ? Tokens.iconSm : Tokens.iconMd
            Behavior on color { ColorAnimation { duration: Motion.respond } }
        }

        MouseArea {
            id: btnHover
            anchors.fill: parent
            hoverEnabled: true
            enabled: !btn.blocked
            cursorShape: btn.blocked ? Qt.ArrowCursor : Qt.PointingHandCursor

            onClicked: btn.activated()

            // The hold is a SEPARATE path from the click, not a repeat of it: the
            // first step must land on press-and-release like an ordinary button, or a
            // deliberate single click feels laggy while it waits to see if you meant
            // to hold.
            onPressed:  holdDelay.restart()
            onReleased: { holdDelay.stop(); holdRepeat.stop() }
            onCanceled: { holdDelay.stop(); holdRepeat.stop() }

            Timer {
                id: holdDelay
                interval: 400
                onTriggered: holdRepeat.start()
            }

            Timer {
                id: holdRepeat
                interval: 60
                repeat: true
                onTriggered: {
                    // Stops itself at the end of the range rather than firing forever
                    // into a clamp — otherwise holding at the maximum keeps the button
                    // lit and pulsing while nothing changes. `blocked` is bound to the
                    // range check by the parent, so this needs no reach outward.
                    if (btn.blocked) {
                        holdRepeat.stop()
                        return
                    }
                    btn.activated()
                }
            }
        }
    }

    StepButton {
        Layout.alignment: Qt.AlignVCenter
        glyph: "󰍴"
        size: root.compact ? 22 : 28
        blocked: root._atMin
        onActivated: root._nudge(-1)
    }

    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        // numberWidth is a floor, not a cap: a readout longer than the caller guessed
        // ("600ms" in 46px, or any readout at a larger Config.fontScale) widens the box
        // instead of eliding to "600…".
        implicitWidth:  Math.max(root.numberWidth, numText.implicitWidth + Tokens.spacingSm)
        implicitHeight: root.compact ? 22 : 28
        radius: Tokens.radiusSm
        color: root.compact ? "transparent" : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)

        StyledText {
            id: numText
            anchors.centerIn: parent
            width: parent.width - Tokens.spacingSm
            horizontalAlignment: Text.AlignHCenter
            text:    root.readout
            variant: root.compact ? "body" : "caption"
            emphasis: root.compact ? "dim" : "normal"
            font.weight: root.compact ? Font.Medium : Font.Normal
            elide:   Text.ElideRight
        }
    }

    StepButton {
        Layout.alignment: Qt.AlignVCenter
        glyph: "󰐕"
        size: root.compact ? 22 : 28
        blocked: root._atMax
        onActivated: root._nudge(1)
    }
}
