pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"
import "../../onboard"

// ── SetupPage — System › Setup ────────────────────────────────────────────────
// The first-run setup (SetupFlow: a scan, a checklist, one button) embedded at the top, then
// one grid of checks for the things it does not install: how Hyprland is wired, optional
// tools, Spotify's bridge, secrets.
//
// ── Less to read (2026-10-26) ─────────────────────────────────────────────────
// It was eight cards, each row a name AND a sentence AND, while outstanding, a command. Now a
// check is a mark, a name and at most one or two words of status ("Missing", "Off", "3 binds");
// a done one says nothing. The fix command is behind the row — tap an outstanding one to see
// it and copy it. Toggles are chips; the long explanations are in each chip's tooltip.
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

    readonly property int pkgTodo: {
        let n = 0
        for (const p of root.packages) if (p.blocker !== "" && !p.unknown) n++
        return n
    }
    readonly property int discordTodo: (Config.discordEnabled && !Discord.hasCredentials) ? 1 : 0
    // The flow's own steps (extras are never a to-do) plus the checks below it.
    readonly property int stepsTodo: Setup.ready ? Setup.steps.filter(x => x.state === "todo" && x.group !== "extras").length : 0
    readonly property int todo: root.stepsTodo + root.pkgTodo + root.discordTodo + (Setup.hyprReady ? 0 : 1)

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

    // A group's name over its checks, across both columns of the grid.
    component Heading: StyledText {
        Layout.fillWidth: true
        Layout.columnSpan: 2
        Layout.topMargin: Tokens.spacingSm
        variant: "caption"
        emphasis: "dim"
        font.weight: Font.DemiBold
    }


    SettingsPage {
        anchors.fill: parent
        bento: true

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
            span:     3
            glyph:    "󰐊"
            title:    Translation.tr("Set up")
            subtitle: !Setup.ready ? "Checking…" : root.stepsTodo === 0 ? "Done" : root.stepsTodo + " to do"
            help:     Translation.tr("Packages, the morphing plugin, Hyprland wiring, app theming and the optional extras — tick what you want and press the one button. The same thing the first-run window shows.")
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
        Section {
            span:     3
            glyph:    "󰄬"
            title:    Translation.tr("Checks")
            subtitle: root.todo - root.stepsTodo === 0 ? "All good" : (root.todo - root.stepsTodo) + " to do"
            help:     Translation.tr("How Hyprland is wired, the optional tools, Spotify's bridge and where secrets live. Tap one that needs attention for its fix.")
            accent:   (root.todo - root.stepsTodo) === 0 ? Colors.of(QsWindow.window).success : Colors.of(QsWindow.window).primary
            Component.onCompleted: Secrets.refresh()

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                columns: width >= 620 ? 2 : 1
                columnSpacing: Tokens.spacingXl
                rowSpacing: Tokens.spacingSm

                Heading { text: "Hyprland"; Layout.columnSpan: parent.columns }
                Check {
                    label:  Translation.tr("Starts with your session")
                    status: Setup.autostart ? "" : "Not started"
                    state:  root._state(Setup.autostart)
                    fix:    Setup.repoDir + "/scripts/install-autostart.sh"
                }
                Check {
                    label:  Translation.tr("Keybinds")
                    status: Setup.bindCount > 0 ? Setup.bindCount + (Setup.bindCount === 1 ? " bind" : " binds") : "None"
                    state:  root._state(Setup.bindCount > 0)
                    fix:    "hl.bind(\"SUPER + R\", hl.dsp.exec_cmd(\"qs ipc -c " + Setup.repoDir + " call launcher toggle\"))"
                }
                Check {
                    readonly property bool fine: Config.barOpacity >= 0.999 || Setup.barBlur === "on"
                    label:  Translation.tr("Bar blur")
                    status: fine ? "" : "No blur rule"
                    state:  root._state(fine)
                    fix:    "hl.layer_rule({ match = { namespace = \"^quickshell-bar$\" }, blur = true })"
                }
                // Only one thing can own org.freedesktop.Notifications, and the shell is built to.
                Check {
                    label:  Translation.tr("Notifications")
                    status: Setup.rivalNotifiers.length > 0 ? Setup.rivalNotifiers.join(", ") + " running" : ""
                    state:  root._state(Setup.rivalNotifiers.length === 0)
                    fix:    "killall " + Setup.rivalNotifiers.join(" ") + "   — then drop it from your autostart"
                }
                Check {
                    visible: Setup.rivalBars.length > 0
                    label:  Translation.tr("Another bar")
                    status: Setup.rivalBars.join(", ")
                    state:  "unknown"
                    fix:    "killall " + Setup.rivalBars.join(" ")
                }
                Check {
                    visible: Setup.rivalAgents.length > 0
                    label:  Translation.tr("Another agent is running")
                    status: Setup.rivalAgents.join(", ")
                    state:  Config.polkitAgent ? "todo" : "unknown"
                    fix:    "killall " + Setup.rivalAgents.join(" ") + "   — then drop it from your autostart"
                }

                Heading { text: "Tools"; Layout.columnSpan: parent.columns }
                Repeater {
                    model: root.packages

                    Check {
                        required property var modelData
                        readonly property bool unknown: modelData.unknown === true
                        readonly property bool ok: !unknown && modelData.blocker === ""

                        label:  modelData.name
                        status: unknown ? "Off" : ok ? "" : "Missing"
                        state:  unknown ? "unknown" : root._state(ok)
                        fix:    modelData.fix
                    }
                }

                Heading { text: "Spotify lyrics"; Layout.columnSpan: parent.columns }
                Check {
                    label:  Translation.tr("Spicetify")
                    status: SpotifyBridge.spicetifyPresent ? "" : "Missing"
                    state:  root._state(SpotifyBridge.spicetifyPresent)
                    fix:    "sudo pacman -S spicetify-cli"
                }
                Check {
                    label:  Translation.tr("Bridge extension")
                    status: SpotifyBridge.extensionPresent ? "" : "Not installed"
                    state:  root._state(SpotifyBridge.extensionPresent)
                    fix:    "cp quickshell-bridge.js \"$(spicetify path userdata)/Extensions/\""
                }
                Check {
                    label:  Translation.tr("Enabled in Spicetify")
                    status: SpotifyBridge.extensionEnabled ? "" : "Off"
                    state:  root._state(SpotifyBridge.extensionEnabled)
                    fix:    "spicetify config extensions quickshell-bridge.js && spicetify apply"
                }
                Check {
                    label:  Translation.tr("Listening")
                    state:  SpotifyBridge.state === "live" ? "ok"
                          : SpotifyBridge.state === "error" ? "todo" : "unknown"
                    status: SpotifyBridge.state === "live"     ? "Live"
                          : SpotifyBridge.state === "waiting"  ? "Waiting for Spotify"
                          : SpotifyBridge.state === "starting" ? "Starting…"
                          : SpotifyBridge.state === "error"    ? SpotifyBridge.lastError : "Off"
                }

                Heading { text: "Accounts"; Layout.columnSpan: parent.columns }
                Check {
                    label:  Translation.tr("Secrets")
                    status: Secrets.keyring === "running" ? "In the keyring"
                          : Secrets.keyring === "activatable" ? "Keyring can start"
                          : Secrets.keyring === "" ? "…" : "In files"
                    state:  Secrets.keyring === "running" ? "ok" : "unknown"
                }
                Check {
                    visible: Config.discordEnabled
                    label:  Translation.tr("Discord application")
                    status: Discord.hasCredentials ? "" : "No credentials"
                    state:  root._state(Discord.hasCredentials)
                    fix:    "Settings → Apps → Discord"
                }
            }
        }

        // ══ Options ═══════════════════════════════════════════════════════════
        Section {
            span:     3
            glyph:    "󰒓"
            title:    Translation.tr("Options")
            accent:   Colors.of(QsWindow.window).primary

            Flow {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                ToggleChip {
                    symbol: "security"
                    label:  Translation.tr("Password prompts")
                    hint:   Translation.tr("When pkexec or an app asks for your password, the dialog is the shell's own instead of hyprpolkitagent's. A session has one agent, so remove the other from your autostart first.")
                            + (AuthAgent.blocker() !== "" ? "  " + AuthAgent.blocker() : "")
                    active: Config.polkitAgent
                    onToggled: Config.polkitAgent = !Config.polkitAgent
                }
                ToggleChip {
                    symbol: "music_note"
                    label:  Translation.tr("Spotify listener stays up")
                    hint:   Translation.tr("Keep the lyrics listener running across shell reloads. Off restarts it with the shell.")
                    active: Config.spotifyBridgeDetached
                    onToggled: Config.spotifyBridgeDetached = !Config.spotifyBridgeDetached
                }
                ToggleChip {
                    symbol: "key"
                    label:  Secrets.busy ? "Moving…" : "Move keys to keyring"
                    hint:   Translation.tr("API keys and the Discord client secret are kept in the system keyring when one is running (new keys go there on their own); otherwise in 0600 files, as before. Moving the keys already in files verifies each one before the file's copy is dropped, and may ask your wallet to unlock.")
                            + (Secrets.result !== "" ? "  " + Secrets.result : "")
                    active: Secrets.inFile === 0 && Secrets.inKeyring > 0
                    available: !Secrets.busy && Secrets.blocker() === "" && Secrets.inFile > 0
                    onToggled: Secrets.migrate()
                }
            }

            // A failed hot reload leaves the old shell running and only says so in the log.
            SettingRow {
                label:  Translation.tr("Reload card")
                detail: ""
                TabStrip {
                    implicitWidth: 320
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
            span:     3
            glyph:    "󰆓"
            title:    Translation.tr("Shell presets")
            subtitle: Config.shellPresets.length === 0 ? "Nothing saved yet"
                                                       : Config.shellPresets.length + " saved"
            help:     Translation.tr("Every settings page, saved under a name; tap one to apply it. To use it on another machine: commit presets/shell.json, git pull there, and tap it. Bar presets (presets/bar.json) and desktop-widget placement (widgets.json) are their own files — commit them too if you want them.")
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
