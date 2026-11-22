pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── DiscordPage — Integrations › Discord ──────────────────────────────────────
// Set up the Discord call panel without hand-editing JSON, and switch on the two rich
// presences (Claude Code, Counter-Strike 2), all grouped rows on one page.
//
// ── Why this page has to exist ────────────────────────────────────────────────
// Discord gates the `rpc.*` scopes to an application's owner, so this repo's author's own
// client id is rejected for everyone else. With nothing filled in, the helper therefore
// signs in as Discord's StreamKit app instead (undocumented; see discord-rpc.py). An
// application of your own is the dependable route, and wins whenever it's set.
//
// ── The secret is never read back ─────────────────────────────────────────────
// `Discord.hasSecret` is a boolean and nothing holds the value. Saving omits
// `clientSecret` unless the field was typed into, so the client id or a keybind can
// change without the secret passing through QML at all. Writing goes through
// scripts/discord-credentials.py, over stdin, because Quickshell can't create a 0600
// file and argv is visible in `ps`.
//
// ── Presence ──────────────────────────────────────────────────────────────────
// The two rich-presence groups are separate Discord applications with their own switches and
// daemons (scripts/claude-presence.py, scripts/cs2-presence.py): a presence card's bold first
// line IS the application's name, so neither can share the call panel's id. Both previews show
// the helper's own strings for what the card is saying, never a second copy of the format
// rules, so a preview cannot confidently show something the real card never said.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    ArmLatch {
        id: logLatch
        onConfirmed: CallLog.clear()
    }
    readonly property int logCount: Object.keys(CallLog.people).length

    // Typed-but-unsaved values. Seeded from the service, then owned by the fields —
    // binding straight to `Discord.clientId` would fight anyone typing mid-save.
    property string draftId:       ""
    property string draftSecret:   ""
    property string draftRedirect: ""
    property string draftCamera:   ""
    property string draftShare:    ""

    property bool seeded: false
    property bool savedOnce: false

    function seed() {
        root.draftId       = Discord.clientId
        root.draftRedirect = Discord.redirectUri !== "" ? Discord.redirectUri : "http://localhost"
        root.draftCamera   = Discord.cameraKey
        root.draftShare    = Discord.screenShareKey
        root.draftSecret   = ""          // never seeded; there is nothing to seed it from
        root.sentKeys      = { camera: Discord.cameraKey, screenshare: Discord.screenShareKey }
        root.seeded = true
    }

    // The status read is async, so the first one may land after this page is built.
    Connections {
        target: Discord
        function onClientIdChanged()  { if (!root.seeded) root.seed() }
        function onHasSecretChanged() { if (!root.seeded) root.seed() }
    }

    Component.onCompleted: {
        Discord.refreshCredentials()
        root.seed()
    }

    readonly property bool dirty:
           root.draftId       !== Discord.clientId
        || root.draftSecret   !== ""
        || root.draftRedirect !== (Discord.redirectUri !== "" ? Discord.redirectUri : "http://localhost")

    function save() {
        const patch = {
            clientId:    root.draftId.trim(),
            redirectUri: root.draftRedirect.trim()
        }
        // Present ONLY when typed. Absent means "keep the stored one".
        if (root.draftSecret !== "") patch.clientSecret = root.draftSecret

        Discord.saveCredentials(patch)
        root.draftSecret = ""    // out of memory the moment it's handed over
        root.savedOnce = true
    }

    // The two keybinds save on their own (Enter or leaving the field), as a `keys` patch
    // that carries nothing else: the sign-in drafts above stay unsaved until their Save.
    // `sentKeys` is what was last handed over, because Discord.cameraKey and
    // screenShareKey only follow the file once the helper re-reads it, a few seconds on.
    // A commit that lands while a save is running waits for it instead of being dropped
    // (saveCredentials ignores a call made while busy).
    property var sentKeys: ({})
    property var pendingKeys: ({})
    // The save in flight and what `sentKeys` was before it: a failed save rolls back, so
    // committing the same value again retries instead of being taken as already sent.
    property var _inflight: null
    property var _sentBefore: ({})

    function saveKey(name, value) {
        const v = value.trim()
        const pend = Object.assign({}, root.pendingKeys)
        if (v === (root.sentKeys[name] ?? "")) {
            // Edited back to what was sent: a different value still waiting must not go out.
            if (name in pend) { delete pend[name]; root.pendingKeys = pend }
            return
        }
        pend[name] = v
        root.pendingKeys = pend
        root.flushKeys()
    }
    function flushKeys() {
        if (Discord.credentialsBusy || Object.keys(root.pendingKeys).length === 0) return
        const keys = root.pendingKeys
        root.pendingKeys = ({})
        root._sentBefore = root.sentKeys
        root._inflight = keys
        root.sentKeys = Object.assign({}, root.sentKeys, keys)
        Discord.saveCredentials({ keys: keys })
    }
    Connections {
        target: Discord
        function onCredentialsBusyChanged() {
            if (!Discord.credentialsBusy && root._inflight !== null) {
                if (Discord.credentialsError !== "") root.sentKeys = root._sentBefore
                root._inflight = null
            }
            root.flushKeys()
        }
    }

    readonly property string stateText:
          !Config.discordEnabled      ? "Off"
        : Discord.connected           ? (Discord.inCall ? "In a call" : "Connected")
        : Discord.awaitingConsent     ? "Waiting for you to approve it in Discord"
        : Discord.needsSetup          ? "Not set up"
        : Discord.lastError !== ""    ? Discord.lastError
        :                               "Connecting…"

    // Reported against the screen-share key, the one people set up. A blocker that's
    // only about the keybind is expected on a fresh install.
    readonly property string injectBlocker: Discord.pressBlocker(Discord.screenShareKey)

    SettingsPage {
        anchors.fill: parent

        grouped:   true
        glyph:     "󰙯"
        title:     Translation.tr("Discord")
        titleTail: Translation.tr("& presence")
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  root.stateText
                 + (ClaudePresence.showing ? "  ·  Claude Code is live" : "")
                 + (Cs2Presence.showing ? "  ·  Counter-Strike 2 is live" : "")

        // The master switch says what it is and which way it is set.
        actions: [
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                text: Config.discordEnabled ? Translation.tr("Discord link on") : Translation.tr("Discord link off")
                variant: "label"
                emphasis: "dim"
            },
            Toggle {
                accent: Colors.of(QsWindow.window).primary
                accessibleName: Translation.tr("Discord link")
                checked: Config.discordEnabled
                onToggled: Config.discordEnabled = !Config.discordEnabled
            }
        ]

        // ══ Sign-in ═══════════════════════════════════════════════════════════
        Section {
            grouped:  true
            symbol:   "login"
            title:    Translation.tr("Sign-in")
            subtitle: Discord.hasCredentials ? Translation.tr("Your own application") : Discord.sharedApp ? Translation.tr("Shared sign-in") : Translation.tr("Not set up")
            help:     Translation.tr("How the shell talks to Discord, so the sidebar's Voice module can mute, deafen and screen share. ")
                    + "Your own application is optional: leave it blank and the shared sign-in is used. "
                    + "Why a shared one? Discord only lets an application's owner grant the voice scopes, so copied credentials are rejected; "
                    + "the shared route borrows Discord's own StreamKit app, which is undocumented, so Discord could change it."

            SettingRow {
                rowTap: true
                label:  Translation.tr("Shared sign-in")
                detail: Discord.hasCredentials ? Translation.tr("Your application takes over") : Translation.tr("Until one is set below")
                onTapped: Discord.saveCredentials({ sharedApp: !Discord.sharedApp })
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Discord.sharedApp
                    onToggled: Discord.saveCredentials({ sharedApp: !Discord.sharedApp })
                }
            }

            FieldRow {
                label: Translation.tr("Client ID")
                InputField {
                    cornerRadius: implicitHeight / 2
                    Layout.fillWidth: true
                    placeholder: Translation.tr("Your app's ID")
                    seed: root.draftId
                    onEdited: function (v) { root.draftId = v }
                }
            }
            FieldRow {
                label: Translation.tr("Client secret")
                InputField {
                    cornerRadius: implicitHeight / 2
                    Layout.fillWidth: true
                    secret: true
                    placeholder: Discord.hasSecret ? "•••••••••••••• saved, blank keeps it" : "From the OAuth2 tab"
                    seed: ""        // deliberately never seeded — see the header
                    onEdited: function (v) { root.draftSecret = v }
                }
            }
            FieldRow {
                label: Translation.tr("Redirect URI")
                InputField {
                    cornerRadius: implicitHeight / 2
                    Layout.fillWidth: true
                    placeholder: "http://localhost"
                    seed: root.draftRedirect
                    onEdited: function (v) { root.draftRedirect = v }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingMd

                StyledText {
                    Layout.fillWidth: true
                    variant: "caption"
                    elide: Text.ElideRight
                    text: Discord.credentialsError !== "" ? Discord.credentialsError
                        : Discord.credentialsBusy         ? "Saving…"
                        : root.dirty                      ? "Unsaved changes"
                        : root.savedOnce                  ? "Saved. Discord picks it up in a few seconds"
                        : Discord.configPath.replace(Quickshell.env("HOME") || "\u0000", "~")
                    color: Discord.credentialsError !== "" ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgDim
                }
                PanelButton {
                    capsule: true
                    label: Translation.tr("Save")
                    accent: Colors.of(QsWindow.window).primary
                    variant: root.dirty ? "primary" : "normal"
                    enabled: root.dirty && !Discord.credentialsBusy
                    onActivated: root.save()
                }
            }
        }

        // ══ Claude Code presence ══════════════════════════════════════════════
        // A client id and nothing else: no secret, no OAuth. The show rows dim while it is off.
        Section {
            grouped:  true
            symbol:   "robot"
            title:    Translation.tr("Claude Code")
            subtitle: ClaudePresence.showing ? Translation.tr("Live") : ""
            help:     Translation.tr("Shows what you're doing in Claude Code as your Discord status. It needs a separate app you register, with a client id and nothing else.")

            actions: [
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 8; implicitHeight: 8
                    radius: width / 2
                    color: ClaudePresence.showing ? Colors.of(QsWindow.window).success
                         : ClaudePresence.needsSetup ? Colors.of(QsWindow.window).warning
                         : Colors.of(QsWindow.window).fgDim
                },
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.claudePresenceEnabled
                    onToggled: Config.claudePresenceEnabled = !Config.claudePresenceEnabled
                }
            ]

            // The service's own summary, so this and the card can't disagree.
            SettingRow {
                label:  Translation.tr("Status")
                detail: ClaudePresence.statusText
                wrapDetail: true
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

            // Re-read rather than restart: a live presence shouldn't be cleared
            // just to pick up an id added next to it.
            SettingRow {
                visible: ClaudePresence.needsSetup
                label:   Translation.tr("Re-read discord-rpc.json")
                detail:  Translation.tr("Picks up a client id you added, without clearing a live card")
                PanelButton {
                    capsule: true
                    variant: "ghost"
                    label: Translation.tr("Re-read")
                    onActivated: ClaudePresence.reloadClientId()
                }
            }

            // What the card is saying right now.
            Rectangle {
                visible: ClaudePresence.showing
                Layout.fillWidth: true
                implicitHeight: claudePreviewCol.implicitHeight + Tokens.spacingSm * 2
                radius: Tokens.radiusSm
                color: Colors.of(QsWindow.window).surfaceHigh

                ColumnLayout {
                    id: claudePreviewCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Tokens.spacingMd
                    anchors.rightMargin: Tokens.spacingMd
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: ClaudePresence.details
                        variant: "caption"
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: ClaudePresence.state !== ""
                        text: ClaudePresence.state
                        variant: "caption"
                        emphasis: "dim"
                        elide: Text.ElideRight
                    }
                }
            }

            SettingRow {
                rowTap: true
                enabled: Config.claudePresenceEnabled
                opacity: enabled ? 1 : 0.4
                label: Translation.tr("Use the AI title")
                detail: Translation.tr("Instead of the short session name")
                onTapped: Config.claudePresenceUseAiTitle = !Config.claudePresenceUseAiTitle
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.claudePresenceUseAiTitle
                    onToggled: Config.claudePresenceUseAiTitle = !Config.claudePresenceUseAiTitle
                }
            }
            SettingRow {
                rowTap: true
                enabled: Config.claudePresenceEnabled
                opacity: enabled ? 1 : 0.4
                label: Translation.tr("Show the workspace")
                detail: ClaudePresence.workspace
                        ? "Currently workspace " + ClaudePresence.workspace
                        : "Hyprland workspace, when the terminal can be placed"
                onTapped: Config.claudePresenceShowWorkspace = !Config.claudePresenceShowWorkspace
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.claudePresenceShowWorkspace
                    onToggled: Config.claudePresenceShowWorkspace = !Config.claudePresenceShowWorkspace
                }
            }
            SettingRow {
                rowTap: true
                enabled: Config.claudePresenceEnabled
                opacity: enabled ? 1 : 0.4
                label: Translation.tr("Show the model")
                detail: ClaudePresence.model || "Read from the transcript"
                onTapped: Config.claudePresenceShowModel = !Config.claudePresenceShowModel
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.claudePresenceShowModel
                    onToggled: Config.claudePresenceShowModel = !Config.claudePresenceShowModel
                }
            }
            SettingRow {
                rowTap: true
                enabled: Config.claudePresenceEnabled
                opacity: enabled ? 1 : 0.4
                label: Translation.tr("Show context used")
                // Says WHICH number: a session total runs to tens of millions,
                // almost all cache reads. This is the context window.
                detail: ClaudePresence.context > 0
                        ? "Currently " + Math.round(ClaudePresence.context / 1000) + "k in the context window"
                        : "Tokens currently in the context window"
                onTapped: Config.claudePresenceShowTokens = !Config.claudePresenceShowTokens
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.claudePresenceShowTokens
                    onToggled: Config.claudePresenceShowTokens = !Config.claudePresenceShowTokens
                }
            }
            SettingRow {
                rowTap: true
                enabled: Config.claudePresenceEnabled
                opacity: enabled ? 1 : 0.4
                label: Translation.tr("Show other sessions")
                detail: ClaudePresence.sessionCount > 1
                        ? Translation.tr("Currently %1 more running").arg(ClaudePresence.sessionCount - 1)
                        : "Appends \"+N more\" when other terminals are open"
                onTapped: Config.claudePresenceShowSessionCount = !Config.claudePresenceShowSessionCount
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.claudePresenceShowSessionCount
                    onToggled: Config.claudePresenceShowSessionCount = !Config.claudePresenceShowSessionCount
                }
            }
        }

        // ══ Your own application ══════════════════════════════════════════════
        Section {
            grouped:  true
            symbol:   "vpn_key"
            title:    Translation.tr("Your own application")
            subtitle: Translation.tr("About a minute, once")
            help:     Translation.tr("Only needed if the shared sign-in fails. An application of your own is the dependable option.")

            // The four steps read as one list, so they share one segment.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                Step { n: 1; text: Translation.tr("discord.com/developers/applications → New Application (any name).") }
                Step { n: 2; text: Translation.tr("General Information → copy the Application ID into Client ID.") }
                Step { n: 3; text: Translation.tr("OAuth2 → Reset Secret, copy it; add http://localhost under Redirects.") }
                Step { n: 4; text: Translation.tr("Save here, then approve Discord's prompt once.") }
            }
        }

        // ══ Counter-Strike 2 presence ═════════════════════════════════════════
        // Nothing to register: it handshakes as Valve's own registered
        // "Counter-Strike 2" app. What it needs is the Game State Integration feed,
        // switched on by scripts/install-cs2-gsi.sh; the blocker says so.
        Section {
            grouped:  true
            symbol:   "sports_esports"
            title:    Translation.tr("Counter-Strike 2")
            subtitle: Cs2Presence.showing ? Translation.tr("Live") : ""
            help:     Translation.tr("Shows your match as your Discord status. No app to set up: it uses Valve's own.")

            actions: [
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 8; implicitHeight: 8
                    radius: width / 2
                    color: Cs2Presence.showing ? Colors.of(QsWindow.window).success
                         : Cs2Presence.needsSetup ? Colors.of(QsWindow.window).warning
                         : Colors.of(QsWindow.window).fgDim
                },
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.cs2PresenceEnabled
                    onToggled: Config.cs2PresenceEnabled = !Config.cs2PresenceEnabled
                }
            ]

            SettingRow {
                label:  Translation.tr("Status")
                detail: Cs2Presence.statusText
                wrapDetail: true
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

            Rectangle {
                visible: Cs2Presence.showing
                Layout.fillWidth: true
                implicitHeight: cs2PreviewCol.implicitHeight + Tokens.spacingSm * 2
                radius: Tokens.radiusSm
                color: Colors.of(QsWindow.window).surfaceHigh

                ColumnLayout {
                    id: cs2PreviewCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Tokens.spacingMd
                    anchors.rightMargin: Tokens.spacingMd
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: Cs2Presence.details
                        variant: "caption"
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: Cs2Presence.state !== ""
                        text: Cs2Presence.state
                        variant: "caption"
                        emphasis: "dim"
                        elide: Text.ElideRight
                    }
                }
            }

            SettingRow {
                rowTap: true
                enabled: Config.cs2PresenceEnabled
                opacity: enabled ? 1 : 0.4
                label: Translation.tr("Show the score")
                detail: Cs2Presence.inMatch && Cs2Presence.ct >= 0
                        ? "Currently CT " + Cs2Presence.ct + " : " + Cs2Presence.tScore + " T"
                        : "The round score, e.g. CT 7 : 5 T"
                onTapped: Config.cs2PresenceShowScore = !Config.cs2PresenceShowScore
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.cs2PresenceShowScore
                    onToggled: Config.cs2PresenceShowScore = !Config.cs2PresenceShowScore
                }
            }
            SettingRow {
                rowTap: true
                enabled: Config.cs2PresenceEnabled
                opacity: enabled ? 1 : 0.4
                label: Translation.tr("Show your K/D")
                detail: Cs2Presence.inMatch && Cs2Presence.kills >= 0
                        ? "Currently " + Cs2Presence.kills + "/" + Cs2Presence.deaths
                        : "Your kills and deaths this match"
                onTapped: Config.cs2PresenceShowKd = !Config.cs2PresenceShowKd
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.cs2PresenceShowKd
                    onToggled: Config.cs2PresenceShowKd = !Config.cs2PresenceShowKd
                }
            }
            SettingRow {
                rowTap: true
                enabled: Config.cs2PresenceEnabled
                opacity: enabled ? 1 : 0.4
                label: Translation.tr("Show the mode")
                detail: Cs2Presence.mode ? "Currently " + Cs2Presence.mode : "The mode in front of the map name"
                onTapped: Config.cs2PresenceShowMode = !Config.cs2PresenceShowMode
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.cs2PresenceShowMode
                    onToggled: Config.cs2PresenceShowMode = !Config.cs2PresenceShowMode
                }
            }
        }

        // ══ Keybinds + injection readiness ════════════════════════════════════
        // One group: the keybinds are ONLY used for injection, and a missing
        // xdotool is invisible until you press a button and nothing happens.
        Section {
            grouped:  true
            symbol:   "keyboard"
            title:    Translation.tr("Screen share & camera")
            subtitle: !Config.discordEnabled ? "" : root.injectBlocker === "" ? Translation.tr("Ready") : Translation.tr("Can't press keys yet")
            help:     Translation.tr("Discord has no RPC command for these, so the shell presses Discord's own keybind. Set the same combinations as Discord → Settings → Keybinds; screen share has no default.")

            actions: Rectangle {
                visible: Config.discordEnabled
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 8; implicitHeight: 8
                radius: width / 2
                color: root.injectBlocker === "" ? Colors.of(QsWindow.window).success : Colors.of(QsWindow.window).warning
            }

            FieldRow {
                label: Translation.tr("Screen share")
                InputField {
                    cornerRadius: implicitHeight / 2
                    Layout.fillWidth: true
                    placeholder: Translation.tr("e.g. ctrl+shift+s")
                    seed: root.draftShare
                    onEdited: function (v) { root.draftShare = v }
                    onCommitted: function (v) { root.saveKey("screenshare", v) }
                }
            }
            FieldRow {
                label: Translation.tr("Camera")
                InputField {
                    cornerRadius: implicitHeight / 2
                    Layout.fillWidth: true
                    placeholder: Translation.tr("e.g. ctrl+shift+v")
                    seed: root.draftCamera
                    onEdited: function (v) { root.draftCamera = v }
                    onCommitted: function (v) { root.saveKey("camera", v) }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: Config.discordEnabled && root.injectBlocker !== ""
                text: root.injectBlocker
                variant: "caption"
                color: Colors.of(QsWindow.window).warning
                wrapMode: Text.WordWrap
            }
        }

        // ══ Call log ══════════════════════════════════════════════════════════
        // The scoreboard on the voice panel's Board tab. Discord's RPC has no friends list, so it can only count
        // who shared your call: hide anyone you don't want from the board there.
        Section {
            grouped:  true
            symbol:   "history"
            title:    Translation.tr("Call log")
            subtitle: root.logCount === 0 ? Translation.tr("Nobody yet")
                      : root.logCount === 1 ? Translation.tr("1 person kept") : Translation.tr("%1 people kept").arg(root.logCount)
            help:     Translation.tr("Keeps how long you have been in a call with each person, for the Board tab of the voice panel. Names and time only, on this computer, until you forget them. No server or channel names, no record of when each call was. Discord doesn't say who your friends are, so it counts everyone who joined; hide anyone from the board there.")

            actions: Toggle {
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.callLog
                onToggled: Config.callLog = !Config.callLog
            }
            SettingRow {
                label:  Translation.tr("Forget everyone")
                detail: Translation.tr("Names and time only, on this computer")
                PanelButton {
                    capsule: true
                    label: logLatch.armed ? Translation.tr("Sure?") : Translation.tr("Forget")
                    variant: logLatch.armed ? "primary" : "ghost"
                    accent: Colors.of(QsWindow.window).danger
                    enabled: root.logCount > 0
                    onActivated: logLatch.trigger()
                }
            }
        }
    }

    // ── FieldRow — label beside a full-width field ────────────────────────────
    // Beside, not above: a label over every field doubled the card's height.
    component FieldRow: RowLayout {
        id: fr
        property string label: ""
        default property alias field: slot.data

        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingMd

        StyledText {
            Layout.preferredWidth: 104
            Layout.alignment: Qt.AlignVCenter
            text: fr.label
            variant: "body"
            // The same weight and brightness as a SettingRow's label, so the rows around read alike.
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
        RowLayout {
            id: slot
            Layout.fillWidth: true
            Layout.fillHeight: false
        }
    }

    // ── Step ──────────────────────────────────────────────────────────────────
    component Step: RowLayout {
        id: step
        property int n: 0
        property string text: ""
        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingMd

        Rectangle {
            Layout.alignment: Qt.AlignTop
            implicitWidth: Tokens.iconMd
            implicitHeight: Tokens.iconMd
            radius: width / 2
            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.16)

            StyledText {
                anchors.centerIn: parent
                text: String(step.n)
                variant: "caption"
                color: Colors.of(QsWindow.window).primary
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            text: step.text
            variant: "caption"
            wrapMode: Text.WordWrap
        }
    }
}
