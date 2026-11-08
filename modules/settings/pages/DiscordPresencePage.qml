pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── DiscordPresencePage — Integrations › Presence ─────────────────────────────
// The two rich-presence cards, side by side. Split out of DiscordPage.
//
// Each needs its own Discord APPLICATION, because a presence card's bold first line
// IS the application's name — so neither can share the call panel's id, and each is
// its own daemon (scripts/claude-presence.py, scripts/cs2-presence.py) with its own
// switch here.
//
// Both cards show the helper's own strings for what the card is saying, never a second
// copy of the format rules — that's how a preview ends up confidently showing
// something the real card never said.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     "󰙯"
        title:     Translation.tr("Rich")
        titleTail: "presence"
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  ClaudePresence.showing && Cs2Presence.showing
                   ? "Claude Code and Counter-Strike 2 are both live"
                   : ClaudePresence.showing ? "Claude Code is live"
                   : Cs2Presence.showing    ? "Counter-Strike 2 is live"
                   : "Nothing is being published right now"

        // ── Claude Code presence ──────────────────────────────────────────────
        // A client id and nothing else — no secret, no OAuth.
        Section {
            span:     1
            glyph:    "󰚩"
            title:    Translation.tr("Claude Code")
            help:     Translation.tr("Shows what you're doing in Claude Code as your Discord status. It needs a separate app you register — a client id, nothing else.")
            accent:   Colors.of(QsWindow.window).primary
            bodySpacing: Tokens.spacingXs

            actions: [
                StatusDot {
                    showing: ClaudePresence.showing
                    needsSetup: ClaudePresence.needsSetup
                },
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.claudePresenceEnabled
                    onToggled: Config.claudePresenceEnabled = !Config.claudePresenceEnabled
                }
            ]

            // The service's own summary, so this and the card can't disagree.
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                text: ClaudePresence.statusText
                variant: "caption"
                color: Colors.of(QsWindow.window).fgDim
                wrapMode: Text.WordWrap
            }

            // The blocker contract: say what to do rather than a toggle that
            // silently publishes nothing.
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: ClaudePresence.blocker() !== ""
                text: ClaudePresence.blocker()
                variant: "caption"
                color: Colors.of(QsWindow.window).warning
                wrapMode: Text.WordWrap
            }

            PanelButton {
                capsule: true
                visible: ClaudePresence.needsSetup
                variant: "ghost"
                label: Translation.tr("Re-read discord-rpc.json")
                // Re-read rather than restart: a live presence shouldn't be cleared
                // just to pick up an id added next to it.
                onActivated: ClaudePresence.reloadClientId()
            }

            PresencePreview {
                visible: ClaudePresence.showing
                details: ClaudePresence.details
                stateLine: ClaudePresence.state
            }

            SettingRow {
                visible: Config.claudePresenceEnabled
                label: Translation.tr("Use the AI title")
                detail: Translation.tr("Instead of the short session name")
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.claudePresenceUseAiTitle
                    onToggled: Config.claudePresenceUseAiTitle = !Config.claudePresenceUseAiTitle
                }
            }
            SettingRow {
                visible: Config.claudePresenceEnabled
                label: Translation.tr("Show the workspace")
                detail: ClaudePresence.workspace
                        ? "Currently workspace " + ClaudePresence.workspace
                        : "Hyprland workspace, when the terminal can be placed"
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.claudePresenceShowWorkspace
                    onToggled: Config.claudePresenceShowWorkspace = !Config.claudePresenceShowWorkspace
                }
            }
            SettingRow {
                visible: Config.claudePresenceEnabled
                label: Translation.tr("Show the model")
                detail: ClaudePresence.model || "Read from the transcript"
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.claudePresenceShowModel
                    onToggled: Config.claudePresenceShowModel = !Config.claudePresenceShowModel
                }
            }
            SettingRow {
                visible: Config.claudePresenceEnabled
                label: Translation.tr("Show context used")
                // Says WHICH number: a session total runs to tens of millions,
                // almost all cache reads. This is the context window.
                detail: ClaudePresence.context > 0
                        ? "Currently " + Math.round(ClaudePresence.context / 1000) + "k in the context window"
                        : "Tokens currently in the context window"
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.claudePresenceShowTokens
                    onToggled: Config.claudePresenceShowTokens = !Config.claudePresenceShowTokens
                }
            }
            SettingRow {
                visible: Config.claudePresenceEnabled
                label: Translation.tr("Show other sessions")
                detail: ClaudePresence.sessionCount > 1
                        ? "Currently " + (ClaudePresence.sessionCount - 1) + " more running"
                        : "Appends \"+N more\" when other terminals are open"
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.claudePresenceShowSessionCount
                    onToggled: Config.claudePresenceShowSessionCount = !Config.claudePresenceShowSessionCount
                }
            }
            }

        // ── Counter-Strike 2 presence ─────────────────────────────────────────
        // Nothing to register: it handshakes as Valve's own registered
        // "Counter-Strike 2" app. What it needs is the Game State Integration feed,
        // switched on by scripts/install-cs2-gsi.sh; the blocker says so.
        Section {
            span:     1
            glyph:    "󰆾"
            title:    Translation.tr("Counter-Strike 2")
            help:     Translation.tr("Shows your match as your Discord status. No app to set up — it uses Valve's own.")
            accent:   Colors.of(QsWindow.window).primary
            bodySpacing: Tokens.spacingXs

            actions: [
                StatusDot {
                    showing: Cs2Presence.showing
                    needsSetup: Cs2Presence.needsSetup
                },
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.cs2PresenceEnabled
                    onToggled: Config.cs2PresenceEnabled = !Config.cs2PresenceEnabled
                }
            ]

            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                text: Cs2Presence.statusText
                variant: "caption"
                color: Colors.of(QsWindow.window).fgDim
                wrapMode: Text.WordWrap
            }
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: Cs2Presence.blocker() !== ""
                text: Cs2Presence.blocker()
                variant: "caption"
                color: Colors.of(QsWindow.window).warning
                wrapMode: Text.WordWrap
            }

            PresencePreview {
                visible: Cs2Presence.showing
                details: Cs2Presence.details
                stateLine: Cs2Presence.state
            }

            SettingRow {
                visible: Config.cs2PresenceEnabled
                label: Translation.tr("Show the score")
                detail: Cs2Presence.inMatch && Cs2Presence.ct >= 0
                        ? "Currently CT " + Cs2Presence.ct + " : " + Cs2Presence.tScore + " T"
                        : "The round score, e.g. CT 7 : 5 T"
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.cs2PresenceShowScore
                    onToggled: Config.cs2PresenceShowScore = !Config.cs2PresenceShowScore
                }
            }
            SettingRow {
                visible: Config.cs2PresenceEnabled
                label: Translation.tr("Show your K/D")
                detail: Cs2Presence.inMatch && Cs2Presence.kills >= 0
                        ? "Currently " + Cs2Presence.kills + "/" + Cs2Presence.deaths
                        : "Your kills and deaths this match"
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.cs2PresenceShowKd
                    onToggled: Config.cs2PresenceShowKd = !Config.cs2PresenceShowKd
                }
            }
            SettingRow {
                visible: Config.cs2PresenceEnabled
                label: Translation.tr("Show the mode")
                detail: Cs2Presence.mode ? "Currently " + Cs2Presence.mode : "The mode in front of the map name"
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.cs2PresenceShowMode
                    onToggled: Config.cs2PresenceShowMode = !Config.cs2PresenceShowMode
                }
            }
        }
    }

    // ── StatusDot — live / needs setup / idle ─────────────────────────────────
    component StatusDot: Rectangle {
        property bool showing: false
        property bool needsSetup: false
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 8
        implicitHeight: 8
        radius: width / 2
        color: showing ? Colors.of(QsWindow.window).success : needsSetup ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).fgDim
    }

    // ── PresencePreview — what the card is saying right now ───────────────────
    component PresencePreview: Rectangle {
        id: pp
        property string details: ""
        property string stateLine: ""

        Layout.fillWidth: true
        implicitHeight: ppCol.implicitHeight + Tokens.spacingSm * 2
        radius: Tokens.radiusSm
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.08)

        ColumnLayout {
            id: ppCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Tokens.spacingMd
            anchors.rightMargin: Tokens.spacingMd
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: pp.details
                variant: "caption"
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                visible: pp.stateLine !== ""
                text: pp.stateLine
                variant: "caption"
                emphasis: "dim"
                elide: Text.ElideRight
            }
        }
    }
}
