import QtQuick
import Quickshell.Io
import "sudolock.js" as Lock

// ── SudoProcess ───────────────────────────────────────────────────────────────
// A Process that hands a typed password to `sudo -S` on stdin, once, and guards
// against the sudo lockout. Setup and Storage run their root jobs through it.
//
//   proc.launch(argv, password, env)   false (and `passwordNote` says why) when the
//                                      password must not be sent; true once started
//   proc.judge(code, lines)            call from the owner's onExited with what the job
//                                      printed ({text} objects or strings); true when
//                                      sudo rejected the password
//
// Why the guard: a wrong password costs MORE than one pam_faillock strike (`sudo -S`
// re-prompts and reads EOF off the one-line stdin; that counts too), and three strikes
// lock sudo for ten minutes, during which the RIGHT password fails as well. So a
// password sudo just rejected isn't sent again until it is retyped (compared by hash;
// the password itself is never kept), and nothing is sent while SudoLock says sudo is
// locked.
//
// Why stdin is re-armed per launch: onStarted turns stdin off (anything downstream
// reading it would otherwise wait forever), and Quickshell closes stdin BEFORE starting
// a process whose stdinEnabled is false (process.cpp startProcessIfReady), so the second
// job of a session would read EOF ("no password was provided"): a strike of its own.
//
// The owner's own onStarted / onExited run as well as these (QML connects both).
// ─────────────────────────────────────────────────────────────────────────────
Process {
    id: proc

    running: false
    stdinEnabled: true

    // Why the last launch() refused, for the UI; "" when it didn't.
    property string passwordNote: ""
    signal passwordRejected()

    property string _pending: ""
    property string _lastHash: ""
    property string _rejectedHash: ""

    function launch(argv, password, env) {
        if (proc.running || !argv || argv.length === 0) return false
        const pass = password ?? ""
        if (pass.length) {
            if (SudoLock.locked) {
                proc.passwordNote = SudoLock.message
                SudoLock.check()
                return false
            }
            const h = Qt.md5(pass)
            if (h === proc._rejectedHash) {
                proc.passwordNote = "That's the password sudo just rejected — retype it. "
                    + "(Each wrong try counts toward a ten-minute sudo lockout.)"
                return false
            }
            proc._lastHash = h
        } else {
            proc._lastHash = ""
        }
        proc.passwordNote = ""
        proc._pending = pass
        proc.command = argv
        proc.environment = env ?? ({})
        proc.stdinEnabled = true
        proc.running = true
        return true
    }

    function judge(code, lines) {
        proc._pending = ""
        if (code === 0) { proc._rejectedHash = ""; return false }
        if (proc._lastHash === "" || !Lock.rejected(lines)) return false
        proc._rejectedHash = proc._lastHash
        proc.passwordNote = "Wrong password — sudo rejected it. Nothing was changed."
        SudoLock.check()
        proc.passwordRejected()
        return true
    }

    // The password sits in the pipe until `sudo -S` reads it.
    onStarted: {
        if (proc._pending !== "") {
            proc.write(proc._pending + "\n")
            proc._pending = ""
        }
        proc.stdinEnabled = false
    }
}
