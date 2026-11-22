import QtQuick
import "../../../config"
import "../../../components"
import "../../../services"

// ── QuickBluetooth ────────────────────────────────────────────────────────────
// The Bluetooth pill's card: the adapter switch and the paired devices to connect or let go with one
// press (`Bt.toggleConnection`). Pairing new ones and the rest stay in the panel.
// ─────────────────────────────────────────────────────────────────────────────
QuickFrame {
    id: root

    readonly property var devices: Bt.known.slice(0, 4)

    symbol: !Bt.powered ? "bluetooth_disabled" : Bt.connectedCount > 0 ? "bluetooth_connected" : "bluetooth"
    shape: "squircle"
    title: Translation.tr("Bluetooth")
    value: !Bt.available ? Translation.tr("No adapter")
         : !Bt.powered ? Translation.tr("Off")
         : Bt.connectedCount > 0 ? Translation.tr("%1 connected").arg(Bt.connectedCount)
         : Translation.tr("On, nothing connected")
    bodyVisible: Bt.powered

    trailing: ChipButton {
        symbol: Bt.powered ? "bluetooth" : "bluetooth_disabled"
        tint: root.palette.primary
        solid: true
        on: Bt.powered
        enabled: Bt.available
        onActivated: if (Bt.adapter) Bt.adapter.enabled = !Bt.powered
    }

    Repeater {
        model: root.devices
        OptionCard {
            required property var modelData
            width: parent.width
            symbol: modelData.connected ? "bluetooth_connected" : "bluetooth"
            label: modelData.name || modelData.address
            detail: Bt.stateCaption(modelData)
            shape: "squircle"
            on: modelData.connected
            onActivated: Bt.toggleConnection(modelData)
        }
    }

    StyledText {
        visible: root.devices.length === 0
        width: parent.width
        variant: "caption"
        emphasis: "dim"
        wrapMode: Text.WordWrap
        text: Translation.tr("Nothing paired yet.")
    }

    ChipButton {
        symbol: "bluetooth"
        label: Translation.tr("Devices")
        tint: root.palette.primary
        onActivated: root.openPanel("bluetooth")
    }
}
