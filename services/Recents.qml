pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "xbel.js" as Xbel

// ── Recents ───────────────────────────────────────────────────────────────────
// The freedesktop recent-files store — $XDG_DATA_HOME/recently-used.xbel, the
// one GTK, GLib and most file managers write — read for the dock's jump lists.
//
// Parsed LAZILY: the file is rewritten every time any app opens a file, and
// nothing here needs it until a jump list opens. So a change only marks the
// parse stale; entries() reparses on the next ask. A missing file is the normal
// state on a machine nothing has written it on yet, not an error.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property string path:
        (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share"))
        + "/recently-used.xbel"

    property var _cache: []
    property bool _stale: true

    function entries() {
        if (root._stale) {
            root._cache = file.loaded ? Xbel.parse(file.text()) : []
            root._stale = false
        }
        return root._cache
    }

    FileView {
        id: file
        path: root.path
        preload: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root._stale = true
        onLoadFailed: root._stale = true
    }
}
