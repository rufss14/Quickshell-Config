import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/switcher.js" as SwitchJs
import "../hud"

// ── Overview ──────────────────────────────────────────────────────────────────
// Your workspaces over a lightly dimmed desktop — with window search, Alt+Tab and a window
// inspector working inside them.
//
//     ╭──────────────────────────────────────────────────────────────────────────╮
//     │  ✿        ╭─ Clips ────────╮  (✿) Your workspaces  (󰌾󰍃󰜉󰐥)  ╭─ Voice ───────╮   │
//     │     ✿     │ ▮▮▮▯ ─ now    │      9 windows on 4 workspaces   │ ◉ ◉ ◉   Mic  │   │
//     │           ╰────────────────╯  [ 󰍉 Search 9 windows       ]  ╰───────────────╯   │
//     │           ╭─────────────────────────────────────────────────────────────╮  ✿  │
//     │    ✿      │   ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐     the workspaces, in       │     │
//     │           │   └───┘ └───┘ └───┘ └───┘ └───┘     one card, dead centre    │     │
//     │           ╰─────────────────────────────────────────────────────────────╯     │
//     │           ╭─ Performance ──╮ ╭ 󰕾 ━━●── │ 󰃠 ━━━●─ ╮ ╭─ Input ───────╮  ✿     │
//     │      ✿    ╰────────────────╯ ╰── the island ─────╯ ╰───────────────╯         │
//     ╰──────────────────────────────────────────────────────────────────────────╯
//                    (✿ = the cookie field, drifting across all of it)
//
// ── The HUD in the corners (2026-10-20) ───────────────────────────────────────
// The HUD's cards (modules/hud — each usable here and pinnable on screen) frame the
// workspaces, so the grid stays in the middle of the screen (the user's call; a rail beside
// the grid pushed it off centre): Clips and Voice in the top corners with the header
// between them, Performance and Input in the bottom ones with the island between them. Every card
// is ONE fixed height (HudCard.bodyHeight), so the grid's room never depends on the cards'
// widths, which follow the grid. Below, the cards give way to the island as it springs wider
// (a picked window's inspector) — on a 1920 screen they never need to. A card's move chip
// ARRANGES the HUD (Hud.arranging): this whole stage fades out, the dim lifts, and
// HudArrange draws the widgets at their real places to drag.
//
// ── The cookie field, everywhere (2026-10-20) ─────────────────────────────────
// One full-screen window onto the shared field (DriftShapes) sits on the dim, behind every
// card; each card draws its own window onto the SAME field, so a cookie crossing from the
// open dim into a card is the same cookie on both sides.
//
// ── The redesign (2026-10-17): the panels' look ───────────────────────────────
// The wallpaper, colour and now-playing panels' language, at full-screen size (Caelestia's
// dashboard is the reference for a bento of rounded tiles; every line is this shell's):
//   · a PanelHeader — the cookie chip, a title with its accent word, a live subtitle — with the
//     search pill and the power tray as its actions;
//   · the workspaces in ONE container card with the shared cookie field drifting behind them
//     (DriftShapes), the cells a little see-through like section cards, so an empty workspace
//     shows the field going by;
//   · the bottom island (OverviewIsland) is volume and brightness until a window is picked, and
//     then springs into that window's INSPECTOR (WindowInspector): a live preview, what it is,
//     float / pin / fullscreen / centre, send it to a workspace, close it (twice).
// Motion: the stage arrives out of a slight zoom; the header drops in, the island rises, the
// grid ripples out from the workspace you are on; a moved window rings the cell it lands in;
// the focused workspace wears its number on a slowly winding cookie.
//
// ── Motion, the second pass (2026-10-20) ──────────────────────────────────────
// The user: "more cool and smooth animations across the whole overview, at the same quality
// as the rest of the shell". What moves, in order of appearance:
//   · the cookie field SWELLS into place with the dim (its shapes grow from 0.85 — the
//     field's positions stay put, DriftShapes maps through the scale);
//   · the top strip drops in and the bottom one rises a beat later; each HUD card flies in
//     from ITS OWN CORNER (diagonally, on top of its PopIn spring), so the four close in on
//     the grid; the grid's cells ripple out from where you are and their windows follow them,
//     a beat behind (WorkspaceGrid);
//   · leaving plays the same moves backwards, fast (`exit`), where it used to cut the strips
//     out in one frame and fade only the grid;
//   · under the pointer: the cards lean toward it with a light on the edge facing it
//     (HudCard), and the whole cookie field glides a little AGAINST it — a parallax, the
//     field behind, the cards in front (UiState.overviewDrift, read by every DriftShapes here);
//   · rest on a workspace and its peek card hangs off it (WorkspaceGrid), the grid lifted over
//     its neighbours while it does.
//
// ── No canvas ─────────────────────────────────────────────────────────────────
// No frame band, strips or tinted well (the user's call, 2026-10-04): the islands stand on
// an even dim. Hyprland's blur stays on for this surface but with `ignore_alpha`
// (hypr/rules.lua), so it frosts only what's behind the cards. Keep `dimAlpha` below that
// threshold, or the whole screen blurs.
//
// ── What's here ───────────────────────────────────────────────────────────────
//   · Search: type and the grid fades every window that doesn't match, across every
//     workspace, and picks the best; Enter goes there. Focus stays in the field; the keys it
//     doesn't need (← →, Tab, digits on an empty field, Ctrl+…) are taken first.
//   · Workspaces (WorkspaceGrid): drag windows between them, click to go. Alt+Tab
//     (services/Switcher) lifts, rings and labels its pick here, turning to its page.
//     Right-click a window to pick it (again to let it go). Don't add a second LIST of the
//     same windows — one was built and dropped (2026-10-04, "the same feature").
//   · The pick's inspector, and its keys: Ctrl+F float, Ctrl+P pin, Ctrl+Enter fullscreen,
//     Ctrl+W close (twice), Ctrl+1…0 send it to that workspace of the page.
//   · Power: PowerPanel, two-step as ever.
//
// Nothing here exists while it's closed: the window is unmapped, Hypr's refresh is
// released, and the live window captures are torn down.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: root

    // `screen` is PanelWindow's own property, assigned by shell.qml — never
    // redeclared (a redeclared `screen` shadows it and the surface never learns its
    // output).

    readonly property var hyprMonitor: Hypr.monitorFor(root.screen)
    readonly property bool monitorFocused: Hyprland.focusedMonitor?.name === hyprMonitor?.name

    // Only the focused monitor shows the overview — mirroring it onto every screen
    // would mean several of them fighting over one keyboard focus.
    readonly property bool shown: UiState.overviewOpen && root.monitorFocused

    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "quickshell-overview"
    WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive
                                            : WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: -1

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    color: "transparent"
    visible: root.shown || (scrim.opacity > 0.005 && !root.landed)

    // ── Lending the screen (a clip dragged out, HudClipsCard) ─────────────────
    // An EMPTY mask makes the window transparent for input (proxywindow.cpp), so the drop
    // lands on the window beneath; the dim and the stage fade so you can see where.
    readonly property bool lending: UiState.overviewLending && root.shown
    mask: root.lending ? lendMask : null
    Region { id: lendMask }

    // Margin from the screen's edge to everything on it.
    readonly property int edge: Tokens.spacingXxl * 2
    // The dim's strength. Must stay under the layer rule's ignore_alpha (0.6, in
    // hypr/rules.lua) — see the header. Arranging the HUD (HudArrange) lifts it most of the
    // way: the point there is to see the desktop the widgets will sit on.
    readonly property real dimAlpha: 0.5
    readonly property real arrangeDim: 0.12

    // ── Live-data lifecycle ───────────────────────────────────────────────────
    // Hypr only refreshes window geometry while something holds a reference.
    // Refcounted, so this is a no-op when another surface already holds it.
    property bool _held: false
    function _sync() {
        if (root.shown === root._held) return
        if (root.shown) Hypr.acquire()
        else Hypr.release()
        root._held = root.shown
    }
    onShownChanged: {
        root._sync()
        if (root.shown) {
            root.ops = []
            search.clear()
            Qt.callLater(() => search.forceFocus())
            // The workspace you're on shrinks into its cell (OverviewZoom "in"), once the
            // grid has laid out.
            // Nothing shows until the captures have a frame (`revealed`): the workspace you're on
            // then shrinks into its cell from exactly where it is (OverviewZoom "in").
            root.revealed = false
            root.landed = false
            // Each opening starts a fresh run of moves to undo.
            Hypr.forgetMoves()
            if (Config.motionEnabled) {
                revealLatest.restart()
                Qt.callLater(() => { if (root.shown) zoom.start("in", Hypr.focusedWorkspaceId) })
            } else root.revealed = true
        } else {
            root.revealed = false
            revealLatest.stop()
            zoom.stop()
            UiState.overviewLeaveTo = -1
            root.bigAddress = ""
            root.sessionsOpen = false
            mods.helpOpen = false
            grid.showAll = false
            root.ctrlOn = false
            root.shiftDown = false
            root.ctrlDown = false
        }
    }

    // ── Leaving into a workspace (UiState.leaveOverview → OverviewZoom "out") ──
    // The stage fades over the first half of the flight (the neighbours go with the growing
    // cell); the dim HOLDS to the end, hiding the workspace slide going on under it, and the
    // overview then closes on the landed frame (`landed`), which Hyprland fades out.
    // A workspace living on ANOTHER monitor (Alt+Tab to a window over there) just closes:
    // the flight would land on the wrong screen.
    readonly property bool leaving: zoom.mode === "out" || root.landed
    // A leave's flight has finished and the overview is closing on its LAST FULL FRAME (stand-ins
    // landed, dim up): nothing in the shell fades it. Hyprland's layer fade-out does — the one
    // thing that can take the compositor's blur away gradually, since blur follows the layer's
    // alpha. Blanking the overlay first (what this did until 2026-10-24) dropped the blur, and
    // the dim, in a single frame: the flash on arriving.
    property bool landed: false
    // ── Revealed ──────────────────────────────────────────────────────────────
    // The overview's visuals (the dim, the field, the stage, the cards' entrances, the grid's
    // ripple) wait on THIS, not on `shown`: it goes true when the opening zoom's stand-ins
    // have their first frames (OverviewZoom `ready`), so the first thing on screen is the
    // windows exactly where they were, not a dim over blank boxes that then fill in. Never
    // later than `revealLatest`, whatever the captures do.
    property bool revealed: false
    Timer { id: revealLatest; interval: 220; onTriggered: root.revealed = root.shown }
    // The Sessions card (the header's Sessions chip) is open.
    property bool sessionsOpen: false
    // The window Space is holding up big ("" = none).
    property string bigAddress: ""
    // ── Shift and Ctrl: toggles (2026-10-24) ──────────────────────────────────
    // TAP either (a press and release with nothing between) or click its chip (OverviewModifiers):
    // Shift opens the grid to all ten and makes a click on a cell SEND your window there; Ctrl makes a
    // click on a window SELECT it and a drag SWAP. Held, they work as they always did, so what the
    // chips show is `toggled || held`. A Shift or Ctrl that was for a click (grid `modUsed`) or came
    // with another key (a capital letter, Ctrl+A) is not a tap. Shift only counts on an empty field.
    property bool shiftDown: false
    property bool ctrlDown: false
    property bool ctrlOn: false
    property bool _shiftTap: false
    property bool _ctrlTap: false
    // Typing in a field that isn't the search (the left face's AI box, OverviewFeed): Shift there
    // is a capital letter, not a tap — the letter's own press is taken by that field and never
    // reaches here to cancel it.
    function _typingElsewhere() {
        const f = stage.Window.activeFocusItem
        return !!f && !search.editing && ("cursorPosition" in f)
    }
    function modPress(event) {
        const k = event.key
        if (k !== Qt.Key_Shift) root._shiftTap = false
        if (k !== Qt.Key_Control) root._ctrlTap = false
        if (event.isAutoRepeat || root._typingElsewhere()) return
        if (k === Qt.Key_Shift) { root.shiftDown = true; root._shiftTap = search.text === "" }
        else if (k === Qt.Key_Control) { root.ctrlDown = true; root._ctrlTap = true }
    }
    function modRelease(event) {
        if (event.isAutoRepeat) return
        if (event.key === Qt.Key_Shift) {
            root.shiftDown = false
            if (root._shiftTap) grid.showAll = !grid.showAll
            root._shiftTap = false
        } else if (event.key === Qt.Key_Control) {
            root.ctrlDown = false
            if (root._ctrlTap) root.ctrlOn = !root.ctrlOn
            root._ctrlTap = false
        }
    }
    Connections { target: grid; function onModUsed() { root._shiftTap = false; root._ctrlTap = false } }
    Connections {
        target: UiState
        function onOverviewLeaveToChanged() {
            const ws = UiState.overviewLeaveTo
            if (ws <= 0 || !root.shown) return
            const there = Hypr.monitorForWorkspace(ws)
            if (there && root.hyprMonitor && there.name !== root.hyprMonitor.name) {
                UiState.overviewLeaveTo = -1
                UiState.overviewOpen = false
                return
            }
            zoom.start("out", ws)
        }
    }
    Component.onCompleted: root._sync()
    Component.onDestruction: if (root._held) Hypr.release()

    Timer {
        id: dbgPage
        property string page: ""
        interval: 450
        onTriggered: {
            const i = island.inspector
            if (!i) return
            i.moreOpen = page === "more"
            i.spaceOpen = page === "space"
        }
    }
    // ── Debug driver: scripts/overview-shots.sh ───────────────────────────────
    // `qs ipc -c … call overviewdebug go <state> [arg]` puts the OPEN overview in a named state, so
    // every face can be photographed (and reviewed) without driving the pointer. It only touches this
    // overview's own view state and the Switcher's pick / marks / query: it never moves, closes or
    // sends a window. Only the focused monitor's overview answers (one handler per screen would clash).
    IpcHandler {
        target: "overviewdebug"
        enabled: root.monitorFocused

        function go(name: string, arg: string): string {
            if (!root.shown) return "overview is not open"
            // Every state starts from rest.
            root.sessionsOpen = false
            mods.helpOpen = false
            grid.showAll = false
            root.ctrlOn = false
            grid.peekWs = -1
            root.clearQuery()
            Switcher.clearMarks()
            Switcher.select(-1)
            switch (name) {
            case "idle": break
            // The "More" fold (Config.overviewMore, kept): the rig restores what it found.
            // The Key display's keyboard preset, shown in the island's Keys page (the rig puts back what it found).
            case "keys": Hud.setOpt("input", "layout", arg); Hud.inspect("input"); break
            case "keysoff": Hud.inspect(""); break
            case "calm": Config.overviewMore = false; break
            case "full": Config.overviewMore = true; break
            case "search": search.setText(arg); root.edited(arg); break
            case "pick": Switcher.select(0); break
            // The inspector's other pages: pick, then turn it once it has loaded (a beat later).
            case "more": Switcher.select(0); dbgPage.page = "more"; dbgPage.restart(); break
            case "space": Switcher.select(0); dbgPage.page = "space"; dbgPage.restart(); break
            case "bulk": Switcher.markAll(Hypr.focusedWorkspaceId); break
            case "all": grid.showAll = true; break
            case "ctrl": root.ctrlOn = true; break
            case "sessions": root.sessionsOpen = true; break
            case "help": mods.helpOpen = true; break
            case "feed": grid.feedPage(parseInt(arg) || 0); break
            case "peek": grid.peekWs = parseInt(arg) || Hypr.focusedWorkspaceId; break
            default: return "unknown state: " + name
            }
            return "ok " + name
        }
        function status(): string {
            return "shown=" + root.shown + " feed=" + Config.overviewFeedPage + " windows=" + Switcher.windows.length
                 + " ws=" + Hypr.focusedWorkspaceId + " more=" + Config.overviewMore + " keys=" + Hud.layout.widgets.input.opts.layout + " marks=" + Switcher.marks.length + " pick=" + Switcher.index
        }
    }

    // Sends the last move's windows back and rings the cells they return to (Hypr.undoMove).
    function undoMove() {
        for (const ws of Hypr.undoMove()) grid.land(ws)
    }

    // ── The search's operator chips ───────────────────────────────────────────
    // `ws:2`, `app:kitty`, `is:floating` are chips INSIDE the field once complete (typed with a space after, or from the
    // filter chips below it), so the field holds only what you are still typing. Switcher gets them all as one query
    // (it parses operators out of a string, services/switcher.js). Backspace in an empty field takes the last one off;
    // Escape clears the text, then the chips.
    property var ops: []
    function applyQuery(text) {
        Switcher.setQuery(root.ops.concat([(text || "").trim()]).filter(w => w !== "").join(" "))
    }
    function edited(value) {
        const s = SwitchJs.splitOps(value)
        if (s.ops.length > 0) {
            root.ops = root.ops.concat(s.ops.filter(o => root.ops.indexOf(o) < 0))
            search.setText(s.rest)
            root.applyQuery(s.rest)
        } else root.applyQuery(value)
    }
    function removeOp(op) {
        root.ops = root.ops.filter(o => o !== op)
        root.applyQuery(search.text)
    }
    // A filter chip: on → off, off → on; one typed by hand into the field's text is taken out of it instead.
    function toggleOp(flag) {
        const op = "is:" + flag
        if (root.ops.indexOf(op) >= 0) root.removeOp(op)
        else if (Switcher.flagOn(flag)) {
            const t = Switcher.withFlag(search.text, flag)
            search.setText(t)
            root.applyQuery(t)
        } else {
            root.ops = root.ops.concat([op])
            root.applyQuery(search.text)
        }
        search.forceFocus()
    }
    function clearQuery() {
        root.ops = []
        search.setText("")
        Switcher.setQuery("")
    }

    // ── Keys the search field doesn't need ────────────────────────────────────
    // Offered by the field before it acts (InputField.keyPressed), so typing always
    // lands in the search while these still steer.
    function steer(event) {
        const empty = search.text === ""
        const k = event.key
        root.modPress(event)
        // Ctrl+… acts on the pick through the inspector (WindowInspector), before the field
        // sees the key — Ctrl+W must not delete a word of the search.
        // Ctrl+M: the "More" fold (the extra panels), same as its chip.
        if ((event.modifiers & Qt.ControlModifier) && k === Qt.Key_M) {
            Config.overviewMore = !Config.overviewMore
            event.accepted = true
            return
        }
        // Ctrl+Z: undo the last move (before the field: it would undo its own text).
        if ((event.modifiers & Qt.ControlModifier) && k === Qt.Key_Z && Hypr.canUndoMove) {
            root.undoMove()
            event.accepted = true
            return
        }
        // Ctrl+A: every window the search shows (or, with nothing typed, the workspace you are on);
        // again to let them go. Taken before the field, which would select its own text.
        if ((event.modifiers & Qt.ControlModifier) && k === Qt.Key_A) {
            Switcher.markAll(Hypr.focusedWorkspaceId)
            event.accepted = true
            return
        }
        // A selection (Ctrl+click, Ctrl+A): the same keys act on all of it, through the bulk face.
        const bulk = island.bulk
        if ((event.modifiers & Qt.ControlModifier) && bulk && Switcher.marked.length > 0) {
            if (k === Qt.Key_F)                                 bulk.floatAll()
            else if (k === Qt.Key_P)                            bulk.pinAll()
            else if (k === Qt.Key_W)                            bulk.requestClose()
            else if (k >= Qt.Key_0 && k <= Qt.Key_9)            bulk.sendAll(grid.firstWorkspace + (k === Qt.Key_0 ? 9 : k - Qt.Key_1))
            else return
            event.accepted = true
            return
        }
        const insp = island.inspector
        if ((event.modifiers & Qt.ControlModifier) && insp && Switcher.picked) {
            if (k === Qt.Key_F)                                 insp.toggleFloat()
            else if (k === Qt.Key_P)                            insp.togglePin()
            else if (k === Qt.Key_Return || k === Qt.Key_Enter) insp.toggleFullscreen()
            else if (k === Qt.Key_W)                            insp.requestClose()
            else if (k >= Qt.Key_0 && k <= Qt.Key_9)            insp.moveTo(grid.firstWorkspace + (k === Qt.Key_0 ? 9 : k - Qt.Key_1))
            else return
            event.accepted = true
            return
        }
        // Space, held, on an empty field: the pick (or the window you were in) BIG and live,
        // until it's let go (`bigAddress`; the release is the stage's). Its repeats are eaten
        // too, so a held Space doesn't type into the search.
        if (empty && k === Qt.Key_Space) {
            if (!event.isAutoRepeat)
                root.bigAddress = Switcher.selectedAddress || Hypr.addr(Hyprland.activeToplevel?.address ?? "")
            event.accepted = true
            return
        }
        if (k === Qt.Key_Backspace && empty && root.ops.length > 0 && !(event.modifiers & Qt.ControlModifier)) {
            root.removeOp(root.ops[root.ops.length - 1])
            event.accepted = true
        } else if (k === Qt.Key_Escape && !empty) {
            search.clear()
            event.accepted = true
        } else if (k === Qt.Key_Escape && root.ops.length > 0) {
            root.clearQuery()
            event.accepted = true
        } else if (k === Qt.Key_Escape && Switcher.index >= 0 && !Switcher.active) {
            Switcher.select(-1)
            event.accepted = true
        } else if (k === Qt.Key_Tab || (!empty && k === Qt.Key_Down)) {
            Switcher.stepBy(1)
            event.accepted = true
        } else if (k === Qt.Key_Backtab || (!empty && k === Qt.Key_Up)) {
            Switcher.stepBy(-1)
            event.accepted = true
        } else if (empty && (k === Qt.Key_Left || k === Qt.Key_Right || k === Qt.Key_Up || k === Qt.Key_Down)) {
            // The arrows move ON THE GRID — to the window that way from the pick (or from
            // the one you were in), where Tab walks the recent order.
            const from = Switcher.selectedAddress || Hypr.addr(Hyprland.activeToplevel?.address ?? "")
            const a = grid.spatialFrom(from,
                                       k === Qt.Key_Left ? -1 : k === Qt.Key_Right ? 1 : 0,
                                       k === Qt.Key_Up ? -1 : k === Qt.Key_Down ? 1 : 0)
            const i = a !== "" ? Switcher.list.findIndex(w => w.address === a) : -1
            if (i >= 0) Switcher.select(i)
            event.accepted = true
        } else if (empty && k >= Qt.Key_0 && k <= Qt.Key_9 && !(event.modifiers & Qt.AltModifier)) {
            // 1–9, 0 = the tenth: straight to that workspace of the grid's page.
            const n = k === Qt.Key_0 ? 9 : k - Qt.Key_1
            Hypr.focusWorkspace(grid.firstWorkspace + n, true, root.hyprMonitor)
            UiState.leaveOverview(grid.firstWorkspace + n)
            event.accepted = true
        }
    }

    // ── The dim ───────────────────────────────────────────────────────────────
    Rectangle {
        id: scrim
        anchors.fill: parent
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, Hud.arranging ? root.arrangeDim : root.dimAlpha)
        Behavior on color { ColorAnimation { duration: Motion.standard } }
        // Up once the overview is REVEALED (the captures have a frame — see `revealed`), and HELD
        // through a leave's whole flight: the compositor's workspace slide is going on underneath,
        // and a dim that thinned out earlier showed the real windows sliding in. It is never
        // faded out here after a leave: the overview closes on it (`landed`) and Hyprland's
        // layer fade takes the dim, the blur and the stand-ins away together.
        opacity: !root.revealed || root.lending ? 0 : 1
        visible: opacity > 0.005 || root.shown
        Behavior on opacity {
            enabled: !root.leaving
            NumberAnimation {
                duration: Motion.surfaceDuration(root.revealed && !root.lending)
                easing.type: Motion.surfaceEasing(root.revealed && !root.lending)
            }
        }
        // Swallows clicks WITHOUT dismissing: a click that misses a control (a
        // slider released off its track) must not close the overview. Escape does.
        MouseArea { anchors.fill: parent }
    }

    // ── The cookie field, over the whole screen ───────────────────────────────
    // The same field (services/Drift) every card here is a window onto — the grid's card,
    // the island, the HUD cards — so a cookie drifting across the open dim carries on into
    // the card it reaches instead of appearing at its edge. Plain rectangle, no mask (a
    // clip, not an offscreen layer). Gone while arranging: it would sit over the desktop
    // you're placing against.
    Item {
        id: cookieField
        anchors.fill: parent
        opacity: scrim.opacity * (Hud.arranging ? 0 : 1)
        // Not while leaving: it goes with the scrim, and a lag on top would leave the field up
        // over the real desktop when the window closes.
        Behavior on opacity { enabled: !root.leaving; NumberAnimation { duration: Motion.standard } }
        // Swells into place as the dim comes up (see the header's Motion).
        scale: root.revealed ? 1 : 0.85
        Behavior on scale {
            NumberAnimation {
                duration: root.revealed ? Motion.emphasized : Motion.exit
                easing.type: root.revealed ? Easing.BezierSpline : Motion.exitCurve
                easing.bezierCurve: Motion.spring
            }
        }
        DriftShapes {
            anchors.fill: parent
            visible: root.visible && cookieField.opacity > 0.01
            radius: 0
            fade: 0
            seam: false
            shift: UiState.overviewDrift
        }
    }

    // ── The parallax ──────────────────────────────────────────────────────────
    // The pointer's place on the screen, -1..1 from its centre, eased slowly (the field is
    // far away: it follows the hand lazily, where the cards lean at once), shifts the whole
    // field up to `reach` px the other way. Every DriftShapes in the overview takes the same
    // shift (UiState.overviewDrift), so a cookie crossing into a card stays one cookie.
    // Motion off, or the pointer off the overview: no shift.
    HoverHandler { id: pointer; enabled: root.shown }
    readonly property real reach: Config.motionEnabled ? Tokens.spacingXl : 0
    property real driftX: pointer.hovered && root.width > 0 ? -(pointer.point.position.x / root.width - 0.5) * 2 * root.reach : 0
    property real driftY: pointer.hovered && root.height > 0 ? -(pointer.point.position.y / root.height - 0.5) * 2 * root.reach : 0
    Behavior on driftX { NumberAnimation { duration: Motion.glide; easing.type: Motion.travel } }
    Behavior on driftY { NumberAnimation { duration: Motion.glide; easing.type: Motion.travel } }
    Binding {
        target: UiState
        property: "overviewDrift"
        value: Qt.point(root.driftX, root.driftY)
        when: root.shown
    }

    // ── Everything on it ──────────────────────────────────────────────────────
    // Enters out of a slight zoom, centre-anchored and small (0.96): a whole screen
    // arriving reads as in front of you, where a fade reads as a picture turned up.
    // Leaves fast and accelerating — you've decided you're done.
    Item {
        id: stage
        anchors.fill: parent
        anchors.margins: root.edge

        // The ancestor of everything with focus, so Escape (which a TextInput
        // doesn't take) bubbles here from the search field. Out of the way while the HUD is
        // being arranged (HudArrange has the keyboard and the screen then).
        focus: root.shown
        enabled: !Hud.arranging
        Keys.onReleased: function (event) {
            root.modRelease(event)
            if (event.key === Qt.Key_Space && !event.isAutoRepeat && root.bigAddress !== "") {
                root.bigAddress = ""
                event.accepted = true
            }
        }
        Keys.onPressed: function (event) {
            root.modPress(event)
            if (event.key !== Qt.Key_Escape) return
            if (mods.helpOpen) mods.helpOpen = false
            else if (root.sessionsOpen) { root.sessionsOpen = false; Qt.callLater(() => search.forceFocus()) }
            else if (power.armed !== "") power.armed = ""
            else if (Hud.inspecting !== "") Hud.inspect("")
            else if (Switcher.marks.length > 0) Switcher.clearMarks()
            // Zooms back into where you are (ends an Alt+Tab too, once closed: Switcher).
            else UiState.leaveOverview(Hypr.focusedWorkspaceId)
            event.accepted = true
        }

        opacity: root.revealed && !Hud.arranging && !root.lending && !root.leaving ? 1 : 0
        scale:   root.revealed && !Hud.arranging && !root.lending ? 1 : 0.96
        transformOrigin: Item.Center
        // A leave fades it over the first half of the zoom, so the cell that is growing has
        // the neighbours going with it, not gone before it moves (it used to be 200ms of
        // emphasizedDecel — nearly out in two frames).
        Behavior on opacity {
            NumberAnimation {
                duration: root.leaving ? Math.round(Motion.zoomOut / 2) : root.revealed ? Motion.spatial : Motion.exit
                easing.type: root.leaving ? Motion.ambient : root.revealed ? Easing.BezierSpline : Motion.exitCurve
                easing.bezierCurve: Motion.emphasizedDecel
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: root.revealed ? Motion.spatial : Motion.exit
                easing.type: root.revealed ? Easing.BezierSpline : Motion.exitCurve
                easing.bezierCurve: Motion.emphasizedDecel
            }
        }

        // The top strip drops in and the bottom one rises a beat later, so the edges settle
        // onto the middle rather than all of it at once; the HUD cards fly in from their own
        // corners (`fly`). Leaving runs it backwards, fast and accelerating — it used to cut
        // the strips out in one frame (a 0 duration) and fade only the grid.
        property real arrive: root.revealed ? 0 : 1
        property real arriveLow: root.revealed ? 0 : 1
        Behavior on arrive {
            NumberAnimation {
                duration: root.revealed ? Motion.spatial : Motion.exit
                easing.type: root.revealed ? Easing.BezierSpline : Motion.exitCurve
                easing.bezierCurve: Motion.emphasizedDecel
            }
        }
        Behavior on arriveLow {
            SequentialAnimation {
                PauseAnimation { duration: root.revealed ? Motion.stagger * 4 : 0 }
                NumberAnimation {
                    duration: root.revealed ? Motion.spatial : Motion.exit
                    easing.type: root.revealed ? Easing.BezierSpline : Motion.exitCurve
                    easing.bezierCurve: Motion.emphasizedDecel
                }
            }
        }
        // How far a corner card travels in from its corner.
        readonly property real fly: Tokens.spacingXxl * 1.5

        // ── One composition, centred ──────────────────────────────────────────
        // The workspaces in the middle, framed: a HUD card in each corner (Clips and Voice
        // above, Performance and Input below), the header between the top two and the island between
        // the bottom two (2026-10-20 — the user: the workspaces "keep being on the center"; the
        // header joined the top strip when Performance shrank to a corner card, which left the
        // middle of it free). The island has a fixed slot (the inspector's height), so picking
        // a window grows the island downward and nothing above it moves.
        readonly property int gap: Tokens.spacingXl
        // The inspector's two rows: the window (96) and its tools (a chip's height).
        readonly property int islandSlot: 96 + Tokens.spacingMd + Tokens.fieldHeight + Tokens.spacingLg * 2
        // The HUD strips: one card height (HudCard's, a constant), and the corner cards' width.
        // Below the grid the island needs its slot even if a card is shorter.
        readonly property real stripH: Math.max(clipsCard.item ? clipsCard.item.implicitHeight : 0,
                                                header.implicitHeight + search.height + filters.implicitHeight + Tokens.spacingMd * 2)
        readonly property real bottomH: Math.max(stage.stripH, stage.islandSlot)
        // The middle card's size: the room, always (the grid fills it, whatever's busy).
        readonly property real cardW: Math.max(0, middle.roomW) + middle.pad * 2
        readonly property real cardH: Math.max(0, middle.roomH) + middle.pad * 2
        readonly property real sideW: Math.min(Tokens.sideCardUnit * 11, Math.floor((stage.cardW - stage.gap * 2) / 3))
        readonly property real flankW: Math.max(0, Math.min(stage.sideW, Math.floor((stage.cardW - island.boxWidth) / 2) - stage.gap))
        Item {
            id: group
            anchors.centerIn: parent
            width: stage.cardW
            height: stage.stripH + stage.gap + stage.cardH + stage.gap + stage.bottomH
        }

        // ── The header: what this is, the search, power — top centre ──────────
        // A panel's header (PanelHeader) over the search field, between the top two cards.
        // Wrapped, not faded directly: a Surface's own opacity is its translucency, and an
        // entrance must not overwrite it.
        Item {
            id: topRow
            anchors.top: group.top
            anchors.left: group.left
            anchors.right: group.right
            anchors.leftMargin: stage.sideW + stage.gap * 2
            anchors.rightMargin: stage.sideW + stage.gap * 2
            height: stage.stripH
            opacity: 1 - stage.arrive
            transform: Translate { y: -stage.arrive * Tokens.spacingXl }

            readonly property bool searching: Switcher.query.trim() !== ""

            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Tokens.spacingMd

                PanelHeader {
                    id: header
                    Layout.fillHeight: false
                    // Screen scale: the hero of the strip between the four cards.
                    chipSize: Tokens.iconXl + Tokens.spacingLg
                    titleVariant: "headline"
                    subtitleVariant: "label"
                    symbol: topRow.searching ? "search" : "grid_view"
                    // The chip is an M3E shape and morphs when the search starts (cookie → sunny).
                    morph: topRow.searching ? "sunny" : "cookie9"
                    title: topRow.searching ? "Matching" : "Your"
                    titleTail: topRow.searching ? "windows" : "workspaces"
                    accent: Colors.of(QsWindow.window).primary
                    // Counts and what is picked; the keys have their own row (OverviewHints).
                    subtitle: Switcher.active ? "Let go of Alt to switch  ·  Esc to stay"
                        : topRow.searching
                            ? (Switcher.list.length === 0 ? "No window matches"
                               : Switcher.list.length + (Switcher.list.length === 1 ? " window" : " windows"))
                        : Switcher.marked.length > 0 ? Switcher.marked.length + " selected"
                        : Switcher.picked ? (Switcher.picked.title || Switcher.picked.appName || "")
                        : Hypr.windows.length + (Hypr.windows.length === 1 ? " window" : " windows")

                    // A running timer, reminders due, unseen notifications — only when there are.
                    OverviewChips {
                        Layout.alignment: Qt.AlignVCenter
                        live: root.shown
                        screen: root.screen
                        sessionsOpen: root.sessionsOpen
                        onSessionsAsked: root.sessionsOpen = !root.sessionsOpen
                        onUndoAsked: root.undoMove()
                    }
                    PowerPanel {
                        id: power
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                InputField {
                    id: search
                    Layout.fillWidth: true
                    // A plain field's height, not the power tray's: at the tray's height the
                    // empty pill was the heaviest thing in the strip (2026-10-20).
                    Layout.preferredHeight: Tokens.fieldHeight
                    elevation: Tokens.elevationCard
                    cornerRadius: height / 2
                    // Always focused here, so a full accent frame would be on for the whole life of the overview and
                    // compete with the focused cell: a quiet rim instead, no tracing outline.
                    trace: false
                    border.color: search.focused ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.45)
                                                 : Colors.of(QsWindow.window).outlineFor(search.elevation)
                    icon: "search"
                    // No count: the subtitle above already gives it.
                    placeholder: root.ops.length > 0 ? "" : "Search windows   ·   ws:2   app:kitty   is:floating"
                    leadingSpace: opChips.width > 0 ? opChips.width + Tokens.spacingXs : 0

                    onEdited: value => root.edited(value)
                    onAccepted: {
                        if (Switcher.index >= 0) Switcher.activate(Switcher.index)
                        else if (Switcher.list.length > 0 && Switcher.query.trim() !== "") Switcher.activate(0)
                    }
                    onKeyPressed: event => root.steer(event)

                    // The operators, inside the field, before the text; a click on one takes it off.
                    Row {
                        id: opChips
                        anchors.left: parent.left
                        anchors.leftMargin: Tokens.spacingMd * 2 + Tokens.iconSm
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Tokens.spacingXs
                        Repeater {
                            model: root.ops
                            delegate: Item {
                                id: opChip
                                required property string modelData
                                height: Tokens.iconXl - Tokens.spacingSm
                                width: opRow.implicitWidth + Tokens.spacingMd
                                SpringValue { id: opPop; target: 1; spec: Motion.springSpatialFast; epsilon: 0.002; Component.onCompleted: jump(0.6) }
                                scale: opPop.value
                                Rectangle {
                                    anchors.fill: parent
                                    radius: height / 2
                                    color: opHover.hovered ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).primaryContainer
                                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                                }
                                Row {
                                    id: opRow
                                    anchors.centerIn: parent
                                    spacing: Tokens.spacingXs
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: opChip.modelData
                                        variant: "caption"
                                        font.weight: Font.DemiBold
                                        color: opHover.hovered ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fgOnPrimaryContainer
                                    }
                                    MaterialIcon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: "close"
                                        font.pixelSize: Tokens.iconSm - 2
                                        color: opHover.hovered ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fgOnPrimaryContainer
                                    }
                                }
                                HoverHandler { id: opHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.removeOp(opChip.modelData) }
                            }
                        }
                    }
                }

                // The flag operators as chips (OverviewFilters): `is:floating` typed for you.
                // …and, on the same line, the keys that do something now (OverviewHints).
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingLg
                    OverviewFilters {
                        id: filters
                        Layout.alignment: Qt.AlignVCenter
                        onToggled: flag => root.toggleOp(flag)
                    }
                    OverviewHints {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        mode: Switcher.marked.length > 0 ? "marks" : topRow.searching ? "search" : Switcher.picked ? "pick" : "idle"
                    }
                }
            }
        }

        // ── Sessions: the header chip's card, hanging under the header ────────
        OverviewSessions {
            z: 3
            anchors.top: topRow.bottom
            anchors.topMargin: -Tokens.spacingSm
            anchors.horizontalCenter: topRow.horizontalCenter
            width: Math.min(topRow.width, Tokens.sideCardUnit * 9)
            shown: root.sessionsOpen && root.shown && !root.leaving
        }

        // ── The middle: the workspaces, in one card with the cookie field ─────
        // Alt+Tab and search live IN the grid (Switcher): the pick is lifted, ringed and
        // labelled where it really is, the rest step back.
        Item {
            id: middle
            anchors.fill: parent
            readonly property int pad: Tokens.spacingXl
            // The room the grid may take: the stage, less the two HUD strips.
            readonly property real roomW: middle.width - middle.pad * 2
            readonly property real roomH: middle.height - stage.stripH - stage.bottomH
                                          - stage.gap * 2 - middle.pad * 2
        }

        // ── The HUD above: Clips and Voice, in the top corners ──────────
        // Built while the overview is up (and for its fade out), so its cards sample
        // nothing the rest of the time. Drop in with the header.
        Loader {
            id: clipsCard
            anchors.left: group.left
            anchors.top: group.top
            width: stage.sideW
            active: root.visible && Config.overviewMore
            // NOT asynchronous, unlike the other three: its height is the strips' (stripH),
            // and a card arriving a few frames late would move the whole stage when it did.
            asynchronous: false
            opacity: 1 - stage.arrive
            transform: Translate { x: -stage.arrive * stage.fly; y: -stage.arrive * stage.fly * 0.6 }
            sourceComponent: HudClipsCard { index: 0; running: root.revealed }
        }
        Loader {
            id: voiceCard
            anchors.right: group.right
            anchors.top: group.top
            width: stage.sideW
            active: root.visible && Config.overviewMore
            // Built across frames (incubated), not all on the overview's first one.
            asynchronous: true
            opacity: 1 - stage.arrive
            transform: Translate { x: stage.arrive * stage.fly; y: -stage.arrive * stage.fly * 0.6 }
            sourceComponent: HudVoiceCard { index: 1; running: root.revealed }
        }

        Item {
            id: cardSlot
            anchors.horizontalCenter: group.horizontalCenter
            anchors.top: group.top
            anchors.topMargin: stage.stripH + stage.gap
            width: stage.cardW
            height: stage.cardH
        }

        // ── The middle card: the workspaces (and, beside the busy ones when there's room,
        // the notification centre — WorkspaceGrid `notesOn`) ─────────────────────────────
        Surface {
            id: gridCard
            anchors.fill: cardSlot
            elevation: Tokens.elevationCard
            // The hero: a little denser than the HUD cards around it (they sit back, HudCard).
            itemOpacity: Math.min(1, Tokens.surfaceOpacity * 1.08)
            cornerRadius: Tokens.radiusXl + Tokens.spacingXs
            // Over its neighbours while a workspace's peek card overhangs them.
            z: grid.peeking ? 1 : 0
            // Arrives on a spring out of 0.94, a beat after the stage.
            scale: root.revealed ? 1 : 0.94
            Behavior on scale {
                NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring }
            }

            DriftShapes {
                anchors.fill: parent
                visible: root.shown
                radius: gridCard.radius
                fade: 0
                seam: false
                shift: UiState.overviewDrift
            }

            WorkspaceGrid {
                id: grid
                anchors.centerIn: parent
                ctrlOn: root.ctrlOn
                monitor: root.hyprMonitor
                active:  root.revealed
                pickedAddress: Switcher.selectedAddress
                pickedWorkspace: Switcher.picked?.workspaceId ?? -1
                matching: {
                    if (Switcher.query.trim() === "") return null
                    const m = {}
                    for (const w of Switcher.list) m[w.address] = true
                    return m
                }
                maxWidth:  Math.max(0, middle.roomW)
                // Folded (no side faces), the cells still clear the watermark / Shift-Ctrl row on top.
                maxHeight: Math.max(0, middle.roomH - (Config.overviewMore ? 0 : grid.sideTop))
                anchors.verticalCenterOffset: Config.overviewMore ? 0 : grid.sideTop / 2
                // The watermark (top left) and Shift/Ctrl (top right) share the top row; the faces
                // start under it and run to the bottom.
                sideTop: Math.max(watermark.height, mods.height) + Tokens.spacingMd
                sideBottom: 0
            }

            // ── Shift and Ctrl, top right (OverviewModifiers) ──────────────────
            OverviewModifiers {
                id: mods
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: middle.pad
                shiftOn: grid.showAll || root.shiftDown
                ctrlOn: root.ctrlOn || root.ctrlDown
                onShiftClicked: grid.showAll = !grid.showAll
                onCtrlClicked: root.ctrlOn = !root.ctrlOn
            }

            // ── Watermark: the middle card's top left, beside workspace 1 ─────
            // Inside the card, not the window's corner: it arrives, scales and fades with
            // the card, and sits in the room the grid leaves on the left (the user's
            // placement, from a screenshot). Built only while the overview is up. Always
            // on — there is no switch for it.
            Loader {
                id: watermark
                anchors.left: parent.left
                anchors.top:  parent.top
                anchors.margins: middle.pad
                active: root.visible
                sourceComponent: Watermark { active: root.shown }
            }
        }


        // ── The HUD below: Performance and Input, either side of the island ─────────
        // Rise with the island. Their width gives way to the island's as it springs.
        Loader {
            id: perfCard
            anchors.left: cardSlot.left
            anchors.top: cardSlot.bottom
            anchors.topMargin: stage.gap
            width: stage.flankW
            active: root.visible && Config.overviewMore
            // Built across frames (incubated), not all on the overview's first one.
            asynchronous: true
            opacity: 1 - stage.arriveLow
            transform: Translate { x: -stage.arriveLow * stage.fly; y: stage.arriveLow * stage.fly * 0.6 }
            sourceComponent: HudPerfCard { index: 2; running: root.revealed }
        }
        Loader {
            id: inputCard
            anchors.right: cardSlot.right
            anchors.top: cardSlot.bottom
            anchors.topMargin: stage.gap
            width: stage.flankW
            active: root.visible && Config.overviewMore
            // Built across frames (incubated), not all on the overview's first one.
            asynchronous: true
            opacity: 1 - stage.arriveLow
            transform: Translate { x: stage.arriveLow * stage.fly; y: stage.arriveLow * stage.fly * 0.6 }
            sourceComponent: HudInputCard { index: 3; running: root.revealed }
        }

        // ── The island — bottom centre: controls, or the picked window ────────
        Item {
            id: bottomRow
            anchors.horizontalCenter: cardSlot.horizontalCenter
            anchors.top: cardSlot.bottom
            anchors.topMargin: stage.gap
            width: island.implicitWidth
            height: island.implicitHeight
            opacity: 1 - stage.arriveLow
            transform: Translate { y: stage.arriveLow * Tokens.spacingXl * 1.5 }

            OverviewIsland {
                id: island
                anchors.fill: parent
                shown: root.revealed
                picked: Switcher.picked
                marks: Switcher.marked
                hudId: Hud.inspecting
                screenW: root.width
                screenH: root.height
                screenName: root.hyprMonitor?.name ?? ""
                firstWorkspace: grid.firstWorkspace
                // As tall as the corner cards beside it, so the three share one bottom edge.
                minH: perfCard.item ? perfCard.item.implicitHeight : 0
                onMoved: ws => grid.land(ws)
            }
        }
    }

    // ── Space: the window, big ────────────────────────────────────────────────
    // Read it without going there: ~62% of the screen, live, its title under it, over a
    // deeper dim. A copy is held for the fade out (the surface keeps what it shows).
    Item {
        id: big
        anchors.fill: parent
        readonly property var w: root.bigAddress !== "" ? (Hypr.windows.find(x => x.address === root.bigAddress) ?? null) : null
        property var held: null
        onWChanged: if (big.w) big.held = big.w
        readonly property bool on: big.w !== null
        readonly property real aspect: big.held && big.held.size[1] > 0 ? big.held.size[0] / big.held.size[1] : 16 / 9
        readonly property real shotW: Math.min(big.width * 0.62, big.height * 0.62 * big.aspect)
        visible: big.opacity > 0.01
        opacity: big.on ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: big.on ? Motion.standard : Motion.fast } }

        Rectangle {
            anchors.fill: parent
            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.45)
        }
        Surface {
            anchors.centerIn: parent
            width: big.shotW + Tokens.spacingLg * 2
            height: bigCol.implicitHeight + Tokens.spacingLg * 2
            elevation: Tokens.elevationPopup
            cornerRadius: Tokens.radiusXl
            scale: big.on ? 1 : 0.92
            Behavior on scale { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring } }

            Column {
                id: bigCol
                x: Tokens.spacingLg
                y: Tokens.spacingLg
                spacing: Tokens.spacingMd
                ClippingRectangle {
                    width: big.shotW
                    height: Math.round(big.shotW / big.aspect)
                    radius: Tokens.radiusCard
                    color: Colors.of(QsWindow.window).surfaceContainer
                    SharpCapture {
                        anchors.fill: parent
                        captureSource: big.visible && big.held ? big.held.wayland : null
                        live: big.visible
                    }
                }
                Row {
                    spacing: Tokens.spacingSm
                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        readonly property string path: big.held ? Icons.pathForAppId(big.held.appClass ?? "") : ""
                        visible: path !== ""
                        source: path
                        width: Tokens.iconMd
                        height: Tokens.iconMd
                        sourceSize: Qt.size(Tokens.iconMd, Tokens.iconMd)
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, big.shotW - Tokens.iconMd * 4)
                        text: big.held ? (big.held.title || big.held.appClass || "") : ""
                        variant: "body"
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Translation.tr("let go of Space to come back")
                        variant: "caption"
                        emphasis: "dim"
                    }
                }
            }
        }
    }

    // ── The zoom in and out of a workspace (OverviewZoom) ─────────────────────
    OverviewZoom {
        id: zoom
        anchors.fill: parent
        grid: grid
        onReady: root.revealed = root.shown
        onFinished: function (mode) {
            if (mode === "out") {
                root.landed = true
                UiState.overviewLeaveTo = -1
                UiState.overviewOpen = false
            }
        }
    }

    // ── Arranging the HUD on the real screen (modules/hud/HudArrange) ─────────
    // Full-screen, so its coordinates are the screen's — what a widget's place is a fraction
    // of. Built only while arranging; the keyboard goes back to the search when it's done.
    Loader {
        id: arrange
        anchors.fill: parent
        active: Hud.arranging && root.shown
        opacity: active ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
        sourceComponent: HudArrange { screenName: root.hyprMonitor?.name ?? "" }
    }
    Connections {
        target: Hud
        // A HUD pick and a selection are two ways of choosing, and the island shows one.
        function onInspectingChanged() { if (Hud.inspecting !== "") Switcher.clearMarks() }
        function onArrangingChanged() { if (!Hud.arranging && root.shown) Qt.callLater(() => search.forceFocus()) }
    }

    // ── The wave (components/Infection.qml) ───────────────────────────────────
    // An open overview takes a wallpaper/colour change on the same front as the rest
    // of the shell. Full-screen, so its coordinates are the screen's.
    Infection {
        host: root.contentItem
        screen: root.screen
        hostVisible: root.visible
    }
}
