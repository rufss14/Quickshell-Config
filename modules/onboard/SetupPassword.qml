import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── SetupPassword ─────────────────────────────────────────────────────────────
// Root, asked once: the password field and the line under it. `password` is what was typed; it is handed
// to Setup.startPlan() and nowhere else, and the field empties when the run ends or sudo says no. With a
// polkit agent running it may be left empty — the system's dialog asks instead (Setup.polkitReady).
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root

    property string password: ""
    signal submitted()
    function focusField() { pw.forceActiveFocus() }

    spacing: Tokens.spacingXs

    Connections {
        target: Setup
        function onPasswordRejected() { pw.text = ""; root.focusField() }
        function onPlanFinished() { pw.text = "" }
    }

    Surface {
        Layout.fillWidth: true
        implicitHeight: Tokens.pillHeight + Tokens.spacingMd + 2
        elevation: Tokens.elevationNested
        cornerRadius: Tokens.radiusPill
        focused: pw.activeFocus

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.spacingLg
            anchors.rightMargin: Tokens.spacingLg
            spacing: Tokens.spacingMd

            MaterialIcon {
                name: root.password.length > 0 ? "lock_open" : "lock"
                fill: root.password.length > 0 ? 1 : 0
                color: root.password.length > 0 ? Verdict.tint(true)
                     : pw.activeFocus ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgDim
                font.pixelSize: Tokens.iconSm
            }
            TextInput {
                id: pw
                Layout.fillWidth: true
                echoMode: TextInput.Password
                verticalAlignment: TextInput.AlignVCenter
                color: Colors.of(QsWindow.window).fg
                selectByMouse: true
                selectionColor: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.35)
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontBody
                enabled: !Setup.busy
                onTextChanged: root.password = text
                onAccepted: root.submitted()

                StyledText {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: pw.text === ""
                    text: Setup.polkitReady ? "Password (or leave empty to use the system dialog)" : "sudo password"
                    variant: "body"; color: Colors.of(QsWindow.window).fgDim
                    elide: Text.ElideRight
                }
            }
        }
    }
    StyledText {
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        text: SudoLock.locked ? SudoLock.message
            : Setup.passwordNote !== "" ? Setup.passwordNote
            : root.password.length > 0 ? "Used for this run only, and never stored."
            : Setup.polkitReady ? "Your system's password dialog will ask — once, and again for each AUR package it builds."
            : "Needed to install packages. Used for this run only, and never stored."
        variant: "caption"
        color: SudoLock.locked || Setup.passwordNote !== "" ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgDim
        wrapMode: Text.WordWrap
    }
}
