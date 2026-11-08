import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── SetupRestore ──────────────────────────────────────────────────────────────
// The way back from the Hyprland step, where it was taken: "your previous config is saved — restore it".
// The step copies ~/.config/hypr to hypr.bak.<time> before replacing it (or an existing quicktest.lua to
// quicktest.lua.bak.<time>); services/Setup lists them (hyprBackups) and restores through
// scripts/restore-hypr-config.sh, which sets what is there NOW aside rather than deleting it — so the button
// is a two-step latch (click, click again: it replaces the current config) and the result is itself undoable.
//
// Shown only when there is something to go back to for the way the shell is wired in (`Setup.hyprMode`):
//   full      a whole-config backup exists
//   minimal   quicktest.lua is in place (an earlier one is restored if there was one, else it is set aside)
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property bool shown: true
    property int pops: 0
    // The host's own reason to show it (the recap: only when this run touched Hyprland).
    property bool condition: true

    readonly property bool full: Setup.hyprMode === "full"
    readonly property var dirBak: Setup.hyprDirBackups[0] ?? null
    readonly property var fileBak: Setup.hyprBackups.find(b => b.kind === "file") ?? null
    readonly property bool available: root.full ? root.dirBak !== null : Setup.hyprMinimalActive
    readonly property var when: root.full ? root.dirBak : root.fileBak

    PopIn { id: pop; active: root.shown && root.available && root.condition; index: root.pops }

    Layout.fillWidth: true
    Layout.fillHeight: false
    visible: root.available && root.condition
    implicitHeight: row.implicitHeight + Tokens.spacingMd * 2
    radius: Tokens.radiusSm
    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.04)
    border.width: Tokens.borderWidth
    border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.10)
    opacity: pop.opacity
    scale: pop.scale

    ArmLatch {
        id: latch
        onConfirmed: root.full ? Setup.restoreHypr(root.dirBak.path) : Setup.restoreHyprMinimal()
    }

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: Tokens.spacingMd
        spacing: Tokens.spacingMd

        MaterialIcon { name: "history"; color: Colors.of(QsWindow.window).fgMuted; font.pixelSize: Tokens.iconMd }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 1
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                text: root.full ? "Your previous Hyprland config is saved"
                    : root.fileBak ? "An earlier quicktest.lua is saved" : "quicktest.lua was added by setup"
                variant: "body"; font.weight: Font.Medium
            }
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                text: (root.when ? "From " + Qt.formatDateTime(new Date(root.when.epoch * 1000), "d MMM, HH:mm") + ". " : "")
                    + (latch.armed ? "Click again to put it back — what is there now is set aside, not deleted."
                                   : root.full ? "Restoring sets the bundled config aside and brings yours back."
                                   : root.fileBak ? "Restoring brings it back." : "Undoing it sets the file aside; remove its require() line from your hyprland.lua too.")
                variant: "caption"; emphasis: "dim"; wrapMode: Text.WordWrap
            }
        }
        PanelButton {
            variant: latch.armed ? "primary" : "ghost"
            accent: Colors.of(QsWindow.window).primary
            symbol: "undo"
            label: latch.armed ? "Yes, restore" : root.full || root.fileBak ? "Restore it" : "Undo it"
            enabled: !Setup.busy
            onActivated: latch.trigger()
        }
    }
}
