import QtQuick
import "../../../config"
import "../../../components"
import "../../../services"

// ── QuickGamemode ─────────────────────────────────────────────────────────────
// The Game Mode pill's card: the switch, and the two things it quiets that people want a say in (the
// desktop visualiser, other apps' key sounds). The rest (effects, tuning, history) is the panel.
// ─────────────────────────────────────────────────────────────────────────────
QuickFrame {
    id: root

    symbol: "sports_esports"
    shape: "clover"
    title: Translation.tr("Game Mode")
    value: Gamemode.active ? (Gamemode.gameName !== "" ? Translation.tr("On, %1").arg(Gamemode.gameName) : Translation.tr("On"))
                           : Translation.tr("Off")

    trailing: ChipButton {
        symbol: "sports_esports"
        tint: root.palette.primary
        solid: true
        on: Gamemode.active
        onActivated: Gamemode.toggle()
    }

    OptionCard {
        width: parent.width
        symbol: "monitor"
        label: Translation.tr("Hide the visualiser")
        shape: "cookie9"
        on: Config.gamemodeVisualizer
        onActivated: Config.gamemodeVisualizer = !Config.gamemodeVisualizer
    }
    OptionCard {
        width: parent.width
        symbol: "volume_off"
        label: Translation.tr("Silence key sounds")
        shape: "cookie6"
        on: Config.gamemodeKeys
        onActivated: Config.gamemodeKeys = !Config.gamemodeKeys
    }
    ChipButton {
        symbol: "sports_esports"
        label: Translation.tr("Game Mode panel")
        tint: root.palette.primary
        onActivated: root.openPanel("gaming")
    }
}
