.pragma library

// ── packages.js ───────────────────────────────────────────────────────────────
// The launcher's `+` mode (services/Packages): search the repos and the AUR, rank what
// comes back, and build the install for the update runner (services/Updates).
//
//     bun scripts/test-packages.js
//
// Pure. The QML side runs `pacman -Ss`, `pacman -Qq` and one AUR RPC request and
// hands their text here.
// ─────────────────────────────────────────────────────────────────────────────

var TERMS_MAX = 5
var TERM_LEN_MAX = 64
var NAMES_MAX = 20
var RESULTS_MAX = 40

// A pacman package name: lowercase alphanumerics and @ . _ + -, never starting with a
// hyphen or a dot (makepkg's rule). Everything that reaches an install command passes
// this — the names come from search output, but output is still input.
var NAME_OK = /^[a-z0-9@_+][a-z0-9@._+-]{0,127}$/

function validName(n) { return typeof n === "string" && NAME_OK.test(n) }

// ── The query → pacman's arguments ────────────────────────────────────────────
// `pacman -Ss` takes each argument as a REGEX and ANDs them. What you typed is text,
// so every metacharacter is escaped — "c++" must not be a broken pattern. Terms under
// two characters are dropped (one letter matches the whole database).
function escapeRegex(s) { return String(s).replace(/[\\^$.*+?()[\]{}|]/g, "\\$&") }

function terms(query) {
    var out = []
    var parts = String(query || "").trim().toLowerCase().split(/\s+/)
    for (var i = 0; i < parts.length && out.length < TERMS_MAX; i++) {
        var t = parts[i].slice(0, TERM_LEN_MAX)
        if (t.length >= 2 && out.indexOf(t) < 0) out.push(t)
    }
    return out
}

function pacmanArgs(query) {
    var ts = terms(query)
    if (ts.length === 0) return []
    return ["pacman", "-Ss", "--"].concat(ts.map(escapeRegex))
}

// The AUR's RPC searches ONE term: the longest, as the most specific. The rest are
// applied here afterwards (rank's AND).
function aurTerm(query) {
    var ts = terms(query)
    if (ts.length === 0) return ""
    var best = ts[0]
    for (var i = 1; i < ts.length; i++) if (ts[i].length > best.length) best = ts[i]
    return best
}

function aurUrl(query) {
    var t = aurTerm(query)
    return t === "" ? "" : "https://aur.archlinux.org/rpc/v5/search/" + encodeURIComponent(t) + "?by=name-desc"
}

// ── Parsing ───────────────────────────────────────────────────────────────────
//   extra/firefox 131.0-1 [installed]
//       Fast, Private & Safe Web Browser
//   core/linux 6.11.1.arch1-1 (base) [installed: 6.10.9.arch1-1]
function parsePacman(text) {
    var out = []
    var lines = String(text || "").split("\n")
    var head = /^([a-z0-9][a-z0-9._-]*)\/(\S+) (\S+)(?: \(([^)]*)\))?(?: \[installed(?:: ([^\]]+))?\])?\s*$/
    for (var i = 0; i < lines.length; i++) {
        var m = head.exec(lines[i])
        if (!m || !validName(m[2])) continue
        var desc = (i + 1 < lines.length && /^\s+/.test(lines[i + 1])) ? lines[i + 1].trim() : ""
        out.push({
            source: "repo", repo: m[1], name: m[2], version: m[3],
            description: desc,
            installed: lines[i].indexOf("[installed") >= 0,
            popularity: 0, outOfDate: false
        })
    }
    return out
}

// The RPC's JSON (`{ results: [{ Name, Version, Description, Popularity, OutOfDate }] }`).
// Null on anything malformed, never a throw.
function parseAur(text) {
    var d
    try { d = JSON.parse(text) } catch (e) { return null }
    if (!d || d.type === "error" || !Array.isArray(d.results)) return null
    var out = []
    for (var i = 0; i < d.results.length; i++) {
        var r = d.results[i]
        if (!r || !validName(r.Name)) continue
        out.push({
            source: "aur", repo: "aur", name: r.Name,
            version: typeof r.Version === "string" ? r.Version : "",
            description: typeof r.Description === "string" ? r.Description : "",
            installed: false,
            popularity: typeof r.Popularity === "number" ? r.Popularity : 0,
            outOfDate: !!r.OutOfDate
        })
    }
    return out
}

