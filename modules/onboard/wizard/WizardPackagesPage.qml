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

// ── WizardPackagesPage ── part of SetupWizard.qml; `wizard` is the SetupWizard it belongs to. ──
WizardPage {
    id: wizardPackagesPage
    required property var wizard
    property alias p1: p1
    host: wizard
    idx: 1
    ViewEnter { target: p1; active: wizard.on(1); rise: Tokens.spacingMd }
    ColumnLayout {
        id: p1
        anchors.fill: parent
        spacing: Tokens.spacingMd

        readonly property var ids: ["core", "aurhelper", "aur", "clips", "gamemode"]
        readonly property var t: wizard.topic(p1.ids)

        WizardPageHead {
            icon: "inventory_2"
            lead: "System"; tail: "packages"
            status: p1.t.done ? "Everything is installed" : p1.t.todo + (p1.t.todo === 1 ? " thing" : " things") + " to install"
            done: p1.t.done
            shown: wizard.on(1)
        }

        StyledText {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            text: Translation.tr("The shell itself, its fonts and the tools it calls, from the Arch repositories; then an AUR helper and the ")
                + "few packages that only exist there (pywal); then Clips and Game Mode, if you want them. "
                + "Nothing is installed until the last page."
            variant: "caption"; emphasis: "dim"; wrapMode: Text.WordWrap
        }

        // Preflight: the things that make an install fail, checked before you start.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: preFlow.implicitHeight
            Flow {
                id: preFlow
                width: parent.width
                spacing: Tokens.spacingSm
                Repeater {
                    model: wizard.preflight
                    delegate: WizardChip {
                        required property var modelData
                        required property int index
                        text: modelData.text
                        level: modelData.level
                        shown: wizard.on(1)
                        pops: index
                    }
                }
            }
        }

        WizardStepGroup { ids: p1.ids; shown: wizard.on(1); base: 2 }

        // The graphics driver is picked from the machine, not assumed.
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm
            MaterialIcon { name: "memory"; color: Colors.of(QsWindow.window).fgDim; font.pixelSize: Tokens.iconSm }
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                text: Setup.facts.gpu !== ""
                      ? Setup.facts.gpu + " graphics found — the Vulkan driver installed with them: "
                        + (Setup.facts.vulkan.length > 0 ? Setup.facts.vulkan.join(", ") : "none needed")
                      : "No GPU recognised — a software Vulkan driver will be used"
                variant: "caption"; emphasis: "dim"; wrapMode: Text.WordWrap
            }
        }

        WizardBlockers { Layout.fillWidth: true; Layout.fillHeight: false }

        Item { Layout.fillHeight: true }
    }
}
