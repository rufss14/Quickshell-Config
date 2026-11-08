pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/wallfx.js" as FX
import ".."
import "wallpaper"

// ── WallpaperPage ─────────────────────────────────────────────────────────────
// Both wallpaper libraries — static images (the pywal theming pipeline) and Steam
// Workshop scenes rendered by linux-wallpaperengine — plus everything that
// decides what a wallpaper does to the rest of the shell.
//
// ── The bar panel's recipe, at page scale ────────────────────────────────────
// This is the settings-app sibling of modules/panels/WallpaperPanel.qml: the same
// PanelHeader, the same one-accent identity (Colors.info), the same "show one
// thing at a time and switch" shape. Not shared code — the panel is a 620px dock
// tile and this is a 1000px page with the renderer's full option set — but the
// same design language, so flipping between the two reads as one tool.
//
// ── Three views, one at a time ───────────────────────────────────────────────
//   Gallery      pick a wallpaper. Hero (what's on screen + its palette), the
//                image/scene switch, search, and the sliding gallery, whose first
//                tile is the one "get more wallpapers" action (as in the bar
//                panel). `browse` is a sub-mode that swaps the gallery for an
//                in-page file browser.
//   Appearance   what applying a wallpaper does: theming + Light/Dark, the
//                static-image parallax, shuffle, the album-cover link, and which
//                monitor images land on.
//   Engine       the renderer itself: every linux-wallpaperengine launch option,
//                the render target, and where the library lives.
//
// ── The gallery SLIDES, it never shows the whole library ─────────────────────
// Nine tiles a page, and the pages physically slide sideways — wheel, drag, or
// the slider underneath. This is a standing rule for this page; the bar panel
// scrolls a grid instead, and that difference is deliberate.
//
// Delegates branch on the ENTRY's shape (string = image path, object = scene),
// never on the source flag: during a tab switch the flag flips while the outgoing
// tiles still exist for a frame, and a string asked for `.id` warns per tile.
//
// ── Scene previews ANIMATE, but only on the visible page ─────────────────────
// Workshop previews are mostly GIFs. Only the page on screen plays (nine bounded
// decoders); parked pages freeze on their last frame.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    readonly property Item galleryPager: galleryView.pager
    // The gallery's pager, for WallpaperPageTile (its own file can't see the gallery's ids).

    // ── View state ───────────────────────────────────────────────────────────
    property string view: "gallery"        // "gallery" | "appearance" | "engine" | "effects"

    // ── The depth clock's preview ─────────────────────────────────────────────
    // The picture on the first screen's workspace, in that screen's shape — what the desktop frames.
    readonly property string depthPath: Wallpaper.currentPath
    readonly property real depthAspect: Quickshell.screens.length > 0 && Quickshell.screens[0].height > 0
        ? Quickshell.screens[0].width / Quickshell.screens[0].height : 16 / 9
    // The spots on offer (centre x, top y), and which one the picture's clock is on, if any.
    readonly property var depthSpots: ({ tl: [0.26, 0.08], t: [0.5, 0.08], tr: [0.74, 0.08], b: [0.5, 0.6] })
    readonly property string depthPreset: {
        const p = Config.wallDepthPlaces[root.depthPath]
        if (!p) return ""
        for (const k of Object.keys(root.depthSpots))
            if (Math.abs(root.depthSpots[k][0] - p[0]) < 0.006 && Math.abs(root.depthSpots[k][1] - p[1]) < 0.006) return k
        return ""
    }
    property bool   browsing: false        // gallery sub-mode: the file browser

    // "images" | "engine"
    property string source: "images"
    property string query: ""
    readonly property bool isImages: root.source === "images"

    // A picture waiting for its workspaces (Choose workspaces on): the gallery steps
    // aside for the picker. Held for the crossfade back.
    readonly property bool choosing: Wallpaper.pending !== ""
    property string choosingPic: ""
    onChoosingChanged: if (root.choosing) { root.choosingPic = Wallpaper.pending; Qt.callLater(() => chooser.forceActiveFocus()) }

    onViewChanged: {
        if (root.view !== "gallery") { root.browsing = false; root.pickingWs = 0 }
        // Leaving the gallery any other way than completing a pick abandons it —
        // a picking state that survived a tab switch would silently reattach to
        // whatever the user clicks next.
        if (root.view !== "gallery" && root.pickingActive) {
            root.pickingForScreen = ""
            root.pickingScreens = []
        }
    }

    // ── Assigning a scene to one (or several, spanned) monitors ───────────────
    // "Choose…" in the Monitors section sets one of these and jumps to the
    // gallery; a tile's click then calls WallpaperEngine.assignMonitor()/
    // spanMonitors() instead of the normal apply() — see WallTile.doApply().
    property string pickingForScreen: ""   // a screen name, or ""
    property var    pickingScreens:   []   // 2+ names when spanning; else []
    property bool   monitorSpanMode:  false
    readonly property bool pickingActive:
        root.pickingForScreen !== "" || root.pickingScreens.length > 0

    // ── Choosing a wallpaper for ONE workspace ────────────────────────────────
    // A cell in the workspace strip sets this; the next gallery click assigns that
    // wallpaper to the workspace (Wallpaper.assign) instead of applying it everywhere.
    // The monitor picking above is the same shape, for scenes and screens.
    property int pickingWs: 0
    readonly property bool anyPicking: root.pickingActive || root.pickingWs > 0
    function cancelPicking() {
        root.pickingForScreen = ""
        root.pickingScreens = []
        root.pickingWs = 0
    }

    // The tile column count the Appearance and Engine grids use, from their width:
    // SettingsPage's rule (a tile narrower than minTile starts eliding its text).
    readonly property int minTile: 300
    function colsFor(w) {
        return Math.max(1, Math.min(3, Math.floor((w + Tokens.spacingLg) / (root.minTile + Tokens.spacingLg))))
    }

    // ── Custom scene properties (view: "properties") ──────────────────────────
    // Entered from a scene tile's "Tune" hover action. The schema and any saved
    // overrides are (re)loaded on open — the service caches per-id, so
    // reopening the same scene is instant.
    property string propertiesForId: ""

    function openProperties(id) {
        if (!id) return
        root.propertiesForId = id
        root.view = "properties"
        WallpaperEngine.loadPropertySchema(id)
        WallpaperEngine.loadOverridesFor(id)
    }

    // ONE handler for both jobs — a second `onBrowsingChanged` in this scope is
    // "Property value set multiple times", a hard load failure of the whole page.
    // Opening the browser cancels a pending screen pick; closing it drops the
    // import selection (see `picked` below).
    onBrowsingChanged: {
        if (root.browsing) root.pickingWs = 0
        if (root.browsing && root.pickingActive) {
            root.pickingForScreen = ""
            root.pickingScreens = []
        }
        if (!root.browsing) root.picked = []
    }

    // ── The renderer's running state is polled, so only poll while looking ────
    property bool _held: false
    function _sync() {
        if (root.visible === root._held) return
        if (root.visible) WallpaperEngine.acquire()
        else              WallpaperEngine.release()
        root._held = root.visible
    }
    onVisibleChanged: root._sync()
    Component.onCompleted: root._sync()
    Component.onDestruction: {
        if (root._held) WallpaperEngine.release()
        if (Wallpaper.pending !== "") Wallpaper.cancelPick()     // closed mid-choice: nothing chosen
    }

    // ── The in-page image browser ────────────────────────────────────────────
    // `browseFolder` is where it's pointed; `picked` is the set of file PATHS
    // ticked for import, cleared whenever the browser closes so a stale selection
    // can't be imported later by accident.
    property url browseFolder: "file://" + (Quickshell.env("HOME") || "")
    property var picked: []

    function isPicked(p) { return root.picked.indexOf(p) !== -1 }
    function togglePick(p) {
        root.picked = root.isPicked(p)
            ? root.picked.filter(x => x !== p)
            : root.picked.concat([p])
    }

    readonly property int pageSize: 9
    readonly property string weLogo: WallpaperEngine.logoFile

    // ── What is ACTUALLY on screen ───────────────────────────────────────────
    // A running scene covers the static wallpaper completely, so while the
    // renderer is up the static image is not "current" — it's the underlay you'd
    // get back.
    readonly property bool sceneOnScreen: WallpaperEngine.running
    // …and so does the Material Wallpaper, which is drawn by the shell instead of the picture.
    readonly property bool materialOnScreen: Config.wallMaterial && !root.sceneOnScreen

    readonly property string currentImagePath: {
        if (root.sceneOnScreen || root.materialOnScreen) return ""
        const hit = Wallpaper.wallpapers.find(
            p => p.split("/").pop() === Wallpaper.current)
        return hit ?? ""
    }

    readonly property string heroName: root.sceneOnScreen
        ? WallpaperEngine.titleFor(WallpaperEngine.current)
        : root.materialOnScreen ? "Material Wallpaper"
        : (Wallpaper.current !== "" ? Wallpaper.current : "")

    readonly property string heroSource: {
        if (root.sceneOnScreen) {
            const it = WallpaperEngine.itemFor(WallpaperEngine.current)
            return (it && it.preview !== "") ? "file://" + it.preview : ""
        }
        return root.currentImagePath !== "" ? "file://" + root.currentImagePath : ""
    }

    readonly property string heroKind: {
        if (!root.sceneOnScreen) return ""
        const it = WallpaperEngine.itemFor(WallpaperEngine.current)
        return it ? it.type : "scene"
    }

    // Where the shell's colours are coming from RIGHT NOW — the wallpaper→theme link in
    // words, as the bar panel's hero says it. The album cover wins over everything while
    // it is active (it is an overlay on Colors, not a file write), so it is checked
    // first; a held scheme also overrides the wallpaper; "theming off" means the picture
    // changed and nothing else did.
    readonly property string heroThemeSource: {
        if (!Config.wallTheming) return "Theming off"
        if (AlbumScheme.active) return "Colours from the album cover"
        if (root.sceneOnScreen)
            return Config.wpeScenePalette ? "Colours from the scene" : "Colours unchanged"
        if (ColorScheme.overrideCount > 0) return "Colours from a saved scheme"
        if (root.materialOnScreen) return "Colours from the last picture"
        return "Colours from this wallpaper"
    }
    readonly property int heroHeight: 84

    readonly property bool applyBusy:
        root.isImages ? Wallpaper.applying : WallpaperEngine.busy

    // Non-empty when this source can't apply anything at all — pywal missing, or
    // the renderer not installed. Controls go inert and say why.
    readonly property string blocked:
        Wallpaper.pywalBlocker() || (root.isImages ? "" : WallpaperEngine.blocker())

    // ── The filtered libraries ───────────────────────────────────────────────
    // Favourites float to the front of their tab; the partition is a plain
    // filter-then-concat so nothing rides on sort() stability.
    readonly property var images: {
        const q = root.query.trim().toLowerCase()
        let all = Wallpaper.wallpapers
        if (q !== "")
            all = all.filter(p => p.split("/").pop().toLowerCase().indexOf(q) !== -1)
        const fav = Config.wallFavorites
        if (fav.length === 0) return all
        const isf = p => fav.indexOf(p.split("/").pop()) !== -1
        return all.filter(isf).concat(all.filter(p => !isf(p)))
    }

    readonly property var scenes: {
        const q = root.query.trim().toLowerCase()
        let all = WallpaperEngine.items
        if (q !== "")
            all = all.filter(i => i.title.toLowerCase().indexOf(q) !== -1
                                || i.type.indexOf(q) !== -1)
        const fav = Config.wpeFavorites
        if (fav.length === 0) return all
        const isf = i => fav.indexOf(i.id) !== -1
        return all.filter(isf).concat(all.filter(i => !isf(i)))
    }

    readonly property var filtered: root.isImages ? root.images : root.scenes
    readonly property int shownCount: root.filtered.length

    // ── "Get more" is the first tile, not a bar under the gallery ─────────────
    // As in the bar panel: the action sits in the first cell of the grid, the same
    // anatomy as a picture, so the space below belongs to the previews. While searching
    // the grid shows only what matched. (`id` is what the pager's model compares by.)
    readonly property var actionEntry: root.isImages
        ? { id: "action:add", action: "add", glyph: "󰋺", title: "Add images",
            caption: "Copy pictures in from any folder" }
        : { id: "action:workshop", action: "workshop", glyph: "󰓓", title: "Workshop",
            caption: "Subscribe to scenes, then rescan" }
    readonly property var entries: root.query.trim() === ""
        ? [root.actionEntry].concat(root.filtered) : root.filtered
    readonly property int pageCount: Math.max(1, Math.ceil(root.entries.length / root.pageSize))

    function runAction(which) {
        if (which === "add") root.browsing = true
        else                 WallpaperEngine.openWorkshopHub()
    }

    onQueryChanged: galleryView.pager.currentIndex = 0
    onSourceChanged: { galleryView.pager.currentIndex = 0; root.browsing = false }

    // ── The renderer's phase, named ──────────────────────────────────────────
    readonly property string engineStatus: {
        if (WallpaperEngine.busy) {
            switch (WallpaperEngine.phase) {
                case "crossfading": return "Bringing in "
                    + WallpaperEngine.titleFor(Config.wpeCurrent) + "…"
                case "stopping":  return "Stopping the current scene…"
                case "starting":  return "Starting "
                    + WallpaperEngine.titleFor(Config.wpeCurrent) + "…"
                case "verifying": return "Checking it stayed up…"
            }
            return "Working…"
        }
        if (WallpaperEngine.needsRefresh) return "Running · changes pending"
        return WallpaperEngine.running ? "Renderer running" : "Renderer stopped"
    }

    // ── Header subtitle — one line, priority order ───────────────────────────
    readonly property string headerNote: {
        if (root.browsing)            return "Pick pictures to copy in"
        if (root.pickingWs > 0)       return "Pick a wallpaper for workspace " + root.pickingWs
        if (root.blocked !== "")      return root.blocked
        if (root.view === "appearance") return "Motion, shuffle and which screens"
        if (root.view === "engine")   return root.engineStatus
        if (root.view === "effects")
            return !Config.wallShellRender ? "Needs the shell to draw the wallpaper"
                 : Config.wallFx ? "Moving with the music" : "Off — the wallpaper stays still"
        if (root.sceneOnScreen)
            return root.isImages
                ? "A scene is covering these — applying one stops it"
                : "Playing " + WallpaperEngine.titleFor(WallpaperEngine.current)
        if (Config.wallMaterial)
            return "Material is on your desktop — applying " + (root.isImages ? "a picture" : "a scene") + " replaces it"
        if (root.scanning) return "Scanning…"
        return root.query !== ""
            ? root.shownCount + " of " + (root.isImages
                ? Wallpaper.wallpapers.length : WallpaperEngine.items.length)
            : root.shownCount + (root.isImages ? " wallpapers" : " scenes")
    }

    readonly property bool scanning: root.isImages
        ? Wallpaper.scanning : WallpaperEngine.scanning

    // ── Rescan: spin the button for a beat, bust the thumbnail cache ─────────
    property int  _previewNonce:   0
    property bool _rescanSpinning:  false
    property real _rescanPhase:     0
    Timer { id: _rescanSpinTimer; interval: 850; onTriggered: root._rescanSpinning = false }
    NumberAnimation {
        target: root; property: "_rescanPhase"
        from: 0; to: 360; duration: 850
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

    // ══ Layout ═══════════════════════════════════════════════════════════════
    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingLg

        // ── View switch ──────────────────────────────────────────────────────
        // The same strip every rail page wears above its content (SettingsCard draws it for
        // pages with several views; this is one view with three modes, so it draws its own, in
        // the same place). One wash that SLIDES between segments. Hidden while the file browser
        // has the body.
        TabStrip {
            Layout.fillWidth: true
            visible: !root.browsing && root.view !== "properties"
            accent: Colors.of(QsWindow.window).primary
            model: [
                { value: "gallery",    label: "Gallery",    icon: "wallpaper" },
                { value: "appearance", label: "Appearance", icon: "palette" },
                { value: "engine",     label: "Engine",     icon: "movie" },
                { value: "effects",    label: "Effects",    icon: "music_note" }
            ]
            current: root.view
            onPicked: function (v) { root.view = v }
        }

        // ── Header ───────────────────────────────────────────────────────────
        // The engine tab wears Wallpaper Engine's own MARK out of Steam's cache;
        // `iconClip` takes the mark alone out of a mark-plus-wordmark file, and
        // `glyph` is the fallback for a machine without the app.
        PanelHeader {
            Layout.fillHeight: false
            icon:      root.isImages && root.view === "gallery"
                       ? Icons.asset("wallpaper")
                       : (!root.isImages && root.view === "gallery"
                          ? "file://" + root.weLogo : "")
            glyph:     "󰸉"
            iconClip:  (!root.isImages && root.view === "gallery")
                       ? Qt.rect(0, 7, 177, 177) : Qt.rect(0, 0, 0, 0)
            iconSize:  Qt.size(20, 20)

            title:     Translation.tr("Wallpaper")
            titleTail: root.view === "appearance" ? "Appearance"
                     : root.view === "engine"     ? "Engine"
                     : root.view === "effects"    ? "Effects"
                     : root.isImages              ? "Gallery" : "Scenes"
            accent:    Colors.of(QsWindow.window).primary
            subtitle:  root.headerNote

            BusyDot {
                Layout.alignment: Qt.AlignVCenter
                running: root.applyBusy
                tint: Colors.of(QsWindow.window).primary
            }

            // Gallery-only: acts on the current wallpaper + the library.
            ChipTray {
                groupShown: root.view === "gallery" && !root.browsing

                ChipButton {
                    visible: root.sceneOnScreen
                    symbol:  "stop"
                    tint:    Colors.of(QsWindow.window).primary
                    enabled: !WallpaperEngine.busy
                    onActivated: WallpaperEngine.stop()
                }
                ChipButton {
                    visible: !root.sceneOnScreen && Wallpaper.wallpapers.length > 1
                    symbol:  "shuffle"
                    tint:    Colors.of(QsWindow.window).primary
                    enabled: !Wallpaper.applying
                    onActivated: Wallpaper.shuffleNow(true)
                }
                ChipButton {
                    symbol:  "refresh"
                    tint:    Colors.of(QsWindow.window).primary
                    enabled: !root.scanning
                    iconAngle: root._rescanSpinning ? root._rescanPhase : 0
                    onActivated: root.doRescan()
                }
            }
        }

        // ══ Body ═════════════════════════════════════════════════════════════
        Item {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true

            // ── GALLERY ──────────────────────────────────────────────────────
            // ── Choosing workspaces: the gallery crossfades into the picker ──
            // (components/WorkspacePicker — the panel folds into the same one.)
            FocusScope {
                id: chooseView
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: chooser.implicitHeight
                opacity: root.choosing ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                WorkspacePicker {
                    id: chooser
                    anchors.left: parent.left
                    anchors.right: parent.right
                    shown: root.choosing
                    picture: root.choosingPic
                    onApplied: list => Wallpaper.assign(root.choosingPic, list)
                    onCancelled: Wallpaper.cancelPick()
                }
            }

            // ── WallpaperGalleryView.qml
            WallpaperGalleryView { id: galleryView; page: root }

            // ── WallpaperBrowseView.qml
            WallpaperBrowseView { id: browserView; page: root }

            // ── WallpaperAppearanceView.qml
            WallpaperAppearanceView { id: appFlick; page: root }
            Scrollbar { flickable: appFlick }

            // ── WallpaperEffectsView.qml
            WallpaperEffectsView { id: fxFlick; page: root }
            Scrollbar { flickable: fxFlick }

            // ── WallpaperEngineView.qml
            WallpaperEngineView { id: engFlick; page: root }
            Scrollbar { flickable: engFlick }

            // ── WallpaperPropertiesView.qml
            WallpaperPropertiesView { id: propFlick; page: root }
            Scrollbar { flickable: propFlick }
        }
    }

    // ── Wheel = turn the page, anywhere over the gallery ─────────────────────
    // Declared AFTER the content so it sits on top; NoButton keeps it transparent
    // to clicks and hover. Deltas accumulate to a notch (±120) so a touchpad
    // doesn't fly through the library per swipe.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        enabled: root.view === "gallery" && !root.browsing && root.pageCount > 1

        property real acc: 0
        onWheel: function(ev) {
            acc += ev.angleDelta.y
            if (acc <= -120) { galleryView.pager.incrementCurrentIndex(); acc = 0 }
            else if (acc >= 120) { galleryView.pager.decrementCurrentIndex(); acc = 0 }
            ev.accepted = true
        }
    }


}
