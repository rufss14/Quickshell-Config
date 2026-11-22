import QtQuick
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"

// ── QuickUpdate ───────────────────────────────────────────────────────────────
// The update pill's card: what is waiting (official, AUR, Flatpak), a recheck, the latest Arch news, and
// the way into the update panel. It runs no update itself: that needs the password flow the panel has.
// ─────────────────────────────────────────────────────────────────────────────
QuickFrame {
    id: root

    symbol: "update"
    shape: "cookie9"
    title: Translation.tr("Updates")
    value: Updates.checking ? Translation.tr("Checking")
         : Updates.total > 0 ? Translation.tr("%1 waiting").arg(Updates.total) : Translation.tr("Up to date")

    trailing: ChipButton {
        symbol: "refresh"
        tint: root.palette.primary
        solid: true
        enabled: !Updates.checking
        onActivated: Updates.check()
    }

    StyledText {
        visible: Updates.total > 0
        width: parent.width
        text: Translation.tr("%1 official, %2 AUR, %3 Flatpak").arg(Updates.count).arg(Updates.aurCount).arg(Updates.flatpakCount)
        variant: "caption"
    }
    StyledText {
        width: parent.width
        text: Updates.needsReboot ? Translation.tr("A restart is needed after these.") : Translation.tr("Last checked %1").arg(Updates.lastCheckedText)
        variant: "caption"
        emphasis: "dim"
        wrapMode: Text.WordWrap
    }
    OptionCard {
        visible: Updates.newsTitle !== ""
        width: parent.width
        symbol: "language"
        label: Updates.newsTitle
        detail: Updates.newsDate
        shape: "squircle"
        on: Updates.newsUnread
        onActivated: Quickshell.execDetached(["xdg-open", Updates.newsUrl])
    }
    ChipButton {
        symbol: "update"
        label: Translation.tr("Update panel")
        tint: root.palette.primary
        onActivated: root.openPanel("update")
    }
}
