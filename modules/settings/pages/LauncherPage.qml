pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"
import "../../panels"

// ── LauncherPage — Launcher ───────────────────────────────────────────────────
// Everything the launcher needs configured, in one place: who answers `?`, where `>`
// runs commands, where a web search goes, and what it has learned from you.
//
// The AI half used to live in the launcher's own help sheet, which meant a panel you
// summon with a keystroke and dismiss on Escape was also where you pasted an API key.
// That is a settings job. The sheet now only lists the keys.
//
// ── The key is write-only ─────────────────────────────────────────────────────
// Typed here and handed to scripts/ai-credentials.py over stdin (Ai.saveKey), which
// writes it 0600. It is never an argument, never written from QML, never read back:
// the page only ever learns the boolean beside each provider. The same route the
// Discord page uses for its client secret.
//
// ── The launcher's own field, at the top ──────────────────────────────────────
// The hero is LauncherField itself — the real search pill, inert — typing the same
// hints the launcher types when it is empty (Launcher.idleHints). It is the quickest
// way to learn the prefixes, and it can't drift from the launcher because it is the
// launcher's. Under it, Ask beside Search: two cards of the same height.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The provider chips, each marked when it already holds a key — so "set up" and
    // "selected" stay visibly separate.
    readonly property var providerChips: Ai.providers.map(p => ({
        value: p.id, label: p.label,
        glyph: p.id === "claudecode" ? (Ai.claudeCliFound ? "󰄬" : "")
                                     : (Ai.hasKey[p.id] === true ? "󰄬" : "")
    }))

    function saveKey(value) {
        if (value === "") return
        Ai.saveKey(Config.aiProvider, value)
        keyField.clear()
    }

    ArmLatch {
        id: forgetLatch
        onConfirmed: Launcher.clearHistory()
    }

    readonly property int remembered: Object.keys(Launcher.history).length

    // ── Site shortcuts: the raw rows, edited by index ─────────────────────────
    // Raw, not cleaned: a half-typed row stays on the page (marked invalid) instead of
    // vanishing from under the cursor. The launcher reads Launcher.webShortcuts, which is cleaned.
    readonly property var shortcutRows: Array.isArray(Config.launcherWebShortcuts) ? Config.launcherWebShortcuts : []
    function keyOk(k) { return /^[a-z0-9]{1,12}$/.test(String(k || "")) }
    function urlOk(u) { return /^https?:\/\/[^\s]*%s[^\s]*$/.test(String(u || "")) }
    function _commit(list) { Config.launcherWebShortcuts = list }
    function setShortcut(i, field, value) {
        const list = root.shortcutRows.map(r => Object.assign({}, r))
        if (!list[i]) return
        list[i][field] = value
        root._commit(list)
    }
    function removeShortcut(i) { root._commit(root.shortcutRows.filter((_, k) => k !== i)) }
    function addShortcut() {
        root._commit(root.shortcutRows.concat([{ key: "", name: "", url: "https://" }]))
    }

    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     "󰀻"
        title:     Translation.tr("App")
        titleTail: "launcher"
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  !Config.aiEnabled ? "? searches the web"
                 : Ai.blocker() !== "" ? ("Ask: " + Ai.blocker()) : ("? asks " + Ai.label)

        // ══ The field ═════════════════════════════════════════════════════════
        Section {
            span:   3
            glyph:  "󰍉"
            title:  Translation.tr("Prefixes")
            help:   Translation.tr("Typed into the launcher's empty field, a prefix switches its mode: > runs a command, ? asks, + installs a package, ; searches your clipboard, : finds an emoji. Sums, unit conversions and site shortcuts (yt cats) just work.")
            accent: Colors.of(QsWindow.window).primary

            PreviewStage {
                Layout.fillWidth: true
                Layout.preferredHeight: 76
                checkered: false

                LauncherField {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - Tokens.spacingXl * 2, 560)
                    height: 44
                    // Inert: it only shows. No focus, no keys, no clicks.
                    enabled: false
                    lead: "Search apps"
                    hints: Launcher.idleHints
                    placeholder: Translation.tr("Search apps")
                }
            }
        }

        // ══ What it answers ═══════════════════════════════════════════════════
        // Everything the launcher does beyond launching an app, each its own switch. Off, the
        // launcher simply doesn't offer it: no row, no mode, nothing sent.
        Section {
            span:     3
            symbol:   "tune"
            title:    Translation.tr("Results")
            subtitle: Translation.tr("What it answers, and how much of it")
            accent:   Colors.of(QsWindow.window).primary

            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm

                ToggleChip {
                    symbol: "bolt"
                    label:  Translation.tr("Shell actions")
                    hint:   Translation.tr("Night light, game mode, the power menu and the rest of what the shell can do, as results when you type their name.")
                    active: Config.launcherActions
                    onToggled: Config.launcherActions = !Config.launcherActions
                }
                ToggleChip {
                    symbol: "settings"
                    label:  Translation.tr("Settings")
                    hint:   Translation.tr("Three letters or more also search Settings; picking one opens its page.")
                    active: Config.launcherSettings
                    onToggled: Config.launcherSettings = !Config.launcherSettings
                }
                ToggleChip {
                    symbol: "calculate"
                    label:  Translation.tr("Calculator")
                    hint:   Translation.tr("Sums and unit conversions answer in the launcher: 12*8, 10 km to mi.")
                    active: Config.launcherCalc
                    onToggled: Config.launcherCalc = !Config.launcherCalc
                }
                ToggleChip {
                    symbol: "package"
                    label:  Translation.tr("Install with +")
                    hint:   Translation.tr("A line starting with + searches the repos and installs a package through the update runner.")
                    active: Config.launcherPackages
                    onToggled: Config.launcherPackages = !Config.launcherPackages
                }
                ToggleChip {
                    symbol: "content_paste"
                    label:  Translation.tr("Clipboard with ;")
                    hint:   Translation.tr("A line starting with ; searches what you copied. Enter puts the entry back on the clipboard. Off, ; is just a semicolon.")
                    active: Config.launcherClipboard
                    onToggled: Config.launcherClipboard = !Config.launcherClipboard
                }
                ToggleChip {
                    symbol: "emoji_emotions"
                    label:  Translation.tr("Emoji with :")
                    hint:   Emoji.blocker() !== "" ? Emoji.blocker()
                            : "A line starting with : finds an emoji by name. Enter copies it; the ones you pick most come first."
                    available: Emoji.blocker() === ""
                    active: Config.launcherEmoji
                    onToggled: Config.launcherEmoji = !Config.launcherEmoji
                }
                ToggleChip {
                    symbol: "public"
                    label:  Translation.tr("AUR lookups")
                    hint:   Translation.tr("The AUR half of + sends the longest word you typed to aur.archlinux.org, and only in + mode. Off keeps + to the repos synced on this machine.")
                    available: Config.launcherPackages
                    active: Config.launcherAur
                    onToggled: Config.launcherAur = !Config.launcherAur
                }
                ToggleChip {
                    symbol: "history"
                    label:  Translation.tr("Learn from use")
                    hint:   Translation.tr("Apps you open often rise within equally good matches. Off, ranking is match quality alone and nothing new is remembered.")
                    active: Config.launcherLearn
                    onToggled: Config.launcherLearn = !Config.launcherLearn
                }
            }

            SliderRow {
                label:  Translation.tr("Rows shown")
                help:   Translation.tr("How many results fit before the list scrolls. The card grows by a row each.")
                from: 3
                to:   8
                step: 1
                value: Config.launcherRows
                readout: Config.launcherRows + ""
                onCommit: function (v) { Config.launcherRows = Math.round(v) }
            }
        }

        // ══ Ask ═══════════════════════════════════════════════════════════════
        Section {
            span:     1
            glyph:    "󰭹"
            title:    Translation.tr("Ask")
            accent:   Colors.of(QsWindow.window).primary
            subtitle: !Config.aiEnabled ? "Off — ? opens a web search"
                    : Ai.ready ? Ai.label + " is ready"
                    : "Needs a key"
            help:     Translation.tr("Start a launcher line with ? to ask. Nothing is sent until you press Enter. Off, ? opens a web search in your browser instead.")

            actions: Toggle {
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.aiEnabled
                onToggled: Config.aiEnabled = !Config.aiEnabled
            }

            ChipRow {
                enabled: Config.aiEnabled
                model:   root.providerChips
                current: Config.aiProvider
                onPicked: value => Config.aiProvider = value
            }

            // A key only exists for the HTTP providers; Claude Pro borrows the CLI's
            // own login, so there is nothing to paste.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                visible: Ai.needsKey
                enabled: Config.aiEnabled

                InputField {
                    cornerRadius: implicitHeight / 2
                    id: keyField
                    Layout.fillWidth: true
                    secret: true
                    placeholder: Ai.ready ? ("Replace " + Ai.label + " key…")
                                          : ("Paste your " + Ai.label + " API key…")
                    // Enter and focus loss both land here; the button below is the
                    // visible way to say the same thing.
                    onCommitted: value => root.saveKey(value)
                }
                PanelButton {
                    capsule: true
                    label: Translation.tr("Save")
                    variant: "primary"
                    enabled: keyField.text.length > 0
                    onActivated: root.saveKey(keyField.text)
                }
                PanelButton {
                    capsule: true
                    label: Translation.tr("Remove")
                    visible: Ai.ready
                    onActivated: Ai.removeKey(Config.aiProvider)
                }
                PanelButton {
                    capsule: true
                    label: Translation.tr("Get a key")
                    glyph: "󰖟"
                    visible: !Ai.ready && Ai.keyUrl !== ""
                    onActivated: Quickshell.execDetached(["xdg-open", Ai.keyUrl])
                }
            }

            // How to get going, only while it isn't — the "ready" state is the
            // subtitle above.
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: !Ai.ready && Ai.keyHelp !== ""
                text: Ai.keyHelp
                variant: "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }

            SettingRow {
                label:  Translation.tr("Model")
                help:   Translation.tr("Empty is the provider's default. Change it if a provider starts answering 404.")
                enabled: Config.aiEnabled
                InputField {
                    cornerRadius: implicitHeight / 2
                    implicitWidth: 150
                    seed: Config.aiModel
                    placeholder: "default"
                    mono: true
                    onCommitted: value => Config.aiModel = value.trim()
                }
            }

            // Only the subscription path has a session: the HTTP providers just send
            // the thread, and closing the launcher drops it.
            SettingRow {
                visible: !Ai.needsKey
                enabled: Config.aiEnabled
                label:   Translation.tr("Session")
                detail:  Translation.tr("Kept between questions")
                help:    Translation.tr("One Claude session named AppLauncher, kept between questions. Clears on reboot.")
                PanelButton {
                    capsule: true
                    label: Translation.tr("New")
                    glyph: "󰑐"
                    onActivated: Ai.resetSession()
                }
            }

            SettingRow {
                visible: Config.aiProvider === "gemini"
                enabled: Config.aiEnabled
                label:   Translation.tr("Search the web first")
                help:    Translation.tr("Gemini only. The question also reaches the search backend.")
                Toggle {
                    checked: Config.aiGrounding
                    onToggled: Config.aiGrounding = !Config.aiGrounding
                }
            }
        }

        // ══ Run and search ════════════════════════════════════════════════════
        Section {
            span:     1
            glyph:    "󰆍"
            title:    Translation.tr("Run & search")
            accent:   Colors.of(QsWindow.window).primary
            help:     "> runs a command in a terminal. A search that finds no app offers the web search instead."

            SettingRow {
                label:  Translation.tr("Terminal")
                detail: "Now: " + Terminal.resolved
                help:   "Where > commands run. Empty uses $TERMINAL, then " + Config.launcherTerminalFallback + "."
                InputField {
                    cornerRadius: implicitHeight / 2
                    implicitWidth: 130
                    seed: Config.launcherTerminal
                    placeholder: Terminal.resolved
                    mono: true
                    onCommitted: value => Config.launcherTerminal = value.trim()
                }
            }

            SettingRow {
                label:  Translation.tr("Search engine")
                help:   Translation.tr("The address a web search opens; %s is replaced by what you typed.")
                InputField {
                    cornerRadius: implicitHeight / 2
                    implicitWidth: 250
                    seed: Config.webSearchUrl
                    placeholder: "https://duckduckgo.com/?q=%s"
                    mono: true
                    // A URL with no %s would send the same page for every query.
                    invalid: text.length > 0 && text.indexOf("%s") < 0
                    onCommitted: value => {
                        if (value.indexOf("%s") >= 0) Config.webSearchUrl = value.trim()
                    }
                }
            }

            SettingRow {
                label:  Translation.tr("Engine name")
                help:   Translation.tr("What the launcher calls it where it offers a search.")
                InputField {
                    cornerRadius: implicitHeight / 2
                    implicitWidth: 130
                    seed: Config.webSearchName
                    onCommitted: value => Config.webSearchName = value.trim()
                }
            }

            // ── What it learned ───────────────────────────────────────────────
            SettingRow {
                label:  Translation.tr("History")
                detail: root.remembered + (root.remembered === 1 ? " app remembered" : " apps remembered")
                help:   Translation.tr("Apps you open often rise within equally good matches. Only app ids and counts are kept — never what you typed.")
                PanelButton {
                    capsule: true
                    label: forgetLatch.armed ? "Sure?" : "Forget"
                    variant: forgetLatch.armed ? "primary" : "normal"
                    accent: Colors.of(QsWindow.window).danger
                    enabled: root.remembered > 0
                    onActivated: forgetLatch.trigger()
                }
            }
        }

        // ══ Site shortcuts ════════════════════════════════════════════════════
        // `yt cats` → the shortcut's address with the rest of the line in place of %s. The
        // list is Config.launcherWebShortcuts; launcher.js drops anything that is not http(s)
        // with a %s or whose key cannot be typed as a first word, so a bad row here is
        // marked (and ignored) rather than ever reaching the browser.
        Section {
            span:     3
            symbol:   "language"
            title:    Translation.tr("Site shortcuts")
            subtitle: Translation.tr("Type a key, a space, then what to search")
            accent:   Colors.of(QsWindow.window).primary
            help:     "yt cats opens YouTube's search for “cats”. The address needs https:// (or http://) and %s where the search goes."

            Repeater {
                model: root.shortcutRows

                delegate: RowLayout {
                    id: sc
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm

                    InputField {
                        cornerRadius: implicitHeight / 2
                        implicitWidth: 70
                        seed: sc.modelData.key
                        placeholder: "key"
                        mono: true
                        invalid: !root.keyOk(text.length > 0 ? text : sc.modelData.key)
                        onCommitted: value => root.setShortcut(sc.index, "key", value.trim().toLowerCase())
                    }
                    InputField {
                        cornerRadius: implicitHeight / 2
                        implicitWidth: 120
                        seed: sc.modelData.name
                        placeholder: Translation.tr("Name")
                        onCommitted: value => root.setShortcut(sc.index, "name", value.trim())
                    }
                    InputField {
                        cornerRadius: implicitHeight / 2
                        Layout.fillWidth: true
                        seed: sc.modelData.url
                        placeholder: "https://example.com/search?q=%s"
                        mono: true
                        invalid: !root.urlOk(sc.modelData.url)
                        onCommitted: value => root.setShortcut(sc.index, "url", value.trim())
                    }
                    PanelButton {
                        capsule: true
                        symbol: "delete"
                        onActivated: root.removeShortcut(sc.index)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                PanelButton {
                    capsule: true
                    label: Translation.tr("Add")
                    symbol: "add"
                    onActivated: root.addShortcut()
                }
                PanelButton {
                    capsule: true
                    label: Translation.tr("Reset to the starting set")
                    onActivated: Config.launcherWebShortcuts = Config.webShortcutDefaults
                }
                Item { Layout.fillWidth: true }
            }
        }
    }
}
