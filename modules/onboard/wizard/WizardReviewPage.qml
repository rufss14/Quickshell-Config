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
import ".."

// ── WizardReviewPage ── part of SetupWizard.qml; `wizard` is the SetupWizard it belongs to. ──
WizardPage {
    id: wizardReviewPage
    required property var wizard
    property alias p7: p7
    property alias pw: pw
    host: wizard
    idx: 7
    ViewEnter { target: p7; active: wizard.on(7); rise: Tokens.spacingMd }
    ColumnLayout {
        id: p7
        anchors.fill: parent
        spacing: Tokens.spacingMd

        // ── Before it starts ─────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: !wizard.inRun
            spacing: Tokens.spacingMd

            // Nothing to install: say so like it is good news, and offer what to do next.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: Setup.plan.count === 0
                spacing: Tokens.spacingMd

                Item {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 200
                    Layout.preferredHeight: 108
                    // A few small cookies burst out of the big one.
                    Repeater {
                        model: [
                            { x: 10, y: 14, s: 20 }, { x: 160, y: 8, s: 26 }, { x: 28, y: 74, s: 16 },
                            { x: 168, y: 70, s: 20 }, { x: 88, y: 0, s: 14 }
                        ]
                        delegate: Scallop {
                            id: conf
                            required property var modelData
                            required property int index
                            x: modelData.x; y: modelData.y
                            width: modelData.s; height: modelData.s
                            points: 5 + index; petalDepth: 0.16
                            fillColor: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.14)
                            strokeColor: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.30)
                            PopIn { id: confPop; active: wizard.on(7) && Setup.plan.count === 0; index: conf.index + 2 }
                            opacity: confPop.opacity
                            scale: confPop.scale
                            RotationAnimator on rotation {
                                from: 0; to: conf.index % 2 === 0 ? 360 : -360
                                duration: 12000 + conf.index * 3000; loops: Animation.Infinite
                                running: Config.motionEnabled && wizard.on(7)
                            }
                        }
                    }
                    SetupCookie {
                        anchors.centerIn: parent
                        size: 84
                        name: "check"
                        lit: true
                        turning: true
                        tint: Colors.of(QsWindow.window).primary
                        PopIn { id: bigPop; active: wizard.on(7) && Setup.plan.count === 0 }
                        opacity: bigPop.opacity
                        scale: bigPop.scale
                    }
                }
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Tokens.spacingSm
                    StyledText { text: "You're"; variant: "headline"; font.weight: Font.DemiBold }
                    StyledText { text: wizard.anyTodo ? "good to go" : "all set"; variant: "headline"; font.weight: Font.DemiBold; color: Colors.of(QsWindow.window).primary }
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: 440
                    horizontalAlignment: Text.AlignHCenter
                    text: wizard.anyTodo
                        ? "Nothing is ticked. Go back and tick what you want, or carry on — it all works without them."
                        : "Everything you asked for is in place. A few places to start:"
                    variant: "body"; emphasis: "muted"; wrapMode: Text.WordWrap
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: !wizard.anyTodo
                    spacing: Tokens.spacingSm
                    Repeater {
                        model: [
                            { i: "wallpaper", t: "Pick a wallpaper", n: "Colours follow it", act: "wallpaper" },
                            { i: "palette", t: "Tune the colours", n: "Schemes and presets", act: "colorScheme" },
                            { i: "settings", t: "Open Settings", n: "Everything else", act: "settings" }
                        ]
                        delegate: WizardNext {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            icon: modelData.i
                            title: modelData.t
                            note: modelData.n
                            shown: wizard.on(7) && Setup.plan.count === 0
                            pops: index + 4
                            onPicked: {
                                wizard.closeRequested()
                                if (modelData.act === "settings") UiState.openSettingsTo("SetupPage.qml")
                                else UiState.togglePanel(modelData.act)
                            }
                        }
                    }
                }
            }

            // The keys that open things — read from YOUR Hyprland config, not assumed.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: Setup.plan.count === 0 && !wizard.anyTodo && wizard.tryBinds.length > 0
                spacing: Tokens.spacingSm
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Your keys")
                    variant: "caption"; emphasis: "dim"; font.letterSpacing: 1
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingMd
                    Repeater {
                        model: wizard.tryBinds
                        delegate: Row {
                            required property var modelData
                            spacing: Tokens.spacingSm
                            WizardKeyCombo { combo: modelData.combo; anchors.verticalCenter: parent.verticalCenter }
                            StyledText { text: modelData.label; variant: "caption"; emphasis: "dim"; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                }
            }

            // Something to install: the plan, as numbers and a timeline.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: Setup.plan.count > 0
                spacing: Tokens.spacingMd

                WizardPageHead {
                    icon: "play_arrow"
                    lead: "Ready when"; tail: "you are"
                    status: "Review, then one button does all of it"
                    shown: wizard.on(7)
                }

                WizardBlockers { Layout.fillWidth: true; Layout.fillHeight: false }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    uniformCellSizes: true
                    WizardStat {
                        Layout.fillWidth: true
                        big: String(Setup.plan.count)
                        caption: Setup.plan.count === 1 ? "step" : "steps"
                        shown: wizard.on(7); pops: 0
                    }
                    WizardStat {
                        Layout.fillWidth: true
                        big: Plan.etaText(Setup.plan.eta).replace("about ", "~").replace("under a minute", "< 1 min")
                        caption: "estimated"
                        shown: wizard.on(7); pops: 1
                    }
                    WizardStat {
                        Layout.fillWidth: true
                        big: !Setup.plan.root ? "None" : Setup.polkitReady && pw.password.length === 0 ? "Dialog" : "Once"
                        caption: "password"
                        shown: wizard.on(7); pops: 2
                    }
                }

                // The whole plan in order, dependencies included, on a line.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    implicitHeight: planCol.implicitHeight + Tokens.spacingLg * 2
                    radius: Tokens.radiusPill
                    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.035)
                    border.width: Tokens.borderWidth
                    border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)

                    Column {
                        id: planCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.spacingLg
                        spacing: 0

                        Repeater {
                            model: ScriptModel { values: Setup.plan.run; objectProp: "id" }
                            delegate: Item {
                                id: pr
                                required property var modelData
                                required property int index
                                readonly property bool last: pr.index === Setup.plan.run.length - 1
                                width: planCol.width
                                height: 34
                                PopIn { id: prPop; active: wizard.on(7); index: pr.index + 3 }
                                opacity: prPop.opacity

                                // The line, then the node on it.
                                Rectangle {
                                    visible: !pr.last
                                    x: 9; y: 22
                                    width: 2; height: 24
                                    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.30)
                                }
                                Rectangle {
                                    x: 3; y: 11
                                    width: 14; height: 14; radius: 7
                                    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.18)
                                    border.width: 2
                                    border.color: Colors.of(QsWindow.window).primary
                                    scale: prPop.scale
                                }
                                RowLayout {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 30
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Tokens.spacingMd
                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 0
                                        text: pr.modelData.title + (pr.modelData.auto ? "  ·  needed by another step" : "")
                                        variant: "body"; elide: Text.ElideRight
                                    }
                                    MaterialIcon {
                                        visible: pr.modelData.root
                                        name: "lock"; color: Colors.of(QsWindow.window).fgDim
                                        font.pixelSize: Tokens.iconSm - 2
                                    }
                                    StyledText {
                                        text: Plan.etaText(pr.modelData.eta).replace("about ", "~")
                                        variant: "caption"; emphasis: "dim"
                                    }
                                }
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    visible: Setup.plan.blocked.length > 0
                    text: Setup.plan.blocked.map(b => b.why).join("  ·  ")
                    variant: "caption"; color: Colors.of(QsWindow.window).warning; wrapMode: Text.WordWrap
                }

                // Root, asked once.
                SetupPassword {
                    id: pw
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: Setup.plan.root
                    onSubmitted: if (wizard.canStart) wizard.start()
                }
            }
        }

        // ── Running, and the recap ───────────────────────────────
        SetupRun {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: wizard.inRun
            listMax: 280
            password: pw.password
            onCloseRequested: wizard.closeRequested()
        }
    }
}
