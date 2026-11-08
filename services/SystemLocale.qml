pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// ── SystemLocale ──────────────────────────────────────────────────────────────
// The system's LANG and the installed locales, through localectl — what Settings ›
// Language shows and sets. (Not the shell's own UI language: that's Translation.)
//
// Read on demand (`refresh()`, when the page opens), not at startup: nothing else
// needs it. Setting it goes through systemd-localed, which asks polkit; the result is
// re-read rather than trusted, because polkit may have refused.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property string current: ""     // e.g. "en_US.UTF-8"; "" until read
    property var    locales: []     // every installed locale, localectl's order
    property string status:  ""     // the last set's outcome, in words
    property bool   failed:  false

    function refresh() {
        currentQuery.running = false
        currentQuery.running = true
        if (!listQuery.running) listQuery.running = true
    }

    function setLocale(name) {
        root.failed = false
        root.status = "Applying " + name + "…"
        setProc.running = false
        // argv, never a shell string: `name` comes from localectl's own list, but it
        // still doesn't get spliced into a command line.
        setProc.command = ["localectl", "set-locale", "LANG=" + name]
        setProc.running = true
    }

    // `localectl status` prints a block; LANG= is the line that matters.
    Process {
        id: currentQuery
        command: ["bash", "-c",
                  "localectl status 2>/dev/null | sed -n 's/.*LANG=\\([^ ]*\\).*/\\1/p'"]
        stdout: StdioCollector { onStreamFinished: root.current = text.trim() }
    }

    Process {
        id: listQuery
        command: ["localectl", "list-locales"]
        stdout: StdioCollector {
            onStreamFinished: root.locales = text.trim() === "" ? [] : text.trim().split("\n")
        }
    }

    Process {
        id: setProc
        stderr: StdioCollector { id: setErr }
        onExited: function (code) {
            root.failed = code !== 0
            root.status = code === 0
                ? "Applied. Most apps pick it up on their next start."
                : (setErr.text.trim() || "Could not set the locale.")
            currentQuery.running = false
            currentQuery.running = true
        }
    }
}
