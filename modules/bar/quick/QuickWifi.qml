import QtQuick
import "../../../config"
import "../../../components"
import "../../../services"

// ── QuickWifi ─────────────────────────────────────────────────────────────────
// The Wi-Fi pill's card: the radio switch and the networks that can be joined with one press (saved
// ones, and open ones). A network that needs a passphrase is the panel's job, so a press on it opens
// the panel. The list is what the service already holds; nothing here starts a scan.
// ─────────────────────────────────────────────────────────────────────────────
QuickFrame {
    id: root

    readonly property var nearby: Net.networks.filter(n => n.connected || !Net.needsPassword(n)).slice(0, 4)

    symbol: Net.wifiEnabled ? "wifi" : "wifi_off"
    shape: "clover"
    title: Translation.tr("Wi-Fi")
    value: Net.wiredConnected ? Translation.tr("Ethernet")
         : Net.connected ? Net.ssid + " · " + Net.strength + "%"
         : !Net.wifiEnabled ? Translation.tr("Off") : Translation.tr("Not connected")
    bodyVisible: Net.wifiEnabled

    trailing: ChipButton {
        symbol: Net.wifiEnabled ? "wifi" : "wifi_off"
        tint: root.palette.primary
        solid: true
        on: Net.wifiEnabled
        enabled: Net.hasWifi && !Net.wifiBlocked
        onActivated: Net.toggleWifi()
    }

    Repeater {
        model: root.nearby
        OptionCard {
            required property var modelData
            width: parent.width
            symbol: Net.isSecured(modelData) ? "lock" : "wifi"
            label: modelData.name
            detail: modelData.connected ? Translation.tr("Connected, press to disconnect") : Net.strengthOf(modelData) + "%"
            shape: "clover"
            on: modelData.connected
            onActivated: modelData.connected ? Net.disconnect() : Net.connect(modelData)
        }
    }

    StyledText {
        visible: root.nearby.length === 0
        width: parent.width
        variant: "caption"
        emphasis: "dim"
        wrapMode: Text.WordWrap
        text: Translation.tr("No saved or open networks in range.")
    }

    ChipButton {
        symbol: "wifi"
        label: Translation.tr("All networks")
        tint: root.palette.primary
        onActivated: root.openPanel("wifi")
    }
}
