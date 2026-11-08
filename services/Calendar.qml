pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "ics.js" as Ics
import "holidays.js" as H

// ── Calendar ──────────────────────────────────────────────────────────────────
// What the clock panel's Calendar page shows, from two places:
//
//   · SPECIAL DATES — public holidays, regional holidays and observances for the
//     country of the weather location (Config.weatherCountry), from Nager.Date,
//     classified by holidays.js (tested by scripts/test-holidays.js).
//   · YOUR EVENTS — created in the panel, kept in a real .ics file at
//     Quickshell.dataPath("calendar.ics"), so it opens in any other calendar app.
//     The format — parsing, recurrence, writing, validating editor input — is ics.js
//     (tested by scripts/test-ics.js).
//
// ── Why the weather location's country, not the locale ────────────────────────
// A locale names a LANGUAGE's country. This machine runs en_US in Portugal, and
// the locale lookup the overview card used would show US holidays there. The
// weather location is where you actually are; Weather.backfillCountry() fills the
// code in once for a place picked before it was saved.
//
// ── Subscribed calendars ──────────────────────────────────────────────────────
// A third source: any number of .ics URLs (Config.calendarFeeds), fetched with curl, read-only.
// Each feed's events carry their feed's id as `source`, so the month's dots and the agenda's
// icons wear that feed's colour (a palette ROLE, never a hex — the panel resolves it against its
// own screen's palette) and the editor can tell yours from theirs. Fetched one at a time (a
// single Process), on first use, then every 30 minutes while the panel holds the service. A feed
// that fails keeps what it last had and says so; nothing here ever writes to a feed.
//
// The URL is a curl ARGUMENT after `--` and under `--proto =http,https` — never shell text — and
// is never logged (a Google "secret address" is a password). It lives in config.json, in the
// state dir, which is not in the repo.
//
// ── Your events file must never be lost ───────────────────────────────────────
//   · Writes are atomic (write-then-rename), so a crash mid-save leaves the old
//     file whole, never half of the new one.
//   · A file that exists but can't be read — permission denied, not a regular file,
//     not an iCalendar document — is marked `localWritable: false` and is NEVER
//     overwritten. Only a genuinely missing file (first run) starts empty; saving
//     into an unreadable one would replace whatever it held with just the new event.
//   · A failed save keeps the events in memory and says so, rather than pretending.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ══ Special dates ═════════════════════════════════════════════════════════
    // Checked here because it's spliced into a URL: two letters or nothing.
    readonly property string country: /^[A-Za-z]{2}$/.test(Config.weatherCountry || "")
                                      ? Config.weatherCountry.toUpperCase() : ""

    property var    special: ({})        // "Y-M-D" (unpadded) → [{ name, english, kind }]
    property string specialError: ""
    property var    _years: ({})         // year → true once requested
    property int    _inflight: 0

    // The panel's refresh glyph turns while this is true.
    readonly property bool loading: root._inflight > 0 || root._fetching !== ""

    // Asks again for this year and next. What's on screen stays until the new
    // answer replaces it, so a refresh never blanks the grid.
    function refresh() {
        root._years = ({})
        root._ensureAround()
        root._enqueueStale(true)
    }

    function specialOn(y, m, d) { return root.special[H.key(y, m + 1, d)] || [] }

    // The overview card's shape: just the strongest name.
    function holidayFor(y, m, d) {
        const e = root.specialOn(y, m, d)
        return e.length ? e[0].name : ""
    }

    // The next special date from today, up to a year and a bit ahead.
    readonly property var nextSpecial: {
        Clock.dayStamp
        const n = new Date()
        return H.next(root.special, new Date(n.getFullYear(), n.getMonth(), n.getDate()).getTime(), 400)
    }

    // A move abroad must not keep the old country's days on screen.
    onCountryChanged: {
        root.special = ({})
        root._years = ({})
        root.specialError = ""
        if (root._refs > 0) root._ensureAround()
    }

    function _ensureAround() {
        const y = new Date().getFullYear()
        root.ensureHolidays(y)
        root.ensureHolidays(y + 1)
    }

    // Each year is requested at most once per country, and only while something
    // showing the calendar is on screen asks for it.
    function ensureHolidays(year) {
        if (root.country === "" || !(year >= 1975 && year <= 2100) || root._years[year]) return
        root._years[year] = true
        const country = root.country

        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            // Counted down first, so a request made stale by a move still settles.
            root._inflight = Math.max(0, root._inflight - 1)
            // The location moved while this was in flight: it answers the wrong question.
            if (country !== root.country) return
            // 204: a supported country with nothing that year. Not an error.
            if (xhr.status === 204) return
            if (xhr.status !== 200) {
                // Quiet, not silent: a failed fetch shouldn't look like a year with no
                // holidays, and it's retried next time the page asks.
                delete root._years[year]
                root.specialError = "Couldn't load special dates"
                console.warn("Calendar: special dates for", country, year, "failed — status", xhr.status)
                return
            }
            try {
                const add = H.classify(JSON.parse(xhr.responseText))
                const merged = Object.assign({}, root.special)
                for (const k in add) merged[k] = add[k]
                root.special = merged
                root.specialError = ""
            } catch (e) {
                delete root._years[year]
                console.warn("Calendar: could not read special dates —", e)
            }
        }
        xhr.open("GET", "https://date.nager.at/api/v3/PublicHolidays/" + year + "/" + country)
        root._inflight++
        xhr.send()
    }

    // ══ Your events ═══════════════════════════════════════════════════════════
    readonly property string localPath: Quickshell.dataPath("calendar.ics")

    property var    localEvents:   []
    property bool   localReady:    false
    property bool   localWritable: true
    property string localError:    ""

    FileView {
        id: localFile
        path: root.localPath
        preload: true
        watchChanges: true
        atomicWrites: true
        // A missing file is the first-run state, not something to log.
        printErrors: false
        onFileChanged: reload()

        onLoaded: {
            const text = localFile.text()
            if (text.trim() !== "" && text.indexOf("BEGIN:VCALENDAR") < 0) {
                root._lockLocal("calendar.ics isn't a calendar file — it's been left untouched")
                return
            }
            root.localEvents = Ics.parse(text).map(e => Object.assign(e, { source: "local" }))
            root.localWritable = true
            root.localError = ""
            root.localReady = true
            root._expand()
        }
        onLoadFailed: function (error) {
            if (error === FileViewError.FileNotFound) {
                root.localEvents = []
                root.localWritable = true
                root.localError = ""
                root.localReady = true
                root._expand()
            } else {
                root._lockLocal("calendar.ics couldn't be read (" + FileViewError.toString(error)
                                + ") — it's been left untouched")
            }
        }
        onSaveFailed: function (error) {
            // The events are still in memory; the next successful save writes them.
            root.localError = "Couldn't save your events (" + FileViewError.toString(error) + ")"
            console.warn("Calendar: saving", root.localPath, "failed —", FileViewError.toString(error))
        }
        onSaved: root.localError = ""
    }

    function _lockLocal(msg) {
        root.localWritable = false
        root.localReady = true
        root.localError = msg
        console.warn("Calendar:", msg)
    }

    // One of your events by UID, for the editor to prefill. null for anything else.
    function localEvent(uid) { return root.localEvents.find(e => e.uid === uid) ?? null }

    // draft → "" on success, or the reason, worded for the editor to show.
    // Editing a repeating event edits the whole series.
    function saveLocal(draft) {
        if (!root.localWritable) return root.localError
        const v = Ics.validateEvent(draft)
        if (!v.ok) return v.error
        const ev = v.event
        if (!ev.uid) ev.uid = Ics.newUid(Date.now(), Math.random().toString(36).slice(2, 10))
        root.localEvents = root.localEvents.filter(e => e.uid !== ev.uid).concat([ev])
        root._writeLocal()
        return ""
    }

    function deleteLocal(uid) {
        if (!root.localWritable) return root.localError
        root.localEvents = root.localEvents.filter(e => e.uid !== uid)
        root._writeLocal()
        return ""
    }

    function _writeLocal() {
        localFile.setText(Ics.serialize(root.localEvents, Date.now()))
        root._expand()
    }


    // ══ Subscribed calendars ══════════════════════════════════════════════════
    readonly property var feeds: (Config.calendarFeeds || []).filter(f => f && f.id && f.url)
    property var feedEvents: ({})     // id → [event]
    property var feedState:  ({})     // id → { state: "loading" | "ok" | "error", count, at }
    property var _queue: []
    property string _fetching: ""

    // The palette roles a feed can wear, in the order new ones take them. role() in PaletteRoles
    // knows exactly these (and "focus", which is what your own events default to).
    readonly property var feedRoles: ["ramp5", "ramp9", "ramp3", "ramp2", "primary"]

    function _feed(id) { return root.feeds.find(f => f.id === id) ?? null }
    // The role name for a source — "" for yours, or a feed that has since been removed — which the
    // panel resolves against ITS screen's palette.
    function feedRole(source) { const f = root._feed(source); return f ? f.color : "" }
    function feedName(source) { const f = root._feed(source); return f ? f.name : "" }
    function stateOf(id) { return root.feedState[id] ?? { state: "idle", count: 0, at: 0 } }

    // → "" on success, or why not.
    function addFeed(name, rawUrl) {
        const u = Ics.feedUrl(rawUrl)
        if (!u.ok) return u.error
        if (root.feeds.some(f => f.url === u.url)) return "That calendar is already added"
        if (root.feeds.length >= 12) return "That's plenty of calendars — remove one first"
        const id = "f" + Date.now().toString(36) + Math.random().toString(36).slice(2, 5)
        const label = String(name || "").trim() || u.url.replace(/^https?:\/\//, "").split("/")[0]
        Config.calendarFeeds = root.feeds.concat([{ id: id, name: label.slice(0, 40), url: u.url,
                                                     color: root.feedRoles[root.feeds.length % root.feedRoles.length] }])
        return ""
    }
    function removeFeed(id) { Config.calendarFeeds = root.feeds.filter(f => f.id !== id) }
    function setFeedColor(id, role) {
        Config.calendarFeeds = root.feeds.map(f => f.id === id ? Object.assign({}, f, { color: role }) : f)
    }

    // Everything gone from the list leaves with it; anything new is fetched (if something is looking).
    onFeedsChanged: {
        const keep = {}
        let changed = false
        for (const f of root.feeds) if (root.feedEvents[f.id]) keep[f.id] = root.feedEvents[f.id]
        for (const id in root.feedEvents) if (!keep[id]) changed = true
        if (changed) { root.feedEvents = keep; root._expand() }
        if (root._refs > 0) root._enqueueStale()
    }

    // Feeds never fetched, or last fetched over `refreshMins` ago — or all of them, when `force`.
    readonly property int feedRefreshMins: 30
    function _enqueueStale(force) {
        const cutoff = Date.now() - root.feedRefreshMins * 60000
        for (const f of root.feeds)
            if ((force || root.stateOf(f.id).at < cutoff) && root._queue.indexOf(f.id) < 0 && root._fetching !== f.id)
                root._queue = root._queue.concat([f.id])
        root._pump()
    }
    function _pump() {
        if (feedFetch.running || root._queue.length === 0) return
        const id = root._queue[0]
        root._queue = root._queue.slice(1)
        const f = root._feed(id)
        if (!f) { root._pump(); return }
        root._fetching = id
        root._setState(id, { state: "loading" })
        feedFetch.command = ["curl", "-fsSL", "--max-time", "25", "--max-filesize", "8000000", "--compressed",
                             "--proto", "=http,https", "--proto-redir", "=http,https", "--", f.url]
        feedFetch.running = true
    }
    function _setState(id, patch) {
        const next = Object.assign({}, root.feedState)
        next[id] = Object.assign({}, root.stateOf(id), patch)
        root.feedState = next
    }

    Process {
        id: feedFetch
        stdout: StdioCollector { id: feedOut }
        onExited: function (exitCode) {
            const id = root._fetching
            root._fetching = ""
            // Removed while it was in flight: nothing to record.
            if (root._feed(id)) {
                const text = feedOut.text
                if (exitCode !== 0) {
                    // Nothing about the URL goes to the log — it may be a secret address.
                    root._setState(id, { state: "error", at: Date.now() })
                    console.warn("Calendar: a subscribed calendar couldn't be fetched (curl", exitCode + ")")
                } else if (text.indexOf("BEGIN:VCALENDAR") < 0) {
                    root._setState(id, { state: "error", at: Date.now() })
                    console.warn("Calendar: a subscribed calendar didn't return an iCalendar file")
                } else {
                    const evs = Ics.parse(text).map(e => Object.assign(e, { source: id }))
                    const next = Object.assign({}, root.feedEvents)
                    next[id] = evs
                    root.feedEvents = next
                    root._setState(id, { state: "ok", count: evs.length, at: Date.now() })
                    root._expand()
                }
            }
            root._pump()
        }
    }

    Timer {
        interval: root.feedRefreshMins * 60000
        repeat: true
        running: root._refs > 0 && root.feeds.length > 0
        onTriggered: root._enqueueStale(false)
    }

    // The first feed to have failed, for the panel's one-line message.
    readonly property string feedError: {
        for (const f of root.feeds) if (root.stateOf(f.id).state === "error") return "Couldn't reach " + f.name
        return ""
    }

    // ══ What the panel reads ══════════════════════════════════════════════════
    readonly property bool   ready:     root.localReady
    readonly property bool   hasEvents: root.localEvents.length > 0
    readonly property string error:     root.localError !== "" ? root.localError
                                      : root.specialError !== "" ? root.specialError : root.feedError

    // Expanded once per change (and at midnight) over two years back to two ahead —
    // the span the month scroller can reach.
    property var occurrences: []
    property var counts:      ({})   // "YYYY-MM-DD" → n
    property var sources:     ({})   // "YYYY-MM-DD" → [source, …], at most three — the month's dots

    function eventsOn(y, m, d) { return Ics.onDay(root.occurrences, y, m, d) }
    function countOn(y, m, d)  { return root.counts[Ics.dayKey(new Date(y, m, d).getTime())] || 0 }
    function sourcesOn(y, m, d) { return root.sources[Ics.dayKey(new Date(y, m, d).getTime())] || [] }

    function _expand() {
        const now = new Date()
        const from = new Date(now.getFullYear() - 2, now.getMonth(), 1).getTime()
        const to   = new Date(now.getFullYear() + 2, now.getMonth() + 1, 1).getTime()
        // Yours and every subscribed feed's, expanded together: a series is keyed by source as well as
        // UID, so two feeds carrying the same event stay two.
        let all = root.localEvents
        for (const id in root.feedEvents) all = all.concat(root.feedEvents[id])
        root.occurrences = Ics.expand(all, from, to)
        root.counts      = Ics.dayCounts(root.occurrences)
        root.sources     = Ics.daySources(root.occurrences, 3)
    }

    Connections {
        target: Clock
        function onDayStampChanged() { root._expand() }
    }

    // ── Refcount ──────────────────────────────────────────────────────────────
    // Nothing is requested until something showing the calendar is on screen.
    property int _refs: 0
    function acquire() {
        root._refs++
        if (root._refs === 1) {
            Weather.backfillCountry()
            root._ensureAround()
            root._enqueueStale(false)
        }
    }
    function release() {
        root._refs = Math.max(0, root._refs - 1)
    }
}
