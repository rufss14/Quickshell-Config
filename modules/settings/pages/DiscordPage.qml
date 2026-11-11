pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── DiscordPage — Integrations › Discord ──────────────────────────────────────
// Set up the Discord call panel without hand-editing JSON.
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
// The rich-presence cards moved to DiscordPresencePage (Integrations › Presence) — they
// are separate Discord applications with their own switches, and together with this
// they were two window-heights tall.
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
        || root.draftCamera   !== Discord.cameraKey
        || root.draftShare    !== Discord.screenShareKey

    function save() {
        const patch = {
            clientId:    root.draftId.trim(),
            redirectUri: root.draftRedirect.trim(),
            keys: { camera: root.draftCamera.trim(), screenshare: root.draftShare.trim() }
        }
        // Present ONLY when typed. Absent means "keep the stored one".
        if (root.draftSecret !== "") patch.clientSecret = root.draftSecret

        Discord.saveCredentials(patch)
        root.draftSecret = ""    // out of memory the moment it's handed over
        root.savedOnce = true
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

        bento:     true
        glyph:     "󰙯"
        title:     Translation.tr("Discord")
        titleTail: "calls"
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  root.stateText

        actions: Toggle {
            accent: Colors.of(QsWindow.window).primary
            checked: Config.discordEnabled
            onToggled: Config.discordEnabled = !Config.discordEnabled
        }

        Section {
            span:     1
            glyph:    "󰭕"
            title:    Translation.tr("Sign-in")
            subtitle: Discord.hasCredentials ? "Your own application" : Discord.sharedApp ? "Shared sign-in" : "Not set up"
            help:     Translation.tr("How the shell talks to Discord, so the sidebar's Voice module can mute, deafen and screen share. ")
                    + "Your own application is optional: leave it blank and the shared sign-in is used. "
                    + "Why a shared one? Discord only lets an application's owner grant the voice scopes, so copied credentials are rejected; "
                    + "the shared route borrows Discord's own StreamKit app — undocumented, so Discord could change it."
            accent:   Colors.of(QsWindow.window).primary
            bodySpacing: Tokens.spacingSm

            FieldRow {
                label: Translation.tr("Shared sign-in")
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Discord.sharedApp
                    onToggled: Discord.saveCredentials({ sharedApp: !Discord.sharedApp })
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    text: Discord.hasCredentials ? "Your application takes over" : "Until one is set below"
                    variant: "caption"
                    emphasis: "dim"
                    elide: Text.ElideRight
                }
            }

            FieldRow {
                label: Translation.tr("Client ID")
                InputField {
                    cornerRadius: implicitHeight / 2
                    Layout.fillWidth: true
                    placeholder: "1234567890123456789"
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
                    placeholder: Discord.hasSecret ? "•••••••••••••• saved — blank keeps it" : "From the OAuth2 tab"
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
                Layout.topMargin: Tokens.spacingXs
                spacing: Tokens.spacingMd

                StyledText {
                    Layout.fillWidth: true
                    variant: "caption"
                    elide: Text.ElideRight
                    text: Discord.credentialsError !== "" ? Discord.credentialsError
                        : Discord.credentialsBusy         ? "Saving…"
                        : root.dirty                      ? "Unsaved changes"
                        : root.savedOnce                  ? "Saved — Discord picks it up in a few seconds"
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

        Section {
            span:     1
            glyph:    "󰌹"
            title:    Translation.tr("Your own application")
            subtitle: Translation.tr("About a minute, once")
            help:     Translation.tr("Only needed if the shared sign-in fails. An application of your own is the dependable option.")
            accent:   Colors.of(QsWindow.window).primary
            bodySpacing: Tokens.spacingSm

            Step { n: 1; text: Translation.tr("discord.com/developers/applications → New Application (any name).") }
            Step { n: 2; text: Translation.tr("General Information → copy the Application ID into Client ID.") }
            Step { n: 3; text: Translation.tr("OAuth2 → Reset Secret, copy it; add http://localhost under Redirects.") }
            Step { n: 4; text: Translation.tr("Save here, then approve Discord's prompt once.") }
        }

        // ── Call log ──────────────────────────────────────────────────────────
        // The scoreboard on the voice panel's Board tab. Discord's RPC has no friends list, so it can only count
        // who shared your call: hide anyone you don't want from the board there.
        Section {
            span:     1
            glyph:    "󰋚"
            title:    Translation.tr("Call log")
            subtitle: root.logCount === 0 ? Translation.tr("Nobody yet")
                      : root.logCount === 1 ? Translation.tr("1 person kept") : Translation.tr("%1 people kept").arg(root.logCount)
            help:     Translation.tr("Keeps how long you have been in a call with each person, for the Board tab of the voice panel. Names and time only, on this computer, until you forget them — no server or channel names, no record of when each call was. Discord doesn't say who your friends are, so it counts everyone who joined; hide anyone from the board there.")
            accent:   Colors.of(QsWindow.window).primary

            actions: Toggle {
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.callLog
                onToggled: Config.callLog = !Config.callLog
            }
            PanelButton {
                capsule: true
                label: logLatch.armed ? Translation.tr("Sure?") : Translation.tr("Forget everyone")
                variant: logLatch.armed ? "primary" : "ghost"
                accent: Colors.of(QsWindow.window).danger
                enabled: root.logCount > 0
                onActivated: logLatch.trigger()
            }
        }

        // ── Keybinds + injection readiness ────────────────────────────────────
        // One card: the keybinds are ONLY used for injection, and a missing
        // xdotool is invisible until you press a button and nothing happens.
        // Full width — it carries two fields, a status dot AND a caption, and
        // squeezing it beside the other two left it the tallest card on the page.
        Section {
            span:     3
            glyph:    "󰌋"
            title:    Translation.tr("Screen share & camera")
            subtitle: !Config.discordEnabled ? "" : root.injectBlocker === "" ? "Ready" : "Can't press keys yet"
            help:     Translation.tr("Discord has no RPC command for these, so the shell presses Discord's own keybind. Set the same combinations as Discord → Settings → Keybinds; screen share has no default.")
            accent:   Colors.of(QsWindow.window).primary
            bodySpacing: Tokens.spacingSm

            actions: Rectangle {
                visible: Config.discordEnabled
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 8; implicitHeight: 8
                radius: width / 2
                color: root.injectBlocker === "" ? Colors.of(QsWindow.window).success : Colors.of(QsWindow.window).warning
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingXl

                FieldRow {
                    Layout.fillWidth: true
                    label: Translation.tr("Screen share")
                    InputField {
                        cornerRadius: implicitHeight / 2
                        Layout.fillWidth: true
                        placeholder: "ctrl+shift+s"
                        seed: root.draftShare
                        onEdited: function (v) { root.draftShare = v }
                    }
                }
                FieldRow {
                    Layout.fillWidth: true
                    label: Translation.tr("Camera")
                    InputField {
                        cornerRadius: implicitHeight / 2
                        Layout.fillWidth: true
                        placeholder: "ctrl+shift+v"
                        seed: root.draftCamera
                        onEdited: function (v) { root.draftCamera = v }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: Config.discordEnabled && root.injectBlocker !== ""
                text: root.injectBlocker
                variant: "caption"
                color: Config.discordEnabled && root.injectBlocker !== "" ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).fgDim
                wrapMode: Text.WordWrap
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
            text: fr.label
            variant: "body"
            emphasis: "muted"
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
