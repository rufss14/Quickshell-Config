import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"

// ── Fader ─────────────────────────────────────────────────────────────────────
// The slider for a CONTINUOUS value — a percentage, an fps, a multiplier: label and
// value on one line, a fat ValueSlider (the audio-mixer's thickness) underneath.
//
// `SliderRow` is the same row for the values that must land on an exact number — a
// pixel radius, a border width, a count — and adds an outlined [−] [+] around its
// value. Same line height, same rail, so a card can hold both and read as one list.
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root

    property string label:   ""
    property real   from:    0
    property real   to:      1
    property real   value:   0
    property real   step:    1
    property string readout: ""
    property color  accent:  Colors.of(QsWindow.window).primary
    // The sentence that explains it — a tip on the label (HelpTip).
    property string help:    ""

    signal commit(real v)

    Layout.fillWidth: true
    Layout.fillHeight: false
    spacing: Tokens.spacingXs
    opacity: root.enabled ? 1.0 : 0.4
    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

    function _q(v)     { return Math.round(Math.round(v / root.step) * root.step * 1e6) / 1e6 }
    function _clamp(v) { return Math.max(root.from, Math.min(root.to, v)) }

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.minimumHeight: 22
        spacing: Tokens.spacingSm

        HelpTip { id: tip; text: root.help }

        StyledText {
            Layout.fillWidth: true
            Layout.maximumWidth: Math.ceil(implicitWidth)
            text: root.label
            variant: "body"
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
        MaterialIcon {
            visible: root.help !== ""
            name: "info"
            color: Colors.of(QsWindow.window).fgDim
            font.pixelSize: Tokens.iconSm
            opacity: tip.active ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
        Item { Layout.fillWidth: true }
        StyledText {
            text: root.readout
            variant: "body"
            emphasis: "dim"
            font.weight: Font.Medium
        }
    }

    ValueSlider {
        Layout.fillWidth: true
        thickness: 14
        accent: root.accent
        maximum: 1.0
        value: root.to > root.from ? (root.value - root.from) / (root.to - root.from) : 0
        onMoved:    function(v) { root.commit(root._q(root.from + v * (root.to - root.from))) }
        // Ctrl+wheel only: a settings page scrolls under the pointer (ValueSlider).
        wheelNeedsModifier: true
        onScrolled: function(d) { root.commit(root._clamp(root._q(root.value + d * root.step))) }
    }
}
