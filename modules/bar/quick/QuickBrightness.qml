import QtQuick
import "../../../config"
import "../../../components"
import "../../../services"

// ── QuickBrightness ───────────────────────────────────────────────────────────
// The brightness pill's card: one fader per display that can be set. `Brightness.requestBrightness`
// is the panel's own path (it throttles and syncs); the service is probed when the card first asks.
// ─────────────────────────────────────────────────────────────────────────────
QuickFrame {
    id: root

    Component.onCompleted: Brightness.ensureProbed()

    symbol: "brightness_6"
    shape: "sunny"
    title: Translation.tr("Brightness")
    value: Brightness.count > 0 ? Translation.tr("%1 displays").arg(Brightness.count) : Translation.tr("Looking for displays")

    Repeater {
        model: Brightness.monitors
        Column {
            id: row
            required property int index
            required property string label
            required property int brightness
            required property int controllable
            width: parent.width
            spacing: Tokens.spacingXs
            Row {
                width: parent.width
                StyledText { width: parent.width - pct.width; text: row.label; variant: "caption"; emphasis: "dim"; elide: Text.ElideRight }
                StyledText { id: pct; text: row.brightness + "%"; variant: "caption"; font.features: { "tnum": 1 } }
            }
            ValueSlider {
                width: parent.width
                expressive: true
                thickness: Tokens.spacingXl
                enabled: row.controllable === 1
                value: row.brightness
                maximum: 100
                accessibleName: row.label
                onMoved: function (v) { Brightness.requestBrightness(row.index, v) }
            }
        }
    }

    StyledText {
        visible: Brightness.count === 0
        width: parent.width
        variant: "caption"
        emphasis: "dim"
        wrapMode: Text.WordWrap
        text: Translation.tr("No display here can be dimmed from the shell.")
    }
}
