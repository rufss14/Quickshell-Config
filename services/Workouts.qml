pragma Singleton
import Quickshell
import QtQuick
import "../config"
import "workout.js" as W

// ── Workouts ──────────────────────────────────────────────────────────────────
// The workout log behind the Workout page on the bottom-left island (modules/island/IslandWorkout). A
// singleton for the reason Tasks and Timers are: the island is built per screen, and two writers on one file
// is how a log loses a set.
//
// The rules are services/workout.js (pure, `bun scripts/test-workout.js`); this holds the state, saves it
// through a JsonStore (workouts.json under XDG_STATE_HOME: personal data, never in the repo), and refuses
// edits until the file has been read, so a change before the load cannot be saved over the real log. The
// workout being done is part of the saved state, so a reload or a restart in the middle of one loses nothing.
//
// ── The clock ─────────────────────────────────────────────────────────────────
// `now` ticks once a second, and only while a workout is running and not paused: an idle shell runs no timer
// for this. Everything that moves on the page (the elapsed time, the rest since the last set) reads it.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property var _state: W.empty()

    readonly property bool   ready:   store.ready
    readonly property string unit:    root._state.unit
    readonly property int    restGoal: root._state.restGoal
    readonly property var    active:  root._state.active
    readonly property var    history: root._state.history
    readonly property bool   running: root._state.active !== null
    readonly property bool   paused:  root._state.active !== null && root._state.active.pausedAt > 0

    property real now: Date.now()
    Timer {
        interval: 1000
        repeat: true
        running: root.running && !root.paused
        onTriggered: root.now = Date.now()
    }

    readonly property real elapsedMs: W.elapsed(root._state.active, root.now)
    readonly property var  stats:     W.stats(root._state.active)

    // Time since the last set was ticked off (the rest), 0 when none is yet.
    readonly property real restMs: {
        const a = root._state.active
        if (!a || root.paused) return 0
        let last = 0
        for (const e of a.entries) for (const s of e.sets) if (s.done !== false) last = Math.max(last, s.at)
        return last > 0 ? Math.max(0, root.now - last) : 0
    }

    // The exercises done most lately, with the values of the newest set of each: the composer's quick picks.
    readonly property var recent: W.recents(root._state, 8)
    readonly property var summary: W.summary(root._state.history, root.now)
    // The best set of each exercise so far, for the records badge.
    readonly property var bests: W.bests(root._state.history)
    function isRecord(kind, name, set) { return W.isRecord(root.bests, kind, name, set) }

    // What the add field would add for `text`, and the exercises it matches (both read the log, so a binding
    // that calls them re-runs when it changes).
    function spec(text, defaults)  { return W.quickSpec(root._state, text, root._state.unit, defaults) }
    function suggest(text, n)      { return W.suggest(root._state, text, n) }

    function start()             { root._set(W.startWorkout(root._state, Date.now())) }
    // "Do that again": a new workout with the last one's exercises planned.
    function repeatLast()        { if (root._state.history.length > 0) root._set(W.startFrom(root._state, root._state.history[0], Date.now())) }
    function togglePause()       { root._set(W.togglePause(root._state, Date.now())) }
    function finish()            { root._set(W.finish(root._state, Date.now())) }
    function discard()           { root._set(W.discard(root._state)) }
    // The checklist: sets are planned, then ticked off. `logSets` is for a set already done.
    function planSets(spec, n)   { root._set(W.planSets(root._state, spec, n, Date.now())) }
    function logSets(spec, n)    { root._set(W.logSets(root._state, spec, n, Date.now())) }
    function toggleSet(id, i)    { root._set(W.toggleSet(root._state, id, i, Date.now())) }
    function tweakSet(id, i, p)  { root._set(W.tweakSet(root._state, id, i, p)) }
    function addSetLike(id)      { root._set(W.addSetLike(root._state, id)) }
    function removeSet(id, i)    { root._set(W.removeSet(root._state, id, i)) }
    function removeEntry(id)     { root._set(W.removeEntry(root._state, id)) }
    function removeWorkout(id)   { root._set(W.removeWorkout(root._state, id)) }
    function setUnit(u)          { root._set(W.setUnit(root._state, u)) }
    function setRestGoal(secs)   { root._set(W.setRestGoal(root._state, secs)) }

    // A pure op returns its argument when nothing changed — no write for a no-op.
    function _set(next) {
        if (!store.ready || next === root._state) return
        root._state = next
        root.now = Date.now()
        store.value = next
    }

    JsonStore {
        id: store
        path: Quickshell.statePath("workouts.json")
        onLoaded: {
            root._state = W.normalise(store.value)
            root.now = Date.now()
        }
    }
}
