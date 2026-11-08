pragma Singleton
import Quickshell
import QtQuick
import "../config"
import "mixermemory.js" as Mm

// ── MixerMemory ───────────────────────────────────────────────────────────────
// The audio mixer's per-app memory, over the Audio service. Audio stays the one place that touches
// PipeWire; this decides WHAT to ask of it (services/mixermemory.js, tested) and remembers it.
//
// ── Pinned apps ───────────────────────────────────────────────────────────────
// The mixer's pin on an app card says "keep this app how I set it": its level, whether it is muted and which
// output it plays through. The record is keyed by the app's id (Audio.appIdFor, lower case) and lives in
// gamemode-style state, `mixer-memory.json`. When a stream of a pinned app appears, it is put back — ONCE per
// stream, a moment after it shows up, never again: a player that rewrites its own level later (Spotify does on a
// track change) is not fought, and a level you then set yourself is simply the new record. Apps you did not
// pin are never touched. The routing goes through Audio.moveStream, so the same guards apply.
//
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── Pinned apps ───────────────────────────────────────────────────────────
    property var apps: ({})          // key → { level, muted, sink, name, at }

    JsonStore {
        id: store
        path: Quickshell.statePath("mixer-memory.json")
        defaults: ({ version: 1, apps: {} })
        onLoaded: root.apps = Mm.cleanMemory(store.value)
    }
    Component.onCompleted: if (store.ready) root.apps = Mm.cleanMemory(store.value)

    function _save() { if (store.ready) store.value = ({ version: 1, apps: root.apps }) }

    function keyOf(node) { return Mm.keyOf(Audio.appIdFor(node)) }
    function recordOf(node) { return root.apps[root.keyOf(node)] ?? null }
    function pinned(node) { return root.recordOf(node) !== null }
    readonly property int pinnedCount: Object.keys(root.apps).length

    // What the app is now, written down.
    function pin(node) {
        const k = root.keyOf(node)
        if (k === "" || !node?.audio) return
        root.apps = Mm.remember(root.apps, k, {
            level: Audio.levelOf(node), muted: node.audio.muted === true,
            sink: Audio.sinkOf(node)?.name ?? "", name: Audio.labelFor(node)
        }, Date.now())
        root._seen[node.id] = true            // it is already how it should be
        root._save()
    }
    function unpin(node) { root.forgetKey(root.keyOf(node)) }
    function forgetKey(key) {
        root.apps = Mm.forget(root.apps, key)
        root._save()
    }
    function clearAll() {
        root.apps = ({})
        root._save()
    }
    // A change the user just made to a pinned app becomes the new record. Called from the mixer's handlers
    // after they have written to Audio; an app that is not pinned is ignored.
    function note(node, patch) {
        const k = root.keyOf(node)
        if (k === "" || !(k in root.apps)) return
        root.apps = Mm.remember(root.apps, k, patch, Date.now())
        root._save()
    }

    // ── Putting a pinned app back when it starts ──────────────────────────────
    readonly property var _seen: ({})        // node id → true, once handled
    Connections {
        target: Audio
        function onStreamsChanged() { settle.restart() }
    }
    // After the app has finished setting up its own stream, not while it is.
    Timer {
        id: settle
        interval: 700
        onTriggered: root._restoreStreams()
    }
    function _restoreStreams() {
        const live = {}
        for (const n of Audio.streams) {
            live[n.id] = true
            if (root._seen[n.id]) continue
            root._seen[n.id] = true
            const r = root.recordOf(n)
            if (r) root._apply(n, r)
        }
        for (const id of Object.keys(root._seen)) if (!live[id]) delete root._seen[id]
    }
    function _apply(node, r) {
        if (Math.abs(Audio.levelOf(node) - r.level) > 0.02) Audio.setNodeVolume(node, r.level, r.level > 1)
        if (node.audio && (node.audio.muted === true) !== r.muted) node.audio.muted = r.muted
        if (r.sink !== "" && Audio.sinkOf(node)?.name !== r.sink) {
            const sink = Audio.sinks.find(s => s.name === r.sink)
            if (sink) Audio.moveStream(node, sink)
        }
    }
}
