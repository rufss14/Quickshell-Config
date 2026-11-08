import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services/calc.js" as Calc
import "../../services/launcher.js" as Logic
import "../../services"
import "../../state"

// ── AppLauncherPanel ──────────────────────────────────────────────────────────
// A search field, and — once you type — what it found. At rest it is only the field.
//
//   field    LauncherField   the pill: mode glyph, chip, text, one trailing button
//   band     LauncherAction  a sum, a command or a question: the one actionable answer
//   body     one of:         LauncherChat · LauncherHelp · LauncherQuick · LauncherEmoji ·
//                            the result list · "no match"
//   footer   LauncherHints   the keys that do something right now
//
// The thinking lives elsewhere: ranking, history and what Enter means are
// services/launcher.js (tested) behind the Launcher service; the calculator is
// calc.js; the AI is the Ai service. This file holds the state they share and the
// geometry — that is all.
//
// ── M3E: springs, one plate ───────────────────────────────────────────────────
// Every size that changes here (the card, the band, the footer) follows its target on a
// SpringValue, which keeps its velocity when the target moves — the property the old
// SmoothedAnimation pair existed for, now with the expressive overshoot. The selected row is
// ONE tonal plate behind the list that glides between rows (it stretches a little at speed);
// rows themselves only re-colour. Results are grouped under quiet headers when more than one
// kind answers (launcher.js groupResults), the best match's group first.
//
// ── Geometry: anchored zones, no arithmetic mid-animation ─────────────────────
// `implicitHeight` is the card's TARGET; the host eases the card toward it. The field
// is pinned to the top and the footer to the real bottom, and the body fills whatever
// is actually between — so the whole stack rides the card's animation instead of racing
// it. (The pin strip once positioned itself at the TARGET height and jumped ahead of the
// card on every keystroke.) Don't "simplify" this into a ColumnLayout.
//
// ── One place for keys ────────────────────────────────────────────────────────
// Focus stays in the field the whole time. Up/Down move the list's selection without
// taking focus, so typing always refines the search and there's no "back to the field"
// step. The field and this root both hand keys to handleKey().
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Nothing is drawn past the card's own edge: the footer waits below it and is revealed.
    clip: true

    signal closeRequested()

    property string query: ""
    property string mode: ""            // "" | "run" | "ask" | "pkg" — a prefix, consumed by the field
    // The help card takes the body, like the AI answer does. Any keystroke puts it away:
    // a reference card you have to dismiss before typing is one you stop opening.
    property bool helpOpen: false

    // ── Geometry, all from the tokens ─────────────────────────────────────────
    // Proportions: it used to be a 60px field over 56px rows, six of them, with a 40px
    // footer — 460px of card for a search box. Rows are now icon + a little air, the field
    // is the shell's own field height plus a margin, and five rows is the ceiling: enough
    // to scan, short enough to stay a search box rather than a menu.
    readonly property int fieldBlockH: Tokens.fieldHeight + Tokens.spacingMd * 3
    readonly property int rowH:        Tokens.iconXl + Tokens.spacingMd * 2
    readonly property int actionH:     Tokens.iconLg + Tokens.spacingLg * 2
    readonly property int bodyPad:     Tokens.spacingSm
    readonly property int maxRows:     Math.max(3, Math.min(8, Config.launcherRows))
    readonly property int maxResults:  30
    readonly property int maxBodyH:    maxRows * rowH + (maxRows - 1) * Tokens.spacingXs + bodyPad * 2
    readonly property int emptyH:      rowH * 2 + Tokens.spacingMd
    readonly property int headerH:     Tokens.iconLg + Tokens.spacingXs
    readonly property int maxEmoji:    180

    // ── What it found ─────────────────────────────────────────────────────────
    // A mode owns the query outright: `>htop` must not also match applications behind
    // the command you're typing. Reads the Launcher service's index, history and the
    // pins, so it re-runs when any of them moves.
    readonly property var  rawResults:
          root.mode === ""      ? Launcher.search(root.query, root.maxResults)
        : root.mode === "pkg"   ? root.packageRows
        : root.mode === "clip"  ? Launcher.searchClip(root.query, root.maxResults)
        : root.mode === "emoji" ? Emoji.search(root.query, root.maxEmoji)
        :                         []
    // Same order, with `group` / `groupFirst` on each row (a header only shows when two kinds answer).
    readonly property var  results: Logic.groupResults(root.rawResults)
    // The emoji list is read from disk the first time `:` is up.
    Binding { target: Emoji; property: "wanted"; value: root.isEmoji }

    // `+`: the package search (services/Packages) as rows. The query goes to the service
    // only while the mode is up — nothing searches otherwise.
    Binding { target: Packages; property: "query"; value: root.isPkg ? root.query : "" }
    readonly property var packageRows: Packages.results.map(p => ({
        kind: "package", id: "pkg:" + p.source + "/" + p.name, name: p.name,
        ranges: Logic.scoreText(p.name, root.text.toLowerCase().split(/\s+/)[0] || "").ranges,
        generic: p.version + (p.description !== "" ? "  ·  " + p.description : ""),
        symbol: "package", pkg: p
    }))
    readonly property bool hasResults: root.results.length > 0

    // The calculator's answer, or null — the ordinary case, since most queries are app
    // names. It does NOT suppress the list: "2048" is a game as well as a number.
    readonly property var  calcResult: root.mode === "" && Config.launcherCalc ? Calc.evaluate(root.query) : null
    readonly property bool hasCalc:    root.calcResult !== null

    readonly property bool isRun:    root.mode === "run"
    readonly property bool isAsk:    root.mode === "ask"
    readonly property bool isPkg:    root.mode === "pkg"
    readonly property bool isClip:   root.mode === "clip"
    readonly property bool isEmoji:  root.mode === "emoji"
    readonly property string text:   root.query.trim()
    readonly property bool chatting: Ai.hasThread || Ai.busy

    readonly property string modeLabel:
        root.isRun ? "Run" : root.isAsk ? Ai.label : root.isPkg ? "Install"
        : root.isClip ? "Clipboard" : root.isEmoji ? "Emoji" : ""
    readonly property string modeIcon:
        root.isRun ? "terminal" : root.isPkg ? "package" : root.isClip ? "content_paste"
        : root.isEmoji ? "emoji_emotions" : "search"
    // The badge's M3E shape: it morphs when the mode changes.
    readonly property string modeShape:
        root.isRun ? "squircle" : root.isAsk ? "sunny" : root.isPkg ? "hexagon"
        : root.isClip ? "clover" : root.isEmoji ? "burst" : "cookie9"

    // What Tab / right-click opened: { result, items } for an app row, else null. The body
    // swaps to the quick actions until it is put away (Esc, Tab, a keystroke, a pick).
    property var quick: null
    readonly property bool quickOpen: root.quick !== null

    readonly property bool expanded:
        root.text !== "" || root.mode !== "" || root.chatting || root.helpOpen

    // "No match" is only ever about a search: `>htop` and a chat are not failed searches, a
    // calculator answer is an answer, and the emoji grid says its own.
    readonly property bool showEmpty:
        !root.hasResults && !root.hasCalc && !root.chatting && !root.helpOpen && !root.quickOpen
        && ((root.text !== "" && (root.mode === "" || root.isPkg)) || root.isClip)

    // ── The band: one actionable answer, whichever kind ───────────────────────
    readonly property string actionKind:
          root.chatting || root.helpOpen ? ""
        : root.isRun && root.text !== "" ? "run"
        : root.isAsk && root.text !== "" ? "ask"
        : root.hasCalc                   ? "calc"
        :                                  ""

    // What the band says under the question while `?` is up: what is happening, who is
    // answering, or what went wrong.
    readonly property string askDetail:
          Ai.blocker() !== "" ? (Ai.blocker() + " — Enter searches " + Config.webSearchName)
        : Ai.busy             ? ("Asking " + Ai.label + "…")
        : Ai.error !== ""     ? Ai.error
        :                       ("Ask " + Ai.label)

    // ── Sizes the card should be ──────────────────────────────────────────────
    readonly property int wantActionH: root.actionKind !== "" ? root.actionH : 0

    readonly property int wantBodyH:
          root.helpOpen   ? Math.min(help.implicitHeight, root.maxBodyH - root.bodyPad * 2) + root.bodyPad * 2
        : root.quickOpen  ? Math.min(quickView.implicitHeight, root.maxBodyH + root.headerH)
        : root.chatting   ? Math.min(chat.contentH + root.bodyPad * 2, root.maxBodyH)
        : root.isEmoji    ? emoji.implicitHeight
        : root.hasResults ? Logic.bodyHeight(root.results, { rowH: root.rowH, gap: Tokens.spacingXs,
                                headerH: root.headerH, maxRows: root.maxRows, pad: root.bodyPad })
        : root.showEmpty  ? root.emptyH
        :                   0

    readonly property int footerH:     hints.implicitHeight + Tokens.spacingSm * 2
    readonly property int wantFooterH: root.expanded ? root.footerH : 0

    // Where the footer sits: just below the content, whether or not it is showing. Closed,
    // that is exactly the card's bottom edge, so it is clipped away; opening, the edge
    // sweeps down over it. It used to be anchored to the card's bottom, which put it ON the
    // search field the instant the first letter was typed and then dragged it down the
    // card with the edge.
    readonly property real wantFootY: root.fieldBlockH + root.wantActionH + root.wantBodyH
    readonly property int wantTotalH: root.fieldBlockH + root.wantActionH + root.wantBodyH + root.wantFooterH

    // ── Sizes follow their targets on springs ─────────────────────────────────
    // The targets change with nearly every keystroke (the number of matches). A spring keeps
    // its velocity when the target moves, so a run of keystrokes is one continuous motion
    // instead of a restart per letter (the stutter the first version had, and the reason
    // the dock's own ease follows a panel that is already moving). The slight overshoot of
    // Motion.springSpatial is the expressive part; `clip` hides any gap it opens below the
    // footer for a frame. Animations off: the springs simply equal their targets.
    //
    // (An earlier version told the dock to stop easing a panel that was already open.
    // It read `wanted` through a Behavior's `enabled`, which can still hold its old value
    // when the close lands, and the card snapped shut with no melt. Don't do that.)
    SpringValue { id: heightSpring; spec: Motion.springSpatial; epsilon: 0.3; target: root.wantTotalH }
    SpringValue { id: footSpring;   spec: Motion.springSpatial; epsilon: 0.3; target: root.wantFootY }
    SpringValue { id: bandSpring;   spec: Motion.springSpatial; epsilon: 0.3; target: root.wantActionH }
    readonly property real footY: Math.max(root.fieldBlockH, footSpring.value)
    implicitHeight: Math.max(root.fieldBlockH, Math.round(heightSpring.value))

    // ── What the empty field types out, in turn ───────────────────────────────
    // "Search apps" stays; after it the field types one prefix at a time — the key you
    // would press, then what it does — and erases it for the next. The prefixes are the
    // launcher's best features and its worst-kept secret.
    // The hints the empty field types — the Launcher service's, so Settings shows the
    // same ones.
    readonly property var idleHints: Launcher.idleHints

    // ── What the footer says ──────────────────────────────────────────────────
    readonly property var hintList:
          root.helpOpen ? [["any key", "Close"]]
        : root.quickOpen ? [["↑↓", "Select"], ["↵", "Do it"], ["Esc", "Back"]]
        : root.chatting ? [["↵", "Send"], ["Esc", "Clear"]]
        : root.isRun    ? [["↵", "Run in " + Terminal.resolved], ["Esc", "Back"]]
        : root.isAsk    ? [["↵", "Ask " + Ai.label], ["Esc", "Back"]]
        : root.isPkg    ? (root.hasResults ? [["↑↓", "Select"], ["↵", "Install"], ["Esc", "Back"]]
                                           : [["Esc", "Back"]])
        : root.isClip   ? (root.hasResults ? [["↑↓", "Select"], ["↵", "Copy"], ["Esc", "Back"]]
                                           : [["Esc", "Back"]])
        : root.isEmoji  ? (root.hasResults ? [["←↑↓→", "Move"], ["↵", "Copy"], ["Esc", "Back"]]
                                           : [["Esc", "Back"]])
        : root.hasResults
            ? [["↑↓", "Select"], ["↵", root.currentKind === "web" ? "Search" : "Open"]]
              .concat(root.currentKind === "app" ? [["Tab", "Actions"], ["Ctrl P", "Pin"]] : [],
                      root.hasCalc ? [["Ctrl ↵", "Copy answer"]] : [], [["Esc", "Clear"]])
        : root.hasCalc  ? [["↵", "Copy answer"], ["Esc", "Clear"]]
        :                 [["Esc", "Clear"]]

    // ── Actions ───────────────────────────────────────────────────────────────
    function launch(entry) {
        if (!entry) return
        Launcher.launch(entry)
        root.closeRequested()
    }

    // Any row: an app, a shell action, a settings page, a package. Closes only when
    // something happened — an action that's blocked, or a package already installed,
    // leaves the launcher up, its row saying why.
    function open(result) {
        if (!result) return
        if (result.kind === "package") {
            if (Packages.install(result.pkg)) root.closeRequested()
            return
        }
        if (Launcher.open(result)) root.closeRequested()
    }

    function runCommand() {
        if (!root.isRun || root.text === "") return
        // `exec bash` after, so the window stays for you to read the output.
        Terminal.run(root.text + "; exec bash")
        root.closeRequested()
    }

    function openUrl(url) {
        if (!url) return
        Quickshell.execDetached(["xdg-open", url])
        root.closeRequested()
    }

    // The escape hatch: search the web for the same thing in a browser. Reachable
    // whether or not the AI answered, because "that is not what I meant" needs somewhere
    // to go.
    function openInBrowser(q) {
        const text = (q === undefined ? root.text : q).trim()
        if (text !== "") root.openUrl(Config.webSearchUrl.replace("%s", encodeURIComponent(text)))
    }

    // Nothing leaves the machine until this runs — no suggestions, no network call as
    // you type. That is why this is a prefix and not the default. With no key (or
    // Config.aiEnabled off) it falls through to a plain web search, so `?` always does
    // SOMETHING rather than failing on a click — the blocker() contract.
    function askAi(q) {
        const text = (q === undefined ? root.text : q).trim()
        if (text === "") return
        if (Ai.blocker() !== "") { root.openInBrowser(text); return }
        Ai.ask(text)
        // Cleared here: the first message is sent before a thread exists, so a caller
        // that only clears on a follow-up would leave the opening question in the field.
        field.clear()
    }

    function copyCalc() {
        if (!root.hasCalc) return
        Clipboard.copyText(root.calcResult.display)
        root.closeRequested()
    }

    // The selection lives in the view that shows it (a list, or the emoji grid).
    function selIndex() { return root.isEmoji ? emoji.currentIndex : list.currentIndex }
    function setSel(i)  { list.currentIndex = i; emoji.currentIndex = i }

    function currentEntry() {
        if (!root.hasResults) return null
        return root.results[Math.max(0, Math.min(root.selIndex(), root.results.length - 1))]
    }
    readonly property string currentKind: root.hasResults ? (root.currentEntry()?.kind ?? "") : ""

    // ── Quick actions: what you can do with the app you are on ────────────────
    function openQuick(result) {
        const items = Launcher.quickActions(result)
        if (items.length === 0) return
        quickView.currentIndex = 0
        root.quick = { result: result, items: items }
    }
    function toggleQuick() {
        if (root.quickOpen) root.quick = null
        else if (root.currentKind === "app") root.openQuick(root.currentEntry())
    }
    function runQuick(i) {
        const it = root.quick ? root.quick.items[i] : null
        if (!it) return
        it.run()
        // Opening and a desktop action close the launcher; pin and forget change the row
        // and go back to the list, which shows the change.
        if (it.closes) root.closeRequested()
        else           root.quick = null
    }

    // What the band does when tapped — the same decision Enter makes, so a tap and a
    // keypress can never disagree about what is on offer.
    function runAction() {
        if      (root.actionKind === "run")  root.runCommand()
        else if (root.actionKind === "ask")  root.askAi()
        else if (root.actionKind === "calc") root.copyCalc()
    }

    // ── What Enter does, in exactly one place (launcher.js enterAction) ───────
    function activate() {
        if (root.quickOpen) { root.runQuick(quickView.currentIndex); return }
        switch (Logic.enterAction({ mode: root.mode, text: root.query, chatting: root.chatting,
                                    results: root.results.length, calc: root.hasCalc })) {
        case "run":    root.runCommand(); break
        case "ask":    root.askAi(); break
        case "launch":
        case "pick":
        case "install": root.open(root.currentEntry()); break
        case "copy":   root.copyCalc(); break
        }
    }

    // Escape peels one layer: the help card, then the text, then the mode, then the
    // launcher itself.
    function back() {
        if (root.quickOpen)                      root.quick = null
        else if (root.helpOpen)                  root.helpOpen = false
        else if (field.text.length > 0)          field.clear()
        else if (root.mode !== "" && !root.chatting) root.mode = ""
        else                                     root.closeRequested()
    }

    function step(by) {
        if (root.quickOpen) { quickView.step(by); return }
        if (!root.hasResults || root.chatting || root.helpOpen) return
        root.setSel(Math.max(0, Math.min(root.selIndex() + by, root.results.length - 1)))
    }

    // Left / Right: along a row of the emoji grid. Nothing elsewhere — the field keeps them
    // for its caret.
    function sideStep(by) {
        if (!root.isEmoji || !root.hasResults || root.helpOpen) return false
        root.step(by)
        return true
    }

    function togglePin(entry) {
        // Pins are the dock's: apps only.
        if (entry && (entry.kind ?? "app") === "app") Pins.toggle(entry.id)
    }

    // ── Called by BarPanelDock (the centre dock hosts this) ───────────────────
    // Part of this panel's contract with its host: the popup focuses the field when it
    // opens, and clears everything on close so the height collapses BEFORE the fade
    // starts — otherwise the card flashes at full height the next time it opens.
    function focusSearch() { field.focusInput() }

    function resetSearch() {
        field.clear()
        root.query = ""
        root.mode = ""
        root.helpOpen = false
        root.quick = null
        root.setSel(0)
        // The thread's whole lifetime: open the launcher, have a conversation, close it
        // and it is gone. Nothing is written to disk — see services/Ai.qml.
        Ai.clear()
    }

    // The one key handler. Returns with `accepted` false for anything it doesn't own, so
    // typing, selection and paste reach the text field untouched.
    function handleKey(ev) {
        const ctrl = (ev.modifiers & Qt.ControlModifier) !== 0
        if (ev.key === Qt.Key_Escape)                      root.back()
        else if (ev.key === Qt.Key_Down)                   root.step(root.isEmoji && !root.quickOpen ? emoji.columns : 1)
        else if (ev.key === Qt.Key_Up)                     root.step(root.isEmoji && !root.quickOpen ? -emoji.columns : -1)
        else if (ev.key === Qt.Key_Right && root.sideStep(1))  {}
        else if (ev.key === Qt.Key_Left && root.sideStep(-1))  {}
        else if (ev.key === Qt.Key_Tab && (root.quickOpen || root.currentKind === "app")) root.toggleQuick()
        else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
            // Ctrl+Enter copies the sum even while an app match holds plain Enter —
            // "2048" is both a number and a game, and the number would otherwise be
            // unreachable from the keyboard.
            if (ctrl) root.copyCalc()
            else      root.activate()
        }
        else if (ctrl && ev.key === Qt.Key_P && !root.quickOpen) root.togglePin(root.currentEntry())
        // Backspace on an empty field takes the chip off, so the prefix deletes like the
        // character it replaced. Anywhere else it is just editing.
        else if (ev.key === Qt.Key_Backspace && field.text.length === 0
                 && root.mode !== "" && !root.chatting)    root.mode = ""
        else return
        ev.accepted = true
    }

    Keys.onPressed: function(ev) { root.handleKey(ev) }

    // ══ FIELD ═════════════════════════════════════════════════════════════════
    Item {
        id: fieldBlock
        anchors.top:   parent.top
        anchors.left:  parent.left
        anchors.right: parent.right
        height: root.fieldBlockH

        LauncherField {
            id: field
            anchors.fill: parent
            anchors.leftMargin:   Tokens.spacingLg
            anchors.rightMargin:  Tokens.spacingLg
            anchors.topMargin:    Tokens.spacingMd
            anchors.bottomMargin: Tokens.spacingMd

            mode: root.mode
            modeLabel: root.modeLabel
            shape: root.modeShape
            icon: root.modeIcon
            busy: Ai.busy
            helpOpen: root.helpOpen
            // Idle: the field types its hints. In a mode or a chat it says one fixed thing.
            lead: "Search apps"
            hints: root.mode === "" && !root.chatting ? root.idleHints : []
            placeholder: root.isRun ? "Command to run…"
                       : root.isPkg ? (Packages.aurEnabled ? "Package to install (repos and AUR)…" : "Package to install…")
                       : root.isClip ? "Search what you copied…"
                       : root.isEmoji ? "Find an emoji…"
                       : root.isAsk || root.chatting ? (root.chatting ? "Reply…" : "Ask anything…")
                       : "Search apps"

            onPrefixTyped: m => root.mode = m
            onEdited: t => {
                root.query = t
                root.setSel(0)
                root.helpOpen = false       // typing puts the card away
                root.quick = null
            }
            onKeyed: ev => root.handleKey(ev)
            onStopRequested: Ai.stop()
            onHelpToggled: root.helpOpen = !root.helpOpen
        }

        Divider {
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin:  Tokens.spacingLg
            anchors.rightMargin: Tokens.spacingLg
            opacity: root.expanded ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.standard } }
        }
    }

    // ══ BAND ══════════════════════════════════════════════════════════════════
    // Sprung like the card's own height. This band appearing is a step, and taken instantly
    // it shoved the list down a whole row while the card was still growing into the space —
    // the top of the launcher twitching as you type.
    Item {
        id: band
        anchors.top:   fieldBlock.bottom
        anchors.left:  parent.left
        anchors.right: parent.right
        height: Math.max(0, Math.round(bandSpring.value))
        clip: true

        LauncherAction {
            anchors.fill: parent
            anchors.leftMargin:   Tokens.spacingMd
            anchors.rightMargin:  Tokens.spacingMd
            anchors.bottomMargin: Tokens.spacingXs
            visible: root.actionKind !== ""

            icon: root.actionKind === "run" ? "terminal"
                : root.actionKind === "ask" ? "auto_awesome" : "calculate"
            title: root.actionKind === "calc" ? (root.calcResult?.display ?? "") : root.text
            detail: root.actionKind === "run"  ? ("Run in " + Terminal.resolved)
                  : root.actionKind === "ask"  ? root.askDetail
                  : root.actionKind === "calc" ? (root.calcResult?.detail ?? "") : ""
            onActivated: root.runAction()
        }
    }

    // ══ FOOTER ════════════════════════════════════════════════════════════════
    Item {
        id: footer
        anchors.left:  parent.left
        anchors.right: parent.right
        y: root.footY
        height: root.footerH
        opacity: root.expanded ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.standard } }

        Divider {
            anchors.top:   parent.top
            anchors.left:  parent.left
            anchors.right: parent.right
            anchors.leftMargin:  Tokens.spacingLg
            anchors.rightMargin: Tokens.spacingLg
        }
        LauncherHints {
            id: hints
            anchors.left:  parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin:  Tokens.spacingLg
            anchors.rightMargin: Tokens.spacingLg
            hints: root.hintList
        }
    }

    // ══ BODY ══════════════════════════════════════════════════════════════════
    Item {
        id: body
        anchors.top:    band.bottom
        anchors.left:   parent.left
        anchors.right:  parent.right
        anchors.bottom: footer.top
        clip: true

        LauncherChat {
            id: chat
            anchors.fill: parent
            visible: root.chatting && !root.helpOpen
        }

        Flickable {
            anchors.fill: parent
            anchors.margins: root.bodyPad
            visible: root.helpOpen
            clip: true
            interactive: contentHeight > height
            contentWidth:  width
            contentHeight: help.implicitHeight

            LauncherHelp {
                id: help
                width: parent.width
                terminal: Terminal.resolved
                onSettingsRequested: {
                    UiState.openSettingsTo("LauncherPage.qml")
                    root.closeRequested()
                }
            }
        }

        // What the app on the selection can do (Tab / right-click).
        LauncherQuick {
            id: quickView
            anchors.fill: parent
            visible: root.quickOpen && !root.helpOpen
            items: root.quick ? root.quick.items : []
            title: root.quick ? root.quick.result.name : ""
            iconPath: root.quick ? Icons.pathForAppId(root.quick.result.id) : ""
            onPicked: i => root.runQuick(i)
        }

        // `:` — a grid, not a list.
        LauncherEmoji {
            id: emoji
            anchors.fill: parent
            visible: root.isEmoji && !root.helpOpen
            rows: root.isEmoji ? root.results : []
            emptyText: Emoji.blocker() !== "" ? Emoji.blocker()
                     : !Emoji.ready ? "Loading…"
                     : root.text !== "" ? "No emoji matches “" + root.text + "”"
                     : "Type to find one"
            onPicked: i => root.open(root.results[i])
        }

        ListView {
            id: list
            anchors.fill: parent
            anchors.margins: root.bodyPad
            visible: root.hasResults && !root.isEmoji && !root.quickOpen && !root.chatting && !root.helpOpen
            clip: true
            spacing: Tokens.spacingXs
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds

            // Keyed by id: typing more letters keeps the rows that still match, so
            // their hover and entrance state survive instead of every row rebuilding.
            model: ScriptModel { values: root.results; objectProp: "id" }

            onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

            // ── The selection: one plate that glides ──────────────────────────
            // It sits behind the rows, follows the selected row's place on a spring (so it also
            // follows when the list re-flows under it), and stretches a little at speed.
            SpringValue {
                id: plateY
                spec: Motion.springSpatial
                target: list.currentItem ? list.currentItem.y + list.currentItem.rowTop : 0
            }
            highlightFollowsCurrentItem: false
            highlight: Rectangle {
                z: 0
                width: list.width
                readonly property real stretch: Math.min(Tokens.spacingMd, Math.abs(plateY.velocity) / 160)
                y: plateY.value - stretch / 2
                height: root.rowH + stretch
                radius: Tokens.radiusSm
                color: Colors.of(QsWindow.window).primaryContainer
            }

            // Rows that survive a keystroke slide to their new place; new ones lift in
            // by themselves (LauncherRow).
            displaced: Transition {
                NumberAnimation { property: "y"; duration: Motion.standard
                                  easing.type: Motion.travel }
            }

            // A cell is a row, plus its group's header when it opens one. The header is part
            // of the cell (not a ListView section) so the plate's place is plain arithmetic.
            delegate: Item {
                id: cell
                required property var modelData
                required property int index
                readonly property int rowTop: cell.modelData.groupFirst ? root.headerH : 0
                z: 1
                width: list.width
                height: cell.rowTop + root.rowH

                StyledText {
                    visible: !!cell.modelData.groupFirst
                    x: Tokens.spacingLg
                    height: root.headerH
                    verticalAlignment: Text.AlignVCenter
                    text: cell.modelData.group ?? ""
                    variant: "caption"
                    emphasis: "dim"
                    font.weight: Font.DemiBold
                    opacity: line.appeared
                }
                LauncherRow {
                    id: line
                    y: cell.rowTop
                    width: cell.width
                    height: root.rowH
                    modelData: cell.modelData
                    index: cell.index
                    current: list.currentIndex === cell.index
                    pinned: !!Pins.isPinned(cell.modelData.id)
                    onActivated: root.open(cell.modelData)
                    onPointed: list.currentIndex = cell.index
                    onPinToggled: root.togglePin(cell.modelData)
                    onMenuRequested: { list.currentIndex = cell.index; root.openQuick(cell.modelData) }
                }
            }
        }

        // No app matches. Say so, and offer the two things people do next — as buttons,
        // not as Enter: a launcher that sends your text to a search engine or an AI
        // because nothing matched is guessing, and this one doesn't.
        Column {
            anchors.centerIn: parent
            spacing: Tokens.spacingMd
            visible: root.showEmpty

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.isClip ? (root.text !== "" ? "Nothing copied matches “" + root.text + "”"
                                                      : Clipboard.ready ? "Nothing copied yet" : "Loading…")
                    : !root.isPkg ? "Nothing matches “" + root.text + "”"
                    : Packages.blocker() !== "" ? Packages.blocker()
                    : Packages.busy ? "Searching…"
                    : Packages.error !== "" ? Packages.error
                    : "No package matches “" + root.text + "”"
                variant: "body"
                emphasis: "dim"
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Tokens.spacingMd
                visible: !root.isPkg && !root.isClip

                PanelButton {
                    label: "Search " + Config.webSearchName
                    symbol: "language"
                    onActivated: root.openInBrowser()
                }
                PanelButton {
                    visible: Ai.blocker() === ""
                    label: "Ask " + Ai.label
                    symbol: "auto_awesome"
                    onActivated: root.askAi()
                }
            }
        }
    }
}
