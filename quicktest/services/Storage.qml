pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../state"

// ── Storage ───────────────────────────────────────────────────────────────────
// What's using the disks, and what can safely be given back.
//
// ── Refcounted, like SysInfo ──────────────────────────────────────────────────
// Nothing here runs unless the Storage page is open. There is no bar widget for this
// and no background polling: disk usage does not change on a timescale that justifies
// a timer, and `du` is expensive enough that running it unobserved would be rude.
//
// ── Reporting and doing are separate ──────────────────────────────────────────
// `scripts/storage.sh` is strictly read-only — every figure it prints comes from a dry
// run or a listing. The removals live HERE, as explicit commands, so that everything
// capable of deleting something is visible in one file rather than split between QML
// and a shell script that also does the measuring.
//
// ── What this deliberately will NOT delete ────────────────────────────────────
// Trash and the per-app caches under ~/.cache are the two biggest things on this
// machine (38 GB and 45 GB), and neither gets a button. They're reported, with their
// paths, and that's all. The reclaimers here are limited to things that regenerate on
// their own — package caches, logs, crash dumps, unused runtimes — where the worst case
// of pressing the button is that something is slower once. Emptying Trash is deleting
// the user's own files, and a shell should not offer that behind a one-click button
// sitting next to six harmless ones.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    property int _refs: 0
    function acquire() {
        root._refs++
        if (root._refs === 1) root.refresh()
    }
    function release() { root._refs = Math.max(0, root._refs - 1) }
    readonly property bool active: root._refs > 0

    // ── Reported state ────────────────────────────────────────────────────────
    // filesystems: [{ device, fstype, size, used, avail, mount, rotational, fraction }]
    readonly property var filesystems: root._fs
    // reclaimers:  [{ id, label, bytes, known, detail }]
    readonly property var reclaimers:  root._reclaim
    // directories: [{ label, bytes, path, owner }]
    readonly property var directories: root._dirs

    readonly property bool probing: probe.running

    property var _fs:      []
    property var _reclaim: []
    property var _dirs:    []

    // Total of the reclaimers we can actually put a number on. Flatpak is excluded by
    // `known`, so the headline figure never silently includes a guess — the UI says
    // "plus unused Flatpak runtimes" separately rather than folding an unknown into a sum.
    readonly property real reclaimableBytes: {
        let t = 0
        for (let i = 0; i < root._reclaim.length; i++)
            if (root._reclaim[i].known) t += root._reclaim[i].bytes
        return t
    }
    readonly property bool hasUnknownReclaim: root._reclaim.some(r => !r.known)

    // ── Formatting ────────────────────────────────────────────────────────────
    // NetStats has a `bytes()` too, but it stops at GB and lives on the network service —
    // pulling that singleton in (and its /proc timers) just to format a number would be
    // the wrong dependency, and a 1.6 TB disk needs the terabyte case. Worth hoisting both
    // into a shared Format singleton at some point; not worth restyling a working page for
    // it right now.
    function bytes(n) {
        const b = n || 0
        if (b < 1024)                return Math.round(b) + " B"
        if (b < 1048576)             return (b / 1024).toFixed(0) + " KB"
        if (b < 1073741824)          return (b / 1048576).toFixed(0) + " MB"
        if (b < 1099511627776)       return (b / 1073741824).toFixed(1) + " GB"
        return (b / 1099511627776).toFixed(2) + " TB"
    }

    // ── Probe ─────────────────────────────────────────────────────────────────
    // One process for the whole page (measured: 1.3s, all of it on the SSD). Parsed as
    // KEY=value, same contract as specs.sh.
    function refresh() {
        if (probe.running) return
        probe._seen = ({})
        probe.running = true
    }

    Process {
        id: probe
        running: false

        // ── Progressive, not all-at-once ──────────────────────────────────────
        // The script emits the cheap things first (df, reclaim dry runs — 1.3s) and the
        // expensive directory sizes last (/usr and /opt add ~3s). Assigning everything in
        // onExited meant the page sat empty for the whole 4.5s waiting on numbers it
        // wasn't going to show above the fold anyway.
        //
        // `_seen` tracks which kinds have arrived THIS run, so the first row of a kind
        // clears the previous run's data and the rest append. The alternative — clearing
        // everything in refresh() — makes the page flash empty on every reopen.
        property var _seen: ({})

        function _push(key, row) {
            const first = !probe._seen[key]
            if (first) probe._seen[key] = true
            if (key === "FS")
                root._fs = first ? [row] : root._fs.concat([row])
            else if (key === "RECLAIM")
                root._reclaim = first ? [row] : root._reclaim.concat([row])
            else
                root._dirs = first ? [row] : root._dirs.concat([row])
        }
        // `shellPath` resolves against the shell's own directory. AboutPage hardcodes
        // "$HOME/.config/quicktest/scripts/..." instead, which breaks the moment the config
        // lives anywhere else — worth migrating that one to match this.
        //
        // Invoked through bash rather than directly so a missing executable bit (a copy, a
        // fresh clone, an unpacked tarball) can't turn the page blank.
        command: ["bash", Quickshell.shellPath("scripts/storage.sh")]

        stdout: SplitParser {
            onRead: function(line) {
                const eq = line.indexOf("=")
                if (eq < 0) return
                const key = line.substring(0, eq)
                const parts = line.substring(eq + 1).split("|")

                if (key === "FS" && parts.length >= 7) {
                    const size = parseFloat(parts[2]) || 0
                    const used = parseFloat(parts[3]) || 0
                    probe._push("FS", {
                        device: parts[0], fstype: parts[1],
                        size: size, used: used, avail: parseFloat(parts[4]) || 0,
                        mount: parts[5], rotational: parts[6] === "1",
                        fraction: size > 0 ? used / size : 0
                    })
                } else if (key === "RECLAIM" && parts.length >= 5) {
                    probe._push("RECLAIM", {
                        id: parts[0], label: parts[1],
                        bytes: parseFloat(parts[2]) || 0,
                        known: parts[3] === "1",
                        detail: parts.slice(4).join("|")
                    })
                } else if (key === "DIR" && parts.length >= 4) {
                    probe._push("DIR", {
                        label: parts[0], bytes: parseFloat(parts[1]) || 0,
                        path: parts[2], owner: parts[3]
                    })
                }
            }
        }

        // A run producing NO reclaimers is a real answer, not a failure — it's what a
        // freshly-cleaned machine looks like. Without this the list would keep showing the
        // previous run's rows forever, since `_push` only clears on the first row of a kind
        // and there would never be one.
        onExited: function(code) {
            if (!probe._seen["RECLAIM"]) root._reclaim = []
            if (!probe._seen["DIR"])     root._dirs    = []
        }
    }

    // ── What's actually on the root filesystem ────────────────────────────────
    // The composition chart's model. Everything measured that lives on /, plus an
    // "Other" remainder and the free space, as proportions of the whole disk.
    //
    // "Other" is computed as a REMAINDER rather than measured — it's whatever `used`
    // is that the named directories don't account for. That makes it honest by
    // construction (the segments always sum to the disk) and it's why /usr is measured
    // at all: without it, Other was ~16 GB and explained nothing.
    readonly property var rootComposition: {
        const fs = root._fs.filter(f => f.mount === "/")[0]
        if (!fs || fs.size <= 0) return []

        // Only directories that are actually ON / — /home is its own filesystem, and
        // folding it in here would be a straightforward lie.
        const named = root._dirs.filter(d => d.path.indexOf("/home") !== 0)
        let accounted = 0
        const segs = []
        for (let i = 0; i < named.length; i++) {
            accounted += named[i].bytes
            segs.push({ label: named[i].label, bytes: named[i].bytes, kind: named[i].owner })
        }

        const other = Math.max(0, fs.used - accounted)
        segs.push({ label: "Other", bytes: other, kind: "other" })
        segs.push({ label: "Free",  bytes: fs.avail, kind: "free" })

        // ── Reserved blocks, or the bar would not add up ──────────────────────
        // On ext4 `used + avail` is LESS than `size` — measured here as a 5.5 GB gap on a
        // 106.8 GB disk, which is mkfs's default 5% reserved for root (it keeps the system
        // bootable and the filesystem defragmentable when a user fills the disk).
        //
        // Caught by asserting the segments sum to the disk size, which they didn't. Without
        // this the chart would quietly misrepresent the disk by 5%, and "why doesn't this
        // add up" is precisely the question the chart exists to answer. Shown rather than
        // hidden, because it IS space, just not space anyone can use.
        const reserved = Math.max(0, fs.size - fs.used - fs.avail)
        if (reserved > 0)
            segs.push({ label: "Reserved", bytes: reserved, kind: "reserved" })

        return segs
    }

    // ── Home scan ─────────────────────────────────────────────────────────────
    // `du` on the home directory, on demand only. This is the one genuinely slow thing on
    // the page: /home is a 1.6 TB spinning disk and the scan has to stat everything.
    //
    // Measured BOTH ways, because the difference is enormous and the UI copy has to be
    // true in both: over two minutes on a cold cache, 3 seconds once the kernel has the
    // directory entries. The cold case is why this is a button rather than part of
    // `refresh()` — opening a settings tab should never spin up a drive for two minutes.
    //
    // `-x` keeps it on one filesystem, so a mounted drive under home isn't silently folded
    // into the total. Depth 1: the useful answer is "which of my top-level folders is
    // huge", and going deeper multiplies the cost for detail nobody reads at this level.
    readonly property var  scanned:     root._scanned      // [{ label, bytes, path }]
    readonly property bool scanning:    scanProc.running
    readonly property real scanElapsed: root._scanElapsed  // seconds, live while running
    readonly property bool hasScanned:  root._hasScanned

    property var  _scanned: []
    property bool _hasScanned: false
    property real _scanElapsed: 0

    function scanHome() {
        if (scanProc.running) return
        scanProc._rows = []
        root._scanElapsed = 0
        scanProc.running = true
    }
    function cancelScan() { if (scanProc.running) scanProc.running = false }

    Timer {
        running: scanProc.running
        interval: 1000; repeat: true
        onTriggered: root._scanElapsed += 1
    }

    Process {
        id: scanProc
        running: false
        // Sorted numerically, biggest first, and capped — the tail of a home directory is
        // hundreds of dotfiles worth nothing individually.
        command: ["bash", "-c",
            "du -x --block-size=1 --max-depth=1 \"$HOME\" 2>/dev/null | sort -rn | head -25"]

        property var _rows: []

        stdout: SplitParser {
            onRead: function(line) {
                const m = line.match(/^(\d+)\s+(.+)$/)
                if (!m) return
                const path = m[2]
                // du's first row is $HOME itself — that's the total, not a child, and
                // listing it alongside its own children would double the apparent size.
                if (path === scanProc._home) return
                scanProc._rows = scanProc._rows.concat([{
                    bytes: parseFloat(m[1]) || 0,
                    path: path,
                    label: path.split("/").pop()
                }])
            }
        }

        readonly property string _home: Quickshell.env("HOME") ?? ""

        onExited: function(code) {
            if (scanProc._rows.length > 0) {
                root._scanned = scanProc._rows
                root._hasScanned = true
            }
            scanProc._rows = []
        }
    }

    // ── Reclaiming ────────────────────────────────────────────────────────────
    // Same runner shape as Updates: one Process, the sudo password written to stdin after
    // `started` rather than interpolated into a command line where /proc would expose it.
    // See Updates.installSelected() for the full reasoning — this is the same technique,
    // not a second invention of it.
    //
    // Every command below is deliberately non-interactive AND scoped to one thing. There
    // is no "clean everything" that chains them, because the failure mode of a chain is
    // that you can't tell which step ate your disk.
    function _commandFor(id) {
        switch (id) {
        // Keep the 2 newest versions of each installed package. -k2 rather than -k0 so a
        // downgrade is still possible afterwards.
        case "paccache":             return "sudo -S -p '' paccache -r -k2"
        // Packages no longer installed at all — nothing left to downgrade to.
        case "paccache-uninstalled": return "sudo -S -p '' paccache -ruk0"
        // -Rns: also drop their now-unneeded dependencies and their config. Guarded on a
        // non-empty list because `pacman -Rns` with no arguments is an error, and an error
        // here would read as "cleaning failed" rather than "nothing to clean".
        case "orphans":              return "mapfile -t O < <(pacman -Qtdq)\n"
                                          + "if [ ${#O[@]} -eq 0 ]; then echo 'No orphans.'; exit 0; fi\n"
                                          + "sudo -S -p '' pacman -Rns --noconfirm \"${O[@]}\""
        // Trims to 200 MB rather than emptying: the journal is how the last crash gets
        // diagnosed, and trading that away for one more gigabyte is a bad deal.
        case "journal":              return "sudo -S -p '' journalctl --vacuum-size=200M"
        // -type f so the directory itself survives; systemd expects it to exist.
        case "coredumps":            return "sudo -S -p '' find /var/lib/systemd/coredump -type f -delete\n"
                                          + "echo 'Crash dumps removed.'"
        // No sudo: these are system installs, so flatpak authenticates through polkit and
        // hyprpolkitagent raises its own dialog. Passing a password here would do nothing.
        case "flatpak":              return "flatpak uninstall --unused -y"
        }
        return ""
    }

    // Only the pacman/systemd ones go through sudo. Flatpak has its own auth path, so
    // demanding a password for it would be theatre.
    function needsPassword(id) { return id !== "flatpak" }

    // ── Where a reclaimer's space actually lives ──────────────────────────────
    // The page used to list "largest folders" beside the reclaimers, which was the SAME
    // DATA TWICE: "Package cache 24.6 GB" is the thing the paccache row cleans, and
    // "System logs 1.2 GB" is what the journal row trims. Showing both invited the reader
    // to add them together.
    //
    // So the directory total becomes CONTEXT on the row instead — "17.1 GB of 24.6 GB" says
    // how much of that cache is actually stale, which neither figure said on its own.
    // Orphans and coredumps have no meaningful containing directory, and get nothing rather
    // than a contrived one.
    readonly property var _dirForId: ({
        "paccache":             "/var/cache/pacman/pkg",
        "paccache-uninstalled": "/var/cache/pacman/pkg",
        "flatpak":              "/var/lib/flatpak",
        "journal":              "/var/log"
    })

    function contextFor(id) {
        const path = root._dirForId[id]
        if (!path) return null
        return root._dirs.filter(d => d.path === path)[0] ?? null
    }

    // Largest of the known reclaimers, for the proportion bars — a row's share of the
    // total is what shows at a glance that one item is most of the win.
    readonly property real largestReclaim: {
        let m = 0
        for (let i = 0; i < root._reclaim.length; i++)
            if (root._reclaim[i].known && root._reclaim[i].bytes > m) m = root._reclaim[i].bytes
        return m
    }

    function reclaim(id, password) {
        if (runProcess.running) return
        const cmd = root._commandFor(id)
        if (cmd === "") return

        const entry = root._reclaim.filter(r => r.id === id)[0]
        root.clearRun()
        root._runLabel   = entry ? entry.label : id
        root._runId      = id
        root._pendingPass = root.needsPassword(id) ? (password ?? "") : ""
        // `set -e` so a rejected password stops here instead of being buried under
        // whatever the real command prints next.
        runProcess.command = ["bash", "-c", "set -e\n" + cmd]
        runProcess.running = true
    }

    readonly property bool  runBusy:  runProcess.running
    readonly property var   runLog:   root._runLog
    readonly property int   runExit:  root._runExit
    readonly property bool  runDone:  root._runDone
    readonly property string runLabel: root._runLabel
    readonly property string runId:    root._runId

    property var    _runLog:  []
    property int    _runExit: 0
    property bool   _runDone: false
    property string _runLabel: ""
    property string _runId:    ""
    property string _pendingPass: ""

    // Free space on / at the moment the run started, so the finish message can report what
    // was ACTUALLY reclaimed rather than repeating the estimate. An estimate that turns out
    // wrong is exactly the thing worth noticing, and only a before/after can show it.
    property real _freeBefore: 0

    function _log(text, isError) {
        if (!text || text.trim() === "") return
        root._runLog = root._runLog.concat([{ text: text, error: isError === true }])
    }

    function clearRun() {
        root._runLog  = []
        root._runDone = false
        root._runExit = 0
    }

    function _rootFree() {
        const r = root._fs.filter(f => f.mount === "/")[0]
        return r ? r.avail : 0
    }

    Process {
        id: runProcess
        running: false
        stdinEnabled: true

        onStarted: {
            root._freeBefore = root._rootFree()
            if (root._pendingPass !== "") {
                runProcess.write(root._pendingPass + "\n")
                root._pendingPass = ""
            }
            // Closed once the password is in, or anything downstream reading stdin waits
            // forever for input that isn't coming.
            runProcess.stdinEnabled = false
        }

        stdout: SplitParser { onRead: function(line) { root._log(line, false) } }
        stderr: SplitParser { onRead: function(line) { root._log(line, true) } }

        onExited: function(code) {
            root._runExit = code
            root._runDone = true
            root._pendingPass = ""
            root._log(code === 0 ? "✓ Finished." : "✗ Exited with code " + code, code !== 0)
            // Re-probe so the page reflects reality; the freed figure is computed once the
            // new df lands, in onFilesystemsChanged below.
            root.refresh()

            root._notify(
                code === 0 ? "Storage cleaned" : "Cleanup failed",
                code === 0 ? (root._runLabel || "Cleanup") + " finished."
                           : (root._runLabel || "Cleanup") + " stopped with code " + code
                             + ". Reopen Settings → Storage for the log.",
                code === 0 ? "normal" : "critical",
                // An absolute SVG, not a theme name: `drive-harddisk` only ships a
                // small raster here, and the toast requests 80px — the same
                // scale-up warning the other notification icons hit. An SVG scales.
                code === 0 ? Icons.assetPath("disk") : "dialog-error")
        }
    }

    // The re-probe is asynchronous, so the before/after comparison has to wait for the new
    // numbers rather than reading them straight after `refresh()`.
    onFilesystemsChanged: {
        if (!root._runDone || root._freeBefore <= 0) return
        const freed = root._rootFree() - root._freeBefore
        // Negative or trivial deltas are ignored: something else on the system writes to
        // disk while we work, and reporting "-4 MB reclaimed" because a log rotated would
        // be noise presented as a measurement.
        if (freed > 1048576)
            root._log("Freed " + root.bytes(freed) + " on /.", false)
        root._freeBefore = 0
    }

    // ── Notifications ─────────────────────────────────────────────────────────
    // Same route as Updates. Cleanup can take a while (paccache deleting 882 files, pacman
    // removing 137 packages), and the page lives inside the overview where one Escape
    // hides it.
    Process { id: notifyProc; running: false }

    function _notify(title, body, urgency, icon) {
        notifyProc.command = ["notify-send", "--app-name=Storage",
                              "--urgency=" + (urgency || "normal"),
                              "--icon=" + (icon || Icons.assetPath("disk")),
                              title, body]
        notifyProc.running = false
        notifyProc.running = true
    }

    Connections {
        target: UiState
        function onOverviewOpenChanged() {
            if (UiState.overviewOpen || !runProcess.running) return
            root._notify("Cleanup still running",
                         (root._runLabel || "A cleanup") + " is still working in the "
                         + "background. You'll get another notification when it's done.",
                         "low", Icons.assetPath("disk"))
        }
    }
}
