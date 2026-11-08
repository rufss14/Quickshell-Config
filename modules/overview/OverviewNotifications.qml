import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../notifications"

// ── OverviewNotifications ─────────────────────────────────────────────────────
// The notification centre as a standalone card — the lock screen's right edge (it
// was the overview's second page, bottom-right, before the bar's panel took over).
// The list is read-only here; the sidebar's / bar's NotificationsPanel is the one
// that acts.
//
// ── Grouped by app ────────────────────────────────────────────────────────────
// A flat chronological stack made a busy chat app bury everything else. The centre now
// buckets by app (Notifications.historyGroups): each app is a header — its icon, name, a
// count and a per-app clear — with its notifications stacked beneath as the same toast
// cards you see on screen, so the drawer and the toasts speak one visual language.
//
// It sizes to its CONTENT: a couple of notifications makes a couple-of-notifications-tall
// card, and an empty inbox makes a small one. It doesn't stretch to fill the corner.
// ─────────────────────────────────────────────────────────────────────────────
Surface {
    id: root

    elevation: Tokens.elevationCard
    // The expressive corner the shell's large standalone surfaces use (Section,
    // HeroCard) — not radiusCard, which is tuned to match a window's rounding and
    // is right for the workspace cells but reads as boxy on a content card this
    // size floating on the scrim.
    cornerRadius: Tokens.radiusXl
    implicitWidth:  400
    implicitHeight: layout.implicitHeight + Tokens.spacingXl * 2

    // How tall the scrolling list may get before it scrolls instead of growing. The
    // caller can lower it to fit a short corner.
    property int maxListHeight: 460

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: Tokens.spacingXl
        spacing: Tokens.spacingMd

        // ── Header ────────────────────────────────────────────────────────────
        // The shell's shared PanelHeader — same icon chip / two-word title / subtitle
        // every bar panel carries. Was a hand-rolled row that disagreed with them on
        // the chip size, the title weight and the subtitle opacity.
        PanelHeader {
            Layout.fillHeight: false
            glyph:     Notifications.quiet ? "󰂛" : "󰂚"
            title:     Translation.tr("Notification")
            titleTail: Translation.tr("Centre")
            accent:    Colors.of(QsWindow.window).primary
            subtitle:  Notifications.statusLine

            // Do Not Disturb — spelled out, not "DND". Filled when on.
            PanelButton {
                Layout.alignment: Qt.AlignVCenter
                variant: Notifications.dnd ? "primary" : "normal"
                accent:  Colors.of(QsWindow.window).primary
                glyph:   Notifications.dnd ? "󰂛" : "󰂚"
                label:   Translation.tr("Do Not Disturb")
                onActivated: Notifications.toggleDnd()
            }
        }

        Divider {}

        // ── Clear-all toolbar ─────────────────────────────────────────────────
        // The old clear-all was an unlabelled glyph tucked in the header corner — easy to
        // mis-hit and unclear what it did. It's now a labelled, HOLD-to-confirm action in
        // its own row: you press and hold for a beat (a fill sweeps across) to wipe every
        // notification, so a destructive action can't happen on a stray tap. Only shown
        // when there's something to clear.
        RowLayout {
            Layout.fillHeight: false
            Layout.fillWidth: true
            visible: Notifications.count > 0
            spacing: Tokens.spacingSm

            // No repeat of "N apps" here — the header subtitle above already says it.
            Item { Layout.fillWidth: true }

            HoldButton {
                // Set at the call site now that HoldButton is shared — the private
                // version baked this in, which a component used in two layouts can't.
                Layout.alignment: Qt.AlignVCenter
                glyph: "󰃢"                 // broom — sweep it all away
                label: Translation.tr("Clear all")
                busyLabel: Translation.tr("Hold to clear…")
                onConfirmed: Notifications.clearHistory()
            }
        }

        // ── Empty state ───────────────────────────────────────────────────────
        // Compact by design — a couple of lines, so an empty inbox is a small card.
        RowLayout {
            Layout.fillHeight: false
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacingXs
            Layout.bottomMargin: Tokens.spacingXs
            visible: Notifications.count === 0
            spacing: Tokens.spacingMd

            MaterialIcon { glyph: "󰂚"; font.pixelSize: Tokens.iconLg; color: Colors.of(QsWindow.window).fgDim; opacity: 0.5 }
            StyledText {
                Layout.fillWidth: true
                text: Notifications.dnd
                    ? "Do Not Disturb is on. New notifications wait here quietly."
                    : Notifications.quietHeldExternally
                    ? "Quiet while " + Notifications.quietHolds.join(", ") + " is on. New notifications wait here."
                    : "No notifications right now."
                variant: "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }
        }

        // A row's ✕ or an app's clear is instant; this puts it back.
        UndoBar { id: undo }

        // ── The stack, grouped by app ─────────────────────────────────────────
        // preferredHeight (not fillHeight) so the card's own height follows the content:
        // it grows with the groups up to maxListHeight, then the list scrolls inside it.
        // Read-only: this card is the lock screen's, and a click must not open an app
        // (or a link) behind the lock.
        NotificationGroups {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, root.maxListHeight)
            visible: Notifications.count > 0
            actionable: false
            onCleared: (recs) => {
                if (recs.length > 0)
                    undo.show(recs.length === 1 ? "Cleared 1 notification"
                                                : "Cleared " + recs.length + " notifications",
                              () => Notifications.restore(recs))
            }
        }
    }
}
