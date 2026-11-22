import QtQuick
import "../../../config"
import "../../../components"
import "../../../services"

// ── QuickNightLight ───────────────────────────────────────────────────────────
// The night light pill's card: the switch, three warmths to pick (a pick turns it on), and the
// schedule. `NightLight.blocker()` says why it can't run (no hyprsunset) and disables the controls.
// ─────────────────────────────────────────────────────────────────────────────
QuickFrame {
    id: root

    readonly property string blocked: NightLight.blocker()
    readonly property var warmths: [
        { name: Translation.tr("Warm"), k: 3000 },
        { name: Translation.tr("Soft"), k: 4000 },
        { name: Translation.tr("Mild"), k: 5000 }
    ]

    symbol: "nightlight"
    shape: "circle"
    title: Translation.tr("Night light")
    value: NightLight.statusText

    trailing: ChipButton {
        symbol: "nightlight"
        tint: root.palette.primary
        solid: true
        on: Config.nightLight
        enabled: root.blocked === ""
        onActivated: NightLight.toggle()
    }

    StyledText {
        visible: root.blocked !== ""
        width: parent.width
        variant: "caption"
        emphasis: "dim"
        wrapMode: Text.WordWrap
        text: root.blocked
    }

    Repeater {
        model: root.warmths
        OptionCard {
            required property var modelData
            width: parent.width
            symbol: "sunny"
            label: modelData.name
            detail: modelData.k + "K"
            shape: "sunny"
            on: Config.nightLight && Config.nightLightTemp === modelData.k
            enabled: root.blocked === ""
            onActivated: { Config.nightLightTemp = modelData.k; Config.nightLight = true }
        }
    }

    OptionCard {
        width: parent.width
        symbol: "timer"
        label: Translation.tr("Follow the schedule")
        detail: NightLight.startText + " to " + NightLight.endText
        shape: "cookie9"
        on: Config.nightLightAuto
        enabled: root.blocked === ""
        onActivated: Config.nightLightAuto = !Config.nightLightAuto
    }
}
