.pragma library

// ── shellupdate.js ────────────────────────────────────────────────────────────
// The pure half of services/ShellUpdate: which GitHub release is newer than the
// running shell, and what the release says about itself. No I/O — the service
// fetches, this decides. scripts/test-shellupdate.js pins it.
//
// Versions are dotted integers ("0.3", "0.4.1"), tags are the same with a "v".
// Anything else (a "-rc1", a branch name) is NOT a version this shell offers:
// `parse` returns null and `newer` says no, so a stray tag can never be pushed to
// users as an update.
// ─────────────────────────────────────────────────────────────────────────────

function parse(v) {
    const m = String(v ?? "").trim().replace(/^v/i, "").match(/^\d+(?:\.\d+){0,3}$/)
    return m ? m[0].split(".").map(n => parseInt(n, 10)) : null
}

// a < b, segment by segment; a missing segment is 0 ("0.4" == "0.4.0").
function newer(candidate, current) {
    const a = parse(candidate), b = parse(current)
    if (!a || !b) return false
    for (let i = 0; i < Math.max(a.length, b.length); i++) {
        const x = a[i] ?? 0, y = b[i] ?? 0
        if (x !== y) return x > y
    }
    return false
}

// GitHub's /releases/latest JSON → the fields the UI shows, or null when the
// document isn't a usable release (rate-limit error body, a draft, a bad tag,
// a release missing the signed assets the installer needs).
const ASSETS = ["quicktest.tar.xz", "SHA256SUMS", "SHA256SUMS.sig"]

function release(text) {
    let d
    try { d = JSON.parse(text) } catch (e) { return null }
    if (!d || typeof d !== "object" || d.draft || d.prerelease) return null
    const tag = String(d.tag_name ?? "")
    if (!parse(tag)) return null
    const names = (Array.isArray(d.assets) ? d.assets : []).map(a => a && a.name)
    if (ASSETS.some(n => names.indexOf(n) < 0)) return null
    return {
        tag:     tag,
        version: tag.replace(/^v/i, ""),
        notes:   String(d.body ?? "").replace(/\r\n/g, "\n").trim(),
        url:     String(d.html_url ?? ""),
        date:    String(d.published_at ?? "").slice(0, 10)
    }
}
