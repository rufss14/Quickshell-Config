pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "../config"

// ── Lock ──────────────────────────────────────────────────────────────────────
// Whether the session is locked, and what may lock it.
//
// Same split as the Idle service: the POLICY lives here, and the Wayland object that
// enforces it lives in modules/lock/LockScreen.qml, which is where the surface and
// its PAM conversation are. This file has no UI and no authentication in it.
//
// ── Read this before enabling auto-lock ───────────────────────────────────────
// ext-session-lock-v1 is designed so that a locker crashing CANNOT expose the
// session: if the client goes away without unlocking, the compositor stays locked
// with a blank (Hyprland: red) screen and no way in. That is the protocol working
// as intended, and it is also the failure mode to respect — a broken lockscreen is
// not "the lockscreen doesn't appear", it is "you are locked out until you switch
// to a TTY".
//
// The recovery, for the record, because the moment you need it is the worst moment
// to be looking it up:
//
//     Ctrl+Alt+F2   → a TTY, log in normally
//     loginctl unlock-session   (or: pkill -f 'quickshell.*quicktest' and restart)
//
// ── Which is why auto-lock ships OFF ──────────────────────────────────────────
// `Config.lockIdleEnabled` defaults to false. Locking is reachable by IPC from the
// first reload, so the flow can be proven deliberately — lock, unlock, confirm the
// password is accepted — before anything is allowed to lock the machine on a timer
// while you are away from it. Turning it on is a decision, made once, after the
// evidence exists.
//
// ── Auto-lock respects inhibitors, and that is the point of stage 3 ───────────
// `respectInhibitors: true` means the idle pill and gamemode both suppress the
// auto-lock timer, not just screen blanking. Holding the machine awake to watch
// something and then having it lock in your face would make the inhibitor a lie.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // Not writable from outside: `unlock()` must only ever be reachable from a
    // successful PAM conversation, and a plain writable property is an invitation to
    // set it from somewhere that has not authenticated anything.
    readonly property bool locked: root._locked
    property bool _locked: false

    // Mirrored back from WlSessionLock by LockScreen. False while locked means the
    // compositor did not honour the lock — the surface says so out loud rather than
    // presenting a password box that is protecting nothing.
    property bool secure: false

    // Set by LockScreen when PAM cannot even be started (a missing or unusable
    // config). Surfaced in `status()` so the IPC can answer "why did nothing happen".
    property string lastError: ""

    function lock() {
        if (root._locked) return
        root.lastError = ""
        // The picture is re-found at every lock: it can have been deleted or replaced since.
        faceProbe.running = false
        faceProbe.running = true
        root._locked = true
    }

    // Called by the lock surface, and only after PamResult.Success. There is
    // deliberately no IPC route to this: an unlock command reachable from the session
    // bus would be a lock anyone with a shell could open.
    function unlock() {
        if (!root._locked) return
        root._locked = false
        root.secure  = false
    }

    // ── Is the configuration actually usable? ────────────────────────────────
    // Probed here rather than in the settings page, because they are questions
    // about the SYSTEM (does /etc/pam.d/<name> exist, is the avatar file still
    // there), and the page is only one of the things that wants the answer.
    //
    // /etc/pam.d is world-readable, so no privileges and no polkit — a plain `test`,
    // re-run whenever the name changes. A wrong PAM name means "a password box that
    // can never accept a password", which is why this is checked at all.
    readonly property string pamState:    root._pamState      // "" (checking) | "ok" | "missing"
    readonly property string avatarState: root._avatarState   // "" (unset)    | "ok" | "missing"
    property string _pamState: ""
    property string _avatarState: ""

    function recheck() {
        root._pamState = ""
        pamProbe.running = false
        pamProbe.running = true
        root._avatarState = ""
        avatarProbe.running = false
        avatarProbe.running = true
    }

    Process {
        id: pamProbe
        running: true
        // `test` is a real binary, so it can be exec'd directly; `command` would not be.
        command: ["test", "-r", "/etc/pam.d/" + Config.lockPamConfig]
        onExited: function (code) { root._pamState = code === 0 ? "ok" : "missing" }
    }

    // A picture chosen last month can have been deleted since — so this is about the
    // file as it is NOW. The path goes in as $1, never spliced into the script.
    Process {
        id: avatarProbe
        running: true
        command: ["sh", "-c", '[ -n "$1" ] && [ -r "$1" ]', "sh", Config.lockAvatar]
        onExited: function (code) {
            root._avatarState = Config.lockAvatar === "" ? "" : (code === 0 ? "ok" : "missing")
        }
    }

    // ── The face on the lock screen ───────────────────────────────────────────
    // The first readable of: the chosen picture, ~/.face, ~/.face.icon, AccountsService's
    // icon for this user — "" for none, and the surface draws a monogram. Probed rather
    // than trusted (a broken-image box on a locked screen is worse than the monogram), and
    // once here rather than per screen. "$@": the paths are arguments, never spliced into
    // the script, so a space or a quote in one cannot become shell syntax.
    readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""
    readonly property string facePath: root._facePath
    property string _facePath: ""

    Process {
        id: faceProbe
        running: true
        command: ["sh", "-c",
                  'for f in "$@"; do [ -n "$f" ] && [ -r "$f" ] && { printf %s "$f"; exit 0; }; done; exit 0',
                  "sh",
                  Config.lockAvatar,
                  (Quickshell.env("HOME") || "") + "/.face",
                  (Quickshell.env("HOME") || "") + "/.face.icon",
                  "/var/lib/AccountsService/icons/" + root.userName]
        stdout: StdioCollector { onStreamFinished: root._facePath = text.trim() }
    }

    Connections {
        target: Config
        function onLockPamConfigChanged() { root.recheck() }
        function onLockAvatarChanged() {
            root.recheck()
            faceProbe.running = false
            faceProbe.running = true
        }
    }

    // ── Auto-lock ─────────────────────────────────────────────────────────────
    // Disabled while already locked: the monitor has nothing to contribute once the
    // session is locked, and leaving it running would re-fire `isIdle` against a lock
    // that is already up.
    IdleMonitor {
        enabled: Config.lockIdleEnabled && !root._locked
        timeout: Math.max(60, Config.lockIdleMinutes * 60)
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) root.lock()
    }

    // ── Lock before sleep ─────────────────────────────────────────────────────
    // logind announces a suspend/hibernate with PrepareForSleep(true) and waits for
    // DELAY inhibitors before it goes. So the shell holds one (`systemd-inhibit
    // --mode=delay`), and on the signal locks, then lets go once the compositor says
    // the lock is up (`secure`) — the machine sleeps with the lock already drawn, and
    // wakes to it instead of to a flash of the desktop.
    //
    // Never in the way of sleep: logind stops waiting after InhibitDelayMaxSec (5 s
    // by default) whatever we do, and sleepRelease lets go after 2 s even if the lock
    // never reported secure. On PrepareForSleep(false) (resume) the hold is taken
    // again for next time.
    //
    // The hold's child is `cat` on a stdin pipe the shell owns, so a killed shell
    // closes the pipe, cat exits, and systemd-inhibit releases with it — nothing
    // orphaned holds sleep back (the Gamemode hold uses the same trick). pdeathsig
    // covers systemd-inhibit itself.
    //
    // Optional tools: systemd-inhibit (systemd) and gdbus (glib2). Without either,
    // `sleepBlocker` says why and the setting is disabled — never a toggle that does
    // nothing.
    readonly property string sleepBlocker: root._sleepToolsChecked && !root._sleepToolsOk
        ? "Needs systemd-inhibit and gdbus" : ""
    readonly property bool sleepArmed: Config.lockOnSleep && root._sleepToolsOk
    property bool _sleepToolsOk: false
    property bool _sleepToolsChecked: false
    property bool _sleepHold: true     // false between PrepareForSleep(true) and resume

    Process {
        running: true
        command: ["sh", "-c", "command -v systemd-inhibit >/dev/null && command -v gdbus >/dev/null"]
        onExited: function (code) {
            root._sleepToolsOk = code === 0
            root._sleepToolsChecked = true
        }
    }

    function _letSleep() {
        sleepRelease.stop()
        root._sleepHold = false
    }

    // gdbus prints a signal as `<path>: <interface>.<member> <g_variant_print(args)>`
    // (gio/gdbus-tool.c, monitor_signal_cb), so logind's one boolean arrives as
    //   /org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (true,)
    function _onLogindLine(line) {
        const m = String(line).match(/\.Manager\.PrepareForSleep \((true|false),\)/)
        if (!m) return
        if (m[1] === "true") {
            root.lock()
            if (root.secure) root._letSleep()
            else sleepRelease.restart()
        } else {
            sleepRelease.stop()
            root._sleepHold = true
        }
    }

    onSecureChanged: if (root.secure && root._locked && sleepRelease.running) root._letSleep()

    Timer {
        id: sleepRelease
        interval: 2000
        onTriggered: root._letSleep()
    }

    Process {
        id: sleepInhibit
        running: root.sleepArmed && root._sleepHold
        stdinEnabled: true
        command: ["setpriv", "--pdeathsig", "TERM",
                  "systemd-inhibit", "--what=sleep", "--mode=delay", "--who=Quicktest",
                  "--why=Lock the screen before sleep", "cat"]
        // Re-armed for the next start: docs/gotchas-system.md (Process.stdinEnabled).
        onRunningChanged: if (!running) stdinEnabled = true
    }

    // Same restart dance as Gamemode's gameWatch: a Process that exits on its own stays
    // exited while its `running` binding still reads true, so dip a flag it reads.
    // Backing off: with no system bus (a container, a non-systemd machine) the monitor
    // exits at once, and a fixed 5 s retry logged a warning every 5 s for the whole
    // session. Each failure in a row doubles the wait, to 5 min; a run that stayed up a
    // minute resets it. Only the first three failures are logged.
    property bool _logindCycling: false
    property int _logindFails: 0
    property double _logindStartedAt: 0
    Timer {
        id: logindRestart
        interval: 5000
        onTriggered: { root._logindCycling = true; root._logindCycling = false }
    }

    Process {
        running: root.sleepArmed && !root._logindCycling
        command: ["setpriv", "--pdeathsig", "TERM", "gdbus", "monitor", "--system",
                  "--dest", "org.freedesktop.login1", "--object-path", "/org/freedesktop/login1"]
        stdout: SplitParser { onRead: function (line) { root._onLogindLine(line) } }
        // A monitor that (re)starts can have missed the resume signal; hold again.
        onStarted: {
            root._sleepHold = true
            root._logindStartedAt = Date.now()
        }
        onExited: function (code) {
            if (!root.sleepArmed) return
            if (Date.now() - root._logindStartedAt > 60000) root._logindFails = 0
            root._logindFails++
            logindRestart.interval = Math.min(300000, 5000 * Math.pow(2, root._logindFails - 1))
            if (root._logindFails <= 3)
                console.warn("Lock: logind monitor exited (" + code + "), retrying in "
                             + Math.round(logindRestart.interval / 1000) + "s")
            logindRestart.restart()
        }
    }

    // ══ IPC ═══════════════════════════════════════════════════════════════════
    // `qs ipc -c ~/.config/quicktest call lock lock`
    //
    // The lock verb exists so a keybind can reach it; there is no unlock verb, on
    // purpose — see unlock() above.
    property var _ipc: IpcHandler {
        target: "lock"

        function lock(): void { root.lock() }

        function status(): string {
            const auto = (Config.lockIdleEnabled
                ? "auto-lock after " + Config.lockIdleMinutes + " min (inhibitors respected)"
                : "auto-lock off")
                + "  ·  " + (root.sleepArmed ? "locks before sleep"
                             : root.sleepBlocker !== "" ? "no lock before sleep: " + root.sleepBlocker
                             : "no lock before sleep")
            const err = root.lastError !== "" ? "  ·  last error: " + root.lastError : ""
            return (root._locked ? (root.secure ? "locked (secure)" : "LOCKED BUT NOT SECURE")
                                 : "unlocked")
                   + "  ·  " + auto + err
        }

        // Auto-lock from a script or keybind; Settings › Desktop › Lock screen is the
        // other way in. Minutes are clamped: a sub-minute auto-lock is
        // indistinguishable from a broken machine.
        function autolock(minutes: int): void {
            Config.lockIdleMinutes = Math.max(1, Math.min(120, minutes))
            Config.lockIdleEnabled = true
        }

        function autolockOff(): void { Config.lockIdleEnabled = false }
    }
}
