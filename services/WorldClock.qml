pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "worldclock.js" as Z

// ── WorldClock ────────────────────────────────────────────────────────────────
// The clock panel's world clocks: a list of IANA zones (Config.worldClocks), and what time it is
// in each. QML's JavaScript has no time zones, so the system is asked ONCE for each zone's offset and
// name (`date`, with TZ set per zone) and everything after is arithmetic (worldclock.js, tested).
// Offsets are re-read every 15 minutes while something holds the service, which is how a
// daylight-saving change in any of them is picked up within a quarter hour.
//
// ── Nothing here is built from typed text ─────────────────────────────────────
// A zone is only ever taken from `timedatectl list-timezones` (so it exists) and checked against
// Z.validZone before it is stored, and it reaches `date` as a positional ARGUMENT to a fixed
// script, never inside a command string.
//
// Same refcount contract as Weather: acquire() while a page shows it, release() when it goes. The
// zone LIST (about 600 names) is only fetched when someone starts to search it.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property int maxZones: 8
    readonly property var zones: (Config.worldClocks || []).filter(z => Z.validZone(z))

    // zone → { off: minutes east of UTC, abbr }
    property var info: ({})
    property string localZone: ""
    property var allZones: []
    property bool listing: false

    // ── What a row reads ──────────────────────────────────────────────────────
    // A function of the zone and the instant — now, or `atMs` when the planner is scrubbed to
    // another one — re-read each minute (Clock.minutes). So a Repeater over `zones` keeps its
    // delegates and each one updates its own text; a model rebuilt each minute would replay every
    // row's entrance.
    function reading(zone, atMs) {
        Clock.minutes
        const i = root.info[zone]
        if (!i) return { known: false }
        const local = -new Date().getTimezoneOffset()
        const t = Z.zoneTime(atMs > 0 ? atMs : Date.now(), i.off, local)
        return { known: true, h: t.h, m: t.m, dayShift: t.dayShift, abbr: i.abbr, off: i.off,
                 diff: Z.diffLabel(i.off, local), day: Z.isDay(t.h) }
    }
    // The machine's own zone, the same shape (no offset to look up).
    function here(atMs) {
        Clock.minutes
        const local = -new Date().getTimezoneOffset()
        const t = Z.zoneTime(atMs > 0 ? atMs : Date.now(), local, local)
        return { known: true, h: t.h, m: t.m, dayShift: 0, off: local, day: Z.isDay(t.h) }
    }

    // → "" on success, or why not.
    function add(zone) {
        if (!Z.validZone(zone)) return "That isn't a time zone"
        if (root.zones.indexOf(zone) >= 0) return "Already there"
        if (root.zones.length >= root.maxZones) return "That's plenty of clocks — remove one first"
        Config.worldClocks = root.zones.concat([zone])
        return ""
    }
    function remove(zone) { Config.worldClocks = root.zones.filter(z => z !== zone) }

    function search(query) { return Z.search(root.allZones, query, 6) }
    // Starts the (once-only) fetch of the zone list; search() fills in when it lands.
    function ensureList() {
        if (root.allZones.length > 0 || root.listing) return
        root.listing = true
        listProc.running = true
    }

    // ── Refcount ──────────────────────────────────────────────────────────────
    property int _refs: 0
    function acquire() {
        root._refs++
        if (root._refs === 1) {
            root._readOffsets()
            if (root.localZone === "") localProc.running = true
        }
    }
    function release() { root._refs = Math.max(0, root._refs - 1) }

    Timer {
        interval: 15 * 60000
        repeat: true
        running: root._refs > 0 && root.zones.length > 0
        onTriggered: root._readOffsets()
    }
    onZonesChanged: if (root._refs > 0) root._readOffsets()

    // ── Offsets ───────────────────────────────────────────────────────────────
    property var _asked: []
    function _readOffsets() {
        if (root.zones.length === 0 || offProc.running) return
        root._asked = root.zones.slice()
        // A fixed script; the zones are its arguments ($1…), which the loop reads as "$@".
        offProc.command = ["sh", "-c", 'for z in "$@"; do TZ="$z" date +"%z %Z"; done', "sh"].concat(root._asked)
        offProc.running = true
    }
    Process {
        id: offProc
        stdout: StdioCollector { id: offOut }
        onExited: function (exitCode) {
            if (exitCode !== 0) { console.warn("WorldClock: date exited", exitCode); return }
            const lines = offOut.text.split("\n")
            const next = {}
            root._asked.forEach((z, i) => {
                const parts = (lines[i] || "").trim().split(" ")
                const off = Z.parseOffset(parts[0])
                if (!Number.isNaN(off)) next[z] = { off: off, abbr: parts.slice(1).join(" ") }
            })
            root.info = next
            // Zones added while this was running.
            if (JSON.stringify(root.zones) !== JSON.stringify(root._asked)) root._readOffsets()
        }
    }

    // The machine's own zone, for the pinned "here" row's name.
    Process {
        id: localProc
        command: ["timedatectl", "show", "-p", "Timezone", "--value"]
        stdout: StdioCollector { id: localOut }
        onExited: function (exitCode) {
            const z = localOut.text.trim()
            if (exitCode === 0 && Z.validZone(z)) root.localZone = z
        }
    }

    Process {
        id: listProc
        command: ["timedatectl", "list-timezones"]
        stdout: StdioCollector { id: listOut }
        onExited: function (exitCode) {
            root.listing = false
            if (exitCode !== 0) { console.warn("WorldClock: timedatectl couldn't list zones"); return }
            root.allZones = listOut.text.split("\n").map(s => s.trim()).filter(z => Z.validZone(z))
        }
    }
}
