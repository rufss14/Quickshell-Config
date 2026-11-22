pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/wallpaperentry.js" as WEntry
import "wallpaper"
import "../../services/wallpaperlib.js" as Lib

// ── WallpaperPanel ────────────────────────────────────────────────────────────
// The wallpaper gallery — BOTH libraries, the same two the settings page carries:
// static images (the pywal theming pipeline) and Steam Workshop scenes rendered
// by linux-wallpaperengine.
//
// ── One gallery, two sources, three views ─────────────────────────────────────
// Picking an animated wallpaper shouldn't mean opening Settings, a full-screen window
// for the one thing this panel exists for. So it carries the page's own jobs at panel scale: `gallery` (pick one), `browse` (the
// in-panel file browser that imports images), and `settings` (the renderer's dozen
// launch options). The source switch sits in the search row rather than the header,
// which is already carrying four controls at this width.
//
// ── 340px is the whole design constraint ──────────────────────────────────────
// Every layout choice here is paying for vertical space. Status PROSE goes in the
// header's subtitle (see `headerNote`) and status BUTTONS go in the header's action
// row, because a strip under the gallery costs ~38px — a third of a thumbnail rank —
// and clipped the bottom row of wallpapers to say one sentence.
//
// Delegates branch on the ENTRY's shape (string = image path, object = scene or the
// action card), never on the source flag. During a tab switch the flag flips while
// the outgoing tiles still exist for a frame, and a string entry asked for `.id`
// warns once per tile — the same trap WallpaperPage documents.
//
// ── The action card is the FIRST TILE, not a bar under the gallery ────────────
// The settings page can afford a full-width BigAction below its pager; 340px of
// panel cannot — a row there costs a whole rank of thumbnails. "Add images" and
// "Browse the Workshop" therefore live in the first cell of the grid (and the first
// row of the list), which is space the library was using anyway and reads as one
// more thing you can pick.
//
// ── All logic lives in the Wallpaper / WallpaperEngine services ───────────────
// No `Process` here: a pipeline owned by the panel dies when the panel closes mid-apply,
// leaving the palette half-written. The pipeline is `scripts/apply-wallpaper.sh`, driven by the
// `Wallpaper` singleton, and this file only shows things and calls functions.
//
// ── Progress is shown, not hidden in /tmp ─────────────────────────────────────
// Applying repaints fourteen applications and takes seconds. A log in /tmp and an
// "applied!" that shows even when steps failed is how GTK theming once stayed broken
// for a month unnoticed. The service parses a step protocol
// and this renders it live, including which steps failed. Scenes have no step protocol —
// they have a stop → start → verify phase — so the same pane reports the phase instead.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    // Reached by the view files in wallpaper/.
    property alias browseComponent: browseComponent
    property alias bulkLatch: bulkLatch
    property alias effectsComponent: effectsComponent
    property alias materialComponent: materialComponent
    property alias propertiesComponent: propertiesComponent
    property alias searchInput: searchInput
    property alias settingsComponent: settingsComponent

    // BarPanelDock PINS the wallpaper gallery (wallpaperPanelWidth ×
    // wallpaperPanelHeight) regardless of what this file asks for — it is a
    // thumbnail grid and self-sizing to content made it worse. Declared to
    // match, rather than asking for a size that will be ignored.
    // ── As an island page ─────────────────────────────────────────────────────
    // The same panel, laid out for the island's width (IslandCard): no title row, no outer padding
    // (the rail names it, the card has its gutter). A column on the LEFT (`sideCol`) holds what is
    // on screen at 16:9 (WallpaperNow), the three sources as cards (WallpaperSources, in place of
    // the tab strip) and the library's tools; the search and the gallery take the full height on
    // the right. The bar panel's own header, tab strip and hero strip are not shown.
    property bool island: false
    readonly property int sideW: Math.round(root.width * 0.4)
    implicitWidth:  620
    implicitHeight: 394

    // ── One accent with the media panel ───────────────────────────────────────
    // This panel wore `info` (a muted ramp colour) while the media panel wears the accent its
    // visualiser module resolves to (`focus` unless you chose another), so the two headers sat
    // side by side in different colours. It now asks for the SAME thing the media panel does,
    // and every highlight in here — header, chips, switch, ring, badges — follows it.
    readonly property color accent: Config.moduleAccent("visualizer", Colors.of(QsWindow.window).primary)

    // ── Choosing workspaces: the gallery folds into the picker ────────────────
    // A click with Choose workspaces on makes the picture `Wallpaper.pending`. The
    // gallery fades and folds away under the header (`swapped`, a fast motion later —
    // out, then in, never both), the card shrinks around the title and the picker
    // (components/WorkspacePicker), and BarPanelDock lets go of the fixed pin for it
    // (`pinnedHeight`). `choosingPic` is held for the fold back out.
    readonly property bool choosing: Wallpaper.pending !== ""
    property string choosingPic: ""
    onChoosingChanged: {
        root.popover = ""
        if (root.choosing) root.choosingPic = Wallpaper.pending
        swapBeat.restart()
    }
    property bool swapped: false
    Timer {
        id: swapBeat
        interval: Math.max(1, Motion.fast)
        onTriggered: {
            root.swapped = root.choosing
            if (root.swapped) Qt.callLater(() => picker.forceActiveFocus())
        }
    }
    readonly property real pinnedHeight: root.swapped
        ? Math.ceil(head.implicitHeight + picker.implicitHeight + Tokens.spacingMd + Tokens.spacingLg * 2)
        : 0

    property bool listView: false


    // "images" | "engine"
    property string source: "images"
    readonly property bool isImages: root.source === "images"

    // "gallery" | "browse" | "settings" | "properties" | "material" | "effects"
    //   material   — the Material Wallpaper's own tab: one wallpaper, drawn live, and its style.
    //                A THIRD tab beside Images and Scenes, but a view rather than a `source`: it has
    //                no library, no search and no thumbnails, so every gallery branch on `source`
    //                stays as it was and simply isn't shown (they all wait on view === "gallery").
    //   browse     — the in-panel file browser; images only
    //   settings   — the renderer's launch options; engine only
    //   properties — one scene's author-defined sliders/colours/etc.
    //   effects    — the wallpaper moved by the music (wallpaper/WallpaperEffects.qml)
    property string view: "gallery"
    readonly property bool isMaterial: root.view === "material"
    // The tab the switch shows, and what the body slides on.
    readonly property string tab: root.isMaterial ? "material" : root.source
    // The one way to change tab: "images" | "engine" | "material". While a scene is being assigned
    // to a monitor only Scenes can be shown.
    function pickSource(v) {
        if (root.pickingActive && v !== "engine") return
        if (v === "material") { root.view = "material"; return }
        if (v !== "images" && v !== "engine") return
        root.view = "gallery"
        root.source = v
    }

    // One scene being customised — set by a tile's "Tune" hover action.
    property string propertiesForId: ""

    function openProperties(id) {
        if (!id) return
        root.propertiesForId = id
        root.view = "properties"
        WallpaperEngine.loadPropertySchema(id)
        WallpaperEngine.loadOverridesFor(id)
    }

    // ── The renderer's state is POLLED, so hold the poll while open ───────────
    // An external process has nothing to subscribe to. Refcounted in the service;
    // this panel is destroyed by PanelHost's Loader when the accordion closes
    // (`active: activeKey !== ""`), so onCompleted/onDestruction is the whole
    // lifetime. Held on both tabs, not just the engine one: the images tab needs
    // `running` to know that no image is currently on screen.
    Component.onCompleted: {
        WallpaperEngine.acquire()
        // Opened on a part of the page (`qs ipc … call island part wallpaper engine`).
        if (root.island && UiState.islandPartFor("wallpaper") !== "") root.pickSource(UiState.islandPartFor("wallpaper"))
    }
    Component.onDestruction: {
        WallpaperEngine.release()
        if (Wallpaper.pending !== "") Wallpaper.cancelPick()     // closed mid-choice: nothing chosen
    }

    // A running scene covers the static wallpaper completely, so while the renderer
    // is up no image is "current" — it's the underlay you'd get back.
    readonly property bool sceneOnScreen: WallpaperEngine.running

    // Gamemode stopping the renderer looks identical to "nothing is running" to
    // every check above — sceneOnScreen goes false either way. Without this, the
    // panel falls back to treating the static image underneath as "current",
    // which is exactly what WallpaperView's own takeover card exists to NOT show
    // on screen. Gate every "no scene → show the image instead" branch on this
    // too, so the panel never claims something is active that isn't.
    readonly property bool gamePaused: Gamemode.wallpaperPaused
    // The mode already ended but the relaunch it kicked off hasn't landed yet —
    // gamePaused stays true through that (see Gamemode.wallpaperPaused), but
    // "Paused for Game Mode" would be wrong, not just stale, once it's actually off.
    readonly property bool gameRestoring: Gamemode.wallpaperRestoring


    // Whether the library drawer is open under the search ("" | "library"; the options chip, Escape, or leaving
    // the gallery closes it).
    property string popover: ""
    // The part of the Material picture its Shapes plate is choosing a form for, while the pointer is on that plate
    // ("" = none): the preview dims the rest. WallpaperMaterial sets it; WallpaperNow and the bar panel's preview read it.
    property string materialSlot: ""
    // Something is moving the wallpaper: parallax on a picture or a scene, or the music.
    readonly property bool motionOn: Config.wallParallax || Config.wpeParallax || Config.wallFx

    // ── Rescan: spin the button, bust the thumbnail cache ────────────────────
    // A rescan for images is a fast `find`, so the button is latched spinning for
    // a beat regardless. `_previewNonce` is appended to every thumbnail URL as a
    // #fragment (ignored by the file loader, but a new cache key), so a rescan
    // also reloads previews whose file changed under the same name.
    property int  _previewNonce:   0
    property bool _rescanSpinning:  false
    property real _rescanPhase:     0
    Timer { id: _rescanSpinTimer; interval: 850; onTriggered: root._rescanSpinning = false }
    NumberAnimation {
        target: root; property: "_rescanPhase"
        from: 0; to: 360; duration: Motion.spin
        loops: Animation.Infinite
        running: root._rescanSpinning
    }
    function doRescan() {
        root._previewNonce++
        root._rescanSpinning = true
        _rescanSpinTimer.restart()
        if (root.isImages) Wallpaper.rescan()
        else               WallpaperEngine.rescan()
    }
    function bust(url) {
        return (url !== "" && root._previewNonce > 0)
            ? url + "#r" + root._previewNonce : url
    }

    // ── What's on screen right now — the hero strip's subject ─────────────────
    // A running scene wins over the static image (it covers it); a scene's still
    // is its Workshop preview, the same frame the palette is derived from.
    //
    // `WallpaperEngine.current` is parsed from the running renderer's command
    // line and is briefly "" right after the panel opens (before the first
    // probe). `Config.wpeCurrent` — the id we asked for — is the stable fallback,
    // so the hero shows the scene's picture instead of a blank box.
    // Gamemode's stop() never touches Config.wpeCurrent, so it's still the right
    // id to name here — same fallback the sceneOnScreen branch already trusts.
    readonly property string heroSceneId: (root.sceneOnScreen || root.gamePaused)
        ? (WallpaperEngine.current !== "" ? WallpaperEngine.current : Config.wpeCurrent)
        : ""
    readonly property var heroSceneItem:
        root.heroSceneId !== "" ? WallpaperEngine.itemFor(root.heroSceneId) : null

    // The Material Wallpaper is what is on screen (a scene covers it, and a pause hides it).
    readonly property bool materialOnScreen: Config.wallMaterial && !root.sceneOnScreen && !root.gamePaused

    readonly property string heroName:
        root.materialOnScreen ? "Material Wallpaper"
        : root.gamePaused ? (root.heroSceneId !== ""
            ? WallpaperEngine.titleFor(root.heroSceneId)
            : (root.gameRestoring ? "Resuming Your Wallpaper" : "Paused for Game Mode"))
        : root.sceneOnScreen ? WallpaperEngine.titleFor(root.heroSceneId)
        : Wallpaper.current
    // The paused scene's own still, same as the sceneOnScreen branch — showing
    // it dimmed (see the overlay in heroThumb below) says "this is what's
    // paused" without claiming it's actually on screen right now. Only the
    // static-image fallback is skipped while paused: Wallpaper.currentPath is
    // the underlay you'd see if the scene weren't there, and claiming THAT'S
    // current would be the same false state the gallery checkmarks already
    // guard against above.
    readonly property string heroSource: {
        if (root.sceneOnScreen || root.gamePaused) {
            const prev = root.heroSceneItem && root.heroSceneItem.preview
                ? root.heroSceneItem.preview : ""
            return prev !== "" ? "file://" + prev : ""
        }
        // Material draws itself in the thumbnail (heroThumb); no picture stands for it.
        if (root.materialOnScreen) return ""
        return Wallpaper.currentPath !== "" ? "file://" + Wallpaper.currentPath : ""
    }
    // "Paused" on its own reads fine next to a known scene's title; the no-scene
    // case already says the full phrase on the name line above, so this line
    // doesn't need to repeat it.
    readonly property string heroKind:
        root.gamePaused      ? (root.gameRestoring ? "Resuming" : "Paused")
        : root.sceneOnScreen ? (root.heroSceneItem ? root.heroSceneItem.type : "scene") : ""

    // Where the shell's colours are coming from RIGHT NOW — the wallpaper→theme
    // link stated in words. The album cover wins over everything while it's active
    // (it's an overlay on Colors, not a file write), so it's checked first — and
    // regardless of reach: shell-only is the default, `systemWide` is not the test.
    // A held scheme also overrides the wallpaper; "theming off" means the picture
    // changed and nothing else did.
    readonly property string heroThemeSource: {
        if (!Config.wallTheming) return "Theming off"
        if (AlbumScheme.active) return "Colours from the album cover"
        if (root.sceneOnScreen)
            return Config.wpeScenePalette ? "Colours from the scene"
                                          : "Colours unchanged"
        if (ColorScheme.overrideCount > 0) return "Colours from a saved scheme"
        // Material is drawn FROM the palette; the palette is still the last picture's.
        if (root.materialOnScreen) return "Colours from the last picture"
        return "Colours from this wallpaper"
    }

    readonly property int libraryCount: root.isImages
        ? Wallpaper.wallpapers.length
        : WallpaperEngine.items.length

    readonly property bool scanning: root.isImages
        ? Wallpaper.scanning
        : WallpaperEngine.scanning

    // Whichever library is on show, through the search box, the filter and the sort. The logic is in
    // services/wallpaperlib.js (`bun scripts/test-wallpaperlib.js`); the action card is added after it,
    // so it is never filtered or sorted away. Both filters are the panel's alone and reset with the
    // source (the kinds differ); the sort is a preference (`Config.wallSort`).
    property bool   favOnly:    false
    property string kindFilter: "all"
    readonly property var filterOpts: ({
        images: root.isImages, search: searchInput.text, kind: root.kindFilter, favOnly: root.favOnly,
        favs: root.isImages ? Config.wallFavorites : Config.wpeFavorites,
        sort: Config.wallSort, mtimes: Wallpaper.mtimes, colors: WallColors.map
    })
    // The colour reading (WallColors) while this panel is open: the sort and the swatches want it.
    Binding { target: WallColors; property: "wanted"; value: true }
    readonly property int activeFilters: Lib.activeFilters(root.filterOpts)
    readonly property var filtered:
        Lib.filterSort(root.isImages ? Wallpaper.wallpapers : WallpaperEngine.items, root.filterOpts)

    // ── The action card ───────────────────────────────────────────────────────
    // What WallpaperActionCard shows (its glyph and words); `runAction` is what it does.
    //
    // Still a Nerd Font `glyph`, not a `symbol`: the Workshop card wears the Steam
    // mark (󰓓), which Material Symbols has no equivalent for, and "add" reads
    // better as the same weight as its neighbour than as the one migrated icon.
    readonly property var actionEntry: root.isImages
        ? ({ action: "add",    glyph: "󰋺", title: "Add images",
             caption: Translation.tr("Copy pictures in from any folder") })
        : ({ action: "browse", glyph: "󰓓", title: "Browse the Workshop",
             caption: Translation.tr("Subscribe on Steam, then rescan") })

    // The action card rides in the model as the FIRST entry, so a delegate reads its glyph and words off
    // the entry like it reads a wallpaper's — no "is this index 0" case in the grid or the list.
    readonly property var galleryModel: [root.actionEntry].concat(root.filtered)

    function runAction(kind) {
        if (kind === "add") root.view = "browse"
        else                WallpaperEngine.openWorkshopHub()
    }

    // ── The keyboard ──────────────────────────────────────────────────────────
    // BarPanelDock hands a panel the keys its focus owner didn't take (`handleKey`) and Escape
    // (`handleEscape`, true = used). `kbIndex` is a place in `galleryModel` (the library, in the order shown);
    // `kbOn` is whether the cursor shows: a key shows it, the pointer moving hides it. The entry under it is
    // a WallpaperEntry like any tile's, so Enter does exactly what a click does.
    property int  kbIndex: 0
    property bool kbOn: false
    // Tiles across: the bar's panel three, an island page two (WallpaperPanelBody's grid).
    readonly property int gridCols: root.island ? 2 : 3
    // The canvas round a picture on an island's card (WallpaperCard), which the grid's cell height allows for.
    readonly property real cardMat: Tokens.spacingSm + Tokens.spacingXs
    readonly property int kbCols: root.listView ? 1 : root.gridCols
    WallpaperEntry { id: kbEntry; panel: root; entry: root.galleryModel[root.kbIndex] }
    HoverHandler { onPointChanged: root.kbOn = false }
    onGalleryModelChanged: {
        if (root.kbIndex >= root.galleryModel.length) root.kbIndex = Math.max(0, root.galleryModel.length - 1)
    }

    // The hero's click: put the keyboard cursor on the wallpaper that is applied (a scene's id, a picture's
