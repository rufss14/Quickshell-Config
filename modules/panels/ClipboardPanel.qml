pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── ClipboardPanel ────────────────────────────────────────────────────────────
// Clipboard history, beside the sidebar's clipboard button (SidePanelDock) or under the bar's. Click a row to
// put it back on the clipboard; the panel then steps aside so you can paste. In the shell's Material 3
// Expressive panel shape:
//
//   Header  (Settings › Modules › Clipboard hides it) the title and the count
//   Hero    how much is kept, what the newest entry is, and Wipe (asks twice: it deletes the payloads too)
//   Find    once there are a few entries: a search field (words, any order) and All / Text / Links / Images
//   List    ClipboardList, the same rows the overview draws
//
// Everything real is services/Clipboard; this shows it and calls it.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The room the slot has (SidePanelDock sets it); the list scrolls past it.
    property real maxHeight: Infinity

    readonly property int pad: Tokens.spacingXl
    readonly property color accent: Colors.of(QsWindow.window).primary
    implicitWidth: Tokens.sideCardUnit * 8
    implicitHeight: Math.min(root.maxHeight, col.implicitHeight + root.pad * 2)

    // The list's ceiling: what the slot leaves under the header and hero, never more than
    // nine card units (a long history scrolls rather than filling the screen's height).
    readonly property real listRoom: Math.max(Tokens.sideCardUnit * 2, Math.min(Tokens.sideCardUnit * 9,
        root.maxHeight - root.pad * 2 - (head.visible ? head.implicitHeight + col.spacing : 0)
        - hero.implicitHeight - col.spacing - (find.visible ? find.implicitHeight + col.spacing : 0)))

    // What of the history is on show (the panel's own state; ClipboardList filters by it).
    property string query: ""
    property string kind: ""
    readonly property bool finding: Clipboard.count > 4

    readonly property int imageCount: Clipboard.entries.filter(e => e.kind === "image").length
    readonly property string countLine: Clipboard.count === 0 ? Translation.tr("Nothing copied yet")
        : (Clipboard.count === 1 ? Translation.tr("1 item") : Translation.tr("%1 items").arg(Clipboard.count))
          + (root.imageCount > 0 ? " · " + (root.imageCount === 1 ? Translation.tr("1 image")
                                                                  : Translation.tr("%1 images").arg(root.imageCount)) : "")

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
        spacing: Tokens.spacingSm

        PanelHeader {
            id: head
            Layout.fillHeight: false
            visible: Config.panelHeader("clipboard")
            symbol:    "content_paste"
            title:     Translation.tr("Clipboard")
            titleTail: Translation.tr("history")
            accent:    root.accent
            subtitle:  root.countLine
        }

        PanelHero {
            id: hero
            visible: Clipboard.count > 0
            compact: true
            symbol: "content_paste"
            shape: "clover"
            active: true
            turning: false
            accent: root.accent
            title: root.countLine
            line: Translation.tr("Click one to copy it again")

            // Deletes the stored payloads too, so it asks twice.
            PanelButton {
                capsule: true
                variant: wipeLatch.armed ? "primary" : "normal"
                accent:  Colors.of(QsWindow.window).danger
                symbol:  "delete"
                label:   wipeLatch.armed ? Translation.tr("Wipe all?") : Translation.tr("Wipe")
                onActivated: wipeLatch.trigger()
            }
        }

        PanelEmpty {
            visible: Clipboard.count === 0
            symbol: "content_paste"
            shape: "clover"
            title: Translation.tr("Nothing copied yet")
            text: Translation.tr("Copy something and it'll show up here — text or images.")
        }

        ColumnLayout {
            id: find
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.finding
            spacing: Tokens.spacingSm

            InputField {
                id: search
                Layout.fillWidth: true
                icon: "search"
                placeholder: Translation.tr("Search the history")
                onEdited: function (v) { root.query = v }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                Repeater {
                    model: [
                        { value: "",      label: Translation.tr("All"),    symbol: "inventory_2" },
                        { value: "text",  label: Translation.tr("Text"),   symbol: "text_fields" },
                        { value: "link",  label: Translation.tr("Links"),  symbol: "link" },
                        { value: "image", label: Translation.tr("Images"), symbol: "image" }
                    ]
                    delegate: ChipButton {
                        required property var modelData
                        Layout.fillWidth: true
                        symbol: modelData.symbol
                        label: modelData.label
                        on: root.kind === modelData.value
                        tint: root.accent
                        onActivated: root.kind = modelData.value
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacingMd
            Layout.bottomMargin: Tokens.spacingMd
            visible: Clipboard.count > 0 && clips.count === 0
            horizontalAlignment: Text.AlignHCenter
            text: root.query !== "" ? Translation.tr("Nothing matches “%1”").arg(root.query) : Translation.tr("Nothing of that kind")
            variant: "caption"
            emphasis: "dim"
            elide: Text.ElideRight
        }

        ClipboardList {
            id: clips
            query: root.finding ? root.query : ""
            kind: root.finding ? root.kind : ""
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, root.listRoom)
            visible: Clipboard.count > 0
            maxListHeight: root.listRoom
            onPicked: stepAside.restart()
        }
    }
}
