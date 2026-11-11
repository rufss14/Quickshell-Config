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
// ── Two columns, not three ────────────────────────────────────────────────────
// Sound and Network are three columns because they answer three separate questions. This
// page answers one — "what's waiting?" — and the answer is a LIST. A list wants length,
// so the layout is a narrow summary/actions rail beside a list that takes everything
// else, rather than a wide list chopped into thirds.
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
        if (root.recentChanges.length === 0) return "No recorded updates yet"
        const days = Math.floor((Date.now() - new Date(root.recentChanges[0].date)) / 86400000)
        if (days <= 0) return "Last updated today"
        if (days === 1) return "Last updated yesterday"
        return "Last updated " + days + " days ago"
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
        if (Updates.runBusy || passField.text.length === 0) return
        Updates.installAll(passField.text)
        passField.clear()
    }

    ColumnLayout {
        anchors.fill: parent
        // Its lists run to the bottom; they stop short of the window's edge like the
        // last card of every other page does.
        anchors.bottomMargin: Tokens.spacingXl
        spacing: Tokens.spacingMd

        PanelHeader {
            // The same header every Settings page wears (SettingsPage): a morphing badge, a headline.
            morph:     "sunny"
            chipSize:  Tokens.iconXl + Tokens.spacingLg
            titleVariant: "headline"
            subtitleVariant: "label"
            glyph:     Updates.total > 0 ? "󰚰" : "󰄬"        // update / check
            title:     Translation.tr("Updates")
            titleTail: Updates.checking ? "checking…"
                     : Updates.total > 0 ? Updates.total + " pending" : ""
            accent:    Updates.total > 0 ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).success

            subtitle: Updates.hasError
                    ? "Couldn't read the package database — try again in a moment."
                    : Updates.checking ? "Asking the mirrors what's changed."
                    : Updates.total === 0 ? "Everything is up to date."
                    : Updates.count + " official  ·  " + Updates.aurCount + " AUR"
                      + (Updates.hasFlatpak ? "  ·  " + Updates.flatpakCount + " Flatpak" : "")

            ChipTray {
                ChipButton {
                    symbol:  "refresh"
                    label:   Updates.checking ? "Checking…" : "Check"
                    tint:    Colors.of(QsWindow.window).primary
                    enabled: !Updates.checking
                    iconAngle: Updates.checking ? checkSpin.angle : 0
                    onActivated: Updates.check()

                    QtObject {
                        id: checkSpin
                        property real angle: 0
                        NumberAnimation on angle {
                            running: Updates.checking
                            from: 0; to: 360
                            duration: Motion.spin
                            loops: Animation.Infinite
                        }
                    }
                }
            }
        }

        // ══ What's waiting, and installing it ═════════════════════════════════
        // One card across the top: the number, what kind it is, and the way to act on it.
        // The page's question is "what is waiting?": one card answers it, not a rail of
        // nine beside the list.
        Section {
            Layout.fillWidth: true
            Layout.fillHeight: false
            symbol:   Updates.total > 0 ? "update" : "check_circle"
            title:    Updates.total > 0 ? Updates.total + (Updates.total === 1 ? " package waiting" : " packages waiting")
                    : Updates.checking ? "Checking…" : "Up to date"
            subtitle: root.lastUpdatedText
            accent:   Updates.total > 0 ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).success

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingXl

                // Official / AUR / Flatpak, proportional and countable.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm

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
                            glyph: "󰏗"
                            label: Translation.tr("Official")
                            value: Updates.count
                            tint:  Colors.of(QsWindow.window).focus
                        }
                        CountRow {
                            glyph: "󰣇"
                            label: "AUR"
                            value: Updates.aurCount
                            tint:  Colors.of(QsWindow.window).info
                            // No helper means we cannot know, and showing "0" would be a claim
                            // rather than a reading.
                            unknown: Updates.helper === ""
                        }
                        CountRow {
                            glyph: "󰏓"
                            label: Translation.tr("Flatpak")
                            value: Updates.flatpakCount
                            tint:  Colors.of(QsWindow.window).success
                            unknown: !Updates.hasFlatpak
                        }
                    }
                }

                // The password, and the two ways to go. The password goes to the process over
                // stdin, never into a command line (Updates.installSelected); flatpak needs none
                // (polkit's own dialog).
                ColumnLayout {
                    Layout.fillWidth: false
                    Layout.preferredWidth: 300
                    Layout.alignment: Qt.AlignTop
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    visible: Updates.total > 0 || Updates.runBusy

                    InputField {
                        id: passField
                        cornerRadius: implicitHeight / 2
                        Layout.fillWidth: true
                        visible: Updates.total > 0 && !Updates.runBusy
                        secret: true
                        placeholder: Translation.tr("sudo password")
                        onAccepted: root.selectedCount > 0 ? root.runSelected() : root.runFullUpdate()
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm

                        PanelButton {
                            capsule: true
                            Layout.fillWidth: true
                            variant: "primary"
                            accent:  Colors.of(QsWindow.window).warning
                            symbol:  "update"
                            label:   Updates.runBusy ? "Installing…" : "Update everything"
                            // This one runs pacman as root, so it needs the credential.
                            enabled: Updates.total > 0 && !Updates.runBusy && passField.text.length > 0
                            onActivated: root.runFullUpdate()
                        }
                        PanelButton {
                            capsule: true
                            visible: root.selectedCount > 0
                            variant: "normal"
                            symbol:  "checklist"
                            label:   "Install " + root.selectedCount
                            enabled: !Updates.runBusy && (!root.needsPassword || passField.text.length > 0)
                            onActivated: root.runSelected()
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        text: root.selectedCount > 0
                            ? (root.needsPassword
                                ? "Your password goes straight to sudo and isn't stored."
                                : "Flatpak asks for permission in its own dialog.")
                            : "Official packages update together — tick AUR and Flatpak ones to install singly."
                        variant: "micro"
                        emphasis: "dim"
                        wrapMode: Text.WordWrap

                        HelpTip {
                            text: Translation.tr("Installing one official package on its own is a partial upgrade, which breaks programs that rely on the libraries left behind. Use Update everything for those.")
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingLg

            // ══ The list ══════════════════════════════════════════════════════
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Tokens.spacingMd

                // ── The source filter, and the dismiss that only a failed run offers ──
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd
                    visible: root.showLog || Updates.total > 0

                    TabStrip {
                        Layout.fillWidth: true
                        visible: !root.showLog
                        accent: Updates.total > 0 ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).success
                        model: [
                            { value: "all",      label: "All  " + Updates.total },
                            { value: "official", label: "Official  " + Updates.count },
                            { value: "aur",      label: "AUR  " + Updates.aurCount },
                            { value: "flatpak",  label: "Flatpak  " + Updates.flatpakCount }
                        ]
                        current: root.source
                        onPicked: function (v) { root.source = v }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: root.showLog
                        text: Translation.tr("Installing")
                        variant: "label"
                        emphasis: "muted"
                    }
                    BusyDot { visible: Updates.runBusy }
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
                }

                // ── Where the run has got to ──────────────────────────────────
                // This page had NO progress display at all: the runner's `:: [n/N]`
                // markers were parsed only by UpdatePanel, the bar pill's popup, so the
                // richer view — the one you open when a run is going wrong — showed a
                // wall of log and nothing else. It looked deliberate because the markers
                // are visible in that log as ordinary text.
                //
                // The parse lives in the service now, so this is pure presentation and
                // shares one source with the panel. Only while there's a run to describe:
                // the log pane also holds finished output you came back to read.
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingSm
                    visible: Updates.runBusy || Updates.runPhaseCount > 0

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingMd

                        // "2 of 3" — absent for runs that have no phases at all (a
                        // Vencord patch, a selected install), where it would read as a
                        // one-step process that stalled at step one.
                        StyledText {
                            visible: Updates.runPhaseCount > 0
                            text: "Step " + Updates.runPhaseIndex
                                + " of " + Updates.runPhaseCount
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

                    // The hooks are the one stretch with no progress signal at all, and
                    // the silence is what makes a live upgrade look hung — the reason the
                    // latch exists. Saying so costs one line and removes the whole
                    // question.
                    StyledText {
                        Layout.fillWidth: true
                        visible: Updates.runInHooks
                        text: Translation.tr("Running post-transaction hooks — this can take a while ")
                            + "on a kernel update. Don't reload the shell."
                        variant: "caption"
                        emphasis: "dim"
                        wrapMode: Text.WordWrap
                    }
                }

                Surface {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 200
                    elevation: Tokens.elevationNested
                    clip: true

                    // ── Run log ───────────────────────────────────────────────
                    // Takes over the pane while installing. The list underneath is about
                    // to be wrong anyway — the packages being installed are leaving it.
                    Flickable {
                        id: logFlick
                        anchors.fill: parent
                        anchors.margins: Tokens.spacingLg
                        // Cross-fade with the list rather than swapping. `visible` still
                        // follows opacity so the faded-out pane stops taking clicks —
                        // a transparent Flickable would happily keep eating them.
                        opacity: root.showLog ? 1.0 : 0.0
                        visible: opacity > 0.005
                        Behavior on opacity {
                            NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
                        }
                        contentHeight: logCol.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        // Pinned to the newest line, which is the one that matters while
                        // something is running.
                        onContentHeightChanged: if (Updates.runBusy)
                            logFlick.contentY = Math.max(0, logFlick.contentHeight - logFlick.height)

                        ColumnLayout {
                            id: logCol
                            width: logFlick.width
                            spacing: 0

                            Repeater {
                                model: Updates.runLog

                                StyledText {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    text: modelData.text
                                    // stderr is not automatically failure — pacman and
                                    // makepkg both report ordinary progress there — so it
                                    // is muted, not alarmed. The exit code decides.
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
                        anchors.margins: Tokens.spacingLg
                        opacity: root.showLog ? 0.0 : 1.0
                        visible: opacity > 0.005
                        Behavior on opacity {
                            NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
                        }
                        contentHeight: listCol.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds

                        // ── Sectioned, two across ─────────────────────────────
                        // One flat list of 41 rows in a 1100px-wide box wasted most of
                        // the width and made the version column sit a mile from the name
                        // it belonged to. Two columns halve the scrolling and put each
                        // version back beside its package; the section headers replace
                        // the per-row source badge, which had to be read 41 times to
                        // learn something the grouping now says once.
                        ColumnLayout {
                            id: listCol
                            width: listFlick.width - Tokens.scrollRoom   // clear of the Scrollbar
                            spacing: Tokens.spacingLg

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
                                title: Updates.helper ? "AUR — " + Updates.helper : "AUR"
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

                    // ── Empty pane, done properly ──────────────────────────────
                    // Not one dim line of text floating in a blank ~1100×700 box,
                    // and not nothing during a CHECK (`Updates.checking` shows here
                    // too).
                    // "Up to date" is the most common state this page is ever in, so
                    // leaving it the emptiest-looking one was backwards. Same spinning-
                    // glyph idiom ReloadPill uses for "working", not a new one.
                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: !root.showLog && Updates.packages.length === 0
                        spacing: Tokens.spacingSm
                        width: Math.min(parent.width - Tokens.spacingXl * 2, 380)

                        MaterialIcon {
                            Layout.alignment: Qt.AlignHCenter
                            variant: "display"
                            sizeScale: 1.6
                            glyph:  Updates.checking ? "󰑐"
                                 : Updates.hasError  ? "󰀪"
                                                      : "󰄬"
                            color: Updates.checking ? Colors.of(QsWindow.window).fgDim
                                 : Updates.hasError  ? Colors.of(QsWindow.window).warning
                                                      : Colors.of(QsWindow.window).success
                            Behavior on color { ColorAnimation { duration: Motion.respond } }

                            // Category 3: busy indicator — not gated on
                            // motionEnabled, literal duration. See ReloadPill's
                            // spinner for the full reasoning, and Motion.qml.
                            RotationAnimation on rotation {
                                running: Updates.checking
                                loops: Animation.Infinite
                                from: 0; to: 360
                                duration: 1400
                            }
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            variant: "title"
                            font.weight: Font.DemiBold
                            text: Updates.checking ? "Checking for updates…"
                                : Updates.hasError  ? "Package database unavailable"
                                                     : "You're all caught up"
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            variant: "caption"
                            emphasis: "dim"
                            text: Updates.checking ? "Asking the mirrors what's changed."
                                : Updates.hasError  ? "Try Check again in a moment — the sync "
                                                      + "database may be mid-refresh."
                                                     : root.lastUpdatedText
                        }
                    }
                }

                // ══ Interactive prompt ═══════════════════════════════════════
                // pacman/yay asked something — a conflict, a replacement, a
                // provider choice, a confirmation — and the run is blocked on stdin
                // until it's answered. Cancel is always here too, so a question the
                // parser didn't anticipate can never wedge the update.
                Surface {
                    Layout.fillWidth: true
                    elevation: Tokens.elevationNested
                    focused: true
                    visible: Updates.awaitingInput
                    implicitHeight: promptCol.implicitHeight + Tokens.spacingLg * 2

                    ColumnLayout {
                        id: promptCol
                        anchors.left:  parent.left
                        anchors.right: parent.right
                        anchors.top:   parent.top
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingSm

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingSm
                            MaterialIcon { glyph: "󰋗"; variant: "body"; color: Colors.of(QsWindow.window).focus }
                            StyledText {
                                text: Translation.tr("The update needs your input")
                                variant: "body"
                                font.weight: Font.DemiBold
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

                        // Yes / No — the default answer is the filled one.
                        RowLayout {
                            Layout.fillWidth: true
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
                            Item { Layout.fillWidth: true }
                            PanelButton {
                                capsule: true
                                label: Translation.tr("Cancel run")
                                glyph: "󰅖"
                                variant: "ghost"
                                accent: Colors.of(QsWindow.window).danger
                                onActivated: Updates.cancelRun()
                            }
                        }

                        // Provider number / password / anything else the process asks.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingSm
                            visible: Updates.promptKind !== "yesno"
                            onVisibleChanged: if (visible) answerField.forceActiveFocus()

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Tokens.pillHeight + Tokens.spacingXs * 2
                                radius: Tokens.radiusSm
                                color: Colors.of(QsWindow.window).surfaceContainer
                                border.width: Tokens.borderWidth
                                border.color: answerField.activeFocus ? Colors.of(QsWindow.window).outlineFocus
                                                                      : Colors.of(QsWindow.window).outline

                                TextInput {
                                    id: answerField
                                    anchors.fill: parent
                                    anchors.leftMargin:  Tokens.spacingMd
                                    anchors.rightMargin: Tokens.spacingMd
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: Colors.of(QsWindow.window).fg
                                    font.family: Tokens.fontFamily
                                    font.pixelSize: Tokens.fontBody
                                    echoMode: Updates.promptKind === "password"
                                        ? TextInput.Password : TextInput.Normal
                                    clip: true
                                    onAccepted: { Updates.answer(answerField.text); answerField.text = "" }

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: answerField.text === ""
                                        text: Updates.promptKind === "password" ? "Password"
                                            : Updates.promptKind === "number"
                                                ? ("A number" + (Updates.promptDefault !== ""
                                                    ? " (default " + Updates.promptDefault + ")" : ""))
                                                : "Type your answer, then Send"
                                        variant: "body"
                                        emphasis: "dim"
                                    }
                                }
                            }
                            PanelButton {
                                capsule: true
                                label: Translation.tr("Send")
                                glyph: "󰅂"
                                variant: "primary"
                                onActivated: { Updates.answer(answerField.text); answerField.text = "" }
                            }
                            PanelButton {
                                capsule: true
                                label: Translation.tr("Cancel")
                                variant: "ghost"
                                accent: Colors.of(QsWindow.window).danger
                                onActivated: Updates.cancelRun()
                            }
                        }
                    }
                }
            }

            // ══ The rest ══════════════════════════════════════════════════════
            // What is not about the packages themselves, in a rail that scrolls on its own.
            Item {
                Layout.preferredWidth: 288
                Layout.fillHeight: true

                Flickable {
                    id: railFlick
                    anchors.fill: parent
                    contentHeight: railCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: railCol
                        width: railFlick.width - Tokens.scrollRoom   // clear of the Scrollbar
                        spacing: Tokens.spacingMd

                // ── Finish setup ─────────────────────────────────────────────
                // Shown here, where a new user looking at "packages" is most likely
                // to be, when the compositor wiring or the core packages aren't done.
                // Hands off to the Setup status board rather than duplicating it.
                Section {
                    Layout.fillWidth: true
                    visible: !Setup.hyprReady || (Setup.coreProbed && !Setup.coreReady)
                    glyph:   "󰄬"
                    title:   Translation.tr("Finish setup")
                    subtitle: (Setup.coreProbed && !Setup.coreReady)
                             ? Setup.missingCore + " core package"
                               + (Setup.missingCore === 1 ? " is" : "s are") + " missing — run ./setup.sh."
                             : "Not wired into Hyprland yet. None of it stops the shell running."
                    accent:  Colors.of(QsWindow.window).info

                    PanelButton {
                        capsule: true
                        label:   Translation.tr("Open setup")
                        glyph:   "󰄬"
                        variant: "primary"
                        onActivated: UiState.openSettingsTo("SetupPage.qml")
                    }
                }

                // ── Reboot notice ─────────────────────────────────────────────
                // Only when a kernel or graphics module is in the list. This is the one
                // consequence of an upgrade that bites you later rather than at the time,
                // so it's worth a whole card instead of a footnote.
                // Its heading is a Section heading, not a hand-built icon-plus-bold-
                // label row. Tonal is deliberately left
                // ON here even though the accent is `warning`: Section's own note
                // warns against tinting a whole card with an alarm colour, and the
                // exception it is describing is a blocker or an error, where the alarm
                // is about the CONTROL rather than the content. This card is genuinely
                // a warning about your machine, and a card that carries that colour is
                // exactly what should stand out of a column of neutral ones.
                Section {
                    Layout.fillWidth: true
                    visible: Updates.needsReboot

                    glyph:  "󰀪"
                    title:  Translation.tr("Reboot afterwards")
                    accent: Colors.of(QsWindow.window).warning

                    StyledText {
                        Layout.fillWidth: true
                        text: "This upgrade replaces " + Updates.rebootPackages.length
                            + " kernel or driver package"
                            + (Updates.rebootPackages.length !== 1 ? "s" : "")
                            + ". Until you reboot, plugging in new hardware may not "
                            + "work — the running kernel's modules will have been "
                            + "replaced on disk."
                        variant: "caption"
                        emphasis: "dim"
                        wrapMode: Text.WordWrap
                    }
                }

                // ── Arch news ─────────────────────────────────────────────────
                // Shown when the newest feed item post-dates your last full upgrade.
                // The one thing --noconfirm genuinely can't handle is an upgrade that
                // needs a manual step, and that's what these posts announce.
                Section {
                    Layout.fillWidth: true
                    visible: Updates.newsUnread

                    glyph:  "󰎕"
                    title:  Translation.tr("Arch news")
                    accent: Colors.of(QsWindow.window).warning

                    StyledText {
                        Layout.fillWidth: true
                        text: Updates.newsTitle
                        variant: "body"
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Updates.newsDate + " — newer than your last upgrade. "
                            + "Read it before running a full upgrade."
                        variant: "caption"
                        emphasis: "dim"
                        wrapMode: Text.WordWrap
                    }
                    PanelButton {
                        capsule: true
                        Layout.fillWidth: true
                        variant: "normal"
                        accent:  Colors.of(QsWindow.window).warning
                        glyph:   "󰏌"
                        label:   Translation.tr("Open archlinux.org/news")
                        onActivated: Qt.openUrlExternally(Updates.newsUrl)
                    }
                }

                // ── Held back ─────────────────────────────────────────────────
                Section {
                    Layout.fillWidth: true
                    visible: Updates.heldPending.length > 0

                    glyph:  "󰏥"
                    title:  Translation.tr("Held back")
                    accent: Colors.of(QsWindow.window).warning

                    StyledText {
                        Layout.fillWidth: true
                        text: Updates.heldPending.length + " package"
                            + (Updates.heldPending.length === 1 ? "" : "s")
                            + " will be skipped with --ignore on the next upgrade."
                        variant: "caption"
                        emphasis: "dim"
                        wrapMode: Text.WordWrap
                    }
                    PanelButton {
                        capsule: true
                        Layout.fillWidth: true
                        variant: "normal"
                        label:   Translation.tr("Release all")
                        onActivated: Updates.clearHolds()
                    }
                }

                // ── Quicktest itself ──────────────────────────────────────────
                // The shell's own releases (services/ShellUpdate): the same card the
                // bar's update panel shows (Check / Update), plus the schedule toggle.
                Section {
                    Layout.fillWidth: true

                    glyph:  "󰚰"
                    title:  Translation.tr("Quicktest")
                    help:     Translation.tr("Updates to the shell itself — signed releases from GitHub.")

                    ShellUpdateCard { Layout.fillWidth: true }

                    SettingRow {
                        label:  Translation.tr("Check for new versions")
                        detail: Translation.tr("Every 6 hours")
                        help:   Translation.tr("Asks GitHub every 6 hours for a newer signed release of the shell.")
                        Toggle {
                            accent: Colors.of(QsWindow.window).primary
                            checked: Config.shellUpdateCheck
                            onToggled: Config.shellUpdateCheck = !Config.shellUpdateCheck
                        }
                    }
                }

                Section {
                    Layout.fillWidth: true
                    visible: root.recentChanges.length > 0
                    symbol: "history"
                    title:  Translation.tr("Recently changed")
                    subtitle: root.lastUpdatedText
                    accent: Colors.of(QsWindow.window).primary
                    bodySpacing: Tokens.spacingXs

                    Repeater {
                        model: root.recentChanges
                        delegate: RowLayout {
                            id: histRow
                            required property var modelData
                            Layout.fillWidth: true
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

                // ── Vencord ───────────────────────────────────────────────────
                // Separate from the package actions on purpose: it isn't a package update,
                // pacman can't see it, and Discord silently un-patches itself on every one of
                // its own updates — so it's a thing you redo, not a thing that happens on the
                // way past. Uses the password field above.
                Section {
                    Layout.fillWidth: true
                    symbol: "refresh"
                    title:  Translation.tr("Discord")
                    subtitle: Translation.tr("Re-patch Vencord")
                    help:   Translation.tr("Downloads the official VencordInstaller and runs it as root. Re-apply this after Discord updates itself and drops the patch.")
                    accent: Colors.of(QsWindow.window).info

                    actions: ChipTray {
                        ChipButton {
                            symbol:  "refresh"
                            label:   Translation.tr("Re-patch")
                            tint:    Colors.of(QsWindow.window).info
                            enabled: !Updates.runBusy && passField.text.length > 0
                            onActivated: root.runVencord()
                        }
                    }
                }
                    }
                }
                Scrollbar { flickable: railFlick }
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
            text: cr.unknown ? "—" : String(cr.value)
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

            // The source badge is gone — the section heading says it once instead of
            // every row repeating it 41 times.
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
                                : "update available"
                variant: "caption"
                emphasis: "dim"
                elide: Text.ElideRight
                // Capped so a long version pair can't push the name into an ellipsis;
                // the name is what you scan for.
                Layout.maximumWidth: 210
            }

            // ── Hold ──────────────────────────────────────────────────────────
            // --ignore on the next run, not IgnorePkg — a hold you can see and undo,
            // available on official packages too (skipping one isn't a partial
            // upgrade; installing one alone is). Not Flatpak: `flatpak update` has no
            // exclude, so the hold couldn't be honoured.
            PanelButton {
                capsule: true
                visible: (pr.pkg?.source ?? "") !== "flatpak"
                variant: "ghost"
                implicitHeight: 22
                accent: Colors.of(QsWindow.window).warning
                symbol: pr.held ? "play_arrow" : "pause"
                onActivated: Updates.toggleHold(pr.pkg?.name ?? "")
            }
        }
    }
}
