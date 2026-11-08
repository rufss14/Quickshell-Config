.pragma library

// ── updatelog.js ──────────────────────────────────────────────────────────────
// What the update panel reads OUT of the system, as logic rather than QML: sizes from pacman's
// print format, past upgrades from /var/log/pacman.log, a package's details from `pacman -Si` and
// the AUR's JSON, the commands that undo or precede an upgrade. Pure functions; tested by
// `bun scripts/test-updatelog.js`. (updatefmt.js is the panel's words; this is its data.)
// ─────────────────────────────────────────────────────────────────────────────

// ── Sizes ─────────────────────────────────────────────────────────────────────
function formatBytes(n) {
    if (!isFinite(n) || n < 0) return ""
    if (n < 1024) return Math.round(n) + " B"
    const units = ["KiB", "MiB", "GiB", "TiB"]
    let v = n / 1024, i = 0
    while (v >= 1024 && i < units.length - 1) { v /= 1024; i++ }
    // Two significant decimals while small, none once large, and never a trailing zero ("5 GiB", not "5.0 GiB").
    return Number(v.toFixed(v >= 100 ? 0 : v >= 10 ? 1 : 2)) + " " + units[i]
}

// "1971.53 KiB", "5.8 MiB" (pacman, binary) and "12.3 MB", "340 kB" (flatpak, decimal) → bytes, or NaN.
function parseSizeText(s) {
    const m = /^\s*([\d.,]+)\s*([A-Za-z]*)\s*$/.exec(String(s === undefined || s === null ? "" : s))
    if (!m) return NaN
    const n = parseFloat(m[1].replace(",", "."))
    if (!isFinite(n)) return NaN
    const u = m[2].toLowerCase()
    const bin = { "": 1, b: 1, kib: 1024, mib: 1048576, gib: 1073741824, tib: 1099511627776 }
    const dec = { kb: 1000, mb: 1e6, gb: 1e9, tb: 1e12 }
    const f = bin[u] !== undefined ? bin[u] : dec[u]
    return f === undefined ? NaN : Math.round(n * f)
}

function signedBytes(d) {
    if (!isFinite(d)) return ""
    if (Math.abs(d) < 1024) return "about the same"
    return (d > 0 ? "+" : "−") + formatBytes(Math.abs(d))
}

// `pacman -Sup --print-format '%n|%v|%s|%l'`: one line per package the upgrade would fetch (new
// dependencies included) with its download size in bytes. → { sizes: { name: bytes }, total }.
function parseSizes(text) {
    const sizes = {}
    let total = 0
    String(text || "").split("\n").forEach(function (line) {
        const p = line.split("|")
        if (p.length < 3) return
        const b = parseInt(p[2], 10)
        if (!p[0] || !isFinite(b) || b < 0) return
        sizes[p[0]] = b
        total += b
    })
    return { sizes: sizes, total: total }
}

// `flatpak remote-ls --updates --columns=…,download-size` third-or-later column text → bytes, or NaN.
function flatpakSize(col) { return parseSizeText(col) }

// ── Names that may become part of a command ───────────────────────────────────
// Package names and versions come from pacman's own output, but they end up in a command the user is
// handed to paste — so they are checked, not trusted. Arch's own rule: letters, digits, @ . _ + -.
function validName(n) { return typeof n === "string" && n.length > 0 && n.length < 128 && /^[A-Za-z0-9@._+][A-Za-z0-9@._+\-]*$/.test(n) }
function validVersion(v) { return typeof v === "string" && v.length > 0 && v.length < 128 && /^[A-Za-z0-9._+:~\-]+$/.test(v) }

// The command that puts a package back to the version it was: from pacman's own cache, which is exactly
// what the cache is for. A glob, because the file name carries the architecture and the compression, and
// an epoch ("1:") is not always spelled the same in a file name. Never run by the shell — it is copied.
function downgradeCmd(name, from) {
    if (!validName(name) || !validVersion(from)) return ""
    const ver = from.replace(/^\d+:/, "")
    return "sudo pacman -U /var/cache/pacman/pkg/" + name + "-*" + ver + "-*.pkg.tar*"
}

