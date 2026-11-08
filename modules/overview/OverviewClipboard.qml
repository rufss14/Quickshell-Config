pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"

// ── OverviewClipboard ─────────────────────────────────────────────────────────
// Clipboard history on the overview's notifications page, bottom-left — the same card
// language as the notification centre diagonally opposite it: one Surface at card
// elevation, a tinted glyph disc in the header, a hold-to-confirm destructive action,
// and a list that grows with its content instead of filling the corner.
//
// ── Why it mirrors the notification centre so closely ─────────────────────────
// The two answer the same shape of question — "what happened while I wasn't looking,
// and can I act on it" — and they share a screen. Giving them different list idioms
// would make one page look like two.
//
// ── Text and images are one list, not two tabs ────────────────────────────────
// You don't remember what you copied by its type, you remember it by when and roughly
// what it looked like. So they interleave in one chronological list and the row simply
// renders differently: an image gets a thumbnail, text gets its first lines. Splitting
// them would mean checking two places for the thing you copied a minute ago.
// ─────────────────────────────────────────────────────────────────────────────
Surface {
    id: root

    elevation: Tokens.elevationCard
    // Matches OverviewNotifications diagonally opposite it — the expressive corner
    // the shell's large standalone surfaces use. See that card's note.
    cornerRadius: Tokens.radiusXl
    implicitWidth:  400
    implicitHeight: layout.implicitHeight + Tokens.spacingXl * 2

    // How tall the scrolling list may get before it scrolls instead of growing. The
    // caller lowers it to fit the corner it's placed in.
    property int maxListHeight: 420


    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: Tokens.spacingXl
        spacing: Tokens.spacingMd

        // ── Header ────────────────────────────────────────────────────────────
        // Shared PanelHeader, same as the notification centre it mirrors.
        PanelHeader {
            glyph:     "󰅍"                  // clipboard with lines — cmap-verified
            title:     Translation.tr("Clipboard")
            titleTail: Translation.tr("History")
            accent:    Colors.of(QsWindow.window).primary
            subtitle: Clipboard.count === 0 ? "Nothing copied yet"
                : Clipboard.count === 1 ? "1 item"
                : Clipboard.count + " items"
        }

        Divider {}

        // ── Wipe toolbar ──────────────────────────────────────────────────────
        // Hold-to-confirm, and the same HoldButton the notification centre uses for
        // Clear all — this deletes the payloads too, not just the list, so it is the
        // more destructive of the two. Only shown when there is something to wipe.
        RowLayout {
            Layout.fillWidth: true
            visible: Clipboard.count > 0
            spacing: Tokens.spacingSm

            StyledText {
                Layout.fillWidth: true
                text: root.imageCount > 0
                      ? root.imageCount + (root.imageCount === 1 ? " image" : " images")
                      : "text only"
                variant: "caption"
                emphasis: "dim"
            }

            HoldButton {
                Layout.alignment: Qt.AlignVCenter
                glyph: "󰃢"                     // broom — same as Clear all
                label: Translation.tr("Wipe all")
                busyLabel: Translation.tr("Hold to wipe…")
                onConfirmed: Clipboard.wipe()
            }
        }

        // ── Empty state ───────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacingXs
            Layout.bottomMargin: Tokens.spacingXs
            visible: Clipboard.count === 0
            spacing: Tokens.spacingMd

            MaterialIcon { glyph: "󰅍"; font.pixelSize: Tokens.iconLg; color: Colors.of(QsWindow.window).fgDim; opacity: 0.5 }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Copy something and it'll show up here — text or images.")
                variant: "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }
        }

        // ── The list ──────────────────────────────────────────────────────────
        // preferredHeight, not fillHeight, so the card's height follows its content up
        // to maxListHeight and only then scrolls — the same contract as the notification
        // centre, which is what keeps the two corners visually balanced.
        ClipboardList {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, root.maxListHeight)
            visible: Clipboard.count > 0
            maxListHeight: root.maxListHeight
        }
    }

    // How many stored entries are images — the header's one piece of texture, and the
    // thing that tells you at a glance whether that screenshot is still in here.
    readonly property int imageCount:
        Clipboard.entries.filter(e => e.kind === "image").length
}
