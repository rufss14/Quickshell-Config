pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "../config"
import "../services"

// ── UiState ───────────────────────────────────────────────────────────────────
// The single answer to "what is the shell currently showing".
//
// This state used to live in three places: `barShape`/`barMode` were per-screen
// PersistentProperties inside StatusBarRoot — a *global* preference stored once
// per monitor, so two monitors could disagree — and every panel's open/closed flag
// lived in a `Panels` singleton buried in overlay/modules/.
//
// It is all here now, and nowhere else.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ══ Panels ════════════════════════════════════════════════════════════════
    // Which screen owns the currently-open panels. Panels render only on this
    // screen; null means "all screens" (an IPC/keybind invocation has no screen
    // context to attribute).
    property var activeScreen: null

    // ── Left / right / centre columns ─────────────────────────────────────────
    // Each column holds AT MOST ONE panel key — that's the mutual exclusion, for
    // free, unlike the old per-panel booleans (wallpaperOpen/colorSchemeOpen/…)
    // which needed every sibling in a group cleared by hand whenever one opened.
    //
    // A panel key is no longer welded to one column either: Config.panelSide(name)
    // says which one it opens in — default the side its bar button already sits
    // on — and Settings → Bar → Panel placement can move it, including into the
    // centre slot the update/launcher panels already share (they still win the
    // slot over a reassigned panel — see BarPanelDock's centerAccordion). That's
    // also why there's no separate "gaming"/"wifi" group here any more: which
    // column a name belongs to is a Config lookup, not a fact this file hardcodes.
    property string leftKey:   ""
    property string rightKey:  ""
    property string centerKey: ""

    // Is this panel open, wherever it's configured to be.
    function isOpen(name) {
        return root.leftKey === name || root.rightKey === name || root.centerKey === name
    }

    // Opens (or, if already open, closes) a panel in whichever column
    // Config.panelSide says it belongs to.
    function togglePanel(name) {
        const side = Config.panelSide(name)
        const key  = side === "right" ? "rightKey" : side === "center" ? "centerKey" : "leftKey"
        root[key] = (root[key] === name) ? "" : name
    }

    // Opens a panel, never closes it — for something that needs the panel on screen
    // (a Bluetooth pairing prompt), where a toggle would shut an already-open one.
    function openPanel(name) {
        const side = Config.panelSide(name)
        const key  = side === "right" ? "rightKey" : side === "center" ? "centerKey" : "leftKey"
        root[key] = name
    }

    // Closes one named panel, wherever it currently is — for a panel's own "close
    // me" button, which shouldn't have to know which column it's in, or which DOCK:
    // a panel can open from the bar or the sidebar (modules.js), so the sidebar's
    // slot counts too.
    function closePanel(name) {
        if (root.sidePanel === name) root.sidePanel = ""
        if (root.leftKey   === name) root.leftKey   = ""
        if (root.rightKey  === name) root.rightKey  = ""
        if (root.centerKey === name) root.centerKey = ""
    }

    // Center — system update
    property bool updateOpen:         false
    property int  pendingUpdateCount: 0
    // Bumped on every click. A plain boolean toggle wouldn't fire a change when
    // clicked twice in a row, so re-clicking Update while it's already open would
    // do nothing instead of restarting the check.
    property int  updateRequestId:    0

    // ── Desktop clock ─────────────────────────────────────────────────────────
    // A background-layer surface, not a panel: it sits behind every window and is
    // toggled by the bar's clock pill. Transient by design — restoring it across a
    // reload would be surprising.
    property bool desktopClockOpen: false
    function toggleDesktopClock() { root.desktopClockOpen = !root.desktopClockOpen }

    // Standalone overlays
    property bool launcherOpen: false

    // ── Annotate ──────────────────────────────────────────────────────────────
    // The screenshot editor. Holds the FILE being edited rather than a bare open flag:
    // the editor is meaningless without one, so the path is the state, and "" is
    // closed. Transient — a reload should not reopen an editor over a half-drawn arrow.
    property string annotatePath: ""
    function openAnnotate(path) {
        if (!path) return
        root.activeScreen = null
        root.annotatePath = path
    }
    function closeAnnotate() { root.annotatePath = "" }

    // ── Keybind cheatsheet ────────────────────────────────────────────────────
    // The binds from the user's own Hyprland config, on screen. Transient like
    // everything else in this file — it is a thing you summon, look at, and dismiss,
    // and a cheatsheet restored across a reload would be a cheatsheet in the way.
    property bool cheatsheetOpen: false
    function toggleCheatsheet() { root.cheatsheetOpen = !root.cheatsheetOpen }

    // ── Power menu ────────────────────────────────────────────────────────────
    // The session menu (modules/bar/PowerDock, the edge column), opened
    // by the sidebar's power button or `qs ipc … call power toggle`. Transient, like
    // the cheatsheet: a power menu restored across a reload is one in the way.
    property bool powerMenuOpen: false

    // ── Clip gallery ──────────────────────────────────────────────────────────
    // The clips library overlay (modules/clips/ClipsGallery), opened from the clips
    // pill or `qs ipc … call clips gallery`. Transient, like the cheatsheet.
    property bool clipsGalleryOpen: false

    // ── First-run welcome ─────────────────────────────────────────────────────
    // Its own panel, shown once on a fresh profile (shell.qml drives it off
    // Config.setupSeen). Not restored across a reload — dismissing it persists
    // setupSeen, which is the real "don't show again". IPC-reachable so it can be
    // re-opened for a look: qs ipc -c ~/.config/quicktest call welcome toggle
    property bool welcomeOpen: false
    function toggleWelcome() { root.welcomeOpen = !root.welcomeOpen }
    // Which page it opens on, once (it resets to 0): Settings → Setup's "Theme your
    // apps" lands on the Colours page instead of the welcome.
    property int welcomeStartPage: 0


    // ── Bar-stage inspector wiring ────────────────────────────────────────────
    // Clicking a module in the bar layout editor (Settings → Bar → ModuleTray) has
    // to reach the ModuleInspector living in a different subtree of BarPage.qml,
    // loaded by SettingsCard's page Loader several levels down.
    //
    // (The overview's own real-position BarStage used this too, before the overview's
    // embedded settings page was removed — the salvaged file is in
    // ~/quickshell-salvage/overview-legacy/BarStage.qml.)
    //
    // A plain string can't signal "select this one again" if it was already the
    // selection, so a request counter rides alongside it, same idiom as
    // `updateRequestId` above.
    property string barInspectModule:  ""
    property int    barInspectRequest: 0
    function inspectBarModule(id) {
        root.barInspectModule = id
        root.barInspectRequest++
    }

    // ── Desktop widget arrange mode ───────────────────────────────────────────
    // Transient by design: it is a mode you are IN, not a setting. Restoring it across
    // a reload would drop you onto a dimmed desktop with a grid on it and no memory of
    // asking for that. Entering it closes the overview — the settings page that starts
    // it is inside an overlay covering the very desktop you are arranging.
    property bool widgetArrange: false
    function startArranging() {
        root.overviewOpen   = false
        root.widgetArrange  = true
    }

    // ── Bar arrange mode ──────────────────────────────────────────────────────
    // The REAL bar becomes the editor: its modules turn draggable, the three regions
    // get labelled, and a shelf of unplaced modules opens below it. Same shape as
    // widgetArrange above, and transient for the same reason — it is a mode you are
    // IN, not a setting, and restoring it across a reload would drop you onto a bar
    // covered in drop targets with no memory of asking.
    //
    // ── Why the bar and not a copy of it ──────────────────────────────────────
    // The settings page used to draw its own bar-shaped strip and let you arrange
    // that. It was a clone, and a clone is the wrong object: you tune the real bar's
    // opacity, roundness and spacing three sections away, then arrange something that
    // only approximates the result.
    //
    // It also could not be fixed by making the clone more faithful, because the thing
    // that made it a clone is structural: Qt's Drag/DropArea only work WITHIN one
    // window. Settings is an xdg-toplevel and the bar is a layer-shell surface, so
    // nothing can be dragged from one into the other. The drop targets have to live
    // on the bar's own surface, which means the bar has to be the editor.
    //
    // Bar.qml already reserves window height beyond the bar strip for the Control
    // Center, for the same class of reason (one scene graph). The arrange shelf is
    // that pattern again.
    //
    // Turned on by the Arrange button in Bar › Modules' header, and cleared when that
    // page is destroyed so it can't stay on. (It used to arm itself whenever the page
    // opened, and cover the bar in drop targets whether or not you wanted to move
    // anything.)
    //
    // ── One switch for both surfaces (2026-11-08) ─────────────────────────────
    // `arrange` arms the bar AND the sidebar together, because a module can be dragged
    // from one onto the other (state/ModuleDrag) and a drag needs both ends live. The
    // two names below were two switches, one per settings page; they stay as readonly
    // mirrors so their ~20 readers needn't change. Write `arrange`.
    property bool arrange: false
    readonly property bool barArrange: root.arrange

    // The sidebar's half: the REAL sidebar becomes the editor (modules/bar/SideArrange,
    // state/SideDrag). While it's on the sidebar stays out — shown even with nothing on
    // it, so there's somewhere to drop the first module — and SUPER+SHIFT+D can't sink it.
    readonly property bool sidebarArrange: root.arrange
    onArrangeChanged: if (root.arrange) { root.sidebarHidden = false; root.closeAllPanels() }

    // Every panel the bar and the sidebar hang out. Arranging closes them and keeps them shut: the
    // arrange cards melt out of the same edges, and a panel in the way hides what is being arranged.
    function closeAllPanels() {
        root.leftKey = ""
        root.rightKey = ""
        root.centerKey = ""
        root.sidePanel = ""
        root.updateOpen = false
    }
    Connections {
        target: root
        function onLeftKeyChanged()   { if (root.arrange && root.leftKey   !== "") root.leftKey   = "" }
        function onRightKeyChanged()  { if (root.arrange && root.rightKey  !== "") root.rightKey  = "" }
        function onCenterKeyChanged() { if (root.arrange && root.centerKey !== "") root.centerKey = "" }
        function onSidePanelChanged() { if (root.arrange && root.sidePanel !== "") root.sidePanel = "" }
        function onUpdateOpenChanged() { if (root.arrange && root.updateOpen) root.updateOpen = false }
    }


    // ── Overview ──────────────────────────────────────────────────────────────
    // The full-screen overlay: workspace grid, dock, media, glance info, power.
    // Transient.
    //
    // There is no `overviewPanel` any more. The overview briefly had a
    // panel-over-the-grid mode for the calendar and the power menu; both are now
    // cards/buttons ON the overlay, so nothing in the overview is behind a panel and
    // the overlay has exactly one piece of state: open or not. (The HUD's cards live in
    // it too, in a rail beside the grid — services/Hud.)
    property bool overviewOpen: false
    // Closing ZOOMS back into the workspace you're on (leaveOverview), the way choosing one
    // does — the keybind, the bar button, Escape (Overview) all leave the same way.
    function toggleOverview() {
        if (root.overviewOpen) root.leaveOverview(Hypr.focusedWorkspaceId)
        else root.overviewOpen = true
    }
    // The overview's cookie parallax: how far the shared field is shifted against the
    // pointer, in px. Every DriftShapes window in the overview reads it (`shift`), so the
    // field glides as one and a cookie crossing into a card stays the same cookie.
    // Written only by Overview.qml; (0, 0) whenever the pointer isn't over it.
    property point overviewDrift: Qt.point(0, 0)
    // A clip is being dragged OUT of the overview (HudClipsCard's shelf): the overview steps
    // aside — its stage fades and its input mask empties — so the drop lands on the window
    // beneath. Set on the drag's start, cleared when it finishes.
    property bool overviewLending: false
    // "Go there" from the overview (a cell, a window, Enter, Alt let go): it ZOOMS into that
    // workspace's cell — the windows fly to their real places — and then closes (Overview,
    // OverviewZoom). Motion off, or no workspace: it just closes. `overviewLeaveTo` is the
    // request; the overview showing it clears it when it's done.
    property int overviewLeaveTo: -1
    function leaveOverview(ws) {
        if (!root.overviewOpen) return
        if (ws > 0 && Config.motionEnabled) root.overviewLeaveTo = ws
        else root.overviewOpen = false
    }

    // ── Dock reveal (auto-hide pin-open latch) ────────────────────────────────
    // Only meaningful while Config.sidebarAutoHide is on — the sidebar also reveals
    // on plain hover of the screen edge (SideBarHost), independent of this. This is the
    // "pinned open" state: the toggle keybind (SUPER+D) or IPC call latches it
    // until pressed again. Transient like every other panel-open flag here — an
    // auto-hidden dock starts hidden on every reload.
    property bool dockRevealed: false
    function toggleDockRevealed() { root.dockRevealed = !root.dockRevealed }

    // ── The whole sidebar, out of the way ─────────────────────────────────────
    // SUPER+SHIFT+D: the dock and the stats pill both sink into the frame and stay
    // there — no edge reveal, no reserved space — until pressed again. Not the
    // settings' on/off (nothing is unloaded), and transient like the latch above:
    // a hidden sidebar you forgot about comes back on the next reload.
    property bool sidebarHidden: false

    // ── The sidebar's panel ───────────────────────────────────────────────────
    // A sidebar button's panel (the stats, the clips) opens BESIDE its button,
    // melting out of the sidebar's face (modules/bar/SidePanelDock) — not in a bar
    // column. One at a time, on one screen:
    //   sidePanel        the panel's key ("stats", "clips", "clipsTarget", "clipsPeek",
    //                    "notifications", "clipboard", "timer", "voice", "claude", "screentime", "inactivity", "tasks",
    //                    "brightness", "window", "layout")
    //   sidePanelFrom    the sidebar module that opened it — where it opens beside
    //   sidePanelScreen  whose sidebar. A caller with no screen of its own (the
    //                    `sidebar panel` keybind) gets the FOCUSED monitor's, resolved
    //                    once at open (see _hereScreen); null only if Hyprland hasn't
    //                    named one yet, and then the first screen's.
    //   sidePanelArg     what the panel opened ON, "" for nothing in particular (the
    //                    voice panel: the person right-clicked)
    // It hangs off the same face as the bar column on the sidebar's side, so the two
    // are one or the other: opening either closes the other.
    property string sidePanel: ""
    property string sidePanelFrom: ""
    property var    sidePanelScreen: null
    property string sidePanelArg: ""
    // The ShellScreen of Hyprland's focused monitor, or null. Read at the moment a
    // panel opens, never bound: focus follows the mouse, and a live binding would
    // move an open panel between screens as the pointer crosses an edge (the same
    // reason ScreenOwner captures).
    function _hereScreen() {
        const name = Hyprland.focusedMonitor?.name ?? ""
        return name === "" ? null : (Quickshell.screens.find(s => s.name === name) ?? null)
    }
    function openSidePanel(key, from, screen, arg) {
        // Where and whose BEFORE which, so the dock never sees the new key with the
        // old button's place.
        root.sidePanelScreen = screen ?? root._hereScreen()
        root.sidePanelArg = arg ?? ""
        root.sidePanelFrom = from
        root.sidePanel = key
        if (Config.dockPosition === "left")       root.leftKey  = ""
        else if (Config.dockPosition === "right") root.rightKey = ""
    }
    // The same button asking again closes it; anything else opens that instead.
    // (Open on something else — another person — and it switches to that instead.)
    function toggleSidePanel(key, from, screen, arg) {
        if (root.sidePanel === key && root.sidePanelFrom === from
            && root.sidePanelScreen === (screen ?? root._hereScreen()) && root.sidePanelArg === (arg ?? ""))
            root.closeSidePanel()
        else root.openSidePanel(key, from, screen, arg)
    }
    function closeSidePanel() { root.sidePanel = "" }
    onLeftKeyChanged:  if (root.leftKey  !== "" && Config.dockPosition === "left")  root.sidePanel = ""
    onRightKeyChanged: if (root.rightKey !== "" && Config.dockPosition === "right") root.sidePanel = ""
    // Sunk into the frame, the sidebar takes its panel with it.
    onSidebarHiddenChanged: if (root.sidebarHidden) root.sidePanel = ""

    // ── Peek ──────────────────────────────────────────────────────────────────
    // The window a dock preview is resting on (its 0x address), "" for none. The
    // Bar on that window's monitor draws its workspace with it lit (WindowPeek).
    // Set by DockPreview after a dwell; cleared when the pointer leaves the tile.
    property string dockPeek: ""

    // ── Dock from the keyboard ────────────────────────────────────────────────
    // `dockKeyboard`: the dock on the focused monitor holds keyboard focus — arrows
    // move along it, Enter opens, Menu opens the jump list, Escape leaves. SUPER+T,
    // as on Windows. `dockActivate(n)`: SUPER+ALT+n opens the nth app of that dock.
    // A request is a bumped sequence number, so asking for the same n twice in a
    // row still fires.
    property bool dockKeyboard: false
    property int  dockActivateIndex: -1
    property int  dockActivateSeq:   0
    function dockActivate(n) {
        root.dockActivateIndex = n
        root.dockActivateSeq++
    }

    // ── Dragging an app from the launcher onto the dock ───────────────────────
    // The launcher and the dock share Bar's window — one scene — so this is plain
    // state rather than a platform drag: the launcher reports the pointer in that
    // window's scene coordinates, the dock opens a gap under it, and a drop pins
    // the app there. `appDropped` fires BEFORE the key is cleared, so the dock can
    // still read where the gap was.
    property string appDragKey: ""
    property real   appDragX: 0
    property real   appDragY: 0
    signal appDropped(string key)

    // A window SUPER-dragged by Hyprland and let go at (x, y), local to `monitor`.
    // Hyprland owns that drag, so the shell never sees it; the `windrag` hook in
    // hypr/binds.lua reports the release. Each bar's WorkspacesPill hit-tests it.
    signal windowDropped(string address, string monitor, int x, int y)
    // …and the same drop when NOTHING took it (no pill hit-tested it): snap zones
    // (services/Snap) get those. A handler that acts on windowDropped claims it first
    // (claimWindowDrop), so one release never both moves and snaps a window.
    signal windowLanded(string address, string monitor, int x, int y)
    property bool _dropClaimed: false
    function claimWindowDrop() { root._dropClaimed = true }

    // The window a SUPER-drag is carrying right now ("" when none): set by the
    // hook's `begin` on the press, cleared by its `drop` on the release. While
    // it's set, the pills follow Pointer to show which workspace a release would
    // pick. A lost release (the hook's exec failing) can't strand it: it lets go
    // on its own after a minute.
    property string windowDrag: ""
    property var _windowDragFailsafe: Timer {
        interval: 60000
        running: root.windowDrag !== ""
        onTriggered: root.windowDrag = ""
    }

    function beginAppDrag(key) { root.appDragKey = key }
    function moveAppDrag(x, y) { root.appDragX = x; root.appDragY = y }
    function endAppDrag(drop) {
        if (drop && root.appDragKey !== "") root.appDropped(root.appDragKey)
        root.appDragKey = ""
    }

    // ── Settings is a WINDOW ──────────────────────────────────────────────────
    // A real xdg-toplevel (modules/settings/SettingsWindow.qml), not a layer-shell
    // overlay: the compositor gives it ordinary focus, alt-tab and tiling, which is
    // what makes it an application rather than a thing the shell paints over you.
    //
    // The overview no longer has a settings page at all — it duplicated this window
    // and nothing routed to it. See SettingsWindow's header.
    property bool settingsWindowOpen: false

    function openSettingsWindow() { root.settingsWindowOpen = true }
    function closeSettingsWindow() { root.settingsWindowOpen = false }
    function toggleSettingsWindow() {
        root.settingsWindowOpen = !root.settingsWindowOpen
    }

    // ── Resuming after an in-process reload ───────────────────────────────────
    // True only for the instant shell.qml's `reloadCarry` is handing
    // `settingsWindowOpen` back to the new generation. SettingsWindow resets the
    // window to its opening size on every open; a resume is not an open — the
    // surface it adopted already carries whatever size the user left it at — so
    // this is the bit that tells the two apart.
    //
    // Set and cleared around one assignment, so it is never observable outside
    // that synchronous change signal and there is no lifetime to leak.
    property bool settingsWindowResuming: false

    // ── Lyrics is a WINDOW too ─────────────────────────────────────────────────
    // Same shape as Settings above, for the same reason: a real xdg-toplevel gets
    // ordinary focus, alt-tab and tiling, which is the whole point of it being
    // launchable from the search bar rather than another accordion panel.
    // modules/lyrics/LyricsWindow.qml is the overview's own lyrics card
    // (modules/overview/OverviewLyrics.qml) standalone and resizable — not a
    // second lyrics implementation.
    property bool lyricsWindowOpen: false

    function openLyricsWindow() { root.lyricsWindowOpen = true }
    function closeLyricsWindow() { root.lyricsWindowOpen = false }
    function toggleLyricsWindow() {
        root.lyricsWindowOpen = !root.lyricsWindowOpen
    }

    // ── Opening the overview to a specific SETTINGS page ──────────────────────
    // A step finer than `openOverviewTo("settings")`: hardware pills (Battery,
    // Bluetooth) want the page ABOUT them, not whichever page you were last on.
    //
    // Why a request pair and not just `Config.settingsPage = file`: SettingsCard
    // binds `currentFile` to Config.settingsPage but its own showPage() ASSIGNS to
    // currentFile, which destroys that binding the first time you click the rail.
    // A Config write would therefore work until you'd navigated settings once and
    // then silently stop — the same failure SettingsCard's own header comment
    // documents about the restore. Bumping a counter is immune to that: the card
    // reacts to the signal and assigns, so it never matters what is or isn't bound.
    //
    // Same idiom as barInspectModule/barInspectRequest below, for the same reason —
    // re-requesting the page you're already on has to navigate, and a string that
    // didn't change wouldn't fire.
    property string settingsPageRequest: ""
    property int    settingsPageNav:     0
    // Which GROUP of a composed settings page to scroll to — the member file a deep
    // link named ("DockPage.qml" → the Dock group of Sidebar & dock). Set by the card
    // when the request was for a member, cleared by the page once it has scrolled; so
    // a page that loads after the request (a fresh card) and one already open both see
    // it. See SettingsIndex.memberPages.
    property string settingsGroup: ""

    // True only while SettingsCard is loading a page it changed TO (not the one a window opens on):
    // Section and QuickToggleTile made in that window rise in one after another. Cleared again
    // straight after, so a card a page builds later (a device that appears) just appears.
    property bool settingsCascade: false

    // ── The settings help tip ─────────────────────────────────────────────────
    // A setting carries one short state line; the sentence that explains it is its
    // `help`, shown in a tip when the pointer rests on it (components/HelpTip). One
    // tip for the whole card, drawn by SettingsCard above everything, because a tip
    // drawn by the row itself is clipped by the page's scroll area and the card.
    // `tipSource` is the HelpTip (a HoverHandler) the pointer is resting in — its
    // `parent` is the control, its `point` where the pointer is. QtObject-typed, so it
    // clears itself when that handler is destroyed with its page.
    property QtObject tipSource: null
    property string   tipText: ""
    function showTip(source, text) {
        root.tipText = text
        root.tipSource = source
    }
    function hideTip(source) {
        if (root.tipSource === source) root.tipSource = null
    }

    // Pages that became a module in Bar › Modules (2026-11-08): opening one opens that
    // page with the module picked, so the dock's "Settings" and the stats button's
    // right-click still land on the dock's and the stats' settings.
    readonly property var _moduleOfPage: ({ "DockPage.qml": "dock", "SidebarStatsPage.qml": "stats" })
    function openSettingsTo(file) {
        const m = root._moduleOfPage[file]
        if (m !== undefined) { root.inspectBarModule(m); file = "BarPage.qml" }
        root.settingsPageRequest = file
        root.settingsPageNav++
        // Raises the WINDOW, not the overview. The bar's hardware pills (Battery,
        // Bluetooth) come through here, so "open the page about this" now lands in
        // the settings app like every other route in.
        root.settingsWindowOpen = true
    }

    // ── Where a docked panel welds into the screen frame's side strip ────────
    // ── Who draws the screen ring ─────────────────────────────────────────────
    // True while the blob layer in the bar's window is drawing the frame band
    // itself. ScreenFrame's overlay unmaps when it is: the frame's Shape stroke and
    // the blob's SDF outline are different curves in different windows, and the two
    // can never be made to meet at a panel's corner. One window, one silhouette,
    // one outline. False (the plugin absent) puts ScreenFrame back in charge.
    property bool blobRingOwned: false

    // ── The active panel in each group, as a key ──────────────────────────────
    // The panel host sizes and swaps its container from these. Deriving one key
    // from the booleans (rather than having the host inspect four flags) is what
    // lets the Accordion sequence a swap: it only has to watch one string.
    readonly property string leftPanel:   leftKey
    readonly property string rightPanel:  rightKey
    readonly property string centerPanel: centerKey

    // Plain column clears — for Escape and the IPC's `close`, which don't care
    // which panel a column holds, only that it goes away. closeCenter() only
    // ever clears centerKey: update/launcher aren't driven by it (see
    // BarPanelDock's centerAccordion), so it can't accidentally close either.
    function closeLeft()   { root.leftKey   = "" }
    function closeRight()  { root.rightKey  = "" }
    function closeCenter() { root.centerKey = "" }

    // ══ Almost nothing here persists ══════════════════════════════════════════
    // Panel state is transient by design — a reload should not reopen whatever you
    // happened to have open. The appearance PREFERENCES that used to live here
    // (barShape/barMode) moved to Config, which is where durable settings belong.
    //
    // ONE exception, and it is carried rather than persisted: `settingsWindowOpen`
    // is handed across an in-process reload by shell.qml's `reloadCarry`. Settings
    // is a real application window you might be halfway through using, not a panel
    // you flicked open — having it vanish because the shell rebuilt itself is the
    // one case where "transient" was the wrong answer. Nothing is written to disk
    // and it does not survive a full process restart.
    //
    // That state still lives HERE, not in the carry: the carry only mirrors it out
    // and hands it back in. See shell.qml for why it has to sit where it does.

    // ══ IPC ═══════════════════════════════════════════════════════════════════
    // `qs ipc -c ~/.config/quicktest call launcher toggle`
    // activeScreen is cleared so the launcher shows on every screen — a raw
    // keybind carries no screen context.
    property var _ipc: IpcHandler {
        target: "launcher"

        function toggle(): void {
            root.activeScreen = null
            root.launcherOpen = !root.launcherOpen
        }
        function open(): void {
            root.activeScreen = null
            root.launcherOpen = true
        }
        function close(): void {
            root.launcherOpen = false
        }
    }

    // `qs ipc -c ~/.config/quicktest call cheatsheet toggle`
    //
    // activeScreen is cleared for the same reason the launcher does it: a raw keybind
    // carries no screen context, so the sheet shows wherever you are.
    property var _cheatsheetIpc: IpcHandler {
        target: "cheatsheet"

        function toggle(): void {
            root.activeScreen = null
            root.cheatsheetOpen = !root.cheatsheetOpen
        }
        function open(): void {
            root.activeScreen = null
            root.cheatsheetOpen = true
        }
        function close(): void { root.cheatsheetOpen = false }
    }

    // `qs ipc -c ~/.config/quicktest call power toggle` — the power menu, on the
    // focused monitor (ScreenOwner), for a keybind.
    property var _powerIpc: IpcHandler {
        target: "power"
        function toggle(): void { root.powerMenuOpen = !root.powerMenuOpen }
        function open(): void   { root.powerMenuOpen = true }
        function close(): void  { root.powerMenuOpen = false }
    }

    // `qs ipc -c ~/.config/quicktest call welcome toggle`
    property var _welcomeIpc: IpcHandler {
        target: "welcome"
        function toggle(): void { root.welcomeOpen = !root.welcomeOpen }
        function open(): void   { root.welcomeOpen = true }
        function close(): void  { root.welcomeOpen = false }
    }

    // `qs ipc -c ~/.config/quicktest call overview toggle`
    //
    // Same target name the old standalone overview process used, so an existing
    // Hyprland keybind keeps working — it just no longer starts a second shell.
    property var _overviewIpc: IpcHandler {
        target: "overview"

        function toggle(): void { root.toggleOverview() }
        function open(): void    { root.overviewOpen = true }
        function close(): void   { root.leaveOverview(Hypr.focusedWorkspaceId) }
        // The "More" fold (Config.overviewMore): show / hide the overview's extra panels. A Hyprland bind can call it,
        // open or not; Ctrl+M does the same inside the overview.
        function more(): void    { Config.overviewMore = !Config.overviewMore }
    }

    // `qs ipc -c ~/.config/quicktest call dock toggle` — the auto-hide reveal
    // latch's keybind path (see dockRevealed above). Same shape as `overview`.
    // `qs ipc -c ~/.config/quicktest call sidebar toggle` — SUPER+SHIFT+D.
    property var _sidebarIpc: IpcHandler {
        id: sidebarIpc
        target: "sidebar"

        function toggle(): void { root.sidebarHidden = !root.sidebarHidden }
        function show(): void   { root.sidebarHidden = false }
        function hide(): void   { root.sidebarHidden = true }
        // Read-only. Groups in brackets, per region, near end first:
        //   hidden=false edge=left start=[clips] centre=[dock] end=[stats]
        function status(): string {
            const l = Config.sidebarLayout
            const region = r => (l[r] ?? []).map(g => "[" + g.join(",") + "]").join("")
            return "hidden=" + root.sidebarHidden + " edge=" + Config.dockPosition
                 + " start=" + region("start") + " centre=" + region("centre") + " end=" + region("end")
        }
        // Put a module on the sidebar as a group of its own at the far end of a
        // region (start | centre | end), or move it there. Writes the config — this is
        // what the settings page does.
        function place(id: string, region: string): string {
            if (!Config.sidebarModuleInfo(id))
                return "unknown module '" + id + "' — expected one of: "
                     + Config.sidebarModuleList.map(m => m.id).join(", ")
            if (Config.sidebarRegionIds.indexOf(region) === -1)
                return "unknown region '" + region + "' — expected one of: " + Config.sidebarRegionIds.join(", ")
            // Past the last group; layout.js clamps it once the module is lifted out.
            Config.sidebarMoveToOwnGroup(id, region, (Config.sidebarLayout[region] ?? []).length)
            return sidebarIpc.status()
        }
        function remove(id: string): string {
            Config.sidebarRemove(id)
            return sidebarIpc.status()
        }
        // Toggle a sidebar button's panel (stats | clips | notifications | clipboard | timer | voice),
        // beside that button, on the focused screen — what a click on it does. For a keybind.
        function panel(key: string): string {
            const keys = ["stats", "clips", "notifications", "clipboard", "timer", "voice", "claude", "screentime", "inactivity", "tasks",
                          "brightness", "window", "layout",
                          "colorScheme", "equalizer", "wifi", "bluetooth", "gaming", "clock"]
            if (!keys.includes(key)) return "unknown panel '" + key + "' — expected " + keys.join(", ")
            // The bar's panels are named apart from the module that opens them.
            const from = ({ colorScheme: "palette", equalizer: "volume", gaming: "gamemode" })[key] ?? key
            if (!Config.sidebarPlaced(from)) return "'" + from + "' isn't on the sidebar"
            root.toggleSidePanel(key, from, null)
            return root.sidePanel === "" ? "closed" : "open " + root.sidePanel
        }
    }

    // `qs ipc -c ~/.config/quicktest call windrag drop <address> <monitor> <x> <y>`
    // — sent by hypr/binds.lua when a SUPER-drag ends (see windowDropped).
    property var _windragIpc: IpcHandler {
        target: "windrag"

        function begin(address: string): void { root.windowDrag = address }
        function drop(address: string, monitor: string, x: int, y: int): void {
            root._dropClaimed = false
            root.windowDropped(address, monitor, x, y)
            if (!root._dropClaimed) root.windowLanded(address, monitor, x, y)
            root.windowDrag = ""
        }
    }

    property var _dockIpc: IpcHandler {
        target: "dock"

        function toggle(): void { root.dockRevealed = !root.dockRevealed }
        function open(): void   { root.dockRevealed = true }
        function close(): void  { root.dockRevealed = false }
        // SUPER+T — keyboard focus onto the dock of the focused monitor.
        function focus(): void  { root.dockKeyboard = true }
        // SUPER+ALT+n — open the nth app (1-based, the way the keys are numbered).
        function activate(n: int): void { root.dockActivate(n - 1) }
        function status(): string {
            return "enabled=" + Config.dockEnabled
                 + " position=" + Config.dockPosition
                 + " overflow=" + Config.dockOverflow
                 + " autoHide=" + Config.sidebarAutoHide
                 + " takesSpace=" + Config.dockTakesSpace
                 + " revealed=" + root.dockRevealed
                 // What the dock would draw right now, straight from the service —
                 // separates "the dock is broken" from "there is nothing to draw".
                 // App keys only; no window titles.
                 + " | pinned=" + Taskbar.pinned.length
                 + " running=" + Taskbar.running.length
                 + " apps=[" + Taskbar.apps.join(",") + "]"
        }
    }

    // `qs ipc -p ~/.config/quicktest call settings open`
    //
    // This exists so Settings can be a real desktop entry. The .desktop written by
    // scripts/install-desktop-entry.sh has exactly this as its Exec, which is what
    // makes it launchable from the shell's own search bar AND from rofi/wofi/anything
    // else that reads $XDG_DATA_HOME/applications — rather than only from the bar's
    // gear, which you have to already know is there.
    //
    // It raises the settings WINDOW — a real toplevel the compositor manages, so the
    // desktop entry behaves like any other application's.
    property var _settingsIpc: IpcHandler {
        target: "settings"

        function open(): void { root.settingsWindowOpen = true }
        function toggle(): void { root.settingsWindowOpen = !root.settingsWindowOpen }
        function close(): void { root.settingsWindowOpen = false }

        // Straight to one page: `… call settings page NightLightPage.qml`. The file
        // name, not a friendly label, because that is the id SettingsCard's `pages`
        // list already keys on — a second vocabulary would be a mapping to keep in
        // sync for no gain. An unknown name is ignored by openSettingsTo's guard
        // rather than stranding the rail on a page that doesn't exist.
        function page(file: string): void { root.openSettingsTo(file) }
    }

    // `qs ipc -p ~/.config/quicktest call shell reload`
    //
    // The bar's ReloadPill, from a script: an in-process reload, so the settings
    // window survives it (shell.qml's reloadCarry). It exists because the hot
    // reloader only watches files the shell imported — a settings PAGE is loaded by
    // path when you open it, so saving one changes nothing until something else
    // reloads, and this is that something without a full restart (ALT+Q).
    property var _shellIpc: IpcHandler {
        target: "shell"

        function reload(): void { Quickshell.reload(false) }
    }

    // `qs ipc -p ~/.config/quicktest call lyricswindow open`
    //
    // Same reason as `_settingsIpc` above: scripts/lyrics-open.sh (the Exec target
    // of scripts/install-lyrics-entry.sh's desktop entry) has exactly this as its
    // call, which is what makes the standalone lyrics window launchable by typing
    // "Lyrics" into the search bar.
    property var _lyricsWindowIpc: IpcHandler {
        target: "lyricswindow"

        function open(): void    { root.lyricsWindowOpen = true }
        function toggle(): void  { root.lyricsWindowOpen = !root.lyricsWindowOpen }
        function close(): void   { root.lyricsWindowOpen = false }
    }

    // ── The bar's own panel groups, over IPC ──────────────────────────────────
    // Every other surface in this shell is reachable this way (launcher,
    // cheatsheet, overview); these two groups were the only ones
    // openable by CLICK ALONE, which made them the only ones that could not be
    // checked without a hand on the mouse — and they are now docked inside Bar's
    // window, where "did it load" says nothing about whether it draws.
    //     qs ipc -c ~/.config/quicktest call panel toggle wifi
    property var _panelIpc: IpcHandler {
        target: "panel"

        // `name` is a key from leftPanel/rightPanel/centerPanel above — wallpaper,
        // colorScheme, equalizer, media, wifi, bluetooth, gaming — or "update" for
        // the centre slot's other occupant, which is not an accordion key: the
        // panel decides its own lifetime off a request id, so a toggle either
        // fires a fresh request or closes it. Every other name goes through
        // togglePanel(), which resolves its column from Config.panelSide() itself.
        function toggle(name: string): void {
            if (name === "update") {
                if (root.updateOpen) root.updateOpen = false
                else                 root.updateRequestId++
            }
            else root.togglePanel(name)
        }

        function close(): void {
            root.closeLeft()
            root.closeRight()
            root.closeCenter()
            root.updateOpen = false
        }

        // Which group is showing what — tells "the panel is broken" apart from
        // "there is nothing open to draw".
        function status(): string {
            // The centre slot holds the launcher OR the update panel OR a
            // reassigned panel — reported in the order the Accordion resolves
            // them, so this says what is actually on screen rather than what
            // merely wants to be.
            return "left="   + (root.leftPanel  || "-")
                 + " right=" + (root.rightPanel || "-")
                 + " center=" + (root.launcherOpen ? "launcher"
                               : root.updateOpen   ? "update"
                               :                     (root.centerPanel || "-"))
        }
    }

}
