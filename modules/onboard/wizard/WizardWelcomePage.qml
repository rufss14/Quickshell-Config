import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/setupplan.js" as Plan
import "../../../state"
import "../wizard"

// ── WizardWelcomePage ── part of SetupWizard.qml; `wizard` is the SetupWizard it belongs to. ──
WizardPage {
    id: wizardWelcomePage
    required property var wizard
    property alias p0: p0
    host: wizard
    idx: 0
    ViewEnter { target: p0; active: wizard.on(0); rise: Tokens.spacingMd }
    ColumnLayout {
        id: p0
        anchors.fill: parent
        spacing: Tokens.spacingMd

        // The hero: the shell's own cookie, breathing and turning slowly, with two small ones
        // drifting the other way — and the logo, which never turns.
        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 220
            Layout.preferredHeight: 124

            PopIn { id: heroPop; active: wizard.on(0) }

            Scallop {
                id: bigCookie
                anchors.centerIn: parent
                width: 116; height: 116
                points: 9; petalDepth: 0.11
                fillColor: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.14)
                strokeColor: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.34)
                opacity: heroPop.opacity
                scale: heroPop.scale
                RotationAnimator on rotation {
                    from: 0; to: 360; duration: 40000; loops: Animation.Infinite
                    running: Config.motionEnabled && wizard.on(0)
                }
            }
            Scallop {
                x: 6; y: 70
                width: 34; height: 34
                points: 7; petalDepth: 0.14
                fillColor: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.10)
                strokeColor: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.26)
                opacity: heroPop.opacity
                RotationAnimator on rotation {
                    from: 360; to: 0; duration: 22000; loops: Animation.Infinite
                    running: Config.motionEnabled && wizard.on(0)
                }
            }
            Scallop {
                x: 178; y: 8
                width: 24; height: 24
                points: 6; petalDepth: 0.16
                fillColor: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.10)
                strokeColor: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.26)
                opacity: heroPop.opacity
                RotationAnimator on rotation {
                    from: 0; to: 360; duration: 18000; loops: Animation.Infinite
                    running: Config.motionEnabled && wizard.on(0)
                }
            }
            Image {
                anchors.centerIn: parent
                source: Icons.logo("quickshell.svg")
                sourceSize: Qt.size(56, 56)
                width: 56; height: 56
                fillMode: Image.PreserveAspectFit
                smooth: true
                opacity: heroPop.opacity
                scale: heroPop.scale
            }
        }

        Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacingSm
            StyledText { text: "Welcome to"; variant: "headline"; font.weight: Font.DemiBold }
            StyledText { text: "Quicktest"; variant: "headline"; font.weight: Font.DemiBold; color: Colors.of(QsWindow.window).primary }
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: 440
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("A Quickshell desktop for Hyprland. A few things to set up — none of them stop the shell running.")
            variant: "body"; emphasis: "muted"; wrapMode: Text.WordWrap
        }

        // What the scan found: this is THIS machine, not a generic checklist.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: chipFlow.implicitHeight
            // Centred by padding, not by sizing it to its own implicit width (which starts at one chip and
            // would never grow): a single row has padding (room - content) / 2; a wrapped one has none.
            Flow {
                id: chipFlow
                width: parent.width
                leftPadding: Math.max(0, (parent.width - chipFlow.childrenRect.width) / 2)
                spacing: Tokens.spacingSm
                Repeater {
                    model: Setup.ready ? wizard.scanChips : []
                    delegate: WizardChip {
                        required property var modelData
                        required property int index
                        text: modelData.text
                        level: modelData.level
                        shown: wizard.on(0)
                        pops: index
                    }
                }
            }
            RowLayout {
                anchors.centerIn: parent
                visible: !Setup.ready
                spacing: Tokens.spacingSm
                BusyDot { running: !Setup.ready; tint: Colors.of(QsWindow.window).primary }
                StyledText { text: "Looking at your system…"; variant: "caption"; emphasis: "dim" }
            }
        }

        WizardBlockers { Layout.fillWidth: true; Layout.fillHeight: false }

        // Coming back to it: what has drifted since. Only after the first time through — on a fresh
        // machine the plan says all of this already.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: Setup.ready && Config.setupSeen
            spacing: Tokens.spacingSm
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                MaterialIcon {
                    name: Setup.healthIssues.length === 0 ? "check_circle" : "info"
                    fill: 1
                    color: Setup.healthIssues.length === 0 ? Verdict.tint(true) : Colors.of(QsWindow.window).warning
                    font.pixelSize: Tokens.iconSm
                }
                StyledText {
                    text: Setup.healthIssues.length === 0 ? "Health check: nothing has drifted"
                        : "Health check: " + Setup.healthIssues.length + (Setup.healthIssues.length === 1 ? " thing needs" : " things need") + " a look"
                    variant: "label"; font.weight: Font.Medium
                }
            }
            Repeater {
                model: ScriptModel { values: Setup.healthIssues; objectProp: "id" }
                delegate: WizardFinding {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    issue: modelData
                    shown: wizard.on(0)
                    pops: index + 3
                    onPicked: wizard.goto(modelData.page)
                }
            }
        }

        // How ready it already is.
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: Setup.ready
            implicitHeight: readyRow.implicitHeight + Tokens.spacingLg * 2
            radius: Tokens.radiusPill
            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.035)
            border.width: Tokens.borderWidth
            border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
            PopIn { id: readyPop; active: wizard.on(0); index: 4 }
            opacity: readyPop.opacity
            scale: readyPop.scale

            RowLayout {
                id: readyRow
                anchors.fill: parent
                anchors.margins: Tokens.spacingLg
                spacing: Tokens.spacingLg

                RadialGauge {
                    Layout.preferredWidth: 60
                    Layout.preferredHeight: 60
                    thickness: 6
                    value: wizard.readyRatio
                    accent: wizard.readyRatio >= 1 ? Verdict.tint(true) : Colors.of(QsWindow.window).primary
                    StyledText {
                        anchors.centerIn: parent
                        text: wizard.readyCount + "/" + wizard.essentials.length
                        variant: "label"; font.weight: Font.DemiBold
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        text: wizard.readyRatio >= 1 ? "Everything essential is already in place"
                            : (wizard.essentials.length - wizard.readyCount) + (wizard.essentials.length - wizard.readyCount === 1 ? " essential thing" : " essential things") + " to set up"
                        variant: "body"; font.weight: Font.DemiBold; wrapMode: Text.WordWrap
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        text: wizard.readyRatio >= 1 ? "Look around, or run it again later from Settings › Setup."
                            : Setup.defaultIds.length > 0 ? "The recommended ones are ticked for you — about " + Plan.etaText(Setup.plan.eta).replace("about ", "") + " in all."
                            : "Nothing recommended is left; the rest is optional."
                        variant: "caption"; emphasis: "dim"; wrapMode: Text.WordWrap
                    }
                }
            }
        }

        // The topics — each is a link to its page.
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            columns: 6
            columnSpacing: Tokens.spacingSm
            uniformCellWidths: true
            Repeater {
                model: [
                    { i: "inventory_2", t: "Packages",     p: 1, ids: ["core", "aurhelper", "aur", "clips", "gamemode"], opt: false },
                    { i: "widgets",     t: "Morphing",     p: 2, ids: ["blob"], opt: true },
                    { i: "tune",        t: "Hyprland",     p: 3, ids: ["hypr", "autostart"], opt: true },
                    { i: "extension",   t: "Integrations", p: 4, ids: ["spotify", "wpe", "argos", "songrec", "awww", "ddc", "beatsync", "discordkeys"], opt: true },
                    { i: "palette",     t: "Colours",      p: 5, ids: ["themes", "colours"], opt: true },
                    { i: "auto_awesome", t: "Style",       p: 6, ids: [], opt: true }
                ]
                delegate: WizardTopic {
                    host: wizard
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    icon: modelData.i
                    title: modelData.t
                    info: wizard.topic(modelData.ids)
                    isOptional: modelData.opt
                    shown: wizard.on(0)
                    pops: index + 5
                    onPicked: wizard.goto(modelData.p)
                }
            }
        }

        // Escape hatch for someone who wants to run with an unfinished setup and never be
        // nagged again — setupSeen alone doesn't cover that; see shell.qml's _maybeShowFirstRun.
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: false
            spacing: Tokens.spacingSm

            Toggle {
                checked: Config.setupAutoOpenDisabled
                onToggled: Config.setupAutoOpenDisabled = !Config.setupAutoOpenDisabled
            }
            StyledText {
                text: Translation.tr("Don't show this automatically again")
                variant: "caption"; emphasis: "dim"
            }
        }
    }
}
