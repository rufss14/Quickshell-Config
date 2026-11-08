pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../config"
import "../state"
import "switcher.js" as S

// ── Switcher ──────────────────────────────────────────────────────────────────
// Alt+Tab and window search, both over the overview's workspace grid — no second list
// of windows (a "recent" row was built and dropped 2026-10-04: it drew the same windows
// the grid already does). Every window on every workspace, most recently used first;
// a search over them; which one is picked (the grid lifts it, rings it and labels it,
// and turns to its page); going there.
//
// ── Alt+Tab ───────────────────────────────────────────────────────────────────
// Hyprland owns the keys. hypr/binds.lua posts a CUSTOM EVENT on the event socket the
// shell already reads (SfxKeys' channel — no `qs ipc` spawn per key, which would put a
// process start between you and every Tab), carrying Hyprland's own focus history:
//
//     ALT+TAB        qs-switch:next:<addr>,…     ALT+SHIFT+TAB   qs-switch:prev:<addr>,…
//     Alt let go     qs-switch:up                (a non-consuming release bind)
//
// The first Tab picks the window you were on before this one and starts `revealDelay`;
// let go of Alt before it runs out and you're simply there — nothing is drawn (the quick
// flick between two windows). Hold on and the overview opens with the pick lit in the
// grid, Tab walking it in recently-used order; letting go goes to the pick. Escape (the overview's) cancels. The overview takes
// the keyboard while it's up, but Tab and Alt's release still reach Hyprland's binds
// first, so they keep arriving here.
//
// ── Recency ───────────────────────────────────────────────────────────────────
// `_mru` follows Hyprland.activeToplevel from the shell's start (eager in shell.qml for
// that reason), and every Alt+Tab replaces it with the compositor's own list — the
// authority. Windows neither has seen go after, by `focusHistoryID` off the last
// refresh.
//
// Logic: services/switcher.js (`bun scripts/test-switcher.js`).
// Diagnose: `qs ipc -c ~/.config/quicktest call switcher status` (counts only).
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // How long Alt+Tab waits before drawing anything: a flick back to the last window
    // must not flash the overview. An input threshold, not a motion — it holds with
    // animations off.
    readonly property int revealDelay: 150

    // ── The windows ───────────────────────────────────────────────────────────
    // Plain records the row and switcher.js both read. The title is read off the
    // toplevel LIVE (Hypr.windows' copy is only rebuilt when windows come and go);
    // the app id off its Wayland handle, which is there before any refresh.
    readonly property var windows: Hypr.windows.map(w => {
        const t = w.toplevel
        const cls = t?.wayland?.appId || w.appClass || ""
        return {
            address:  w.address,
            title:    t?.title ?? w.title ?? "",
            appClass: cls,
            appName:  Icons.nameForAppId(cls),
            workspaceId: t?.workspace?.id ?? w.workspaceId,
            toplevel: t,
            wayland:  w.wayland
        }
    })

    property var _mru: []
    // address → when it last LOST focus (ms), for the pick's "2 min ago".
    property var _leftAt: ({})
    property string _activeAddr: ""
    function _touch(address) {
        const a = S.norm(address ?? "")
        if (a === "" || a === root._activeAddr) return
        if (root._activeAddr !== "") {
            const left = Object.assign({}, root._leftAt)
            left[root._activeAddr] = Date.now()
            // Closed windows drop out, so the map can't grow for the session's life.
            for (const k of Object.keys(left))
                if (k !== root._activeAddr && !root.windows.some(w => w.address === k)) delete left[k]
            root._leftAt = left
        }
        root._activeAddr = a
        root._mru = [a].concat(root._mru.filter(x => x !== a)).slice(0, 64)
    }

    // The pick's label: "now" for the window you're on, else when you left it.
    // Reads Clock.now, so it moves on with the minute.
    function agoText(address) {
        const a = S.norm(address ?? "")
        if (a === "") return ""
        if (a === root._activeAddr) return "now"
        return S.ago(root._leftAt[a] ?? 0, Clock.now.getTime())
    }

    function _history(address) {
        const w = root.windows.find(x => x.address === address)
        return w?.toplevel?.lastIpcObject?.focusHistoryID
    }

    // Most recent first: Alt+Tab's order with no query.
    readonly property var recent: S.arrange(root._mru, S.byHistory(root.windows, a => root._history(a)))

    // ── Search ────────────────────────────────────────────────────────────────
    property string query: ""
    // What a flag operator (`is:floating`…) asks of a window. Read LIVE and only when one is typed:
    // the records above leave Hyprland's `lastIpcObject` alone, since it is rewritten on every
    // refresh and would rebuild the whole list four times a second.
    function _facts(w) {
        const g = Hypr.geometryOf(w.toplevel)
        return {
            floating:   g.floating,
            fullscreen: g.fullscreen,
            pinned:     w.toplevel?.lastIpcObject?.pinned ?? false,
            audio:      Audio.streamsFor(w.appClass).length > 0
        }
    }
    readonly property var list: S.filter(root.recent, root.query, root._facts)

    // The search text with a flag switched on or off, and whether one is on (the overview's filter chips).
    function withFlag(text, flag) { return S.toggleFlag(text, flag) }
    function flagOn(flag)         { return S.hasFlag(root.query, flag) }
    // The picked window's record (null for none) — the grid turns to its page.
    readonly property var picked: root.index >= 0 ? (root.list[root.index] ?? null) : null

    function setQuery(q) {
        root.query = q
        root.index = (root.query.trim() !== "" && root.list.length > 0) ? 0 : (root.active ? root.index : -1)
    }

    // ── The pick ──────────────────────────────────────────────────────────────
    property int index: -1
    property string selectedAddress: ""
    onIndexChanged: {
        root.selectedAddress = root.list[root.index]?.address ?? ""
        // A pick and a selection are two ways of choosing, and the island shows one: choosing
        // the other lets the first go.
        if (root.index >= 0 && root.marks.length > 0) root.marks = []
    }
    // The list moves under the pick (a window opened, a title changed the search):
    // the same window stays picked.
    onListChanged: {
        const i = S.keep(root.selectedAddress, root.list, root.index)
        if (i !== root.index) root.index = i
        else root.selectedAddress = root.list[root.index]?.address ?? ""
    }

    // ── Marks: several windows at once (Ctrl+click in the overview) ───────────
    // Addresses, in the order they were marked. What the island's bulk face acts on, and what
    // dragging one of them or Shift+click on a cell moves together. A window that closes drops
    // out of `marked` by itself (it is read off `windows`), so a stale address costs nothing.
    property var marks: []
    readonly property var marked: root.windows.filter(w => root.marks.indexOf(w.address) >= 0)
    function toggleMark(address) {
        const has = root.marks.indexOf(address) >= 0
        root.marks = has ? root.marks.filter(a => a !== address) : root.marks.concat([address])
        if (root.marks.length > 0) root.index = -1
    }
    // Ctrl+A: every window the search shows (all of them when it is empty, or only the workspace
    // `ws` has when given one); again, when they are all marked already, lets them go.
    function markAll(ws) {
        const from = root.query.trim() !== "" || ws === undefined ? root.list
                   : root.list.filter(w => w.workspaceId === ws)
        const addrs = from.map(w => w.address)
        const all = addrs.length > 0 && addrs.every(a => root.marks.indexOf(a) >= 0)
        root.marks = all ? [] : addrs
        if (root.marks.length > 0) root.index = -1
    }
    function clearMarks() { if (root.marks.length > 0) root.marks = [] }

    function select(i) { root.index = (i >= 0 && i < root.list.length) ? i : -1 }
    // Pick a window by address (the overview's right-click: inspect it); a second right-click on the
    // pick lets it go. One not in the list (a search hides it) is not picked.
    function selectAddress(address) {
        const i = root.list.findIndex(w => w.address === address)
        root.select(i >= 0 && i === root.index ? -1 : i)
    }
    function stepBy(dir) { root.index = S.step(root.index, root.list.length, dir) }

    // Go to the pick (Enter): focus it where it is — its own workspace on its own
    // monitor — the way Alt+Tab does. The grid's click keeps its own rule (bring the
    // workspace here).
    function activate(i) {
        const w = root.list[i ?? root.index]
        root._finish()
        UiState.leaveOverview(w ? w.workspaceId : -1)
        if (w) Hypr.focusWindow(w.address)
    }

    // ── Alt+Tab ───────────────────────────────────────────────────────────────
    // Switching: from the first Tab until Alt is let go (or Escape).
    property bool active: false
    // Whether Alt+Tab opened the overview (vs. finding it already open).
    property bool _opened: false

    function _onKey(ev) {
        if (ev.kind === "up") {
            if (root.active) root.commit()
            return
        }
        const dir = ev.kind === "prev" ? -1 : 1
        if (!root.active) {
            if (ev.order.length > 0) root._mru = ev.order
            root.active = true
            root.query = ""
            if (UiState.overviewOpen) {
                root._opened = false
                root.index = S.step(root.index, root.list.length, dir)
            } else {
                root._opened = true
                root.index = S.initialIndex(root.list.length, ev.kind)
                reveal.restart()
            }
            return
        }
        root.stepBy(dir)
    }

    function commit() {
        const w = root.list[root.index]
        reveal.stop()
        root._finish()
        UiState.leaveOverview(w ? w.workspaceId : -1)
        if (w) Hypr.focusWindow(w.address)
    }

    function cancel() {
        reveal.stop()
        root._finish()
    }

    function _finish() {
        root.active = false
        root._opened = false
        root.query = ""
        root.index = -1
        root.marks = []
    }

    Timer {
        id: reveal
        interval: root.revealDelay
        onTriggered: if (root.active && !UiState.overviewOpen) UiState.overviewOpen = true
    }

    // The overview closing any other way (Escape, a click elsewhere) ends a switch.
    Connections {
        target: UiState
        function onOverviewOpenChanged() {
            if (!UiState.overviewOpen) { reveal.stop(); root._finish() }
        }
    }

    Connections {
        target: Hyprland
        function onActiveToplevelChanged() { root._touch(Hyprland.activeToplevel?.address) }
        function onRawEvent(event) {
            if (event.name !== "custom") return
            const ev = S.parseEvent(event.data)
            if (ev !== null) root._onKey(ev)
        }
    }

    IpcHandler {
        target: "switcher"
        function next(): void   { root._onKey({ kind: "next", order: [] }) }
        function prev(): void   { root._onKey({ kind: "prev", order: [] }) }
        function commit(): void { if (root.active) root.commit() }
        function cancel(): void { root.cancel() }
        function status(): string {
            return "active=" + root.active + " windows=" + root.windows.length + " recent=" + root._mru.length
                 + " listed=" + root.list.length + " index=" + root.index + " query=" + (root.query !== "")
        }
    }
}
