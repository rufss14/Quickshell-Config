pragma Singleton
import Quickshell
import QtQuick
import "../config"

// ── WorkspaceLabels ───────────────────────────────────────────────────────────
// Names and icons for workspaces — but STORED PER APP (Config.appLabels, keyed by app id): a
// workspace wears the label of its biggest labelled window's app. So "Code" with a code icon
// follows VS Code to whichever workspace it's on; move things around and the labels move
// with them (the user's call, 2026-10-20 — numbered labels went stale the moment you
// rearranged). Set from the overview's window inspector (its workspace page); shown on the overview's cells and, the
// icon, in place of the number in the bar's WorkspacesPill.
//
// `icons` is the set offered: Material Symbols names already in the bundled font (a new one
// would need `material-symbols-map.py --emit`).
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property var icons: ["code", "terminal", "public", "chat", "mail", "sports_esports",
                                  "music_note", "movie", "folder", "description", "palette", "star"]

    // A window record's app key: its class, or (a record Hypr hasn't refreshed yet) its
    // Wayland app id — through Taskbar.keyFor, the dock's own canonical key.
    function keyOf(w) { return Taskbar.keyFor(w?.appClass || (w?.wayland?.appId ?? "")) }

    // The apps on a workspace, biggest window first, once each: [{ key, appClass }].
    function appsOn(ws) {
        const wins = Hypr.windows.filter(w => w.workspaceId === ws)
        wins.sort((a, b) => b.size[0] * b.size[1] - a.size[0] * a.size[1])
        const out = [], seen = {}
        for (const w of wins) {
            const k = root.keyOf(w)
            if (k === "" || seen[k]) continue
            seen[k] = true
            out.push({ key: k, appClass: w.appClass || (w.wayland?.appId ?? "") })
        }
        return out
    }

    function appLabel(key) { return Config.appLabels[key] ?? null }

    // The label a workspace wears: its first labelled app's (biggest window first), or null.
    function labelOf(ws) {
        for (const a of root.appsOn(ws)) {
            const l = root.appLabel(a.key)
            if (l) return l
        }
        return null
    }
    function nameOf(ws) { return root.labelOf(ws)?.name ?? "" }
    function iconOf(ws) { return root.labelOf(ws)?.icon ?? "" }

    // Either may be ""; both "" forgets the app.
    function setApp(key, name, icon) {
        if (!key) return
        const m = Object.assign({}, Config.appLabels)
        const n = String(name ?? "").replace(/[\n\r\0]/g, " ").trim().slice(0, 32)
        const i = root.icons.indexOf(icon) >= 0 ? icon : ""
        if (n === "" && i === "") delete m[key]
        else m[key] = { name: n, icon: i }
        Config.appLabels = m
    }
    function setAppName(key, name) { root.setApp(key, name, root.appLabel(key)?.icon ?? "") }
    function setAppIcon(key, icon) { root.setApp(key, root.appLabel(key)?.name ?? "", icon) }
}