// name) and scroll to it.
function revealCurrent() {
    if (root.view !== "gallery") return
    const cur = root.sceneOnScreen ? WallpaperEngine.current : Wallpaper.current
    const at = root.galleryModel.findIndex(e => {
        const d = WEntry.describe(e)
        return root.sceneOnScreen ? d.key === cur : d.name === cur
    })
    if (at >= 0) root.kbMove(at)
}
function kbMove(to) {
        const n = root.galleryModel.length
        if (n === 0) return
        root.kbIndex = Math.max(0, Math.min(n - 1, to))
        root.kbOn = true
        if (root.listView) body.list.positionViewAtIndex(root.kbIndex, ListView.Contain)
        else               body.grid.positionViewAtIndex(root.kbIndex, GridView.Contain)
    }
    // The first arrow shows the cursor where it is (the first wallpaper, not the action card); the rest move it.
    function _kbStep(delta) {
        if (!root.kbOn) { root.kbMove(root.galleryModel.length > 1 && root.kbIndex === 0 ? 1 : root.kbIndex); return }
        root.kbMove(root.kbIndex + delta)
    }
    function handleKey(e) {
        // Ctrl+V adds what the clipboard holds to the library, on every tab and view (the drop's twin).
        if (e.key === Qt.Key_V && (e.modifiers & Qt.ControlModifier) && !(e.modifiers & (Qt.AltModifier | Qt.MetaModifier))) {
            Wallpaper.pasteFromClipboard(false)
            return true
        }
        if (e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return false
        // The sub-views, the progress pane and the workspace picker keep their own keys.
        if (root.view !== "gallery" || root.showProgress || root.choosing) return false
        const k = e.key
        const rows = Math.max(1, Math.floor(root.listView ? body.list.height / 52 : body.grid.height / Math.max(1, body.grid.cellHeight)))
        if (k === Qt.Key_Slash) { root.popover = ""; searchInput.forceActiveFocus(); return true }
        if (k === Qt.Key_A)     { root.runAction(root.actionEntry.action); return true }
        if (k === Qt.Key_Right && !root.listView) { root._kbStep(1);             return true }
        if (k === Qt.Key_Left  && !root.listView) { root._kbStep(-1);            return true }
        if (k === Qt.Key_Down)     { root._kbStep(root.kbCols);                  return true }
        if (k === Qt.Key_Up)       { root._kbStep(-root.kbCols);                 return true }
        if (k === Qt.Key_PageDown) { root._kbStep(root.kbCols * rows);           return true }
        if (k === Qt.Key_PageUp)   { root._kbStep(-root.kbCols * rows);          return true }
        if (k === Qt.Key_Home)     { root.kbMove(0);                             return true }
        if (k === Qt.Key_End)      { root.kbMove(root.galleryModel.length - 1);  return true }
        if (k === Qt.Key_S && !root.galleryEmpty) { root.selecting ? root.endSelect() : root.selecting = true; return true }
        if (k === Qt.Key_L)        { root.listView = !root.listView;             return true }
        if (!root.kbOn) return false
        if (k === Qt.Key_Return || k === Qt.Key_Enter)  { kbEntry.doApply();   return true }
        if (k === Qt.Key_Space && root.selecting)       { kbEntry.doApply();   return true }
        if (k === Qt.Key_F)                             { kbEntry.toggleFav(); return true }
        return false
    }
    // Escape closes what is nearest first, and only then the panel.
    function handleEscape() {
        if (root.popover !== "")      { root.popover = ""; return true }
        if (root.choosing)            { Wallpaper.cancelPick(); return true }
        if (root.pickingActive)       { root.pickingForScreen = ""; root.pickingScreens = []; return true }
        if (root.selecting)           { root.endSelect(); return true }
        if (root.view !== "gallery" && !root.isMaterial) { root.view = "gallery"; return true }
        if (searchInput.text !== "")  { searchInput.text = ""; return true }
        if (root.kbOn)                { root.kbOn = false; return true }
        return false
    }

    // One gate for "an apply is in flight", whichever pipeline is running it.
    readonly property bool applyBusy: root.isImages
        ? Wallpaper.applying
        : WallpaperEngine.busy

    // Non-empty when this source can't apply anything at all — the engine when the
    // renderer isn't installed, and either source when pywal is missing (the whole
    // theming pipeline needs it). The tiles go inert and say why rather than
    // starting a run that takes seven seconds to fail.
    readonly property string blocked:
        Wallpaper.pywalBlocker() || (root.isImages ? "" : WallpaperEngine.blocker())

    function applyEntry(entry) {
        if (!entry) return
        if (root.pickingActive) {
            const d = WEntry.describe(entry)
            if (d.kind !== "scene") return
            if (root.pickingScreens.length > 0) WallpaperEngine.spanMonitors(root.pickingScreens, d.key)
            else                                 WallpaperEngine.assignMonitor(root.pickingForScreen, d.key)
            root.pickingForScreen = ""
            root.pickingScreens = []
            return
        }
        if (root.applyBusy || root.blocked !== "") return
        if (typeof entry === "object") Wallpaper.pickScene(entry.id ?? "")
        else                           Wallpaper.pick(String(entry))
    }

    // A source switch changes what every view means, so it always lands back on the
    // gallery. The models swap under both views at the same time; without the reset
    // the new library opens scrolled to wherever the old one was left.
    onSourceChanged: {
        root.favOnly = false
        root.kindFilter = "all"
        root.kbOn = false
        root.kbIndex = 0
        root.endSelect()
        root.view = "gallery"
        body.grid.positionViewAtBeginning()
        body.list.positionViewAtBeginning()
    }

    // ── Select mode: bulk delete ──────────────────────────────────────────────
    // While `selecting`, a click on a tile or row ticks it instead of applying it, and the
    // bar at the bottom deletes every tick at once (armed first, like the single ✕).
    // `selected` holds each entry's `key` — an image's path, a scene's Workshop id — the
    // same value WEntry.describe hands the delegates. Ended by anything that swaps the
    // library under it (the tab, the view), so a stale tick can never be deleted.
    property bool selecting: false
    property var  selected: []
    readonly property var selectableKeys: root.filtered.map(e => root.isImages ? e : e.id)
    readonly property bool allSelected: root.selected.length > 0
        && root.selected.length === root.selectableKeys.length

    function isSelected(k) { return root.selected.indexOf(k) !== -1 }
    function toggleSelect(k) {
        if (k === "") return
        root.selected = root.isSelected(k)
            ? root.selected.filter(x => x !== k)
            : root.selected.concat([k])
    }
    function toggleSelectAll() {
        root.selected = root.allSelected ? [] : root.selectableKeys.slice()
        bulkLatch.disarm()
    }
    function endSelect() {
        root.selecting = false
        root.selected = []
        bulkLatch.disarm()
    }
    function deleteSelected() {
        const keys = root.selected.slice()
        if (keys.length === 0) return
        if (root.isImages) Wallpaper.removeMany(keys)
        else               WallpaperEngine.removeAndUnsubscribeMany(keys)
        root.endSelect()
    }
    ArmLatch { id: bulkLatch; onConfirmed: root.deleteSelected() }

    // ── The in-panel image browser ────────────────────────────────────────────
    // The page's browser, at panel scale. `browseFolder` is where it's pointed;
    // `picked` is the set of file PATHS ticked for import, cleared whenever the
    // browser closes so a stale selection can't be imported later by accident.
    property url browseFolder: "file://" + Quickshell.env("HOME")
    property var picked: []

    function isPicked(p) { return root.picked.indexOf(p) !== -1 }
    function togglePick(p) {
        root.picked = root.isPicked(p)
            ? root.picked.filter(x => x !== p)
            : root.picked.concat([p])
    }

    onViewChanged: {
        root.popover = ""
        if (root.view !== "gallery") root.endSelect()
        if (root.view !== "browse") root.picked = []
        // Leaving the gallery any other way than completing a pick abandons it.
        if (root.view !== "gallery" && root.pickingActive) {
            root.pickingForScreen = ""
            root.pickingScreens = []
        }
    }

    // ── Assigning a scene to one (or several, spanned) monitors ───────────────
    // Set from the settings view's Monitors section; a tile's click then calls
    // WallpaperEngine.assignMonitor()/spanMonitors() instead of the normal
    // apply() — see WallpaperEntry.doApply() / applyEntry().
    property string pickingForScreen: ""
    property var    pickingScreens:   []
    property bool   monitorSpanMode:  false
    readonly property bool pickingActive:
        root.pickingForScreen !== "" || root.pickingScreens.length > 0

    // ── What replaces the gallery ─────────────────────────────────────────────
    // A FAILED run ALWAYS takes over — hiding it would remove the only account of
    // what went wrong (the lesson behind this whole progress pane). A run in
    // PROGRESS only takes over when `Config.wallApplyDebug` is on; otherwise the
    // gallery stays put and a small "Applying…" note sits by the header (see
    // `applyingQuiet`). Never over settings or properties — both have their own
    // status line, and properties' Loader would otherwise be fought over by the
    // progress pane for the same body space.
    readonly property bool applyFailed: root.isImages
        ? Wallpaper.lastFailed
        : (WallpaperEngine.lastError !== "" && !WallpaperEngine.busy)

    readonly property bool showProgress: root.view !== "settings" && root.view !== "properties" && root.view !== "effects" && !root.isMaterial
        && (root.applyFailed || (Config.wallApplyDebug && root.applyBusy))

    // Debug OFF and an apply is running — the gallery stays, this drives the
    // header note + the apply button's pulse.
    readonly property bool applyingQuiet: !Config.wallApplyDebug && root.applyBusy

    readonly property bool inGallery: root.view === "gallery" && !root.showProgress
    
    readonly property bool galleryEmpty: root.filtered.length === 0

    // ── Everything the header's second line has to say ────────────────────────
    // In priority order, because only one line is available and they are not
    // equally urgent. The count is the LEAST of them: "22 wallpapers" is a fact you
    // can also get by looking, where "a scene is covering these" explains why none
    // of them is marked current, and the blocker explains why none of them applies.
    //
    // This chain is why the panel has no status strip under the gallery any more —
    // see the Stop button in the header.
    readonly property string headerNote: {
        if (Wallpaper.pasteNote !== "") return Wallpaper.pasteNote
        if (root.pickingActive)
            return root.pickingScreens.length > 0
                ? "Choose a scene to span " + root.pickingScreens.join(" + ")
                : "Choose a scene for " + root.pickingForScreen
        if (root.applyingQuiet)       return root.progressTitle
        if (root.view === "browse")     return "Pick pictures to copy in"
        if (root.view === "settings")   return "How the renderer runs"
        if (root.view === "effects")    return Config.wallFx ? "Moving with the music" : root.motionOn ? "Parallax is on" : "Nothing moves it"
        if (root.view === "properties") return "Customising " + WallpaperEngine.titleFor(root.propertiesForId)
        if (root.isMaterial)
            return Config.wallMaterial ? "On your desktop now"
                 : Wallpaper.materialBlocker() !== "" ? Wallpaper.materialBlocker()
                 : "Not applied. Applying it replaces the picture or scene"
        if (root.blocked !== "")      return root.blocked
        if (root.gamePaused) {
            // A pick made while paused doesn't apply now — Gamemode queues it
            // rather than starting a scene process (or showing an image) behind
            // the takeover card — so say so, or a click here would read as
            // having done nothing at all.
            if (Gamemode.queuedWallpaperName !== "")
                return "Queued: " + Gamemode.queuedWallpaperName + " applies when Game Mode ends"
            const sceneTitle = root.heroSceneId !== "" ? WallpaperEngine.titleFor(root.heroSceneId) : ""
            if (root.gameRestoring)
                return sceneTitle !== "" ? "Resuming: " + sceneTitle + " is coming back"
                                          : "Resuming your wallpaper…"
            return sceneTitle !== "" ? "Paused for Game Mode. " + sceneTitle + " will resume"
                                      : "Paused for Game Mode"
        }
        if (Wallpaper.needsRestart && !root.applyBusy)
            return (Wallpaper.restartApps.length === 1
                ? Wallpaper.restartApps[0].label + " needs a restart"
                : Wallpaper.restartApps.length + " apps need a restart") + ". Press the amber button"
        if (root.sceneOnScreen)
            return root.isImages
                ? "A scene is covering these. Applying one stops it"
                : "Playing " + WallpaperEngine.titleFor(WallpaperEngine.current)
        if (Config.wallMaterial)
            return "Material is on your desktop. Applying " + (root.isImages ? "a picture" : "a scene") + " replaces it"
        if (root.scanning) return "Scanning…"
        return root.filtered.length === root.libraryCount
            ? root.libraryCount + (root.isImages ? " wallpapers" : " scenes")
            : root.filtered.length + " of " + root.libraryCount
    }

    // Step list is collapsed by default and opens itself on failure — the only time the
    // per-step breakdown is what you actually want to see. Images only: a scene apply is
    // three phases with no per-step protocol to expand.
    property bool showDetails: false
    onShowProgressChanged: if (!root.showProgress) root.showDetails = false

    Connections {
        target: Wallpaper
        function onLastFailedChanged() { if (Wallpaper.lastFailed) root.showDetails = true }
    }

    // Dismisses the pointer focus from the search field when clicking elsewhere in the
    // panel, so typing doesn't keep going into a box you've visually left.
    MouseArea {
        anchors.fill: parent
        propagateComposedEvents: true
        onPressed: function(mouse) {
            if (searchInput.activeFocus) searchInput.focus = false
            mouse.accepted = false
        }
    }

    // ── Drop pictures on the panel to add them ────────────────────────────────
    // Whatever is dropped is filtered to local .jpg/.jpeg/.png/.gif files (Lib.dropPaths — a drop is outside
    // input) and copied into the library by Wallpaper.addPaths, which never overwrites. Works on every tab:
    // the pictures belong to the library either way.
    DropArea {
        id: dropZone
        anchors.fill: parent
        z: 30
        keys: ["text/uri-list"]
        onDropped: function (drop) {
            const paths = Lib.dropPaths(drop.urls)
            if (paths.length > 0) Wallpaper.addPaths(paths)
            drop.accept()
        }

        SpringValue { id: dropGrow; target: dropZone.containsDrag ? 1 : 0; spec: Motion.springSpatial; epsilon: 0.002 }
        Rectangle {
            anchors.fill: parent
            anchors.margins: Tokens.spacingSm
            radius: Tokens.radiusXl
            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primaryContainer, 0.94)
            border.width: 2
            border.color: root.accent
            opacity: Math.min(1, Math.max(0, dropGrow.value))
            visible: dropZone.containsDrag || dropGrow.value > 0.005
            scale: 0.96 + 0.04 * Math.max(0, dropGrow.value)

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Tokens.spacingSm
                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    name: "upload_file"
                    variant: "headline"
                    color: root.accent
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Drop pictures to add them")
                    variant: "body"
                    font.weight: Font.DemiBold
                    color: Colors.of(QsWindow.window).fgOnPrimaryContainer
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "JPG, PNG or GIF, copied into " + Wallpaper.wallpaperDir.split("/").pop()
                    variant: "caption"
                    color: Colors.of(QsWindow.window).fgOnPrimaryContainer
                }
            }
        }
    }

    ColumnLayout {
        id: sideCol
        visible: root.island
        width: root.sideW
        height: parent.height
        spacing: Tokens.spacingMd

        // What is on screen, at the screen's own shape.
        WallpaperNow {
            panel: root
            Layout.fillWidth: true
            Layout.fillHeight: false
            // The screen's own 16:9, held: the column squeezes everything that can give, never this
            // (a preferred height alone is shrunk with the rest when the column runs short).
            Layout.preferredHeight: Math.round(root.sideW * 9 / 16)
            Layout.minimumHeight: Math.round(root.sideW * 9 / 16)
            Layout.maximumHeight: Math.round(root.sideW * 9 / 16)
            opacity: root.choosing ? 0.4 : 1
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
        // Where the gallery draws from: three cards, in place of the bar panel's tab strip.
        WallpaperSources {
            panel: root
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: Tokens.iconXl * 3
            onPicked: function (v) { root.pickSource(v) }
        }
        // The library's tools.
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: toolsCol.implicitHeight + Tokens.spacingMd * 2
            radius: Tokens.radiusCard
            color: Colors.of(QsWindow.window).section

            ColumnLayout {
                id: toolsCol
                anchors.fill: parent
                anchors.margins: Tokens.spacingMd
                spacing: Tokens.spacingSm

                // The header's own line, which the island does not draw a header for.
                StyledText {
                    Layout.fillWidth: true
                    text: root.swapped ? Translation.tr("Which workspaces get it? The others keep theirs.") : root.headerNote
                    visible: text !== ""
                    variant: "caption"
                    emphasis: "dim"
                    elide: Text.ElideRight
                }
                // The header tray's chips land here (the tray sends them over, in order), each a
                // pill of its own as the Dashboard's switches are.
                // The same tools the bar panel's header carries, each a pill of its own as the
                // Dashboard's switches are. Declared here, not moved over from the header: a chip that
                // is hidden when it is reparented and shown later is laid out but never painted
                // (measured on Qt 6.12: the renderer-options chip left a blank slot on Scenes).
                RowLayout {
                    id: toolsRow
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm

                    ChipButton {
                        Layout.fillWidth: true
                        tonal: true
                        visible: !root.isMaterial
                        symbol: "refresh"
                        tint: root.accent
                        enabled: !root.scanning
                        iconAngle: root._rescanSpinning ? root._rescanPhase : 0
                        onActivated: root.doRescan()
                        HoverTip { text: Translation.tr("Rescan the library") }
                    }
                    ChipButton {
                        Layout.fillWidth: true
                        tonal: true
                        visible: root.view === "gallery" || root.isMaterial
                        symbol: "animation"
                        on: root.motionOn
                        tint: root.accent
                        onActivated: root.view = "effects"
                        HoverTip { text: Translation.tr("Parallax and music effects") }
                    }
                    ChipButton {
                        Layout.fillWidth: true
                        tonal: true
                        visible: !root.isImages && !root.isMaterial
                        symbol: "settings"
                        tint: root.accent
                        onActivated: root.view = "settings"
                        HoverTip { text: Translation.tr("Renderer options") }
                    }
                    ChipButton {
                        Layout.fillWidth: true
                        tonal: true
                        visible: root.view === "gallery" && !root.galleryEmpty
                        symbol: "checklist"
                        on: root.selecting
                        tint: root.accent
                        onActivated: root.selecting ? root.endSelect() : root.selecting = true
                        HoverTip { text: root.selecting ? Translation.tr("Done selecting") : Translation.tr("Select several (S)") }
                    }
                    ChipButton {
                        Layout.fillWidth: true
                        tonal: true
                        visible: root.view === "gallery"
                        symbol: root.listView ? "view_quilt" : "format_list_bulleted"
                        tint: root.accent
                        onActivated: root.listView = !root.listView
                        HoverTip { text: root.listView ? Translation.tr("Show a grid (L)") : Translation.tr("Show a list (L)") }
                    }
                }
            }
        }
    }

    ColumnLayout {
        id: mainCol
        anchors.fill: parent
        anchors.margins: root.island ? 0 : Tokens.spacingLg
        anchors.leftMargin: root.island ? root.sideW + Tokens.spacingMd : Tokens.spacingLg
        spacing: Tokens.spacingMd

        // ── Header ────────────────────────────────────────────────────────────
        // The engine tab wears Wallpaper Engine's own MARK out of Steam's cache —
        // the clearest signal that this is a different library. `iconClip` takes
        // the mark alone out of a mark-plus-wordmark file; `glyph` is the fallback
        // for a machine without the app.
        PanelHeader {
            id: head
            // The bar panel's. An island page has no header: the rail names it, and its tools stand
            // in the side column (`toolsRow`).
            visible: !root.island
            icon:      (root.isImages || root.isMaterial) ? Icons.asset("wallpaper")
                                     : ("file://" + WallpaperEngine.logoFile)
            glyph:     "󰕧"
            iconClip:  (root.isImages || root.isMaterial) ? Qt.rect(0, 0, 0, 0)
                                     : Qt.rect(0, 7, 177, 177)
            iconSize:  Qt.size(20, 20)

            title:     Translation.tr("Wallpaper")
            titleTail: root.isMaterial ? "Material" : root.isImages ? "Gallery" : "Engine"
            accent:    root.accent
            subtitle:  root.swapped ? "Which workspaces get it? The others keep theirs." : root.headerNote

            // Applying, debug off — a breathing dot next to the "Applying…" note.
            BusyDot {
                Layout.alignment: Qt.AlignVCenter
                running: root.applyingQuiet
                tint: root.accent
            }

            // ── ONE tray: the LIBRARY and how you see it ───────────────────────
            // Rescan, motion (parallax and music), the renderer's options (scenes), select, and the layout.
            // What you do to the WALLPAPER (shuffle, stop, undo, restart, cancel) lives on
            // the hero strip below, next to the picture it acts on. A lit chip IS the on state; the
            // layout chip shows the layout it switches TO. (The apply log's switch lives in the library
            // drawer: it is a setting, not an action.)
            ChipTray {
                groupShown: root.view === "gallery" || root.isMaterial

                ChipButton {
                    visible: !root.isMaterial
                    symbol:  "refresh"
                    tint:    root.accent
                    enabled: !root.scanning
                    iconAngle: root._rescanSpinning ? root._rescanPhase : 0
                    onActivated: root.doRescan()
                    HoverTip { below: true; text: Translation.tr("Rescan the library") }
                }
                // What moves the wallpaper: parallax (picture and scene) and the music, in one view
                // (Settings has the music controls too). Lit while any of them is on. On the Material tab too:
                // parallax pans it as it pans a picture.
                ChipButton {
                    visible: root.view === "gallery" || root.isMaterial
                    symbol:  "animation"
                    on:      root.motionOn
                    tint:    root.accent
                    onActivated: root.view = "effects"
                    HoverTip { below: true; text: Translation.tr("Parallax and music effects") }
                }
                ChipButton {
                    visible: !root.isImages && !root.isMaterial
                    symbol:  "settings"
                    tint:    root.accent
                    onActivated: root.view = "settings"
                    HoverTip { below: true; text: Translation.tr("Renderer options") }
                }
                ChipButton {
                    symbol:  "checklist"
                    on:      root.selecting
                    tint:    root.accent
                    visible: root.view === "gallery" && !root.galleryEmpty
                    onActivated: root.selecting ? root.endSelect() : root.selecting = true
                    HoverTip { below: true; text: root.selecting ? "Done selecting" : "Select several (S)" }
                }
                ChipButton {
                    symbol:  root.listView ? "view_quilt" : "format_list_bulleted"
                    tint:    root.accent
                    visible: root.view === "gallery"
                    onActivated: root.listView = !root.listView
                    HoverTip { below: true; text: root.listView ? "Show a grid (L)" : "Show a list (L)" }
                }
            }
        }

        // ── Library switch + search ──────────────────────────────────────────
        RowLayout {
            id: searchRow
            Layout.fillWidth: true
            // Above what is under it: the options chip's tip hangs over the drawer and the gallery.
            z: 50
            visible: (root.view === "gallery" || root.isMaterial) && !root.showProgress && !root.swapped
            opacity: root.choosing ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            spacing: Tokens.spacingMd

            // The library switch: a pill with a sliding filled indicator (SegmentSwitch), each
            // segment with its icon and count. Wide enough that every tab keeps its name (below 104px a
            // segment it drops to the chosen one's, and 306px truncated that to "Images…").
            SegmentSwitch {
                // The island page has cards for this (WallpaperSources, in the side column).
                visible: !root.island
                Layout.preferredWidth: 336
                Layout.fillHeight: false
                accent: root.accent
                model: [
                    { value: "images",   label: "Images  " + Wallpaper.wallpapers.length,   icon: "image" },
                    { value: "engine",   label: "Scenes  " + WallpaperEngine.items.length, icon: "movie" },
                    // Lit while it is the wallpaper, so the tab says so from the other two.
                    { value: "material", label: "Material", icon: "category", lit: Config.wallMaterial }
                ]
                current: root.tab
                onPicked: function (v) { root.pickSource(v) }
            }

            // Nothing to search in the Material tab.
            Item { Layout.fillWidth: true; visible: root.isMaterial }

            // The search: a tonal pill on the section tone, ringed in the accent while it has the keys.
            // Its height is the chips' (ChipButton), so the field and the options button are one row.
            //   empty and idle   the field types its own hints (TypedPlaceholder, the launcher's and the
            //                    settings search's): what else it understands, a colour's name included
            //   empty and typing the eight hues as swatches: a press searches that colour
            //   with text        how many it found, out of how many; the glass bumps with every key
            Rectangle {
                id: searchPill
                visible: !root.isMaterial
                Layout.fillWidth: true
                implicitHeight: Tokens.iconXl + Tokens.spacingXs
                radius: height / 2
                color: Colors.of(QsWindow.window).section
                border.width: searchInput.activeFocus ? 2 : 0
                border.color: root.accent
                Behavior on border.width { NumberAnimation { duration: Motion.respond } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin:  Tokens.spacingMd
                    anchors.rightMargin: Tokens.spacingSm
                    spacing: Tokens.spacingSm

                    MaterialIcon {
                        id: glass
                        name: "search"
                        variant: "body"
                        color: searchInput.activeFocus ? root.accent : Colors.of(QsWindow.window).fgDim
                        scale: glassBump.value
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                        SpringValue { id: glassBump; target: 1; spec: Motion.springSpatialFast; epsilon: 0.002 }
                    }

                    TextInput {
                        id: searchInput
                        Layout.fillWidth: true
                        color: Colors.of(QsWindow.window).fg
                        selectionColor: Colors.of(QsWindow.window).alpha(root.accent, 0.35)
                        selectByMouse: true
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontLabel
                        verticalAlignment: TextInput.AlignVCenter
                        cursorVisible: activeFocus
                        onTextChanged: if (Config.motionEnabled) { glassBump.jump(1.28); glassBump.target = 1 }

                        Keys.onEscapePressed: {
                            searchInput.text = ""
                            searchInput.focus = false
                        }
                        // A picture on the clipboard is added to the library; plain text pastes into the field as ever
                        // (not accepted here, so the field still gets the key).
                        Keys.onPressed: function (e) {
                            if (e.key === Qt.Key_V && (e.modifiers & Qt.ControlModifier)) Wallpaper.pasteFromClipboard(true)
                        }
                        Keys.onReturnPressed: {
                            if (root.filtered.length === 1) root.applyEntry(root.filtered[0])
                        }

                        TypedPlaceholder {
                            anchors.fill: parent
                            visible: searchInput.text.length === 0
                            variant: "label"
                            lead: root.isImages ? Translation.tr("Search wallpapers") : Translation.tr("Search scenes")
                            placeholder: lead
                            // Idle only: while it has the keys the swatches stand where the hints would run.
                            hints: searchInput.activeFocus ? [] : (root.isImages
                                ? [{ key: "blue", text: Translation.tr("by colour") },
                                   { key: "gif",  text: Translation.tr("the animated ones") },
                                   { key: "/",    text: Translation.tr("to jump here") }]
                                : [{ key: "blue",  text: Translation.tr("by colour") },
                                   { key: "video", text: Translation.tr("only the videos") },
                                   { key: "/",     text: Translation.tr("to jump here") }])
                        }
                    }

                    // The hues.
                    Row {
                        spacing: Tokens.spacingXs
                        visible: opacity > 0.01
                        opacity: searchInput.activeFocus && searchInput.text.length === 0 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                        Repeater {
                            model: Lib.colorList()
                            delegate: Rectangle {
                                id: swatch
                                required property var modelData
                                required property int index
                                width: Tokens.iconSm
                                height: width
                                radius: width / 2
                                // The gamut a colour search is picked FROM, not themed chrome (docs/standards.md).
                                color: Qt.hsla(swatch.modelData.hue / 360, 0.72, 0.55, 1)
                                border.width: Tokens.borderWidth
                                border.color: Colors.of(QsWindow.window).outline
                                scale: swatchMouse.containsMouse ? 1.3 : 1
                                Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Motion.overshoot } }
                                MouseArea {
                                    id: swatchMouse
                                    anchors.fill: parent
                                    anchors.margins: -Tokens.spacingXs
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: searchInput.text = swatch.modelData.id
                                    Accessible.role: Accessible.Button
                                    Accessible.name: swatch.modelData.id
                                    Accessible.onPressAction: searchInput.text = swatch.modelData.id
                                }
                            }
                        }
                    }

                    // How many it found, out of how many.
                    Rectangle {
                        visible: searchInput.text.length > 0
                        implicitWidth: found.implicitWidth + Tokens.spacingMd * 2
                        implicitHeight: found.implicitHeight + Tokens.spacingXs
                        radius: height / 2
                        color: root.filtered.length === 0 ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).danger, 0.2)
                                                          : Colors.of(QsWindow.window).primaryContainer
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                        StyledText {
                            id: found
                            anchors.centerIn: parent
                            text: root.filtered.length === 0 ? Translation.tr("None")
                                : Translation.tr("%1 of %2").arg(root.filtered.length).arg(root.libraryCount)
                            variant: "micro"
                            font.weight: Font.DemiBold
                            font.features: ({ tnum: 1 })
                            color: Colors.of(QsWindow.window).fgOnPrimaryContainer
                        }
                    }
                    IconButton {
                        symbol: "close"
                        visible: searchInput.text.length > 0
                        onClicked: searchInput.text = ""
                    }

                    // The key that gets here from the page, said on the field while it is empty and idle.
                    Rectangle {
                        visible: searchInput.text.length === 0 && !searchInput.activeFocus
                        implicitWidth: slash.implicitWidth + Tokens.spacingSm * 2
                        implicitHeight: slash.implicitHeight + Tokens.spacingXs
                        radius: Tokens.spacingXs + 2
                        color: "transparent"
                        border.width: Tokens.borderWidth
                        border.color: Colors.of(QsWindow.window).outline
                        StyledText {
                            id: slash
                            anchors.centerIn: parent
                            text: "/"
                            variant: "micro"
                            emphasis: "dim"
                        }
                    }
                }
            }

            // Sort, filter and shuffle (the library drawer): a round chip of its own, lit while the
            // drawer is open, and a pill with the number of things changing what you see (filters,
            // and the order when it is not the default).
            ChipButton {
                id: tuneButton
                visible: !root.isMaterial
                tonal: true
                symbol: "tune"
                readonly property int changes: root.activeFilters + (Config.wallSort !== "name" ? 1 : 0)
                label: tuneButton.changes > 0 ? String(tuneButton.changes) : ""
                on: root.popover === "library" || tuneButton.changes > 0
                tint: root.accent
                onActivated: root.popover = root.popover === "library" ? "" : "library"
                HoverTip { text: Translation.tr("Sort, filter and shuffle"); below: true; alignEnd: true }
            }
        }

        // ── The library's options: a drawer under the search ─────────────────
        // How the gallery is ordered and narrowed, and the shuffle. It opens in the column (the gallery
        // gives way and takes the room back on close) rather than floating over it, so a filter is seen
        // doing its work. A critically damped spring: a bounce would shake the grid under it.
        // `popover` is "library" while it is open (the options chip, Escape).
        SpringValue {
            id: drawerK
            target: root.popover === "library" && root.view === "gallery" ? 1 : 0
            spec: ({ stiffness: Motion.springSpatial.stiffness, damping: 1.0 })
            epsilon: 0.002
        }
        Item {
            id: drawer
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Math.round(Math.max(0, drawerK.value) * drawerPlate.implicitHeight)
            visible: Layout.preferredHeight > 0
            clip: true
            opacity: Math.min(1, Math.max(0, drawerK.value))

            Rectangle {
                id: drawerPlate
                width: parent.width
                implicitHeight: drawerGrid.implicitHeight + Tokens.spacingMd * 2
                height: implicitHeight
                radius: Tokens.radiusCard
                color: Colors.of(QsWindow.window).section

                ColumnLayout {
                    id: drawerGrid
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingMd
                    spacing: Tokens.spacingSm

                    // How it is ordered.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm
                        Repeater {
                            model: [
                                { value: "name",  label: Translation.tr("Name"),   icon: "abc",      shape: "cookie9" },
                                { value: "new",   label: Translation.tr("Newest"), icon: "schedule", shape: "clover" },
                                { value: "color", label: Translation.tr("Colour"), icon: "palette",  shape: "sunny" }
                            ]
                            delegate: OptionCard {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.fillHeight: false
                                symbol: modelData.icon
                                label: modelData.label
                                shape: modelData.shape
                                on: Config.wallSort === modelData.value
                                onActivated: Config.wallSort = modelData.value
                            }
                        }
                    }

                    // What is shown.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm
                        Repeater {
                            model: Lib.kinds(root.isImages)
                            delegate: OptionCard {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.fillHeight: false
                                symbol: modelData.value === "gif" ? "play_arrow" : modelData.value === "scene" ? "movie"
                                      : modelData.value === "video" ? "video_library" : "select_all"
                                label: modelData.label
                                shape: "squircle"
                                on: root.kindFilter === modelData.value
                                onActivated: root.kindFilter = modelData.value
                            }
                        }
                        OptionCard {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.fillHeight: false
                            symbol: "bookmark"
                            label: Translation.tr("Favourites")
                            shape: "cookie9"
                            on: root.favOnly
                            onActivated: root.favOnly = !root.favOnly
                        }
                    }

                    // The shuffle, and the two switches that are about applying.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm
                        OptionCard {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.fillHeight: false
                            symbol: "shuffle"
                            label: Translation.tr("Shuffle")
                            detail: Config.wallShuffle ? Translation.tr("Every %1 min").arg(Config.wallShuffleMins) : Translation.tr("Off")
                            shape: "clover"
                            on: Config.wallShuffle
                            onActivated: Config.wallShuffle = !Config.wallShuffle
                        }
                        OptionCard {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.fillHeight: false
                            symbol: "bookmark"
                            label: Translation.tr("Starred only")
                            detail: Translation.tr("Shuffle from favourites")
                            shape: "cookie9"
                            on: Config.wallShuffleFavs
                            onActivated: Config.wallShuffleFavs = !Config.wallShuffleFavs
                        }
                        OptionCard {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.fillHeight: false
                            symbol: "checklist"
                            label: Translation.tr("Apply log")
                            detail: Translation.tr("Show each step")
                            shape: "squircle"
                            on: Config.wallApplyDebug
                            onActivated: Config.wallApplyDebug = !Config.wallApplyDebug
                        }
                    }
                    // How often, while it shuffles.
                    ChipRow {
                        Layout.fillHeight: false
                        visible: Config.wallShuffle
                        accent: root.accent
                        model: [
                            { value: 15,  label: "15 min" }, { value: 30,  label: "30 min" },
                            { value: 60,  label: "1 hour" }, { value: 120, label: "2 hours" }
                        ]
                        current: Config.wallShuffleMins
                        onPicked: function (v) { Config.wallShuffleMins = v }
                    }
                }
            }
        }

        // ── Hero — what's on screen, and what it did to the shell ───────────
        // The current wallpaper's picture, its name and aspect, where the shell's
        // colours are coming from, and the palette that produced (the
        // wallpaper→theme link, made visible). The gallery below CHANGES the
        // wallpaper; this SHOWS it. Hidden entirely when nothing is set.
        Rectangle {
            id: hero
            Layout.fillWidth: true
            Layout.preferredHeight: 74
            // The island page has its own (WallpaperNow, in the side column).
            visible: root.view === "gallery" && !root.showProgress && root.heroName !== "" && !root.swapped && !root.island
            opacity: root.choosing ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            // Flat and rounder, like every box in the redesigned panels: one solid container fill,
            // no outline, no gradient (the blurred copy of the picture behind is the colour).
            radius: Tokens.radiusCard
            color: Colors.of(QsWindow.window).plateLow

            // The current wallpaper's aspect, from the loaded thumbnail (sourceSize
            // preserves the ratio even though it scales the pixels). More use than
            // an exact resolution here — it tells you whether it fits your screen.
            readonly property string aspect: {
                const w = heroImage.implicitWidth, h = heroImage.implicitHeight
                if (!(w > 1) || !(h > 1)) return ""
                const r = w / h
                const known = [[16, 9], [16, 10], [21, 9], [4, 3], [3, 2], [1, 1],
                               [9, 16], [9, 21], [3, 4], [2, 3]]
                for (let i = 0; i < known.length; i++)
                    if (Math.abs(r - known[i][0] / known[i][1]) < 0.03)
                        return known[i][0] + ":" + known[i][1]
                return r.toFixed(2)
            }

            // The current picture again, blurred and dim, as the card's own backdrop:
            // depth and a hint of the wallpaper's colour without any extra room.
            ClippingRectangle {
                anchors.fill: parent
                radius: hero.radius
                color: "transparent"
                Image {
                    anchors.fill: parent
                    source: heroImage.source
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 240
                    opacity: status === Image.Ready ? 0.62 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.spatial } }
                    layer.enabled: opacity > 0
                    layer.effect: MultiEffect { blurEnabled: true; blur: 0.7; blurMax: 40; saturation: 0.25 }
                }
                // A scrim from the left (where the words are) so the text keeps its contrast over a bright
                // picture, and the right of the strip shows the wallpaper's own colour.
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Colors.of(QsWindow.window).alpha(hero.color, 0.55) }
                        GradientStop { position: 0.6; color: Colors.of(QsWindow.window).alpha(hero.color, 0.30) }
                        GradientStop { position: 1.0; color: Colors.of(QsWindow.window).alpha(hero.color, 0.10) }
                    }
                }
            }

            // ── It answers the pointer, and a click finds the wallpaper in the grid ──────
            // A state layer under the pointer (with the press ripple), and `revealCurrent` on a click:
            // the cursor lands on the tile that is applied and the grid scrolls to it. Declared before the
            // row, so the strip's own buttons (Refresh) sit above it and keep their clicks.
            HoverHandler { id: heroHover }
            StateLayer {
                id: heroFeel
                anchors.fill: parent
                radius: hero.radius
                hovered: heroHover.hovered
                layerColor: root.accent
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: function (m) { heroFeel.press(m.x, m.y) }
                onReleased: heroFeel.release()
                onCanceled: heroFeel.release()
                onClicked: root.revealCurrent()
            }

            RowLayout {
                anchors.fill: parent
                // One even inset all round, and the thumbnail's corner CONCENTRIC with the card's
                // (the card's radius less the inset): a 4px corner 2px inside a 23px one reads
                // as clipped.
                anchors.margins: Tokens.spacingMd
                spacing: Tokens.spacingMd

                ClippingRectangle {
                    id: heroThumb
                    Layout.preferredWidth:  Math.round((hero.height - Tokens.spacingMd * 2) * 16 / 9)
                    Layout.fillHeight: true
                    radius: Math.max(Tokens.radiusSm, hero.radius - Tokens.spacingMd)
                    color:  Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surface, 0.5)

                    // ── Crossfade on a wallpaper change ─────────────────────
                    // `heroImage` shows the current picture; `heroPrev` holds the
                    // one before it underneath until the new one has loaded, so a
                    // switch dissolves instead of blinking through the empty plate.
                    readonly property string src: root.bust(root.heroSource)
                    onSrcChanged: {
                        heroPrev.source  = heroImage.source
                        heroPrev.opacity = 1
                        heroImage.source = heroThumb.src
                    }
                    Component.onCompleted: heroImage.source = heroThumb.src

                    Image {
                        id: heroPrev
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        cache: true
                        sourceSize.width: 240
                        opacity: 0
                        Behavior on opacity {
                            NumberAnimation { duration: Motion.spatial }
                        }
                    }
                    Image {
                        id: heroImage
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        sourceSize.width: 240
                        opacity: (String(source) !== "" && status === Image.Ready) ? 1 : 0
                        Behavior on opacity {
                            NumberAnimation { duration: Motion.spatial
                                              easing.type: Motion.travel }
                        }
                        onStatusChanged: if (status === Image.Ready) heroPrev.opacity = 0
                    }
                    // The Material Wallpaper, as it is drawn on the desktop, in place of a picture.
                    Loader {
                        anchors.fill: parent
                        active: root.materialOnScreen
                        sourceComponent: MaterialWallpaper {}
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        visible: heroImage.opacity < 0.05 && heroPrev.opacity < 0.05 && !root.materialOnScreen
                        name: root.gamePaused ? "gamepad" : root.sceneOnScreen ? "movie" : "wallpaper"
                        variant: "title"
                        color: Colors.of(QsWindow.window).fgDim
                    }

                    // The paused scene's own still stays visible underneath, just
                    // dimmed with the mode's icon over it — "this is paused", not
                    // "this is gone". Only when there's actually a picture to dim;
                    // the no-scene-known case already gets the plain icon above.
                    Rectangle {
                        anchors.fill: parent
                        visible: root.gamePaused && root.heroSceneId !== ""
                        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.6)
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        visible: root.gamePaused && root.heroSceneId !== ""
                        name: "gamepad"
                        fill: 1
                        color: Colors.of(QsWindow.window).primary
                        variant: "headline"
                    }
                }

                // ── What it is: a name, and two quiet chips ───────────────────────
                // A title with its kind beside it on a pill, and under it where the colours are
                // from and the mode — one idea per line, where it was three icons and a dim line
                // each. The title slides up into place when the wallpaper changes.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Tokens.spacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingSm

                        StyledText {
                            id: heroTitle
                            Layout.fillWidth: true
                            text: root.heroName
                            variant: "body"
                            font.weight: Font.DemiBold
                            elide: Text.ElideMiddle

                            property real rise: 0
                            transform: Translate { y: heroTitle.rise }
                            onTextChanged: { if (Config.motionEnabled) { heroTitle.opacity = 0; heroTitle.rise = 8; titleIn.restart() } }
                            ParallelAnimation {
                                id: titleIn
                                NumberAnimation { target: heroTitle; property: "opacity"; to: 1; duration: Motion.spatial; easing.type: Motion.travel }
                                NumberAnimation { target: heroTitle; property: "rise"; to: 0; duration: Motion.spatial; easing.type: Motion.overshoot }
                            }
                        }

                        // paused / scene / kind — only when there is something to say
                        Rectangle {
                            id: kindPill
                            visible: kindText.text !== ""
                            implicitWidth:  kindText.implicitWidth + Tokens.spacingMd * 2
                            implicitHeight: kindText.implicitHeight + Tokens.spacingXs * 2
                            radius: height / 2
                            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.10)

                            StyledText {
                                id: kindText
                                anchors.centerIn: parent
                                text: {
                                    const bits = []
                                    // No scene id known → the name line above already
                                    // says "Paused for Game Mode" in full; don't repeat it.
                                    if (root.gamePaused) {
                                        if (root.heroSceneId !== "") bits.push(root.heroKind)
                                    } else if (root.sceneOnScreen && root.heroKind !== "") {
                                        bits.push(root.heroKind)
                                    } else if (root.materialOnScreen) {
                                        bits.push("Live")
                                    } else if (!root.sceneOnScreen) {
                                        if (hero.aspect !== "") bits.push(hero.aspect)
                                        const ext = root.heroName.indexOf(".") !== -1
                                            ? root.heroName.split(".").pop().toUpperCase() : ""
                                        if (ext !== "") bits.push(ext)
                                    }
                                    return bits.join("  ·  ")
                                }
                                variant: "micro"
                                font.weight: Font.DemiBold
                                color: Colors.of(QsWindow.window).fgMuted
                            }
                        }
                    }

                    // Where the colours are from, and the mode.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.maximumWidth: themeRow.implicitWidth + Tokens.spacingMd * 2
                        implicitHeight: themeRow.implicitHeight + Tokens.spacingXs * 2
                        radius: height / 2
                        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.07)

                        RowLayout {
                            id: themeRow
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.spacingMd
                            anchors.rightMargin: Tokens.spacingMd
                            spacing: Tokens.spacingXs

                            MaterialIcon {
                                name: !Config.wallTheming ? "format_paint"
                                    : AlbumScheme.active   ? "music_note" : "palette"
                                fill: (Config.wallTheming && AlbumScheme.active) ? 1 : 0
                                color: Config.wallTheming ? root.accent : Colors.of(QsWindow.window).fgDim
                                font.pixelSize: Tokens.iconSm
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: root.heroThemeSource
                                    + (Config.wallTheming
                                       ? "  ·  " + (Config.themeMode === "light" ? "Light" : "Dark")
                                       : "")
                                variant: "caption"
                                emphasis: "dim"
                                elide: Text.ElideRight
                            }
                        }
                    }
                }

                // ── The palette, as a stack of dots ───────────────────────────────
                // ansi(1..6), the vivid half of the extracted set — the colours the whole shell
                // is wearing right now. Overlapping discs rather than a long strip of bars:
                // smaller, calmer, and each one pops in turn on a spring when the palette
                // changes, so a new wallpaper reads as a wave passing through them.
                // Hidden when theming is off: there is nothing to show.
                Row {
                    Layout.alignment: Qt.AlignVCenter
                    visible: Config.wallTheming
                    spacing: -(Tokens.spacingSm + Tokens.spacingXs)

                    Repeater {
                        model: [1, 2, 3, 4, 5, 6]
                        delegate: Rectangle {
                            id: dot
                            required property int index
                            required property int modelData
                            width:  Tokens.iconLg + Tokens.spacingSm
                            height: Tokens.iconLg + Tokens.spacingSm
                            radius: width / 2
                            color: Colors.of(QsWindow.window).ansi(dot.modelData)
                            border.width: 2
                            border.color: hero.color
                            Behavior on color { ColorAnimation { duration: Motion.standard } }

                            // In on a spring when the hero appears; a little pop, one after another, when
                            // the colour changes.
                            SpringValue { id: pop; target: Config.motionEnabled ? 0 : 1; spec: Motion.springSpatialFast }
                            readonly property real k: Math.max(0, pop.value)
                            Timer { running: Config.motionEnabled; interval: dot.index * 55; onTriggered: pop.target = 1 }
                            scale: dot.k
                            onColorChanged: if (Config.motionEnabled && dot.k > 0.9) bump.restart()
                            SequentialAnimation {
                                id: bump
                                PauseAnimation { duration: dot.index * 45 }
                                NumberAnimation { target: dot; property: "scale"; to: 1.28; duration: Motion.respond; easing.type: Motion.travel }
                                NumberAnimation { target: dot; property: "scale"; to: 1.0;  duration: Motion.standard; easing.type: Motion.overshoot }
                            }
                        }
                    }
                }

                // ── What you do to the wallpaper ──────────────────────────────────────
                // On the strip, beside the picture they act on (they were a second pill in the header,
                // away from it). Shuffle / Stop carry their name: the main action is not a guess.
                ChipTray {
                    Layout.alignment: Qt.AlignVCenter
                    // A click inside the strip must not also "reveal the wallpaper" (the strip's MouseArea
                    // sits under the row, so the chips take their own clicks).
                // Apps that need restarting after an apply. This was a text pill (up to
                // ~270px wide with its two buttons) in the header's row: appearing after
                // an apply, it pushed the header past the panel's 620px, and since a
                // layout can't be narrower than its widest child's minimum, the WHOLE
                // panel overflowed its pin — the "dimensions change, border breaks"
                // report. It is one icon now; the subtitle names the apps.
                ChipButton {
                    visible: !root.isMaterial && Wallpaper.needsRestart && !root.applyBusy && !root.pickingActive
                    symbol:  "restart_alt"
                    on:      true
                    tint:    Colors.of(QsWindow.window).warning
                    onActivated: Wallpaper.restartAll()
                    HoverTip { below: true; text: Translation.tr("Restart the apps that need it") }
                }
                ChipButton {
                    visible: !root.isMaterial && root.pickingActive
                    symbol:  "close"
                    label:   Translation.tr("Cancel")
                    tint:    root.accent
                    onActivated: {
                        root.pickingForScreen = ""
                        root.pickingScreens = []
                    }
                }
                // One click back to what was on screen before the last change (Wallpaper.undo).
                ChipButton {
                    visible: Wallpaper.canUndo && !root.applyBusy && !root.pickingActive
                    symbol:  "undo"
                    tint:    root.accent
                    onActivated: Wallpaper.undo()
                    HoverTip { below: true; text: "Back to " + Wallpaper.previousName }
                }
                ChipButton {
                    visible: !root.isMaterial && !root.pickingActive && root.sceneOnScreen
                    symbol:  "stop"
                    label:   Translation.tr("Stop")
                    tint:    root.accent
                    enabled: !WallpaperEngine.busy
                    onActivated: WallpaperEngine.stop()
                    HoverTip { below: true; text: Translation.tr("Stop the scene") }
                }
                ChipButton {
                    visible: !root.isMaterial && !root.sceneOnScreen && Wallpaper.wallpapers.length > 1
                    symbol:  "shuffle"
                    label:   Translation.tr("Shuffle")
                    tint:    root.accent
                    enabled: !Wallpaper.applying
                    onActivated: Wallpaper.shuffleNow(true)
                    HoverTip { below: true; text: Config.wallShuffleFavs ? "Shuffle now (starred)" : "Shuffle now" }
                }
                }

                ChipButton {
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.sceneOnScreen && WallpaperEngine.needsRefresh
                    symbol:  "refresh"
                    on:      true
                    tint:    root.accent
                    onActivated: WallpaperEngine.refresh()
                }
            }
        }

        // ══ Sub-view toolbars ════════════════════════════════════════════════
        // browse and settings each REPLACE the gallery header above rather than
        // stacking under it — at 340px a second toolbar row costs a rank of
        // thumbnails. The gallery's own controls live in `galleryHeader`.

        // ── Browser: back out ─────────────────────────────────────────────────
        // The browser draws its own places, path and Add capsule (WallpaperBrowse); this is only the way back.
        WallpaperSubBar {
            visible: root.view === "browse"

            ChipTray {
                ChipButton {
                    symbol: "arrow_left"
                    label: Translation.tr("Back")
                    tint: root.accent
                    onActivated: root.view = "gallery"
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Add pictures to the library")
                variant: "caption"
                emphasis: "dim"
                elide: Text.ElideRight
            }
        }

        // ── Settings: back out, and the one action the options need ───────────
        WallpaperSubBar {
            visible: root.view === "settings"

            ChipTray {
                ChipButton {
                    symbol: "arrow_left"
                    label: Translation.tr("Back")
                    tint: root.accent
                    onActivated: root.view = "gallery"
                }
            }

            BusyDot {
                Layout.alignment: Qt.AlignVCenter
                running: WallpaperEngine.busy
                tint: WallpaperEngine.running ? Colors.of(QsWindow.window).success : root.accent
            }

            StyledText {
                Layout.fillWidth: true
                text: WallpaperEngine.busy       ? root.progressTitle
                    : WallpaperEngine.needsRefresh ? "Running · changes pending"
                    : WallpaperEngine.running    ? "Renderer running"
                    : "Renderer stopped"
                variant: "caption"
                emphasis: "dim"
                elide: Text.ElideRight
            }

            // Options no longer restart the scene on their own — a change is
            // collected and applied here, so dragging a slider doesn't flicker the
            // wallpaper on every tick.
            ChipTray {
                ChipButton {
                    label: Translation.tr("Refresh")
                    symbol: "refresh"
                    on: true
                    tint: root.accent
                    visible: WallpaperEngine.needsRefresh
                    onActivated: WallpaperEngine.refresh()
                }
                ChipButton {
                    symbol: "stop"
                    tint: root.accent
                    visible: WallpaperEngine.running && !WallpaperEngine.busy
                    onActivated: WallpaperEngine.stop()
                }
                ChipButton {
                    symbol: "play_arrow"
                    tint: root.accent
                    visible: !WallpaperEngine.running && !WallpaperEngine.busy
                             && Config.wpeCurrent !== ""
                    enabled: root.blocked === ""
                    onActivated: WallpaperEngine.apply(Config.wpeCurrent)
                }
            }
        }

        // ── Effects: back out, and what the beat clock hears ──────────────────
        WallpaperSubBar {
            visible: root.view === "effects"

            ChipTray {
                ChipButton {
                    symbol: "arrow_left"
                    label: Translation.tr("Back")
                    tint: root.accent
                    onActivated: root.view = "gallery"
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: !Config.wallFx ? Translation.tr("Off")
                    : !MusicPulse.probed ? ""
                    : !MusicPulse.dspOk ? Translation.tr("Following the bass with cava")
                    : !MusicPulse.live ? Translation.tr("Listens while music plays")
                    : MusicPulse.locked ? Translation.tr("In time at ") + Math.round(MusicPulse.bpm) + " BPM"
                    :                     Translation.tr("Finding the beat…")
                variant: "caption"
                emphasis: "dim"
                elide: Text.ElideRight
            }
        }

        // ── Properties: back out ───────────────────────────────────────────────
        WallpaperSubBar {
            visible: root.view === "properties"

            ChipTray {
                ChipButton {
                    symbol: "arrow_left"
                    label: Translation.tr("Back")
                    tint: root.accent
                    onActivated: root.view = "gallery"
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: WallpaperEngine.titleFor(root.propertiesForId)
                variant: "caption"
                emphasis: "dim"
                elide: Text.ElideRight
            }
        }

        // ══ Body ══════════════════════════════════════════════════════════════
        WallpaperPanelBody {
            id: body
            panel: root
        }

        WorkspacePicker {
            id: picker
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.swapped
            shown: root.swapped
            picture: root.choosingPic
            onApplied: wsList => Wallpaper.assign(root.choosingPic, wsList)
            onCancelled: Wallpaper.cancelPick()
        }
    }

    // Applying arrives as a wave (services/WallWave.qml): the new picture as water
    // from the bottom middle, the new colours eating the old look off the shell on
    // the same front. This panel rides it inside the BAR's window, whose Infection
    // covers everything docked there. Nothing to draw here.

    // What the progress pane's headline says. Images report failed STEPS; a scene
    // has no steps, it has a phase — and that phase is several seconds long
    // (stop, drain, settle, then up to five verification probes), so naming it
    // beats one static "Restarting…" that looks stuck for most of the journey.
    readonly property string progressTitle: {
        if (root.isImages) {
            if (Wallpaper.applying)
                return "Applying " + Wallpaper.applyingPath.split("/").pop() + "…"
            if (Wallpaper.failedCount > 0)
                return Wallpaper.failedCount + " step"
                     + (Wallpaper.failedCount !== 1 ? "s" : "") + " failed"
            return "The run stopped early"
        }
        switch (WallpaperEngine.phase) {
            case "crossfading": return "Bringing in "
                + WallpaperEngine.titleFor(Config.wpeCurrent) + "…"
            case "stopping":  return "Stopping the current scene…"
            case "starting":  return "Starting "
                + WallpaperEngine.titleFor(Config.wpeCurrent) + "…"
            case "verifying": return "Checking it stayed up…"
        }
        return "The scene didn't start"
    }

    // ══ Lazy sub-views ════════════════════════════════════════════════════════
    // Both are secondary to the gallery and neither is cheap to keep mounted —
    // see the Loaders that own them for what each one costs.
    Component {
        id: browseComponent
        WallpaperBrowse { panel: root }
    }

    // ── The Material tab ──────────────────────────────────────────────────────
    // wallpaper/WallpaperMaterial.qml. Behind a Loader so a panel opened for a picture never builds it.
    Component {
        id: materialComponent
        WallpaperMaterial { panel: root }
    }

    // The music effects: wallpaper/WallpaperEffects.qml
    Component {
        id: effectsComponent
        WallpaperEffects { panel: root }
    }

    // The renderer's launch options: wallpaper/WallpaperRendererSettings.qml
    Component {
        id: settingsComponent
        WallpaperRendererSettings { panel: root }
    }

    // ── One scene's custom properties, at panel scale ──────────────────────────
    // wallpaper/WallpaperSceneProps.qml
    Component {
        id: propertiesComponent
        WallpaperSceneProps { panel: root }
    }
}
