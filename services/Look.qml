pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "look.js" as L

// ── Look ──────────────────────────────────────────────────────────────────────
// Export how the shell looks to one .json file, and import someone else's. The file format,
// the whitelist and every check on what comes in are in look.js (tested: scripts/test-look.js);
// this is the part that talks to files, Config and the colour library.
//
// ── Flow ──────────────────────────────────────────────────────────────────────
// Export  exportLook(name) builds the document from the live state, asks WHERE with a save
//         dialog, and writes it. Nothing is written until a path is chosen.
// Import  importLook() asks for a file, reads at most MAX_BYTES of it, and parses it into
//         `pending`. NOTHING is applied yet: the page shows what the look would change, and
//         applyPending() is the button. A look rewrites the bar, the sidebar and the colours,
//         so it is applied only on a yes, and `undo()` puts every preference back (a
//         `_dumpPrefs()` taken just before).
//
// ── What it will not touch ────────────────────────────────────────────────────
// Motion (the user's comfort setting), paths, accounts, anything not in look.js's whitelist.
// The colour scheme is saved to the library under the look's name (never over an existing
// scheme: look.js uniqueName) and then worn like any scheme from it.
//
// ── Undo and colours ──────────────────────────────────────────────────────────
// Preferences come back exactly. Colours come back from the WALLPAPER (Wallpaper
// reapplyPalette), not from whatever scheme or pins were in force before; the scheme the look
// added stays in the library.
//
// The file dialogs are zenity's (the one graphical picker the shell already uses for
// wallpapers). Without it the controls are disabled with a reason: `blocker()`, the same
// contract as NightLight.blocker().
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── What the page reads ───────────────────────────────────────────────────
    // A parsed look waiting for Apply, or null.
    property var pending: null
    readonly property var pendingLines: root.pending ? L.summary(root.pending) : []
    property int pendingSkipped: 0
    // The last result, one line, and whether it was a failure.
    property string status: ""
    property bool statusBad: false

    property var _undo: null
    readonly property bool canUndo: root._undo !== null
    readonly property bool busy: exportDialog.running || importDialog.running || reader.running

    // ── Is there a file dialog? ───────────────────────────────────────────────
    property bool _hasZenity: true
    property bool _probed: false
    function blocker() {
        return root._probed && !root._hasZenity ? "Needs zenity (the file dialog) — install it to export or import" : ""
    }
    Process {
        running: true
        command: ["sh", "-c", "command -v zenity >/dev/null 2>&1"]
        onExited: function (code) { root._hasZenity = code === 0; root._probed = true }
    }

    function _ok(text)   { root.status = text; root.statusBad = false }
    function _fail(text) { root.status = text; root.statusBad = true }

    // ── Export ────────────────────────────────────────────────────────────────
    property string _outText: ""

    function _styleValues() {
        const out = {}
        for (const k of L.styleKeys()) out[k] = Config[k]
        return out
    }

    function exportLook(name) {
        if (root.busy || root.blocker() !== "") return
        const doc = L.build({
            name: name, shell: Config.version, wallpaper: Wallpaper.current,
            values: root._styleValues(), bar: Config._snapshot(),
            // The live palette, in the mode the shell is in (what the look looks like right now).
            mode: Config.themeMode, palette: ColorScheme.live
        })
        const text = L.serialize(doc)
        if (text.length > L.MAX_BYTES) { root._fail("This look is too big to export"); return }
        root._outText = text
        exportDialog._path = ""
        exportDialog.command = ["zenity", "--file-selection", "--save", "--confirm-overwrite",
            "--title=Export look", "--filename=" + (Quickshell.env("HOME") || "") + "/" + L.fileName(doc.name),
            "--file-filter=Look files | *.look.json *.json"]
        exportDialog.running = true
    }

    Process {
        id: exportDialog
        property string _path: ""
        stdout: SplitParser { onRead: function (line) { if (line.trim() !== "") exportDialog._path = line.trim() } }
        // 1 = cancelled, which is not an error.
        onExited: function (code) {
            if (code !== 0 || exportDialog._path === "") return
            const p = /\.json$/i.test(exportDialog._path) ? exportDialog._path : exportDialog._path + ".look.json"
            writerC.createObject(root, { path: p })
        }
    }

    // One writer per export, destroyed when it is done. `path` is set at creation so the
    // text goes to the file that was chosen.
    Component {
        id: writerC
        FileView {
            id: w
            printErrors: false
            Component.onCompleted: w.setText(root._outText)
            onSaved: { root._ok("Saved to " + w.path); root._outText = ""; w.destroy() }
            onSaveFailed: { root._fail("Couldn't write " + w.path); root._outText = ""; w.destroy() }
        }
    }

    // ── Import ────────────────────────────────────────────────────────────────
    function importLook() {
        if (root.busy || root.blocker() !== "") return
        importDialog._path = ""
        importDialog.running = true
    }

    Process {
        id: importDialog
        property string _path: ""
        command: ["zenity", "--file-selection", "--title=Import look",
                  "--file-filter=Look files | *.look.json *.json"]
        stdout: SplitParser { onRead: function (line) { if (line.trim() !== "") importDialog._path = line.trim() } }
        onExited: function (code) {
            if (code !== 0 || importDialog._path === "") return
            // One byte past the limit is enough to know it is too big; the file is never read whole.
            reader.command = ["head", "-c", String(L.MAX_BYTES + 1), "--", importDialog._path]
            reader.running = true
        }
    }

    Process {
        id: reader
        stdout: StdioCollector {
            onStreamFinished: root._parsed(text)
        }
        onExited: function (code) { if (code !== 0) root._fail("Couldn't read that file") }
    }

    function _parsed(text) {
        const r = L.parse(text)
        if (!r.ok) { root.pending = null; root._fail(r.error); return }
        root.pending = r.look
        root.pendingSkipped = r.skipped
        root.status = ""
    }

    function discard() { root.pending = null }

    // ── Apply / undo ──────────────────────────────────────────────────────────
    function applyPending() {
        const look = root.pending
        if (!look) return
        root.pending = null
        root._undo = { prefs: Config._dumpPrefs(), scheme: look.scheme !== null }
        Config.applyLook(look.style, look.bar)
        if (look.scheme) root._wearScheme(look)
        root._ok("Applied “" + look.name + "”" + (root.pendingSkipped > 0
            ? "  ·  " + root.pendingSkipped + " value" + (root.pendingSkipped === 1 ? "" : "s") + " skipped" : ""))
    }

    function _wearScheme(look) {
        // Saved to the library first so it can be found again; but only when the library has been
        // listed, or "no scheme by that name" could be a list that hasn't arrived yet, and the new
        // one would be written over a real scheme.
        if (ColorScheme.presetsReady) {
            const variants = ({})
            variants[look.scheme.mode] = look.scheme.palette
            ColorScheme.saveScheme(L.uniqueName(look.name, ColorScheme.presets.map(p => p.name)), variants)
        }
        ColorScheme.applyPalette(look.scheme.palette, "Look · " + look.name)
    }

    function undo() {
        const u = root._undo
        if (!u) return
        root._undo = null
        Config.restorePrefs(u.prefs)
        if (u.scheme) Wallpaper.reapplyPalette()
        root._ok("Put back what you had")
    }
}
