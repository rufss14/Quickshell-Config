pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

// ── Secrets ───────────────────────────────────────────────────────────────────
// Where the shell keeps its API keys and the Discord client secret, for Settings › Setup.
// The keys themselves never come through here (QML never holds them): the three
// credentials scripts keep them, in the system keyring when one is RUNNING and in 0600
// files otherwise (scripts/secretstore.py says how it decides, and why nothing moves
// until you ask). This only reports counts and runs the move.
//
//   keyring   "running" · "activatable" · "missing" · "no-tool" · "" before the first look
//   inFile    secrets still in a file
//   inKeyring secrets that have moved
//
// `blocker()` is the usual contract: "" when Move can work, else the reason.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property string keyring: ""
    property int    inFile: 0
    property int    inKeyring: 0
    property bool   busy: false
    // What the last Move did: "" · "moved 2" · "1 could not be moved — kept in the file".
    property string result: ""

    readonly property string script: Quickshell.shellPath("scripts/secrets-tool.py")

    function refresh() {
        if (root.busy) return
        statusProc.running = true
    }

    function blocker() {
        if (root.keyring === "")            return Translation.tr("Checking…")
        if (root.keyring === "no-tool")     return Translation.tr("Needs libsecret's secret-tool")
        if (root.keyring === "missing")     return Translation.tr("No keyring service is running or installable (GNOME Keyring, KWallet…)")
        if (root.inFile === 0)              return Translation.tr("Nothing is stored in a file")
        return ""
    }

    function migrate() {
        if (root.busy || root.blocker() !== "") return
        root.busy = true
        root.result = ""
        migrateProc.running = true
    }

    Process {
        id: statusProc
        command: ["python3", root.script, "status"]
        stdout: StdioCollector {
            onStreamFinished: root._apply(text)
        }
    }

    Process {
        id: migrateProc
        command: ["python3", root.script, "migrate"]
        stdout: StdioCollector {
            onStreamFinished: {
                let r = null
                try { r = JSON.parse(text) } catch (e) { }
                root.busy = false
                if (r === null) { root.result = Translation.tr("The helper said something odd"); return }
                root.result = r.failed > 0
                    ? Translation.tr("%1 could not be moved — kept in the file").arg(r.failed)
                    : r.moved > 0 ? Translation.tr("Moved %1").arg(r.moved) : Translation.tr("Nothing to move")
                root._apply(text)
            }
        }
    }

    function _apply(text) {
        try {
            const r = JSON.parse(text)
            if (r.keyring !== undefined) root.keyring = r.keyring
            root.inFile = r.inFile ?? root.inFile
            root.inKeyring = r.inKeyring ?? root.inKeyring
        } catch (e) { }
    }
}
