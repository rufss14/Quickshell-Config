pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "sudolock.js" as Lock

// ── SudoLock ──────────────────────────────────────────────────────────────────
// Whether pam_faillock has locked the user out of sudo right now — so a panel
// with a password box can SAY so, instead of "failed" (which invites the retry
// that keeps the lock going). The arithmetic is sudolock.js
// (`bun scripts/test-sudolock.js`); this runs `faillock --user $USER`, which any
// user may do for their own tally, and reads faillock.conf.
//
// Asked, never polled: call check() after a sudo run failed on its password, or
// when a password box opens. While locked, a timer checks again the moment the
// lock should lift.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property bool locked: root._s.locked
    // ms since the epoch; -1 = until an admin runs `faillock --reset`.
    readonly property real until: root._s.until
    readonly property string message: !root.locked ? ""
        : root.until < 0
          ? "sudo is locked after too many wrong passwords. It won't unlock by itself — "
            + "from a root shell, run: faillock --user " + root._user + " --reset"
          : "sudo is locked after too many wrong passwords, until "
            + Qt.formatTime(new Date(root.until), "hh:mm") + ". Any attempt before then fails, "
            + "even with the right password."

    property var _s: ({ locked: false, until: 0, count: 0, deny: 3 })
    readonly property string _user: Quickshell.env("USER") || ""

    function check() {
        if (root._user === "" || probe.running) return
        probe.running = true
    }

    FileView {
        id: conf
        path: "/etc/security/faillock.conf"
        blockLoading: true
        printErrors: false
    }

    Process {
        id: probe
        command: ["faillock", "--user", root._user]
        stdout: StdioCollector {
            onStreamFinished: {
                root._s = Lock.state(text, conf.text(), Date.now())
                if (root._s.locked && root._s.until > 0)
                    liftTimer.interval = Math.max(1000, root._s.until - Date.now() + 1000)
                liftTimer.running = root._s.locked && root._s.until > 0
            }
        }
    }
    Timer { id: liftTimer; onTriggered: root.check() }
}
