pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../config"
import "../state"
import "snap.js" as S

// ── Snap ──────────────────────────────────────────────────────────────────────
// Snap zones for FLOATING windows (`Config.snapZones`): SUPER-drag one to the screen's
// left or right edge for a half, a corner for a quarter, the top (just under the bar) to
// fill the screen. Tiled windows are Hyprland's tiling's, and are left alone.
//
// ── How it knows ──────────────────────────────────────────────────────────────
// Hyprland owns the drag and says nothing mid-way; the windrag hook in hypr/binds.lua
// (the workspace pill's) reports the press (`UiState.windowDrag`) and the release. While
// a floating window is carried, Pointer's fast poll follows the pointer and `zone` /
// `rect` say what a release would do — modules/desktop/SnapOverlay draws it. The release
// arrives as `UiState.windowLanded` ONLY if no workspace pill took the drop, so a window
// let go on the pill goes to that workspace and is never also snapped.
//
// The move is two Lua dispatches (resize, then move — snap.js `dispatches`), with
// Hyprland's own gaps so a snapped window lines up with tiled ones. Unverified on a live
// Hyprland: the `window =` selector on hl.dsp.window.move/resize (their error text names
// `{ x, y, relative?, window? }` for resize) — a reload is the test.
// Logic: snap.js (`bun scripts/test-snap.js`).
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property bool enabled: Config.snapZones

    // The window being carried, if it's a floating one.
    readonly property var carried: UiState.windowDrag === "" ? null
        : (Hypr.windows.find(w => w.address === Hypr.addr(UiState.windowDrag)) ?? null)
    readonly property bool active: root.enabled && root.carried !== null
        && (root.carried.toplevel?.lastIpcObject?.floating ?? root.carried.floating) === true

    // What a release would do now (global layout pixels), and on which monitor.
    property string zone: ""
    property var rect: null
    property string monitorName: ""

    property bool _held: false
    onActiveChanged: {
        if (root.active === root._held) return
        if (root.active) {
            Pointer.acquireFast()
            Hyprland.refreshMonitors()      // `reserved` comes from the last refresh
        } else {
            Pointer.releaseFast()
            root.zone = ""
            root.monitorName = ""
        }
        root._held = root.active
    }
    Component.onDestruction: if (root._held) Pointer.releaseFast()

    Connections {
        target: Pointer
        enabled: root.active
        function onPosChanged() { root._follow(Pointer.pos.x, Pointer.pos.y) }
    }

    // The monitor under a global point, as { name, area } — the usable rectangle.
    function _where(px, py) {
        for (const m of Hypr.monitors) {
            const scale = m.scale || 1
            const rot = Hypr.isRotated(m)
            const w = (rot ? m.height : m.width) / scale
            const h = (rot ? m.width : m.height) / scale
            if (px >= m.x && px < m.x + w && py >= m.y && py < m.y + h)
                return { name: m.name, area: S.usable({ x: m.x, y: m.y, w: w, h: h }, Hypr.reservedOf(m)) }
        }
        return null
    }

    function _plan(px, py) {
        const at = root._where(px, py)
        if (!at) return { zone: "", rect: null, name: "" }
        const z = S.zoneAt(px, py, at.area)
        return { zone: z, rect: S.rectFor(z, at.area, Blend.v.gaps_out, Blend.v.gaps_in), name: at.name }
    }

    // Put a window in a zone of ITS monitor ("left", "right", "max", "tl", "tr", "bl", "br"),
    // the same rectangles a drag-to-edge gives — the overview inspector's snap chips. A tiled
    // window is floated first (a zone is a floating place).
    function snapWindow(address, zone) {
        const w = Hypr.windows.find(x => x.address === Hypr.addr(address))
        const m = w?.monitor
        if (!w || !m) return
        const scale = m.scale || 1
        const rot = Hypr.isRotated(m)
        const area = S.usable({ x: m.x, y: m.y, w: (rot ? m.height : m.width) / scale, h: (rot ? m.width : m.height) / scale },
                              Hypr.reservedOf(m))
        const rect = S.rectFor(zone, area, Blend.v.gaps_out, Blend.v.gaps_in)
        if (!rect) return
        if (!Hypr.geometryOf(w.toplevel).floating) ActiveWindow.toggleFloating(w.address)
        for (const lua of S.dispatches(w.address, rect)) Hyprland.dispatch(lua)
    }

    function _follow(px, py) {
        const p = root._plan(px, py)
        root.monitorName = p.name
        // `rect` keeps its last value when the zone goes, so the overlay fades out
        // where it was rather than jumping (the fade-keeps-its-copy rule).
        if (p.rect) root.rect = p.rect
        root.zone = p.zone
    }

    // ── Landing ───────────────────────────────────────────────────────────────
    // Hyprland says nothing about a dragged window, and a toplevel's record
    // (`lastIpcObject`: floating, where it is) stays EMPTY until something calls
    // `refreshToplevels()` — which only the overview, the peek and the dock's dodge do,
    // while they are open. So a drop is not judged on what Hypr.windows says (it reads
    // "tiled" for a window nobody has refreshed, and the first version of this never
    // moved anything). Ask for the record, and decide once the answer has had time to
    // come back over the local socket: floating? a zone? else the widgets' grid.
    //
    // `Config.snapToGrid`: the window's top-left goes to the nearest dot of the desktop
    // widgets' grid (`Config.widgetGrid`, from the monitor's corner).
    property var _landing: null
    function _land(address, m, px, py) {
        const t = Hyprland.toplevels.values.find(v => Hypr.addr(v.address) === Hypr.addr(address))
        if (!t) return
        root._landing = { toplevel: t, address: Hypr.addr(address), mon: m, px: px, py: py }
        Hyprland.refreshToplevels()
        landWait.restart()
    }
    Timer {
        id: landWait
        interval: 120
        onTriggered: {
            const L = root._landing
            root._landing = null
            if (!L) return
            const g = Hypr.geometryOf(L.toplevel)
            if (!g.floating) return
            // A zone wins: the half, quarter or fill the preview showed.
            if (root.enabled) {
                const p = root._plan(L.px, L.py)
                if (p.rect) {
                    for (const lua of S.dispatches(L.address, p.rect)) Hyprland.dispatch(lua)
                    return
                }
            }
            if (!Config.snapToGrid) return
            const at = root._where(g.x + g.width / 2, g.y + g.height / 2) ?? root._where(L.mon.x + 1, L.mon.y + 1)
            if (!at) return
            const pt = S.gridPoint({ x: g.x, y: g.y, w: g.width, h: g.height }, { x: L.mon.x, y: L.mon.y },
                                   at.area, Config.widgetGrid)
            if (pt) for (const lua of S.dispatches(L.address, pt)) Hyprland.dispatch(lua)
        }
    }

    Connections {
        target: UiState
        function onWindowLanded(address, monitor, x, y) {
            if (!root.enabled && !Config.snapToGrid) return
            const m = Hypr.monitors.find(v => v.name === monitor)
            if (m) root._land(address, m, m.x + x, m.y + y)
        }
        // The press: learn whether the carried window floats NOW, so the zone preview
        // knows (`active` reads it from the same record).
        function onWindowDragChanged() { if (UiState.windowDrag !== "") Hyprland.refreshToplevels() }
    }
}
