import "../../services"
import "../../state"
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../config"
import "../../components"

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
// panel now DELEGATES to it (`Updates.installAll` / `installVencord`) and renders those
// prompts, instead of maintaining a parallel `--noconfirm` implementation. One runner,
// one place a password or a "Proceed? [Y/n]" is ever handled — and it's shared with the
// Settings → Updates page, so opening one mid-run shows the other's progress.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: panel

    // Mirror our own visibility into the Panels singleton so the status-bar pill (in a
    // separate component tree) can react without holding a direct reference to this Item.
    onVisibleChanged: UiState.updateOpen = panel.visible

    function startUpdate(count) {
        // The runner is a shared singleton — a run may already be in flight from the
        // Settings page. Don't reset over it; just show its progress.
        if (Updates.runBusy) {
            state.view = "running"
            panel.visible = true
            Qt.callLater(() => updateFocusItem.forceActiveFocus())
        } else {
            _resetState()
            state.pkgCount = count ?? 0
            panel.visible = true
            Qt.callLater(() => passField.forceActiveFocus())
        }
    }

    // ── Presentation state ────────────────────────────────────────────────────
    // Only what to SHOW and the parsed progress live here now. Whether a run is
    // happening, and its outcome, come from the service.
    QtObject {
        id: state
        property string view:        "main"    // main | running
        property int    pkgCount:    0
        property int    pkgsDone:    0
        property real   progress:    0.0
        property string currentPkg:  ""
        property int    elapsedSecs: 0
    }

    // Outcome, straight off the shared runner.
    readonly property bool isBusy:     Updates.runBusy
    readonly property bool isFinished: Updates.runDone
    readonly property bool isError:    Updates.runDone && Updates.runExit !== 0
    // A Vencord patch and a package upgrade share the runner; the label tells them apart
    // for the "Patching Discord" line and the finished copy.
    readonly property bool isVencord:  Updates.runLabel === "Vencord"

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

    // ── Progress + feed, parsed from the runner's log ─────────────────────────
    // The service streams the PTY output as `Updates.runLog` ([{text,error}]). We read
    // the SAME lines the old local pacman parser read — no second process, just watching
    // the one that exists. `_seenLines` marks how far we've consumed; a shrunk log means
    // the runner was cleared for a new run, so we start over.
    property int _seenLines: 0
    function _syncLog() {
        const log = Updates.runLog
        if (log.length < panel._seenLines) { panel._seenLines = 0; state.currentPkg = "" }
        for (let i = panel._seenLines; i < log.length; i++) panel._parseLine(log[i].text)
        panel._seenLines = log.length
    }
    function _parseLine(line) {
        if (!line) return
        const m = line.match(/(?:upgrading|installing|reinstalling|removing)\s+(\S+)\s+\((\d+)\/(\d+)\)/i)
        if (m) {
            const done = parseInt(m[2]), total = parseInt(m[3])
            state.currentPkg = m[1]
            state.pkgsDone   = done
            if (total > 0) { state.pkgCount = total; state.progress = done / total }
            return
        }
        // flatpak's byte progress, once the pacman phase is done — nudge, never rewind.
        const p = line.match(/([\d.]+)\s*MB\s*\/\s*([\d.]+)\s*MB/i)
        if (p && parseFloat(p[2]) > 0) {
            state.progress = Math.max(state.progress, parseFloat(p[1]) / parseFloat(p[2]))
            return
        }
        // pacman section header (":: …") — a phase, not a package.
        const d = line.match(/^::\s*(.*)/)
        if (d) state.currentPkg = d[1]
    }

    Connections {
        target: Updates
        function onRunLogChanged() { panel._syncLog() }
        function onRunDoneChanged() {
            if (Updates.runDone) {
                state.progress = 1.0
                if (Updates.runExit === 0) autoCloseTimer.start()
            }
        }
    }

    property bool showDetails: false

    // The running view is SLIM by default (progress + current item) and grows to show the
    // activity feed only when asked — but a pending PROMPT always expands it, because a
    // blocked run you can't see the question for is exactly the hang we're fixing.
    property bool expanded: false

    Timer {
        id: elapsedTimer
        interval: 1000; repeat: true
        running: panel.isBusy
        onTriggered: state.elapsedSecs++
    }

    // Drives the host window's size. Fixed per view (not content-derived) so the Wayland
    // surface is one stable size per state rather than resizing every frame. A prompt
    // forces the taller size so its answer controls are never clipped.
    implicitWidth:  state.view === "running" ? 440 : 380
    implicitHeight: state.view === "main" ? 220
                  : ((panel.expanded || Updates.awaitingInput) ? 400 : 184)

    Behavior on implicitWidth  { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
    Behavior on implicitHeight { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }

    visible: false

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
        Connections {
            target: panel
            function onVisibleChanged() {
                if (panel.visible) updateFocusItem.forceActiveFocus()
            }
        }
    }

    function _notifyStillRunning() {
        bgNotify.command = ["notify-send", "--app-name=System Update", "--urgency=normal",
                            "--icon=" + Icons.assetPath("update"),
                            "Update still running",
                            "It'll keep going in the background and notify you when it's done."]
        bgNotify.running = false
        bgNotify.running = true
    }

    Process { id: bgNotify }

    // Long enough to read "all up to date" before it vanishes on its own.
    Timer {
        id: autoCloseTimer
        interval: 4500; repeat: false
        onTriggered: _close()
    }

    // ── Helpers ───────────────────────────────────────────────────────────────
    function _resetState() {
        state.view        = "main"
        state.pkgCount    = 0
        state.pkgsDone    = 0
        state.progress    = 0.0
        state.currentPkg  = ""
        state.elapsedSecs = 0
        passField.text    = ""
        activityModel.clear()
        panel._lastPkg    = ""
        panel._seenLines  = 0
        panel.showDetails = false
        panel.expanded    = false
        // Only clear the runner when it's idle — never wipe a run the Settings page owns.
        if (!Updates.runBusy) Updates.clearRun()
    }

    function _close() {
        panel.visible = false
        passField.text = ""
    }

    function getElapsedText() {
        const m = Math.floor(state.elapsedSecs / 60)
        const s = state.elapsedSecs % 60
        return (m > 0 ? m + "m " : "") + s + "s"
    }

    // ── Plain-language status ─────────────────────────────────────────────────
    function heroGlyph() {
        if (panel.isError)    return "󰅚"       // alert
        if (panel.isFinished) return "󰄬"       // check
        if (panel.isBusy)     return "󰇚"       // downloading
        return "󰚰"                             // update available
    }

    function heroSubtitle() {
        if (Updates.awaitingInput) return "Waiting on you — answer the question below."
        if (panel.isError)    return "Something went wrong. Open the details to see what."
        if (panel.isFinished) return "Everything's current — this window will close itself."
        if (panel.isBusy) {
            const bits = []
            if (state.pkgCount > 0) bits.push(state.pkgsDone + " of " + state.pkgCount + " done")
            bits.push(getElapsedText() + " so far")
            return bits.join("    ·    ")
        }
        if (state.pkgCount > 0)
            return state.pkgCount + " update" + (state.pkgCount === 1 ? "" : "s") + " ready to install"
        return "Enter your password to begin"
    }

    // The single line under the progress bar: what's happening right now.
    function nowDoing() {
        if (panel.isVencord) return "Patching Discord"
        if (state.currentPkg !== "") return state.currentPkg
        if (panel.isBusy) return "Working…"
        return ""
    }

    // ── The card ──────────────────────────────────────────────────────────────
    // One Surface, one layout. A HERO at the top is always present and simply changes what
    // it says as the update moves prompt → working → done; the body below crossfades
    // between the two views. That's what makes it read as one continuous thing.
    Surface {
        id: card

        anchors.fill: parent
        elevation: Tokens.elevationCard
        focused: cardHover.hovered
        clip: true

        HoverHandler { id: cardHover }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.spacingLg
            spacing: Tokens.spacingMd

            // ══ HEADER ═════════════════════════════════════════════════════════
            PanelHeader {
                glyph:     panel.heroGlyph()
                title:     "System"
                titleTail: "Update"
                accent:    Colors.info
                subtitle:  panel.heroSubtitle()

                BusyDot {
                    Layout.alignment: Qt.AlignVCenter
                    running: panel.isBusy
                }
            }

            // ══ MAIN — the prompt ══════════════════════════════════════════════
            ColumnLayout {
                Layout.fillWidth: true
                visible: state.view === "main"
                opacity: visible ? 1 : 0
                spacing: Tokens.spacingMd
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                Divider {}

                PasswordInput {
                    id: passField
                    iconColor: Colors.focus
                    onAccepted: _confirmSysUpdate()
                    onEscaped:  panel._escClose()
                }

                ActionButton {
                    icon: "󰇚"
                    text: "Update everything"
                    accent: Colors.focus
                    disabled: passField.text.length === 0
                    clickHandler: function() { _confirmSysUpdate() }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingMd
                    Divider { Layout.fillWidth: true }
                    StyledText { text: "or just"; variant: "caption"; emphasis: "dim" }
                    Divider { Layout.fillWidth: true }
                }

                ActionButton {
                    icon: "󰙯"
                    text: "Update Discord (Vencord)"
                    accent: Colors.info
                    variant: "normal"
                    disabled: passField.text.length === 0
                    clickHandler: function() { _confirmVencord() }
                }
            }

            // ══ RUNNING — progress + prompt + friendly feed ════════════════════
            ColumnLayout {
                Layout.fillWidth:  true
                Layout.fillHeight: true
                visible: state.view === "running"
                opacity: visible ? 1 : 0
                spacing: Tokens.spacingMd
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                // Progress bar + percent.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingMd

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 6
                        radius: 3
                        color: Colors.alpha(Colors.fg, 0.12)

                        Rectangle {
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: parent.width * Math.max(0, Math.min(1, state.progress))
                            radius: parent.radius
                            color: panel.isError ? Colors.danger : Colors.focus
                            Behavior on width { NumberAnimation { duration: Motion.slow; easing.type: Motion.travel } }
                            Behavior on color { ColorAnimation { duration: Motion.fast } }
                        }
                    }

                    StyledText {
                        text: Math.round(Math.max(0, Math.min(1, state.progress)) * 100) + "%"
                        variant: "caption"
                        font.family: Tokens.fontMono
                        font.bold: true
                        color: panel.isError ? Colors.danger : Colors.focus
                    }
                }

                // What's happening right now.
                RowLayout {
                    Layout.fillWidth: true
                    visible: panel.nowDoing() !== "" && !Updates.awaitingInput
                    spacing: Tokens.spacingMd

                    StyledText { text: "󰦖"; variant: "label"; color: Colors.focus }
                    StyledText {
                        Layout.fillWidth: true
                        text: panel.nowDoing()
                        variant: "body"
                        font.family: Tokens.fontMono
                        elide: Text.ElideMiddle
                    }
                    Badge {
                        visible: state.pkgCount > 0 && !panel.isVencord
                        label: state.pkgsDone + " / " + state.pkgCount
                        tint: Colors.focus
                        filled: true
                    }
                }

                // ══ INTERACTIVE PROMPT ═════════════════════════════════════════
                // pacman/yay asked something — a conflict, a replacement, a provider
                // choice, a confirmation, or sudo re-prompting after a long build — and
                // the run is blocked on stdin until it's answered. This is the whole point
                // of the rewrite: the question is now VISIBLE and answerable, instead of
                // the run wedging silently. Cancel is always here, so a question the parser
                // didn't anticipate can never trap the panel.
                Surface {
                    Layout.fillWidth: true
                    elevation: Tokens.elevationNested
                    focused: true
                    visible: Updates.awaitingInput
                    implicitHeight: promptCol.implicitHeight + Tokens.spacingLg * 2

                    ColumnLayout {
                        id: promptCol
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Tokens.spacingLg }
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
                            maximumLineCount: 4
                            elide: Text.ElideRight
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
                                label: "Cancel"
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
                                implicitHeight: 34
                                radius: Tokens.radiusPill
                                color: Colors.surfaceContainer
                                border.width: Tokens.borderWidth
                                border.color: answerField.activeFocus ? Colors.outlineFocus : Colors.outline

                                TextInput {
                                    id: answerField
                                    anchors.fill: parent
                                    anchors.leftMargin:  Tokens.spacingMd
                                    anchors.rightMargin: Tokens.spacingMd
                                    verticalAlignment: TextInput.AlignVCenter
                                    color: Colors.fg
                                    font.family: Tokens.fontFamily
                                    font.pixelSize: Tokens.fontBody
                                    echoMode: Updates.promptKind === "password" ? TextInput.Password : TextInput.Normal
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

                // Expand / collapse. Slim by default; this reveals the activity feed.
                // Hidden while a prompt is up — the question is what matters then.
                PanelButton {
                    Layout.fillWidth: true
                    visible: !Updates.awaitingInput
                    variant: "normal"
                    glyph: panel.expanded ? "󰅃" : "󰅀"
                    label: panel.expanded ? "Hide activity" : "Show activity"
                    onActivated: panel.expanded = !panel.expanded
                }

                // ══ ACTIVITY — only when expanded and not prompting ════════════
                ColumnLayout {
                    Layout.fillWidth:  true
                    Layout.fillHeight: true
                    visible: panel.expanded && !Updates.awaitingInput
                    spacing: Tokens.spacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            Layout.fillWidth: true
                            text: panel.showDetails ? "OUTPUT" : "RECENTLY UPDATED"
                            variant: "caption"
                            emphasis: "dim"
                            font.bold: true
                            font.letterSpacing: 1.0
                        }
                        PanelButton {
                            variant: "ghost"
                            implicitHeight: 22
                            glyph: "󰦪"
                            label: panel.showDetails ? "Simple" : "Details"
                            onActivated: panel.showDetails = !panel.showDetails
                        }
                    }

                    // ── The friendly feed (default) ────────────────────────────
                    ListView {
                        Layout.fillWidth:  true
                        Layout.fillHeight: true
                        visible: !panel.showDetails
                        clip: true
                        model: activityModel
                        spacing: 2

                        delegate: RowLayout {
                            required property var model
                            width: ListView.view.width
                            spacing: Tokens.spacingSm

                            StyledText { text: "󰄬"; variant: "caption"; color: Colors.success }
                            StyledText {
                                Layout.fillWidth: true
                                text: model.name
                                variant: "caption"
                                emphasis: "muted"
                                font.family: Tokens.fontMono
                                elide: Text.ElideMiddle
                            }
                        }

                        StyledText {
                            anchors.centerIn: parent
                            visible: activityModel.count === 0
                            text: panel.isBusy ? "Getting started…" : "Nothing to report"
                            variant: "caption"
                            emphasis: "dim"
                        }
                    }

                    // ── Raw details (opt-in) ───────────────────────────────────
                    // Bound straight to the runner's log — no local copy to keep in sync.
                    ListView {
                        id: logView
                        Layout.fillWidth:  true
                        Layout.fillHeight: true
                        visible: panel.showDetails
                        clip: true
                        model: Updates.runLog
                        spacing: 1
                        verticalLayoutDirection: ListView.BottomToTop

                        delegate: RowLayout {
                            required property var modelData
                            width: ListView.view.width
                            spacing: Tokens.spacingSm

                            Rectangle {
                                visible: modelData.error
                                Layout.preferredWidth: 2
                                Layout.preferredHeight: 9
                                radius: 1
                                color: Colors.danger
                                Layout.alignment: Qt.AlignVCenter
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.text
                                variant: "caption"
                                color: modelData.error ? Colors.danger : Colors.fgMuted
                                font.family: Tokens.fontMono
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                            }
                        }
                        onCountChanged: Qt.callLater(() => logView.positionViewAtBeginning())
                    }
                }
            }
        }
    } // end card

    // ── Reusable components ───────────────────────────────────────────────────

    // The sudo field as an inset pill — the same idiom the bar uses for its controls and
    // the launcher uses for its search.
    component PasswordInput: Surface {
        id: pwdRoot
        property alias text: input.text
        property color iconColor: Colors.focus
        signal accepted
        signal escaped

        Layout.fillWidth: true
        implicitHeight: 34
        elevation:    Tokens.elevationNested
        cornerRadius: Tokens.radiusPill
        focused:      input.activeFocus

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin:  Tokens.spacingLg
            anchors.rightMargin: Tokens.spacingLg
            spacing: Tokens.spacingMd

            StyledText {
                text: "󰌾"
                color: input.activeFocus ? pwdRoot.iconColor : Colors.fgDim
                variant: "label"
                Behavior on color { ColorAnimation { duration: Motion.respond } }
            }
            TextInput {
                id: input
                Layout.fillWidth: true
                verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                color: Colors.fg
                selectionColor: Colors.alpha(pwdRoot.iconColor, 0.35)
                font.family: Tokens.fontFamily
                font.pixelSize: Tokens.fontBody

                StyledText {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: input.text.length === 0
                    text: "sudo password…"
                    variant: "body"
                    color: Colors.fgDim
                }
                Keys.onReturnPressed: pwdRoot.accepted()
                Keys.onEnterPressed:  pwdRoot.accepted()
                Keys.onEscapePressed: pwdRoot.escaped()
            }
        }
    }

    // A full-width primary action.
    component ActionButton: PanelButton {
        property string icon
        property string text
        property var clickHandler: null
        property bool  disabled: false

        Layout.fillWidth: true
        implicitHeight: 34
        variant: "primary"
        glyph: icon
        label: text
        enabled: !disabled          // Item.enabled — PanelButton already dims on it
        onActivated: if (clickHandler) clickHandler()
    }

    // ── Confirmation handlers ─────────────────────────────────────────────────
    // Both hand the password to the shared runner and switch to the running view. The
    // runner's PTY answers sudo's first prompt from that password; a WRONG one (or any
    // later question) comes back through Updates.awaitingInput and the prompt surface
    // above — nothing is silently swallowed.
    function _confirmSysUpdate() {
        if (passField.text.length === 0) return
        const pass = passField.text
        passField.text = ""
        state.view = "running"
        state.progress = 0
        state.pkgsDone = 0
        updateFocusItem.forceActiveFocus()
        Updates.installAll(pass)
    }

    function _confirmVencord() {
        if (passField.text.length === 0) return
        const pass = passField.text
        passField.text = ""
        state.view = "running"
        state.progress = 0
        updateFocusItem.forceActiveFocus()
        Updates.installVencord(pass)
    }
}
