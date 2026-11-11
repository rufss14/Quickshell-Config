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

    // ══ Start-up settle ═══════════════════════════════════════════════════════
    // Quickshell asks Hyprland for monitors and workspaces once, right after its
    // `j/status` round trip, and ignores any refresh asked for while one is in flight
    // (`requestingWorkspaces` / `requestingMonitors` in the C++ IPC). A workspace event
    // that lands in that window is dropped, and nothing re-asks until the NEXT event —
    // so a reload could leave the bar's workspace pill showing a state that was already
    // out of date. Not reproduced or measured (a race, "sometimes"); this re-asks twice
    // while the shell settles, which is a socket request each, not a subprocess. QML's
    // refresh passes canCreate=false (qml.cpp): it corrects the state of workspaces and
    // monitors Quickshell already knows, and can neither add a missing workspace nor
    // drop a stale one.
    Timer {
        property int runs: 0
        running: true
        repeat: true
        interval: 2000
        onTriggered: {
            Hyprland.refreshMonitors()
            Hyprland.refreshWorkspaces()
            if (++runs >= 2) running = false
        }
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

    // ── The event-driven tier ─────────────────────────────────────────────────
    // For a watcher that needs window GEOMETRY but not live tracking of a drag —
    // the dock's "dodge windows" auto-hide. Instead of four requests a second, it
    // refreshes when Hyprland says something happened (a window opened, closed,
    // moved workspace, changed floating state, took focus…), debounced so a burst
    // of events costs one request.
    //
    // Hyprland emits NOTHING while a floating window is dragged or resized, so a
    // float moved over the dock would otherwise go unnoticed until the next event.
    // `floatPoll` covers exactly that case, slowly, and only while a floating
    // window is on a visible workspace.
    //
    // Superseded by acquire() when both are held — the 250ms loop already covers it.
    property int _eventRefs: 0
    function acquireEvents() { root._eventRefs++; eventRefresh.restart() }
    function releaseEvents() { root._eventRefs = Math.max(0, root._eventRefs - 1) }
    readonly property bool _eventMode: root._eventRefs > 0 && root._refs === 0

    Connections {
        target: Hyprland
        enabled: root._eventMode
        function onRawEvent(event) { eventRefresh.restart() }
    }

    // A window moving workspace changes neither the toplevel list nor (outside the two
    // tiers above) anything that re-asks, so `windows` kept the old workspaceId and
    // everything derived from it (the bar pill's per-app workspace icon) went stale.
    // Always on, but only for the move events: one debounced refresh per move.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "movewindow" || event.name === "movewindowv2")
                eventRefresh.restart()
        }
    }

    Timer {
        id: eventRefresh
        interval: 100
        onTriggered: {
            Hyprland.refreshToplevels()
            // The reply is asynchronous; rebuild once it has landed.
            eventSettle.restart()
        }
    }
    // The first rebuild() runs at construction, before Hyprland's IPC has answered, so
    // `windows` can come up empty (or without workspace ids) and nothing re-asks until the
    // overview opens. Re-ask a few times at start; rebuild() ignores an unchanged answer.
    property int _boot: 0
    Timer {
        running: root._boot < 6
        interval: 500
        repeat: true
        onTriggered: {
            root._boot++
            Hyprland.refreshToplevels()
            eventSettle.restart()
        }
    }

    Timer {
        id: eventSettle
        interval: 50
        onTriggered: root.rebuild()
    }

    // Assigned in rebuild(), not bound: a binding that walks Hyprland.monitors can
    // be re-entered while the model notifies mid-evaluation (see CavaBG.suppressed).
    property bool _floatVisible: false
    Timer {
        id: floatPoll
        running: root._eventMode && root._floatVisible
        interval: 1000
        repeat: true
        onTriggered: eventRefresh.restart()
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

    // A window's rectangle inside its workspace's preview box (the overview's cells): `g` is
    // geometryOf(), `scale` logical px → preview px, `fit` the box ({ w, h } — the monitor's
    // USABLE area, scaled). Offset by the monitor and its reserved edges, and kept INSIDE the
    // box. A fullscreen window covers the reserved edges too (the bar), so its raw size is
    // bigger than the area the box stands for: unclamped, it spilled past its cell to the right
    // and down (2026-10-20). It fills the box instead — it IS that whole screen.
    function previewRect(g, monitor, scale, fit) {
        if (g.fullscreen) return { x: 0, y: 0, w: fit.w, h: fit.h }
        const r = root.reservedOf(monitor)
        const w = Math.min(g.width  * scale, fit.w)
        const h = Math.min(g.height * scale, fit.h)
        return {
            x: Math.max(0, Math.min(fit.w - w, (g.x - (monitor?.x ?? 0) - r[0]) * scale)),
            y: Math.max(0, Math.min(fit.h - h, (g.y - (monitor?.y ?? 0) - r[1]) * scale)),
            w: w,
            h: h
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
                    // Whether the client is X11-under-XWayland rather than native
                    // Wayland. Only the keystroke injector cares (an X11 client needs
                    // XTEST, a Wayland one needs the virtual-keyboard protocol, and
                    // using the wrong one fails SILENTLY) — but geometryOf already
                    // reads it, so carrying it costs nothing and guessing costs a
                    // button that does nothing.
                    xwayland: g.xwayland,
                    at:       [g.x, g.y],
                    size:     [g.width, g.height],
                    floating: g.floating,
                    workspaceId: t.workspace?.id ?? -1,
                    monitorId:   t.monitor?.id ?? -1,
                    monitor:     t.monitor
                }
            })
        // Special workspaces (scratchpads, negative ids) and a window not on a workspace yet
        // (-1 from the fallback above) are not in `windows`: every consumer means the numbered ones.
        const regular = next.filter(w => w.workspaceId >= 0)

        // Ahead of the snapshot test: switching workspace changes what's VISIBLE
        // without changing any window, and the snapshot wouldn't see it.
        const visible = Hyprland.monitors.values.map(m => m.activeWorkspace?.id ?? -1)
        root._floatVisible = regular.some(w => w.floating && visible.indexOf(w.workspaceId) >= 0)

        const snapshot = regular.map(w =>
            w.address + ":" + w.workspaceId + ":" + w.at + ":" + w.size + ":" + w.title
        ).join("|")
        if (snapshot === root._snapshot) return


        // ── Occupancy, folded once ────────────────────────────────────────────
        // The grid asks "does workspace N have anything on it?" for every cell it
        // draws. Answering that with windowsOn(N) — a filter over the whole window
        // list, allocating a throwaway array only to read .length — meant ten full
        // passes over every window on every rebuild, and rebuild runs 4×/s while the
        // overview is open. One pass here answers all ten with a map lookup.
        const counts = ({})
        for (let i = 0; i < regular.length; i++) {
            const id = regular[i].workspaceId
            counts[id] = (counts[id] ?? 0) + 1
        }

        root._snapshot        = snapshot
        root.countByWorkspace = counts
        root.windows          = regular
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

    // workspaceId → how many windows are on it. Recomputed in rebuild(), so it is a
    // plain notifying property rather than a scan: safe to bind to, and O(1) to ask.
    // Kept in step with `windows` by being assigned in the same place.
    property var countByWorkspace: ({})

    // ── Workspaces ────────────────────────────────────────────────────────────
    readonly property var workspaces: Hyprland.workspaces.values

    function workspaceOccupied(id) {
        return (root.countByWorkspace[id] ?? 0) > 0
    }

    // Which monitor a workspace actually lives on right now. Workspaces here aren't
    // pinned to a monitor — any of them can end up on any screen — so the overview
    // can't assume a page's ten workspaces share one monitor's resolution. Null when
    // the workspace doesn't exist yet (never visited): callers fall back to whatever
    // monitor they were already assuming.
    function monitorForWorkspace(id) {
        const w = root.workspaces.find(w => w.id === id)
        return w ? w.monitor : null
    }

    readonly property int focusedWorkspaceId: {
        // Not `?? 1` alone: a monitor mid-teardown can hand back something that is neither null nor a number,
        // and an `int` property logs "Unable to assign [undefined] to int" for it.
        const id = Hyprland.focusedMonitor?.activeWorkspace?.id
        return typeof id === "number" && id > 0 ? id : 1
    }

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
    // ── on_current_monitor is not optional polish, it is the whole verb ───────
    // Without it, `focus({ workspace = N })` does NOT bring N to you. If N currently
    // lives on another monitor, Hyprland FOCUSES THAT MONITOR instead — you don't go
    // to the workspace, the workspace's screen goes to the front of the queue.
    //
    // That is wrong for every caller here. The bar pill and the overview grid are both
    // per-monitor surfaces drawing all ten workspaces as cells on YOUR screen; clicking
    // one means "put this here", which is exactly what SUPER+N already does
    // (binds.lua:41 has always passed on_current_monitor). The shell was the odd one out.
    //
    // ── Why it looked like a mouse bug ────────────────────────────────────────
    // The old form left focus on the OTHER monitor while the pointer stayed on this one.
    // With input:follow_mouse=1 and misc:mouse_move_focuses_monitor=true (both on here),
    // the first pointer movement after the click drags focus straight back — so the
    // workspace visibly flashed in and then reverted. The overview's own 1-9 keys ran
    // the identical dispatch and appeared to work only because a hand on the keyboard
    // generates no pointer motion to bounce it. Same bug, one input device hiding it.
    //
    // `follow` = false is for the restore in moveWindowToWorkspace() below, which is NOT
    // navigation: it puts focus back after the preselect dance, and must never drag a
    // workspace across monitors as a side effect of doing so.
    //
    // ── `monitor`, and why "current" still isn't enough ────────────────────────
    // `on_current_monitor` answers "put it on MY screen" only as well as Hyprland's own
    // idea of "current" tracks reality — and on a layer-shell overlay spanning several
    // outputs, it sometimes doesn't. The overview is a separate PanelWindow per monitor,
    // so clicking a cell on monitor B's grid is real input landing on a real surface on
    // B — but a fast click right after the pointer crosses onto B can beat Hyprland's own
    // mouse_move_focuses_monitor bookkeeping there, and the dispatch fires while Hyprland
    // still thinks A is current. `on_current_monitor` then does exactly what it says and
    // sends the workspace to A, next to nothing visibly wrong with the call itself —
    // "sometimes it doesn't send my current monitor" was this.
    //
    // A caller that already KNOWS which monitor it means (every overview surface does —
    // it's the one its own PanelWindow is on) can hand it here. Dispatched first and
    // dispatched separately: Hyprland processes its own dispatch queue in order over one
    // connection, so by the time the workspace-focus call below runs, "current" is
    // whatever we just told it to be — no race left to lose. Omit it and behaviour is
    // exactly what it always was.
    function focusWorkspace(id, follow, monitor) {
        const here = (follow === undefined) ? true : follow
        if (monitor && monitor.name)
            Hyprland.dispatch(`hl.dsp.focus({ monitor = "${monitor.name}" })`)
        Hyprland.dispatch(`hl.dsp.focus({ workspace = ${id}, on_current_monitor = ${here} })`)
    }

    // Every window selector goes through addr() — see the note above rebuild(). A bare
    // address is not an error Hyprland reports usefully; it just can't find the window.
    function focusWindow(address) {
        Hyprland.dispatch(`hl.dsp.focus({ window = "address:${root.addr(address)}" })`)
    }

    function closeWindow(address) {
        Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${root.addr(address)}" })`)
    }

    // Ends the Hyprland session — both power menus' "Log out". They used to run
    // `hyprctl dispatch exit`, the legacy spelling: under the Lua config manager a bare
    // word evaluates to nothing (the stub declares no global `exit`), so the dispatch
    // was rejected with nobody reading hyprctl's output. `hl.dsp.exit()` passes
    // `Hyprland --verify-config`, and through Hyprland.dispatch() a rejection is at
    // least logged ("Dispatch request … failed with error …").
    function exitSession() {
        Hyprland.dispatch("hl.dsp.exit()")
    }

    // Monitors off / on (the Inactivity panel's screen-off rule). The stub declares
    // `dpms` as `fun(...)`; the 0.56.2 binary has `Config::Actions::dpms(eTogglableAction,
    // monitor?)` and an "Invalid DPMS action" error, the same togglable `{ action = … }`
    // table `hl.dsp.window.float` takes. Not run live: `hyprctl dispatch 'hl.dsp.dpms({
    // action = "off" })'` from a terminal confirms it (wiggle the mouse to come back).
    function setDpms(on) {
        Hyprland.dispatch(`hl.dsp.dpms({ action = "${on ? "on" : "off"}" })`)
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

    // ── Undoing moves (the overview's Ctrl+Z / Undo chip) ─────────────────────
    // Every move of a window to a workspace — a drag, a Shift+click, the inspector's chips, the
    // inspector's swap — is logged as it is dispatched, with where each window WAS. Moves made
    // within `_stepMs` of each other are ONE step (a selection dragged, a swap's two halves).
    // `undoMove()` sends the last step's windows back and returns the workspaces they went to
    // (for the cell to ring). It cannot reopen a closed window, a tiled window returns to its
    // workspace and not its slot, and a window on a special workspace is not logged. The undo is
    // not logged itself. Held in memory only, cleared with `forgetMoves()`.
    property var moveLog: []                 // newest last: [{ moves: [{ address, from }] }]
    readonly property bool canUndoMove: root.moveLog.length > 0
    readonly property int _stepMs: 250
    readonly property int _logMax: 20
    function _logMove(address, to) {
        const a = root.addr(address)
        const w = root.windows.find(x => root.addr(x.address) === a)
        if (!w || w.workspaceId <= 0 || w.workspaceId === to) return
        const log = root.moveLog.slice()
        let step = stepTimer.running ? log[log.length - 1] : null
        if (!step) {
            step = { moves: [] }
            log.push(step)
        }
        // A window moved twice inside one step keeps its first origin.
        if (!step.moves.some(m => m.address === a)) step.moves.push({ address: a, from: w.workspaceId })
        root.moveLog = log.slice(-root._logMax)
        stepTimer.restart()
    }
    Timer { id: stepTimer; interval: root._stepMs }
    function undoMove() {
        const step = root.moveLog[root.moveLog.length - 1]
        if (!step) return []
        stepTimer.stop()
        root.moveLog = root.moveLog.slice(0, -1)
        const back = []
        for (const m of step.moves) {
            // Closed since: nothing to send back.
            if (!root.windows.some(w => root.addr(w.address) === m.address)) continue
            Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${m.from}, window = "address:${m.address}", follow = false })`)
            back.push(m.from)
        }
        return back
    }
    function forgetMoves() { stepTimer.stop(); root.moveLog = [] }

    function moveWindowToWorkspace(address, workspaceId, anchorAddress, direction) {
        root._logMove(address, workspaceId)
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
        //
        // `false` because this is a RESTORE, not navigation. focusWindow(anchor) above may
        // have carried focus to another monitor; pulling `back` onto whatever monitor we
        // happen to have landed on would rearrange the user's screens as a side effect of
        // dragging one window.
        if (hint && back > 0)
            root.focusWorkspace(back, false)
    }

    // ── Whole workspaces (the overview's inspector) ──────────────────────────
    // Each is window moves / closes by address, the lists read BEFORE anything is
    // dispatched — so a swap can't move a window twice. Nothing follows; nothing focuses.
    function moveAll(fromWs, toWs) {
        if (fromWs === toWs) return
        for (const w of root.windowsOn(fromWs)) {
            root._logMove(w.address, toWs)
            Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${toWs}, window = "address:${root.addr(w.address)}", follow = false })`)
        }
    }
    function swapWorkspaces(a, b) {
        if (a === b) return
        const fromA = root.windowsOn(a), fromB = root.windowsOn(b)
        for (const w of fromA) {
            root._logMove(w.address, b)
            Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${b}, window = "address:${root.addr(w.address)}", follow = false })`)
        }
        for (const w of fromB) {
            root._logMove(w.address, a)
            Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${a}, window = "address:${root.addr(w.address)}", follow = false })`)
        }
    }
    function closeAll(ws) {
        for (const w of root.windowsOn(ws)) root.closeWindow(w.address)
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
    //
    // ── EXCEPT across monitors, which is a different question ─────────────────
    // "Brings its workspace along" is true only when that workspace is already on the
    // monitor you're looking at. When it isn't, `focus({ window })` doesn't bring the
    // workspace to you — it moves FOCUS TO THE OTHER SCREEN and leaves the workspace
    // where it was. Your pointer stays behind on this monitor, and with
    // input:follow_mouse=1 and misc:mouse_move_focuses_monitor=true (both on here) the
    // first twitch of the mouse drags focus straight back. That is the "it flashes there
    // and then returns" report, and it is NOT a click bug.
    //
    // This is the path that actually bites, because an occupied cell in the overview is
    // almost entirely covered by its window previews — "clicking on workspace 4" is
    // nearly always clicking a WINDOW, which lands here and never went near
    // focusWorkspace(). Fixing only the bare-cell click fixed the case nobody hits.
    //
    // So: if the window is on another monitor, bring its workspace here FIRST (that
    // dispatch swaps the two monitors' workspaces and leaves focus — and the pointer —
    // on this one, measured), and only then focus the window, which is now local.
    //
    // The same-monitor case is untouched and still a single dispatch, so the
    // double-switch the comment above warns about doesn't come back.
    //
    // ── `originMonitor`, for the same reason focusWorkspace() takes one ────────
    // "Here" used to mean `Hyprland.focusedMonitor` — Quickshell's own cached read of
    // Hyprland's ambient state, which is exactly the value that can still be stale a
    // beat after the pointer crosses onto a monitor whose overview you just clicked in.
    // A caller that knows which PanelWindow the click came from knows "here" exactly,
    // with no round trip to wait on — pass it and the comparison (and the monitor-focus
    // dispatch inside focusWorkspace) use that instead. Omitted, this falls back to the
    // old ambient read, unchanged.
    function goToWindow(address, originMonitor) {
        const a = root.addr(address)
        const w = root.windows.find(x => x.address === a)
        if (w) root.goToToplevel(w.toplevel, originMonitor)
        else   root.focusWindow(address)
    }

    // The same, for a caller already holding the HyprlandToplevel (the dock).
    // Reads the window's workspace and monitor LIVE rather than off the `windows`
    // snapshot above, which is only rebuilt while something holds acquire() — so a
    // window moved to another screen while nothing was watching is still found
    // where it really is.
    function goToToplevel(toplevel, originMonitor) {
        if (!toplevel) return
        const ws   = toplevel.workspace
        const mon  = toplevel.monitor
        const here = originMonitor || Hyprland.focusedMonitor

        if (ws && ws.id > 0 && mon && here && mon.id !== here.id)
            root.focusWorkspace(ws.id, true, originMonitor)

        root.focusWindow(toplevel.address)
    }
}
