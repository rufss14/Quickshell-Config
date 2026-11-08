import QtQuick
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/wallpaperentry.js" as WEntry

// ── One gallery entry, as the grid tile and the list row both read it ─────────
// A gallery entry is one of THREE things: a string (an image's absolute path), a scene object from
// WallpaperEngine ({ id, title, type, preview }), or the action card, the gallery's first tile
// ({ action, glyph, title, caption }: "Add images" / "Browse the Workshop"). Shape, key, name, thumb, type and isGif all come from the
// shared normaliser — services/wallpaperentry.js, exercised by `bun scripts/test-wallpaperentry.js`.
// WallpaperPage goes through the same function, so the views can no longer disagree about what
// an entry is. Delegates branch on the entry's shape, never on the images/scenes flag: during a tab
// switch the flag flips while the outgoing delegates still exist for a frame, and a string would
// be asked for `.id`. Only the LIVE bits (isCurrent / busy) touch singletons.
//
// The tile and the row used to carry a copy each (and drifted: one latch was `removeLatch`, the
// other `removeRowLatch`). Non-visual; `panel` is the WallpaperPanel it lives in.
QtObject {
    id: st

    required property var panel
    property var entry

    readonly property var    d:        WEntry.describe(st.entry)
    readonly property bool   isAction: st.d.kind === "action"
    readonly property bool   isScene:  st.d.kind === "scene"
    readonly property string key:      st.d.key
    readonly property string name:     st.d.name
    readonly property string thumb:    st.d.thumb
    readonly property bool   isGif:    st.d.isGif
    // The file extension for an image, "scene"/"video" for a workshop item.
    readonly property string kind:     st.d.type

    readonly property bool isCurrent: st.isAction ? false
        : st.isScene ? (st.panel.sceneOnScreen && WallpaperEngine.current === st.key)
        : (!st.panel.sceneOnScreen && !st.panel.gamePaused && !Config.wallMaterial && Wallpaper.current === st.name)

    // What a workspace would be given (services/Wallpaper's values), and whether it
    // is already EVERYWHERE — a current wallpaper that some workspace overrides still
    // offers Apply, since the left click puts it back on all of them.
    readonly property string value: st.isScene ? "scene:" + st.key : st.key
    readonly property bool applied: st.isCurrent && Wallpaper.everywhere(st.value, true)

    readonly property bool busy: st.isAction ? false
        : st.isScene ? (WallpaperEngine.busy && Config.wpeCurrent === st.key)
        : (Wallpaper.applying && Wallpaper.applyingPath === st.key)

    readonly property bool isFav: st.isAction ? false
        : st.isScene ? Config.wpeFavorites.indexOf(st.key) !== -1
        : Config.wallFavorites.indexOf(st.name) !== -1

    function toggleFav() {
        if (st.isAction) return
        if (st.isScene) Config.wpeFavToggle(st.key)
        else            Config.wallFavToggle(st.name)
    }

    readonly property bool selected: st.panel.selecting && st.panel.isSelected(st.key)

    function doApply() {
        const p = st.panel
        if (p.selecting) { if (!st.isAction) p.toggleSelect(st.key); return }
        if (st.isAction) { p.runAction(st.entry.action); return }
        if (p.pickingActive) {
            if (!st.isScene) return
            if (p.pickingScreens.length > 0)
                WallpaperEngine.spanMonitors(p.pickingScreens, st.key)
            else
                WallpaperEngine.assignMonitor(p.pickingForScreen, st.key)
            p.pickingForScreen = ""
            p.pickingScreens = []
            return
        }
        if (p.applyBusy || p.blocked !== "" || st.applied) return
        if (st.isScene) Wallpaper.pickScene(st.key)
        else            Wallpaper.pick(st.key)
    }

    // Right-click: choose which workspaces get it (the gallery folds into the picker).
    function doChoose() {
        const p = st.panel
        if (p.selecting || st.isAction || p.pickingActive || p.applyBusy || p.blocked !== "") return
        Wallpaper.choose(st.value)
    }

    // ── Removing: armed, then confirmed ───────────────────────────────────────
    // One click arms, a second within four seconds does it. An image goes to the
    // TRASH (gio trash — they're the user's own files). A scene's files are
    // deleted AND its Workshop page opens, because unsubscribing is a Steam
    // account action with no local API: delete alone and Steam downloads it
    // again on the next sync, which would read as the removal not working.
    readonly property ArmLatch removeLatch: ArmLatch {
        onConfirmed: {
            if (st.isScene) WallpaperEngine.removeAndUnsubscribe(st.key)
            else            Wallpaper.remove(st.key)
        }
    }

    function doRemove() {
        if (st.isAction) return
        st.removeLatch.trigger()
    }
}
