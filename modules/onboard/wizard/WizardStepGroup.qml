import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/setupplan.js" as Plan
import "../../../state"
import ".."

// ── The steps of one page, as cards ──────────────────────────────────────
// (Was SetupWizard's inline `StepGroup`.)
ColumnLayout {
    id: sg
    property var ids: []
    property bool shown: true
    property int base: 0
    // Catalogue order, not the order of `ids`: dependencies read top to bottom.
    readonly property var rows: Setup.steps.filter(s => sg.ids.indexOf(s.id) >= 0)

    Layout.fillWidth: true
    Layout.fillHeight: false
    visible: sg.rows.length > 0
    spacing: Tokens.spacingSm

    Repeater {
        model: ScriptModel { values: sg.rows; objectProp: "id" }
        delegate: SetupStepRow {
            required property var modelData
            required property int index
            Layout.fillWidth: true
            step: modelData
            allowRedo: true
            shown: sg.shown
            order: sg.base + index
        }
    }
}
