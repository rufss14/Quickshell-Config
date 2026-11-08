pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

// ── ReloadWatch ───────────────────────────────────────────────────────────────
// What the last configuration reload did, for modules/panels/ReloadPopup to show.
//
// ── Why this exists ───────────────────────────────────────────────────────────
// A hot reload that fails leaves the OLD config running and says so only in the log
// ("Failed to load configuration … caused by …"). Save a file with a typo and nothing
// on screen changes — which reads as "the edit did nothing", and the next thing tried is
// a restart that then fails to start at all. ii shows the error in a popup; this is that.
//
// ── Quickshell's own popup ────────────────────────────────────────────────────
// Quickshell draws a reload card of its own, in a window of its own, after both events.
// `Quickshell.inhibitReloadPopup()` called from either handler suppresses it for that
// reload — which is done unless Config.reloadPopup is "off" (then it is Quickshell's to
// show, as it always was).
//
// ── Which generation hears what ───────────────────────────────────────────────
// `reloadFailed` goes to the generation that is STILL RUNNING (the new one never came up);
// `reloadCompleted` goes to the NEW one, after it is built — so this singleton, created by
// shell.qml's Connections, is the right place to hear both.
//
// `serial` counts events so the popup restarts its timer for a second failure with the same
// text (saving the same broken file twice). Config.reloadPopup says what is worth showing:
// "failures" (default), "all", or "off".
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property bool   failed: false
    property string error:  ""
    property int    serial: 0

    // Whether the popup should be up for the latest event.
    readonly property bool wanted: root.serial > 0
        && (Config.reloadPopup === "all" || (Config.reloadPopup === "failures" && root.failed))

    // Show the card without breaking anything:  qs ipc … call reloadcard fail | ok
    IpcHandler {
        target: "reloadcard"
        function fail(): void {
            root.failed = true
            root.error = "Failed to load configuration\n  caused by @shell.qml[211:19]: Type Bar unavailable\n  caused by @modules/bar/Bar.qml[1111:5]: Type DockHost unavailable\n  caused by @components/DockIconStrip.qml[1490:5]: LeadButton is not a type"
            root.serial++
        }
        function ok(): void {
            root.failed = false
            root.error = ""
            root.serial++
        }
    }

    Connections {
        target: Quickshell

        function onReloadCompleted() {
            if (Config.reloadPopup !== "off") Quickshell.inhibitReloadPopup()
            root.failed = false
            root.error = ""
            root.serial++
        }

        function onReloadFailed(error) {
            if (Config.reloadPopup !== "off") Quickshell.inhibitReloadPopup()
            root.failed = true
            root.error = String(error || "")
            root.serial++
        }
    }
}
