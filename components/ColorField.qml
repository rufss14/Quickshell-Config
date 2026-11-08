import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"
import "../services"

// ── ColorField ──────────────────────────────────────────────────────────────
// A label, a swatch + hex field, and the SV+hue picker tucked behind a
// Disclosure — a scene can carry a dozen colour properties, and showing a
// 126×126 square for each up front would be most of the panel. Reuses
// SpectrumPicker (the same widget ColorSchemePanel already drives) rather than
// inventing a second picker; the swatch+hex row mirrors that panel's own
// pattern too, just wrapped for a single value instead of a whole scheme.
//
// `value` is always #rrggbb. An unparsable typed hex is silently dropped on
// commit — InputField's `seed` re-applies once the field loses focus, so a
// bad edit just reverts rather than needing its own error state.
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root

    property string label: ""
    property string value: "#000000"
    signal commit(string hex)

    Layout.fillWidth: true
    Layout.fillHeight: false
    spacing: Tokens.spacingXs

    function _normalise(s) {
        const m = /^#?([0-9a-fA-F]{6})$/.exec(String(s).trim())
        return m ? ("#" + m[1].toLowerCase()) : null
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacingSm

        StyledText {
            Layout.fillWidth: true
            text: root.label
            variant: "body"
            font.weight: Font.DemiBold
        }

        Rectangle {
            Layout.preferredWidth: Tokens.iconSm
            Layout.preferredHeight: Tokens.iconSm
            radius: 3
            color: root.value
            border.width: 1
            border.color: Colors.of(QsWindow.window).outline
        }

        InputField {
            Layout.preferredWidth: 88
            seed: root.value
            onCommitted: function(v) {
                const hex = root._normalise(v)
                if (hex) root.commit(hex)
            }
        }
    }

    Disclosure {
        Layout.fillWidth: true
        label: Translation.tr("Pick a colour")
        contentComponent: Component {
            SpectrumPicker {
                implicitWidth: 160
                implicitHeight: 140
                value: root.value
                onColorPicked: function(hex) { root.commit(hex) }
            }
        }
    }
}
