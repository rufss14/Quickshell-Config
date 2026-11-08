import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"

// ── ChipRow ───────────────────────────────────────────────────────────────────
// One choice out of a handful, laid out as pills. The logo renderer, a theme
// variant, a bar position — a value the user PICKS, not an action they trigger.
//
// ── Why not a row of PanelButtons ─────────────────────────────────────────────
// That's what these sites were, and it was wrong twice over. A PanelButton is an
// action ("Connect", "Save"); its `primary` variant means "the one thing this
// dialog is FOR", which a selected option is not. And nine of them in a RowLayout
// simply overflow — the row squeezed the labels to nothing rather than wrapping,
// so the last chip fell off the card on a narrow rail. A Flow wraps, which is what
// a set of nine short labels actually wants.
//
// The selected chip IS a filled accent, unlike the settings rail's selected item.
// The distinction is what the selection MEANS: the rail says "you are here", which
// is `focus` at a tint, while a chip says "this is the value" — the state the
// control is in, the same thing a Toggle's filled track says. Filling it is what
// makes the current choice findable at a glance instead of hunting for the
// slightly-lighter grey, which is exactly how it read on a desaturated palette.
//
// The model is strings, or `{ value, label, glyph }` when the label shouldn't be
// the value — `file-raw` is what fastfetch calls it, "Raw text" is what it is.
// ─────────────────────────────────────────────────────────────────────────────
Flow {
    id: root

    property var    model:   []
    property color  accent:  Colors.of(QsWindow.window).primary

    // `var`, not `string`, for both the current value and the signal — and that is
    // load-bearing, not looseness. A chip's value is whatever the caller's vocabulary
    // is, and BatteryPage's is PowerProfile enum INTS. Declared `string`, QML coerces
    // silently in both directions and the control breaks in two ways that look like
    // nothing: `current` holds "1" while `_value()` returns 1, so `===` is false and
    // NO chip renders as selected; and `picked` hands the caller "1" to assign back
    // to an int property. Strings are unaffected — `"auto" === "auto"` either way.
    property var current: ""

    signal picked(var value)

    function _value(m) { return (typeof m === "string") ? m : (m.value !== undefined ? m.value : m.label) }
    function _label(m) { return (typeof m === "string") ? m : (m.label !== undefined ? m.label : m.value) }
    function _glyph(m) { return (typeof m === "string") ? "" : (m.glyph || "") }

    Layout.fillWidth: true
    spacing: Tokens.spacingXs

    // No `property bool enabled` — Flow is an Item and already has one; inheriting
    // it is also what we want, since it propagates to the MouseAreas below.
    opacity: root.enabled ? 1.0 : 0.4
    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

    Repeater {
        model: root.model

        delegate: Rectangle {
            id: chip

            required property var modelData

            readonly property bool isCurrent: root._value(chip.modelData) === root.current
            Accessible.role: Accessible.RadioButton
            Accessible.name: root._label(chip.modelData)
            Accessible.checkable: true
            Accessible.checked: chip.isCurrent
            Accessible.onPressAction: root.picked(root._value(chip.modelData))

            // ── The pick pops ─────────────────────────────────────────────────
            // Driven by the CHANGE, not bound to the state: a chip that merely ends
            // up bigger says "this one is selected" (the fill already says that),
            // where a chip that swells and settles says "you just picked me". Runs
            // on the same spring the toggle's thumb uses.
            property real pop: 1.0
            onIsCurrentChanged: if (chip.isCurrent) popAnim.restart()

            SequentialAnimation {
                id: popAnim
                NumberAnimation {
                    target: chip; property: "pop"; to: 1.14
                    duration: Motion.respond; easing.type: Motion.respondCurve
                }
                NumberAnimation {
                    target: chip; property: "pop"; to: 1.0
                    duration: Motion.standard
                    easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring
                }
            }

            // Hover lifts an unselected chip; the selected one is already home.
            scale: chip.pop * (chipHover.containsMouse && !chip.isCurrent ? 1.04 : 1.0)
            Behavior on scale {
                NumberAnimation { duration: Motion.respond; easing.type: Motion.respondCurve }
            }

            implicitHeight: 32
            implicitWidth:  Math.ceil(chipContent.implicitWidth) + Tokens.spacingXl

            // A capsule, like the chips of the colours, clock and media panels (2026-10-26;
            // it was the 12px control corner). The chosen chip is the only SOLID thing in
            // the row; the others are a faint wash that lifts under the pointer, so a row of
            // options doesn't spend weight on the ones you didn't pick and needs no outline.
            radius: height / 2

            color: chip.isCurrent
                ? Colors.of(QsWindow.window).alpha(root.accent, chipHover.containsMouse ? 0.95 : 0.85)
                : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, chipHover.containsMouse ? 0.12 : 0.06)

            Behavior on color { ColorAnimation { duration: Motion.respond } }

            RowLayout {
                id: chipContent
                anchors.centerIn: parent
                spacing: Tokens.spacingSm

                MaterialIcon {
                    visible: root._glyph(chip.modelData) !== ""
                    glyph:    root._glyph(chip.modelData)
                    color:   chip.isCurrent ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fgMuted
                    variant: "label"
                }
                StyledText {
                    text:    root._label(chip.modelData)
                    color:   chip.isCurrent ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fg
                    opacity: chip.isCurrent ? 1.0 : 0.80
                    variant: "label"
                    font.weight: chip.isCurrent ? Font.DemiBold : Font.Medium
                }
            }

            MouseArea {
                id: chipHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.picked(root._value(chip.modelData))
            }
        }
    }
}
