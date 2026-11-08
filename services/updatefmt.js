.pragma library

// ── updatefmt.js ──────────────────────────────────────────────────────────────
// The words and judgements the update panel puts on its numbers: how big a jump a package is making,
// how long a run has left, when the list was last checked, where a package's page is, and which
// packages a search keeps. Pure functions, no QML — tested by `bun scripts/test-updatefmt.js`.
// ─────────────────────────────────────────────────────────────────────────────

// ── How big a jump ────────────────────────────────────────────────────────────
// Arch versions are `[epoch:]pkgver-pkgrel`. The first place two pkgvers differ says what kind of
// update this is:
//   epoch or the first number changes   "major"    (6.x → 7.x, 1.4 → 2.0)
//   the second                          "minor"    (6.11 → 6.12)
//   anything after                      "patch"    (6.12.1 → 6.12.2)
//   only the pkgrel                     "rebuild"  (same upstream, repackaged)
//   a VCS snapshot (r1234.abc, 20261012) "git"     (a number that means "newer", not "bigger")
//   no version on one side              "new"
// Judged on the numbers, never the letters: "arch1" → "arch2" is a patch, and a version that will not
// split comes back "unknown" rather than a guess.
function bump(from, to) {
    if (!to) return "unknown"
    if (!from) return "new"
    const a = _split(from), b = _split(to)
    if (!a || !b) return "unknown"
    if (a.epoch !== b.epoch) return "major"
    if (a.ver === b.ver) return a.rel !== b.rel ? "rebuild" : "unknown"
    if (_isSnapshot(a.ver) || _isSnapshot(b.ver)) return "git"
    const x = _nums(a.ver), y = _nums(b.ver)
    const n = Math.max(x.length, y.length)
    for (let i = 0; i < n; i++) {
        if ((x[i] || 0) !== (y[i] || 0)) return i === 0 ? "major" : i === 1 ? "minor" : "patch"
    }
    return "patch"      // same numbers, different letters (1.2.3a → 1.2.3b)
}

function _split(v) {
    const m = /^(?:(\d+):)?(.+?)(?:-([^-]+))?$/.exec(String(v))
    return m ? { epoch: m[1] || "0", ver: m[2], rel: m[3] || "" } : null
}
function _nums(ver) { return (ver.match(/\d+/g) || []).map(Number) }
// r1234.abcdef0, 20261012, 1.2.r45.gabc123: a revision count or a date, not a release.
function _isSnapshot(ver) { return /(^|[._])r\d+([._]|$)/.test(ver) || /^\d{8}(\D|$)/.test(ver) }

// Biggest first, for sorting a list so the jumps worth reading come to the top.
var BUMP_RANK = { major: 0, minor: 1, patch: 2, git: 3, new: 3, rebuild: 4, unknown: 5 }
function bumpRank(kind) { return BUMP_RANK[kind] !== undefined ? BUMP_RANK[kind] : 5 }

// ── How long is left ──────────────────────────────────────────────────────────
// A guess, and worded as one: progress through an upgrade is lumpy (downloads, then a long
// install, then hooks), so it only speaks once there is something to extrapolate from — a fifth of
// the way and 20 seconds in — and never past two hours.
function etaText(elapsedSecs, progress) {
    if (!(elapsedSecs >= 20) || !(progress >= 0.2) || progress >= 1) return ""
    const left = elapsedSecs * (1 - progress) / progress
    if (left > 7200) return ""
    if (left < 60) return "under a minute left"
    const m = Math.round(left / 60)
    return "about " + m + (m === 1 ? " minute" : " minutes") + " left"
}

// "3 min ago" for a check that finished at `atMs` (0 = never).
function agoText(atMs, nowMs) {
    if (!(atMs > 0)) return ""
    const mins = Math.floor((nowMs - atMs) / 60000)
    if (mins < 1) return "just now"
    if (mins < 60) return mins + " min ago"
    const h = Math.floor(mins / 60)
    return h < 24 ? h + " h ago" : Math.floor(h / 24) + " d ago"
}

// ── Where a package lives ─────────────────────────────────────────────────────
// A page to read before updating — its changelog, bug reports, the flags other people raised.
// Official packages go to the search (a package can sit in core, extra or multilib and the search
// finds it in all); the name is encoded, since an AUR or Flatpak id can carry anything.
function pkgUrl(pkg) {
    if (!pkg || !pkg.name) return ""
    const n = encodeURIComponent(pkg.name)
    if (pkg.source === "aur") return "https://aur.archlinux.org/packages/" + n
    if (pkg.source === "flatpak") return "https://flathub.org/apps/" + n
    return "https://archlinux.org/packages/?q=" + n
}

// ── A search ──────────────────────────────────────────────────────────────────
// Every word typed must appear in the name, in any order and any case ("lib ssl" finds openssl-libs).
function matches(pkg, query) {
    const words = String(query || "").toLowerCase().split(/\s+/).filter(function (w) { return w !== "" })
    if (words.length === 0) return true
    const name = String((pkg && pkg.name) || "").toLowerCase()
    return words.every(function (w) { return name.indexOf(w) >= 0 })
}

// ── Quiet hours ───────────────────────────────────────────────────────────────
// The automatic check does not run between two times of day (23:00 → 07:00): no network or disk wake-up
// while you are asleep or in a meeting. A window that crosses midnight is the usual case, so "from"
// later than "to" wraps. Equal times mean no window at all — an empty one, not a whole day.
function _hhmm(s) {
    const m = /^\s*(\d{1,2}):(\d{2})\s*$/.exec(String(s === undefined || s === null ? "" : s))
    if (!m) return NaN
    const h = parseInt(m[1], 10), n = parseInt(m[2], 10)
    return h <= 23 && n <= 59 ? h * 60 + n : NaN
}
// A typed time as "HH:MM", or "" if it isn't one ("7:5" is not; "7:05" is "07:05").
function cleanTime(s) {
    const t = _hhmm(s)
    return isNaN(t) ? "" : ("0" + Math.floor(t / 60)).slice(-2) + ":" + ("0" + (t % 60)).slice(-2)
}
function inQuiet(nowMinutes, from, to) {
    const a = _hhmm(from), b = _hhmm(to)
    if (isNaN(a) || isNaN(b) || a === b || !isFinite(nowMinutes)) return false
    return a < b ? (nowMinutes >= a && nowMinutes < b) : (nowMinutes >= a || nowMinutes < b)
}
