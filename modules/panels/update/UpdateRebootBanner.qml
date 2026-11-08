import "../../../services"
import "../../../state"
import QtQuick
import Quickshell
import QtQuick.Layouts
import Quickshell.Io
import "../../../config"
import "../../../components"
import "../../../services/updatefmt.js" as UF

// ── RebootBanner ─────────────────────────────────────────────────────────
// Kernel or graphics module in the pending list — the one upgrade consequence
// that bites later rather than now (a module the running kernel doesn't have
// won't load until you reboot).
// (Was UpdatePanel's inline `RebootBanner`.)
Rectangle {
    implicitHeight: rbRow.implicitHeight + Tokens.spacingSm * 2
    radius: Tokens.radiusPill
    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).warning, 0.12)

    RowLayout {
        id: rbRow
        anchors.fill: parent
        anchors.leftMargin:  Tokens.spacingLg
        anchors.rightMargin: Tokens.spacingLg
        anchors.topMargin:   Tokens.spacingSm
        anchors.bottomMargin: Tokens.spacingSm
        spacing: Tokens.spacingMd

        MaterialIcon { name: "restart_alt"; font.pixelSize: Tokens.iconMd; color: Colors.of(QsWindow.window).warning }
        StyledText {
            Layout.fillWidth: true
            text: "Replaces " + Updates.rebootPackages.length + " kernel/driver package"
                + (Updates.rebootPackages.length === 1 ? "" : "s") + " — reboot afterwards."
            variant: "caption"
            emphasis: "dim"
            wrapMode: Text.WordWrap
        }
    }
}
