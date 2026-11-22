import QtQuick
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"

// ── QuickPower ────────────────────────────────────────────────────────────────
// The power pill's card: the two things that lose nothing, Lock and Sleep, one press each. Anything that
// ends the session (log out, restart, shut down) is behind the power menu, which asks first.
// ─────────────────────────────────────────────────────────────────────────────
QuickFrame {
    id: root

    symbol: "power_settings_new"
    shape: "circle"
    title: Translation.tr("Power")
    value: Session.bootEpoch > 0 ? Translation.tr("Up %1").arg(Session.uptimeText(Date.now())) : ""
    Component.onCompleted: Session.probe()

    OptionCard {
        width: parent.width
        symbol: "lock"
        label: Translation.tr("Lock")
        detail: Translation.tr("Everything keeps running")
        shape: "squircle"
        onActivated: Session.lock()
    }
    OptionCard {
        width: parent.width
        symbol: "bedtime"
        label: Translation.tr("Sleep")
        shape: "circle"
        onActivated: Session.suspend()
    }
    ChipButton {
        symbol: "power_settings_new"
        label: Translation.tr("Power menu")
        tint: root.palette.primary
        onActivated: { UiState.activeScreen = QsWindow.window?.screen ?? UiState.activeScreen; UiState.powerMenuOpen = true }
    }
}
