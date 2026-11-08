pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import Qt.labs.folderlistmodel
import "../config"

// ── Translation ───────────────────────────────────────────────────────────────
// The shell's strings in the language you read. `Translation.tr("English text")` returns
// the entry for that exact text in translations/<code>.json, or the text itself when there
// is none — so a missing language, a missing entry and an English locale all read as
// English, never as a blank or a key name.
//
//     text: Translation.tr("Reload failed")
//     text: Translation.tr("Moved %1 keys").arg(n)      // a sentence with a number: placeholder
//     label: Translation.tr(modelData.label)             // data: mark it N_("…") where it is written
//
// ── Which language ────────────────────────────────────────────────────────────
// Config.uiLanguage: "auto" follows the system locale (Qt.locale().name, "fr_FR"), or a code
// from translations/. Exact match first, then any file in the same language ("pt_PT" gets
// pt_BR's), then English. Setting it applies at once — `tr()` reads `table`, so every
// binding that calls it re-evaluates when a different file loads.
//
// ── What this does NOT do yet ─────────────────────────────────────────────────
// Only the strings wrapped in tr() are translated; the rest of the shell is still English.
// scripts/translations.py finds the wrapped ones (and fails the tests when en_US.json is
// stale); `status` reports a language's coverage. The settings search index is built from
// English text and is not translated.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property string dir: Quickshell.shellPath("translations")

    // Codes with a file, sorted: ["de_DE", "en_US", …]. Filled by the folder scan.
    property var available: []

    readonly property string wanted: Config.uiLanguage === "auto" ? Qt.locale().name : Config.uiLanguage

    // The file that will be read, or "" for plain English.
    readonly property string resolved: {
        const w = root.wanted
        if (root.available.indexOf(w) >= 0 && !w.startsWith("en_")) return w
        const lang = w.split("_")[0]
        if (lang === "en") return ""
        const same = root.available.filter(c => c.split("_")[0] === lang)
        return same.length > 0 ? same[0] : ""
    }

    // {"English text": "translation"} — reassigned whole on load, which is what
    // notifies every binding that read it through tr().
    property var table: ({})

    function tr(text) {
        const key = String(text === undefined || text === null ? "" : text)
        if (key === "") return ""
        const t = root.table[key]
        return (typeof t === "string" && t !== "") ? t : key
    }

    // A language's own name for itself, for the picker ("français", "Deutsch").
    function nameOf(code) {
        const l = Qt.locale(code)
        const n = l.nativeLanguageName
        return n ? n.charAt(0).toUpperCase() + n.slice(1) : code
    }

    FolderListModel {
        id: scan
        folder: "file://" + root.dir
        nameFilters: ["*.json"]
        showDirs: false
        onCountChanged: root._rescan()
        onStatusChanged: if (status === FolderListModel.Ready) root._rescan()
    }
    function _rescan() {
        const out = []
        for (let i = 0; i < scan.count; i++) {
            const n = String(scan.get(i, "fileName"))
            if (n.endsWith(".json")) out.push(n.slice(0, -5))
        }
        out.sort()
        root.available = out
    }

    FileView {
        id: file
        path: root.resolved !== "" ? root.dir + "/" + root.resolved + ".json" : ""
        preload: true
        printErrors: false
        // A translator saving the file shows up at once.
        watchChanges: true
        onFileChanged: file.reload()
        onLoaded: {
            try {
                const data = JSON.parse(file.text())
                root.table = (data && typeof data === "object") ? data : ({})
            } catch (e) {
                console.warn("Translation: could not read", root.resolved, "—", e)
                root.table = ({})
            }
        }
        onLoadFailed: root.table = ({})
    }

    // English (or no file at all): nothing to look up.
    onResolvedChanged: if (root.resolved === "") root.table = ({})
}
