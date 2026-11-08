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

// ── WizardIntegrationsPage ── part of SetupWizard.qml; `wizard` is the SetupWizard it belongs to. ──
WizardPage {
    id: wizardIntegrationsPage
    required property var wizard
    property alias p4: p4
    host: wizard
    idx: 4
    ViewEnter { target: p4; active: wizard.on(4); rise: Tokens.spacingMd }
    ColumnLayout {
        id: p4
        anchors.fill: parent
        spacing: Tokens.spacingMd

        readonly property var spot: ["spotify"]
        readonly property var others: ["wpe", "argos", "songrec", "awww", "ddc", "beatsync", "discordkeys"]
        readonly property var rows: Setup.steps.filter(s => p4.others.indexOf(s.id) >= 0)

        WizardPageHead {
            icon: "extension"
            lead: "Other"; tail: "integrations"
            badge: "optional"
            status: wizard.topic(p4.spot).done ? "Spotify bridge is wired up" : "Tick only what you use"
            done: wizard.topic(p4.spot).done
            shown: wizard.on(4)
        }

        StyledText {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            text: Translation.tr("Word-level lyrics come off Spotify's own playhead, through a Spicetify extension. Unticked, lyrics still work — just coarser.")
            variant: "caption"; emphasis: "dim"; wrapMode: Text.WordWrap
        }
        WizardStepGroup { ids: p4.spot; shown: wizard.on(4); base: 1 }

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            columns: 2
            columnSpacing: Tokens.spacingSm
            rowSpacing: Tokens.spacingSm
            uniformCellWidths: true
            uniformCellHeights: true
            Repeater {
                model: ScriptModel { values: p4.rows; objectProp: "id" }
                delegate: SetupStepRow {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    step: modelData
                    tile: true
                    allowRedo: true
                    shown: wizard.on(4)
                    order: index + 2
                }
            }
        }

        Item { Layout.fillHeight: true }
    }
}
