pragma Singleton
import Quickshell
import Quickshell.Hyprland
import QtQuick

// ── Hypr ──────────────────────────────────────────────────────────────────────
// Window geometry and monitor layout, for the overview.
//
// ── What this replaces ────────────────────────────────────────────────────────
// The vendored overview shipped a `HyprlandData` singleton that did this:
//
//     Connections {
//         target: Hyprland
//         function onRawEvent(event) { updateAll() }   // ← FOUR hyprctl processes
//     }
//
// `updateAll()` spawned `hyprctl clients -j`, `hyprctl monitors -j`,
// `hyprctl layers -j`, `hyprctl workspaces -j` and `hyprctl activeworkspace -j`,
// parsed five JSON blobs, and rebuilt every list — on EVERY Hyprland event. Every
// focus change, every window title update, every workspace switch. Dragging one
// window across the overview fires dozens of events, so it spawned processes in a
// tight loop exactly when the UI most needed to stay smooth.
//
// None of it was necessary. `HyprlandToplevel.lastIpcObject` IS that window's
// `hyprctl clients` record, and `HyprlandMonitor.lastIpcObject` is its monitor
// record — Quickshell receives both over the event socket it already holds open.
// Zero subprocesses.
//
// ══ THE TRAP: QVariantList is not a JS Array ══════════════════════════════════
// `lastIpcObject` is a QVariantMap, so its list members (`at`, `size`, `reserved`)
// arrive as QVariantList. They index like arrays. They JSON.stringify like arrays.
//
//     Array.isArray(ipc.at)   →   FALSE
//
// Guard with Array.isArray() and every value is silently discarded for its
// fallback: every window reads back at 0,0 sized 100x100 (so every preview renders
// as a tiny stub in the corner), and every monitor reports zero reserved space (so
// previews are offset by the height of the bar).
//
// This cost hours, because it disguises itself. `JSON.stringify(ipc.at)` prints
// `[418,205]` — so every debug print looks perfect while the code takes the
// fallback branch. It also mimics several *other* bugs convincingly: it looks like
// the property doesn't notify, like bindings don't track it, like the data isn't
// there yet. It is there, it does notify, and bindings track it fine. Use `_nums()`
// below and never reach for Array.isArray on anything out of an IPC object.
//
// ── The one real quirk ────────────────────────────────────────────────────────
// MONITORS populate `lastIpcObject` on their own. TOPLEVELS do not — theirs stays
// empty until something calls `Hyprland.refreshToplevels()`. And since a window can
// move while you're looking at it, that has to be re-asked periodically. Hence the
// refresh loop below, which runs ONLY while something is watching.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // Convert a QVariantList (or anything array-like) to a plain JS number array.
    // See the header — this exists because Array.isArray() lies about them.
    function _nums(v, fallback) {
        if (!v || v.length === undefined || v.length < fallback.length) return fallback
        const out = []
        for (let i = 0; i < fallback.length; i++) out.push(Number(v[i]))
        return out
    }

    // ══ Freshness ═════════════════════════════════════════════════════════════
    // Refcounted: the overview acquires on open and releases on close. Nothing is
    // asked of Hyprland while it's shut.
    //
    // This re-asks on a timer rather than off `rawEvent`, for two reasons: a window
    // being dragged moves continuously without necessarily emitting an event we'd
    // catch, and `refreshToplevels()` called during this singleton's construction is
    // a no-op (the IPC object isn't connected yet), so a one-shot at acquire time
    // can silently miss.
    //
    // It is a request over the socket Quickshell already holds — NOT a subprocess.
    // Four socket round-trips a second while the overview is open, versus the old
    // code's four PROCESS SPAWNS per Hyprland event.
    property int _refs: 0

    function acquire() { root._refs++ }
    function release() { root._refs = Math.max(0, root._refs - 1) }

    Timer {
        running: root._refs > 0
        interval: 250
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            Hyprland.refreshToplevels()
            root.rebuild()
        }
    }

    // ── Monitors ──────────────────────────────────────────────────────────────
    readonly property var monitors: Hyprland.monitors.values

    function monitorFor(screen) { return Hyprland.monitorFor(screen) }

    // Hyprland reserves screen edges for layer-shell surfaces — our own bar takes
    // 40px off the top. The overview must exclude that, or every window preview is
    // offset by the bar's height.
    //   reserved = [left, top, right, bottom]
    function reservedOf(monitor) {
        return root._nums(monitor?.lastIpcObject?.reserved, [0, 0, 0, 0])
    }

    // Transform is 0-7; the odd values are the 90°/270° rotations, which swap the
    // monitor's logical axes.
    function isRotated(monitor) {
        return ((monitor?.lastIpcObject?.transform ?? 0) % 2) === 1
    }

    // Usable area in logical pixels: physical size ÷ scale, minus reserved edges,
    // accounting for rotation. This is the rectangle a workspace preview represents.
    function usableSize(monitor) {
        if (!monitor) return { width: 1920, height: 1080 }

        const scale = monitor.scale || 1
        const res   = root.reservedOf(monitor)
        const rot   = root.isRotated(monitor)

        return {
            width:  (rot ? monitor.height : monitor.width)  / scale - res[0] - res[2],
            height: (rot ? monitor.width  : monitor.height) / scale - res[1] - res[3]
        }
    }

    // ── Windows ───────────────────────────────────────────────────────────────
    // Geometry for one toplevel, in Hyprland's logical coordinates. Reading
    // `lastIpcObject` inside a binding works — the property notifies correctly.
    function geometryOf(toplevel) {
        const ipc  = toplevel?.lastIpcObject ?? {}
        const at   = root._nums(ipc.at,   [0, 0])
        const size = root._nums(ipc.size, [100, 100])
        return {
            x: at[0],  y: at[1],
            width: size[0], height: size[1],
            appClass:   ipc["class"] ?? "",
            floating:   ipc.floating ?? false,
            xwayland:   ipc.xwayland ?? false,
            fullscreen: (ipc.fullscreen ?? 0) !== 0
        }
    }

    // A flat list, for things that GROUP rather than position (the overview dock).
    //
    // Rebuilt rather than bound, and guarded by a snapshot compare: an unguarded
    // rebuild would hand out a brand-new array four times a second, and any Repeater
    // keyed on it would destroy and recreate every delegate — tearing down the live
    // ScreencopyView captures behind the window previews. If nothing moved, nothing
    // is reassigned.
    property var windows: []
    property string _snapshot: ""

    // ── Window addresses need an 0x prefix. Hyprland's does not add it. ───────
    // Quickshell reports `toplevel.address` as bare hex — "562d73b1be60". Hyprland's
    // `address:` selector expects the C-style pointer — "0x562d73b1be60". Hand it the
    // bare form and it answers:
    //
    //     hl.focus: window not found
    //
    // …and does nothing. Every focus, close and move this shell sent was addressing a
    // window that did not exist, which is why dragging a window between workspaces
    // appeared to be a *drag* bug and survived three rewrites of the drag. It never
    // was: the drop fired, the dispatch went out, and Hyprland threw it away.
    //
    // Normalised once, here, so no call site can forget. (The previous overview did the
    // same thing at every use site: `` `0x${toplevel.HyprlandToplevel.address}` ``.)
    function addr(a) {
        if (!a) return ""
        return a.startsWith("0x") ? a : "0x" + a
    }

    function rebuild() {
        const next = Hyprland.toplevels.values
            .map(t => {
                const g = root.geometryOf(t)
                return {
                    toplevel: t,
                    wayland:  t.wayland,           // what ScreencopyView captures from
                    address:  root.addr(t.address),
                    title:    t.title,
                    appClass: g.appClass,
                    at:       [g.x, g.y],
                    size:     [g.width, g.height],
                    floating: g.floating,
                    workspaceId: t.workspace?.id ?? -1,
                    monitorId:   t.monitor?.id ?? -1,
                    monitor:     t.monitor
                }
            })
            .filter(w => w.workspaceId >= 0)

        const snapshot = next.map(w =>
            w.address + ":" + w.workspaceId + ":" + w.at + ":" + w.size + ":" + w.title
        ).join("|")
        if (snapshot === root._snapshot) return

        root._snapshot = snapshot
        root.windows   = next
    }

    // Windows opened / closed / moved workspace.
    Connections {
        target: Hyprland.toplevels
        function onValuesChanged() { root.rebuild() }
    }

    Component.onCompleted: root.rebuild()

    function windowsOn(workspaceId) {
        return root.windows.filter(w => w.workspaceId === workspaceId)
    }

    // ── Workspaces ────────────────────────────────────────────────────────────
    readonly property var workspaces: Hyprland.workspaces.values

    function workspaceOccupied(id) {
        return root.windows.some(w => w.workspaceId === id)
    }

    readonly property int focusedWorkspaceId:
        Hyprland.focusedMonitor?.activeWorkspace?.id ?? 1

    // ── Dispatch ──────────────────────────────────────────────────────────────
    // This Hyprland runs in LUA dispatch mode — every dispatch in this shell is
    // `hl.dsp.*` form. The legacy space-separated syntax is a *lua syntax error* here
    // ("')' expected near '2'"), so it cannot be used at all.
    //
    // ── Read this before touching a dispatch ──────────────────────────────────
    // Hyprland validates the KEYS of the table and, if it doesn't recognise one, drops
    // the whole call. It does not warn, it does not log, and `hyprctl` still answers
    // "ok" — because "ok" only means the dispatch was QUEUED, not that it ran. An
    // invalid key is therefore indistinguishable from a no-op, which makes this the
    // single easiest place in the shell to be confidently wrong.
    //
    // Do NOT trust the binary's "Expected one of:" strings. They are incomplete, and
    // trusting them has now broken this file twice:
    //
    //   • hl.focus's list omits `workspace`  — yet `workspace` works (binds.lua).
    //   • hl.window.move's list omits `window` — yet `window` works, and is exactly
    //     how the previous overview moved windows. Believing that list is what led to
    //     a focus→move→restore-focus dance here, which was both wrong and janky.
    //
    // The only trustworthy references are forms already known to RUN:
    // ~/.config/hypr/binds.lua, and the old overview preserved in the trash at
    // .local/share/Trash/files/overview/modules/overview/OverviewWidget.qml.
    function focusWorkspace(id) {
        Hyprland.dispatch(`hl.dsp.focus({ workspace = ${id} })`)
    }

    // Every window selector goes through addr() — see the note above rebuild(). A bare
    // address is not an error Hyprland reports usefully; it just can't find the window.
    function focusWindow(address) {
        Hyprland.dispatch(`hl.dsp.focus({ window = "address:${root.addr(address)}" })`)
    }

    function closeWindow(address) {
        Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${root.addr(address)}" })`)
    }

    // ── Move a window to another workspace ────────────────────────────────────
    //
    // `follow = false` is valid and IS honoured — so the move alone never switches
    // workspace and never warps the pointer. (The earlier conditional focus-restore was
    // fighting a problem that didn't exist; it's gone.)
    //
    // ── Placing it where the user actually dropped it ─────────────────────────
    // `window.move` APPENDS the window to the target layout — you cannot hand it a
    // coordinate. I concluded from that (and from `window.swap` only ever acting on the
    // active window) that precise placement was impossible. That was wrong: I never
    // looked at `layout`.
    //
    //     hl.dsp.layout("preselect <l|r|u|d>")
    //
    // is dwindle's preselect hint — it tells the layout which side of the CURRENTLY
    // FOCUSED window the next arrival should take. So:
    //
    //     focus(anchor)            ← the window sitting under the drop point
    //     layout("preselect dir")  ← which half of it the drop landed in
    //     move(window → ws)        ← lands exactly there
    //     focus(originWorkspace)   ← put us back
    //
    // The cost is honest and unavoidable: focusing the anchor briefly visits the target
    // workspace, so there's a short flash behind a see-through overlay. It only happens
    // when dropping onto a workspace that already has windows — an empty workspace needs
    // no anchor, so that path stays flash-free. `smartPlacement` turns it off.
    property bool smartPlacement: true

    function moveWindowToWorkspace(address, workspaceId, anchorAddress, direction) {
        const hint = root.smartPlacement && anchorAddress && direction
        const back = root.focusedWorkspaceId

        if (hint) {
            root.focusWindow(anchorAddress)
            Hyprland.dispatch(`hl.dsp.layout("preselect ${direction}")`)
        }

        Hyprland.dispatch(
            `hl.dsp.window.move({ workspace = ${workspaceId}, window = "address:${root.addr(address)}", follow = false })`)

        // Only needed because the preselect hint moved focus. Hyprland applies dispatches
        // in order, so this lands last.
        if (hint && back > 0)
            root.focusWorkspace(back)
    }

    // Go to a specific window. Focus the WINDOW — not its workspace.
    //
    // This used to dispatch a focusWorkspace() first, on the theory that focusing by
    // address didn't carry you to the window's workspace. It does. What it didn't do
    // was work at all, because the address was missing its 0x prefix (see addr()), and
    // I papered over the symptom with a workspace jump instead of finding the cause.
    //
    // With a valid address, `hl.dsp.focus({ window = … })` lands on the window and
    // brings its workspace along. The extra dispatch now only adds a visible
    // double-switch.
    function goToWindow(address) {
        root.focusWindow(address)
    }
}
