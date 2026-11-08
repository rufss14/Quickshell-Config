import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/setupplan.js" as Plan
import "../../state"

// ── SetupFlow ─────────────────────────────────────────────────────────────────
// The whole of setup as ONE screen and ONE button — what Settings › Setup embeds, for coming back to it
// later. (The first-run window is the same plan, paged: SetupWizard.) A short scan of the machine, a
// checklist with the recommended steps ticked, "Set up N things", then the run and its recap (SetupRun).
//
//   scan   a look at the machine (Setup.scan + the probes) — a second or two
//   plan   what it found, the checklist, the one button
//   run    the checklist as a timeline            (SetupRun)
//   done   the recap                              (SetupRun)
//
// Everything that can be decided is in services/setupplan.js (tested) and Setup.qml (facts, plan, runner);
// this file shows it and calls functions. Recommended | Custom is the only mode switch: Custom lists every
// step (the optional extras, and the finished ones, to run again) and lets a Hyprland style be chosen.
//
// ── Root, once ────────────────────────────────────────────────────────────────
// A plan that needs root asks ONCE, before it starts (SetupPassword): the password typed here is reused by
// every step; empty with a polkit agent running, the system's own dialog asks instead. Never stored.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The Settings page embeds it uncapped; the first-run card caps the list and scrolls it.
    property bool embedded: false
    property real listMax: 330
    signal closeRequested()

    implicitHeight: col.implicitHeight
    implicitWidth: col.implicitWidth

    property bool custom: false
    readonly property string password: pw.password

    // A run and its recap come first: finishing starts a re-check, which must not blank the recap.
    readonly property string stage: Setup.run.active ? "run"
                                  : Setup.run.done ? "done"
                                  : !Setup.ready ? "scan" : "plan"

    // Recommended hides the extras and the finished steps; Custom lists them all.
    readonly property var shown: Setup.steps.filter(s => root.custom || (s.group !== "extras" && s.state !== "done"))
    readonly property var finished: Setup.steps.filter(s => s.state === "done" && s.group !== "extras")
    readonly property int extrasCount: Setup.steps.filter(s => s.group === "extras" && s.state !== "done").length

    readonly property bool needPw: Setup.plan.root && !Setup.polkitReady
    readonly property bool canStart: Setup.plan.count > 0 && !Setup.fatalBlock && !Setup.busy && !SudoLock.locked

    function start() {
        if (root.needPw && root.password.length === 0) { pw.focusField(); return }
        Setup.startPlan(root.password)
    }
    Component.onCompleted: SudoLock.check()

    // One line saying what was found: the reassurance that the scan looked at THIS machine.
    readonly property string foundLine: {
        const f = Setup.facts
        const bits = []
        if (f.arch) bits.push("Arch Linux")
        if (f.hyprland) bits.push("Hyprland " + f.hyprland)
        if (f.quickshell) bits.push("Quickshell " + f.quickshell)
        if (f.gpu) bits.push(f.gpu + " graphics")
        if (f.aurHelper !== "none") bits.push(f.aurHelper)
        return bits.join("  ·  ")
    }
    readonly property var versionWarnings: Setup.compat.filter(c => c.state === "warn")

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.spacingLg

        // ═══ scan ═══════════════════════════════════════════════════════════
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.stage === "scan"
            spacing: Tokens.spacingMd
            BusyDot { running: root.stage === "scan"; tint: Colors.of(QsWindow.window).primary }
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                text: Translation.tr("Looking at your system…")
                variant: "body"; emphasis: "dim"
            }
        }

        // ═══ plan ═══════════════════════════════════════════════════════════
        ColumnLayout {
            id: planView
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.stage === "plan"
            spacing: Tokens.spacingMd

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingMd

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        text: Setup.plan.count === 0 && Setup.steps.length > 0 && root.shown.length === 0
                              ? "Everything is set up"
                              : "Here's what I'd do"
                        variant: "title"; font.weight: Font.DemiBold
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        visible: root.foundLine !== ""
                        text: "Found  " + root.foundLine
                        variant: "caption"; emphasis: "dim"; elide: Text.ElideRight
                    }
                }
                SegmentSwitch {
                    // Two text-only segments, nothing to fall back to: the width has to hold
                    // "Recommended" — 190 elided it to "Recomm…".
                    Layout.preferredWidth: 260
                    Layout.alignment: Qt.AlignVCenter
                    model: [{ value: false, label: "Recommended" }, { value: true, label: "Custom" }]
                    current: root.custom
                    onPicked: function (v) {
                        root.custom = v
                        if (!v) Setup.selectRecommended()
                    }
                }
            }

            // What stops it, or is worth knowing first.
            Repeater {
                model: Setup.blockers
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool fatal: modelData.level === "fatal"
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    implicitHeight: bRow.implicitHeight + Tokens.spacingMd * 2
                    radius: Tokens.radiusSm
                    color: Colors.of(QsWindow.window).alpha(fatal ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).warning, 0.12)
                    border.width: Tokens.borderWidth
                    border.color: Colors.of(QsWindow.window).alpha(fatal ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).warning, 0.32)
                    RowLayout {
                        id: bRow
                        anchors.fill: parent
                        anchors.margins: Tokens.spacingMd
                        spacing: Tokens.spacingMd
                        MaterialIcon {
                            name: fatal ? "error" : "warning"; fill: 1
                            color: fatal ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).warning
                            font.pixelSize: Tokens.iconSm
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 0
                            text: modelData.text
                            variant: "caption"; wrapMode: Text.WordWrap
                        }
                        PanelButton {
                            visible: fatal
                            variant: "ghost"
                            accent: Colors.of(QsWindow.window).primary
                            symbol: "refresh"; label: "Re-check"
                            onActivated: Setup.recheck()
                        }
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: root.versionWarnings.length > 0
                text: root.versionWarnings.map(c => c.label + " " + c.have + " (tested on " + c.want + ")").join("  ·  ")
                      + " — newer versions very likely work; if something looks off, this is the first thing to check."
                variant: "caption"; color: Colors.of(QsWindow.window).warning; wrapMode: Text.WordWrap
            }

            // ── The checklist ────────────────────────────────────────────────
            // The scrollbar is a SIBLING of the Flickable (it anchors to it; as a child it would anchor to a
            // non-sibling and the shell would warn at every start).
            Item {
                id: listBox
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: Math.min(root.listMax, listCol.implicitHeight)
                Behavior on Layout.preferredHeight {
                    NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
                }

            Flickable {
                id: listFlick
                anchors.fill: parent
                contentHeight: listCol.implicitHeight
                contentWidth: width
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Column {
                    id: listCol
                    width: listFlick.width
                    spacing: Tokens.spacingXs

                    Repeater {
                        model: ScriptModel { values: root.shown; objectProp: "id" }
                        delegate: Column {
                            id: entry
                            required property var modelData
                            required property int index
                            width: listCol.width
                            spacing: Tokens.spacingXs

                            SetupStepRow {
                                width: parent.width
                                step: entry.modelData
                                allowRedo: root.custom
                                heading: entry.index === 0 || root.shown[entry.index - 1].group !== entry.modelData.group
                                         ? (entry.modelData.group === "essentials" ? "Essentials"
                                            : entry.modelData.group === "yours" ? "Make it yours" : "Optional extras")
                                         : ""
                            }
                            // How to wire Hyprland in — outside the row, so tapping it doesn't also tick the row.
                            SegmentSwitch {
                                width: parent.width
                                visible: root.custom && entry.modelData.id === "hypr" && Setup.isSelected("hypr")
                                height: visible ? implicitHeight : 0
                                model: [{ value: "minimal", label: "Add one file to my config" }, { value: "full", label: "Replace with the bundled config" }]
                                current: Setup.hyprMode
                                onPicked: function (v) { Setup.hyprModeChoice = v }
                            }
                        }
                    }

                    // The finished ones, in a line — not a list of things to read past.
                    StyledText {
                        width: parent.width
                        topPadding: Tokens.spacingSm
                        visible: !root.custom && root.finished.length > 0
                        text: "Already set up:  " + root.finished.map(s => s.title).join("  ·  ")
                        variant: "caption"; emphasis: "dim"; wrapMode: Text.WordWrap
                    }
                    StyledText {
                        width: parent.width
                        visible: !root.custom && root.extrasCount > 0
                        text: root.extrasCount + " optional extras (Spotify lyrics, Wallpaper Engine, translation…) are under Custom."
                        variant: "caption"; emphasis: "dim"; wrapMode: Text.WordWrap
                    }
                }
            }
            Scrollbar { flickable: listFlick }
            }

            // ── Root, asked once ─────────────────────────────────────────────
            SetupPassword {
                id: pw
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: Setup.plan.root && Setup.plan.count > 0
                onSubmitted: if (root.canStart) root.start()
            }

            // Steps that were ticked but can't run.
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: Setup.plan.blocked.length > 0
                text: Setup.plan.blocked.map(b => b.why).join("  ·  ")
                variant: "caption"; color: Colors.of(QsWindow.window).warning; wrapMode: Text.WordWrap
            }

            // ── The one button ───────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    text: Setup.plan.count === 0 ? ""
                        : Setup.plan.count + (Setup.plan.count === 1 ? " step" : " steps") + "  ·  " + Plan.etaText(Setup.plan.eta)
                    variant: "caption"; emphasis: "dim"
                }
                PanelButton {
                    visible: root.embedded === false && Setup.plan.count === 0
                    variant: "ghost"
                    accent: Colors.of(QsWindow.window).primary
                    label: Translation.tr("Close")
                    onActivated: root.closeRequested()
                }
                PanelButton {
                    visible: Setup.plan.count > 0 || root.embedded
                    variant: "primary"
                    accent: Colors.of(QsWindow.window).primary
                    label: Setup.plan.count === 0 ? "Nothing selected"
                         : Setup.plan.count === 1 ? "Set up 1 thing" : "Set up " + Setup.plan.count + " things"
                    enabled: root.canStart
                    onActivated: root.start()
                }
            }
        }

        // ═══ run + recap ════════════════════════════════════════════════════
        SetupRun {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.stage === "run" || root.stage === "done"
            embedded: root.embedded
            listMax: root.listMax + 60
            password: root.password
            onCloseRequested: root.closeRequested()
        }
    }
}
