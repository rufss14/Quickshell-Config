import "../../../services"
import "../../../state"
import QtQuick
import Quickshell
import QtQuick.Layouts
import Quickshell.Io
import "../../../config"
import "../../../components"
import "../../../services/updatefmt.js" as UF

// ── UpdateCaughtUpView ── part of UpdatePanel.qml; `panel` is the UpdatePanel it belongs to. ──
ColumnLayout {
    id: caughtCol
    required property var panel
    property alias caughtPassField: caughtPassField
    Layout.fillWidth:  true
    Layout.fillHeight: false
    visible: panel.viewState.view === "caught"
    opacity: visible ? 1 : 0
    spacing: Tokens.spacingSm
    Behavior on opacity { NumberAnimation { duration: Motion.standard } }

    // The shell's own cookie, with a tick in it, arriving on a spring.
    Item {
        id: caughtMark
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Tokens.spacingMd
        implicitWidth:  Tokens.iconXl * 2.6
        implicitHeight: Tokens.iconXl * 2.6

        PopIn { id: markPop; active: panel.caughtOn; delay: panel.lead }
        opacity: markPop.opacity
        scale:   markPop.scale

        Scallop {
            anchors.fill: parent
            points: 10
            petalDepth: 0.08
            fillColor:   Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).success, 0.20)
            strokeColor: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).success, 0.35)
        }
        MaterialIcon {
            anchors.centerIn: parent
            name: "check"
            fill: 1
            font.pixelSize: Tokens.iconXl * 1.3
            color: Colors.of(QsWindow.window).success
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacingSm
        horizontalAlignment: Text.AlignHCenter
        text: Translation.tr("You're all caught up")
        variant: "title"
        font.weight: Font.DemiBold
    }

    // Also where the shell-update gear speaks in this view (_shellNoteShown). And — so that
    // "nothing pending" can be trusted — when it last looked.
    StyledText {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        text: panel._shellNoteShown ? panel._shellText()
            : Updates.lastUpgradeText + (Updates.lastCheckedText !== "" ? "  ·  checked " + Updates.lastCheckedText : "")
        variant: "caption"
        emphasis: "dim"
        elide: Text.ElideRight
    }

    // Look again, or go set things up — the header is hidden here, so its two actions live here.
    ChipTray {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Tokens.spacingXs
        ChipButton {
            symbol: "refresh"
            label:  Translation.tr("Check now")
            tint:   Colors.of(QsWindow.window).info
            iconAngle: Updates.checking ? panel._checkPhase : 0
            enabled: !Updates.checking
            onActivated: Updates.check()
        }
        ChipButton {
            symbol: "settings"
            tint:   Colors.of(QsWindow.window).info
            onActivated: {
                UiState.updateOpen = false
                UiState.openSettingsTo("SetupPage.qml")
            }
        }
    }

    // Arch news headline even here — a manual-intervention post matters
    // whether or not pacman currently has anything for you.
    UpdateNewsLine {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacingSm
        visible: Updates.newsUnread
    }

    // Password + the shell's own update gear (see ShellUpdateButton) —
    // exactly when no packages are pending is when a new Quicktest
    // release would otherwise go unseen.
    ColumnLayout {
        id: caughtActions
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.topMargin: Tokens.spacingMd
        spacing: Tokens.spacingSm
        opacity: 0
        ViewEnter { target: caughtActions; active: panel.caughtOn; delay: panel.lead + Motion.respond; rise: Tokens.spacingMd }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm
            InputField {
                id: caughtPassField
                Layout.fillWidth: true
                implicitHeight: panel._fieldH
                cornerRadius: implicitHeight / 2
                icon: "lock"
                secret: true
                placeholder: "sudo password…"
                onAccepted: panel._confirmVencord(caughtPassField.text)
                onKeyPressed: (event) => { if (event.key === Qt.Key_Escape) { panel._escClose(); event.accepted = true } }
            }
            UpdateShellUpdateButton { host: panel }
        }

        UpdateActionButton {
            host: panel
            icon: "extension"
            text: Translation.tr("Update Discord (Vencord)")
            primary: false
            disabled: caughtPassField.text.length === 0
            clickHandler: function() { panel._confirmVencord(caughtPassField.text) }
        }
    }
}
