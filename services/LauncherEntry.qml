pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "unityentry.js" as UnityEntry

// ── LauncherEntry ─────────────────────────────────────────────────────────────
// What apps say about themselves on their dock icon: a badge count, a progress
// bar, a request for attention — the com.canonical.Unity.LauncherEntry signal,
// which Firefox (downloads), Chromium, Telegram, Discord and most KDE apps
// broadcast on the session bus. The dock shows the count as its badge (over the
// shell's own notification count), the progress as a bar on the icon, and the
// request the way it shows Hyprland's own urgency.
//
// Read through `dbus-monitor` — part of dbus itself, so present on every system
// that has a session bus — parsed line by line in unityentry.js
// (`bun scripts/test-unityentry.js`). Runs only while the dock is on.
//
// If the monitor is killed along with a crashed shell, it notices on its next
// write (SIGPIPE) — the first LauncherEntry signal after — and exits then.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // desktop id → { count, countVisible, progress, progressVisible, urgent }.
    // Look it up by a dock key through Taskbar.keyForAny — apps name themselves by
    // their .desktop id, which is usually, not always, the dock's key.
    property var entries: ({})

    property var _parser: UnityEntry.createParser()

    readonly property bool wanted: Config.dockEnabled
    // False for the few seconds after the monitor died, then true to relaunch it.
    // A flag the binding reads, never an assignment to `running` — that would
    // break the binding, and turning the dock off would no longer stop it.
    property bool _up: true

    Process {
        id: monitor
        running: root.wanted && root._up
        // `setpriv --pdeathsig TERM`: a SIGTERM'd shell (reload-quickshell.sh) runs no cleanup, and
        // dbus-monitor sleeps in a read() until a badge changes — so it outlived every restart.
        command: ["setpriv", "--pdeathsig", "TERM", "dbus-monitor", "--session",
                  "type='signal',interface='com.canonical.Unity.LauncherEntry',member='Update'"]
        stdout: SplitParser {
            onRead: function(line) {
                const u = root._parser.feed(line)
                if (u) root.entries = UnityEntry.apply(root.entries, u)
            }
        }
        // Died while still wanted (the bus restarted, say): try again shortly, with
        // a fresh parser — a half-read update from the old stream means nothing.
        onExited: {
            root._up = false
            if (root.wanted) respawn.restart()
        }
    }

    Timer {
        id: respawn
        interval: 5000
        onTriggered: {
            root._parser = UnityEntry.createParser()
            root._up = true
        }
    }

    // The dock turned off: forget what apps last said, so turning it back on
    // doesn't show a stale progress bar from an hour ago.
    onWantedChanged: {
        if (!root.wanted) root.entries = ({})
        else root._up = true
    }
}
