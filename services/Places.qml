pragma Singleton
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import QtQuick
import "dock.js" as DockJs

// ── Places ────────────────────────────────────────────────────────────────────
// The two folders the dock can show at its end, macOS-style: the Trash (full or
// empty, open it, empty it, drop files on it) and Downloads (the newest files,
// fanned out on a click).
//
// Both are watched with FolderListModel — Qt's own filesystem watcher, the one
// WallpaperPanel already uses — so the trash icon fills and empties as things
// are deleted, and a finished download appears, without polling.
//
// Everything that TOUCHES files goes through `gio` (glib2, already a dependency
// for the screenshot toast's trash): `gio trash` moves to the trash rather than
// deleting (the same rule the screenshot toast follows), `gio open` hands a file
// to its default app, `trash:///` is the file manager's own trash view.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property string home:       Quickshell.env("HOME") || ""
    readonly property string dataHome:   Quickshell.env("XDG_DATA_HOME")   || (root.home + "/.local/share")
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (root.home + "/.config")

    // ══ Trash ═════════════════════════════════════════════════════════════════
    // The home trash only (the spec's $XDG_DATA_HOME/Trash) — per-mount trashes
    // on other drives aren't counted, but `gio trash --empty` does empty them.
    readonly property string trashDir: root.dataHome + "/Trash/files"
    readonly property int  trashCount: trash.count
    readonly property bool trashFull:  trash.count > 0

    FolderListModel {
        id: trash
        folder: DockJs.pathToFileUrl(root.trashDir)
        showDirs: true
        showFiles: true
        showHidden: true
        showDotAndDotDot: false
    }

    function openTrash()  { Quickshell.execDetached(["gio", "open", "trash:///"]) }
    function emptyTrash() { Quickshell.execDetached(["gio", "trash", "--empty"]) }

    // Absolute paths only (a dropped file's is), after `--`, so no file can be read
    // as an option.
    function trashFiles(paths) {
        const abs = paths.filter(p => typeof p === "string" && p.startsWith("/"))
        if (abs.length === 0) return false
        Quickshell.execDetached(["gio", "trash", "--"].concat(abs))
        return true
    }

    // ══ Downloads ═════════════════════════════════════════════════════════════
    // Where xdg-user-dirs says it is (a localised "Téléchargements" included),
    // else ~/Downloads — see dock.js downloadDir().
    FileView {
        id: userDirs
        path: root.configHome + "/user-dirs.dirs"
        preload: true
        printErrors: false
    }

    readonly property string downloadsDir:
        DockJs.downloadDir(userDirs.loaded ? userDirs.text() : "", root.home)

    FolderListModel {
        id: downloads
        folder: DockJs.pathToFileUrl(root.downloadsDir)
        showDirs: false
        showHidden: false
        showDotAndDotDot: false
        sortField: FolderListModel.Time
    }

    // Newest first, `limit` of them, skipping downloads still in flight — a
    // browser's partial file isn't something to open yet.
    readonly property var _partial: /\.(part|crdownload|download|tmp)$/i
    function recentDownloads(limit) {
        const out = []
        for (let i = 0; i < downloads.count && out.length < limit; i++) {
            const name = downloads.get(i, "fileName")
            if (root._partial.test(name)) continue
            out.push({ path: downloads.get(i, "filePath"), name: name })
        }
        return out
    }

    function openFile(path)  { if (path) Quickshell.execDetached(["gio", "open", "--", path]) }
    function openDownloads() { Quickshell.execDetached(["gio", "open", "--", root.downloadsDir]) }
}
