pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "../config"
import "calllog.js" as Cl

// ── CallLog ───────────────────────────────────────────────────────────────────
// How long you have been in a Discord call with each person: the scoreboard on the voice panel
// (modules/panels/voice/VoiceBoardView). Added 2026-11-08 — the user wanted "the friend I've been the most in
// call with" on a board.
//
// ── What counts ───────────────────────────────────────────────────────────────
// Everyone in your current voice channel who isn't you and isn't a bot (`Discord.users`, which the RPC helper
// keeps from VOICE_STATE_* events). Time together is credited every `tick` and whenever the set of people
// changes; a span over two ticks (a suspend) is clipped. Each arrival is one more call together.
//
// DISCORD'S RPC DOES NOT EXPOSE YOUR FRIENDS LIST — only the people in the channel — so this can't tell a friend
// from anyone else who joined. The board ranks everyone; a person you don't want on it is hidden with one tap
// (still recorded, so they don't return), or removed for good.
//
// ── What's kept ───────────────────────────────────────────────────────────────
// `Quickshell.statePath("call-log.json")`: { version, people: { user id: { name, avatar, seconds, calls, last,
// hidden } } } — kept until you forget it (the user's choice; Settings › Discord › Call log, or the board's own
// controls). Never a channel or server name, never when each call was. Written once a minute and when a call
// ends. Logic and validation of what Discord sends: calllog.js (`bun scripts/test-calllog.js`).
//
// Eager in shell.qml, so it counts with no panel open. Off with `Config.callLog`.
// Diagnose: `qs ipc -c ~/.config/quicktest call calllog status` (counts only, never a name).
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property bool enabled: Config.callLog
    readonly property int tick: 30000
    readonly property int flushMs: 60000

    JsonStore {
        id: store
        path: Quickshell.statePath("call-log.json")
        defaults: ({ version: 1, people: {} })
        onLoaded: root._load()
    }
    Component.onCompleted: root._load()
    function _load() {
        if (root.loaded || !store.ready) return
        root.people = Cl.clean(store.value)
        root.loaded = true
        root._sync(true)
    }

    // In memory, ahead of the file by at most a flush.
    property var people: ({})
    property bool loaded: false
    property bool _dirty: false

    // ── Counting ──────────────────────────────────────────────────────────────
    // Who is in the call right now, as calllog.js keeps them; `_idsStamp` is their ids, so a speaking flicker (which
    // changes `Discord.users` without changing who is there) costs nothing.
    readonly property bool counting: root.enabled && root.loaded && Discord.inCall
    property var _present: []
    property string _idsStamp: ""
    property var _here: ({})
    property real _since: 0

    function _sync(force) {
        const now = Date.now()
        const next = root.counting ? Cl.people(Discord.users) : []
        const stamp = next.map(p => p.id).sort().join(",")
        if (!force && stamp === root._idsStamp) return
        // Credit what has been running, then the new people (each an arrival), then start the next span.
        if (root._since > 0 && root._present.length > 0) {
            root.people = Cl.credit(root.people, root._present, root._since, now, root.tick * 2 + 5000)
            root._dirty = true
        }
        const here = ({})
        for (const p of next) {
            here[p.id] = true
            if (!root._here[p.id]) { root.people = Cl.arrive(root.people, p, now); root._dirty = true }
        }
        root._here = here
        root._present = next
        root._idsStamp = stamp
        root._since = next.length > 0 ? now : 0
        // A call that just ended is saved now, not up to a minute later.
        if (next.length === 0 && root._dirty) root._flush()
    }
    Connections {
        target: Discord
        function onUsersChanged() { root._sync(false) }
        function onInCallChanged() { root._sync(false) }
    }
    onCountingChanged: root._sync(false)

    // The same stamp-less credit on a clock, so a long call with nobody joining is still counted.
    Timer {
        interval: root.tick
        repeat: true
        running: root.counting && root._present.length > 0
        onTriggered: root._sync(true)
    }
    Timer {
        interval: root.flushMs
        repeat: true
        running: root.enabled
        onTriggered: root._flush()
    }
    function _flush() {
        if (!root._dirty) return
        store.value = ({ version: 1, people: root.people })
        root._dirty = false
    }
    Component.onDestruction: { root._sync(true); root._flush(); store.flush() }

    // ── What the views read ───────────────────────────────────────────────────
    readonly property var board: Cl.ranking(root.people, false)
    readonly property var boardAll: Cl.ranking(root.people, true)
    readonly property int hiddenCount: root.boardAll.length - root.board.length
    readonly property real totalSeconds: root.board.reduce((s, r) => s + r.seconds, 0)
    // Who is in the call now (ids), for the board to light them.
    function isHere(id) { return root._here[id] === true }
    function duration(s) { return Cl.duration(s) }
    function ago(last) { void Clock.now; return Cl.ago(last, Date.now()) }

    function hide(id, hidden) { root.people = Cl.hide(root.people, id, hidden); root._dirty = true; root._flush() }
    function forget(id) { root.people = Cl.forget(root.people, id); root._dirty = true; root._flush() }
    // Everything (the settings card's ArmLatch). Writes at once: a "forgot" that is still in memory isn't one.
    function clear() {
        root._sync(true)
        root.people = ({})
        store.value = ({ version: 1, people: {} })
        root._dirty = false
        store.flush()
    }

    IpcHandler {
        target: "calllog"
        function status(): string {
            return "enabled=" + root.enabled + " loaded=" + root.loaded + " counting=" + root.counting
                 + " here=" + root._present.length + " people=" + Object.keys(root.people).length
                 + " hidden=" + root.hiddenCount
        }
    }
}