// ── The snapshot before an upgrade ────────────────────────────────────────────
// The commands for the two snapshot tools worth supporting. Fixed strings: nothing typed reaches them.
// A failing one stops the whole run (the script is `set -e`) BEFORE anything is installed — which is the
// point: you asked for a way back, and no way back means no upgrade.
function snapshotCommand(tool) {
    const d = "Quicktest: before system update"
    if (tool === "snapper")  return "sudo -S snapper -c root create --type single --description '" + d + "'"
    if (tool === "timeshift") return "sudo -S timeshift --create --comments '" + d + "' --scripted"
    return ""
}
// The first of the supported tools `command -v` found.
function snapshotTool(commandVOutput) {
    const t = String(commandVOutput || "")
    if (/(^|\/)snapper\s*$/m.test(t)) return "snapper"
    if (/(^|\/)timeshift\s*$/m.test(t)) return "timeshift"
    return ""
}

// ── Past upgrades: /var/log/pacman.log ────────────────────────────────────────
// Each transaction (started → completed) with what it upgraded, installed, removed or downgraded,
// newest first. The line before it, `[PACMAN] Running 'pacman -Syu'`, says what asked for it.
// Timestamps are `2026-10-12T21:03:11+0100`; QML's engine wants the offset as +01:00.
function _ts(s) {
    const t = new Date(String(s).replace(/([+-]\d\d)(\d\d)$/, "$1:$2")).getTime()
    return isFinite(t) ? t : 0
}

function parseHistory(text, max) {
    const out = []
    let cmd = "", cur = null
    String(text || "").split("\n").forEach(function (line) {
        const m = /^\[([^\]]+)\] \[(ALPM|PACMAN)\] (.*)$/.exec(line)
        if (!m) return
        const body = m[3]
        if (m[2] === "PACMAN") {
            const c = /^Running '(.*)'$/.exec(body)
            if (c) cmd = c[1]
            return
        }
        if (body === "transaction started") {
            cur = { when: _ts(m[1]), cmd: cmd, upgraded: [], installed: [], removed: [], downgraded: [] }
            return
        }
        if (body === "transaction completed" || body === "transaction failed") {
            if (cur && body === "transaction completed"
                    && cur.upgraded.length + cur.installed.length + cur.removed.length + cur.downgraded.length > 0)
                out.push(cur)
            cur = null
            return
        }
        if (!cur) return
        let r
        if ((r = /^(upgraded|downgraded) (\S+) \((\S+) -> (\S+)\)$/.exec(body)))
            cur[r[1]].push({ name: r[2], from: r[3], to: r[4] })
        else if ((r = /^(installed|reinstalled) (\S+) \((\S+)\)$/.exec(body)))
            cur.installed.push({ name: r[2], to: r[3] })
        else if ((r = /^removed (\S+) \((\S+)\)$/.exec(body)))
            cur.removed.push({ name: r[1], from: r[2] })
    })
    out.reverse()
    return out.slice(0, max > 0 ? max : 12).map(function (t) {
        // A full upgrade is the one worth naming; the rest are "pacman -S foo" and its kin.
        t.full = /(^|\s)(-\w*S\w*u|--sysupgrade)/.test(t.cmd) && /-\w*u|--sysupgrade/.test(t.cmd)
        t.count = t.upgraded.length + t.installed.length + t.removed.length + t.downgraded.length
        return t
    })
}

// The last `n` package changes across parseHistory's transactions (newest first), one row
// per package: [{ date: "YYYY-MM-DD" (local, as pacman logs it), action: "upgraded" |
// "downgraded" | "installed" | "removed", name, to }] — `to` is the version you have now
// (for a removal, the one that went). Settings › Updates' "recent changes" card.
function recentChanges(history, n) {
    function day(ms) {
        const d = new Date(ms)
        function p2(x) { return (x < 10 ? "0" : "") + x }
        return d.getFullYear() + "-" + p2(d.getMonth() + 1) + "-" + p2(d.getDate())
    }
    const out = []
    ;(history || []).forEach(function (t) {
        const date = day(t.when)
        ;["upgraded", "downgraded", "installed", "removed"].forEach(function (k) {
            ;(t[k] || []).forEach(function (e) {
                out.push({ date: date, action: k, name: e.name, to: k === "removed" ? e.from : e.to })
            })
        })
    })
    return out.slice(0, n > 0 ? n : 10)
}

// ── A package's details ───────────────────────────────────────────────────────
// `pacman -Si` / `-Qi`: "Key            : value", values that wrap carry on with leading spaces.
function parsePacmanInfo(text) {
    const f = {}
    let key = ""
    String(text || "").split("\n").forEach(function (line) {
        const m = /^([A-Za-z][A-Za-z ]*?)\s*:\s(.*)$/.exec(line)
        if (m) { key = m[1]; f[key] = m[2].trim() }
        else if (key && /^\s+\S/.test(line)) f[key] += " " + line.trim()
    })
    return f
}
// The script prints the repo's version of the package, a marker, then the installed one.
function splitInfo(text) {
    const parts = String(text || "").split("__INSTALLED__")
    return { next: parsePacmanInfo(parts[0]), old: parsePacmanInfo(parts[1] || "") }
}

