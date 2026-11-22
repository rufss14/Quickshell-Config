import QtQuick
import Quickshell.Services.UPower
import "../../../config"
import "../../../components"
import "../../../services"

// ── QuickBattery ──────────────────────────────────────────────────────────────
// The battery pill's card: the charge as a meter, what the battery is doing and how long it has, and the
// power saver's three settings (`Config.powerSaver`: auto follows the plug, on, off). The saver itself is
// PowerSaver's; this only sets the preference.
// ─────────────────────────────────────────────────────────────────────────────
QuickFrame {
    id: root

    readonly property var dev: UPower.displayDevice
    readonly property real pct: root.dev ? root.dev.percentage * 100 : 0
    readonly property bool charging: !!root.dev && (root.dev.state === UPowerDeviceState.Charging
                                                   || root.dev.state === UPowerDeviceState.PendingCharge)

    function _span(secs) {
        if (!secs || secs <= 0) return ""
        const h = Math.floor(secs / 3600), m = Math.floor((secs % 3600) / 60)
        return h > 0 ? Translation.tr("%1 h %2 min").arg(h).arg(m) : Translation.tr("%1 min").arg(m)
    }
    readonly property string timeLine: !root.dev ? ""
        : root.charging ? (root._span(root.dev.timeToFull) !== "" ? Translation.tr("Full in %1").arg(root._span(root.dev.timeToFull)) : Translation.tr("Charging"))
        : (root._span(root.dev.timeToEmpty) !== "" ? Translation.tr("%1 left").arg(root._span(root.dev.timeToEmpty)) : Translation.tr("On battery"))

    symbol: root.charging ? "bolt" : "battery_full"
    shape: "cookie9"
    title: Translation.tr("Battery")
    value: root.dev ? Math.round(root.pct) + "%" + (root.timeLine !== "" ? " · " + root.timeLine : "") : Translation.tr("No battery")

    Meter {
        width: parent.width
        value: root.pct / 100
        accent: root.pct <= 15 && !root.charging ? root.palette.danger : root.palette.primary
    }
    StyledText {
        width: parent.width
        variant: "caption"
        emphasis: "dim"
        text: Translation.tr("Power saver")
    }
    Repeater {
        model: [
            { key: "auto", name: Translation.tr("Automatic"), detail: Translation.tr("On while unplugged") },
            { key: "on",   name: Translation.tr("Always on"), detail: "" },
            { key: "off",  name: Translation.tr("Off"),       detail: "" }
        ]
        OptionCard {
            required property var modelData
            width: parent.width
            symbol: "bolt"
            label: modelData.name
            detail: modelData.detail
            shape: "cookie6"
            on: Config.powerSaver === modelData.key
            onActivated: Config.powerSaver = modelData.key
        }
    }
}
