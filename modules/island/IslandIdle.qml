import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── IslandIdle ────────────────────────────────────────────────────────────────
// The idle rules, edited on the island: IslandDesk grows this out of its "When I'm away" card until it fills
// the page. Rules on the left, one card each, the chosen one a loud pill; the chosen rule on the right: how
// long (a numeral that rolls, a stepper, the usual lengths), what it does (a card per action), a command's own
// text, and what to know about it.
//
// Everything real is `Inactivity` (the rules, the monitors, the warning) and `inactivity.js` (what a rule may
// contain); this shows them and calls them.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    signal closeRequested()

    readonly property var palette: Colors.of(QsWindow.window)

    // The rule being edited: the one picked, else the first; none when there are no rules.
    property string selectedId: ""
    readonly property var rule: Inactivity.rules.find(r => r.id === root.selectedId) ?? Inactivity.rules[0] ?? null
    property bool confirmDelete: false
    onRuleChanged: root.confirmDelete = false

    // Why this rule cannot run, and what is worth knowing before it does.
    readonly property string blocked: root.rule ? Inactivity.blocker(root.rule.action, root.rule.command) : ""
    readonly property string note: !root.rule ? ""
        : root.blocked !== "" ? root.blocked
        : Inactivity.warns(root.rule.action) ? Translation.tr("Warns for %1 s first. Any input cancels it.").arg(Inactivity.warnSeconds)
        : root.rule.action === "screenoff" ? Translation.tr("Wakes on the next key or mouse move.")
        : !Session.canHibernate ? Translation.tr("Hibernate needs swap and a resume device, and this machine has none set up.")
        : ""

    // What explains a quiet machine: held awake, what last ran, else the summary.
    readonly property string statusLine:
          Idle.inhibited && Inactivity.enabled ? Translation.tr("Paused: %1").arg(Idle.reasonText.toLowerCase())
        : Inactivity.last ? Translation.tr("Last ran: %1, %2").arg(Inactivity.describe(Inactivity.last.rule))
                                .arg(Qt.formatDateTime(new Date(Inactivity.last.at), "HH:mm"))
        : Inactivity.summary

    // One shape per action, so a rule is known by its badge before it is read.
    readonly property var shapes: ({
        lock: "squircle", screenoff: "clover", suspend: "cookie9", hibernate: "sunny",
        logout: "pentagon", poweroff: "hexagon", command: "cookie12"
    })

    function addRule() {
        const before = new Set(Inactivity.rules.map(r => r.id))
        Inactivity.addRule()
        const made = Inactivity.rules.find(r => !before.has(r.id))
        if (made) root.selectedId = made.id
    }

    // "Can this machine hibernate" is asked, not assumed (logind, once per open).
    Component.onCompleted: Session.probe()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingLg
        spacing: Tokens.spacingMd

        // ── The master switch, and the way back ───────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd

            IslandBadge {
                symbol: "bedtime"
                shape: Inactivity.enabled ? (Idle.inhibited ? "squircle" : "cookie9") : "circle"
                filled: Inactivity.enabled && !Idle.inhibited
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: 0
                StyledText {
                    text: Translation.tr("When I'm away")
                    variant: "title"
                    font.weight: Font.DemiBold
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.statusLine
                    variant: "caption"
                    emphasis: "muted"
                    elide: Text.ElideRight
                }
            }
            StyledText {
                text: Inactivity.enabled ? Translation.tr("On") : Translation.tr("Off")
                variant: "label"
                emphasis: "muted"
            }
            Toggle {
                checked: Inactivity.enabled
                accessibleName: Translation.tr("Run the idle rules")
                onToggled: Inactivity.setEnabled(!Inactivity.enabled)
            }
            ChipButton {
                symbol: "close"
                tonal: true
                Accessible.name: Translation.tr("Back to Desk")
                onActivated: root.closeRequested()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingLg

            // ── The rules ─────────────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: false
                Layout.preferredWidth: Tokens.spacingXl * 15
                Layout.fillHeight: true
                spacing: Tokens.spacingSm

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    interactive: list.contentHeight > list.height
                    boundsBehavior: Flickable.StopAtBounds
                    spacing: Tokens.spacingSm
                    model: ScriptModel {
                        values: Inactivity.rules
                        objectProp: "id"
                    }

                    // A new rule rises into its place and the rest make room; a removed one shrinks away.
                    add: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "scale"; from: 0.8; to: 1; duration: Motion.spatial; easing.type: Motion.travel }
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.standard }
                        }
                    }
                    remove: Transition {
                        ParallelAnimation {
                            NumberAnimation { property: "scale"; to: 0.8; duration: Motion.standard; easing.type: Motion.travel }
                            NumberAnimation { property: "opacity"; to: 0; duration: Motion.standard }
                        }
                    }
                    displaced: Transition {
                        NumberAnimation { properties: "y"; duration: Motion.spatial; easing.type: Motion.travel }
                    }

                    delegate: Item {
                        id: entry
                        required property var modelData
                        width: list.width
                        height: card.implicitHeight

                        OptionCard {
                            id: card
                            width: parent.width
                            symbol: Inactivity.actionChips.find(c => c.value === entry.modelData.action)?.symbol ?? "bedtime"
                            shape: root.shapes[entry.modelData.action] ?? "cookie9"
                            label: Inactivity.describe(entry.modelData)
                            detail: !entry.modelData.enabled ? Translation.tr("Off")
                                  : Inactivity.warns(entry.modelData.action) ? Translation.tr("Warns first") : ""
                            on: root.rule !== null && root.rule.id === entry.modelData.id
                            opacity: entry.modelData.enabled && Inactivity.enabled ? 1 : 0.6
                            Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                            onActivated: root.selectedId = entry.modelData.id
                        }
                    }
                }

                ChipButton {
                    Layout.fillWidth: false
                    symbol: "add"
                    label: Translation.tr("Add a rule")
                    tonal: true
                    enabled: Inactivity.rules.length < Inactivity.maxRules
                    onActivated: root.addRule()
                }
            }

            // ── No rules: the way in ──────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.rule === null
                spacing: Tokens.spacingMd

                Item { Layout.fillHeight: true; Layout.fillWidth: true }
                IslandBadge {
                    Layout.alignment: Qt.AlignHCenter
                    size: Tokens.iconXl * 2
                    symbol: "bedtime"
                    shape: "cookie9"
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("No rules yet")
                    variant: "title"
                    font.weight: Font.DemiBold
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("After some minutes without input: lock, turn the screen off, suspend, or run a command of your own.")
                    variant: "caption"
                    emphasis: "muted"
                    wrapMode: Text.Wrap
                }
                Item { Layout.fillHeight: true; Layout.fillWidth: true }
            }

            // ── The chosen rule ───────────────────────────────────────────────
            ColumnLayout {
                id: pane
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.rule !== null
                spacing: Tokens.spacingMd

                // How long: the figure rolls as it changes.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: 0
                        StyledText {
                            text: Translation.tr("After")
                            variant: "caption"
                            emphasis: "muted"
                        }
                        RollText {
                            text: root.rule ? Inactivity.duration(root.rule.minutes) : ""
                            pixelSize: Tokens.fontDisplay * 1.5
                            weight: Font.Bold
                            color: root.palette.fg
                        }
                    }
                    NumberStepper {
                        Layout.alignment: Qt.AlignBottom
                        from: Inactivity.minMinutes
                        to: Inactivity.maxMinutes
                        step: 1
                        value: root.rule ? root.rule.minutes : Inactivity.minMinutes
                        readout: String(value)
                        numberWidth: Tokens.spacingXl * 3
                        onCommit: function (v) { if (root.rule) Inactivity.patchRule(root.rule.id, { minutes: v }) }
                    }
                }
                ChipRow {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    model: [{ value: 5, label: "5" }, { value: 10, label: "10" }, { value: 15, label: "15" },
                            { value: 30, label: "30" }, { value: 60, label: "1 h" }, { value: 120, label: "2 h" }]
                    current: root.rule ? root.rule.minutes : 0
                    onPicked: (value) => { if (root.rule) Inactivity.patchRule(root.rule.id, { minutes: value }) }
                }

                // What it does: a card each, the chosen one a loud pill with its own shape.
                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    columns: 4
                    rowSpacing: Tokens.spacingSm
                    columnSpacing: Tokens.spacingSm
                    uniformCellWidths: true

                    Repeater {
                        model: Inactivity.actionChips
                        delegate: OptionCard {
                            id: choice
                            required property var modelData
                            Layout.fillWidth: true
                            symbol: choice.modelData.symbol
                            shape: root.shapes[choice.modelData.value] ?? "cookie9"
                            label: choice.modelData.value === "command" ? Translation.tr("Command") : choice.modelData.label
                            on: root.rule !== null && root.rule.action === choice.modelData.value
                            enabled: choice.modelData.value === "command"
                                     || Inactivity.blocker(choice.modelData.value, "") === ""
                            onActivated: if (root.rule) Inactivity.patchRule(root.rule.id, { action: choice.modelData.value })
                        }
                    }
                }

                InputField {
                    Layout.fillWidth: true
                    visible: root.rule !== null && root.rule.action === "command"
                    icon: "terminal"
                    mono: true
                    placeholder: "notify-send 'Still there?'"
                    seed: root.rule ? root.rule.command : ""
                    invalid: root.blocked !== ""
                    onCommitted: (value) => { if (root.rule) Inactivity.patchRule(root.rule.id, { command: value }) }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: root.note !== ""
                    text: root.note
                    variant: "caption"
                    emphasis: root.blocked !== "" ? "normal" : "dim"
                    color: root.blocked !== "" ? root.palette.danger : root.palette.fgDim
                    wrapMode: Text.Wrap
                }

                Item { Layout.fillHeight: true; Layout.fillWidth: true }

                // This rule: on or off, or gone. Deleting asks on the row, not by arming a button in place.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd

                    Toggle {
                        checked: root.rule ? root.rule.enabled : false
                        accessibleName: Translation.tr("This rule")
                        onToggled: if (root.rule) Inactivity.patchRule(root.rule.id, { enabled: !root.rule.enabled })
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.rule && root.rule.enabled ? Translation.tr("This rule is on") : Translation.tr("This rule is off")
                        variant: "label"
                        emphasis: "muted"
                    }
                    ChipButton {
                        visible: !root.confirmDelete
                        symbol: "delete"
                        label: Translation.tr("Delete")
                        tonal: true
                        onActivated: root.confirmDelete = true
                    }
                    ChipButton {
                        visible: root.confirmDelete
                        label: Translation.tr("Keep")
                        tonal: true
                        onActivated: root.confirmDelete = false
                    }
                    ChipButton {
                        visible: root.confirmDelete
                        symbol: "delete"
                        label: Translation.tr("Delete rule")
                        solid: true
                        tint: root.palette.danger
                        onActivated: { if (root.rule) Inactivity.removeRule(root.rule.id); root.confirmDelete = false }
                    }
                }
            }
        }
    }
}
