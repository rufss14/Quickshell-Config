pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../state"

// ── Updates ───────────────────────────────────────────────────────────────────
// Pending pacman update count.
//
// The check itself was already sensibly infrequent (every 10 minutes), but it
// lived *inside* the bar's UpdateButton — so it ran once per button, and the bar
// builds both its split and merged layouts, meaning two `checkupdates` processes
// on every tick, times the number of monitors. Hoisting it to a singleton makes
// that exactly one regardless of how many things display the count.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property int  count:    _count
    readonly property bool checking: _checking
    // `checkupdates` exits 1 with no output when the sync database can't be
    // read — a transient state (e.g. mid-`pacman -Sy`), not "zero updates".
    // Surfacing it lets the UI say "unknown" rather than confidently say "0".
    readonly property bool hasError: _hasError

    property int  _count:    0
    property bool _checking: false
    property bool _hasError: false

    // ── What is actually pending ──────────────────────────────────────────────
    // The bar only ever needed a NUMBER, so this service counted lines and threw the
    // content away. A settings page has to show WHICH packages, so the same output is
    // now parsed instead of tallied — no extra process, no extra work on the bar's path.
    //
    // `checkupdates` prints "name 1.2.3-1 -> 1.2.4-1". Lines that don't match that shape
    // are skipped rather than guessed at.
    //
    // [{ name, from, to, source }] — source is "official" | "aur" | "flatpak".
    readonly property var packages: root._official.concat(root._aur, root._flatpak)
    property var _official: []
    property var _aur:      []
    property var _flatpak:  []

    // Per-source lists, so a view can section them without re-filtering the combined one.
    readonly property var official: root._official
    readonly property var aur:      root._aur
    readonly property var flatpak:  root._flatpak

    readonly property int aurCount:     root._aur.length
    readonly property int flatpakCount: root._flatpak.length

    // ── Does this upgrade want a reboot? ──────────────────────────────────────
    // Derived from the list we already have, so it costs nothing. A running kernel keeps
    // its modules in /usr/lib/modules/<version>, and a kernel upgrade replaces that
    // directory — so after one, loading a module the running kernel hasn't already got
    // (plugging in a USB device, say) fails until you reboot. Same story for the
    // out-of-tree graphics modules.
    //
    // Worth saying out loud rather than leaving the user to notice: it's the single most
    // consequential thing a pacman upgrade can do to a session.
    readonly property var rebootPackages: root.packages.filter(p =>
        /^(linux|linux-lts|linux-zen|linux-hardened|linux-rt)(-headers)?$/.test(p.name)
        || /^(nvidia|nvidia-open|nvidia-dkms)$/.test(p.name))
    readonly property bool needsReboot: root.rebootPackages.length > 0
    // `count` stays OFFICIAL-ONLY on purpose: the bar's pill has shown that number for a
    // long time, and quietly folding AUR into it would change what an existing widget
    // means without anyone asking for it.
    readonly property int total: root._count + root.aurCount + root.flatpakCount

    // AUR needs a helper, and there may not be one. Detected once rather than assumed —
    // this machine has yay and no paru, but that's a fact about this machine.
    readonly property string helper: root._helper
    property string _helper: ""

    function _parseLine(line, source) {
        // name  from  ->  to   (checkupdates and `-Qua` share this exact shape)
        const m = line.trim().match(/^(\S+)\s+(\S+)\s+->\s+(\S+)$/)
        return m ? ({ name: m[1], from: m[2], to: m[3], source: source }) : null
    }

    // ── Check ─────────────────────────────────────────────────────────────────
    Process {
        id: proc
        command: ["checkupdates"]
        property var _rows: []

        stdout: SplitParser {
            onRead: function(line) {
                const row = root._parseLine(line, "official")
                if (row) proc._rows = proc._rows.concat([row])
            }
        }

        onExited: function(code) {
            const n = proc._rows.length
            if (n > 0) {
                root._official = proc._rows
                root._count    = n
                root._hasError = false
            } else if (code !== 1) {
                root._official = []
                root._count    = 0
                root._hasError = false
            } else {
                root._hasError = true
            }
            proc._rows     = []
            root._checking = false

            // AUR only after the official check, so the two can't interleave their
            // "checking" states and leave the spinner stuck on.
            if (root._helper) aurProc.running = true
            if (root._hasFlatpak) fpInstalled.running = true
        }
    }

    // ── AUR ───────────────────────────────────────────────────────────────────
    Process {
        id: helperProbe
        running: true
        command: ["bash", "-c",
                  "command -v paru >/dev/null && echo paru || " +
                  "(command -v yay >/dev/null && echo yay || echo)"]
        stdout: SplitParser {
            onRead: function(line) { root._helper = line.trim() }
        }
    }

    Process {
        id: aurProc
        running: false
        command: [root._helper || "true", "-Qua"]
        property var _rows: []

        stdout: SplitParser {
            onRead: function(line) {
                const row = root._parseLine(line, "aur")
                if (row) aurProc._rows = aurProc._rows.concat([row])
            }
        }
        // `-Qua` exits non-zero when there is nothing to report, which is not a failure —
        // so the rows decide the outcome, not the exit code.
        onExited: function(code) {
            root._aur = aurProc._rows
            aurProc._rows = []
        }
    }

    // ── Flatpak ───────────────────────────────────────────────────────────────
    // A separate package system with its own idea of everything, so it gets its own pair
    // of processes rather than being bent into the pacman path.
    //
    // ── What flatpak will and won't tell us ───────────────────────────────────
    // `remote-ls --updates` names what has an update but does NOT give the new version —
    // measured on this machine, the version column comes back EMPTY and only the branch
    // is populated ("org.gnome.Platform, , 50, flathub"). So there is no honest
    // old → new to show for flatpaks, and the row renders a plain "update available"
    // instead of inventing an arrow between two numbers.
    //
    // The installed version IS available (`flatpak list`), so that's shown as context.
    //
    // This one talks to the NETWORK and is by far the slowest check here, which is why
    // it runs last and never blocks the official count the bar depends on.
    readonly property bool hasFlatpak: root._hasFlatpak
    property bool _hasFlatpak: false
    property var  _fpInstalled: ({})     // app id → installed version

    Process {
        id: flatpakProbe
        running: true
        command: ["bash", "-c", "command -v flatpak >/dev/null && echo yes || echo"]
        stdout: SplitParser {
            onRead: function(line) { root._hasFlatpak = line.trim() === "yes" }
        }
    }

    Process {
        id: fpInstalled
        running: false
        command: ["flatpak", "list", "--columns=application,version"]
        property var _map: ({})

        stdout: SplitParser {
            onRead: function(line) {
                const parts = line.split("\t")
                if (parts.length >= 1 && parts[0].trim())
                    fpInstalled._map[parts[0].trim()] = (parts[1] ?? "").trim()
            }
        }
        onExited: function(code) {
            root._fpInstalled = fpInstalled._map
            fpInstalled._map  = ({})
            fpUpdates.running = true
        }
    }

    Process {
        id: fpUpdates
        running: false
        command: ["flatpak", "remote-ls", "--updates",
                  "--columns=application,version,branch"]
        property var _rows: []

        stdout: SplitParser {
            onRead: function(line) {
                const parts = line.split("\t")
                const name  = (parts[0] ?? "").trim()
                if (!name) return
                fpUpdates._rows = fpUpdates._rows.concat([{
                    name:   name,
                    from:   root._fpInstalled[name] ?? "",
                    // Empty in practice — see the note above. The row copes.
                    to:     (parts[1] ?? "").trim(),
                    source: "flatpak"
                }])
            }
        }
        onExited: function(code) {
            root._flatpak = fpUpdates._rows
            fpUpdates._rows = []
        }
    }

    function check() {
        if (proc.running) return
        proc._rows     = []
        root._checking = true
        proc.running   = true
    }

    Timer {
        interval: 600000            // 10 minutes
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.check()
    }

    // ── Post-update recheck ───────────────────────────────────────────────────
    // After an update run finishes, pacman's local db has changed but the sync
    // db may not have settled yet. Rechecking immediately tends to report a
    // stale count, so wait first. Call this when an update completes.
    Timer {
        id: recheckTimer
        interval: 90000
        repeat: false
        onTriggered: root.check()
    }
    function scheduleRecheck() { recheckTimer.restart() }

    // ══ Applying updates ══════════════════════════════════════════════════════
    // ── REMOVED: terminal detection and the terminal launcher ─────────────────
    // This service used to probe for kitty/foot/alacritty/… and run upgrades through
    // one. Nothing does that any more: the full upgrade hands off to UpdatePanel and a
    // selected install runs in-page via stdin (below), so `terminal`, `canApply`,
    // `apply()` and their Process had no callers left. Removed rather than left as
    // plausible-looking scaffolding for someone to wire back up.
    //
    // ── A FULL upgrade does not come through here ─────────────────────────────
    // `modules/panels/UpdatePanel.qml` already runs pacman + flatpak inside the shell,
    // with streamed output, a progress feed and its own password field. The settings page
    // triggers THAT (UiState.updateRequestId) rather than opening a terminal — the shell
    // had an in-shell updater the whole time and the page simply wasn't using it.
    //
    // What's left here is the case the panel deliberately doesn't cover: installing a
    // CHOSEN SUBSET.
    //
    // ── OFFICIAL PACKAGES CANNOT BE INSTALLED INDIVIDUALLY. This is deliberate ─
    // Not an omission, and not a thing to "finish later" — the operation is unsafe and
    // the UI does not offer it.
    //
    // `pacman -S pkg` cannot do it: checkupdates syncs a THROWAWAY database, so the
    // system's own sync db lags behind. Measured on this machine: `pacman -Qu` reported
    // 0 while checkupdates reported 17. So -S would find nothing to do and the button
    // would appear broken.
    //
    // Making it work needs `pacman -Sy pkg`, which syncs the database and then installs
    // ONE package against a newer repo state while everything else stays behind. That is
    // the partial upgrade Arch explicitly does not support, and it breaks systems for
    // real: update a library without the packages linked against it and those programs
    // stop starting. It is not a risk the user can meaningfully consent to at click time,
    // because the damage shows up later and somewhere else.
    //
    // The safe way to install one official package is to upgrade the system — so the UI
    // points at "Update everything" instead.
    //
    // ── Why the AUR/Flatpak subset still uses a terminal ──────────────────────
    // The AUR helper builds with makepkg and then calls sudo. There is no passwordless
    // sudo here (`sudo -n` is refused), so with no TTY it would hang forever on a prompt
    // nobody can see.
    // ══ Installing a selection, inside the shell ══════════════════════════════
    // Runs on the Updates page itself with its output streamed into the page — no
    // terminal. What made that possible is `Process.stdinEnabled` + `write()`: the sudo
    // password can be handed to the process directly instead of needing a TTY.
    //
    // ── The password goes over STDIN, never into the command ──────────────────
    // UpdatePanel builds `printf '%s\n' <pass> | sudo -S …` as a bash string, which puts
    // the password in the process's argv where anything reading /proc can see it. Writing
    // it to stdin after `started` keeps it out of the command line entirely. Same result,
    // one fewer place the password exists.
    //
    // ── sudo -v first, then the helper ────────────────────────────────────────
    // The AUR helper shells out to sudo itself, several times, at moments we don't
    // control. Piping a password *at the helper* would be guesswork about which child
    // reads stdin and when. Instead `sudo -S -v` validates once up front and caches the
    // credential, so the helper's own sudo calls find it already satisfied and never
    // prompt.
    //
    // Flatpak needs no password here: these installs are system-wide, so it authenticates
    // through polkit, which raises hyprpolkitagent's own dialog — a graphical prompt that
    // works fine without a terminal.
    readonly property bool  runBusy: runProcess.running
    readonly property var   runLog:  root._runLog
    readonly property int   runExit: root._runExit
    readonly property bool  runDone: root._runDone
    property var  _runLog:  []
    property int  _runExit: 0
    property bool _runDone: false
    property string _pendingPass: ""

    // ── Interactive prompts ─────────────────────────────────────────────────────
    // pacman and yay ASK — "Proceed? [Y/n]", "X and Y are in conflict. Remove Y?
    // [y/N]", "Enter a number" for providers, "Import PGP key…?". Running them with
    // --noconfirm made every conflict a silent failure (the default answer to a
    // removal prompt is "no", so pacman aborts). We now run them for real, through a
    // PTY, and surface each question here for the page to answer live.
    readonly property bool   awaitingInput: root._awaiting
    readonly property string promptText:    root._promptText   // the question line
    readonly property string promptKind:    root._promptKind   // yesno|number|password|text
    readonly property string promptDefault: root._promptDefault
    property bool   _awaiting: false
    property string _promptText: ""
    property string _promptKind: ""
    property string _promptDefault: ""
    // Raw output accumulates here until a newline; the trailing (unterminated)
    // fragment is where a prompt lives, since a prompt is printed WITHOUT a newline
    // and then blocks — so SplitParser's line mode would never emit it.
    property string _partial: ""

    function _log(text, isError) {
        if (!text || text.trim() === "") return
        root._runLog = root._runLog.concat([{ text: text, error: isError === true }])
    }

    function clearRun() {
        root._runLog  = []
        root._runDone = false
        root._runExit = 0
        root._partial  = ""
        root._clearPrompt()
    }

    function _clearPrompt() {
        root._awaiting      = false
        root._promptText    = ""
        root._promptKind    = ""
        root._promptDefault = ""
    }

    // ── How the run is wrapped: a real PTY, via python ────────────────────────
    // Two earlier tries failed. `--noconfirm` turned conflicts into silent aborts.
    // A plain pipe fixed that but "sometimes stopped": yay builds AUR packages for
    // minutes, its cached sudo credential expires, and the inner `sudo pacman`
    // re-prompts on a terminal that a plain pipe doesn't have — nothing can answer
    // it, so it hangs. `script` gives a terminal but buffers its stdout to a pipe
    // unpredictably (a real yay produced NOTHING and hung).
    //
    // `python -m pty.spawn` gives a genuine PTY AND writes output with os.write —
    // unbuffered, no `script` buffering. Every tool then behaves interactively and
    // flushes its prompts, stderr is folded into the one stream, /dev/tty works, and
    // a re-prompt from yay's inner sudo is just another "[sudo] password" we answer.
    // waitstatus_to_exitcode unpacks the child's real exit code from the wait status.
    function _wrap(cmd) {
        return ["python3", "-c",
                "import pty,sys,os; sys.exit(os.waitstatus_to_exitcode(pty.spawn(sys.argv[1:])))",
                "bash", "-c", cmd]
    }

    // ── Answering ─────────────────────────────────────────────────────────────
    function answer(text) {
        if (!runProcess.running) return
        // A password the user typed is remembered for the run, because yay's inner
        // sudo can re-prompt later (long AUR builds outlive the credential cache) and
        // we auto-answer those without asking again.
        if (root._promptKind === "password") root._pendingPass = text ?? ""
        runProcess.write((text ?? "") + "\n")
        root._partial = ""       // the prompt line is consumed; don't re-detect it
        root._clearPrompt()
    }
    function answerYes() { root.answer("y") }
    function answerNo()  { root.answer("n") }

    // Kill the run — the fallback for a question our parser doesn't recognise, so the
    // UI is never stuck on a prompt with no way out. Dropping the process stops bash
    // and its children.
    function cancelRun() {
        if (!runProcess.running) return
        root._log("✗ Cancelled by user.", true)
        runProcess.running = false
    }

    // ── Raw output → log lines + prompt detection ─────────────────────────────
    // The PTY terminates lines with \r\n and uses bare \r for redraws (download
    // bars). The terminating \r must be dropped BEFORE the redraw logic, or a normal
    // "line\r\n" gets treated as a redraw of nothing and logged EMPTY — which is
    // exactly why an earlier version showed no output. So: strip ANSI, split on \n,
    // drop one trailing \r (the CRLF), THEN collapse any remaining \r to its last
    // segment.
    function _rawRead(data) {
        let s = String(data)
            .replace(/\x1b\[[0-9;?]*[ -\/]*[@-~]/g, "")   // CSI (colour, cursor)
            .replace(/\x1b\][^\x07\x1b]*(\x07|\x1b\\)/g, "") // OSC (titles)
        root._partial += s

        let idx
        while ((idx = root._partial.indexOf("\n")) >= 0) {
            let line = root._partial.slice(0, idx)
            root._partial = root._partial.slice(idx + 1)
            if (line.endsWith("\r")) line = line.slice(0, -1)  // the CRLF's \r
            const r = line.lastIndexOf("\r")
            if (r >= 0) line = line.slice(r + 1)               // redraw: keep last
            root._log(line, false)
            // A wrong-password message is a COMPLETE line, so it can't be caught by
            // the fragment check below. Forget the stored password and let the next
            // "[sudo] password" prompt ask the user for the right one.
            if (/sorry, try again/i.test(line) || /incorrect password/i.test(line))
                root._pendingPass = ""
        }
        root._checkPrompt()
    }

    function _checkPrompt() {
        let cur = root._partial
        const r = cur.lastIndexOf("\r")
        if (r >= 0) cur = cur.slice(r + 1)
        cur = cur.replace(/\s+$/, "")
        if (cur === "") return

        // sudo's password prompt — on the PTY it prints "[sudo] password for …" with
        // echo OFF. Auto-answer with the stored password (kept for the whole run so
        // yay's later inner sudo re-prompts are handled too); ask the user only when
        // we have none, or the stored one was just rejected (cleared above).
        if (/\[sudo\] password for /i.test(cur) || /'s password:\s*$/i.test(cur)) {
            if (root._pendingPass !== "") {
                runProcess.write(root._pendingPass + "\n")
                root._partial = ""
            } else {
                root._setPrompt("Enter your password to continue.", "password", "")
            }
            return
        }

        // Provider selection: "Enter a number (default=1):"
        const num = cur.match(/enter a number(?:\s*\(default\s*=\s*(\d+)\))?/i)
        if (num) { root._setPrompt(cur, "number", num[1] ?? ""); return }

        // Yes/no — the uppercase letter in the bracket is the default.
        const yn = cur.match(/\[\s*(y\/n|n\/y)\s*\]\s*[:?]?\s*$/i)
        if (yn) { root._setPrompt(cur, "yesno", /Y/.test(yn[1]) ? "y" : "n"); return }

        // Not a shape we recognise — but if the line clearly ends in a question and
        // the process has gone quiet, still let the user type an answer rather than
        // hang. (Debounced by _quietTimer so mid-print lines don't trip it.)
        if (/[?:]\s*$/.test(cur)) { root._maybeQuiet(cur); return }

        root._clearPrompt()
    }

    function _setPrompt(text, kind, def) {
        root._promptText    = text
        root._promptKind    = kind
        root._promptDefault = def
        root._awaiting      = true
        quietTimer.stop()
    }

    // A line ending in ? or : that we don't recognise MIGHT be a prompt. Wait a
    // beat: if nothing more prints, treat it as one (free-text) so the run can't
    // wedge on a question we didn't anticipate.
    property string _quietCandidate: ""
    function _maybeQuiet(cur) {
        root._quietCandidate = cur
        quietTimer.restart()
    }
    Timer {
        id: quietTimer
        interval: 1500
        onTriggered: {
            if (runProcess.running && !root._awaiting && root._quietCandidate !== "")
                root._setPrompt(root._quietCandidate, "text", "")
        }
    }

    // Which selected packages come from where. Also answers "do we need a password".
    function selectionBySource(names) {
        const out = ({ official: [], aur: [], flatpak: [] })
        if (!names) return out
        for (let i = 0; i < root.packages.length; i++) {
            const p = root.packages[i]
            if (names.indexOf(p.name) >= 0) out[p.source].push(p.name)
        }
        return out
    }

    function selectionNeedsPassword(names) {
        return root.selectionBySource(names).aur.length > 0
    }

    // The whole lot, in-page, on the same runner as a selected install. Previously this
    // handed off to UpdatePanel; running it here means one password field, one log, and
    // one place to look — the panel is still what the BAR's update pill opens.
    function installAll(password) {
        if (runProcess.running) return

        // ── The helper, NOT pacman, when there is one ─────────────────────────
        // `yay -Syu` does everything `pacman -Syu` does AND rebuilds the AUR packages.
        // Plain pacman quietly skipped every AUR package while reporting success.
        //
        // The helper must run as the USER (makepkg refuses to run as root); it calls
        // sudo itself for the install step, and `sudo -v` up front primes the
        // credential cache so those inner calls don't re-prompt.
        //
        // NO --noconfirm: that is exactly what turned a conflict into a silent
        // failure. The AUR diff/clean/edit MENUS are answered non-interactively
        // (they're not conflicts, just noise), but pacman's real questions —
        // proceed, replacements, conflicts, key imports — are left to ask, and the
        // page answers them live.
        const steps = ["sudo -v"]
        steps.push(root._upgradeCmd())
        if (root._hasFlatpak) steps.push("flatpak update -y")

        root.clearRun()
        root._pendingPass = password ?? ""
        root._runLabel = "Updating everything"
        runProcess.stdinEnabled = true
        runProcess.command = root._wrap("set -e\n" + steps.join("\n"))
        runProcess.running = true
    }

    // The system upgrade command, with the helper's noisy AUR menus silenced but its
    // real prompts intact. yay and paru name those menu flags differently.
    function _upgradeCmd() {
        if (root._helper === "yay")
            return "yay -Syu --answerdiff=None --answerclean=None --answeredit=None"
        if (root._helper === "paru")
            return "paru -Syu --skipreview"
        if (root._helper)
            return root._helper + " -Syu"
        return "sudo pacman -Syu"
    }

    // What the run is, for the notification that fires after the user has walked away.
    readonly property string runLabel: root._runLabel
    property string _runLabel: ""

    // ── Vencord ───────────────────────────────────────────────────────────────
    // Re-patches Discord with Vencord. Discord replaces its own files on every update,
    // which un-patches it, so this is a thing you genuinely have to redo periodically —
    // and it is invisible to pacman, so nothing else on this page would ever mention it.
    //
    // ── What this actually does, stated plainly ───────────────────────────────
    // Downloads the official VencordInstaller CLI from GitHub and runs it AS ROOT. That
    // is a remote binary executed with full privileges, which is a real trust decision —
    // in your favour, since it's the upstream installer and the same thing UpdatePanel
    // has always done here, but worth naming rather than burying.
    //
    // Kept as its own action rather than folded into "Update everything": it isn't a
    // package update, it touches a different program, and it should be something you ask
    // for rather than something that happens on the way past.
    function installVencord(password) {
        if (runProcess.running) return

        const script = [
            "set -e",
            "CLI=$(mktemp /tmp/vencord-cli.XXXXXX)",
            // Cleaned up even if the installer fails — a trap, not a trailing rm that
            // `set -e` would skip on error.
            "trap 'rm -f \"$CLI\"' EXIT",
            "echo 'Downloading VencordInstaller…'",
            "curl -fsSL https://github.com/Vendicated/VencordInstaller/releases/latest"
              + "/download/VencordInstallerCli-Linux -o \"$CLI\"",
            "chmod +x \"$CLI\"",
            "sudo -v",
            "sudo \"$CLI\" --install --branch stable"
        ].join("\n")

        root.clearRun()
        root._pendingPass = password ?? ""
        root._runLabel = "Vencord"
        runProcess.stdinEnabled = true
        runProcess.command = root._wrap(script)
        runProcess.running = true
    }

    function installSelected(names, password) {
        if (runProcess.running || !names || names.length === 0) return

        const by = root.selectionBySource(names)
        // by.official is deliberately ignored — installing official packages singly is a
        // partial upgrade. See the block above; the UI blocks it too.
        const steps = []
        if (by.aur.length > 0 && root._helper) {
            steps.push("sudo -v")
            let s = root._helper + " -S --needed " + by.aur.join(" ")
            if (root._helper === "yay")
                s += " --answerdiff=None --answerclean=None --answeredit=None"
            else if (root._helper === "paru")
                s += " --skipreview"
            steps.push(s)
        }
        if (by.flatpak.length > 0 && root._hasFlatpak)
            steps.push("flatpak update -y " + by.flatpak.join(" "))

        if (steps.length === 0) return

        root.clearRun()
        root._pendingPass = by.aur.length > 0 ? (password ?? "") : ""
        root._runLabel = names.length + " package" + (names.length !== 1 ? "s" : "")

        // `set -e`: if sudo is cancelled, stop rather than running the helper and
        // burying an authentication failure under a wall of build output.
        runProcess.stdinEnabled = true
        runProcess.command = root._wrap("set -e\n" + steps.join("\n"))
        runProcess.running = true
    }

    Process {
        id: runProcess
        running: false
        // Stays OPEN for the whole run — the password AND every prompt answer go
        // through here. The password is NOT written on start: under the PTY, sudo
        // prints its prompt and turns echo OFF, so we wait for that prompt and answer
        // it (see _checkPrompt). Writing early would be echoed straight into the log.
        stdinEnabled: true

        // stdout carries EVERYTHING — the PTY folds stderr into it — read RAW
        // (splitMarker "") because a prompt is printed with no trailing newline and
        // then blocks, which line mode would never emit. _rawRead reassembles whole
        // lines for the log and inspects the still-open fragment for a question.
        stdout: SplitParser {
            splitMarker: ""
            onRead: function(data) { root._rawRead(data) }
        }
        // The PTY merges the child's stderr into stdout, so this only catches errors
        // from python/pty itself. Kept so those aren't lost.
        stderr: SplitParser { onRead: function(line) { root._log(line, true) } }

        onExited: function(code) {
            // Flush any final unterminated line (a summary line without a newline).
            if (root._partial.trim() !== "") { root._log(root._partial, false); root._partial = "" }
            root._clearPrompt()
            root._runExit = code
            root._runDone = true
            root._pendingPass = ""
            root._log(code === 0 ? "✓ Finished." : "✗ Exited with code " + code, code !== 0)
            root.scheduleRecheck()

            // ── Always notify, even if the page is open ───────────────────────
            // An install can outlast the user's attention by minutes, and the page is
            // inside the overview — one Escape and the log is gone. The notification is
            // the only thing that survives that, so it fires unconditionally rather than
            // only when we think nobody is looking. A duplicate "it's done" beside a
            // visible log costs nothing; a missing one loses the result entirely.
            root._notify(
                code === 0 ? "Updates finished" : "Update failed",
                code === 0 ? (root._runLabel || "Packages") + " installed successfully."
                           : (root._runLabel || "The update") + " stopped with code "
                             + code + ". Reopen Settings → Updates for the log.",
                code === 0 ? "normal" : "critical",
                // Absolute SVGs, not theme names: `system-software-update` /
                // `dialog-error` only ship small rasters here, and the toast asks
                // for a large one — which is the "could not load icon at 88px"
                // warning and the blank avatar. SVGs scale.
                code === 0 ? Icons.assetPath("update") : Icons.assetPath("error"))
        }
    }

    // ── Notifications ─────────────────────────────────────────────────────────
    // notify-send, the same route UpdatePanel already uses, so update messages arrive
    // through the shell's own notification daemon and look like everything else.
    Process { id: notifyProc; running: false }

    function _notify(title, body, urgency, icon) {
        notifyProc.command = ["notify-send", "--app-name=Updates",
                              "--urgency=" + (urgency || "normal"),
                              "--icon=" + (icon || Icons.assetPath("update")),
                              title, body]
        notifyProc.running = false
        notifyProc.running = true
    }

    // ── "Still running" when the user walks away ──────────────────────────────
    // The install lives in a settings page inside the overview, so closing the overview
    // hides the only sign it's happening — and it keeps going, because the Process
    // belongs to this singleton and not to the page. Without this you'd close the
    // overview and have no way of knowing pacman was still working.
    //
    // This service watching UI state is the one inversion in here, and it's deliberate:
    // the alternative is the PAGE noticing its own destruction, which also fires when you
    // merely switch to another settings tab — the wrong event, and a false alarm every
    // time you look at Sound mid-install.
    Connections {
        target: UiState
        function onOverviewOpenChanged() {
            if (UiState.overviewOpen || !runProcess.running) return
            root._notify("Updates still running",
                         (root._runLabel || "An update") + " is still installing in the "
                         + "background. You'll get another notification when it's done.",
                         "low", Icons.assetPath("update"))
        }
    }

}
