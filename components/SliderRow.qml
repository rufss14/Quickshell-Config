import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"

// ── SliderRow ─────────────────────────────────────────────────────────────────
// A slider for a value you must land on EXACTLY — pixels, minutes, Kelvin. The
// label and an outlined [−] value [+] share the top line; the rail runs under them.
// `Fader` is the same row for a continuous value, with a plain readout instead of
// the stepper.
//
// ValueSlider is normalised 0..maximum and emits a real; this maps a real `from..to`
// range onto it; `step` and `readout` are what stop this being copied instead of used
// for a caller wanting integer px, a percentage, or a multiplier.
//
// ── Two lines, the same as Fader ──────────────────────────────────────────────
// This was label | thin rail | filled stepper on one line, while Fader was label
// over a fat rail — and a third look (HyprlandPage's own row) sat on the Tuning
// page. Three sliders in one app read as three apps. Now there is one shape: label
// left, value right, rail below at the mixer's thickness, and the only difference
// between the exact and the continuous kind is whether the value has buttons.
// It costs a few pixels of height per slider and buys a label that never elides
// into a fixed 84px column (`labelWidth` is still accepted, and ignored).
//
// `numberWidth` exists because readouts differ in length for real reasons (Kelvin
// runs longer than px), and pinning it stops the buttons shuffling as digits change.
//
// HyprlandPage carries a slider of its own that commits only on RELEASE (each write
// spawns a backup + syntax-check script); it draws this same shape.
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: sliderRow

    property string label: ""
    property real from:  0
    property real to:    100
    property real value: 0
    property real step:  1

    // Overridable because the unit is the caller's business: px, %, ×.
    property string readout: sliderRow.value + "px"
    property real numberWidth: 52

    // `false` for a value with no meaningful discrete step (a free-running scale):
    // the readout is plain text, like Fader's.
    property bool stepper: true

    // Accepted for the callers that set it; the label has the whole line now.
    property real labelWidth: 84

    // The sentence that explains it — a tip on the label (HelpTip).
    property string help: ""
    property color  accent: Colors.of(QsWindow.window).primary

    // No `property bool enabled` — ColumnLayout is an Item, which already has one,
    // and redeclaring it shadows the property QML uses to gate input. Inheriting it
    // is also what we want: `enabled: false` on the row disables everything in it.

    signal commit(real v)

    // Snap to the step, then snap off the float noise. `Math.round(v / 0.05) * 0.05`
    // produces 0.7500000000000001, and toFixed in the readout would happily print it.
    function quantise(v) {
        return Math.round(Math.round(v / sliderRow.step) * sliderRow.step * 1e6) / 1e6
    }

    Layout.fillWidth: true
    Layout.fillHeight: false
    spacing: Tokens.spacingXs
    opacity: sliderRow.enabled ? 1.0 : 0.4
    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.minimumHeight: 22
        spacing: Tokens.spacingSm

        HelpTip { id: tip; text: sliderRow.help }

        StyledText {
            Layout.fillWidth: true
            Layout.maximumWidth: Math.ceil(implicitWidth)
            text:    sliderRow.label
            variant: "body"
            font.weight: Font.Medium
            elide:   Text.ElideRight
        }
        MaterialIcon {
            visible: sliderRow.help !== ""
            name: "info"
            color: Colors.of(QsWindow.window).fgDim
            font.pixelSize: Tokens.iconSm
            opacity: tip.active ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
        Item { Layout.fillWidth: true }

        // Shares the row's range and step, so the two controls cannot disagree.
        NumberStepper {
            visible: sliderRow.stepper
            Layout.alignment: Qt.AlignVCenter
            compact: true

            from: sliderRow.from
            to:   sliderRow.to
            step: sliderRow.step
            value: sliderRow.value
            readout: sliderRow.readout
            numberWidth: sliderRow.numberWidth

            onCommit: function (v) { sliderRow.commit(v) }
        }

        StyledText {
            visible: !sliderRow.stepper
            text:     sliderRow.readout
            variant:  "body"
            emphasis: "dim"
            font.weight: Font.Medium
        }
    }

    ValueSlider {
        Layout.fillWidth: true
        thickness: 16
        expressive: true
        accent: sliderRow.accent
        maximum: 1.0
        value: sliderRow.to > sliderRow.from
            ? (sliderRow.value - sliderRow.from) / (sliderRow.to - sliderRow.from)
            : 0

        onMoved: function(v) {
            sliderRow.commit(sliderRow.quantise(
                sliderRow.from + v * (sliderRow.to - sliderRow.from)))
        }
        // Ctrl+wheel only: a settings page scrolls under the pointer (ValueSlider).
        wheelNeedsModifier: true
        // One step per notch, not one pixel — a 0.05 scale would otherwise jump the
        // whole range on a single wheel click.
        onScrolled: function(d) {
            sliderRow.commit(Math.max(sliderRow.from, Math.min(sliderRow.to,
                sliderRow.quantise(sliderRow.value + d * sliderRow.step))))
        }
    }
}
