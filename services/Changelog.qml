pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "shellupdate.js" as SU

// ── Changelog ─────────────────────────────────────────────────────────────────
// The patch notes, for the overview's "What's changed" page (FeedChanges). They live in
// assets/changelog.json — data, newest version first, one entry per release, checked by
// `bun scripts/test-changelog.js` — so a release adds an entry and no QML changes.
//
// "Since the version you last had": Config.changelogSeen is the newest version whose notes you've
// seen; every version after it is `unseen` and wears "New". The page calls markSeen() after it has
// been looked at for a moment, not on a swipe past.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property var versions: []
    readonly property var latest: root.versions.length > 0 ? root.versions[0] : null

    function isNew(v) { return Config.changelogSeen === "" || SU.newer(v, Config.changelogSeen) }
    readonly property int unseen: root.versions.filter(v => root.isNew(v.version)).length

    function markSeen() {
        if (root.latest && Config.changelogSeen !== root.latest.version) Config.changelogSeen = root.latest.version
    }

    // "2026-10" → "October 2026"; "2026-07-26" → "26 July 2026".
    function dateLabel(d) {
        const m = /^(\d{4})-(\d{2})(?:-(\d{2}))?$/.exec(d || "")
        if (!m) return ""
        const month = Qt.locale().standaloneMonthName(Number(m[2]) - 1, Locale.LongFormat)
        return (m[3] ? Number(m[3]) + " " : "") + month + " " + m[1]
    }

    FileView {
        path: Quickshell.shellPath("assets/changelog.json")
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text())
                root.versions = Array.isArray(d.versions) ? d.versions : []
            } catch (e) {
                console.warn("Changelog: assets/changelog.json didn't parse —", e)
                root.versions = []
            }
        }
    }
}
