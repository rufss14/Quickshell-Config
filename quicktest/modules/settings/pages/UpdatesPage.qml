pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
// Process + StdioCollector for the "Recently changed" card. Their absence is what
// blanked this whole page: an unresolved type is a hard load failure for the file,
// not a skipped element — and qmllint passes it clean.
import Quickshell.Io
import "../../../config"
import "../../../components"
import "../../../services"

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
    onVisibleChanged: if (root.visible) Updates.check()

    // ── Recently changed ──────────────────────────────────────────────────────
    // The tail of pacman's own log: what actually got upgraded/installed/removed and
    // when. This is the page's memory — a list of pending updates says what's coming,
    // this says what happened, and after a run it's the receipt.
    property var recentChanges: []          // [{ date, action, name, to }], newest first

    Process {
        id: historyQuery
        running: true
        // tail BEFORE grep: bounds the read on a log that only grows (and reading the
        // whole file through grep has misbehaved on this machine where tail has not).
        // Recent entries are by definition at the end.
        command: ["bash", "-c",
            "tail -n 4000 /var/log/pacman.log"
            + " | grep -E '\\[ALPM\\] (upgraded|installed|removed) '"
            + " | tail -n 10"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                const re = /^\[(\d{4}-\d{2}-\d{2})T[^\]]*\] \[ALPM\] (upgraded|installed|removed) (\S+) \((.+)\)$/
                for (const line of text.trim().split("\n")) {
                    const m = line.match(re)
                    if (!m) continue
                    // "0.47.4-1 -> 0.48.0-1" → the version you HAVE now; the old one is
                    // history twice over.
                    const vers = m[4].split(" -> ")
                    out.push({ date: m[1], action: m[2], name: m[3],
                               to: vers[vers.length - 1] })
                }
                out.reverse()
                root.recentChanges = out
            }
        }
    }
    // Re-read after a run finishes: the log just grew, and the card should show it.
    Connections {
        target: Updates
        function onRunDoneChanged() {
            if (Updates.runDone) { historyQuery.running = false; historyQuery.running = true }
        }
    }

    // ── Selection ─────────────────────────────────────────────────────────────
    // Keyed by package name in a plain object. Reassigned rather than mutated on every
    // toggle — QML only re-evaluates bindings on a property CHANGE, and mutating an
    // object in place doesn't emit one, so the checkboxes would never redraw. (Audio.qml
    // hit exactly this with its client cache; the same rule, the same fix.)
    property var selected: ({})

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
        passField.text = ""      // not kept a moment longer than the call needs it
    }

    function runVencord() {
        if (Updates.runBusy || passField.text.length === 0) return
        Updates.installVencord(passField.text)
        passField.text = ""
    }

    // Runs here too, on the same runner and into the same log — not the overlay panel.
    // UpdatePanel is still what the BAR's update pill opens; this page is now
    // self-contained, so there is one password field and one place to watch.
    function runFullUpdate() {
        if (Updates.runBusy || passField.text.length === 0) return
        Updates.installAll(passField.text)
        passField.text = ""
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        PanelHeader {
            glyph:     Updates.total > 0 ? "󰚰" : "󰄬"        // update / check
            title:     "Updates"
            titleTail: Updates.checking ? "checking…"
                     : Updates.total > 0 ? Updates.total + " pending" : ""
            accent:    Updates.total > 0 ? Colors.warning : Colors.success

            subtitle: Updates.hasError
                    ? "Couldn't read the package database — try again in a moment."
                    : Updates.checking ? "Asking the mirrors what's changed."
                    : Updates.total === 0 ? "Everything is up to date."
                    : Updates.count + " official  ·  " + Updates.aurCount + " AUR"
                      + (Updates.hasFlatpak ? "  ·  " + Updates.flatpakCount + " Flatpak" : "")
        }

        Divider {}

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingXl

            // ══ Summary and actions ═══════════════════════════════════════════
            // fillWidth FALSE is load-bearing: a Layout nested in a Layout defaults it to
            // true, which would let this rail eat the list's width. Burned by exactly
            // this on NetworkPage, where a side column took 1415px and starved the graph
            // to 6px.
            ColumnLayout {
                Layout.fillWidth: false
                Layout.preferredWidth: 340
                // fillHeight, not AlignTop: the Vencord action at the foot of this rail
                // needs a full-height column to be pushed to the bottom OF. The spacer
                // before it does the pushing, so everything above still hugs the top.
                Layout.fillHeight: true
                spacing: Tokens.spacingMd

                StyledText { text: "Summary"; variant: "label"; emphasis: "muted" }

                Surface {
                    Layout.fillWidth: true
                    elevation: Tokens.elevationNested
                    implicitHeight: sumBox.implicitHeight + Tokens.spacingLg * 2

                    ColumnLayout {
                        id: sumBox
                        anchors.left:  parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingMd

                        CountRow {
                            Layout.fillWidth: true
                            glyph: "󰏗"                              // package
                            label: "Official"
                            value: Updates.count
                            tint:  Colors.focus
                        }
                        CountRow {
                            Layout.fillWidth: true
                            glyph: "󰣇"                              // arch
                            label: Updates.helper ? "AUR (" + Updates.helper + ")" : "AUR"
                            value: Updates.aurCount
                            tint:  Colors.info
                            // No helper means we cannot know, and showing "0" would be a
                            // claim rather than a reading.
                            unknown: Updates.helper === ""
                        }
                        CountRow {
                            Layout.fillWidth: true
                            glyph: "󰏓"                              // flatpak-ish (package)
                            label: "Flatpak"
                            value: Updates.flatpakCount
                            tint:  Colors.success
                            unknown: !Updates.hasFlatpak
                        }
                    }
                }

                // ── Reboot notice ─────────────────────────────────────────────
                // Only when a kernel or graphics module is in the list. This is the one
                // consequence of an upgrade that bites you later rather than at the time,
                // so it's worth a whole card instead of a footnote.
                Surface {
                    Layout.fillWidth: true
                    visible: Updates.needsReboot
                    elevation: Tokens.elevationNested
                    implicitHeight: rebootBox.implicitHeight + Tokens.spacingLg * 2

                    ColumnLayout {
                        id: rebootBox
                        anchors.left:  parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingSm

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingMd

                            StyledText { text: "󰀪"; color: Colors.warning; variant: "body" }
                            StyledText {
                                Layout.fillWidth: true
                                text: "Reboot afterwards"
                                variant: "body"
                                font.weight: Font.DemiBold
                            }
                        }
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
                }

                StyledText {
                    Layout.topMargin: Tokens.spacingSm
                    text: "Actions"
                    variant: "label"
                    emphasis: "muted"
                }

                PanelButton {
                    Layout.fillWidth: true
                    variant: "normal"
                    glyph:   "󰑐"                                    // refresh
                    label:   Updates.checking ? "Checking…" : "Check again"
                    onActivated: Updates.check()
                }

                // ── Full upgrade: the shell's own updater ─────────────────────
                // Opens UpdatePanel, which runs pacman and flatpak INSIDE the shell with
                // a live progress feed. That panel already existed — the bar's update
                // pill has always used it — and this page was spawning a terminal beside
                // it for no reason.
                PanelButton {
                    Layout.fillWidth: true
                    variant: "primary"
                    accent:  Colors.warning
                    glyph:   "󰚰"
                    label:   Updates.runBusy ? "Installing…" : "Update everything"
                    // Same password gate as a selected install: this one runs pacman as
                    // root, so it needs the credential just as much.
                    enabled: Updates.total > 0 && !Updates.runBusy
                             && passField.text.length > 0
                    onActivated: root.runFullUpdate()
                }

                PanelButton {
                    Layout.fillWidth: true
                    variant: "normal"
                    glyph:   "󰄲"
                    label:   Updates.runBusy ? "Installing…"
                           : root.selectedCount > 0
                           ? "Install " + root.selectedCount + " selected"
                           : "Select packages below"
                    enabled: root.selectedCount > 0 && !Updates.runBusy
                             && (!root.needsPassword || passField.text.length > 0)
                    onActivated: root.runSelected()
                }

                // ── sudo password ─────────────────────────────────────────────
                // Only when AUR packages are picked: the helper calls sudo, and there is
                // no passwordless sudo here. Flatpak needs none — those are system
                // installs and authenticate through polkit's own dialog.
                //
                // Goes to the process over stdin, never into a command line. See
                // Updates.installSelected().
                Surface {
                    Layout.fillWidth: true
                    // Shown whenever there is anything to install: "Update everything"
                    // always needs it, and a selection needs it when AUR is involved.
                    visible: Updates.total > 0 && !Updates.runBusy
                    elevation: Tokens.elevationNested
                    implicitHeight: Tokens.pillHeight + Tokens.spacingMd * 2

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin:  Tokens.spacingLg
                        anchors.rightMargin: Tokens.spacingLg
                        spacing: Tokens.spacingMd

                        StyledText { text: "󰌾"; color: Colors.fgMuted; variant: "body" }

                        TextInput {
                            id: passField
                            Layout.fillWidth: true
                            echoMode: TextInput.Password
                            color: Colors.fg
                            selectionColor: Colors.alpha(Colors.focus, 0.35)
                            selectByMouse: true
                            font.family: Tokens.fontFamily
                            font.pixelSize: Tokens.fontBody
                            verticalAlignment: TextInput.AlignVCenter

                            StyledText {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: passField.text.length === 0
                                text: "sudo password…"
                                variant: "body"
                                emphasis: "dim"
                            }
                            Keys.onReturnPressed: root.runSelected()
                            Keys.onEnterPressed:  root.runSelected()
                        }
                    }
                }


                // Why the official section has no tick boxes. Stated once, here, rather
                // than as a warning attached to an action that shouldn't exist.
                StyledText {
                    Layout.fillWidth: true
                    text: root.selectedCount > 0
                        ? (root.needsPassword
                            ? "Installs here on this page. Your password goes straight to "
                              + "sudo and isn't stored."
                            : "Installs here on this page. Flatpak will ask for "
                              + "permission in its own dialog.")
                        : "AUR and Flatpak packages can be picked individually. Official "
                          + "packages can't — installing one on its own is a partial "
                          + "upgrade, which breaks programs that rely on the libraries "
                          + "left behind. Use Update everything for those."
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                }

                // ── Recently changed ──────────────────────────────────────────
                StyledText {
                    Layout.topMargin: Tokens.spacingSm
                    visible: root.recentChanges.length > 0
                    text: "Recently changed"
                    variant: "label"
                    emphasis: "muted"
                }

                Surface {
                    Layout.fillWidth: true
                    visible: root.recentChanges.length > 0
                    elevation: Tokens.elevationNested
                    implicitHeight: historyCol.implicitHeight + Tokens.spacingLg * 2

                    ColumnLayout {
                        id: historyCol
                        anchors.left:  parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingXs

                        Repeater {
                            model: root.recentChanges
                            delegate: RowLayout {
                                id: histRow
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Tokens.spacingSm

                                StyledText {
                                    text: histRow.modelData.action === "upgraded" ? "󰚰"
                                        : histRow.modelData.action === "installed" ? "󰐕"
                                        : "󰅖"
                                    variant: "caption"
                                    color: histRow.modelData.action === "upgraded" ? Colors.focus
                                         : histRow.modelData.action === "installed" ? Colors.success
                                         : Colors.fgDim
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
                                    text: histRow.modelData.date
                                    variant: "caption"
                                    emphasis: "dim"
                                    font.family: Tokens.fontMono
                                }
                            }
                        }
                    }
                }

                // Everything above hugs the top; this claims the slack so Vencord sits at
                // the foot of the rail.
                Item { Layout.fillHeight: true; Layout.minimumHeight: Tokens.spacingLg }

                Divider { Layout.fillWidth: true }

                // ── Vencord ───────────────────────────────────────────────────
                // Separate from the package actions on purpose: it isn't a package
                // update, pacman can't see it, and Discord silently un-patches itself on
                // every one of its own updates — so it's a thing you redo, not a thing
                // that happens on the way past.
                StyledText { text: "Discord"; variant: "label"; emphasis: "muted" }

                PanelButton {
                    Layout.fillWidth: true
                    variant: "normal"
                    accent:  Colors.info
                    glyph:   "󰙯"                                  // discord
                    label:   "Re-patch Vencord"
                    enabled: !Updates.runBusy && passField.text.length > 0
                    onActivated: root.runVencord()
                }

                StyledText {
                    Layout.fillWidth: true
                    text: "Downloads the official VencordInstaller and runs it as root. "
                        + "Re-apply this after Discord updates itself and drops the patch."
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                }
            }

            Divider { orientation: Qt.Vertical }

            // ══ The list ══════════════════════════════════════════════════════
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Tokens.spacingMd

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingMd

                    StyledText {
                        text: root.showLog ? "Installing" : "Pending packages"
                        variant: "label"
                        emphasis: "muted"
                    }
                    BusyDot { visible: Updates.runBusy }
                    Item { Layout.fillWidth: true }

                    StyledText {
                        visible: !root.showLog && Updates.packages.length > 0
                        text: Updates.packages.length + " total"
                        variant: "caption"
                        emphasis: "dim"
                    }
                    // Only once it's finished — dismissing a running install would hide
                    // the only thing telling you it's still going.
                    // Only on failure now: a successful run clears itself, so a "Done"
                    // button there would just be a race against the timer.
                    PanelButton {
                        variant: "ghost"
                        visible: Updates.runDone && !Updates.runBusy && Updates.runExit !== 0
                        glyph:   "󰅖"
                        label:   "Dismiss"
                        onActivated: root.returnToList()
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
                                    color: modelData.error ? Colors.warning : Colors.fgMuted
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
                            width: listFlick.width
                            spacing: Tokens.spacingLg

                            UpdateSection {
                                Layout.fillWidth: true
                                title: "Official"
                                glyph: "󰏗"
                                tint:  Colors.focus
                                rows:  Updates.official
                            }
                            UpdateSection {
                                Layout.fillWidth: true
                                title: Updates.helper ? "AUR — " + Updates.helper : "AUR"
                                glyph: "󰣇"
                                tint:  Colors.info
                                rows:  Updates.aur
                            }
                            UpdateSection {
                                Layout.fillWidth: true
                                title: "Flatpak"
                                glyph: "󰏓"
                                tint:  Colors.success
                                rows:  Updates.flatpak
                            }
                        }
                    }

                    Scrollbar { flickable: listFlick; visible: listFlick.visible }

                    StyledText {
                        anchors.centerIn: parent
                        visible: !root.showLog && Updates.packages.length === 0 && !Updates.checking
                        text: Updates.hasError ? "Package database unavailable."
                                               : "Nothing to update."
                        variant: "body"
                        emphasis: "dim"
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
                            StyledText { text: "󰋗"; variant: "body"; color: Colors.focus }
                            StyledText {
                                text: "The update needs your input"
                                variant: "body"
                                font.weight: Font.DemiBold
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 0
                            text: Updates.promptText
                            variant: "caption"
                            color: Colors.fg
                            font.family: Tokens.fontMono
                            wrapMode: Text.WrapAnywhere
                        }

                        // Yes / No — the default answer is the filled one.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingSm
                            visible: Updates.promptKind === "yesno"

                            PanelButton {
                                label: "Yes"
                                glyph: "󰄬"
                                variant: Updates.promptDefault === "y" ? "primary" : "normal"
                                onActivated: Updates.answerYes()
                            }
                            PanelButton {
                                label: "No"
                                variant: Updates.promptDefault === "n" ? "primary" : "normal"
                                onActivated: Updates.answerNo()
                            }
                            Item { Layout.fillWidth: true }
                            PanelButton {
                                label: "Cancel run"
                                glyph: "󰅖"
                                variant: "ghost"
                                accent: Colors.danger
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
                                radius: Tokens.radiusFull
                                color: Colors.surfaceContainer
                                border.width: Tokens.borderWidth
                                border.color: answerField.activeFocus ? Colors.outlineFocus
                                                                      : Colors.outline

                                TextInput {
                                    id: answerField
                                    anchors.fill: parent
                                    anchors.leftMargin:  Tokens.spacingMd
                                    anchors.rightMargin: Tokens.spacingMd
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: Colors.fg
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
                                label: "Send"
                                glyph: "󰅂"
                                variant: "primary"
                                onActivated: { Updates.answer(answerField.text); answerField.text = "" }
                            }
                            PanelButton {
                                label: "Cancel"
                                variant: "ghost"
                                accent: Colors.danger
                                onActivated: Updates.cancelRun()
                            }
                        }
                    }
                }
            }
        }
    }

    // ══ Components ════════════════════════════════════════════════════════════

    // ── CountRow ──────────────────────────────────────────────────────────────
    component CountRow: RowLayout {
        id: cr

        property string glyph: ""
        property string label: ""
        property int    value: 0
        property color  tint:  Colors.focus
        property bool   unknown: false

        spacing: Tokens.spacingMd

        StyledText { text: cr.glyph; color: cr.tint; variant: "body" }
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
        property color  tint:  Colors.focus
        property var    rows:  []

        visible: sec.rows.length > 0
        spacing: Tokens.spacingSm

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacingSm

            StyledText { text: sec.glyph; color: sec.tint; variant: "caption" }
            StyledText {
                text: sec.title
                color: sec.tint
                variant: "label"
                font.weight: Font.DemiBold
            }
            StyledText {
                text: String(sec.rows.length)
                variant: "caption"
                emphasis: "dim"
            }
            Divider { Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
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

        implicitHeight: Math.max(prRow.implicitHeight, Tokens.pillHeight)

        // The whole row is the hit target, not just the 16px box — a checkbox you have
        // to aim at is a checkbox you misclick.
        Rectangle {
            anchors.fill: parent
            anchors.rightMargin: Tokens.spacingSm
            radius: Tokens.radiusSm
            color: pr.picked                      ? Colors.alpha(Colors.focus, 0.12)
                 : (prHover.hovered && pr.selectable) ? Colors.alpha(Colors.fg, 0.06)
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

                StyledText {
                    anchors.centerIn: parent
                    visible: pr.selectable
                    text:  pr.picked ? "󰄲" : "󰄱"        // checked / unchecked
                    color: pr.picked ? Colors.focus : Colors.fgDim
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
        }
    }
}
