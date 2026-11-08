pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// ── Session ───────────────────────────────────────────────────────────────────
// Ending or pausing the session: lock, suspend, log out, restart, shut down. The
// one place those are done, so the overview's power panel and the sidebar's power
// module can't come to disagree about what "log out" means.
//
// Lock is the Lock service's own (`loginctl lock-session` only broadcasts a signal
// nothing in this shell listens for — a button wired to it starts a process that
// exits 0 and does nothing). Log out is Hyprland's dispatch (Hypr.exitSession says
// why it isn't `hyprctl dispatch exit`). The rest are systemctl, which polkit lets
// the seat's active user run without a password.
//
// None of these ask first: that's the caller's job (PowerPanel's arming, the
// power menu's), because only the caller knows what a misclick looks like.
//
// ── What this machine can do ──────────────────────────────────────────────────
// Hibernating needs a swap big enough and a resume device; restarting into the
// firmware needs UEFI that offers it. logind knows both (CanHibernate,
// CanRebootToFirmwareSetup: "yes", "challenge" = polkit will ask, "no"/"na").
// `probe()` asks once per call — the power menu calls it as it opens, so a closed
// menu costs nothing — and reads the boot moment from /proc/uptime in the same
// shell (and the host name, for the menu's "user@host"). Without busctl (no systemd)
// both stay false and the menu leaves them out.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    function lock()      { Lock.lock() }
    function logout()    { Hypr.exitSession() }
    function suspend()   { root._run(["systemctl", "suspend"]) }
    function hibernate() { root._run(["systemctl", "hibernate"]) }
    function reboot()    { root._run(["systemctl", "reboot"]) }
    function rebootToFirmware() { root._run(["systemctl", "reboot", "--firmware-setup"]) }
    function poweroff()  { root._run(["systemctl", "poweroff"]) }

    // The action a power menu key names (services/powermenu.js has the keys). The welded
    // column fires through here, so there is one table from key to command and a key added
    // to the menu cannot be left without one.
    // An unknown key does nothing: this takes whatever a view hands it.
    function run(key) {
        if      (key === "lock")      root.lock()
        else if (key === "suspend")   root.suspend()
        else if (key === "hibernate") root.hibernate()
        else if (key === "logout")    root.logout()
        else if (key === "reboot")    root.reboot()
        else if (key === "firmware")  root.rebootToFirmware()
        else if (key === "shutdown")  root.poweroff()
    }

    property bool canHibernate: false
    property bool canFirmware:  false
    // The same two, as the object powermenu.js asks about.
    readonly property var caps: ({ hibernate: root.canHibernate, firmware: root.canFirmware })
    // When the machine booted (epoch ms; 0 = not read yet). An epoch, not a duration:
    // the caller derives uptime against a clock it already has.
    property double bootEpoch: 0
    // Who and where, for the power menu's "user@host" — from the environment and the
    // kernel, never hardcoded (this config is published).
    readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME") || ""
    property string hostName: ""

    // ── What ending the session would cut off ─────────────────────────────────
    // Asked of the services that already know, not guessed: the shell's own update run,
    // a recording, a Claude Code session mid-task — plus pacman's lock file for an
    // upgrade started in a terminal (read by `probe()`, as the power menu opens, so a
    // closed menu costs nothing). The menu shows it on the tiles that END the session
    // (log out, restart, firmware, shut down); a suspend keeps everything running, so
    // it has no business crying wolf. Nothing here blocks anything — it informs the
    // click that was already going to be a confirmation.
    property bool pacmanLocked: false
    readonly property var interrupts: {
        const out = []
        if (Updates.runBusy || root.pacmanLocked) out.push(Translation.tr("A package update is running"))
        if (Clips.recording) out.push(Translation.tr("A recording is in progress"))
        const n = ClaudeSessions.busyCount
        if (n > 0) out.push(n === 1 ? Translation.tr("A Claude session is working") : Translation.tr("%1 Claude sessions are working").arg(n))
        return out
    }
    // One line for a tile: the first reason, and how many more.
    readonly property string interruptText: root.interrupts.length === 0 ? ""
        : (root.interrupts.length > 1
           ? Translation.tr("%1 (+%2 more)").arg(root.interrupts[0]).arg(root.interrupts.length - 1)
           : root.interrupts[0])

    function probe() { if (!root._probe.running) root._probe.running = true }

    // "3 days, 4h" / "4h 12m" / "6m" — Greet.uptimeText's wording (the greeter reads
    // its own boot moment; it runs without this session).
    function uptimeText(now) {
        if (root.bootEpoch <= 0) return ""
        const s = Math.max(0, Math.floor((now - root.bootEpoch) / 1000))
        const d = Math.floor(s / 86400)
        const h = Math.floor((s % 86400) / 3600)
        const m = Math.floor((s % 3600) / 60)
        if (d > 0) return d + (d === 1 ? " day, " : " days, ") + h + "h"
        if (h > 0) return h + "h " + m + "m"
        return m + "m"
    }

    property Process _probe: Process {
        command: ["sh", "-c",
            "read u < /proc/uptime && printf 'UPTIME=%s\\n' \"${u%% *}\"; "
          + "read h < /proc/sys/kernel/hostname && printf 'HOST=%s\\n' \"$h\"; "
          + "if [ -e /var/lib/pacman/db.lck ]; then echo PACMAN=1; else echo PACMAN=0; fi; "
          + "command -v busctl >/dev/null || exit 0; "
          + "for m in CanHibernate CanRebootToFirmwareSetup; do "
          + "  printf '%s=%s\\n' \"$m\" \"$(busctl --system call org.freedesktop.login1 "
          + "/org/freedesktop/login1 org.freedesktop.login1.Manager \"$m\" 2>/dev/null)\"; "
          + "done"]
        stdout: StdioCollector {
            onStreamFinished: {
                // `s "yes"` → yes; "challenge" means polkit asks, which still works.
                const ok = v => /"(yes|challenge)"/.test(v)
                for (const line of text.split("\n")) {
                    const eq = line.indexOf("=")
                    if (eq < 0) continue
                    const key = line.substring(0, eq), val = line.substring(eq + 1)
                    if (key === "UPTIME") {
                        const secs = parseFloat(val)
                        if (isFinite(secs)) root.bootEpoch = Date.now() - secs * 1000
                    }
                    else if (key === "HOST")                     root.hostName = val.trim()
                    else if (key === "PACMAN")                   root.pacmanLocked = val.trim() === "1"
                    else if (key === "CanHibernate")             root.canHibernate = ok(val)
                    else if (key === "CanRebootToFirmwareSetup") root.canFirmware  = ok(val)
                }
            }
        }
    }

    function _run(cmd) {
        root._proc.command = cmd
        root._proc.running = true
    }
    property Process _proc: Process {}
}
