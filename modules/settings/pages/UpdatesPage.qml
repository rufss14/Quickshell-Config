pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"
import "../../../services/updatelog.js" as UL

// ── UpdatesPage ───────────────────────────────────────────────────────────────
// What's pending, and how to install it.
//
// ── Grouped, with the list as one full-width segment ──────────────────────────
// The page answers one question, "what's waiting?", and the answer is a LIST. So the first
// row of columns is the summary and the install group (the number, and the password with
// the buttons that spend it), the list is a full-width group under them, and the small
// groups (history, the shell's own update, Discord, notices) balance in columns below.
// A list stays one segment (a window with its own scroll), not one segment per package.
//
// ── Everything installs HERE ──────────────────────────────────────────────────
// Both actions — the whole upgrade and a chosen subset — run on this page and stream into
// the pane where the list was. No terminal, and no handoff to the overlay panel; that
// panel is still what the BAR's update pill opens, but a page with its own password field
// shouldn't send you somewhere else to type it again.
//
// `Process.stdinEnabled` + `write()` are what make it possible: the sudo password goes to
// the process directly, so no TTY is needed and the password never reaches a command
// line. See Updates.installAll() / installSelected().
//
// Only OFFICIAL packages can't be installed individually — that's a partial upgrade and
// it breaks the system, so the rows offer no way to try.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Refreshed on open: the service polls every 10 minutes, which is right for a bar
    // pill and too stale for a page you deliberately navigated to.
    onVisibleChanged: if (root.visible) { Updates.check(); Updates.refreshNews() }

    // ── Recently changed ──────────────────────────────────────────────────────
    // The tail of pacman's own log: what actually got upgraded/installed/removed and
    // when. This is the page's memory — a list of pending updates says what's coming,
    // this says what happened, and after a run it's the receipt.
    // Read from Updates.history (one parse of the log for the whole shell, not a
    // second read of pacman.log here). updatelog.js recentChanges flattens it.
    readonly property var recentChanges: UL.recentChanges(Updates.history, 10)   // [{ date, action, name, to }], newest first
    Component.onCompleted: Updates.loadHistory()

    // "Last updated 3 days ago" — free context from the same history, read once here
    // rather than reimplemented everywhere it's shown (the summary card and the
    // up-to-date empty state both use it).
    readonly property string lastUpdatedText: {
        if (root.recentChanges.length === 0) return Translation.tr("No recorded updates yet")
        const days = Math.floor((Date.now() - new Date(root.recentChanges[0].date)) / 86400000)
        if (days <= 0) return Translation.tr("Last updated today")
        if (days === 1) return Translation.tr("Last updated yesterday")
        return Translation.tr("Last updated %1 days ago").arg(days)
    }

    // Re-read after a run finishes: the log just grew, and the card should show it.
    Connections {
        target: Updates
        function onRunDoneChanged() { if (Updates.runDone) Updates.loadHistory() }
    }

    // ── Selection ─────────────────────────────────────────────────────────────
    // Keyed by package name in a plain object. Reassigned rather than mutated on every
    // toggle — QML only re-evaluates bindings on a property CHANGE, and mutating an
    // object in place doesn't emit one, so the checkboxes would never redraw. (Audio.qml
    // hit exactly this with its client cache; the same rule, the same fix.)
    property var selected: ({})

    // Which source the list shows: all | official | aur | flatpak (the strip above it).
    property string source: "all"

    readonly property var selectedNames: Object.keys(root.selected).filter(k => root.selected[k])
    readonly property int selectedCount: root.selectedNames.length

    // Official packages are never selectable (partial upgrades break the system — see
    // Updates.applySelected). Guarded here as well as in the row, so a future caller
    // can't add a tick by going around the UI.
    function toggle(name) {
        const pkg = Updates.packages.filter(p => p.name === name)[0]
        if (!pkg || pkg.source === "official") return

        const next = Object.assign({}, root.selected)
        next[name] = !next[name]
        root.selected = next
    }

    // A finished run changes what's pending, so a stale tick could point at a package
    // that is no longer in the list.
    Connections {
        target: Updates
        function onPackagesChanged() { root.selected = ({}) }
    }

    // ── Which pane owns the space ─────────────────────────────────────────────
    // `showLog` is a plain property, not a binding on the service, because the fade has
    // to OUTLIVE the data. Clearing the run empties the log model instantly, so a
    // binding would blank the text and then fade an already-empty pane — the words would
    // vanish rather than fade. So: hide first, clear once the fade has finished.
    readonly property bool hasRun: Updates.runBusy || Updates.runLog.length > 0
    property bool showLog: false

    // The same "it went wrong" test the Dismiss button already spelled out inline, named
    // once so the progress strip and the button can't disagree about what failure is.
    readonly property bool runFailed:
        Updates.runDone && !Updates.runBusy && Updates.runExit !== 0

    onHasRunChanged: {
        if (!root.hasRun) return
        root.showLog = true
        // Cancel a pending clear: starting a new run inside the fade-out window would
        // otherwise have the old timer wipe the NEW run's first lines.
        clearAfterFade.stop()
    }

    // ── Returning to the list ─────────────────────────────────────────────────
    // On success the log has done its job and gets out of the way on its own. The delay
    // is long enough to read the "✓ Finished." line without being long enough to feel
    // like the page has hung.
    //
    // A FAILED run stays put. Auto-dismissing an error would hide the only explanation
    // of what went wrong — a rejected password, a build failure — and leave the packages
    // still sitting in the list with no reason given. That one waits to be dismissed.
    Timer {
        running: Updates.runDone && !Updates.runBusy && Updates.runExit === 0
        interval: 2200
        onTriggered: root.returnToList()
    }

    function returnToList() {
        root.showLog = false     // fade out with the text still in place
        clearAfterFade.restart() // then drop the data, once nothing is showing it
    }

    Timer {
        id: clearAfterFade
        // A little past the fade so the clear lands on an already-invisible pane. Reads
        // Motion.standard rather than hardcoding 150, so it still lines up if the user
        // scales motion or turns it off.
        interval: Motion.standard + 40
        onTriggered: {
            Updates.clearRun()
            // The list is stale the moment an install succeeds — the packages just
            // installed are still in it. Re-check so what faded back in becomes true.
            Updates.check()
        }
    }

    readonly property bool needsPassword: Updates.selectionNeedsPassword(root.selectedNames)

    // The install runs HERE, in this page, with its output below — not in a terminal and
    // not in the overlay panel. Only the full system upgrade hands off, because that one
    // already has a purpose-built panel.
    function runSelected() {
        if (root.selectedCount === 0 || Updates.runBusy) return
        if (root.needsPassword && passField.text.length === 0) return
        Updates.installSelected(root.selectedNames, passField.text)
        passField.clear()      // not kept a moment longer than the call needs it
    }

    function runVencord() {
        if (Updates.runBusy || passField.text.length === 0) return
        Updates.installVencord(passField.text)
        passField.clear()
    }

    // Runs here too, on the same runner and into the same log — not the overlay panel.
    // UpdatePanel is still what the BAR's update pill opens; this page is now
    // self-contained, so there is one password field and one place to watch.
    function runFullUpdate() {
        // The field is up with nothing pending (for Re-patch), so Enter must not start an upgrade.
        if (Updates.total === 0 || Updates.runBusy || passField.text.length === 0) return
        Updates.installAll(passField.text)
        passField.clear()
    }

    SettingsPage {
        anchors.fill: parent

        grouped:     true
        groupLayout: "columns"
        glyph:       Updates.total > 0 ? "󰚰" : "󰄬"        // update / check
        headerShape: "sunny"
        title:       Translation.tr("Updates")
        titleTail:   Updates.checking ? Translation.tr("checking…")
                   : Updates.total > 0 ? Translation.tr("%1 pending").arg(Updates.total) : ""
        accent:      Updates.total > 0 ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).success

        subtitle: Updates.hasError
                ? Translation.tr("Couldn't read the package database. Try again in a moment.")
                : Updates.checking ? Translation.tr("Asking the mirrors what's changed.")
                : Updates.total === 0 ? Translation.tr("Everything is up to date.")
                : Updates.count + " official  ·  " + Updates.aurCount + " AUR"
                  + (Updates.hasFlatpak ? "  ·  " + Updates.flatpakCount + " Flatpak" : "")

        // The one Check on the page: the packages and the shell's own releases together.
        actions: ChipTray {
            ChipButton {
                readonly property bool busy: Updates.checking || ShellUpdate.checking
                symbol:  "refresh"
                label:   busy ? Translation.tr("Checking…") : Translation.tr("Check")
                tint:    Colors.of(QsWindow.window).primary
                enabled: !busy
                iconAngle: busy ? checkSpin.angle : 0
                onActivated: { Updates.check(); ShellUpdate.check() }

                QtObject {
                    id: checkSpin
                    property real angle: 0
                    NumberAnimation on angle {
                        running: Updates.checking || ShellUpdate.checking
                        from: 0; to: 360
                        duration: Motion.spin
                        loops: Animation.Infinite
                    }
                }
            }
        }

        // ══ Interactive prompt ═══════════════════════════════════════════════
        // pacman/yay asked something (a conflict, a replacement, a provider choice, a
        // confirmation) and the run is blocked on stdin until it's answered. Cancel is always
        // in the header too, so a question the parser didn't anticipate can never wedge the update.
        Section {
            grouped:  true
            fullRow:  true
            visible:  Updates.awaitingInput
            symbol:   "help"
            title:    Translation.tr("The update needs your input")
            accent:   Colors.of(QsWindow.window).focus

            actions: ChipTray {
                ChipButton {
                    symbol: "close"
                    label:  Translation.tr("Cancel run")
                    tint:   Colors.of(QsWindow.window).danger
                    onActivated: Updates.cancelRun()
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                text: Updates.promptText
                variant: "caption"
                color: Colors.of(QsWindow.window).fg
                font.family: Tokens.fontMono
                wrapMode: Text.WrapAnywhere
            }

            // Yes / No: the default answer is the filled one.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                visible: Updates.promptKind === "yesno"

                PanelButton {
                    capsule: true
                    label: Translation.tr("Yes")
                    glyph: "󰄬"
                    variant: Updates.promptDefault === "y" ? "primary" : "normal"
                    onActivated: Updates.answerYes()
                }
                PanelButton {
                    capsule: true
                    label: Translation.tr("No")
                    variant: Updates.promptDefault === "n" ? "primary" : "normal"
                    onActivated: Updates.answerNo()
                }
            }

            // Provider number / password / anything else the process asks.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                visible: Updates.promptKind !== "yesno"
                onVisibleChanged: if (visible) answerField.forceFocus()

                InputField {
                    id: answerField
                    cornerRadius: implicitHeight / 2
                    Layout.fillWidth: true
                    secret: Updates.promptKind === "password"
                    placeholder: Updates.promptKind === "password" ? Translation.tr("Password")
                        : Updates.promptKind === "number"
                            ? (Updates.promptDefault !== ""
                                ? Translation.tr("A number (default %1)").arg(Updates.promptDefault)
                                : Translation.tr("A number"))
                            : Translation.tr("Type your answer, then Send")
                    onAccepted: function (v) { Updates.answer(v); answerField.clear() }
                }
                PanelButton {
                    capsule: true
                    label: Translation.tr("Send")
                    glyph: "󰅂"
                    variant: "primary"
                    onActivated: { Updates.answer(answerField.text); answerField.clear() }
                }
            }
        }

        // ══ What's waiting ═══════════════════════════════════════════════════
        // The number, what kind it is, and how much of each. Paired with the install group in
        // the first row of columns.
        Section {
            grouped:  true
            symbol:   Updates.total > 0 ? "update" : "check_circle"
            title:    Updates.total > 0 ? Translation.tr("Waiting")
                    : Updates.checking ? Translation.tr("Checking…") : Translation.tr("Up to date")
            subtitle: root.lastUpdatedText
            accent:   Updates.total > 0 ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).success

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingMd

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd

                    StyledText {
                        text: String(Updates.total)
                        font.pixelSize: Tokens.fontDisplay
                        font.weight: Font.Bold
                        font.features: ({ tnum: 1 })
                        color: Updates.total > 0 ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).success
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Updates.hasError ? Translation.tr("Package database unavailable")
                            : Updates.checking ? Translation.tr("Asking the mirrors…")
                            : Updates.total === 0 ? Translation.tr("You're all caught up")
                            : Updates.total === 1 ? Translation.tr("package waiting")
                            : Translation.tr("packages waiting")
                        variant: "body"
                        wrapMode: Text.WordWrap
                    }
                }

                // Official / AUR / Flatpak, proportional and countable.
                CompositionStrip {
                    Layout.fillWidth: true
                    official: Updates.count
                    aur:      Updates.aurCount
                    flatpak:  Updates.flatpakCount
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingLg
                    CountRow {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        glyph: "󰏗"
                        label: Translation.tr("Official")
                        value: Updates.count
                        tint:  Colors.of(QsWindow.window).focus
                    }
                    CountRow {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        glyph: "󰣇"
                        label: "AUR"
                        value: Updates.aurCount
                        tint:  Colors.of(QsWindow.window).info
                        // No helper means we cannot know, and showing "0" would be a claim
                        // rather than a reading.
                        unknown: Updates.helper === ""
                    }
                    CountRow {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        glyph: "󰏓"
                        label: Translation.tr("Flatpak")
                        value: Updates.flatpakCount
                        tint:  Colors.of(QsWindow.window).success
                        unknown: !Updates.hasFlatpak
                    }
                }
            }
        }

        // ══ Installing ═══════════════════════════════════════════════════════
        // The password, and the two ways to go. The password goes to the process over stdin,
        // never into a command line (Updates.installSelected); flatpak needs none (polkit's
        // own dialog). Always shown: it is also what Re-patch Vencord needs, and that must
        // work with nothing pending.
        Section {
            grouped:  true
            symbol:   "lock"
            title:    Translation.tr("Install")
            subtitle: root.selectedCount > 0 ? Translation.tr("%1 ticked").arg(root.selectedCount) : ""
            help:     Translation.tr("Official packages update together. Installing one on its own is a partial upgrade, which breaks programs that rely on the libraries left behind, so tick AUR and Flatpak ones to install them singly.")
            accent:   Colors.of(QsWindow.window).warning

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                InputField {
                    id: passField
                    cornerRadius: implicitHeight / 2
                    Layout.fillWidth: true
                    visible: !Updates.runBusy
                    secret: true
                    placeholder: Translation.tr("sudo password")
                    // With nothing pending the field is only there for the Vencord re-patch.
                    onAccepted: root.selectedCount > 0 ? root.runSelected()
                              : Updates.total > 0      ? root.runFullUpdate()
                              :                          root.runVencord()
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    visible: Updates.total > 0 || Updates.runBusy || root.selectedCount > 0

                    PanelButton {
                        capsule: true
                        Layout.fillWidth: true
                        visible: Updates.total > 0 || Updates.runBusy
                        variant: "primary"
                        accent:  Colors.of(QsWindow.window).warning
                        symbol:  "update"
                        label:   Updates.runBusy ? Translation.tr("Installing…") : Translation.tr("Update everything")
                        // This one runs pacman as root, so it needs the credential.
                        enabled: Updates.total > 0 && !Updates.runBusy && passField.text.length > 0
                        onActivated: root.runFullUpdate()
                    }
                    PanelButton {
                        capsule: true
                        visible: root.selectedCount > 0
                        variant: "normal"
                        symbol:  "checklist"
                        label:   Translation.tr("Install %1").arg(root.selectedCount)
                        enabled: !Updates.runBusy && (!root.needsPassword || passField.text.length > 0)
                        onActivated: root.runSelected()
                    }
                }
                // Says why the buttons are greyed out, so a disabled one is not a mystery.
                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    text: Updates.runBusy ? Translation.tr("Running. The log is below.")
                        : root.selectedCount > 0
                        ? (root.needsPassword
                            ? Translation.tr("Your password goes straight to sudo and isn't stored.")
                            : Translation.tr("Flatpak asks for permission in its own dialog."))
                        : Updates.total === 0
                        ? Translation.tr("Re-patch Vencord uses this password.")
                        : passField.text.length === 0
                        ? Translation.tr("Type your sudo password to enable the buttons.")
                        : Translation.tr("Official packages update together. Tick AUR and Flatpak ones to install them singly.")
                    variant: "micro"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                }
            }
        }

        // ══ The list ═════════════════════════════════════════════════════════
        // One full-width group: the source filter, the run's progress, and the packages (or the
        // run's log, which takes over the pane while installing: the list underneath is about to
        // be wrong anyway, the packages being installed are leaving it). Hidden when nothing is
        // pending: the summary above already says "up to date".
        Section {
            grouped:  true
            fullRow:  true
            visible:  root.showLog || Updates.total > 0
            symbol:   root.showLog ? "sync" : "inventory_2"
            title:    root.showLog ? Translation.tr("Installing") : Translation.tr("Packages")
            subtitle: root.showLog ? "" : Translation.tr("Tap an AUR or Flatpak row to tick it")
            help:     Translation.tr("Official packages can't be ticked: installing one on its own is a partial upgrade. Hold skips a package on the next full upgrade (--ignore); Flatpak has no way to skip one.")
            accent:   Updates.total > 0 ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).success

            actions: [
                ChipTray {
                    visible: !root.showLog && Updates.total > 0
                    ChipButton {
                        label: Translation.tr("All %1").arg(Updates.total)
                        on:    root.source === "all"
                        tint:  Colors.of(QsWindow.window).warning
                        onActivated: root.source = "all"
                    }
                    ChipButton {
                        visible: Updates.count > 0
                        label: Translation.tr("Official %1").arg(Updates.count)
                        on:    root.source === "official"
                        tint:  Colors.of(QsWindow.window).focus
                        onActivated: root.source = "official"
                    }
                    ChipButton {
                        visible: Updates.aurCount > 0
                        label: "AUR " + Updates.aurCount
                        on:    root.source === "aur"
                        tint:  Colors.of(QsWindow.window).info
                        onActivated: root.source = "aur"
                    }
                    ChipButton {
                        visible: Updates.flatpakCount > 0
                        label: Translation.tr("Flatpak %1").arg(Updates.flatpakCount)
                        on:    root.source === "flatpak"
                        tint:  Colors.of(QsWindow.window).success
                        onActivated: root.source = "flatpak"
                    }
                },
                BusyDot { running: Updates.runBusy; visible: Updates.runBusy },
                // Only on failure: a successful run clears itself, so a "Done" button there
                // would just be a race against the timer.
                ChipTray {
                    visible: root.runFailed
                    ChipButton {
                        symbol: "close"
                        label:  Translation.tr("Dismiss")
                        tint:   Colors.of(QsWindow.window).danger
                        onActivated: root.returnToList()
                    }
                }
            ]

            // ── Where the run has got to ──────────────────────────────────────
            // The runner's `:: [n/N]` markers are parsed in the service, so this is pure
            // presentation and shares one source with the bar's update panel. Only while
            // there's a run to describe: the log pane also holds finished output.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                visible: Updates.runBusy || Updates.runPhaseCount > 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd

                    // "2 of 3": absent for runs that have no phases at all (a Vencord patch,
                    // a selected install), where it would read as a one-step process that
                    // stalled at step one.
                    StyledText {
                        visible: Updates.runPhaseCount > 0
                        text: Translation.tr("Step %1 of %2").arg(Updates.runPhaseIndex).arg(Updates.runPhaseCount)
                        variant: "caption"
                        font.family: Tokens.fontMono
                        emphasis: "dim"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Updates.runCurrentItem
                        variant: "caption"
                        emphasis: Updates.runInHooks ? "dim" : "muted"
                        elide: Text.ElideRight
                    }
                    // The package counter, when a pacman transaction is running one.
                    StyledText {
                        visible: Updates.runPkgCount > 0 && !Updates.runInHooks
                        text: Updates.runPkgsDone + " / " + Updates.runPkgCount
                        variant: "caption"
                        font.family: Tokens.fontMono
                        emphasis: "dim"
                    }
                    StyledText {
                        text: Math.round(Updates.runProgress * 100) + "%"
                        variant: "caption"
                        font.family: Tokens.fontMono
                        font.bold: true
                        color: root.runFailed ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).focus
                    }
                }

                Meter {
                    Layout.fillWidth: true
                    value: Updates.runProgress
                    accent: root.runFailed ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).primary
                }

                // The hooks are the one stretch with no progress signal at all, and the
                // silence is what makes a live upgrade look hung. One line removes the question.
                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    visible: Updates.runInHooks
                    text: Translation.tr("Running post-transaction hooks. This can take a while on a kernel update. Don't reload the shell.")
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                }
            }

            // ── The pane: list, or the run's log ──────────────────────────────
            // A fixed window onto the list (its own scroll past ~10 rows), so a long upgrade
            // does not push the groups below it off the page. The segment is the well.
            Item {
                id: listBox
                Layout.fillWidth: true
                implicitHeight: root.showLog ? 240 : Math.min(listCol.implicitHeight, 300)

                Flickable {
                    id: logFlick
                    anchors.fill: parent
                    // Cross-fade with the list rather than swapping. `visible` still follows
                    // opacity so the faded-out pane stops taking clicks.
                    opacity: root.showLog ? 1.0 : 0.0
                    visible: opacity > 0.005
                    Behavior on opacity {
                        NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
                    }
                    contentHeight: logCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    // Pinned to the newest line, which is the one that matters while
                    // something is running.
                    onContentHeightChanged: if (Updates.runBusy)
                        logFlick.contentY = Math.max(0, logFlick.contentHeight - logFlick.height)

                    ColumnLayout {
                        id: logCol
                        width: logFlick.width - Tokens.scrollRoom   // clear of the Scrollbar
                        spacing: 0

                        Repeater {
                            model: Updates.runLog

                            StyledText {
                                required property var modelData
                                Layout.fillWidth: true
                                text: modelData.text
                                // stderr is not automatically failure (pacman and makepkg both
                                // report ordinary progress there), so it is muted, not alarmed.
                                // The exit code decides.
                                color: modelData.error ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).fgMuted
                                variant: "caption"
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
                Scrollbar { flickable: logFlick; visible: logFlick.visible }

                Flickable {
                    id: listFlick
                    anchors.fill: parent
                    opacity: root.showLog ? 0.0 : 1.0
                    visible: opacity > 0.005
                    Behavior on opacity {
                        NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
                    }
                    contentHeight: listCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    // Sectioned by source: the heading says it once instead of every row
                    // repeating a badge.
                    ColumnLayout {
                        id: listCol
                        width: listFlick.width - Tokens.scrollRoom   // clear of the Scrollbar
                        spacing: Tokens.spacingMd

                        UpdateSection {
                            Layout.fillWidth: true
                            visible: (root.source === "all" || root.source === "official") && rows.length > 0
                            title: Translation.tr("Official")
                            glyph: "󰏗"
                            tint:  Colors.of(QsWindow.window).focus
                            rows:  Updates.official
                        }
                        UpdateSection {
                            Layout.fillWidth: true
                            visible: (root.source === "all" || root.source === "aur") && rows.length > 0
                            title: Updates.helper ? "AUR · " + Updates.helper : "AUR"
                            glyph: "󰣇"
                            tint:  Colors.of(QsWindow.window).info
                            rows:  Updates.aur
                        }
                        UpdateSection {
                            Layout.fillWidth: true
                            visible: (root.source === "all" || root.source === "flatpak") && rows.length > 0
                            title: Translation.tr("Flatpak")
                            glyph: "󰏓"
                            tint:  Colors.of(QsWindow.window).success
                            rows:  Updates.flatpak
                        }
                    }
                }
                Scrollbar { flickable: listFlick; visible: listFlick.visible }
            }
        }

        // ══ Recently changed ═════════════════════════════════════════════════
        // Ahead of the small groups: it is the tallest of them, and the columns balance
        // best with the tall one first.
        Section {
            grouped:  true
            visible:  root.recentChanges.length > 0
            symbol:   "history"
            title:    Translation.tr("Recently changed")
            subtitle: root.lastUpdatedText
            help:     Translation.tr("The tail of pacman's own log: what was upgraded, installed or removed, and when. After a run it is the receipt.")

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingXs

                Repeater {
                    model: root.recentChanges
                    delegate: RowLayout {
                        id: histRow
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm

                        MaterialIcon {
                            glyph: histRow.modelData.action === "upgraded" ? "󰚰"
                                : histRow.modelData.action === "installed" ? "󰐕"
                                : "󰅖"
                            variant: "caption"
                            color: histRow.modelData.action === "upgraded" ? Colors.of(QsWindow.window).focus
                                 : histRow.modelData.action === "installed" ? Colors.of(QsWindow.window).success
                                 : Colors.of(QsWindow.window).fgDim
                        }
                        StyledText {
                            text: histRow.modelData.name
                            variant: "caption"
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            // "removed" has no surviving version to name.
                            text: histRow.modelData.action === "removed"
                                ? "" : histRow.modelData.to
                            variant: "caption"
                            emphasis: "dim"
                            elide: Text.ElideRight
                        }
                        StyledText {
                            text: histRow.modelData.date.slice(5)
                            variant: "caption"
                            emphasis: "dim"
                            font.family: Tokens.fontMono
                        }
                    }
                }
            }
        }

        // ══ Quicktest itself ═════════════════════════════════════════════════
        // The shell's own releases (services/ShellUpdate). Its Check is the header's; the one
        // action that is different, installing a release, is here, and only while there is one.
        Section {
            grouped:  true
            symbol:   "update"
            title:    Translation.tr("Quicktest")
            subtitle: ShellUpdate.available ? Translation.tr("%1 is available").arg(ShellUpdate.latest) : ""
            help:     Translation.tr("Updates to the shell itself: signed releases from GitHub. Needs no password, the shell lives in your own config folder.")
            accent:   (ShellUpdate.available || ShellUpdate.installing) ? Colors.of(QsWindow.window).primary
                    : ShellUpdate.error !== "" ? Colors.of(QsWindow.window).danger
                    : Colors.of(QsWindow.window).primary

            SettingRow {
                wrapDetail: true
                label:  ShellUpdate.installing ? Translation.tr("Updating Quicktest")
                      : ShellUpdate.error !== "" ? Translation.tr("Shell update stopped")
                      : Translation.tr("Quicktest %1").arg(ShellUpdate.current)
                detail: ShellUpdate.installing ? ShellUpdate.status
                      : ShellUpdate.error !== "" ? ShellUpdate.error
                      : ShellUpdate.available
                        ? (ShellUpdate.blocker !== "" ? ShellUpdate.blocker
                           : ShellUpdate.date ? Translation.tr("Released %1").arg(ShellUpdate.date) : "")
                      : ShellUpdate.checking ? Translation.tr("Checking for a new version…")
                      : ShellUpdate.checkFailed ? Translation.tr("Couldn't reach GitHub. Try again later.")
                      : ShellUpdate.checked ? Translation.tr("Up to date")
                      : ""

                BusyDot { visible: ShellUpdate.installing; running: visible; tint: Colors.of(QsWindow.window).primary }
                PanelButton {
                    capsule: true
                    visible: !ShellUpdate.installing && (ShellUpdate.available || ShellUpdate.error !== "")
                    enabled: ShellUpdate.available && ShellUpdate.blocker === ""
                    variant: "primary"
                    accent:  ShellUpdate.error !== "" ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).primary
                    symbol:  "download"
                    label:   ShellUpdate.error !== "" ? Translation.tr("Retry") : Translation.tr("Update")
                    onActivated: ShellUpdate.install()
                }
            }

            // The release notes, as qtrelease wrote them: a few lines here, the full page one click away.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                visible: ShellUpdate.available && !ShellUpdate.installing
                         && (ShellUpdate.notes !== "" || ShellUpdate.url !== "")

                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    visible: ShellUpdate.notes !== ""
                    text: ShellUpdate.notes
                    variant: "caption"
                    wrapMode: Text.WordWrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                }
                PanelButton {
                    visible: ShellUpdate.url !== ""
                    variant: "ghost"
                    glyph:   "󰏌"
                    label:   Translation.tr("Release notes")
                    onActivated: Qt.openUrlExternally(ShellUpdate.url)
                }
            }

            SettingRow {
                rowTap: true
                label:  Translation.tr("Check for new versions")
                detail: Config.shellUpdateCheck ? Translation.tr("Every 6 hours") : Translation.tr("Only when you press Check")
                help:   Translation.tr("Asks GitHub every 6 hours for a newer signed release of the shell.")
                onTapped: Config.shellUpdateCheck = !Config.shellUpdateCheck
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.shellUpdateCheck
                    onToggled: Config.shellUpdateCheck = !Config.shellUpdateCheck
                }
            }
        }

        // ══ Vencord ══════════════════════════════════════════════════════════
        // Separate from the package actions on purpose: it isn't a package update, pacman
        // can't see it, and Discord silently un-patches itself on every one of its own
        // updates, so it's a thing you redo, not a thing that happens on the way past. Uses the
        // password field above, which stays up with nothing pending.
        Section {
            grouped:  true
            symbol:   "refresh"
            title:    Translation.tr("Discord")
            accent:   Colors.of(QsWindow.window).info

            SettingRow {
                label:  Translation.tr("Re-patch Vencord")
                detail: passField.text.length > 0 ? "" : Translation.tr("Uses the sudo password above")
                help:   Translation.tr("Downloads the official VencordInstaller and runs it as root. Re-apply this after Discord updates itself and drops the patch.")

                PanelButton {
                    capsule: true
                    symbol:  "refresh"
                    label:   Translation.tr("Re-patch")
                    enabled: !Updates.runBusy && passField.text.length > 0
                    onActivated: root.runVencord()
                }
            }
        }

        // ══ Notices, only when they apply ════════════════════════════════════
        // ── Finish setup ──────────────────────────────────────────────────────
        // Shown here, where a new user looking at "packages" is most likely to be, when the
        // compositor wiring or the core packages aren't done. Hands off to the Setup page
        // rather than duplicating it.
        Section {
            grouped:  true
            visible:  !Setup.hyprReady || (Setup.coreProbed && !Setup.coreReady)
            symbol:   "check_circle"
            title:    Translation.tr("Finish setup")
            accent:   Colors.of(QsWindow.window).info

            SettingRow {
                wrapDetail: true
                label:  Translation.tr("Open setup")
                detail: (Setup.coreProbed && !Setup.coreReady)
                        ? (Setup.missingCore === 1 ? Translation.tr("1 core package is missing. Run ./setup.sh.")
                                                   : Translation.tr("%1 core packages are missing. Run ./setup.sh.").arg(Setup.missingCore))
                        : Translation.tr("Not wired into Hyprland yet. None of it stops the shell running.")

                PanelButton {
                    capsule: true
                    label:   Translation.tr("Open setup")
                    variant: "primary"
                    onActivated: UiState.openSettingsTo("SetupPage.qml")
                }
            }
        }

        // ── Reboot notice ─────────────────────────────────────────────────────
        // Only when a kernel or graphics module is in the list: the one consequence of an
        // upgrade that bites you later rather than at the time.
        Section {
            grouped:  true
            visible:  Updates.needsReboot
            symbol:   "warning"
            title:    Translation.tr("Reboot afterwards")
            accent:   Colors.of(QsWindow.window).warning

            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                text: Updates.rebootPackages.length === 1
                    ? Translation.tr("This upgrade replaces 1 kernel or driver package. Until you reboot, plugging in new hardware may not work, because the running kernel's modules will have been replaced on disk.")
                    : Translation.tr("This upgrade replaces %1 kernel or driver packages. Until you reboot, plugging in new hardware may not work, because the running kernel's modules will have been replaced on disk.").arg(Updates.rebootPackages.length)
                variant: "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }
        }

        // ── Arch news ─────────────────────────────────────────────────────────
        // Shown when the newest feed item post-dates your last full upgrade. The one thing
        // --noconfirm genuinely can't handle is an upgrade that needs a manual step, and
        // that's what these posts announce.
        Section {
            grouped:  true
            visible:  Updates.newsUnread
            symbol:   "newspaper"
            title:    Translation.tr("Arch news")
            accent:   Colors.of(QsWindow.window).warning

            SettingRow {
                rowTap: true
                wrapDetail: true
                label:  Updates.newsTitle
                detail: Translation.tr("Posted %1, after your last upgrade. Read it before a full upgrade.").arg(Updates.newsDate)
                onTapped: Qt.openUrlExternally(Updates.newsUrl)

                PanelButton {
                    capsule: true
                    variant: "normal"
                    accent:  Colors.of(QsWindow.window).warning
                    glyph:   "󰏌"
                    label:   Translation.tr("Read")
                    onActivated: Qt.openUrlExternally(Updates.newsUrl)
                }
            }
        }

        // ── Held back ─────────────────────────────────────────────────────────
        Section {
            grouped:  true
            visible:  Updates.heldPending.length > 0
            symbol:   "pause"
            title:    Translation.tr("Held back")
            accent:   Colors.of(QsWindow.window).warning

            SettingRow {
                wrapDetail: true
                label:  Updates.heldPending.length === 1 ? Translation.tr("1 package held")
                                                         : Translation.tr("%1 packages held").arg(Updates.heldPending.length)
                detail: Translation.tr("Skipped with --ignore on the next upgrade.")

                PanelButton {
                    capsule: true
                    variant: "normal"
                    label:   Translation.tr("Release all")
                    onActivated: Updates.clearHolds()
                }
            }
        }
    }

    // ══ Components ════════════════════════════════════════════════════════════

    // ── CompositionStrip ──────────────────────────────────────────────────────
    // Official/AUR/Flatpak side by side, widths proportional to their share of the
    // total — "how much, and of what kind" in one glance, ahead of the CountRows
    // that give the exact numbers. Same idea as Network's and Storage's composition
    // strips, built locally rather than pulled into a shared component for one page.
    //
    // Segments are sized by hand (not Layout.fillWidth ratios — QtQuick Layouts
    // doesn't guarantee proportional distribution from preferredWidth alone) so the
    // widths are exactly the fractions they claim to be.
    component CompositionStrip: Item {
        id: strip

        property int official: 0
        property int aur:      0
        property int flatpak:  0
        readonly property int total: strip.official + strip.aur + strip.flatpak

        implicitHeight: 8

        // Nothing pending: a flat, muted track rather than three invisible
        // zero-width segments — an empty bar should look empty, not blank.
        Rectangle {
            anchors.fill: parent
            radius: Tokens.radiusXs
            color:  Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.10)
            visible: strip.total === 0
        }

        Row {
            anchors.fill: parent
            visible: strip.total > 0
            spacing: 1   // a hairline seam between segments, not a gap in the bar

            Rectangle {
                width:  Math.round((strip.width - 2) * (strip.official / Math.max(strip.total, 1)))
                height: parent.height
                radius: Tokens.radiusXs
                color:  Colors.of(QsWindow.window).focus
            }
            Rectangle {
                width:  Math.round((strip.width - 2) * (strip.aur / Math.max(strip.total, 1)))
                height: parent.height
                radius: Tokens.radiusXs
                color:  Colors.of(QsWindow.window).info
            }
            Rectangle {
                width:  Math.round((strip.width - 2) * (strip.flatpak / Math.max(strip.total, 1)))
                height: parent.height
                radius: Tokens.radiusXs
                color:  Colors.of(QsWindow.window).success
            }
        }
    }

    // ── CountRow ──────────────────────────────────────────────────────────────
    component CountRow: RowLayout {
        id: cr

        property string glyph: ""
        property string label: ""
        property int    value: 0
        property color  tint:  Colors.of(QsWindow.window).focus
        property bool   unknown: false

        spacing: Tokens.spacingMd

        MaterialIcon { glyph: cr.glyph; color: cr.tint; variant: "body" }
        StyledText {
            Layout.fillWidth: true
            text: cr.label
            variant: "body"
            elide: Text.ElideRight
        }
        StyledText {
            text: cr.unknown ? "?" : String(cr.value)
            variant: "body"
            font.weight: Font.DemiBold
            emphasis: (cr.unknown || cr.value === 0) ? "dim" : "normal"
        }
    }

    // ── UpdateSection ─────────────────────────────────────────────────────────
    // One source's packages, under a heading that names it once. Hidden entirely when
    // empty — an "AUR (0)" heading is a row of furniture telling you nothing.
    component UpdateSection: ColumnLayout {
        id: sec

        property string title: ""
        property string glyph: ""
        property color  tint:  Colors.of(QsWindow.window).focus
        property var    rows:  []

        visible: sec.rows.length > 0
        spacing: Tokens.spacingSm

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacingSm

            MaterialIcon { glyph: sec.glyph; color: sec.tint; variant: "caption" }
            StyledText {
                text: sec.title
                color: sec.tint
                variant: "label"
                font.weight: Font.DemiBold
            }
            Badge { label: String(sec.rows.length); tint: sec.tint }
            Divider { Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter }
        }

        GridLayout {
            Layout.fillWidth: true
            // One column now: the list sits beside a rail, and two ~280px columns elided every
            // name that had a version to carry.
            columns: 1
            columnSpacing: Tokens.spacingXl
            rowSpacing: 0

            Repeater {
                model: sec.rows

                PackageRow {
                    required property var modelData
                    // The even-split idiom: fillWidth distributes the SURPLUS, so equal
                    // tiny preferred widths halve the grid regardless of name length.
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    pkg: modelData
                }
            }
        }
    }

    // ── PackageRow ────────────────────────────────────────────────────────────
    // One package, and what it's about to become. The version transition is the whole
    // point of the row — "linux 7.1.3.arch2-1 → 7.1.3.arch2-2" tells you it's a rebuild,
    // where a bare name tells you nothing.
    component PackageRow: Item {
        id: pr

        property var pkg: null

        // Official packages are not selectable — installing one on its own is a partial
        // upgrade, which breaks the rest of the system. The row simply offers no way to
        // do it rather than offering it with a warning attached: a warning you can click
        // past is still a door.
        readonly property bool selectable: (pr.pkg?.source ?? "") !== "official"
        readonly property bool picked: root.selected[pr.pkg?.name ?? ""] === true
        readonly property bool held:   Updates.isHeld(pr.pkg?.name ?? "")

        implicitHeight: Math.max(prRow.implicitHeight, Tokens.pillHeight)

        // The whole row is the hit target, not just the 16px box — a checkbox you have
        // to aim at is a checkbox you misclick.
        Rectangle {
            anchors.fill: parent
            anchors.rightMargin: Tokens.spacingSm
            radius: Tokens.radiusSm
            color: pr.picked                      ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.12)
                 : (prHover.hovered && pr.selectable) ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
                                                      : "transparent"
            Behavior on color { ColorAnimation { duration: Motion.respond } }
        }

        HoverHandler { id: prHover; enabled: pr.selectable }
        TapHandler {
            enabled: pr.selectable
            onTapped: root.toggle(pr.pkg?.name ?? "")
        }

        RowLayout {
            id: prRow
            anchors.left:  parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin:  Tokens.spacingSm
            anchors.rightMargin: Tokens.spacingMd
            spacing: Tokens.spacingMd

            // Reserved slot either way, so official and AUR names stay on one left edge
            // instead of the sections looking mis-indented against each other.
            Item {
                Layout.preferredWidth: 14
                Layout.preferredHeight: 14

                MaterialIcon {
                    anchors.centerIn: parent
                    visible: pr.selectable
                    glyph:  pr.picked ? "󰄲" : "󰄱"        // checked / unchecked
                    color: pr.picked ? Colors.of(QsWindow.window).focus : Colors.of(QsWindow.window).fgDim
                    variant: "caption"
                }
            }

            // No source badge: the section heading says it once.
            StyledText {
                Layout.fillWidth: true
                text: pr.pkg?.name ?? ""
                variant: "body"
                elide: Text.ElideRight
                opacity: pr.held ? 0.4 : 1.0
                font.strikeout: pr.held
            }

            // ── Version, or an honest absence ─────────────────────────────────
            // Flatpak's `remote-ls --updates` does not report the new version, so there
            // is nothing to put on the right of an arrow. Printing "1.2.3 →" with a blank
            // after it would look like a rendering fault; saying "update available" is
            // the same information without pretending to more.
            StyledText {
                readonly property bool hasTarget: (pr.pkg?.to ?? "") !== ""
                text: hasTarget ? (pr.pkg?.from ?? "") + "  →  " + pr.pkg.to
                                : Translation.tr("update available")
                variant: "caption"
                emphasis: "dim"
                elide: Text.ElideRight
                // Capped so a long version pair can't push the name into an ellipsis;
                // the name is what you scan for.
                Layout.maximumWidth: 210
            }

            // ── Hold ──────────────────────────────────────────────────────────
            // --ignore on the next run, not IgnorePkg: a hold you can see and undo,
            // available on official packages too (skipping one isn't a partial
            // upgrade; installing one alone is). Not Flatpak: `flatpak update` has no
            // exclude, so the hold couldn't be honoured. Worded, not a bare glyph: a
            // pause mark at the end of every row read as "00".
            PanelButton {
                capsule: true
                visible: (pr.pkg?.source ?? "") !== "flatpak"
                variant: "ghost"
                implicitHeight: 22
                accent: Colors.of(QsWindow.window).warning
                symbol: pr.held ? "play_arrow" : "pause"
                label:  pr.held ? Translation.tr("Held") : Translation.tr("Hold")
                onActivated: Updates.toggleHold(pr.pkg?.name ?? "")

                HelpTip {
                    text: pr.held ? Translation.tr("Held back: skipped on the next full upgrade. Tap to include it again.")
                                  : Translation.tr("Skip this package on the next full upgrade.")
                }
            }
        }
    }
}
