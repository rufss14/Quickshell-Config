pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "reminders.js" as R
import "ics.js" as Ics

// ── Reminders ─────────────────────────────────────────────────────────────────
// Things to remember, with or without a time, from the clock panel's Calendar page.
// A timed reminder posts a desktop notification when it comes due; ticking one off
// keeps it for a day (so a mis-tick can be undone), then it's dropped.
//
// The rules — valid input, the quick times, what's due, the order, the words for
// "when" — are reminders.js (tested by scripts/test-reminders.js). This owns the
// file, the minute tick and the notification.
//
// ── It has to be running to remind you ────────────────────────────────────────
// A reminder that only fires while the panel is open isn't one. shell.qml holds an
// eager reference so this exists from launch, and the tick is Clock's minute — no
// timer of its own.
//
// ── The file ──────────────────────────────────────────────────────────────────
// A JsonStore at Quickshell.dataPath("reminders.json"): atomic writes, the directory
// created on first save, and a file that doesn't parse is never overwritten. Same
// late-load rule as Timers: if you add a reminder before the file has been read, what
// you did wins and the stale read is discarded.
//
// ── Missed while the shell was down ───────────────────────────────────────────
// On load, anything that came due in the last 12 hours and never fired is notified
// once, marked as missed. Older ones are marked fired silently — a notification about
// last week's reminder, every login, is noise.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property var items: []

    // Listed order: overdue, timed, untimed, done. Re-sorted when the reminders
    // change, NOT every minute: a fresh array each minute would rebuild every row (and
    // replay its entrance) for nothing. The words that do move with the clock — "in 25
    // min", "Overdue" — come from dueLabel(), which does re-read each minute.
    readonly property var sorted: R.sorted(root.items, Date.now())
    readonly property int openCount: root.items.filter(r => !r.done).length
    readonly property int overdueCount: {
        Clock.minutes
        const now = Date.now()
        return root.items.filter(r => !r.done && r.due > 0 && r.due <= now).length
    }

    readonly property bool ready: store.ready

    function dueLabel(r) {
        Clock.minutes
        return R.dueLabel(r.due, Date.now())
    }

    // ── Adding ────────────────────────────────────────────────────────────────
    // → "" on success, or why not, worded for the panel to show.

    // `preset` is "", "hour", "evening" or "tomorrow".
    function add(text, preset) {
        const due = preset ? R.presetDue(preset, Date.now()) : 0
        return root._add(text, due)
    }

    // A typed time ("8", "8:30", "20h") on a day.
    function addAt(text, dayMs, timeText) {
        const t = Ics.parseTime(timeText)
        if (!t) return "That time isn't a time"
        return root._add(text, R.dueAt(dayMs, t.h, t.m, Date.now()))
    }

    // At an exact moment (epoch ms) — what the clock panel's quick-add resolved "in 20 min" or "friday 9am" to.
    // One already behind us would fire at the next minute tick, which is not what anyone typed it for.
    function addDue(text, dueMs) {
        if (!(dueMs > Date.now())) return "That time has already passed"
        return root._add(text, dueMs)
    }

    function _add(text, due) {
        const now = Date.now()
        const c = R.create(text, due, now, Ics.newUid(now, Math.random().toString(36).slice(2, 10)))
        if (!c.ok) return c.error
        root._set(root.items.concat([c.item]))
        return ""
    }

    // ── Changing ──────────────────────────────────────────────────────────────
    function toggle(id) {
        const now = Date.now()
        root._set(root.items.map(r => r.id !== id ? r
            : Object.assign({}, r, { done: !r.done, doneAt: r.done ? 0 : now })))
    }

    function snooze(id, minutes) {
        const now = Date.now()
        root._set(root.items.map(r => r.id === id ? R.snooze(r, minutes, now) : r))
    }

    function remove(id) {
        root._set(root.items.filter(r => r.id !== id))
    }

    function _set(list) {
        root.items = list
        root._persist()
    }

    // ── The minute tick ───────────────────────────────────────────────────────
    Connections {
        target: Clock
        function onMinutesChanged() { root._check() }
    }

    function _check() {
        if (!store.ready) return
        const now = Date.now()
        const due = R.dueToFire(root.items, now)
        const pruned = R.prune(root.items, now)
        if (due.length === 0 && pruned.length === root.items.length) return
        if (due.length > 0) root._notify(due, false)
        const fired = due.map(r => r.id)
        root._set(pruned.map(r => fired.indexOf(r.id) >= 0 ? Object.assign({}, r, { notified: true }) : r))
    }

    // ── Notifying ─────────────────────────────────────────────────────────────
    // notify-send, the route Timers and Updates already use, so a reminder arrives as
    // an ordinary notification — history, Do Not Disturb and all. Several at once are
    // one notification, not a stack.
    Process { id: notifyProc; running: false }

    function _notify(list, missed) {
        if (list.length === 0) return
        const title = missed
            ? (list.length === 1 ? "Missed reminder" : list.length + " missed reminders")
            : (list.length === 1 ? "Reminder" : list.length + " reminders")
        const body = list.map(r => r.text).join("\n")
        notifyProc.command = ["notify-send", "--app-name=Quickshell", "--urgency=normal",
                              "--icon=alarm", title, body]
        notifyProc.running = false
        notifyProc.running = true
    }

    // ── Persistence ───────────────────────────────────────────────────────────
    property bool _loading: false
    // Set by any change of yours: from then on live state is authoritative and a late
    // disk read must not overwrite it (see onLoaded).
    property bool _touched: false

    JsonStore {
        id: store
        path: Quickshell.dataPath("reminders.json")
        defaults: ({ items: [] })

        onLoaded: {
            if (root._touched) { root._persist(); return }
            root._loading = true

            const now = Date.now()
            const loaded = R.prune(R.normalize((store.value ?? {}).items), now)
            // Came due while the shell was down and never fired.
            const missed = R.dueToFire(loaded, now)
            const recent = missed.filter(r => now - r.due < 12 * 3600 * 1000)
            root.items = loaded.map(r => missed.some(m => m.id === r.id)
                ? Object.assign({}, r, { notified: true }) : r)

            root._loading = false
            if (missed.length > 0) root._persist()
            root._notify(recent, true)
        }
    }

    function _persist() {
        if (root._loading) return
        root._touched = true
        if (!store.ready) return
        store.value = { items: root.items }
    }
}
