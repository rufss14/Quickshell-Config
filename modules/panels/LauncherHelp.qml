import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"

// ── LauncherHelp ──────────────────────────────────────────────────────────────
// What you can type. That is all it is now: a reference card for the three things a
// search box can't show by looking at it. Setting up the AI (provider, API key) moved
// to Settings › Launcher — a panel you open with a keystroke and close with Escape is
// the wrong place to paste a secret.
//
// It closes on any keystroke (the panel does that), so it never needs putting away.
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root

    // The panel's resolved terminal name, for the `>` row.
    property string terminal: ""

    signal settingsRequested()

    readonly property var entries: [
        { key: "app",  what: "Just type. Enter opens, ↑↓ to pick. Matches names, keywords and initials (vsc)." },
        { key: "lock", what: "Shell actions and settings answer too: night light, random wallpaper, mute mic, a settings page." },
        { key: "12*8", what: "Sums and conversions need no prefix. Enter copies the answer." },
        { key: ">",    what: "Run a command in " + root.terminal + "." },
        { key: "?",    what: "Ask " + Ai.label + ". Enter sends; once a chat is open, just keep typing." },
        { key: "+",    what: "Find a package in the repos" + (Packages.aurEnabled ? " and the AUR" : "") + ". Enter installs it through the updater." }
    ]

    spacing: Tokens.spacingMd

    Repeater {
        model: root.entries
        delegate: RowLayout {
            id: line
            required property var modelData
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd

            // The prefix as a pill, so the eye finds the column of things you actually
            // type rather than a column of dim sentences.
            Surface {
                Layout.preferredWidth:  Tokens.fieldHeight * 2
                Layout.preferredHeight: Tokens.fieldHeight - Tokens.spacingMd
                Layout.alignment: Qt.AlignVCenter
                elevation: Tokens.elevationNested
                cornerRadius: Tokens.radiusSm
                StyledText {
                    anchors.centerIn: parent
                    text: line.modelData.key
                    variant: "caption"
                    font.family: Tokens.fontMono
                    color: Colors.of(QsWindow.window).primary
                }
            }
            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: line.modelData.what
                variant: "body"
                wrapMode: Text.WordWrap
            }
        }
    }

    Divider { Layout.fillWidth: true }

    // One line about the AI, and the way to its settings.
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingMd

        StyledText {
            Layout.fillWidth: true
            text: Ai.ready ? (Ai.label + " is ready.")
                           : (Ai.blocker() !== "" ? Ai.blocker() + "." : "")
            variant: "caption"
            emphasis: "dim"
            wrapMode: Text.WordWrap
        }
        PanelButton {
            label: Translation.tr("Launcher settings")
            symbol: "settings"
            onActivated: root.settingsRequested()
        }
    }
}
