pragma Singleton
import Quickshell
import QtQuick
import "../config"
import "tasks.js" as T

// ── Tasks ─────────────────────────────────────────────────────────────────────
// The to-do list behind the sidebar's checklist button (TasksPanel). A singleton for
// the reason Timers is one: the panel is built per screen, and two writers on one file
// is how a list loses an item.
//
// The rules are services/tasks.js (pure, `bun scripts/test-tasks.js`); this holds the
// state, saves it through a JsonStore (tasks.json under XDG_STATE_HOME — personal data,
// so never in the repo), and refuses edits until the file has been read: a change before
// the load would otherwise be saved over the real list.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property var _state: T.empty()

    readonly property bool ready:     store.ready
    readonly property var  items:     T.view(root._state)
    readonly property int  openCount: T.openCount(root._state)
    readonly property int  doneCount: root._state.items.length - root.openCount

    function add(text)       { root._set(T.add(root._state, text, Date.now())) }
    function toggle(id)      { root._set(T.toggle(root._state, id, Date.now())) }
    function rename(id, t)   { root._set(T.rename(root._state, id, t)) }
    function remove(id)      { root._set(T.remove(root._state, id)) }
    function clearDone()     { root._set(T.clearDone(root._state)) }

    // A pure op returns its argument when nothing changed — no write for a no-op.
    function _set(next) {
        if (!store.ready || next === root._state) return
        root._state = next
        store.value = next
    }

    JsonStore {
        id: store
        path: Quickshell.statePath("tasks.json")
        onLoaded: root._state = T.normalise(store.value)
    }
}
