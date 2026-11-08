import "../../services"
import "../../state"
import QtQuick
import Quickshell
import QtQuick.Layouts
import Quickshell.Io
import "../../config"
import "../../components"
import "../../services/updatefmt.js" as UF
import "update"

// ── UpdatePanel ───────────────────────────────────────────────────────────────
// Embeddable content Item — the bar update pill's popup, hosted inside OverlayRoot's
// Center container (one instance per screen, same pattern as every other module).
//
// ── It is now a VIEW over the one runner, not a second updater ─────────────────
// It used to run `yay -Syu --noconfirm` through a plain `bash -c` with no PTY. Two ways
// that hangs, both silent, both reported by the user:
//   • A long AUR build outlives sudo's cached credential, and yay's inner sudo
//     RE-PROMPTS on a terminal that doesn't exist — nothing can answer it, so it wedges
//     with no indicator.
//   • `--noconfirm` turns a real pacman question (a replacement, a conflict, a provider
//     choice) into its default answer — usually "no", which aborts.
// The Updates service already solved both: a real PTY (`python -m pty.spawn`) that
// surfaces every prompt as `Updates.awaitingInput` / `promptText` / `promptKind` for the
// UI to answer, and auto-answers sudo's re-prompts from the remembered password. So this
// panel DELEGATES to it (`Updates.installAll` / `installVencord`) and renders those
// prompts, instead of maintaining a parallel `--noconfirm` implementation. One runner,
// one place a password or a "Proceed? [Y/n]" is ever handled — and it's shared with the
// Settings → Updates page, so opening one mid-run shows the other's progress.
//
// ── In the recipe the wallpaper, media, colours and clock panels wear ─────────
// ChipTrays for the header's actions, flat section cards (Colors.section, so the cookies show through),
// SegmentSwitches for a choice between views of the same thing, pill fields, springs, and each view
// arriving in a cascade. NOTHING it does changed: every state, prompt, password path and runner call is
// the same code as before. What is new is mostly what it tells you:
//   · the pending list filters by source and by name, and says how big each jump is (major / minor / patch /
//     rebuild — updatefmt.js `bump`), biggest first, with a link to each package's page;
//   · a run says which step of how many it is on and roughly how long is left, and can be cancelled
//     (two-step) from the header; a finished run is a receipt, with Copy log for the log;
//   · "nothing pending" says when it last looked.
//
// ── Rigid, not filling ────────────────────────────────────────────────────────
// The dock animates the card's height to this panel's implicitHeight; the layout is pinned to the top at its
// OWN height (and every layout child states fillHeight), so the header does not slide while the card springs.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: panel
    // Reached by the view files in update/.
    property alias activityModel: activityModel
    property alias rebootLatch: rebootLatch
    property alias viewState: state   // not `state`: that would mask Item.state

    // ── UiState.updateOpen is the one owner of "is this panel up" ────────────
    // It used to be the other way round: this Item owned `visible` and MIRRORED it
    // out. That only worked while the host was a plain always-visible holder. The
    // panel now lives in a BarDock Card whose own visibility is animated by the
    // Accordion, and `Item.visible` is EFFECTIVE visibility — an invisible ancestor
    // forces it false — so the panel and its container each thought they owned the
    // flag and fought over it, with the password field's forceActiveFocus landing
    // inside a still-invisible parent. The panel asks, the host shows.

    function startUpdate(count) {
        // The runner is a shared singleton — a run may already be in flight from the
        // Settings page. Don't reset over it; just show its progress.
        if (Updates.runBusy) {
            state.view = "running"
            UiState.updateOpen = true
            Qt.callLater(() => updateFocusItem.forceActiveFocus())
            return
        }

        _resetState()
        state.pendingCount = count ?? 0
        UiState.updateOpen = true
        if (ShellUpdate.available || ShellUpdate.error !== "") panel._shellFlash()

        // ── Nothing to update → drop the option that has nothing to do ────────
        // Offering "Update everything" with nothing pending asks for a root credential
        // to do nothing. The caught-up card says so instead, and keeps Vencord, which is
        // invisible to pacman and worth having exactly when no packages are pending.
        //
        // It does NOT auto-close: it is a card you can act on, and a panel that vanishes
        // while you are deciding is worse than one you dismiss with ESC.
        if (Updates.total === 0 && !Updates.hasError) {
            state.view = "caught"
            Qt.callLater(() => caughtCol.caughtPassField.forceFocus())
        } else {
            Qt.callLater(() => mainCol.passField.forceFocus())
        }
    }

    // ── Presentation state ────────────────────────────────────────────────────
    // Only what to SHOW lives here now. Whether a run is happening, its outcome, AND
    // its progress all come from the service: the `:: [n/N]` parser and the `inHooks`
    // latch that used to sit in this object are a protocol shared with update-run.sh,
    // not something a popup should own — see the block comment on Updates.runProgress.
    // These stay bindings rather than copies so there is still exactly one parser.
    QtObject {
        id: state
        property string view:        "main"    // main | running | caught
        property int    elapsedSecs: 0

        // How many updates are WAITING, as the caller passed them to openWith(). This
        // used to share `pkgCount` with the running view's transaction total below —
        // two different numbers under one name, which only worked because the two views
        // are never on screen at once. Separating them was forced by pkgCount becoming
        // a binding, and it should have been separate anyway.
        property int    pendingCount: 0

        readonly property int    pkgCount:      Updates.runPkgCount
        readonly property int    pkgsDone:      Updates.runPkgsDone
        readonly property real   progress:      Updates.runProgress
        readonly property string currentPkg:    Updates.runCurrentItem
        readonly property bool   inHooks:       Updates.runInHooks
        readonly property int    phaseIndex:    Updates.runPhaseIndex
        readonly property int    phaseCount:    Updates.runPhaseCount
        readonly property real   phaseProgress: Updates.runPhaseProgress
    }

    // Outcome, straight off the shared runner.
    readonly property bool isBusy:     Updates.runBusy
    readonly property bool isFinished: Updates.runDone
    readonly property bool isError:    Updates.runDone && Updates.runExit !== 0

    // ── "Finished" is not the same as "there is nothing left" ─────────────────
    // A `pacman -Syu` that finds its packages held, or a phase that no-op'd, exits
    // 0 — the run "succeeded" and installed nothing. So a clean exit only counts as
    // truly done when the post-run recheck agrees there's nothing pending (or it's
    // Vencord, which has no package count, or the check itself errored and we
    // genuinely can't tell). Otherwise the panel says so instead of claiming
    // everything's current and closing itself.
    readonly property bool trulyDone: panel.isFinished && Updates.runExit === 0
        && (panel.isVencord || Updates.total === 0 || Updates.hasError)
    // A Vencord patch and a package upgrade share the runner; the label tells them apart
    // for the "Patching Discord" line and the finished copy.
    readonly property bool isVencord:  Updates.runLabel === "Vencord"

    // ── Arriving ──────────────────────────────────────────────────────────────
    // Each view's cards play ViewEnter / PopIn when their view is shown (and once the panel has finished being
    // created); `lead` holds the very first back for the dock's own opening pause, then is 0.
    property bool opened: false
    property int  lead: Motion.emphasized
    Timer {
        running: true
        interval: Motion.emphasized + Motion.spatial * 2
        onTriggered: panel.lead = 0
    }
    Component.onCompleted: Qt.callLater(function () { panel.opened = true })
    readonly property bool mainOn:    panel.opened && state.view === "main"
    readonly property bool runningOn: panel.opened && state.view === "running"
    readonly property bool caughtOn:  panel.opened && state.view === "caught"

    // The source colours, as the counts have always worn them.
    readonly property color officialTint: Colors.of(QsWindow.window).focus
    readonly property color aurTint:      Colors.of(QsWindow.window).info
    readonly property color flatpakTint:  Colors.of(QsWindow.window).success
    function sourceTint(source) {
        return source === "aur" ? panel.aurTint : source === "flatpak" ? panel.flatpakTint : panel.officialTint
    }
    // How big a jump a package is making, in colour: the ones worth reading are the loud ones.
    function bumpTint(kind) {
        const p = Colors.of(QsWindow.window)
        return kind === "major" ? p.danger : kind === "minor" ? p.warning : kind === "new" ? p.success
             : kind === "patch" ? p.info : p.fgDim
    }

    // ── Friendly activity feed ────────────────────────────────────────────────
    // One entry per package as it finishes ("✓ firefox"), newest first — built for free
    // from the progress the log parser already extracts. When currentPkg moves on, the
    // previous one is done.
    ListModel { id: activityModel }
    property string _lastPkg: ""

    Connections {
        target: state
        function onCurrentPkgChanged() {
            const p = state.currentPkg
            if (p === "" || p === panel._lastPkg) return
            // Only real package names reach the feed. pacman parks its section headers
            // here too (":: Synchronizing package databases…"), and those contain spaces
            // where a package name never does — so a space is the tell.
            if (panel._lastPkg !== "" && panel._lastPkg.indexOf(" ") < 0) {
                activityModel.insert(0, { name: panel._lastPkg })
                if (activityModel.count > 20) activityModel.remove(activityModel.count - 1)
            }
            panel._lastPkg = p
        }
    }

    Connections {
        target: Updates
        // `state.progress` is a binding onto the service now, and the service sets it to
        // 1.0 itself when a run ends — so this is only about the auto-close.
        function onRunDoneChanged() {
            // Give the post-run recheck (3s) time to land before we decide whether
            // this was a real "nothing left" — see trulyDone / autoCloseTimer.
            if (Updates.runDone && Updates.runExit === 0) autoCloseTimer.start()
        }
    }

    // ── Activity shows the RAW OUTPUT by default ──────────────────────────────
    // Same thing the Settings page shows, for the same reason: when you go looking
    // for what an upgrade is doing, "✓ firefox" is a summary of what already
    // finished, not an account of what is happening now. The friendly per-package
    // feed is still one click away behind "Simple" — this only changes which of the
    // two you land on.
    property bool showDetails: true

    // The running view is SLIM by default (progress + current item) and grows to show the
    // activity feed only when asked — but a pending PROMPT always expands it, because a
    // blocked run you can't see the question for is exactly the hang we're fixing.
    property bool expanded: false

    // ── The pre-run peek ──────────────────────────────────────────────────────
    // The main view used to be a count and a password field — "5 updates ready",
    // trust us. This opens the actual list: what's pending, split by source, with a
    // hold toggle and (for AUR/Flatpak) a tick so you can install a subset without
    // opening full Settings.
    property bool peekExpanded: false

    // ── Filtering the list ────────────────────────────────────────────────────
    // By source (the SegmentSwitch) and by name (the field, shown once there is enough to need it); every
    // row carries how big its jump is, and the biggest come first.
    property string srcFilter: "all"        // all | official | aur | flatpak
    property string query: ""
    readonly property var sourceModel: {
        const m = [{ value: "all", label: "All " + Updates.total, icon: "inventory_2" }]
        if (Updates.count > 0)        m.push({ value: "official", label: "Official " + Updates.count,    icon: "deployed_code" })
        if (Updates.aurCount > 0)     m.push({ value: "aur",      label: "AUR " + Updates.aurCount,       icon: "extension" })
        if (Updates.flatpakCount > 0) m.push({ value: "flatpak",  label: "Flatpak " + Updates.flatpakCount, icon: "download" })
        return m
    }
    // A filter whose source emptied (a check landed) falls back to All.
    onSourceModelChanged: if (!panel.sourceModel.some(m => m.value === panel.srcFilter)) panel.srcFilter = "all"

    readonly property var rows: {
        const base = panel.srcFilter === "official" ? Updates.official
                   : panel.srcFilter === "aur"      ? Updates.aur
                   : panel.srcFilter === "flatpak"  ? Updates.flatpak
                   :                                  Updates.packages
        return base.filter(p => UF.matches(p, panel.query))
                   .map(p => ({ pkg: p, kind: UF.bump(p.from, p.to) }))
                   .sort((a, b) => UF.bumpRank(a.kind) - UF.bumpRank(b.kind) || a.pkg.name.localeCompare(b.pkg.name))
    }

    // Selected subset — same shape and rules as UpdatesPage: keyed by name,
    // reassigned not mutated (QML won't re-evaluate on an in-place change), and
    // official packages can never be ticked (a single-package official install is a
    // partial upgrade). Cleared whenever the pending list changes underneath it.
    property var selected: ({})
    readonly property var selectedNames: Object.keys(panel.selected).filter(k => panel.selected[k])
    readonly property int selectedCount: panel.selectedNames.length
    readonly property bool selectionNeedsPassword: Updates.selectionNeedsPassword(panel.selectedNames)

    function toggleSelect(name) {
        const pkg = Updates.packages.filter(p => p.name === name)[0]
        if (!pkg || pkg.source === "official") return
        const next = Object.assign({}, panel.selected)
        next[name] = !next[name]
        panel.selected = next
    }
    // Everything on show that CAN be ticked (AUR and Flatpak) — so "all the AUR ones" is two clicks.
    readonly property int tickableShown: panel.rows.filter(r => r.pkg.source !== "official").length
    function selectShown() {
        const next = Object.assign({}, panel.selected)
        panel.rows.forEach(r => { if (r.pkg.source !== "official") next[r.pkg.name] = true })
        panel.selected = next
    }
    function clearSelection() { panel.selected = ({}) }

    Connections {
        target: Updates
        function onPackagesChanged() { panel.selected = ({}) }
    }

    // How many the "update everything" run will actually touch, holds removed — the
    // number the button and the subtitle should quote.
    readonly property int activePending: Updates.total - Updates.heldPending.length

    // ── Reboot, from the finished screen ──────────────────────────────────────
    // Only offered when the upgrade replaced a kernel or graphics module. Two-step
    // (ArmLatch): a stray click here logs you out.
    ArmLatch {
        id: rebootLatch
        onConfirmed: Session.reboot()
    }

    // ── Cancel, from the header ───────────────────────────────────────────────
    // Two-step too: it ends a run in progress. Updates.cancelRun walks the real process tree and lets pacman
    // exit through its own cleanup (see the runner notes in docs/updates.md) — it was reachable only from a
    // prompt before, so a run that was merely slow could not be stopped from here.
    ArmLatch {
        id: cancelLatch
        onConfirmed: Updates.cancelRun()
    }

    // The password field, the primary action button and the in-run answer field
    // all line up on one height — they're the same "type here / press this" row in
    // three places.
    readonly property int _fieldH: Tokens.iconXl + Tokens.spacingMd

    // The shell-update gear: its spin, and whether the user clicked Check this
    // time the panel was opened (so "up to date" answers them, but a background
    // check doesn't leave a caption hanging under the form).
    property bool _shellAsked: false
    property bool _shellHover: false
    property real _shellPhase: 0

    // ── What the gear says, and for how long ──────────────────────────────────
    // No line of its own. It used to be a caption under the password row, and its
    // coming and going changed the panel's height — the card springs after the
    // content, and for that moment the content ran over the card's bottom edge. So
    // the words borrow a line that's always there: the header subtitle (main view)
    // or the "last updated" line (caught-up view). Shown while the gear is hovered,
    // checking or installing; flashed for a few seconds when a check the user
    // asked for lands, a release turns up, or an install fails — then the line
    // goes back to saying what it said. The gear's fill/red stays as the lasting cue.
    property bool _shellNote: false
    readonly property bool _shellNoteShown: panel._shellHover || panel._shellNote
        || ShellUpdate.installing || (panel._shellAsked && ShellUpdate.checking)
    Timer { id: shellNoteTimer; interval: 4500; onTriggered: panel._shellNote = false }
    function _shellFlash() { panel._shellNote = true; shellNoteTimer.restart() }
    Connections {
        target: ShellUpdate
        function onCheckingChanged() { if (!ShellUpdate.checking && panel._shellAsked) panel._shellFlash() }
        function onAvailableChanged() { if (ShellUpdate.available && UiState.updateOpen) panel._shellFlash() }
        function onErrorChanged() { if (ShellUpdate.error !== "") panel._shellFlash() }
    }
    function _shellText() {
        if (ShellUpdate.installing)   return ShellUpdate.status
        if (ShellUpdate.error !== "") return "Shell update failed: " + ShellUpdate.error
        if (ShellUpdate.available)
            return ShellUpdate.blocker !== "" ? ShellUpdate.blocker
                 : "Quicktest " + ShellUpdate.latest + " is out — the gear installs it"
        if (ShellUpdate.checking)     return "Checking for Quicktest updates…"
        if (ShellUpdate.checkFailed)  return "Couldn't reach GitHub"
        if (ShellUpdate.checked)      return "Quicktest " + ShellUpdate.current + " is up to date"
        return "Check for Quicktest updates"
    }
    NumberAnimation on _shellPhase {
        from: 0; to: 360; duration: 900
        loops: Animation.Infinite
        running: ShellUpdate.checking || ShellUpdate.installing
    }

    // Spinner phase for the header re-check button.
    property real _checkPhase: 0
    NumberAnimation on _checkPhase {
        from: 0; to: 360; duration: 900
        loops: Animation.Infinite
        running: Updates.checking
    }

    Timer {
        id: elapsedTimer
        interval: 1000; repeat: true
        running: panel.isBusy
        onTriggered: state.elapsedSecs++
    }

    // Drives the host window's size, from the content: the layout below is pinned to the top at its own
    // height, so this is simply what it needs, capped so a huge pending list scrolls inside the panel rather
    // than growing it off the bar. No implicitWidth: the DOCK gives every panel in the shell the same one,
    // and a centre panel narrower than the two beside it read as a different class of thing hanging off the
    // same bar. A prompt is part of the content, so its answer controls can never be clipped.
    implicitHeight: Math.min(outer.implicitHeight + Tokens.spacingLg * 2, 600)

    Behavior on implicitHeight { NumberAnimation { duration: Motion.fast; easing.type: Motion.travel } }

    // ── ESC, from anywhere in the panel ───────────────────────────────────────
    // On the ROOT, not only on updateFocusItem. That item is a zero-size sibling, so its
    // handler only ever fired when it personally held focus — which left ESC dead in
    // every view that focuses something else: the answer field during a prompt (a
    // TextInput with no Escape handler of its own), and the caught-up view, which has no
    // focusable control at all.
    //
    // Unhandled keys propagate UP the item tree, so catching Escape here covers every
    // focused descendant at once. The child handlers below stay — the fields consume
    // their own Escape so the key never has to travel — and this is the backstop for
    // everything that doesn't.
    focus: true
    Keys.onEscapePressed: panel._escClose()

    // ── Does this need the keyboard right now? ────────────────────────────────
    // Drives the host surface's focus mode (see PanelHost). The panel is opened by
    // clicking something ELSE — the bar pill, a desktop tile — so nothing has given it
    // keyboard focus, and OnDemand only grants it on a click. That is why the password
    // field needed clicking before it would accept typing, and why ESC did nothing.
    //
    // Exclusive for the states that read the keyboard: the password form, the caught-up
    // view (ESC, and it dismisses itself in seconds anyway), and a run that is actually
    // asking a question. A NORMAL running view deliberately falls back to OnDemand —
    // holding an exclusive keyboard grab for the length of a full system upgrade would
    // lock the rest of the desktop out of typing.
    readonly property bool wantsKeyboard:
        UiState.updateOpen && (state.view !== "running" || Updates.awaitingInput)

    // ── ESC ─────────────────────────────────────────────────────────────────
    // ESC always closes. If a run is in flight it does NOT stop it — the runner belongs
    // to the service and keeps going — so we fire a "still running" notification rather
    // than trapping the user or letting them think closing cancelled it. (The service's
    // own still-running notice is scoped to the OVERVIEW closing; this panel is a separate
    // popup, so it needs its own.)
    function _escClose() {
        if (panel.isBusy) panel._notifyStillRunning()
        _close()
    }

    Item {
        id: updateFocusItem
        Keys.onEscapePressed: panel._escClose()
        // Effective visibility, so this fires when the CONTAINER has finished
        // fading in — which is the first moment a forceActiveFocus can stick. It
        // used to fire on this Item's own flag, back when the host was always
        // visible and the two were the same thing.
        Connections {
            target: panel
            function onVisibleChanged() {
                if (panel.visible) updateFocusItem.forceActiveFocus()
            }
        }
    }

    function _notifyStillRunning() {
        Quickshell.execDetached(["notify-send", "--app-name=Quickshell", "--urgency=normal",
                                 "--icon=" + Icons.assetPath("update"),
                                 "Update still running",
                                 "It'll keep going in the background and notify you when it's done."])
    }

    // Long enough to read "all up to date" before it vanishes on its own, and long
    // enough that the 3s post-run recheck has settled trulyDone by the time it fires.
    Timer {
        id: autoCloseTimer
        interval: 5000; repeat: false
        // Only close if it really is done. A "success" that left updates pending
        // keeps the panel up so its message is seen.
        onTriggered: if (panel.trulyDone) panel._close()
    }

    // ── Helpers ───────────────────────────────────────────────────────────────
    function _resetState() {
        state.view          = "main"
        state.pendingCount  = 0
        state.elapsedSecs   = 0
        // Everything parsed — progress, the current item, the phase counters — is the
        // service's state and is cleared by Updates.clearRun() below, or by the next
        // run's own _attach(). Zeroing it here as well is what kept a second copy alive.
        mainCol.passField.clear()
        caughtCol.caughtPassField.clear()
        activityModel.clear()
        panel._lastPkg     = ""
        panel.showDetails  = true    // the default: raw output, as above
        panel.expanded     = false
        panel.peekExpanded = false
        panel.selected     = ({})
        panel.srcFilter    = "all"
        panel.query        = ""
        panel._shellAsked  = false
        panel._shellNote   = false
        cancelLatch.disarm()
        // Only clear the runner when it's idle — never wipe a run the Settings page owns.
        if (!Updates.runBusy) Updates.clearRun()
        Updates.refreshNews()
    }

    function _close() {
        UiState.updateOpen = false
        mainCol.passField.clear()
        caughtCol.caughtPassField.clear()
    }

    function getElapsedText() {
        const m = Math.floor(state.elapsedSecs / 60)
        const s = state.elapsedSecs % 60
        return (m > 0 ? m + "m " : "") + s + "s"
    }

    // The whole run's log as text, for Copy log — what to paste into a bug report or a forum post.
    function _logText() { return Updates.runLog.map(l => l.text).join("\n") }

    // ── Plain-language status ─────────────────────────────────────────────────
    function heroSymbol() {
        if (panel.isError)    return "error"
        if (panel.isFinished) return "check_circle"
        if (panel.isBusy)     return "download"
        return "update"
    }

    function heroSubtitle() {
        if (Updates.awaitingInput) return "Waiting on you — answer the question below."
        if (panel.isError)    return "Something went wrong. Open the details to see what."
        if (panel.isFinished) {
            if (panel.trulyDone) return "All done — this window will close itself."
            // Exit 0, but the recheck still sees updates — the run reported success
            // without installing them. Don't auto-close over that.
            return Updates.total + " update" + (Updates.total === 1 ? "" : "s")
                 + " still pending — open the details and check the log."
        }
        // Every package is already installed at this point — what's left is disk work
        // (rebuilding boot images, reloading services) that doesn't move the package
        // count. Said explicitly so a quiet minute here doesn't read as frozen.
        if (panel.isBusy && state.inHooks)
            return "Finishing up — this can take a minute. Don't reload yet."
        if (panel.isBusy) {
            const bits = []
            if (state.pkgCount > 0) bits.push(state.pkgsDone + " of " + state.pkgCount + " done")
            bits.push(getElapsedText() + " so far")
            return bits.join("    ·    ")
        }
        if (panel._shellNoteShown) return panel._shellText()
        if (state.pendingCount > 0)
            return state.pendingCount + " update"
                 + (state.pendingCount === 1 ? "" : "s") + " ready to install"
                 + (Updates.lastCheckedText !== "" ? "    ·    checked " + Updates.lastCheckedText : "")
        return "Enter your password to begin"
    }

    // The single line under the progress bar: what's happening right now.
    function nowDoing() {
        if (panel.isFinished) return ""          // the finished card says it instead
        if (panel.isVencord) return "Patching Discord"
        if (state.currentPkg !== "") return state.currentPkg
        if (panel.isBusy) return "Working…"
        return ""
    }

    // ── The layout ────────────────────────────────────────────────────────────
    // A HEADER at the top is always present (but for the caught-up view) and simply changes what it says as
    // the update moves prompt → working → done; the body below swaps between the three views.
    //
    // NO card of its own, deliberately — this is a bare Item like every other panel in modules/panels/. Its
    // host is a BarDock Card, which already supplies the fill, the corners and (welded) the ring's outline.
    Item {
        id: card

        anchors.fill: parent
        clip: true

        ColumnLayout {
            id: outer
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.spacingLg
            spacing: Tokens.spacingMd

            // ══ HEADER ═════════════════════════════════════════════════════════
            // Hidden in the caught-up view: that state is one cookie and two lines of
            // its own, and a "System Update" header above "you're all caught up" would
            // be the third thing saying the same thing.
            PanelHeader {
                id: header
                Layout.fillHeight: false
                visible:   state.view !== "caught"
                symbol:    panel.heroSymbol()
                title:     Translation.tr("System")
                titleTail: Translation.tr("Update")
                accent:    Colors.of(QsWindow.window).info
                subtitle:  panel.heroSubtitle()

                BusyDot {
                    Layout.alignment: Qt.AlignVCenter
                    running: panel.isBusy
                }

                // Grouped header controls, the same tray the wallpaper / colour / media panels carry.
                // Pre-run: re-check, and the way to the setup hub. Running: the log, and Cancel.
                ChipTray {
                    groupShown: state.view !== "caught" && !Updates.awaitingInput

                    ChipButton {
                        visible: state.view === "main"
                        symbol:  "refresh"
                        tint:    Colors.of(QsWindow.window).info
                        iconAngle: Updates.checking ? panel._checkPhase : 0
                        enabled: !Updates.checking
                        onActivated: Updates.check()
                    }
                    ChipButton {
                        visible: state.view === "running"
                        symbol:  "terminal"
                        on:      panel.expanded
                        tint:    Colors.of(QsWindow.window).info
                        onActivated: panel.expanded = !panel.expanded
                    }
                    // Armed, it says so and asks once more.
                    ChipButton {
                        visible: state.view === "running" && panel.isBusy && !panel.isFinished
                        symbol:  cancelLatch.armed ? "check" : "stop"
                        label:   cancelLatch.armed ? "Cancel run?" : ""
                        on:      cancelLatch.armed
                        tint:    Colors.of(QsWindow.window).danger
                        onActivated: cancelLatch.trigger()
                    }

                    // ── Way out to the setup hub ─────────────────────────────
                    // A fresh clone has packages to install and the blob to build
                    // before it looks like the screenshots. That all lives on the
                    // Setup page; this is the shortcut from where a new user is
                    // most likely to be looking.
                    ChipButton {
                        visible: state.view === "main"
                        symbol:  "settings"
                        tint:    Colors.of(QsWindow.window).info
                        onActivated: {
                            UiState.updateOpen = false
                            UiState.openSettingsTo("SetupPage.qml")
                        }
                    }
                }
            }

            // ══ CAUGHT UP — nothing pending ════════════════════════════════════
            // The same card as the main form with the one option that has nothing to do
            // removed. "Update everything" is gone; Vencord stays, because re-patching
            // Discord is invisible to pacman and is exactly the thing you might still
            // want when there are no package updates.
            //
            // It keeps a password field for that reason: the Vencord installer runs as
            // root, so the button needs a credential whether or not anything else is
            // pending. It does NOT auto-close — this is a card you can act on, and a
            // panel that vanishes mid-decision is worse than one you dismiss yourself.
            UpdateCaughtUpView {
                id: caughtCol
                panel: panel
            }

            // ══ MAIN — what's pending, and how to install it ═══════════════════
            UpdateMainView {
                id: mainCol
                panel: panel
            }

            // ══ RUNNING — progress + prompt + friendly feed ════════════════════
            UpdateRunningView {
                id: runCol
                panel: panel
            }
        }
    } // end layout

    // The reusable pieces (ShellUpdateButton, ActionButton, NewsLine, RebootBanner,
    // CompositionStrip, PkgRow) are files in update/, named Update*.







    // ── Confirmation handlers ─────────────────────────────────────────────────
    // Both hand the password to the shared runner and switch to the running view. The
    // runner's PTY answers sudo's first prompt from that password; a WRONG one (or any
    // later question) comes back through Updates.awaitingInput and the prompt surface
    // above — nothing is silently swallowed.
    function _confirmSysUpdate() {
        if (mainCol.passField.text.length === 0) return
        const pass = mainCol.passField.text
        mainCol.passField.clear()
        state.view = "running"
        updateFocusItem.forceActiveFocus()
        Updates.installAll(pass)
    }

    // A ticked subset — AUR/Flatpak only (official can't be installed singly). Same
    // runner, same running view; the password is only forwarded when AUR is in the
    // set (Flatpak authenticates through polkit).
    function _confirmSelected() {
        if (panel.selectedCount === 0) return
        if (panel.selectionNeedsPassword && mainCol.passField.text.length === 0) return
        const pass = mainCol.passField.text
        const names = panel.selectedNames
        mainCol.passField.clear()
        state.view = "running"
        updateFocusItem.forceActiveFocus()
        Updates.installSelected(names, pass)
    }

    // Takes the password rather than reading `passField`: there are two fields now (the
    // main form's and the caught-up card's), and both reach the same runner.
    function _confirmVencord(pass) {
        if (!pass || pass.length === 0) return
        mainCol.passField.clear()
        caughtCol.caughtPassField.clear()
        state.view = "running"
        updateFocusItem.forceActiveFocus()
        Updates.installVencord(pass)
    }
}
