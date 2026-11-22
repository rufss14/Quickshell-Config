pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"
import "../../onboard"

// ── SetupPage: System › Setup ────────────────────────────────────────────────
// The first-run setup (SetupFlow: a scan, a checklist, one button) in the first column, then the
// checks for the things it does not install, a group per topic (how Hyprland is wired, optional
// tools, Spotify's bridge, secrets) balanced in the columns beside it. The header's "N to do" is
// counted off the same rows the checks draw.
//
// ── Less to read ──────────────────────────────────────────────────────────────
// A check is a mark, a name and at most one or two words of status ("Missing", "Off", "3 binds");
// a done one says nothing. The fix command is behind the row — tap an outstanding one to see
// it and copy it. SetupFlow and the checks are tools and keep their own layout (each on one
// segment); the options and the presets are the settings of the page: rows you tap, with the
// long explanations in each row's tip. "Move keys to keyring" is a one-way action, so it is a
// button row, not a switch.
//
// Every status is asked of the service that owns it — NightLight / WallpaperEngine /
// LyricsTranslate blocker(), SpotifyBridge.setupBlocker(), Discord.hasCredentials, Setup's probes.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    function recheckAll() {
        Setup.recheck()
        SpotifyBridge.recheckSetup()
        NightLight.reprobe()
        WallpaperEngine.probe()
        Lens.refreshLangs()
    }

    function _state(done) { return done ? "ok" : "todo" }

    // Three named segments of the reload card's connected choice, each with its icon and label.
    readonly property int reloadWidth: Tokens.fieldHeight * 10

    readonly property var packages: [
        {
            name: "Night light", glyph: "󰖔",
            blocker: NightLight.blocker(),
            detail: "Warms the screen after dark.",
            fix: "sudo pacman -S hyprsunset      # or: gammastep"
        },
        {
            name: "Wallpaper Engine", glyph: "󰸉",
            blocker: WallpaperEngine.blocker(),
            detail: "Animated Workshop scenes. Images work fine without it.",
            fix: (Updates.helper || "paru") + " -S linux-wallpaperengine"
        },
        {
            name: "Music recognition", glyph: "󰎈",
            blocker: SongRec.blocker(false),
            detail: "The Now-Playing panel's \"what is this song?\" buttons.",
            fix: (Updates.helper || "paru") + " -S songrec"
        },
        {
            // Text and Translate in the snip tool (and Lens) read only what tesseract has data
            // for. With English alone, a Dutch, Japanese or Russian screenshot comes back empty
            // or as noise before translation even starts.
            name: Translation.tr("Reading other languages"), glyph: "󰗊",
            blocker: Lens.hasTesseract && Lens.onlyEnglish ? Translation.tr("Only English can be read") : "",
            unknown: !Lens.hasTesseract,
            detail: Translation.tr("Text and Translate in the snip tool read the languages installed for tesseract."),
            fix: "sudo pacman -S tesseract-data-nld tesseract-data-jpn tesseract-data-chi_sim   # …any tesseract-data-<code>"
        },
        {
            name: "Lyrics translation", glyph: "󰗊",
            blocker: LyricsTranslate.blocker(),
            unknown: !Config.lyricsTranslate,
            detail: "Translates lyrics on-device instead of over a public endpoint.",
            fix: LyricsTranslate.installHint
                 || ((Updates.helper || "paru") + " -S python-argostranslate")
        }
    ]

    // ── The checks, as data ───────────────────────────────────────────────────
    // One list per group, so the header's "N to do" is counted off the very rows drawn below it:
    // a row is flagged exactly when its state is "todo". (A "?" mark is information, not a to-do.)
    function _row(label, status, state, fix) { return { label: label, status: status, state: state, fix: fix || "" } }
    function _todoIn(rows) { return rows.filter(r => r.state === "todo").length }
    function _todoText(rows) { const n = root._todoIn(rows); return n === 0 ? Translation.tr("All good") : Translation.tr("%1 to do").arg(n) }
    function _tint(rows) { return root._todoIn(rows) === 0 ? Colors.of(QsWindow.window).success : Colors.of(QsWindow.window).primary }

    readonly property var hyprChecks: {
        const r = [
            root._row(Translation.tr("Starts with your session"), Setup.autostart ? "" : "Not started",
                      root._state(Setup.autostart), Setup.repoDir + "/scripts/install-autostart.sh"),
            root._row(Translation.tr("Keybinds"),
                      Setup.bindCount > 0 ? Setup.bindCount + (Setup.bindCount === 1 ? " bind" : " binds") : "None",
                      root._state(Setup.bindCount > 0),
                      "hl.bind(\"SUPER + R\", hl.dsp.exec_cmd(\"qs ipc -c " + Setup.repoDir + " call launcher toggle\"))"),
            // Only one thing can own org.freedesktop.Notifications, and the shell is built to.
            root._row(Translation.tr("Notifications"),
                      Setup.rivalNotifiers.length > 0 ? Setup.rivalNotifiers.join(", ") + " running" : "",
                      root._state(Setup.rivalNotifiers.length === 0),
                      "killall " + Setup.rivalNotifiers.join(" ") + "   # then drop it from your autostart")
        ]
        const blurFine = Config.barOpacity >= 0.999 || Setup.barBlur === "on"
        r.splice(2, 0, root._row(Translation.tr("Bar blur"), blurFine ? "" : "No blur rule", root._state(blurFine),
                                 "hl.layer_rule({ match = { namespace = \"^quickshell-bar$\" }, blur = true })"))
        if (Setup.rivalBars.length > 0)
            r.push(root._row(Translation.tr("Another bar"), Setup.rivalBars.join(", "), "unknown",
                             "killall " + Setup.rivalBars.join(" ")))
        if (Setup.rivalAgents.length > 0)
            r.push(root._row(Translation.tr("Another agent is running"), Setup.rivalAgents.join(", "),
                             Config.polkitAgent ? "todo" : "unknown",
                             "killall " + Setup.rivalAgents.join(" ") + "   # then drop it from your autostart"))
        return r
    }
    readonly property var toolChecks: root.packages.map(p => {
        const unknown = p.unknown === true
        const ok = !unknown && p.blocker === ""
        return root._row(p.name, unknown ? "Off" : ok ? "" : "Missing", unknown ? "unknown" : root._state(ok), p.fix)
    })
    readonly property var spotifyChecks: [
        root._row(Translation.tr("Spicetify"), SpotifyBridge.spicetifyPresent ? "" : "Missing",
                  root._state(SpotifyBridge.spicetifyPresent), "sudo pacman -S spicetify-cli"),
        root._row(Translation.tr("Bridge extension"), SpotifyBridge.extensionPresent ? "" : "Not installed",
                  root._state(SpotifyBridge.extensionPresent),
                  "cp quickshell-bridge.js \"$(spicetify path userdata)/Extensions/\""),
        root._row(Translation.tr("Enabled in Spicetify"), SpotifyBridge.extensionEnabled ? "" : "Off",
                  root._state(SpotifyBridge.extensionEnabled),
                  "spicetify config extensions quickshell-bridge.js && spicetify apply"),
        root._row(Translation.tr("Listening"),
                  SpotifyBridge.state === "live"     ? "Live"
                : SpotifyBridge.state === "waiting"  ? "Waiting for Spotify"
                : SpotifyBridge.state === "starting" ? "Starting…"
                : SpotifyBridge.state === "error"    ? SpotifyBridge.lastError : "Off",
                  SpotifyBridge.state === "live" ? "ok" : SpotifyBridge.state === "error" ? "todo" : "unknown")
    ]
    readonly property var accountChecks: {
        const r = [root._row(Translation.tr("Secrets"),
                             Secrets.keyring === "running" ? "In the keyring"
                           : Secrets.keyring === "activatable" ? "Keyring can start"
                           : Secrets.keyring === "" ? "…" : "In files",
                             Secrets.keyring === "running" ? "ok" : "unknown")]
        if (Config.discordEnabled)
            r.push(root._row(Translation.tr("Discord application"), Discord.hasCredentials ? "" : "No credentials",
                             root._state(Discord.hasCredentials), "Settings → Apps → Discord"))
        return r
    }
    readonly property int checkTodo: root._todoIn(root.hyprChecks) + root._todoIn(root.toolChecks)
                                   + root._todoIn(root.spotifyChecks) + root._todoIn(root.accountChecks)

    // The flow's own steps (extras are never a to-do) plus the checks below it.
    readonly property int stepsTodo: Setup.ready ? Setup.steps.filter(x => x.state === "todo" && x.group !== "extras").length : 0
    readonly property int todo: root.stepsTodo + root.checkTodo

    // ── Check — one line: mark, name, a word of status ───────────────────────
    // Tap an outstanding one for its fix: a selectable monospace line and a copy chip. A command
    // beside something already installed is noise, so done ones are not tappable.
    component Check: ColumnLayout {
        id: ck
        property string label:  ""
        property string status: ""
        property string fix:    ""
        property string state:  "todo"      // ok | todo | unknown
        property bool   open:   false

        readonly property color tint: ck.state === "ok"      ? Colors.of(QsWindow.window).success
                                    : ck.state === "unknown" ? Colors.of(QsWindow.window).info
                                    :                          Colors.of(QsWindow.window).warning
        readonly property string mark: ck.state === "ok" ? "check_circle" : ck.state === "unknown" ? "help" : "error"
        readonly property bool expandable: ck.state !== "ok" && ck.fix !== ""

        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingXs

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm

            MaterialIcon { name: ck.mark; fill: ck.state === "ok" ? 1 : 0; variant: "caption"; color: ck.tint }
            StyledText {
                Layout.fillWidth: true
                text: ck.label
                variant: "body"
                elide: Text.ElideRight
            }
            StyledText {
                text: ck.status
                visible: text !== ""
                variant: "caption"
                color: ck.state === "ok" ? Colors.of(QsWindow.window).fgDim : ck.tint
            }
            MaterialIcon {
                visible: ck.expandable
                name: ck.open ? "expand_less" : "expand_more"
                variant: "caption"
                color: Colors.of(QsWindow.window).fgDim
            }

            TapHandler {
                enabled: ck.expandable
                onTapped: ck.open = !ck.open
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.leftMargin: Tokens.spacingLg
            visible: ck.expandable && ck.open
            spacing: Tokens.spacingSm

            TextEdit {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                text: ck.fix
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                color: Colors.of(QsWindow.window).fgMuted
                selectionColor: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.35)
                font.family: Tokens.fontMono
                font.pixelSize: Tokens.fontCaption
            }
            ChipTray {
                ChipButton {
                    symbol: "content_copy"
                    onActivated: Clipboard.copyText(ck.fix)
                }
            }
        }
    }

    SettingsPage {
        anchors.fill: parent
        grouped: true
        groupLayout: "columns"

        glyph:     "󰄬"
        title:     Translation.tr("Setup")
        titleTail: root.todo === 0 ? "complete" : root.todo + " to do"
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  root.todo === 0 ? "Everything is set up" : "None of it stops the shell running"

        actions: ChipTray {
            ChipButton {
                label:  Translation.tr("Health check")
                symbol: "check_circle"
                tint:   Colors.of(QsWindow.window).primary
                onActivated: UiState.welcomeOpen = true
            }
            ChipButton {
                label:  Translation.tr("Re-check")
                symbol: "refresh"
                tint:   Colors.of(QsWindow.window).primary
                onActivated: root.recheckAll()
            }
        }

        // Deleting a shell preset is reversible, so it is — no confirm dialog on a list you
        // might be tidying ten entries out of.
        banner: UndoBar { id: undoBar }

        // ══ Set up ════════════════════════════════════════════════════════════
        Section {
            grouped:  true
            glyph:    "󰐊"
            title:    Translation.tr("Set up")
            subtitle: !Setup.ready ? "Checking…" : root.stepsTodo === 0 ? "Done" : root.stepsTodo + " to do"
            help:     Translation.tr("Packages, the morphing plugin, Hyprland wiring, app theming and the optional extras. Tick what you want and press the one button. The same thing the first-run window shows.")
            accent:   root.stepsTodo === 0 ? Colors.of(QsWindow.window).success : Colors.of(QsWindow.window).primary

            actions: ChipTray {
                ChipButton {
                    symbol: "terminal"
                    label:  Translation.tr("Copy command")
                    onActivated: Clipboard.copyText(Setup.setupCommand)
                }
            }

            SetupFlow {
                Layout.fillWidth: true
                Layout.fillHeight: false
                embedded: true
                listMax: 100000
            }
        }

        // ══ Checks ════════════════════════════════════════════════════════════
        // Every one of the optional ones disables its feature with a reason rather than
        // failing on click (the blocker() contract); this is where that reason is spelled out.
        // One group per topic, each one segment of marks you can tap, so the columns balance
        // against the flow beside them.
        Section {
            grouped:  true
            symbol:   "window"
            title:    Translation.tr("Hyprland")
            subtitle: root._todoText(root.hyprChecks)
            help:     Translation.tr("How Hyprland is wired and who owns the notifications. Tap one that needs attention for its fix.")
            accent:   root._tint(root.hyprChecks)

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                Repeater {
                    model: root.hyprChecks

                    Check {
                        required property var modelData
                        label:  modelData.label
                        status: modelData.status
                        state:  modelData.state
                        fix:    modelData.fix
                    }
                }
            }
        }

        Section {
            grouped:  true
            symbol:   "widgets"
            title:    Translation.tr("Tools")
            subtitle: root._todoText(root.toolChecks)
            help:     Translation.tr("Optional tools. Each feature that needs one is switched off with a reason until it is installed. Tap one for the command.")
            accent:   root._tint(root.toolChecks)

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                Repeater {
                    model: root.toolChecks

                    Check {
                        required property var modelData
                        label:  modelData.label
                        status: modelData.status
                        state:  modelData.state
                        fix:    modelData.fix
                    }
                }
            }
        }

        Section {
            grouped:  true
            symbol:   "music_note"
            title:    Translation.tr("Spotify lyrics")
            subtitle: root._todoText(root.spotifyChecks)
            help:     Translation.tr("The bridge that lets the shell read what Spotify is playing, for lyrics.")
            accent:   root._tint(root.spotifyChecks)

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                Repeater {
                    model: root.spotifyChecks

                    Check {
                        required property var modelData
                        label:  modelData.label
                        status: modelData.status
                        state:  modelData.state
                        fix:    modelData.fix
                    }
                }
            }
        }

        Section {
            grouped:  true
            symbol:   "key"
            title:    Translation.tr("Accounts")
            subtitle: root._todoText(root.accountChecks)
            help:     Translation.tr("Where API keys and the Discord client secret are kept.")
            accent:   root._tint(root.accountChecks)
            Component.onCompleted: Secrets.refresh()

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                Repeater {
                    model: root.accountChecks

                    Check {
                        required property var modelData
                        label:  modelData.label
                        status: modelData.status
                        state:  modelData.state
                        fix:    modelData.fix
                    }
                }
            }
        }

        // ══ Options ═══════════════════════════════════════════════════════════
        Section {
            grouped:  true
            glyph:    "󰒓"
            title:    Translation.tr("Options")
            accent:   Colors.of(QsWindow.window).primary

            SettingRow {
                rowTap: true
                label:  Translation.tr("Password prompts")
                detail: AuthAgent.blocker() !== "" ? AuthAgent.blocker()
                      : Config.polkitAgent ? Translation.tr("The shell's own dialog")
                      : Translation.tr("Left to another agent")
                help:   Translation.tr("When pkexec or an app asks for your password, the dialog is the shell's own instead of hyprpolkitagent's. A session has one agent, so remove the other from your autostart first.")
                onTapped: Config.polkitAgent = !Config.polkitAgent

                Toggle {
                    accent:  Colors.of(QsWindow.window).primary
                    checked: Config.polkitAgent
                    onToggled: Config.polkitAgent = !Config.polkitAgent
                }
            }

            SettingRow {
                rowTap: true
                label:  Translation.tr("Spotify listener stays up")
                detail: Config.spotifyBridgeDetached ? Translation.tr("Keeps running across reloads")
                                                     : Translation.tr("Restarts with the shell")
                help:   Translation.tr("Keep the lyrics listener running across shell reloads. Off restarts it with the shell.")
                onTapped: Config.spotifyBridgeDetached = !Config.spotifyBridgeDetached

                Toggle {
                    accent:  Colors.of(QsWindow.window).primary
                    checked: Config.spotifyBridgeDetached
                    onToggled: Config.spotifyBridgeDetached = !Config.spotifyBridgeDetached
                }
            }

            // One way and not a state to flip back, so a button. Same guard as ever: nothing to
            // move, a move already running, or no keyring to move into disables it, with the reason.
            SettingRow {
                id: keyRow
                readonly property bool canMove: !Secrets.busy && Secrets.blocker() === "" && Secrets.inFile > 0

                rowTap: true
                enabled: keyRow.canMove
                opacity: keyRow.enabled ? 1 : 0.4
                label:  Secrets.busy ? Translation.tr("Moving…") : Translation.tr("Move keys to keyring")
                detail: Secrets.blocker() !== "" ? Secrets.blocker()
                      : Secrets.inFile > 0 ? Translation.tr("%1 still in files").arg(Secrets.inFile)
                      : Secrets.inKeyring > 0 ? Translation.tr("All in the keyring")
                      : Translation.tr("No keys saved yet")
                help:   Translation.tr("API keys and the Discord client secret are kept in the system keyring when one is running (new keys go there on their own); otherwise in 0600 files, as before. Moving the keys already in files verifies each one before the file's copy is dropped, and may ask your wallet to unlock.")
                        + (Secrets.result !== "" ? "  " + Secrets.result : "")
                onTapped: Secrets.migrate()

                PanelButton {
                    capsule: true
                    symbol: "key"
                    label:  Translation.tr("Move")
                    enabled: keyRow.canMove
                    onActivated: Secrets.migrate()
                }
            }

            // A failed hot reload leaves the old shell running and only says so in the log.
            SettingRow {
                label:  Translation.tr("Reload card")
                detail: ""
                TabStrip {
                    connected: true
                    // A SettingRow's control slot is a plain Item: size by implicitWidth.
                    implicitWidth: root.reloadWidth
                    accent: Colors.of(QsWindow.window).primary
                    model: [
                        { value: "failures", label: Translation.tr("Failures"), icon: "error" },
                        { value: "all",      label: Translation.tr("Always"),   icon: "refresh" },
                        { value: "off",      label: Translation.tr("Quickshell's"), icon: "close" }
                    ]
                    current: Config.reloadPopup
                    onPicked: function (v) { Config.reloadPopup = v }
                }
            }
        }

        // ══ Shell presets ═════════════════════════════════════════════════════
        // Every persisted preference under a name (`Config._dumpPrefs()`, stored in the repo's
        // presets/shell.json), so a fully-configured machine's settings travel to the next one.
        // This was a page of its own (ShellPresetPage); "set up this machine" and "set up the
        // next one" are one trip, so it is Setup's last card. The same machinery as Bar › Style's
        // presets, one level up: a bar preset is one page, a shell preset is all of them.
        //
        // Portability is git: presets/shell.json is tracked (the live config.json is not — it
        // churns on every slider drag). There is no file picker on purpose; the repo IS the
        // transport. It does NOT carry saved bar presets (presets/bar.json) or desktop-widget
        // placement (widgets.json): their own files, their own lives.
        Section {
            grouped:  true
            glyph:    "󰆓"
            title:    Translation.tr("Shell presets")
            subtitle: Config.shellPresets.length === 0 ? "Nothing saved yet"
                                                       : Config.shellPresets.length + " saved"
            help:     Translation.tr("Every settings page, saved under a name; tap one to apply it. To use it on another machine: commit presets/shell.json, git pull there, and tap it. Bar presets (presets/bar.json) and desktop-widget placement (widgets.json) are their own files. Commit them too if you want them.")
            accent:   Colors.of(QsWindow.window).primary

            PresetChips {
                accent:    Colors.of(QsWindow.window).primary
                presets:   Config.shellPresets
                isActive:  function (name) { return Config.shellPresetActive(name) }
                // The built-in preset can't be renamed or deleted (Config guards it too).
                isBuiltin: function (p) { return p.name === Config.defaultShellPresetName }
                // Only when a preset was saved by a different shell version.
                badgeFor:  function (p) {
                    const v = p.version ?? ""
                    return v !== "" && v !== Config.version ? "v" + v : ""
                }
                savePlaceholder: "Name this setup"
                onLoad:   function (name) { Config.applyShellPreset(name) }
                onSave:   function (name) { Config.saveShellPreset(name) }
                onRename: function (from, to) { Config.renameShellPreset(from, to) }
                onRemove: function (name) {
                    const rec = Config.shellPresets.find(function (x) { return x.name === name })
                    if (!rec) return
                    const keep = { name: rec.name, version: rec.version, config: rec.config }
                    Config.deleteShellPreset(keep.name)
                    undoBar.show("Deleted “" + keep.name + "”",
                                 function () { Config.restoreShellPreset(keep) })
                }
            }
        }
    }
}
