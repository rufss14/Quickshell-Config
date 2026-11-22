import QtQuick
import "../../../config"
import "../../../components"
import "../../../services"

// ── QuickNotifications ────────────────────────────────────────────────────────
// The notifications pill's card: Do Not Disturb (on, or for a while), and the latest three records as
// rows that open the centre. Never removes a record: clearing stays in the centre, where it can be undone.
// ─────────────────────────────────────────────────────────────────────────────
QuickFrame {
    id: root

    readonly property var latest: Notifications.records.slice(0, 3)

    symbol: Notifications.dnd ? "notifications_off" : "notifications"
    shape: "pentagon"
    title: Translation.tr("Notifications")
    value: Notifications.dnd ? Translation.tr("Do Not Disturb") + (Notifications.dndLabel !== "" ? " " + Notifications.dndLabel : "")
         : Notifications.count > 0 ? Translation.tr("%1 in the centre").arg(Notifications.count)
         : Translation.tr("All caught up")

    trailing: ChipButton {
        symbol: Notifications.dnd ? "notifications_off" : "notifications"
        tint: root.palette.primary
        solid: true
        on: Notifications.dnd
        onActivated: Notifications.toggleDnd()
    }

    Row {
        spacing: Tokens.spacingSm
        ChipButton { symbol: "timer"; label: Translation.tr("30 min"); tint: root.palette.primary; onActivated: Notifications.dndFor(30) }
        ChipButton { symbol: "timer"; label: Translation.tr("1 h"); tint: root.palette.primary; onActivated: Notifications.dndFor(60) }
        ChipButton { symbol: "bedtime"; label: Translation.tr("Morning"); tint: root.palette.primary; onActivated: Notifications.dndUntilMorning() }
    }

    Repeater {
        model: root.latest
        OptionCard {
            required property var modelData
            width: parent.width
            symbol: "notifications"
            label: modelData.summary || modelData.appName
            detail: modelData.summary ? modelData.appName : ""
            shape: "pentagon"
            onActivated: root.openPanel("notifications")
        }
    }
}