// `pacman -Qq`: one installed name per line.
function parseInstalled(text) {
    var set = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
        var n = lines[i].trim()
        if (validName(n)) set[n] = true
    }
    return set
}

// ── Ranking ───────────────────────────────────────────────────────────────────
// What you typed as the NAME beats it in the description: the exact name, then a name
// that starts with it, then one containing it, then the description. Within a class the
// repos come before the AUR (official, signed, no build), the AUR by popularity, then by
// name. Every term must appear in the name or the description. A name in both the
// repos and the AUR keeps the repo's.
function rank(repo, aur, query, installed) {
    var ts = terms(query)
    if (ts.length === 0) return []
    var q = ts.join(" ")
    var seen = {}
    var rows = []
    var all = (repo || []).concat(aur || [])
    for (var i = 0; i < all.length; i++) {
        var p = all[i]
        if (seen[p.name]) continue
        var name = p.name.toLowerCase(), desc = (p.description || "").toLowerCase()
        var ok = true
        for (var k = 0; k < ts.length && ok; k++)
            ok = name.indexOf(ts[k]) >= 0 || desc.indexOf(ts[k]) >= 0
        if (!ok) continue
        seen[p.name] = true
        var cls = name === q || name === ts[0] ? 0
                : name.indexOf(ts[0]) === 0 ? 1
                : ts.every(function (t) { return name.indexOf(t) >= 0 }) ? 2 : 3
        rows.push({
            p: Object.assign({}, p, { installed: p.installed || !!(installed && installed[p.name]) }),
            cls: cls
        })
    }
    rows.sort(function (a, b) {
        if (a.cls !== b.cls) return a.cls - b.cls
        var sa = a.p.source === "repo" ? 0 : 1, sb = b.p.source === "repo" ? 0 : 1
        if (sa !== sb) return sa - sb
        if (a.p.popularity !== b.p.popularity) return b.p.popularity - a.p.popularity
        if (a.p.name.length !== b.p.name.length) return a.p.name.length - b.p.name.length
        return a.p.name < b.p.name ? -1 : a.p.name > b.p.name ? 1 : 0
    })
    return rows.slice(0, RESULTS_MAX).map(function (r) { return r.p })
}

// ── The install ───────────────────────────────────────────────────────────────
// One script for the update runner (update-run.sh, through Updates._launch): a sudo
// prime, then the repos' packages, then the AUR's through the helper — in numbered
// `:: [n/N]` phases, the protocol Updates' progress reads. `--needed`, so an
// installed package is left alone; `--noconfirm` for the reason the upgrade uses it (a
// conflict aborts cleanly rather than waiting on a prompt nobody owns). `pacman -S`
// WITHOUT `-y` is the safe single install: it uses the databases as they are, never a
// partial upgrade. "" when nothing valid is left, or the AUR is asked for with no helper.
function installScript(official, aur, helper) {
    var off = (official || []).filter(validName).slice(0, NAMES_MAX)
    var au = (aur || []).filter(validName).slice(0, NAMES_MAX)
    if (au.length > 0 && !/^(yay|paru)$/.test(helper || "")) au = []
    if (off.length === 0 && au.length === 0) return ""
    var phases = []
    if (off.length > 0) phases.push(["Official packages", "sudo -S pacman -S --needed --noconfirm " + off.join(" ")])
    if (au.length > 0) {
        var cmd = helper + " -S --needed --noconfirm " + au.join(" ")
        cmd += helper === "yay" ? " --answerdiff=None --answerclean=None --answeredit=None" : " --skipreview"
        phases.push(["AUR packages", cmd])
    }
    var steps = ["set -e", "sudo -S -v"]
    for (var i = 0; i < phases.length; i++) {
        steps.push('echo ":: [' + (i + 1) + "/" + phases.length + "] " + phases[i][0] + '"')
        steps.push(phases[i][1])
    }
    return steps.join("\n")
}
