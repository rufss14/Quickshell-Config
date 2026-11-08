pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../state"
import "../config"
import "packages.js" as PkgJs
import "updatefmt.js" as UF
import "updatelog.js" as UL

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

    // When the last SUCCESSFUL check finished (epoch ms, 0 = none yet this session), and how that reads:
    // "3 min ago". Per minute, off the shared clock — the panel's "Checked …" line, which is what makes
    // "nothing pending" something you can trust rather than a number that might be 9 minutes stale.
    readonly property double lastChecked: root._checkedAt
    property double _checkedAt: 0
    readonly property string lastCheckedText: {
        Clock.minutes
        return UF.agoText(root._checkedAt, Date.now())
    }
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

    // ── Held back ────────────────────────────────────────────────────────────────
    // Packages the user chose to skip on the next upgrade. `--ignore` on the run we
    // build, NOT pacman's IgnorePkg (a root edit to a file a typo can brick, and it
    // never expires). Stored in Config so it survives a reload; a held name that is
    // no longer pending is simply inert, so nothing prunes the list.
    function isHeld(name) { return Config.updateHold.indexOf(name) !== -1 }
    function toggleHold(name) {
        const h = Config.updateHold.slice()
        const i = h.indexOf(name)
        if (i === -1) h.push(name); else h.splice(i, 1)
        Config.updateHold = h
    }
    function clearHolds() { Config.updateHold = [] }
    // Pending right now AND held — what the run will skip, and the number the panel
    // subtracts from `total` when it says how many it's about to install. Flatpak is
    // excluded: `flatpak update` has no exclude flag, so a hold there is unhonourable
    // and counting it would make the button promise a number it won't deliver.
    readonly property var heldPending: root.packages.filter(p =>
        p.source !== "flatpak" && root.isHeld(p.name))

    // AUR needs a helper, and there may not be one. Detected once rather than assumed —
    // this machine has yay and no paru, but that's a fact about this machine.
    readonly property string helper: root._helper
    property string _helper: ""

    // ── When the system was last fully upgraded ───────────────────────────────
    // pacman's own log, because it is the only DURABLE record: anything the shell
    // stored itself would be wrong the first time you upgraded from a terminal, and
    // would reset when the cache is cleared.
    //
    // "starting full system upgrade" specifically — not the newest package mtime, which
    // any single `pacman -S` moves, and not the last ALPM line, which a one-off install
    // would claim. This is the same line scripts/specs.sh reads for the About page.
    readonly property string lastUpgrade: root._lastUpgrade      // "YYYY-MM-DD", or ""
    property string _lastUpgrade: ""

    readonly property string lastUpgradeText: {
        if (root._lastUpgrade === "") return "No recorded system upgrade yet"
        // Parsed as LOCAL midnight — pacman logs local time, and comparing a local
        // timestamp against a UTC-parsed date is how "today" becomes "yesterday" for
        // anyone west of Greenwich.
        const then = new Date(root._lastUpgrade + "T00:00:00")
        if (isNaN(then.getTime())) return ""
        const days = Math.floor((Date.now() - then.getTime()) / 86400000)
        if (days <= 0) return "Last updated today"
        if (days === 1) return "Last updated yesterday"
        return "Last updated " + days + " days ago"
    }

    Process {
        id: lastUpgradeProc
        running: true
        // ── `grep -a` is REQUIRED, not defensive ──────────────────────────────
        // MEASURED on this machine: /var/log/pacman.log contains NUL bytes (partway
        // through — the residue of a pacman killed mid-write). GNU grep classifies any
        // input containing a NUL as BINARY and suppresses every match, silently: plain
        // `grep 'starting full system upgrade' /var/log/pacman.log` returns nothing and
        // exits 1 on a log that plainly contains the line. `-a` forces text mode.
        //
        // This is what the "reading the whole file through grep has misbehaved on this
        // machine" note in UpdatesPage was describing without knowing the cause. tail
        // first still bounds the read on a log that only grows; -a is what makes it
        // correct.
        command: ["bash", "-c",
            "tail -n 20000 /var/log/pacman.log 2>/dev/null"
            + " | grep -a 'starting full system upgrade' | tail -n 1 | cut -c2-11"]
        stdout: SplitParser {
            onRead: function(line) {
                const t = line.trim()
                if (t !== "") root._lastUpgrade = t
            }
        }
    }

    function refreshLastUpgrade() {
        lastUpgradeProc.running = false
        lastUpgradeProc.running = true
    }

    // ── Arch news ────────────────────────────────────────────────────────────────
    // The one thing `--noconfirm` genuinely can't cope with: an upgrade that needs a
    // manual step (a .pacnew merge, a package split, a keyring bump). Arch announces
    // those on the news feed. We can't parse intent out of a headline, so the rule is
    // blunt and honest: if the newest item is dated AFTER your last full upgrade, you
    // haven't seen it — show the headline and link it, let the user judge.
    //
    // Regex, not a DOM: it's Arch's own Atom feed and we want three fields off the
    // top entry. Fetched lazily (refreshNews, 30-min floor) so it costs nothing until
    // something actually looks at updates.
    readonly property string newsTitle: root._newsTitle
    readonly property string newsUrl:   root._newsUrl || "https://archlinux.org/news/"
    readonly property string newsDate:  root._newsDate      // "YYYY-MM-DD", or ""
    readonly property bool   newsUnread:
        root._newsDate !== "" && root._lastUpgrade !== "" && root._newsDate > root._lastUpgrade
    property string _newsTitle: ""
    property string _newsUrl:   ""
    property string _newsDate:  ""
    property real   _newsFetchedAt: 0

    function refreshNews() {
        if (Date.now() - root._newsFetchedAt < 1800000) return   // 30-minute floor
        root._newsFetchedAt = Date.now()
        newsProc.running = false
        newsProc.running = true
    }

    function _unescape(s) {
        return s.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
                .replace(/&quot;/g, '"').replace(/&#0?39;/g, "'").replace(/&#x27;/gi, "'")
    }

    Process {
        id: newsProc
        running: false
        command: ["bash", "-c",
            "curl -sL --max-time 10 https://archlinux.org/feeds/news/ 2>/dev/null | head -c 16000"]
        stdout: StdioCollector {
            onStreamFinished: {
                const first = (text.split("<entry>")[1] || "")
                const t = first.match(/<title[^>]*>([\s\S]*?)<\/title>/)
                const l = first.match(/<link[^>]*href="([^"]+)"/)
                const d = first.match(/<updated>(\d{4}-\d{2}-\d{2})/)
                     || first.match(/<published>(\d{4}-\d{2}-\d{2})/)
                root._newsTitle = t ? root._unescape(t[1].replace(/<[^>]+>/g, "").trim()) : ""
                root._newsUrl   = l ? l[1] : ""
                root._newsDate  = d ? d[1] : ""
            }
        }
    }

    function _parseLine(line, source) {
        // name  from  ->  to  [extra]
        //
        // `checkupdates` and `-Qua` do NOT quite share a shape, which is what this used
        // to assume. yay appends how long the update has been out:
        //
        //     zen-browser-bin 1.21.16b-1 -> 1.22b-1 [6d20h]
        //
        // and the `$` anchored straight after `to` rejected every line of it, so the AUR
        // half parsed to nothing and `aurCount` sat at 0 no matter what was pending.
        //
        // The trailing bracket is optional and its contents don't matter, with one
        // exception: `[ignored]` is how `pacman -Qu` marks an IgnorePkg entry — a package
        // deliberately held back, not an update on offer. `checkupdates` already strips
        // those, so this only matters if the official path ever reads `-Qu` directly, but
        // silently counting a pin as pending is exactly the kind of wrong number this
        // service exists to avoid.
        const m = line.trim().match(/^(\S+)\s+(\S+)\s+->\s+(\S+)(?:\s+\[([^\]]*)\])?$/)
        if (!m || m[4] === "ignored") return null
        return { name: m[1], from: m[2], to: m[3], source: source }
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
            root._checkedOnce = true
            if (!root._hasError) root._checkedAt = Date.now()
            if (!root._hasError) root._readSizes()

            // AUR only after the official check, so the two can't interleave their
            // "checking" states and leave the spinner stuck on.
            root._checkAur()
            root._checkFlatpak()
            // Cheap and rate-limited (30-min floor); keeps `newsUnread` warm so a
            // panel that opens doesn't have to wait on the network.
            root.refreshNews()
        }
    }

    // ── The AUR/Flatpak counts used to depend on losing a race ────────────────
    // These two run only if `_helper` / `_hasFlatpak` are already known — but both are
    // filled in by their own async probes that start at the same moment as the first
    // check. `checkupdates` syncs a throwaway database over the NETWORK, so it usually
    // finishes last and the probes have landed by then... usually. When they hadn't,
    // the first check silently counted official packages only, and nothing corrected it
    // until the 10-minute timer came round again.
    //
    // That is the bug behind "the badge only counts official". The fix is to stop
    // treating probe completion as something that happens before it's needed: whichever
    // of the two lands last drives the query, so the order no longer matters.
    property bool _checkedOnce: false

    function _checkAur() {
        if (!root._helper || !root._checkedOnce) return
        aurProc.running = false
        aurProc.running = true
    }

    function _checkFlatpak() {
        if (!root._hasFlatpak || !root._checkedOnce) return
        fpInstalled.running = false
        fpInstalled.running = true
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
        // If the first check beat this probe, its AUR half was skipped — run it now.
        onExited: root._checkAur()
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
        // Same as the helper probe: cover the case where the check finished first.
        onExited: root._checkFlatpak()
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
                  "--columns=application,version,branch,download-size"]
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
                    // Bytes, from the fourth column (NaN-safe: a missing one is just no size).
                    size:   UL.flatpakSize((parts[3] ?? "").trim()),
                    source: "flatpak"
                }])
            }
        }
        onExited: function(code) {
            root._flatpak = fpUpdates._rows
            root._fpSizeTotal = fpUpdates._rows.reduce((t, r) => t + (isFinite(r.size) ? r.size : 0), 0)
            fpUpdates._rows = []
        }
    }

    function check() {
        if (proc.running) return
        proc._rows     = []
        root._checking = true
        proc.running   = true
    }

    // The first check is always made (the counts must exist) — from the singleton's own Component.onCompleted
    // below; after that, every `updateCheckMins` minutes, unless that is 0 (by hand only) or it is quiet hours.
    Timer {
        interval: Math.max(1, Config.updateCheckMins) * 60000
        running: Config.updateCheckMins > 0
        repeat: true
        onTriggered: if (!root.quietNow) root.check()
    }
    readonly property bool quietNow: {
        Clock.minutes
        return Config.updateQuiet && UF.inQuiet(Clock.hours * 60 + Clock.minutes, Config.updateQuietFrom, Config.updateQuietTo)
    }

    // ══ Sizes ═════════════════════════════════════════════════════════════════
    // What an upgrade would DOWNLOAD, to the byte, from the database `checkupdates` just synced (its
    // throwaway copy, `${TMPDIR:-/tmp}/checkup-db-${UID}`): `pacman -Sup --print-format` lists every package
    // the upgrade fetches — new dependencies too, which the pending list does not show — with its size.
    // Flatpak sizes come in the check's own column. The AUR builds from source, so it has no download to
    // add up: the total says so by being "official + Flatpak".
    property var    _sizes: ({})         // name → bytes (official)
    property double _sizeTotal: 0        // everything pacman would fetch
    property double _fpSizeTotal: 0
    readonly property var sizes: root._sizes
    readonly property double downloadBytes: root._sizeTotal + root._fpSizeTotal
    readonly property string downloadText: root.downloadBytes > 0 ? UL.formatBytes(root.downloadBytes) : ""
    // A package's download in bytes, or NaN (an AUR package, or a check that has not landed).
    function sizeOf(pkg) {
        if (!pkg) return NaN
        if (pkg.source === "flatpak") return isFinite(pkg.size) ? pkg.size : NaN
        return pkg.source === "official" && root._sizes[pkg.name] !== undefined ? root._sizes[pkg.name] : NaN
    }

    function _readSizes() { sizeProc.running = false; sizeProc.running = true }
    Process {
        id: sizeProc
        command: ["bash", "-c",
                  'pacman -Sup --print-format "%n|%v|%s|%l" --dbpath "${CHECKUPDATES_DB:-${TMPDIR:-/tmp}/checkup-db-${UID}}" 2>/dev/null; true']
        stdout: StdioCollector { id: sizeOut }
        onExited: {
            const r = UL.parseSizes(sizeOut.text)
            root._sizes = r.sizes
            root._sizeTotal = r.total
        }
    }

    // ══ History ═══════════════════════════════════════════════════════════════
    // The last upgrades and installs, from pacman's own log (the only durable record — see lastUpgrade).
    // Read on demand, when the panel's History view opens. `grep -a`: the log can hold NUL bytes.
    property var  history: []
    property bool historyLoading: false
    function loadHistory() {
        if (historyProc.running) return
        root.historyLoading = true
        historyProc.running = true
    }
    Process {
        id: historyProc
        command: ["bash", "-c",
                  "tail -n 60000 /var/log/pacman.log 2>/dev/null"
                  + " | grep -a -E '\\[(ALPM|PACMAN)\\] (transaction (started|completed|failed)|upgraded|downgraded|installed|reinstalled|removed|Running)' || true"]
        stdout: StdioCollector { id: historyOut }
        onExited: {
            root.history = UL.parseHistory(historyOut.text, 15)
            root.historyLoading = false
        }
    }

    // ══ What's in an update ═══════════════════════════════════════════════════
    // The details behind a row, fetched when it is opened and kept for the session: an official package's
    // from the same synced database (`pacman -Si`) against what is installed (`-Qi`) — so the card can say
    // how much bigger it gets; an AUR package's from the AUR's own JSON (is it orphaned? flagged out of
    // date? when was it touched?). Flatpak has nothing cheap to add beyond the sizes it already gave.
    // One request at a time; names are checked before they reach a command (and arrive as ARGUMENTS).
    property var    _info: ({})          // key → { state: "loading" | "ok" | "error", rows }
    property var    _infoQueue: []
    property string _infoBusy: ""
    function infoKey(pkg) { return pkg.source + ":" + pkg.name + ":" + pkg.to }
    function infoOf(pkg) { return pkg ? (root._info[root.infoKey(pkg)] ?? null) : null }
    function _setInfo(key, v) { const n = Object.assign({}, root._info); n[key] = v; root._info = n }

    function requestInfo(pkg) {
        if (!pkg) return
        const key = root.infoKey(pkg)
        if (root._info[key] || root._infoBusy === key || root._infoQueue.some(q => q.key === key)) return
        if (pkg.source === "flatpak") {
            root._setInfo(key, { state: "ok", rows: UL.flatpakLines(pkg.from, root.sizeOf(pkg)) })
            return
        }
        if (!UL.validName(pkg.name)) { root._setInfo(key, { state: "error", rows: [] }); return }
        root._setInfo(key, { state: "loading", rows: [] })
        root._infoQueue = root._infoQueue.concat([{ key: key, pkg: pkg }])
        root._pumpInfo()
    }
    function _pumpInfo() {
        if (infoProc.running || root._infoQueue.length === 0) return
        const q = root._infoQueue[0]
        root._infoQueue = root._infoQueue.slice(1)
        root._infoBusy = q.key
        infoProc.pkg = q.pkg
        infoProc.command = q.pkg.source === "aur"
            ? ["curl", "-fsS", "--max-time", "12", "-g",
               "https://aur.archlinux.org/rpc/v5/info?arg[]=" + encodeURIComponent(q.pkg.name)]
            : ["bash", "-c",
               'DB="${CHECKUPDATES_DB:-${TMPDIR:-/tmp}/checkup-db-${UID}}"; pacman -Si --dbpath "$DB" "$1" 2>/dev/null;'
               + ' echo __INSTALLED__; pacman -Qi "$1" 2>/dev/null; true', "sh", q.pkg.name]
        infoProc.running = true
    }
    Process {
        id: infoProc
        property var pkg: null
        stdout: StdioCollector { id: infoOut }
        onExited: function (code) {
            const key = root._infoBusy
            root._infoBusy = ""
            let rows = []
            try {
                if (infoProc.pkg.source === "aur") rows = UL.aurLines((JSON.parse(infoOut.text).results || [])[0])
                else {
                    const i = UL.splitInfo(infoOut.text)
                    rows = UL.officialLines(i.next, i.old, root.sizeOf(infoProc.pkg))
                }
            } catch (e) { rows = [] }
            root._setInfo(key, { state: rows.length > 0 ? "ok" : "error", rows: rows })
            root._pumpInfo()
        }
    }

    // ══ A snapshot first ══════════════════════════════════════════════════════
    // snapper or timeshift, if either is installed (and not snap-pac, which already snapshots every pacman
    // transaction by itself — a second one would only be noise). `Config.updateSnapshot` puts the snapshot
    // in front of "Update everything"; if it fails the script's `set -e` stops the run before anything is
    // installed. See _upgradeSteps.
    property string _snapTool: ""
    property bool   _snapPac: false
    readonly property string snapshotTool: root._snapTool
    readonly property bool   snapPac: root._snapPac
    Process {
        id: snapProbe
        running: true
        command: ["bash", "-c", "command -v snapper timeshift 2>/dev/null; pacman -Qq snap-pac 2>/dev/null; true"]
        stdout: StdioCollector { id: snapOut }
        onExited: {
            root._snapTool = UL.snapshotTool(snapOut.text)
            root._snapPac = /^snap-pac$/m.test(snapOut.text)
        }
    }
    // Whether the run that is (or was last) going took one — so the panel can say so when it fails.
    readonly property bool runSnapshot: root._runSnapshot
    property bool _runSnapshot: false

    // ── Post-update recheck ───────────────────────────────────────────────────
    // TWO passes, and the first one is the point. This used to be a single timer at
    // ninety seconds, on the theory that pacman's databases need to settle — which
    // meant the bar pill's badge, the desktop tile and this service's counts all sat
    // on the pre-upgrade number for a minute and a half after an upgrade visibly
    // finished. That reads as the shell not noticing, and it was the one thing the
    // Settings page got right only by accident: it calls check() itself when its log
    // is dismissed, so the page looked correct while everything else went stale.
    //
    // The short pass is what updates the UI. The long one stays as a confirmation:
    // it costs one `checkupdates` and it is the safety net if the early read did
    // catch a database mid-write, so a wrong count can never be the resting state.
    Timer {
        id: recheckTimer
        interval: 3000
        repeat: false
        onTriggered: root.check()
    }
    Timer {
        id: recheckConfirmTimer
        interval: 90000
        repeat: false
        onTriggered: root.check()
    }
    function scheduleRecheck() {
        recheckTimer.restart()
        recheckConfirmTimer.restart()
    }

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
    // ── Flatpak goes through sudo, NOT polkit ─────────────────────────────────
    // It used to be plain `flatpak update -y`, on the reasoning that a system-wide
    // install authenticates through polkit and hyprpolkitagent's dialog works fine
    // without a terminal. True, and beside the point: by the time the Flatpak phase
    // runs, the user has ALREADY typed their password into the panel and `sudo -v`
    // has cached the credential. Polkit doesn't know that, so it asked for the same
    // password a second time, in a different dialog, in the middle of an upgrade the
    // user had already authorised. That is the "it asks twice".
    //
    // The selected-package path in installSelected() still uses polkit, and that is
    // deliberate rather than an oversight: a selection can be flatpaks ALONE, with no
    // sudo anywhere in the run and so no credential to reuse. There, polkit is the
    // only authentication in play and asking once is correct.
    readonly property bool  runBusy: root._jobRunning
    readonly property var   runLog:  root._runLog
    readonly property int   runExit: root._runExit
    // Why the run failed, in words, when its log says (updatelog.js failureHint); "" otherwise.
    readonly property string runHint: root._runHint
    readonly property bool  runDone: root._runDone
    property var  _runLog:  []
    property int  _runExit: 0
    property string _runHint: ""
    property bool _runDone: false
    property bool _jobRunning: false
    property string _pendingPass: ""

    // ── Launch sequence — the fix for "it says it updated when it didn't" ─────
    // `_attach()` starts the tail the moment the launcher is fired, so it first
    // replays the PREVIOUS run's whole log — including its trailing `__QS_DONE__`.
    // That stale sentinel was parsed as THIS run finishing (auto-close, success
    // notification, credential wiped → the real sudo prompt then asked again).
    // Every `_launch` bumps `_runSeq` and passes it to the runner, which echoes it
    // back as `__QS_RUN__ <seq>`; until the tail delivers OUR seq, `_sawRunMarker`
    // is false and `_rawRead` drops everything. Reattach to a surviving run sets it
    // true straight away — there, the log genuinely is the current run's.
    //
    // ── The token is NOT just the counter ─────────────────────────────────────
    // `_runSeq` restarts at 0 with every shell, so the first run of EVERY session was
    // `__QS_RUN__ 1` — and so was the stale log left by the previous session's first
    // run. The tail replays that stale log before the runner truncates it, its marker
    // matched, and the gate opened onto the old run: its `__QS_DONE__` ended THIS run
    // (`_handleDone` wipes `_pendingPass` and stops the tail) while the real sudo sat
    // unwatched on its prompt — "it failed, type the password again". The launch time
    // makes the token unique across restarts; the counter still breaks a same-ms tie.
    property int    _runSeq:       0
    property string _expectSeq:    ""
    property bool _sawRunMarker: true

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

    // ── Run progress, parsed from the runner's own output ───────────────────────
    // This lived in UpdatePanel, as private state on a QtObject inside the popup. It is
    // not presentation: `:: [n/N] …` is a PROTOCOL between update-run.sh and the shell,
    // the `inHooks` latch is a statement about what the runner is doing, and both have
    // to stay in step with that script. Parsing them in one of the two views meant:
    //
    //   • UpdatesPage — the richer view, and the one you reach for when a run is
    //     actually going wrong — had no phase awareness AT ALL. No phase name, no
    //     "2 of 3", and a progress bar with nothing driving it. It only ever looked
    //     right because it shows the raw log, where the markers are visible as text.
    //   • Anything else that ever wants progress (the bar pill, a notification) would
    //     have been a third copy of a parser that already existed twice over.
    //
    // The views now bind to these and hold no parsing of their own.
    readonly property real   runProgress:      root._runProgress      // 0..1, across all phases
    readonly property string runCurrentItem:   root._runCurrentItem   // package, or hook chatter
    readonly property int    runPkgsDone:      root._runPkgsDone
    readonly property int    runPkgCount:      root._runPkgCount
    readonly property int    runPhaseIndex:    root._runPhaseIndex    // 1-based; 0 = none yet
    readonly property int    runPhaseCount:    root._runPhaseCount
    readonly property real   runPhaseProgress: root._runPhaseProgress
    // Post-transaction hooks (mkinitcpio rebuilding boot images, systemd reload, …) run
    // AFTER every package is done, with zero package-progress signal — the bar sits at
    // 100% and the current item stops moving for however long they take, which for a
    // kernel upgrade can be the better part of a minute. That silence is what made a
    // real update look hung and get reloaded mid-write.
    readonly property bool   runInHooks:       root._runInHooks

    // ── Run summary ─────────────────────────────────────────────────────────────
    // Tallied from the same package lines the progress parser already reads, so the
    // finished screen can say "12 upgraded · 2 new · 1 removed · 214 MiB" instead of
    // just closing. Counts add across phases (a run can upgrade both repo and AUR),
    // which is what "this run did" means. Rebuilt from zero on a reattach replay,
    // same as the phase counters.
    readonly property int    runUpgraded:  root._runUpgraded
    readonly property int    runInstalled: root._runInstalled
    readonly property int    runRemoved:   root._runRemoved
    readonly property string runSizeText:  root._runSizeText     // "214.30 MiB", or ""

    property real   _runProgress:      0
    property string _runCurrentItem:   ""
    property int    _runPkgsDone:      0
    property int    _runPkgCount:      0
    property int    _runPhaseIndex:    0
    property int    _runPhaseCount:    0
    property real   _runPhaseProgress: 0
    property bool   _runInHooks:       false
    property int    _runUpgraded:      0
    property int    _runInstalled:     0
    property int    _runRemoved:       0
    property string _runSizeText:      ""

    function _resetProgress() {
        root._runProgress      = 0
        root._runCurrentItem   = ""
        root._runPkgsDone      = 0
        root._runPkgCount      = 0
        root._runPhaseIndex    = 0
        root._runPhaseCount    = 0
        root._runPhaseProgress = 0
        root._runInHooks       = false
        root._runUpgraded      = 0
        root._runInstalled     = 0
        root._runRemoved       = 0
        root._runSizeText      = ""
    }

    // Map "fraction through the current phase" onto one continuous bar. Before any phase
    // marker arrives (phaseCount 0) this degrades to plain 0→1, which is what
    // installVencord and a selected install want — they have no phases.
    function _setPhaseProgress(p) {
        const clamped = Math.max(0, Math.min(1, p))
        root._runPhaseProgress = clamped
        if (root._runPhaseCount <= 0) { root._runProgress = clamped; return }
        root._runProgress =
            (Math.max(0, root._runPhaseIndex - 1) + clamped) / root._runPhaseCount
    }

    function _parseProgress(line) {
        if (!line) return

        // ── Phase boundary from the runner: `:: [2/3] AUR packages` ───────────
        // Checked FIRST, before the hooks branch below, and this ordering is the whole
        // point. `_runInHooks` LATCHES: once pacman announces post-transaction hooks,
        // every subsequent line is treated as hook chatter. That was fine when the run
        // was one `yay -Syu`, because hooks were genuinely the last thing to happen. Now
        // that the upgrade runs in phases, the official phase's hooks would swallow the
        // AUR and Flatpak phases whole — no package progress, no phase name, just the
        // last hook's output frozen on screen for the rest of the run.
        //
        // A new phase therefore clears the latch and resets the per-phase counters.
        const ph = line.match(/^::\s*\[(\d+)\/(\d+)\]\s*(.*)/)
        if (ph) {
            root._runPhaseIndex  = parseInt(ph[1])
            root._runPhaseCount  = parseInt(ph[2])
            root._runCurrentItem = ph[3]
            root._runInHooks     = false
            root._runPkgsDone    = 0
            root._runPkgCount    = 0
            root._setPhaseProgress(0)
            return
        }

        // pacman's own literal wording (confirmed against the installed binary's
        // strings), not a guess. Once seen, every subsequent line becomes the "now
        // doing" text rather than trying to pattern-match individual hook scripts'
        // output, which varies by what's installed (mkinitcpio, systemd, depmod, …) —
        // the point is just to keep SOMETHING visibly moving.
        if (/running post-transaction hooks/i.test(line)) {
            root._runInHooks     = true
            root._runCurrentItem = "Finishing up…"
            // Every package in this phase is installed; the hooks are the tail of it.
            root._setPhaseProgress(1)
            return
        }
        if (root._runInHooks) {
            const t = line.trim()
            if (t !== "") root._runCurrentItem = t
            return
        }

        const m = line.match(
            /(upgrading|installing|reinstalling|removing)\s+(\S+)\s+\((\d+)\/(\d+)\)/i)
        if (m) {
            const verb = m[1].toLowerCase()
            const done = parseInt(m[3]), total = parseInt(m[4])
            root._runCurrentItem = m[2]
            root._runPkgsDone    = done
            if (verb === "removing")      root._runRemoved++
            else if (verb === "installing") root._runInstalled++
            else                          root._runUpgraded++   // upgrading / reinstalling
            if (total > 0) {
                root._runPkgCount = total
                root._setPhaseProgress(done / total)
            }
            return
        }
        // pacman's transaction summary — download total for the finished screen.
        const sz = line.match(/^\s*Total Download Size:\s+(.+\S)\s*$/i)
        if (sz) { root._runSizeText = sz[1]; return }
        // flatpak's byte progress — nudge, never rewind WITHIN the phase.
        const p = line.match(/([\d.]+)\s*MB\s*\/\s*([\d.]+)\s*MB/i)
        if (p && parseFloat(p[2]) > 0) {
            root._setPhaseProgress(Math.max(root._runPhaseProgress,
                                            parseFloat(p[1]) / parseFloat(p[2])))
            return
        }
        // pacman section header (":: …") — a phase, not a package.
        const d = line.match(/^::\s*(.*)/)
        if (d) root._runCurrentItem = d[1]
    }

    function _log(text, isError) {
        if (!text || text.trim() === "") return
        root._runLog = root._runLog.concat([{ text: text, error: isError === true }])
        // Parsed HERE, as each line arrives, rather than by a consumer diffing the log
        // against a high-water mark. The panel's version had to detect a shrunk log to
        // notice a new run had started; at this end there is no such thing as a line
        // arriving twice, so that whole class of bookkeeping disappears.
        root._parseProgress(text)
    }

    function clearRun() {
        root._runLog  = []
        root._runDone = false
        root._runExit = 0
        root._runHint = ""
        root._partial  = ""
        root._resetProgress()
        root._clearPrompt()
    }

    function _clearPrompt() {
        root._awaiting      = false
        root._promptText    = ""
        root._promptKind    = ""
        root._promptDefault = ""
    }

    // ── Reload safety: the run survives Quickshell dying, by any means ─────────
    // A real incident: reloading Quickshell while pacman was mid-transaction killed it
    // partway through writing kernel files and corrupted them. Qt kills a running child
    // the instant its Process wrapper is destroyed — reloading tears down and rebuilds
    // every QML object, so ANY reload while a Process owned pacman directly was a kill
    // switch. Guards exist at both reload sites now (ReloadPill, reload-quickshell.sh)
    // to refuse while a run is active, but a guard is a second thing that can be
    // bypassed or forgotten. The actual fix is here: pacman/yay/the Vencord installer no
    // longer run AS a QML Process at all.
    //
    // ── The shape ──────────────────────────────────────────────────────────────
    // A tiny launcher Process starts the script below under `setsid`, backgrounds it,
    // and exits immediately — so the QML Process that touched it is gone in
    // milliseconds, and the real job is reparented to init, in its own session, no
    // longer a descendant of Quickshell at all (verified with `ps`: PPID=1, its own
    // SID/PGID, the instant the launcher returns). Nothing Quickshell does afterwards —
    // reload, crash, a plain `pkill quickshell` — can reach it.
    //
    // Output goes to a LOG FILE, not a pipe, because a pipe only has one reader: this is
    // what makes REATTACHMENT possible. Quickshell watches with `tail -n +1 -F`, which is
    // disposable — if that tailer dies (also a reload), the job doesn't notice or care,
    // and starting a fresh tail (see _checkForSurvivedRun, run on startup) picks the
    // whole thing back up, log from the top.
    //
    // Stdin goes through a FIFO for the same reason `answer()` used to write directly to
    // the child: the sudo password must never touch a command line. The job keeps its
    // own read end open for its whole life (`exec 3<>"$FIFO"` — read-WRITE, so the FIFO
    // never sees EOF between answers), and anything — including a NEW ephemeral Process
    // spawned after a reattach — can open the same path to write an answer.
    //
    // Completion is a sentinel LINE in the log (`__QS_DONE__ <code>`), not
    // Process.onExited, for the same reattachment reason: whichever tail happens to be
    // watching when that line appears is what reports it, so it's the same code path
    // whether this is the first run or a resumed one. `__QS_LABEL__ <text>` is the same
    // idea for `runLabel`, which otherwise has nowhere to live across a restart.

    // XDG_CACHE_HOME, not a hardcoded ~/.cache — this config is published and installs
    // on machines that set it.
    readonly property string _cacheDir:
        Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")
    readonly property string _lockPath: root._cacheDir + "/quickshell-update.lock"
    readonly property string _jobDir:   root._cacheDir + "/quickshell-update"
    readonly property string _logPath:  root._jobDir + "/run.log"
    readonly property string _fifoPath: root._jobDir + "/run.fifo"

    // The runner is a reviewable file in the repo now, not a heredoc written to
    // ~/.cache on every start — which used to rewrite the script while a detached job
    // was still executing it. See scripts/update-run.sh.
    readonly property string _runnerPath: Quickshell.shellPath("scripts/update-run.sh")

    Component.onCompleted: {
        root._checkForSurvivedRun()
        Qt.callLater(root.check)
    }

    // ── Is a run in progress? Ask the LOCK, not a PID ─────────────────────────
    // A run survived a Quickshell restart — reattach instead of losing track of it.
    //
    // The test is `flock -n -s`: if the shared lock can be taken, nobody holds the
    // exclusive one, so no run is in progress. That is a kernel fact rather than the
    // old `kill -0 $PID` inference, which could not tell a live run from a recycled
    // PID and, more importantly, was checking a "lock" that never locked anything.
    // `-s` (shared) is used precisely because it does not truncate or disturb the
    // file the way an exclusive write-open would.
    function _checkForSurvivedRun() {
        reattachCheck.command = ["bash", "-c",
            '[ -f "$1" ] || exit 0; flock -n -s "$1" true || echo busy', "_", root._lockPath]
        reattachCheck.running = false
        reattachCheck.running = true
    }

    Process {
        id: reattachCheck
        running: false
        stdout: SplitParser {
            onRead: function(line) {
                if (line.trim() !== "busy") return
                // This is async and fires once, at startup — but "busy" only tells us
                // the lock is held, not by WHOM. If a real `installAll`/etc. has already
                // launched by the time this answer lands (a panel opened and clicked
                // within moments of a reload beats this to the lock), the lock it's
                // reporting is OUR OWN fresh run, not a survivor from before. Reattaching
                // ungated over that wipes the queued FIFO answer and can make the real
                // auto-answer miss the very prompt it exists to catch — the password
                // sits typed and unused while sudo's own prompt times out unanswered.
                if (root._runSeq > 0) return
                root._jobRunning = true
                root._attach()
            }
        }
    }

    // ── Launch ────────────────────────────────────────────────────────────────
    // The outer command is fixed and holds no variable content — cmd/label go through
    // argv, so nothing is ever re-quoted or interpolated into a shell string.
    //
    // The runner refuses (exit 75) if another run holds the lock, so a double-launch is
    // now impossible at the only level that can actually guarantee it. `_jobRunning`
    // stays as the UI's fast path, but it is no longer the thing standing between the
    // user and two concurrent pacman transactions.
    function _launch(cmd, label) {
        root._runLabel   = label
        root._jobRunning = true
        const seq = Date.now() + "." + (++root._runSeq)
        root._expectSeq  = seq
        launchProc.command = ["bash", "-c",
            'setsid bash "$0" run "$@" < /dev/null > /dev/null 2>&1 & disown; exit 0',
            root._runnerPath, root._jobDir, root._lockPath, root._logPath,
            root._fifoPath, label, cmd, seq]
        launchProc.running = false
        launchProc.running = true
        root._attach(true)          // gated: ignore the stale log until __QS_RUN__ <seq>
        launchWatchdog.restart()
    }

    Process { id: launchProc; running: false }

    // ── Nothing may leave the UI stuck on "Installing…" ───────────────────────
    // The launcher is fire-and-forget by design (it backgrounds the real job and exits
    // 0 immediately), so its exit status says nothing about whether the job started.
    // If the runner is missing or unrunnable, nothing ever writes to the log and
    // `_jobRunning` would stay true forever — the UI wedged with no run behind it.
    //
    // So: a few seconds after a launch, if no output has appeared, ask the lock who is
    // right. Held means a real run is simply quiet (or we lost the race to another
    // launch, which the runner's exit-75 path turns into "watch the existing run" —
    // the tail is already pointed at its log, so that resolves itself). Free means
    // nothing is running and the launch genuinely failed, so say so and let go.
    Timer {
        id: launchWatchdog
        interval: 6000
        repeat: false
        onTriggered: {
            if (!root._jobRunning || root._runLog.length > 0) return
            launchCheck.running = false
            launchCheck.running = true
        }
    }

    Process {
        id: launchCheck
        running: false
        command: ["bash", "-c",
            'if [ -f "$1" ] && ! flock -n -s "$1" true; then echo busy; else echo free; fi',
            "_", root._lockPath]
        stdout: SplitParser {
            onRead: function(line) {
                const t = line.trim()
                if (!root._jobRunning || root._runLog.length > 0) return
                if (t === "free") {
                    // Nothing holds the lock and nothing has written — the launcher
                    // genuinely failed (runner missing / unrunnable).
                    root._log("✗ The updater could not be started.", true)
                    root._log("Expected runner at: " + root._runnerPath, true)
                    root._handleDone(127)
                } else if (t === "busy" && !root._sawRunMarker) {
                    // Another run holds the lock, so our launcher backed off (exit 75)
                    // and our `__QS_RUN__` will never come. Watch the run that IS
                    // happening instead of sitting on an empty gated view.
                    root._attach(false)
                }
            }
        }
    }

    // (Re)start watching the job's log from the top. Same function for a fresh run and
    // a reattach — see the block comment above for why that's safe (tail -F just backs
    // up, and the sentinels are the same either way).
    // `gated` (from _launch): the log on disk is still the PREVIOUS run's until the
    // new runner truncates it, so drop everything the tail streams until it hits
    // `__QS_RUN__ <_expectSeq>`. Ungated (reattach): the log IS the running job's,
    // replay it in full.
    function _attach(gated) {
        root._runLog  = []
        root._runExit = 0
        root._runHint = ""
        root._runDone = false
        root._partial = ""
        root._sawRunMarker = (gated !== true)
        // The log is about to be replayed from line 1 — on a reattach that means every
        // line we already parsed comes past again, so the counters have to start from
        // zero or the phase index would run past its own total.
        root._resetProgress()
        root._clearPrompt()
        // Any answer still queued belonged to whatever run we were previously watching.
        // The runner recreates the FIFO from scratch for a fresh launch (`rm -f` +
        // `mkfifo`), so a stale queued answer dispatched now would land as bogus input
        // on a run it was never meant for.
        root._fifoQueue = []
        attachProc.running = false
        attachProc.command = ["tail", "-n", "+1", "-F", root._logPath]
        attachProc.running = true
    }

    Process {
        id: attachProc
        running: false
        // Raw, for the same reason the old direct-pipe read was: a prompt is printed
        // with no trailing newline and then blocks, which line mode would never emit.
        stdout: SplitParser {
            splitMarker: ""
            onRead: function(data) { root._rawRead(data) }
        }
        stderr: SplitParser {
            onRead: function(line) {
                if (line.trim() !== "") console.warn("[Updates tail]", line)
            }
        }
    }

    // Writes one answer into the job's FIFO via a short-lived helper process — `cat`
    // reading OUR stdin and copying it to the FIFO, so the actual text still never
    // touches a command line (same guarantee `runProcess.write()` gave before).
    //
    // ── Queued, not stomped ────────────────────────────────────────────────────
    // `fifoWriter` is one shared Process. Answering twice in quick succession (an
    // auto-answered sudo prompt landing at the same moment as a manual Send, or two
    // prompts back to back) used to reset it mid-flight — `running = false` on a
    // Process kills it, and a write that hadn't reached the FIFO yet was gone with no
    // trace. That's a real way for a typed password to just never arrive: sudo sits on
    // its own prompt until IT times out, which reads as "the update needs your input"
    // followed by "Update incomplete" for no visible reason. Queueing means a second
    // answer waits for the first to actually finish instead of erasing it.
    property var _fifoQueue: []
    property bool _fifoBusy: false

    function _writeToJob(text) {
        root._fifoQueue.push(text)
        root._pumpFifoQueue()
    }

    function _pumpFifoQueue() {
        if (root._fifoBusy || root._fifoQueue.length === 0) return
        root._fifoBusy = true
        fifoWriter.command = ["bash", "-c", 'cat > "$1"', "_", root._fifoPath]
        fifoWriter._pending = root._fifoQueue.shift()
        fifoWriter.stdinEnabled = true
        fifoWriter.running = true
    }

    Process {
        id: fifoWriter
        running: false
        property string _pending: ""
        onStarted: {
            fifoWriter.write(fifoWriter._pending)
            fifoWriter._pending = ""
            // Closes fifoWriter's own stdin, which is `cat`'s stdin — `cat` sees EOF,
            // flushes what it has into the FIFO, and exits. Same idiom as Storage.qml.
            fifoWriter.stdinEnabled = false
        }
        // Free the queue for the next answer only once this one has actually exited —
        // `cat` exiting means the FIFO write is flushed, not just requested.
        onExited: {
            root._fifoBusy = false
            root._pumpFifoQueue()
        }
    }

    // ── Answering ─────────────────────────────────────────────────────────────
    function answer(text) {
        if (!root._jobRunning) return
        // A password the user typed is remembered for the run, because yay's inner
        // sudo can re-prompt later (long AUR builds outlive the credential cache) and
        // we auto-answer those without asking again.
        if (root._promptKind === "password") root._pendingPass = text ?? ""
        root._writeToJob((text ?? "") + "\n")
        root._partial = ""       // the prompt line is consumed; don't re-detect it
        root._clearPrompt()
    }
    function answerYes() { root.answer("y") }
    function answerNo()  { root.answer("n") }

    // Kill the run — the fallback for a question our parser doesn't recognise, so the UI
    // is never stuck on a prompt with no way out.
    //
    // ── The old group-kill did not work, and that is how this got bad ─────────
    // It sent SIGTERM to the wrapper's PROCESS GROUP, on the stated assumption that
    // "every descendant — python3, the pty child, pacman/yay — shares that PGID".
    // MEASURED against a real wedged run: they do not. `pty.spawn` calls setsid() in its
    // child, so one run spans FOUR process groups (wrapper / pty child / sudo / pacman).
    // The kill reached the wrapper and nothing else — leaving yay and pacman alive,
    // invisible and unreachable, which is exactly how two upgrades ended up running
    // against one pacman database at the same time.
    //
    // The runner now walks the real process tree instead. It also deliberately cannot
    // signal the root-owned pacman, which is the safer outcome: killing the user-owned
    // side closes the PTY master, pacman reads EOF at whatever prompt it is on, and it
    // exits through its own cleanup. A pacman killed by signal mid-transaction is
    // precisely what strands /var/lib/pacman/db.lck and breaks every later update.
    function cancelRun() {
        if (!root._jobRunning) return
        root._log("✗ Cancelled by user.", true)
        cancelProc.command = ["bash", root._runnerPath, "cancel", root._lockPath]
        cancelProc.running = false
        cancelProc.running = true
    }

    Process { id: cancelProc; running: false }

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

            // Control lines from the wrapper script, not real output — see scripts/update-run.sh.
            // Never logged, never scanned as a prompt.

            // Fresh-run marker. Until we see the seq WE launched with, everything the
            // tail hands us is the previous run's log (the runner hadn't truncated
            // yet). Match → wipe whatever leaked through and start clean.
            if (line.indexOf("__QS_RUN__ ") === 0) {
                const s = line.substring(11).trim()
                if (!root._sawRunMarker && s === root._expectSeq) {
                    root._sawRunMarker = true
                    // Stale lines before the marker were dropped by the gate as they
                    // arrived; _partial now holds only post-marker bytes. Just reset
                    // the derived state the dropped lines never got to touch.
                    root._runLog  = []
                    root._resetProgress()
                    root._clearPrompt()
                }
                continue
            }
            // Gated attach, marker not seen yet → stale pre-truncation content. Drop it.
            if (!root._sawRunMarker) continue

            if (line.indexOf("__QS_LABEL__ ") === 0) { root._runLabel = line.substring(13); continue }
            if (line.indexOf("__QS_DONE__ ") === 0) {
                const code = parseInt(line.substring(12), 10)
                root._handleDone(isNaN(code) ? 1 : code)
                continue
            }

            root._log(line, false)
            // A wrong-password message is a COMPLETE line, so it can't be caught by
            // the fragment check below. Forget the stored password and let the next
            // "[sudo] password" prompt ask the user for the right one.
            if (/sorry, try again/i.test(line) || /incorrect password/i.test(line))
                root._pendingPass = ""
        }
        root._checkPrompt()
    }

    // Mirrors what runProcess.onExited used to do, now triggered by the __QS_DONE__
    // sentinel instead — see the protocol notes in scripts/update-run.sh for why.
    function _handleDone(code) {
        root._runExit    = code
        root._runHint    = code === 0 ? "" : UL.failureHint(root._runLog.map(l => l.text))
        root._runDone    = true
        root._jobRunning = false
        root._pendingPass = ""
        // A finished run is a full bar, whatever the last parsed line happened to say.
        // A phase that emitted no per-package lines (an all-flatpak selection, a run
        // that failed early) would otherwise leave the bar parked mid-way under a
        // "Finished" heading. Both views used to do this for themselves.
        root._runProgress = 1.0
        root._clearPrompt()
        const summary = root._runSummaryText()
        root._log(code === 0 ? ("✓ Finished" + (summary ? " — " + summary : "") + ".")
                             : "✗ Exited with code " + code, code !== 0)
        root.scheduleRecheck()
        // The log has just gained a "full system upgrade" line, so "last updated" is
        // stale the moment a run ends.
        root.refreshLastUpgrade()
        attachProc.running = false

        // ── Notify — but tell the truth about a "success" that did nothing ────
        // A failure is reported now (the code is authoritative). A clean exit is
        // held until the 3s recheck lands: `pacman -Syu` exits 0 when its packages
        // are held or a phase no-op'd, and "installed successfully" over a list that
        // didn't move is the "it said it updated when it didn't" report.
        if (code !== 0) {
            root._notify("Update failed",
                (root._runLabel || "The update") + " stopped with code " + code + ". "
                    + (root._runHint || "Reopen Settings → Updates for the log."),
                "critical", Icons.assetPath("error"))
        } else {
            resultNotify.restart()
        }
    }

    // "12 upgraded · 2 new · 1 removed · 214 MiB" — omits any zero, so a small run
    // reads "3 upgraded" and a no-op run returns "" (which the finished line then
    // flags rather than celebrating).
    function _runSummaryText() {
        const bits = []
        if (root._runUpgraded  > 0) bits.push(root._runUpgraded  + " upgraded")
        if (root._runInstalled > 0) bits.push(root._runInstalled + " new")
        if (root._runRemoved   > 0) bits.push(root._runRemoved   + " removed")
        if (root._runSizeText !== "") bits.push(root._runSizeText)
        return bits.join("  ·  ")
    }

    Timer {
        id: resultNotify
        interval: 4000              // past the 3s post-run recheck
        onTriggered: {
            if (root._runExit !== 0) return
            const label = root._runLabel || "Packages"
            const nothingLeft = root.total === 0 || root._hasError
                              || root._runLabel === "Vencord"
            if (nothingLeft) {
                const s = root._runSummaryText()
                root._notify("Updates finished",
                    s ? label + " — " + s : label + " installed successfully.",
                    "normal", Icons.assetPath("update"))
            } else {
                root._notify("Update incomplete",
                    "The upgrade reported success but " + root.total + " package"
                        + (root.total === 1 ? "" : "s") + " still show as pending. "
                        + "Open Settings → Updates for the log.",
                    "critical", Icons.assetPath("error"))
            }
        }
    }

    function _checkPrompt() {
        // Gated attach still replaying the previous run's tail — its trailing
        // unterminated line could be that run's own sudo prompt. Not ours to answer.
        if (!root._sawRunMarker) return
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
                root._writeToJob(root._pendingPass + "\n")
                root._partial = ""
            } else {
                // Diagnostic: this is the case that used to fail silently — a password
                // prompt with nothing stored to answer it, either because the user never
                // typed one (a later re-prompt) or because it was cleared (a wrong
                // attempt, or a run boundary). Not a bug by itself, but if a launch that
                // DID collect a password ends up here, this line is what tells the two
                // apart after the fact instead of guessing from a bare timeout.
                console.warn("[Updates] password prompt with no stored password — asking",
                             "(run:", root._runLabel + ", seq:", root._expectSeq + ")")
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

        // ── REMOVED: the "anything quiet for 1.5s is a prompt" fallback ───────
        // It treated ANY unterminated output fragment that went quiet as a question,
        // on the theory that genuinely slow work prints complete, newline-terminated
        // lines. That theory is wrong in practice, and it was a major source of the
        // "it constantly asks for input" complaint: a stalled mirror mid-download, a
        // long AUR compile that emitted a partial line, and mkinitcpio all sit quiet
        // on an unterminated fragment while working perfectly well — and each one
        // raised a fake free-text prompt that the user then had to dismiss.
        //
        // It was there to stop a run wedging on an unrecognised question. The
        // upgrade is non-interactive now (see _upgradeSteps), so the questions it was
        // guessing at are not asked in the first place, and Cancel is always present
        // in the UI for the case where something genuinely does block. Guessing was
        // costing far more than it was saving.
    }

    function _setPrompt(text, kind, def) {
        root._promptText    = text
        root._promptKind    = kind
        root._promptDefault = def
        root._awaiting      = true
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
        if (root._jobRunning) return

        root._pendingPass = password ?? ""
        root._launch(root._upgradeSteps(), "Updating everything")
    }

    // ── The upgrade, in named phases, non-interactive ─────────────────────────
    // This replaces a single `yay -Syu` run interactively.
    //
    // ── Why it was split ──────────────────────────────────────────────────────
    // `yay -Syu` is one command that does two jobs, and it asks about BOTH before
    // doing either: first its own "Packages to exclude" menu, then pacman's "Proceed
    // with installation?", then a second proceed for the AUR batch. Three questions
    // per run, every run, all of them re-asking something the user already answered by
    // pressing "Update everything" — and if any of them failed, the failure was
    // attributable to "the update" rather than to a phase.
    //
    // Split into `pacman -Syu` then `<helper> -Sua` (AUR-only sysupgrade), each phase
    // stands alone: `-Sua` skips the exclude menu entirely, and a failure names which
    // half broke. The `::` lines are section headers pacman itself uses, and
    // UpdatePanel's existing parser already renders them as the current phase — so the
    // progress feed says "Official packages" / "AUR packages" for free.
    //
    // ── Why --noconfirm is right here, having been wrong before ───────────────
    // It was removed once because it turned a conflict into a silent failure: the
    // default answer to "remove conflicting package?" is no, so pacman aborted and
    // nothing said why. That diagnosis was correct and the conclusion was not. Going
    // fully interactive meant the shell had to detect, render and route an answer for
    // every question pacman can ask, over a PTY, through a FIFO — machinery that had
    // more failure modes than the problem it solved, and which produced the phantom
    // prompts removed in _checkPrompt above.
    //
    // The cheaper answer: keep --noconfirm, and treat the abort as what it is — a
    // clear, safe, non-destructive stop that we report. An aborted upgrade changes
    // nothing on disk and can be re-run by hand once the conflict is understood; a
    // half-answered prompt on a hijacked stdin cannot be undone. The prompt machinery
    // stays for the residual cases (a first sudo password, an unexpected question),
    // it just is not load-bearing any more.
    //
    // `sudo -v` still primes the credential; scripts/update-run.sh keeps it fresh for
    // the whole run, so no phase re-prompts partway through.
    // ── The phase markers are NUMBERED, and that is load-bearing ──────────────
    // `:: [2/3] AUR packages`, not just `:: AUR packages`. Two reasons, both about
    // UpdatePanel's log parser rather than about cosmetics:
    //
    //  • pacman prints its own `::` section headers (":: Synchronizing package
    //    databases…"), so a bare `::` line cannot be told apart from a phase boundary.
    //    The `[n/N]` shape is unambiguous.
    //  • The panel's progress is per-phase. Without knowing which phase of how many,
    //    the bar would run 0→100% three times over and read as if it had restarted.
    //    With the numbers it maps each phase into its own segment of one bar.
    //
    // The helper must run as the USER — makepkg refuses to run as root — and calls sudo
    // itself for the install step, which update-run.sh's keepalive has already satisfied.
    // Held-back names for one source, restricted to what's actually pending — a
    // stale hold on a package that's already current would put a bogus name in
    // --ignore, which pacman warns about.
    function _heldFor(source) {
        return root.packages
            .filter(p => p.source === source && Config.updateHold.indexOf(p.name) !== -1)
            .map(p => p.name)
    }

    function _upgradeSteps() {
        const offHeld = root._heldFor("official")
        const pacmanCmd = "sudo -S pacman -Syu --noconfirm"
            + (offHeld.length ? " --ignore " + offHeld.join(",") : "")

        const phases = [["Official packages", pacmanCmd]]
        if (root._helper)     phases.push(["AUR packages", root._aurUpgradeCmd()])
        if (root._hasFlatpak) phases.push(["Flatpak",      root._flatpakUpgradeCmd()])

        const steps = ["set -e", "sudo -S -v"]
        // The way back, if asked for: BEFORE the first phase, and not a numbered one (the progress bar is split
        // by the numbered markers, and a snapshot is seconds against an upgrade's minutes).
        const snap = Config.updateSnapshot && root._snapTool !== "" && !root._snapPac
            ? UL.snapshotCommand(root._snapTool) : ""
        root._runSnapshot = snap !== ""
        if (snap !== "") {
            steps.push('echo ":: Taking a snapshot first (' + root._snapTool + ')…"')
            steps.push(snap)
        }
        for (let i = 0; i < phases.length; i++) {
            steps.push('echo ":: [' + (i + 1) + "/" + phases.length + '] ' + phases[i][0] + '"')
            steps.push(phases[i][1])
        }
        return steps.join("\n")
    }

    // ── The Flatpak phase, in the two scopes it actually has ──────────────────
    // `--system` under sudo is what removes the second password dialog — see the note
    // by _pendingPass. It has to be BOTH scopes and not just `sudo flatpak update`,
    // because as root the "user" installation is root's own (empty) one, so a plain
    // sudo'd update would quietly stop updating anyone's per-user apps.
    //
    // The user pass is guarded by an existence check rather than `|| true`: with no
    // user installation there is nothing to do and the phase should skip it, but a
    // user update that genuinely FAILS still has to trip `set -e` and be reported. An
    // `if` condition is exempt from set -e, so the guard can't abort the run itself.
    function _flatpakUpgradeCmd() {
        return 'sudo -S flatpak update --system -y\n'
             + 'if [ -n "$(flatpak list --user --columns=application 2>/dev/null)" ]; then\n'
             + '    flatpak update --user -y\n'
             + 'fi'
    }

    // AUR-only sysupgrade. The diff/clean/edit menus are noise rather than questions,
    // and yay and paru name those flags differently.
    function _aurUpgradeCmd() {
        const held = root._heldFor("aur")
        const ign  = held.length ? " --ignore " + held.join(",") : ""
        if (root._helper === "yay")
            return "yay -Sua --noconfirm --answerdiff=None --answerclean=None --answeredit=None" + ign
        if (root._helper === "paru")
            return "paru -Sua --noconfirm --skipreview" + ign
        return root._helper + " -Sua --noconfirm" + ign
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
        if (root._jobRunning) return

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
            "sudo -S -v",
            "sudo -S \"$CLI\" --install --branch stable"
        ].join("\n")

        root._runSnapshot = false
        root._pendingPass = password ?? ""
        root._launch(script, "Vencord")
    }

    function installSelected(names, password) {
        if (root._jobRunning || !names || names.length === 0) return

        const by = root.selectionBySource(names)
        // by.official is deliberately ignored — installing official packages singly is a
        // partial upgrade. See the block above; the UI blocks it too.
        const steps = []
        if (by.aur.length > 0 && root._helper) {
            steps.push("sudo -S -v")
            // --noconfirm for the same reason the full upgrade uses it: the user picked
            // these packages explicitly, so re-confirming them is noise, and a conflict
            // aborting cleanly beats a prompt nobody can reliably answer.
            let s = root._helper + " -S --needed --noconfirm " + by.aur.join(" ")
            if (root._helper === "yay")
                s += " --answerdiff=None --answerclean=None --answeredit=None"
            else if (root._helper === "paru")
                s += " --skipreview"
            steps.push(s)
        }
        if (by.flatpak.length > 0 && root._hasFlatpak)
            steps.push("flatpak update -y " + by.flatpak.join(" "))

        if (steps.length === 0) return

        root._runSnapshot = false
        root._pendingPass = by.aur.length > 0 ? (password ?? "") : ""
        // `set -e`: if sudo is cancelled, stop rather than running the helper and
        // burying an authentication failure under a wall of build output.
        root._launch("set -e\n" + steps.join("\n"),
                      names.length + " package" + (names.length !== 1 ? "s" : ""))
    }

    // ── Installing NEW packages (the launcher's `+` search, services/Packages) ─
    // Repos and AUR by name, on this same runner — the password prompt, the progress, the
    // flock. packages.js builds the script and re-checks every name (the trust boundary
    // is here: names come from search output). `pacman -S` without `-y`: a new package
    // from the databases as they are, never a partial upgrade. false when nothing was
    // started (a run already going, no valid name, the AUR with no helper).
    function installPackages(official, aur, label) {
        if (root._jobRunning) return false
        const script = PkgJs.installScript(official, aur, root._helper)
        if (script === "") return false
        root._runSnapshot = false
        root._pendingPass = ""      // sudo asks; the panel shows the field (_checkPrompt)
        root._launch(script, "Installing " + (label || "packages"))
        return true
    }

    // ── Notifications ─────────────────────────────────────────────────────────
    // notify-send, the same route UpdatePanel already uses, so update messages arrive
    // through the shell's own notification daemon and look like everything else.
    Process { id: notifyProc; running: false }

    function _notify(title, body, urgency, icon) {
        notifyProc.command = ["notify-send", "--app-name=Quickshell",
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
            if (UiState.overviewOpen || !root.runBusy) return
            root._notify("Updates still running",
                         (root._runLabel || "An update") + " is still installing in the "
                         + "background. You'll get another notification when it's done.",
                         "low", Icons.assetPath("update"))
        }
    }

}
