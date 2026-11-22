import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"

// ── HyprApplyBar ──────────────────────────────────────────────────────────────
// The "saved to disk — reload to apply" strip and the "edit rejected" strip, shared by
// both Window manager views (Keybinds, Windows). One copy, because the two views write
// through the same HyprConfig queue and must describe its state identically.
//
// Edits are written to disk immediately — each backed up and syntax-checked by the
// script — but NOT applied to the running session until Apply runs a single
// `hyprctl reload`. Writing a file is cheap and reversible; reloading the compositor
// is neither, so it stays one explicit action.
//
// Zero height when there's nothing to say.
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root

    Layout.fillWidth: true
    Layout.fillHeight: false
    spacing: Tokens.spacingSm

    // Flat plates, no outline: a strip of state on the ground (the tone ladder).
    Rectangle {
        Layout.fillWidth: true
        visible: HyprConfig.pendingApply || HyprConfig.canUndo
        implicitHeight: applyRow.implicitHeight + Tokens.spacingSm * 2
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).section

        RowLayout {
            id: applyRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin:  Tokens.spacingLg
            anchors.rightMargin: Tokens.spacingSm
            spacing: Tokens.spacingMd

            StyledText {
                Layout.fillWidth: true
                variant: "label"
                emphasis: "muted"
                elide: Text.ElideRight
                text: HyprConfig.applying     ? Translation.tr("Reloading Hyprland…")
                    : HyprConfig.pendingApply ? Translation.tr("Saved to disk (backed up). Reload to apply to this session.")
                    : Translation.tr("Nothing to apply.")
            }
            PanelButton {
                capsule: true
                visible: HyprConfig.canUndo
                variant: "ghost"
                glyph: "󰕌"
                label: Translation.tr("Undo")
                onActivated: HyprConfig.undo()
            }
            PanelButton {
                capsule: true
                visible: HyprConfig.pendingApply
                variant: "primary"
                accent: Colors.of(QsWindow.window).primary
                glyph: "󰑐"
                label: Translation.tr("Apply")
                onActivated: HyprConfig.apply()
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        visible: HyprConfig.lastError !== ""
        implicitHeight: errRow.implicitHeight + Tokens.spacingSm * 2
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).danger, 0.14)

        RowLayout {
            id: errRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin:  Tokens.spacingLg
            anchors.rightMargin: Tokens.spacingSm
            spacing: Tokens.spacingMd

            StyledText {
                Layout.fillWidth: true
                variant: "label"
                color: Colors.of(QsWindow.window).danger
                elide: Text.ElideRight
                text: Translation.tr("Edit rejected, your config was left untouched: %1").arg(HyprConfig.lastError)
            }
            PanelButton {
                capsule: true
                variant: "ghost"
                symbol: "close"
                onActivated: HyprConfig.clearError()
            }
        }
    }
}