// What the card shows, as rows: { label, value, link?, tone? } (tone "warn" for what you should read twice).
function officialLines(next, old, downloadBytes) {
    const rows = []
    const v = function (k) { return next && next[k] && next[k] !== "None" ? next[k] : "" }
    if (v("Description")) rows.push({ label: "About", value: v("Description") })
    if (v("URL")) rows.push({ label: "Upstream", value: v("URL"), link: v("URL") })
    if (v("Repository")) rows.push({ label: "Repository", value: v("Repository") + (v("Packager") ? "  ·  " + v("Packager").replace(/\s*<.*>$/, "") : "") })
    const dl = isFinite(downloadBytes) && downloadBytes >= 0 ? downloadBytes : parseSizeText(v("Download Size"))
    if (isFinite(dl)) rows.push({ label: "Download", value: formatBytes(dl) })
    const ni = parseSizeText(v("Installed Size")), oi = parseSizeText(old && old["Installed Size"])
    if (isFinite(ni))
        rows.push({ label: "Installed", value: formatBytes(ni) + (isFinite(oi) ? "  (" + signedBytes(ni - oi) + ")" : "") })
    if (v("Build Date")) rows.push({ label: "Built", value: v("Build Date") })
    return rows
}

// The AUR's RPC answer for one package: its `results[0]`.
function aurLines(r) {
    if (!r) return []
    const rows = []
    const day = function (s) {
        const d = new Date(s * 1000)
        return d.getUTCFullYear() + "-" + ("0" + (d.getUTCMonth() + 1)).slice(-2) + "-" + ("0" + d.getUTCDate()).slice(-2)
    }
    if (r.Description) rows.push({ label: "About", value: r.Description })
    if (r.URL) rows.push({ label: "Upstream", value: r.URL, link: r.URL })
    rows.push({ label: "Maintainer", value: r.Maintainer || "none — orphaned", tone: r.Maintainer ? "" : "warn" })
    if (isFinite(r.NumVotes)) rows.push({ label: "Votes", value: r.NumVotes + (isFinite(r.Popularity) ? "  ·  popularity " + (+r.Popularity).toFixed(2) : "") })
    if (r.OutOfDate) rows.push({ label: "Flagged", value: "out of date since " + day(r.OutOfDate), tone: "warn" })
    if (r.LastModified) rows.push({ label: "Updated", value: day(r.LastModified) })
    return rows
}

// A flatpak update has little to say that flatpak will tell without a network round trip per app.
function flatpakLines(installedVersion, downloadBytes) {
    const rows = []
    if (installedVersion) rows.push({ label: "Installed", value: installedVersion })
    if (isFinite(downloadBytes)) rows.push({ label: "Download", value: formatBytes(downloadBytes) })
    return rows
}

// ── Why a run failed ──────────────────────────────────────────────────────────
// A non-zero exit says THAT it failed; the receipt used to stop there. This reads the run's own
// lines for the causes that are not the shell's to fix and names the fix. "" = nothing recognised,
// so the panel keeps its generic "the log has the detail". First match wins, most specific first.
function failureHint(lines) {
    const t = (lines || []).join("\n")
    // A mirror serving a database newer than the files it holds (or another mirror behind it): the
    // sync db names versions the mirrors 404 on. The pacman error is "failed retrieving file … 404".
    if (/failed retrieving file .*returned error: 404/.test(t))
        return "Your mirrors are out of sync (404 on files they should have). Put an up-to-date mirror first in /etc/pacman.d/mirrorlist, then try again."
    if (/failed retrieving file/.test(t) || /could not resolve host/i.test(t))
        return "Couldn't download from the mirrors. Check the network connection, or the mirrors in /etc/pacman.d/mirrorlist."
    if (/unable to lock database/.test(t))
        return "Another package manager is running, or one crashed and left /var/lib/pacman/db.lck behind."
    if (/invalid or corrupted package \(PGP signature\)|unknown trust|key .* could not be looked up/i.test(t))
        return "A package signature didn't verify. Refreshing the keyring (sudo pacman -S archlinux-keyring) usually fixes it."
    return ""
}
