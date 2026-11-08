pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

// ── News ──────────────────────────────────────────────────────────────────────
// Headlines for the overview's News page (OverviewFeed → FeedNews). scripts/news-fetch.py
// does the fetching, the parsing and the cache; this holds the answer and decides the
// edition.
//
// ── Only when looked at ───────────────────────────────────────────────────────
// Nothing here runs on a timer. The page calls `want()` when it comes into view; the script
// answers from its cache while that is under 20 minutes old, so flicking past the page costs
// a file read, not a request. A topic or country change refetches only if the page is up.
//
// ── Where "near you" is ───────────────────────────────────────────────────────
// Config.newsCountry when set; else the country of the weather location you picked
// (Config.weatherCountry); else the system locale's. Never an IP lookup.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // "Near you" and "World" are the two the page is about (the user: geolocated or overall);
    // three more for when you want one subject.
    readonly property var topics: [
        { id: "local",      symbol: "location_on",    label: "Near you" },
        { id: "world",      symbol: "public",         label: "World" },
        { id: "technology", symbol: "computer",       label: "Tech" },
        { id: "science",    symbol: "science",        label: "Science" },
        { id: "sports",     symbol: "sports_esports", label: "Sport" }
    ]
    readonly property string topic: root.topics.some(t => t.id === Config.newsTopic) ? Config.newsTopic : "local"
    readonly property string topicLabel: (root.topics.find(t => t.id === root.topic) ?? root.topics[0]).label

    readonly property string _localeCC: {
        const m = /_([A-Z]{2})/.exec(Qt.locale().name)
        return m ? m[1] : ""
    }
    readonly property string country: /^[A-Za-z]{2}$/.test(Config.newsCountry) ? Config.newsCountry.toUpperCase()
                                     : /^[A-Z]{2}$/.test(Config.weatherCountry ?? "") ? Config.weatherCountry
                                     : root._localeCC !== "" ? root._localeCC : "US"
    // Where the country came from, for the page to say.
    readonly property string countryFrom: /^[A-Za-z]{2}$/.test(Config.newsCountry) ? "chosen"
                                        : /^[A-Z]{2}$/.test(Config.weatherCountry ?? "") ? "weather" : "locale"

    property var items: []
    property bool busy: false
    property string error: ""
    property bool stale: false
    property real fetched: 0
    // The page is in view (set by want/unwant): only then does a change refetch.
    property bool _wanted: false

    function want() { root._wanted = true; root.refresh(false) }
    function unwant() { root._wanted = false }

    // A change while a fetch is out: run again when it lands, for the new edition/topic.
    property bool _again: false

    function refresh(force) {
        if (proc.running) { root._again = true; return }
        proc.command = ["python3", Quickshell.shellPath("scripts/news-fetch.py"),
                        "--country", root.country, "--topic", root.topic,
                        "--max-age", "1200"].concat(force ? ["--force"] : [])
        root.busy = true
        proc.running = true
    }

    function setTopic(id) { Config.newsTopic = id }

    // "12 min", "3 h", "2 d" — how old a story is (`time` is epoch seconds; 0 = unknown).
    function ago(t) {
        if (!t) return ""
        const s = Math.max(0, Date.now() / 1000 - t)
        if (s < 60) return "now"
        if (s < 3600) return Math.floor(s / 60) + " min"
        if (s < 86400) return Math.floor(s / 3600) + " h"
        return Math.floor(s / 86400) + " d"
    }

    // Opens a story in the browser — at the publisher's own address when the picture pass found it
    // (`real`), else Google's link. The overview leaves as it does (the page asks UiState).
    function open(story) {
        const real = story ? (root.pictures[story.url]?.real ?? "") : ""
        const url = /^https?:\/\//.test(real) ? real : (story?.url ?? "")
        if (/^https?:\/\//.test(url)) Qt.openUrlExternally(url)
    }

    // ── Pictures ──────────────────────────────────────────────────────────────
    // A second pass once the headlines are in (news-fetch.py --images): the top stories' pictures,
    // cached by the script for good, so a list seen before fills in at once. Kept BESIDE `items`,
    // keyed by the story's link: reassigning `items` would rebuild the page's list and throw it back
    // to the top under the reader. A story without one keeps its text card.
    property var pictures: ({})
    function pictureOf(url) { return root.pictures[url]?.image ?? "" }
    function _pictures() {
        if (!Config.newsImages || picProc.running || root.items.length === 0) return
        picProc.command = ["python3", Quickshell.shellPath("scripts/news-fetch.py"),
                           "--images", "12", "--country", root.country, "--topic", root.topic]
        picProc.running = true
    }
    Process {
        id: picProc
        stdout: StdioCollector {
            onStreamFinished: {
                let pics = null
                try { pics = JSON.parse(text).images } catch (e) { return }
                if (!pics) return
                const next = Object.assign({}, root.pictures)
                for (const k in pics)
                    next[k] = { image: /^https:\/\//.test(pics[k].image ?? "") ? pics[k].image : "", real: pics[k].url || "" }
                root.pictures = next
            }
        }
    }

    onTopicChanged:   if (root._wanted) { root.items = []; root.refresh(false) }
    onCountryChanged: if (root._wanted) { root.items = []; root.refresh(false) }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    root.items = Array.isArray(d.items) ? d.items : []
                    root.error = d.ok ? "" : (d.error || "couldn't fetch the news")
                    root.stale = !!d.stale
                    root.fetched = d.fetched || 0
                } catch (e) {
                    root.error = "couldn't read the news"
                }
            }
        }
        onExited: {
            root.busy = false
            if (root._again) { root._again = false; root.refresh(false) }
            else root._pictures()
        }
    }
}
