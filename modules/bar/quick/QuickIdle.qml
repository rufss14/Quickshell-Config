import QtQuick
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"

// ── QuickIdle ─────────────────────────────────────────────────────────────────
// The stay-awake pill's card: on until switched off, or for a while (`Idle.keepFor`, which lets go by
// itself). Something else holding the screen awake (a game) is said, and the switch will not clear it.
// ─────────────────────────────────────────────────────────────────────────────
QuickFrame {
    id: root

    function _until() {
        const d = new Date(Idle.manualUntil)
        return Clock.pad(d.getHours()) + ":" + Clock.pad(d.getMinutes())
    }

    symbol: "coffee"
    shape: "hexagon"
    title: Translation.tr("Stay awake")
    value: Idle.manual && Idle.manualUntil > 0 ? Translation.tr("Awake until %1").arg(root._until())
         : Idle.heldExternally && !Idle.manual ? Idle.reasonText
         : Idle.manual ? Translation.tr("Staying awake") : Translation.tr("Normal")

    trailing: ChipButton {
        symbol: "coffee"
        tint: root.palette.primary
        solid: true
        on: Idle.manual
        onActivated: Idle.toggleManual()
    }

    OptionCard {
        width: parent.width
        symbol: "coffee"
        label: Translation.tr("Until I turn it off")
        shape: "hexagon"
        on: Idle.manual && Idle.manualUntil === 0
        onActivated: Idle.manual = true
    }

    Row {
        spacing: Tokens.spacingSm
        ChipButton { symbol: "timer"; label: Translation.tr("30 min"); tint: root.palette.primary; onActivated: Idle.keepFor(30) }
        ChipButton { symbol: "timer"; label: Translation.tr("1 h"); tint: root.palette.primary; onActivated: Idle.keepFor(60) }
        ChipButton { symbol: "timer"; label: Translation.tr("3 h"); tint: root.palette.primary; onActivated: Idle.keepFor(180) }
    }
}
