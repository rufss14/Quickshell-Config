import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"
import "../services"

// ── ShellUpdateCard ───────────────────────────────────────────────────────────
// The shell's OWN update row (services/ShellUpdate), as opposed to the system's
// packages around it: Quickshell's mark, the installed version, what the last check
// found, and the one action that makes sense right now — Check, Update, or progress.
// Settings → Updates wears it; the bar's UpdatePanel has a one-button version
// (ShellUpdateButton) over the same service.
//
// Always shown: "check for a new version" has to be reachable before there is one.
// It turns accent-tinted only when there's something to act on (a release, an
// install, a failure). No password: the shell lives in the user's own config dir.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    readonly property bool _alert: ShellUpdate.available || ShellUpdate.installing
                                   || ShellUpdate.error !== ""
    readonly property color _accent: ShellUpdate.error !== ""
        ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).primary

    implicitHeight: body.implicitHeight + Tokens.spacingSm * 2
    radius: Tokens.radiusSm
    color: root._alert ? Colors.of(QsWindow.window).alpha(root._accent, 0.10)
                       : Colors.of(QsWindow.window).surfaceContainer
    border.width: Tokens.borderWidth
    border.color: root._alert ? Colors.of(QsWindow.window).alpha(root._accent, 0.32)
                              : Colors.of(QsWindow.window).outline
    Behavior on color { ColorAnimation { duration: Motion.respond } }

    ColumnLayout {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top }
        anchors.margins: Tokens.spacingSm
        anchors.leftMargin:  Tokens.spacingMd
        anchors.rightMargin: Tokens.spacingMd
        spacing: Tokens.spacingXs

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm

            // Quickshell's gear, stencilled in the scheme's accent (the mono cut of
            // the mark — see assets/logos/README.md).
            TintedIcon {
                Layout.alignment: Qt.AlignVCenter
                source: Icons.logo("quickshell-mono.svg")
                color:  root._alert ? root._accent : Colors.of(QsWindow.window).primary
                size:   Tokens.iconXl
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: ShellUpdate.installing ? "Updating Quicktest"
                        : ShellUpdate.error !== "" ? "Shell update stopped"
                        : ShellUpdate.available ? "Quicktest " + ShellUpdate.latest + " is available"
                        : "Quicktest " + ShellUpdate.current
                    variant: "caption"
                    color: root._alert ? root._accent : Colors.of(QsWindow.window).fg
                    font.weight: Font.DemiBold
                }
                StyledText {
                    Layout.fillWidth: true
                    text: ShellUpdate.installing ? ShellUpdate.status
                        : ShellUpdate.error !== "" ? ShellUpdate.error
                        : ShellUpdate.available
                          ? (ShellUpdate.blocker !== "" ? ShellUpdate.blocker
                             : "You have " + ShellUpdate.current
                               + (ShellUpdate.date ? " · released " + ShellUpdate.date : ""))
                        : ShellUpdate.checking ? "Checking for a new version…"
                        : ShellUpdate.checkFailed ? "Couldn't reach GitHub — try again later"
                        : ShellUpdate.checked ? "Up to date"
                        : "Shell updates"
                    variant: "micro"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                }
            }

            BusyDot { visible: ShellUpdate.installing; running: visible; tint: root._accent }

            PanelButton {
                visible: !ShellUpdate.installing
                enabled: ShellUpdate.available ? ShellUpdate.blocker === "" : !ShellUpdate.checking
                variant: ShellUpdate.available ? "primary" : "normal"
                accent:  root._accent
                glyph:   ShellUpdate.available ? "󰇚" : "󰑐"
                label:   ShellUpdate.available ? (ShellUpdate.error !== "" ? "Retry" : "Update")
                       : ShellUpdate.checking ? "Checking…" : "Check"
                onActivated: ShellUpdate.available ? ShellUpdate.install() : ShellUpdate.check()
            }
        }

        // The release notes, as qtrelease wrote them — a few lines here, the
        // full page one click away.
        StyledText {
            Layout.fillWidth: true
            visible: ShellUpdate.available && ShellUpdate.notes !== "" && !ShellUpdate.installing
            text: ShellUpdate.notes
            variant: "caption"
            wrapMode: Text.WordWrap
            maximumLineCount: 4
            elide: Text.ElideRight
        }
        PanelButton {
            visible: ShellUpdate.available && ShellUpdate.url !== "" && !ShellUpdate.installing
            variant: "ghost"
            glyph:   "󰏌"
            label:   Translation.tr("Release notes")
            onActivated: Qt.openUrlExternally(ShellUpdate.url)
        }
    }
}
