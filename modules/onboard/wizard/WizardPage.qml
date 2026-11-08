import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/setupplan.js" as Plan
import "../../../state"

// ── A wizard page — crossfaded, only the active one takes input ──────────
// (Was SetupWizard's inline `Page`; `host` is the SetupWizard.)
Item {
    required property var host
    property int idx: 0
    anchors.fill: parent
    opacity: host.page === idx ? 1 : 0
    visible: opacity > 0.01
    enabled: host.page === idx
    Behavior on opacity { NumberAnimation { duration: Motion.standard } }
}
