import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"

// ── HyprApplyBar ──────────────────────────────────────────────────────────────
// The "saved to disk — reload to apply" strip and the "edit rejected" strip, shared by
// both Window manager views (Keybinds, Tuning). One copy, because the two views write
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

    Surface {
        Layout.fillWidth: true
        visible: HyprConfig.pendingApply || HyprConfig.canUndo
        implicitHeight: applyRow.implicitHeight + Tokens.spacingSm * 2
        elevation:    Tokens.elevationNested
        cornerRadius: Tokens.radiusSm
        castsShadow:  false

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
                text: HyprConfig.applying     ? "Reloading Hyprland…"
                    : HyprConfig.pendingApply ? "Saved to disk (backed up). Reload to apply to this session."
                    : "Nothing to apply."
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

    Surface {
        Layout.fillWidth: true
        visible: HyprConfig.lastError !== ""
        implicitHeight: errRow.implicitHeight + Tokens.spacingSm * 2
        elevation:    Tokens.elevationNested
        cornerRadius: Tokens.radiusSm
        castsShadow:  false
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).danger, 0.14)
        border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).danger, 0.4)

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
                text: "Edit rejected — your config was left untouched: " + HyprConfig.lastError
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
