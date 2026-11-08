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

// ── WizardHyprlandPage ── part of SetupWizard.qml; `wizard` is the SetupWizard it belongs to. ──
WizardPage {
    id: wizardHyprlandPage
    required property var wizard
    property alias p3: p3
    host: wizard
    idx: 3
    ViewEnter { target: p3; active: wizard.on(3); rise: Tokens.spacingMd }
    ColumnLayout {
        id: p3
        anchors.fill: parent
        spacing: Tokens.spacingMd

        readonly property var ids: ["hypr", "autostart"]
        readonly property var t: wizard.topic(p3.ids)
        // What suits this machine: your own config is left alone and gets one file.
        readonly property string suggested: Plan.hyprMode(Setup.facts.hyprConfig)

        WizardPageHead {
            icon: "tune"
            lead: "Wire it into"; tail: "Hyprland"
            badge: "optional"
            status: Setup.hyprConfigActive ? "The bundled config is active"
                  : Setup.hyprMinimalActive ? "quicktest.lua is in place"
                  : "Keybinds, window rules and autostart"
            done: Setup.hyprConfigActive || Setup.hyprMinimalActive
            shown: wizard.on(3)
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd

            WizardChoice {
                Layout.fillWidth: true
                Layout.fillHeight: true
                icon: "tune"
                title: Translation.tr("Keep my config")
                note: "Adds one file, quicktest.lua, with just the shell's keybinds and rules. Nothing of yours is touched."
                suggested: p3.suggested === "minimal"
                picked: Setup.hyprMode === "minimal"
                shown: wizard.on(3)
                pops: 0
                onChosen: Setup.hyprModeChoice = "minimal"
            }
            WizardChoice {
                Layout.fillWidth: true
                Layout.fillHeight: true
                icon: "settings"
                title: Translation.tr("Bundled config")
                note: "The maintainer's whole setup — monitors, keybinds, animations, rules. Yours is backed up first."
                suggested: p3.suggested === "full"
                picked: Setup.hyprMode === "full"
                shown: wizard.on(3)
                pops: 1
                onChosen: Setup.hyprModeChoice = "full"
            }
        }

        WizardStepGroup { ids: p3.ids; shown: wizard.on(3); base: 2 }

        // The way back: what was there before is saved, and restoring it is itself undoable.
        SetupRestore { shown: wizard.on(3); pops: 4 }

        // Then one line in your own config — copyable.
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: Setup.hyprMode === "minimal"
            implicitHeight: reqRow.implicitHeight + Tokens.spacingMd * 2
            radius: Tokens.radiusSm
            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.05)
            RowLayout {
                id: reqRow
                anchors.fill: parent
                anchors.margins: Tokens.spacingMd
                spacing: Tokens.spacingMd
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 2
                    StyledText {
                        text: Translation.tr("Then add this near the top of your own hyprland.lua")
                        variant: "caption"; emphasis: "dim"
                    }
                    StyledText {
                        text: Setup.hyprMinimalRequireLine
                        variant: "body"; font.family: Tokens.fontMono
                    }
                }
                PanelButton {
                    variant: "ghost"
                    accent: Colors.of(QsWindow.window).primary
                    symbol: "content_copy"; label: "Copy"
                    onActivated: Clipboard.copyText(Setup.hyprMinimalRequireLine)
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
