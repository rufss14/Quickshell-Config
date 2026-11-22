pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "../config"
import "../services"
import "../config/islands.js" as Islands

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

    // ── …or a page on an island's rail ────────────────────────────────────────
    // With the islands on (Config.island), a panel that is on a rail (config/islands.js) opens as
    // that island's page instead of in a column: `_rail` names the island, "" for a panel that
    // still opens alone in its column (and for every panel while the islands are off or arranging).
    readonly property bool islandsOn: Config.island && !root.arrange
    // Where every page is (config/islands.js layoutOf): each island's rail in order, the panels that open alone
    // per column, the own pages taken off. The board on Settings › Bar & islands › Islands edits it.
    readonly property var islandLayout: Islands.layoutOf(Config.islandRails, Config.panelPlacement, Config.islandPages)
    // An island's option (config/islands.js OPTIONS): its override (Config.islandOverrides) or the shared one.
    readonly property var islandShared: ({
        openBy: Config.islandOpenBy, delay: Config.islandDelay, linger: Config.islandLinger,
        handle: Config.islandHandle, scale: Config.islandScale, effects: Config.islandEffects
    })
    function islandOpt(side, name) { return Islands.optionOf(side, name, root.islandShared, Config.islandOverrides) }
    // The effects switch of the island opened last, for the pages (they don't know which island holds them).
    // With two islands open that differ on it, a page on the older one follows the newer one's switch.
    readonly property bool islandEffectsOn: root.islandOpt(root.islandLast, "effects")
    // The page a panel's button opens on an island ("" = it opens alone in its column): the panel itself, or
    // the page that does its job (config/islands.js ALIAS: Stats is Performance, To-do / Clipboard / Idle are
    // Desk; Now Playing is the Media page, which has the same id). `_rail` names that page's island.
    function _railPage(name) { return root.islandsOn ? Islands.pageFor(name, root.islandLayout) : "" }
    function _rail(name) {
        const page = root._railPage(name)
        return page === "" ? "" : Islands.railOf(page, root.islandLayout)
    }
    // Opened from a button: on that button's screen, on that page, and it stays (pinned) until it is
    // closed, since the pointer is on the bar and not on the island.
    function _showIsland(side, page, screenName) {
        root.openIsland(side, { screen: screenName ?? (root.activeScreen?.name ?? ""), page: page, pinned: true })
    }

    // Is this panel open, wherever it's configured to be.
    function isOpen(name) {
        const rail = root._rail(name)
        if (rail !== "") return root.islandIsOpen(rail) && root.islandWanted(rail) === root._railPage(name)
        return root.leftKey === name || root.rightKey === name || root.centerKey === name
    }

    // Opens (or, if already open, closes) a panel in whichever column
    // Config.panelSide says it belongs to.
    function togglePanel(name) {
        const rail = root._rail(name)
        if (rail !== "") {
            if (root.isOpen(name)) root.closeIsland(rail)
            else root._showIsland(rail, root._railPage(name))
            return
        }
        const side = Config.panelSide(name)
        const key  = side === "right" ? "rightKey" : side === "center" ? "centerKey" : "leftKey"
        root[key] = (root[key] === name) ? "" : name
    }

    // Opens a panel, never closes it — for something that needs the panel on screen
    // (a Bluetooth pairing prompt), where a toggle would shut an already-open one.
    function openPanel(name) {
        const rail = root._rail(name)
        if (rail !== "") { root._showIsland(rail, root._railPage(name)); return }
        const side = Config.panelSide(name)
        const key  = side === "right" ? "rightKey" : side === "center" ? "centerKey" : "leftKey"
        root[key] = name
    }

    // ── A setting that lives outside the settings app ─────────────────────────
    // What a settings search result for a panel or island setting opens (SettingsIndex
    // `elsewhere`): `o` is { page, part } for an island page (on a part, pinned, on the
    // focused screen; off a rail, its panel the usual way), { panel } for a bar panel itself
    // in its column (Now Playing: the island's Media page is the player, the settings are
    // on the panel), or { overview: true }. The settings window stays open beside it; the
    // docked settings card (Config.settingsPanel) closes, since it shares the frame the
    // panel or island opens from.
    function openElsewhere(o) {
        if (!o) return
        if (o.overview) root.overviewOpen = true
        else if (o.page) {
            const rail = root.islandsOn ? Islands.railOf(o.page, root.islandLayout) : ""
            if (rail !== "") root.openIsland(rail, { screen: "", page: o.page, part: o.part ?? "", pinned: true })
            else root.openPanel(o.page)
        } else if (o.panel) {
            const side = Config.panelSide(o.panel)
            root[side === "right" ? "rightKey" : side === "center" ? "centerKey" : "leftKey"] = o.panel
        } else return
        if (Config.settingsPanel) root.settingsWindowOpen = false
    }
    // Where openElsewhere(o) would open it: "island", "panel" or "overview" — how a result
    // says where the setting lives.
    function elsewhereKind(o) {
        if (!o) return "panel"
        if (o.overview) return "overview"
        return o.page && root.islandsOn && Islands.railOf(o.page, root.islandLayout) !== "" ? "island" : "panel"
    }

    // Closes one named panel, wherever it currently is — for a panel's own "close
    // me" button, which shouldn't have to know which column it's in, or which DOCK:
    // a panel can open from the bar or the sidebar (modules.js), so the sidebar's
    // slot counts too.
    function closePanel(name) {
        if (root._rail(name) !== "" && root.isOpen(name)) root.closeIsland(root._rail(name))
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

    // ── Hot corner ────────────────────────────────────────────────────────────
    // The corner panel (modules/panels/HotCorner). Transient like the cheatsheet: a panel
    // restored across a reload would be one in the way. `hotCornerByKey` is true when a key
    // opened it (no pointer in the corner), which gives the pointer a moment to arrive.
    property bool hotCornerOpen: false
    property bool hotCornerByKey: false
    // The screen whose corner was touched; "" = the focused one (a key carries no screen).
    property string hotCornerScreen: ""
    // Pinned: it stays until closed, whatever the pointer does.
    property bool hotCornerPinned: false

    property var _hotCornerIpc: IpcHandler {
        target: "hotcorner"

        function toggle(): void {
            root.hotCornerByKey = true
            root.hotCornerScreen = ""
            root.hotCornerOpen = !root.hotCornerOpen
        }
        function open(): void {
            root.hotCornerByKey = true
            root.hotCornerScreen = ""
            root.hotCornerOpen = true
        }
        function close(): void { root.hotCornerOpen = false }
    }

    // ── Islands ───────────────────────────────────────────────────────────────
    // Six islands (config/islands.js SIDES, modules/island/IslandDock): three hang from the bar (left, center,
    // right), three stand on the screen's bottom edge (bottomLeft, bottomCenter, bottomRight), where the
    // sidebar's buttons open theirs. Each has its own state in `islandSet`: { id: { pinned, screen, page, part } },
    // and an id in it is open. Transient.
    //   screen  the screen it opened on ("" = the focused one, for a key)
    //   pinned  it stays until closed, whatever the pointer does
    //   page    the page this opening lands on instead of the remembered one (the live handle's song opens Media,
    //           a button opens its own page); "" or a page that island does not have = the remembered one
    //   part    a part WITHIN that page (the wallpaper page's source, the colour page's tab), read once by
    //           the page as it is built; "" for wherever the page starts
    // Who may be open together (the user's rule, 2026-11-15): in a row, the two sides may be open at once, the
    // middle only alone (it would cover both). Two sides whose cards would meet (a narrow screen) are one or
    // the other too (`islandSpans`, reported by the docks). The rows are independent: a card is fitted into
    // its half of the screen while the other row has pages (IslandDock.fitScale), so the two never meet.
    property var    islandSet: ({})
    // The island opened last: whose effects switch the pages follow, and where a Dashboard tile hands over from.
    property string islandLast: "center"
    readonly property bool islandOpen: Object.keys(root.islandSet).length > 0
    // Anything hanging from the bar is open: an island, or a panel in one of the plain columns. The
    // notification deck hangs from the same edge and would collide with it (Notifications.glance).
    readonly property bool barSurfaceOpen: root.islandOpen || root.leftKey !== "" || root.rightKey !== ""
                                           || root.centerKey !== "" || root.launcherOpen || root.updateOpen

    function islandIsOpen(id) { return root.islandSet[id] !== undefined }
    function islandIsPinned(id) { return root.islandSet[id]?.pinned === true }
    function islandScreenOf(id) { return root.islandSet[id]?.screen ?? "" }
    function islandPageOf(id) { return root.islandSet[id]?.page ?? "" }
    function islandPartOf(id) { return root.islandSet[id]?.part ?? "" }
    // The island showing a page (its rail's), for a page that needs its own island's screen or part.
    function islandOfPage(page) { return Islands.railOf(page, root.islandLayout) }
    function islandPartFor(page) { return root.islandPartOf(root.islandOfPage(page)) }
    function islandScreenFor(page) { return root.islandScreenOf(root.islandOfPage(page)) }

    // Where each island's card stands along its edge when open, per screen: { "id@screen": { x0, x1 } }. Docks
    // report it as their card's width becomes known; only the side-by-side check reads it, never a binding.
    property var _islandSpans: ({})
    function islandSpan(id, screenName, x0, x1) {
        const k = id + "@" + screenName
        const old = root._islandSpans[k]
        if (old && old.x0 === x0 && old.x1 === x1) return
        root._islandSpans[k] = { x0: x0, x1: x1 }
    }
    function _spanOf(id, screenName) {
        const own = root._islandSpans[id + "@" + screenName]
        if (own) return own
        for (const k in root._islandSpans) if (k.startsWith(id + "@")) return root._islandSpans[k]
        return null
    }
    // Would islands `a` and `b` cover each other, both open (a on `screenA`, b where it is)?
    function _islandsClash(a, b, screenA) {
        if (a === b || Islands.rowOf(a) !== Islands.rowOf(b)) return false
        const sa = screenA ?? "", sb = root.islandScreenOf(b)
        if (sa !== "" && sb !== "" && sa !== sb) return false
        if (Islands.hOf(a) === "center" || Islands.hOf(b) === "center") return true
        const scr = sa !== "" ? sa : sb
        const pa = root._spanOf(a, scr), pb = root._spanOf(b, scr)
        return !!pa && !!pb && pa.x0 < pb.x1 && pb.x0 < pa.x1
    }
    // The bar's plain columns an island of the top row covers: the middle covers all three, a side its own
    // column and the middle one (the launcher, an update, a placed panel). The bottom row covers none.
    function _islandColumns(id) {
        if (Islands.rowOf(id) !== "top") return []
        const h = Islands.hOf(id)
        return h === "center" ? ["left", "right", "center"] : [h, "center"]
    }
    function _columnOpen(col) {
        return col === "left" ? root.leftKey !== "" : col === "right" ? root.rightKey !== ""
             : root.centerKey !== "" || root.launcherOpen || root.updateOpen
    }
    function _closeColumn(col) {
        if (col === "left") { if (root.leftKey !== "") root.leftKey = ""; return }
        if (col === "right") { if (root.rightKey !== "") root.rightKey = ""; return }
        if (root.centerKey !== "") root.centerKey = ""
        if (root.launcherOpen) root.launcherOpen = false
        // Only the view goes: the run is the Updates service's and the update pill shows it again.
        if (root.updateOpen) root.updateOpen = false
    }
    // Opening this island by the pointer would close something kept on purpose: a pinned island it covers, or
    // a plain column. A rest on its handle on the way past must not do that; a click still does.
    function islandBlocked(id, screenName) {
        for (const k in root.islandSet)
            if (root.islandSet[k].pinned && root._islandsClash(id, k, screenName)) return true
        return root._islandColumns(id).some(c => root._columnOpen(c))
    }

    // Opens island `id` (`o`: { screen, page, pinned, part }), closing what it would cover.
    function openIsland(id, o) {
        if (!Islands.SIDES.includes(id)) return
        const opt = o ?? {}
        const scr = opt.screen ?? ""
        const old = root.islandSet[id]
        const next = {}
        for (const k in root.islandSet)
            if (k !== id && !root._islandsClash(id, k, scr)) next[k] = root.islandSet[k]
        next[id] = {
            pinned: opt.pinned === true || (old?.pinned === true && (old?.screen ?? "") === scr),
            screen: scr,
            page: opt.page ?? "",
            part: opt.part ?? ""
        }
        root.islandLast = id
        root.islandSet = next
        for (const c of root._islandColumns(id)) root._closeColumn(c)
    }
    function closeIsland(id) {
        if (root.islandSet[id] === undefined) return
        const next = Object.assign({}, root.islandSet)
        delete next[id]
        root.islandSet = next
    }
    function closeIslands() { if (root.islandOpen) root.islandSet = ({}) }
    function _closeIslandsWhere(test) {
        const next = {}
        let changed = false
        for (const k in root.islandSet) { if (test(k)) changed = true; else next[k] = root.islandSet[k] }
        if (changed) root.islandSet = next
    }
    function setIslandPinned(id, pinned) {
        const cur = root.islandSet[id]
        if (!cur || cur.pinned === pinned) return
        const next = Object.assign({}, root.islandSet)
        next[id] = Object.assign({}, cur, { pinned: pinned })
        root.islandSet = next
    }
    // Forgets an opening's one-off page, so the island shows the remembered one from now on.
    function _clearIslandPage(id) {
        const cur = root.islandSet[id]
        if (!cur || cur.page === "") return
        const next = Object.assign({}, root.islandSet)
        next[id] = Object.assign({}, cur, { page: "" })
        root.islandSet = next
    }

    // An island's pages, in rail order (islandLayout). An island with none has no handle.
    function islandPagesOf(side) { return root.islandLayout.rails[side] || [] }
    // Whether a row has an island with pages: the other row's cards are then fitted into half the screen.
    function islandRowPresent(row) {
        return Config.island && Islands.SIDES.some(s => Islands.rowOf(s) === row && root.islandPagesOf(s).length > 0)
    }
    // The page each island but the middle was last on, this session ({ id: page }); the middle's is Config.islandTab.
    property var islandTabs: ({})
    // The page an island shows: the one asked for, else the one it was on, else its first.
    function islandWanted(side) {
        const pages = root.islandPagesOf(side)
        const asked = root.islandPageOf(side)
        if (pages.indexOf(asked) >= 0) return asked
        const kept = side === "center" ? Config.islandTab : (root.islandTabs[side] || "")
        return pages.indexOf(kept) >= 0 ? kept : (pages[0] || "")
    }
    // A Dashboard tile's jump to another page: on the island it was pressed on when that rail has it, else the
    // island that does (the card hands over: the one it came from closes); a page on no rail goes nowhere.
    function islandGo(page) {
        const rail = Islands.railOf(page, root.islandLayout)
        if (rail === "") return
        const from = root.islandLast
        if (rail === from && root.islandIsOpen(from)) { root.islandPick(rail, page); return }
        const cur = root.islandSet[from]
        root.openIsland(rail, { screen: cur?.screen ?? "", page: page, pinned: cur?.pinned === true })
        if (from !== rail) root.closeIsland(from)
    }
    function islandPick(side, page) {
        root._clearIslandPage(side)
        if (side === "center") { Config.islandTab = page; return }
        const next = Object.assign({}, root.islandTabs)
        next[side] = page
        root.islandTabs = next
    }

    // `qs ipc -c ~/.config/quicktest call island toggle`      … call island show media
    property var _islandIpc: IpcHandler {
        target: "island"

        // The middle island (the others open from their handles, their buttons, or `show`).
        function toggle(): void {
            if (root.islandIsOpen("center")) root.closeIsland("center")
            else root.openIsland("center", {})
        }
        function open(): void { root.openIsland("center", {}) }
        // Every island.
        function close(): void { root.closeIslands() }
        // Open on a page (today | media | system | weather, wifi, bluetooth, clock, desk, timer…) on whichever
        // island's rail has it. One on no rail opens the middle island on the page it was on.
        function show(page: string): void {
            const rail = Islands.railOf(page, root.islandLayout)
            root.openIsland(rail !== "" ? rail : "center", { page: page })
        }
        // …and on a part of it, pinned: `part wallpaper engine` (images | engine | material),
        // `part colorScheme library` (edit | slots | library | album), `part equalizer devices` (apps | devices | mic | options).
        function part(page: string, sub: string): void {
            const rail = Islands.railOf(page, root.islandLayout)
            root.openIsland(rail !== "" ? rail : "center", { page: page, part: sub, pinned: true })
        }
    }

    // ── Desktop menu ──────────────────────────────────────────────────────────
    // Right-click the desktop (modules/desktop/DeskMenu). Transient. Opens on the screen that was
    // clicked at the pointer; a key (-1, -1) opens it in the middle of the focused one.
    property bool   deskMenuOpen: false
    property string deskMenuScreen: ""
    property real   deskMenuX: -1
    property real   deskMenuY: -1
    function openDeskMenu(screenName, x, y) {
        root.deskMenuScreen = screenName
        root.deskMenuX = x
        root.deskMenuY = y
        root.deskMenuOpen = true
    }

    // `qs ipc -c ~/.config/quicktest call deskmenu toggle`
    property var _deskMenuIpc: IpcHandler {
        target: "deskmenu"

        function toggle(): void {
            if (root.deskMenuOpen) root.deskMenuOpen = false
            else root.openDeskMenu("", -1, -1)
        }
        function open(): void { root.openDeskMenu("", -1, -1) }
        function close(): void { root.deskMenuOpen = false }
    }

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
        root.closeIslands()
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
        // A page on an island's rail opens there instead (2026-11-15): the sidebar's own on the bottom row, one
        // that lives on a top rail up there. Beside the button only for what is on no rail (the voice panel,
        // the hover cards, the clips' target and peek).
        const rail = root._rail(key)
        if (rail !== "") {
            const scr = screen ?? root._hereScreen()
            if (root.sidePanel === key) root.sidePanel = ""
            // What it opened on (the voice page: the person right-clicked) still counts on an island.
            root.sidePanelArg = arg ?? ""
            root._showIsland(rail, root._railPage(key), scr?.name ?? "")
            return
        }
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
        if (root._rail(key) !== "") {
            if (root.sideShows(key, screen ?? root._hereScreen())) root.closeIsland(root._rail(key))
            else root.openSidePanel(key, from, screen, arg)
            return
        }
        if (root.sidePanel === key && root.sidePanelFrom === from
            && root.sidePanelScreen === (screen ?? root._hereScreen()) && root.sidePanelArg === (arg ?? ""))
            root.closeSidePanel()
        else root.openSidePanel(key, from, screen, arg)
    }
    function closeSidePanel() { root.sidePanel = "" }
    // Whether a sidebar button's panel is showing for the sidebar on `screen`: beside it, or as its island's page
    // on that screen (an island opened by a key, with no screen, counts for the first one).
    function sideShows(key, screen) {
        const rail = root._rail(key)
        const first = screen === Quickshell.screens[0]
        if (rail !== "") {
            if (!root.isOpen(key)) return false
            const at = root.islandScreenOf(rail)
            return at !== "" ? at === (screen?.name ?? "") : first
        }
        const owns = root.sidePanelScreen ? root.sidePanelScreen === screen : first
        return root.sidePanel === key && owns
    }
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
    // binds `currentKey` to Config.settingsPage but its own showPage() ASSIGNS to
    // currentKey, which destroys that binding the first time you click the rail.
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
    // The anchor of the settings page on show ("" when its key has none). A page key is
    // `file` or `file#anchor` (SettingsIndex.keyOf); a file holding several rail rows reads
    // this to show the right part, and moving between them never reloads it. Written only
    // by SettingsCard.
    property string settingsAnchor: ""
    // A deep link INTO a page: the card or row a search result named ({ section, title,
    // kind }), and a counter so asking for the same target twice still fires. SettingsCard
    // sets it as it navigates (search results, an aliasPlate link) and clears it on any
    // other move; SettingsPage.reveal() scrolls to it, flashes it and clears it. null means
    // nothing to reveal. Set BEFORE the page loads, so the card can skip the cascade for it.
    property var settingsTarget: null
    property int settingsTargetNav: 0

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

    // Pages that are a module in Bar › Modules now: opening one opens that
    // page with the module picked, so the dock's "Settings" and the stats button's
    // right-click still land on the dock's and the stats' settings.
    readonly property var _moduleOfPage: ({ "DockPage.qml": "dock", "SidebarStatsPage.qml": "stats" })
    function openSettingsTo(file) {
        // Keyed on the bare file: a `#anchor` names a part of a page, not a module.
        const m = root._moduleOfPage[String(file).split("#")[0]]
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

    // ── What under the bar may be open together ───────────────────────────────
    // The bar's plain columns keep their old rule among themselves: one at a time, the middle column's own three
    // (a placed panel, the launcher, an update run) in the order BarPanelDock's centre Accordion gives them.
    // Against the islands they follow the islands' rule (2026-11-15): a column closes the top-row islands that
    // would cover it (its own side's and the middle one; the middle column all three), and an island closes the
    // columns it covers (openIsland). The bottom row stands clear of the columns.
    // The sidebar's panel is not part of this: it has its own rule beside the two keys above.
    readonly property bool anyBarIsland: root.leftKey !== "" || root.rightKey !== "" || root.centerKey !== ""
                                         || root.launcherOpen || root.updateOpen
    function _soleIsland(keep) {
        for (const c of ["left", "right", "center"]) if (c !== keep) root._closeColumn(c)
        root._closeIslandsWhere(id => root._islandColumns(id).includes(keep))
    }
    Connections {
        target: root
        function onLeftKeyChanged()         { if (root.leftKey   !== "") root._soleIsland("left") }
        function onRightKeyChanged()        { if (root.rightKey  !== "") root._soleIsland("right") }
        function onCenterKeyChanged()       { if (root.centerKey !== "") root._soleIsland("center") }
        function onLauncherOpenChanged()    { if (root.launcherOpen)     root._soleIsland("center") }
        // System update on a rail is an island page: its request opens that island, and it is not the middle
        // column (which would close the island it stands on).
        function onUpdateOpenChanged()      { if (root.updateOpen && root._rail("update") === "") root._soleIsland("center") }
        function onUpdateRequestIdChanged() {
            const rail = root._rail("update")
            if (rail !== "") { if (!root.isOpen("update")) root._showIsland(rail, "update") }
            else root._soleIsland("center")
        }
    }

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
    // The status bar out of the way (Config.barHidden owns the flag; barExtent follows it). Panels and
    // islands that hang from the bar close with it, so none is left standing under nothing.
    function setBarHidden(hide) {
        if (hide) root.closeAllPanels()
        Config.barHidden = hide
    }
    // `qs ipc -c ~/.config/quicktest call statusbar toggle|show|hide`
    property var _statusbarIpc: IpcHandler {
        target: "statusbar"

        function toggle(): void { root.setBarHidden(!Config.barHidden) }
        function show(): void   { root.setBarHidden(false) }
        function hide(): void   { root.setBarHidden(true) }
    }

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
