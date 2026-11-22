pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// ── WallColors ────────────────────────────────────────────────────────────────
// What each wallpaper is mostly, for the gallery's colour sort and its colour search: { picture path:
// "#rrggbb" }, an image's own path and a scene's PREVIEW path. scripts/wall-colors.py reads them (and caches
// them by path and time in $XDG_CACHE_HOME/quicktest/wall-colors.json, so a library is read once).
//
// Asked for, not always running: the gallery sets `wanted` while the sort is colour or the search is a colour
// name, and the library is read the first time that is true and again when it changes. `map` is {} until then.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property bool wanted: false
    readonly property var map: root._map
    property var _map: ({})
    readonly property bool busy: proc.running

    readonly property string cacheFile: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache"))
                                        + "/quicktest/wall-colors.json"

    // Every picture the gallery can show: the library, and each scene's preview.
    readonly property var paths: {
        const out = Wallpaper.wallpapers.slice()
        for (const it of WallpaperEngine.items) if (it.preview) out.push(it.preview)
        return out
    }
    property string _asked: ""

    // The libraries load a moment apart: wait for them to settle rather than read after each.
    Timer {
        id: settle
        interval: 600
        running: root.wanted && root.paths.length > 0
        onTriggered: root._run()
    }
    onWantedChanged: if (root.wanted) settle.restart()
    onPathsChanged: if (root.wanted) settle.restart()

    function _run() {
        const key = root.paths.join("\n")
        if (!root.wanted || key === root._asked || proc.running) return
        root._asked = key
        proc.rows = ({})
        proc.command = ["python3", Quickshell.shellPath("scripts/wall-colors.py"), root.cacheFile, "--"].concat(root.paths)
        proc.running = true
    }

    Process {
        id: proc
        property var rows: ({})
        stdout: SplitParser {
            onRead: function (line) {
                const i = line.indexOf("\t")
                if (i > 0) proc.rows[line.slice(i + 1)] = line.slice(0, i)
            }
        }
        onExited: {
            root._map = proc.rows
            // The library changed while it read: go again.
            if (root._asked !== root.paths.join("\n")) { root._asked = ""; settle.restart() }
        }
    }
}
