import QtQuick
import "../../../config"
import "../../../components"
import "../../../services"

// ── QuickStats ────────────────────────────────────────────────────────────────
// The stats pill's card: each metric the sidebar's stats module shows (`SysStats.metrics`, the user's pick),
// as a name, its reading and a meter. The ratio and wording are `SysStats.readout`'s, one source with the panel.
// ─────────────────────────────────────────────────────────────────────────────
QuickFrame {
    id: root

    symbol: "speed"
    shape: "hexagon"
    title: Translation.tr("System")
    value: ModuleGlance.value("stats")

    Repeater {
        model: SysStats.metrics.slice(0, 4)
        Column {
            id: row
            required property string modelData
            readonly property var r: SysStats.readout(row.modelData)
            width: parent.width
            spacing: Tokens.spacingXs
            Row {
                width: parent.width
                StyledText { width: parent.width - val.width; text: row.r.label; variant: "caption"; emphasis: "dim" }
                StyledText { id: val; text: row.r.value; variant: "caption"; font.features: { "tnum": 1 } }
            }
            Meter {
                width: parent.width
                value: row.r.ratio
                accent: SysStats.isAlerting(row.modelData) ? root.palette.danger : root.palette.primary
            }
        }
    }
    ChipButton {
        symbol: "speed"
        label: Translation.tr("Monitor")
        tint: root.palette.primary
        onActivated: SysStats.openMonitor()
    }
}
