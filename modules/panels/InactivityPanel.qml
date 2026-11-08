pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── InactivityPanel ───────────────────────────────────────────────────────────
// "After N minutes without input, do X": a list of rules, each with its own timeout and
// action — lock, screen off, suspend, hibernate, log out, power off, or a command of
// your own. Beside the sidebar's Idle actions cell (SidePanelDock), or hanging from the
// top bar's pill (BarPanelDock).
//
// The panel recipe: PanelHeader + ActionGroup, tokens throughout, shared widgets
// (Toggle, NumberStepper, ChipRow, InputField, PanelButton). Everything real is
// services/Inactivity (rules, idle monitors, the warning, persistence) and
// services/inactivity.js (what a rule may contain); this shows them and calls them.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The room the slot has (SidePanelDock sets it); the rule list scrolls past it.
    property real maxHeight: Infinity

    readonly property int pad: Tokens.spacingLg
    implicitWidth: Tokens.sideCardUnit * 8
    implicitHeight: Math.min(root.maxHeight, col.implicitHeight + root.pad * 2)

    // What the list may take: what the slot leaves under the header, the switch row and
    // the notes — never less than two card units, so a rule stays editable.
    readonly property real listRoom: Math.max(Tokens.sideCardUnit * 2,
        root.maxHeight - root.pad * 2 - head.implicitHeight - master.implicitHeight
        - notes.implicitHeight - col.spacing * 4)

    // "Can this machine hibernate" is asked, not assumed (logind, once per open).
    Component.onCompleted: Session.probe()

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
            symbol: "pause_circle"
            title: Translation.tr("Idle")
            titleTail: "actions"
            accent: Colors.of(QsWindow.window).primary
            subtitle: Inactivity.summary

            ActionGroup {
                PanelButton {
                    variant: "ghost"
                    symbol: "add"
                    enabled: Inactivity.rules.length < Inactivity.maxRules
                    onActivated: Inactivity.addRule()
                }
            }
        }

        // The master switch: off, no rule runs and none is lost.
        RowLayout {
            id: master
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Run these rules")
                variant: "label"
            }
            Toggle {
                checked: Inactivity.enabled
                onToggled: Inactivity.setEnabled(!Inactivity.enabled)
            }
        }

        // What explains a quiet machine: held awake, nothing set yet, what last ran.
        ColumnLayout {
            id: notes
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingXs

            StyledText {
                Layout.fillWidth: true
                visible: Idle.inhibited
                text: "Paused — " + Idle.reasonText.toLowerCase()
                      + ". Rules wait while the screen is held awake."
                variant: "caption"
                color: Colors.of(QsWindow.window).info
                wrapMode: Text.WordWrap
            }
            StyledText {
                Layout.fillWidth: true
                visible: Inactivity.ready && Inactivity.rules.length === 0
                text: Translation.tr("Add a rule: after some minutes without input, lock, turn the screen off, ")
                      + "suspend, or run a command of your own."
                variant: "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }
            StyledText {
                Layout.fillWidth: true
                visible: Inactivity.last !== null
                text: Inactivity.last
                      ? "Last ran: " + Inactivity.describe(Inactivity.last.rule) + ", "
                        + Qt.formatDateTime(new Date(Inactivity.last.at), "HH:mm")
                      : ""
                variant: "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Math.min(contentHeight, root.listRoom)
            visible: Inactivity.rules.length > 0
            clip: true
            interactive: contentHeight > height
            spacing: Tokens.spacingSm
            model: ScriptModel {
                values: Inactivity.rules
                objectProp: "id"
            }
            delegate: RuleRow {
                width: list.width
            }
        }
    }

    // One rule: on/off, how long, what, and — for a command — which.
    component RuleRow: Rectangle {
        id: row
        required property var modelData

        readonly property string blocked: Inactivity.blocker(row.modelData.action, row.modelData.command)
        readonly property string note: row.blocked !== "" ? row.blocked
            : Inactivity.warns(row.modelData.action)
              ? "Warns for " + Inactivity.warnSeconds + " s first; any input cancels it."
            : row.modelData.action === "screenoff" ? "Wakes on the next key or mouse move."
            : ""

        implicitHeight: inner.implicitHeight + Tokens.spacingMd * 2
        radius: Tokens.radiusSm
        color: Colors.of(QsWindow.window).surfaceContainer
        border.width: Tokens.borderWidth
        border.color: Colors.of(QsWindow.window).outline
        opacity: row.modelData.enabled ? 1 : 0.6
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }

        ColumnLayout {
            id: inner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.spacingMd
            spacing: Tokens.spacingSm

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                Toggle {
                    checked: row.modelData.enabled
                    onToggled: Inactivity.patchRule(row.modelData.id, { enabled: !row.modelData.enabled })
                }
                StyledText { text: "After"; variant: "label"; emphasis: "dim" }
                NumberStepper {
                    from: Inactivity.minMinutes
                    to: Inactivity.maxMinutes
                    step: 1
                    value: row.modelData.minutes
                    readout: Inactivity.duration(row.modelData.minutes)
                    numberWidth: Tokens.sideCardUnit * 0.9
                    onCommit: function (v) { Inactivity.patchRule(row.modelData.id, { minutes: v }) }
                }
                Item { Layout.fillWidth: true }
                PanelButton {
                    variant: "ghost"
                    accent: Colors.of(QsWindow.window).danger
                    symbol: "delete"
                    onActivated: Inactivity.removeRule(row.modelData.id)
                }
            }

            ChipRow {
                Layout.fillWidth: true
                Layout.fillHeight: false
                model: Inactivity.actionChips
                current: row.modelData.action
                onPicked: (value) => Inactivity.patchRule(row.modelData.id, { action: value })
            }

            InputField {
                Layout.fillWidth: true
                visible: row.modelData.action === "command"
                mono: true
                placeholder: "notify-send 'Still there?'"
                seed: row.modelData.command
                invalid: row.blocked !== ""
                onCommitted: (value) => Inactivity.patchRule(row.modelData.id, { command: value })
            }

            StyledText {
                Layout.fillWidth: true
                visible: row.note !== ""
                text: row.note
                variant: "caption"
                emphasis: row.blocked !== "" ? "normal" : "dim"
                color: row.blocked !== "" ? Colors.of(QsWindow.window).danger
                                          : Colors.of(QsWindow.window).fgDim
                wrapMode: Text.WordWrap
            }
        }
    }
}
