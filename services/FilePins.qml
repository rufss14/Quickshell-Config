pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "dock.js" as DockJs

// ── FilePins ──────────────────────────────────────────────────────────────────
// Files and folders pinned to the dock, and files pinned inside an app's jump
// list. App pins are Pins (shared with the launcher); these are the dock's own,
// in one JsonStore beside config.json:
//
//     { files: [{ path, name, dir, icon }], jump: { appKey: [path…] } }
//
// A file pinned to the dock learns what it is ONCE, at pin time — `gio info`
// says whether it's a folder and which themed icon describes it — so drawing it
// never touches the disk. (A pin whose file has since moved still shows; opening
// it is what fails, through gio, the same as a stale shortcut anywhere.)
//
// The file is hand-editable, so what's read back is validated: only absolute
// string paths survive, and a malformed entry is dropped rather than drawn.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    JsonStore {
        id: store
        path: Quickshell.statePath("dock-files.json")
        defaults: ({ files: [], jump: ({}) })
    }

    function _isPath(p) { return typeof p === "string" && p.startsWith("/") }

    readonly property var files: {
        const raw = store.value.files
        if (!Array.isArray(raw)) return []
        return raw.filter(f => f && root._isPath(f.path)).map(f => ({
            path: f.path,
            name: typeof f.name === "string" && f.name !== "" ? f.name : (f.path.split("/").pop() || f.path),
            dir:  f.dir === true,
            icon: typeof f.icon === "string" ? f.icon : ""
        }))
    }

    readonly property var _jump: {
        const raw = store.value.jump
        return raw && typeof raw === "object" && !Array.isArray(raw) ? raw : ({})
    }

    function _save(files, jump) {
        store.value = { files: files, jump: jump }
    }

    // ══ On the dock ═══════════════════════════════════════════════════════════
    function isPinned(path) { return root.files.some(f => f.path === path) }

    // Queued: `gio info` answers asynchronously, one path at a time.
    property var _queue: []

    function pin(path) {
        if (!root._isPath(path) || root.isPinned(path) || root._queue.indexOf(path) >= 0) return
        root._queue = root._queue.concat([path])
        if (!info.running) root._next()
    }

    function unpin(path) {
        root._save(root.files.filter(f => f.path !== path), root._jump)
    }

    function move(from, to) {
        const next = root.files.slice()
        if (from < 0 || from >= next.length || from === to) return
        const moved = next.splice(from, 1)[0]
        next.splice(Math.max(0, Math.min(to, next.length)), 0, moved)
        root._save(next, root._jump)
    }

    function _next() {
        if (root._queue.length === 0) return
        info.target = root._queue[0]
        info.command = ["gio", "info", "-a", "standard::type,standard::icon", "--", info.target]
        info.running = true
    }

    Process {
        id: info
        property string target: ""
        stdout: StdioCollector { id: infoOut }
        onExited: function(code) {
            const parsed = code === 0 ? DockJs.parseGioInfo(infoOut.text) : null
            const path = info.target
            root._queue = root._queue.slice(1)
            // A path gio can't describe (gone, unreadable) isn't pinned at all.
            if (parsed && !root.isPinned(path)) {
                const icon = parsed.icons.find(n => Quickshell.iconPath(n, true) !== "") ?? ""
                root._save(root.files.concat([{ path: path, name: path.split("/").pop() || path,
                                                dir: parsed.dir, icon: icon }]), root._jump)
            }
            root._next()
        }
    }

    // ══ Inside an app's jump list ═════════════════════════════════════════════
    // Windows' "Pinned" section: files you keep above the app's Recent ones.
    function jumpFor(key) {
        const list = root._jump[key]
        if (!Array.isArray(list)) return []
        return list.filter(root._isPath).map(p => ({ path: p, name: p.split("/").pop() || p }))
    }

    function isJumpPinned(key, path) { return root.jumpFor(key).some(f => f.path === path) }

    function pinJump(key, path) {
        if (!key || !root._isPath(path) || root.isJumpPinned(key, path)) return
        const jump = Object.assign({}, root._jump)
        jump[key] = root.jumpFor(key).map(f => f.path).concat([path])
        root._save(root.files, jump)
    }

    function unpinJump(key, path) {
        const jump = Object.assign({}, root._jump)
        const left = root.jumpFor(key).map(f => f.path).filter(p => p !== path)
        if (left.length > 0) jump[key] = left
        else delete jump[key]
        root._save(root.files, jump)
    }
}
