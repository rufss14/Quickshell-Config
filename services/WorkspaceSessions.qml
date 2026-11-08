pragma Singleton
import Quickshell
import QtQuick
import "../config"

// ── WorkspaceSessions ─────────────────────────────────────────────────────────
// Named snapshots of what's open where — "Work", "Gaming" — saved from the overview and
// started back later (2026-10-20, the user's pick). A session is each workspace's APPS (by
// desktop entry), once per app per workspace: a browser restores its own windows, and
// Hyprland can't recreate a window anyway, only start its app.
//
// ── Restoring: one app at a time ──────────────────────────────────────────────
// A new window opens on the FOCUSED workspace, so each app is started with its workspace
// focused, and the next waits until that app's window has appeared (or `patience` runs out
// — an app that opens no window, or one already running that only raises itself). Slower
// than firing them all, but it lands every one where it belongs using only the dispatches
// this shell already uses; Hyprland's exec-with-rules form isn't documented for 0.56.
// You're returned to where you were at the end.
//
// Stored in Quickshell.statePath("workspace-sessions.json"):
//     { version: 1, sessions: [{ name, at, apps: [{ entry, appClass, ws }] }] }
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property int maxSessions: 12
    readonly property int patience: 8000

    JsonStore {
        id: store
        path: Quickshell.statePath("workspace-sessions.json")
        defaults: ({ version: 1, sessions: [] })
    }

    // Only well-formed sessions come through (the file is hand-editable).
    readonly property var sessions: {
        const v = store.value
        const list = v && Array.isArray(v.sessions) ? v.sessions : []
        return list.filter(s => s && typeof s.name === "string" && s.name !== "" && Array.isArray(s.apps))
                   .map(s => ({ name: s.name.slice(0, 40), at: Number(s.at) || 0,
                                apps: s.apps.filter(a => a && typeof a.entry === "string" && Number.isInteger(a.ws) && a.ws > 0) }))
    }

    // What's open now, as a session's apps.
    function capture() {
        const out = [], seen = {}
        for (const w of Hypr.windows) {
            if (w.workspaceId <= 0 || !w.appClass) continue
            const entry = Taskbar.entryFor(Taskbar.keyFor(w.appClass))
            if (!entry) continue
            const k = entry.id + "@" + w.workspaceId
            if (seen[k]) continue
            seen[k] = true
            out.push({ entry: entry.id, appClass: w.appClass, ws: w.workspaceId })
        }
        out.sort((a, b) => a.ws - b.ws)
        return out
    }

    // Save what's open as `name` (replacing one of that name). "" = nothing to save.
    function save(name) {
        const n = String(name ?? "").replace(/[\n\r\0]/g, " ").trim().slice(0, 40)
        const apps = root.capture()
        if (n === "" || apps.length === 0) return false
        const rest = root.sessions.filter(s => s.name !== n)
        store.value = { version: 1, sessions: [{ name: n, at: Date.now(), apps: apps }].concat(rest).slice(0, root.maxSessions) }
        return true
    }
    function remove(name) {
        store.value = { version: 1, sessions: root.sessions.filter(s => s.name !== name) }
    }

    // ── Restoring ─────────────────────────────────────────────────────────────
    property string restoring: ""            // the session's name while it runs
    property var _queue: []
    property int _back: -1
    property var _waitFor: null              // { key, before: { address: true } }
    readonly property int left: root._queue.length

    function restore(name) {
        if (root.restoring !== "") return
        const s = root.sessions.find(x => x.name === name)
        if (!s) return
        root._back = Hypr.focusedWorkspaceId
        root._queue = s.apps.slice()
        root.restoring = s.name
        // Hypr only refreshes window records (their class) while someone holds it.
        Hypr.acquire()
        root._next()
    }
    function cancel() {
        root._queue = []
        root._finish()
    }

    function _next() {
        if (root._queue.length === 0) { root._finish(); return }
        const a = root._queue[0]
        root._queue = root._queue.slice(1)
        const entry = DesktopEntries.byId(a.entry)
        if (!entry) { root._next(); return }
        const before = {}
        for (const w of Hypr.windows) before[w.address] = true
        root._waitFor = { key: Taskbar.keyFor(a.appClass || a.entry), before: before }
        Hypr.focusWorkspace(a.ws, true)
        Launcher.launch(entry)
        giveUp.restart()
    }
    function _finish() {
        giveUp.stop()
        root._waitFor = null
        if (root.restoring !== "") {
            if (root._back > 0) Hypr.focusWorkspace(root._back, true)
            Hypr.release()
        }
        root.restoring = ""
    }

    // Its window turned up: on to the next.
    Connections {
        target: Hypr
        enabled: root._waitFor !== null
        function onWindowsChanged() {
            const wf = root._waitFor
            if (!wf) return
            for (const w of Hypr.windows)
                // The class can lag a new window's first record; its Wayland app id doesn't.
                if (!wf.before[w.address] && Taskbar.keyFor(w.appClass || (w.wayland?.appId ?? "")) === wf.key) {
                    root._waitFor = null
                    giveUp.stop()
                    Qt.callLater(root._next)
                    return
                }
        }
    }
    Timer {
        id: giveUp
        interval: root.patience
        onTriggered: { root._waitFor = null; root._next() }
    }
}
