pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── ClipboardPanel ────────────────────────────────────────────────────────────
// Clipboard history, beside the sidebar's clipboard button (SidePanelDock): the
// overview's clipboard card as a side panel. Click a row to put it back on the
// clipboard; the panel then steps aside so you can paste.
//
// The panel recipe: PanelHeader + ActionGroup, tokens throughout, shared widgets —
// the rows are ClipboardList, the same list the overview draws. Everything real is
// services/Clipboard; this shows it and calls it.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The room the slot has (SidePanelDock sets it); the list scrolls past it.
    property real maxHeight: Infinity

    readonly property int pad: Tokens.spacingLg
    implicitWidth: Tokens.sideCardUnit * 8
    implicitHeight: Math.min(root.maxHeight, col.implicitHeight + root.pad * 2)

    // The list's ceiling: what the slot leaves under the header, never more than
    // nine card units (a long history scrolls rather than filling the screen's height).
    readonly property real listRoom: Math.max(Tokens.sideCardUnit * 2, Math.min(Tokens.sideCardUnit * 9,
        root.maxHeight - root.pad * 2 - head.implicitHeight - col.spacing))

    readonly property int imageCount: Clipboard.entries.filter(e => e.kind === "image").length

    ArmLatch {
        id: wipeLatch
        onConfirmed: Clipboard.wipe()
    }

    // After a pick: long enough to see the row say "Copied", then out of the way.
    // An interaction timing, not a Motion duration (with motion off those are 0).
    Timer {
        id: stepAside
        interval: 600
        onTriggered: UiState.closePanel("clipboard")
    }

    ColumnLayout {
        id: col
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.pad
        spacing: Tokens.spacingMd

        PanelHeader {
            id: head
            Layout.fillHeight: false
            glyph:     "\u{F014D}"                                   // 󰅍 clipboard-text
            title:     Translation.tr("Clipboard")
            titleTail: "history"
            accent:    Colors.of(QsWindow.window).primary
            subtitle:  Clipboard.count === 0 ? "Nothing copied yet"
                     : (Clipboard.count === 1 ? "1 item" : Clipboard.count + " items")
                       + (root.imageCount > 0 ? " · " + root.imageCount
                          + (root.imageCount === 1 ? " image" : " images") : "")

            ActionGroup {
                groupShown: Clipboard.count > 0
                // Deletes the stored payloads too, so it asks twice.
                PanelButton {
                    variant: wipeLatch.armed ? "primary" : "ghost"
                    accent:  Colors.of(QsWindow.window).danger
                    symbol:  "delete"
                    label:   wipeLatch.armed ? "Wipe all?" : ""
                    onActivated: wipeLatch.trigger()
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: Clipboard.count === 0
            text: Translation.tr("Copy something and it'll show up here — text or images.")
            variant: "caption"
            emphasis: "dim"
            wrapMode: Text.WordWrap
        }

        ClipboardList {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, root.listRoom)
            visible: Clipboard.count > 0
            maxListHeight: root.listRoom
            onPicked: stepAside.restart()
        }
    }
}
