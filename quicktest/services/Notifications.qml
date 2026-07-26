pragma Singleton
import Quickshell
import Quickshell.Services.Notifications
import QtQuick
import "../config"

// ── Notifications ─────────────────────────────────────────────────────────────
// The shell's notification daemon — the thing that replaces dunst. It owns the
// freedesktop `org.freedesktop.Notifications` D-Bus name via Quickshell's
// NotificationServer, so ONLY ONE can run: dunst has to be stopped first, or the
// server can't bind and nothing here receives anything.
//
// Two lists, deliberately separate:
//   • `records` — every notification we've kept, as plain DATA, until you clear it.
//                 This is what the notification centre shows, and it is SAVED TO DISK
//                 so the drawer survives a reload or a reboot.
//   • `popups`  — the toasts currently on screen. Live Notification objects (so their
//                 actions and inline-reply work), with their own short lives. A toast
//                 expiring removes it from `popups` but NOT from `records` — it just
//                 stops shouting; it's still in the drawer.
//
// ── Why history is records and not the server's live model ────────────────────
// The centre used to read `server.trackedNotifications` directly. A Notification
// object only exists for the process that received it, so history evaporated on every
// restart. Records are our own serialisable copies; a record is a drop-in for the
// toast delegate (same fields it reads) plus an empty `actions` — a restored
// notification's callbacks are gone, and the app that could service them may not even
// be running. While a notification is still live, its record carries `_live` (the real
// Notification) so a dismiss from the drawer can still tell the app; `_live` and
// `actions` are stripped before saving.
//
// Timeouts match your old dunstrc rather than honouring each app's requested time:
// low 3s, normal 5s, critical never. dunst worked that way too (per-urgency over app
// hints), so notifications feel exactly as they did.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── Do Not Disturb (persisted) ────────────────────────────────────────────
    // Suppresses toasts and routes everything straight to history. Critical still
    // breaks through — a "your battery is about to die" popup you can silence is not a
    // safety feature.
    property bool dnd: false
    function toggleDnd() { root.dnd = !root.dnd }

    // ── History ─────────────────────────────────────────────────────────────────
    // Newest first, plain records, persisted. `history` keeps the old name the centre
    // reads; `records` is the backing store the persistence layer owns.
    property var records: []
    readonly property var history: root.records
    readonly property int count: root.records.length
    // Bound so the on-disk file can't grow without limit. Oldest fall off the end.
    readonly property int maxHistory: 100
    property int _seq: 0

    // The app a notification (live OR record) is grouped under. "" folds into a single
    // "Notifications" bucket rather than an anonymous group.
    function _appKey(x) { return (x && x.appName) ? x.appName : "Notifications" }

    // ── Grouped history ─────────────────────────────────────────────────────────
    // history, bucketed by app for the notification centre. Newest-first is kept at
    // both levels: groups are ordered by their most recent notification, and items
    // within a group stay newest-first (history already is). Each entry is
    //   { app: <appName>, items: [rec, …], latest: <newest rec> }
    // where `latest` drives the group header's icon and count.
    readonly property var historyGroups: {
        const seen = ({})     // appName → group
        const order = []      // groups in first-seen order, i.e. newest-first
        for (const n of root.records) {
            const key = root._appKey(n)
            let g = seen[key]
            if (!g) { g = { app: key, items: [], latest: n }; seen[key] = g; order.push(g) }
            g.items.push(n)
        }
        return order
    }

    // ── Active toasts ─────────────────────────────────────────────────────────
    // Its own list, layered over history: which notifications are currently toasting.
    // These are LIVE Notification objects, not records — a toast needs real actions.
    property var popups: []
    readonly property int maxPopups: 5

    // Per-urgency dwell time, in ms. 0 = stays until dismissed. Matches dunstrc.
    function timeoutFor(n) {
        if (!n) return 5000
        switch (n.urgency) {
            case NotificationUrgency.Low:      return 3000
            case NotificationUrgency.Critical: return 0
            default:                           return 5000
        }
    }

    // App-level icon for a notification — the app's OWN icon, resolved from appIcon
    // or the app name. Deliberately not the sender's avatar (that's per-message
    // content); this is what the centre's per-app group header shows. Same
    // resolution the toast uses for its app-icon fallback, so a group header and the
    // rows beneath it agree on what the app looks like.
    function appIconFor(n) {
        if (!n) return ""
        const ai = n.appIcon || ""
        if (ai === "") return Icons.pathForAppId(n.appName || "")
        // appIcon can be a path, a file:// url, or an icon-theme name.
        if (ai.indexOf("/") >= 0) return ai.indexOf("file://") === 0 ? ai : "file://" + ai
        const themed = Quickshell.iconPath(ai, true)
        return themed !== "" ? themed : Icons.pathForAppId(n.appName || "")
    }

    function urgencyTint(n) {
        if (!n) return Colors.focus
        switch (n.urgency) {
            case NotificationUrgency.Critical: return Colors.danger
            case NotificationUrgency.Low:      return Colors.fgMuted
            default:                           return Colors.focus
        }
    }

    // ── Server ────────────────────────────────────────────────────────────────
    NotificationServer {
        id: server

        // Everything we can honour, advertised to apps.
        keepOnReload:         false
        actionsSupported:     true
        actionIconsSupported: true
        bodySupported:        true
        bodyMarkupSupported:  true
        bodyImagesSupported:  true
        imageSupported:       true
        inlineReplySupported: true
        persistenceSupported: true

        onNotification: function(n) {
            const critical = n.urgency === NotificationUrgency.Critical
            const show = !root.dnd || critical

            // Transient notifications (volume/brightness OSDs) ask NOT to be kept — they
            // get a toast and nothing in the drawer. Everything else becomes a record.
            let rec = null
            if (!n.transient) {
                rec = root._recordFor(n)
                // ── Track for the record's WHOLE life in history ──────────────────
                // Not just the toast's. While a notification is tracked, an app that
                // REPLACES it (replaces_id) mutates THIS same object in place and fires
                // NO new onNotification — verified in the server source. So history
                // collapses to one entry that updates (see the live-refresh
                // Instantiator), instead of a fresh record per progress tick. Untracked,
                // the server forgets it, and the next replacement is seen as brand new —
                // which is exactly the old duplicate-history bug. Released when the
                // record finally leaves history (dismiss / clear / eviction).
                n.tracked = true
                rec._live = n
                const list = root.records.slice()
                list.unshift(rec)
                while (list.length > root.maxHistory) root._releaseLive(list.pop())
                root.records = list
                root._persist()
            }

            if (show) {
                // A transient toast has no record to hold its object alive, so track it
                // here for the toast's lifetime (its actions/reply); a recorded one is
                // already tracked above.
                n.tracked = true
                root.showPopup(n)
            }
            // Suppressed (DND, non-critical) with a record: still tracked above so it can
            // be dismissed and collapsed. A suppressed TRANSIENT has neither record nor
            // toast — left untracked, and the server drops it.
        }
    }

    // ── Records ─────────────────────────────────────────────────────────────────
    // A notification's image is EITHER a real file/URL (a screenshot's path, an
    // http avatar) OR a per-session `image://qsimage/<handle>` provider url that dies
    // with the notification — and certainly with the process. A record outlives both,
    // so a provider handle stored in one is a DEAD handle by the time the drawer (or a
    // reload) asks for it. That is the flood of "Requested image from unknown handle"
    // warnings. Keep only the stable kind; the delegate falls back to the app icon for
    // the rest, quietly. The live TOAST still shows the provider image — it reads the
    // live object directly, where the handle is valid.
    function _stableImage(img) {
        return (img && img.indexOf("image://") !== 0) ? img : ""
    }

    function _recordFor(n) {
        return {
            key:     "n" + (root._seq++),
            appName: n.appName || "",
            appIcon: n.appIcon || "",
            summary: n.summary || "",
            body:    n.body || "",
            image:   root._stableImage(n.image),
            urgency: n.urgency,
            time:    Date.now(),
            // Empty for records; the toast reads its actions off the live object.
            actions: [],
            _live:   n
        }
    }

    function _removeRecord(rec) {
        if (!rec) return
        root.records = root.records.filter(r => r.key !== rec.key)
        root._persist()
    }

    // A record is leaving history (evicted past maxHistory) — let go of its live
    // object so the server can drop it. Untrack rather than dismiss(): dismiss tells
    // the app the user closed it, but an eviction is us running out of room, not a
    // user action. A still-shown toast is always among the NEWEST records and never
    // evicted, so this can't yank a toast off screen.
    function _releaseLive(rec) {
        if (rec && rec._live) {
            try { rec._live.tracked = false } catch (e) {}
            rec._live = null
        }
    }

    // ── Keep a live record's content current ──────────────────────────────────
    // A replacement mutates the live Notification in place and fires no
    // onNotification (server source), so without this the drawer would freeze at the
    // FIRST version of an updating notification — a download stuck at "0%". One
    // Connections per still-live record refreshes its record when the object changes.
    // Rebuilt only when the SET of live records changes, not on every field tick.
    readonly property var _liveRecords: root.records.filter(r => r._live)
    Instantiator {
        model: root._liveRecords
        delegate: Connections {
            required property var modelData
            target: modelData._live
            function onSummaryChanged() { root._refreshRecord(modelData) }
            function onBodyChanged()    { root._refreshRecord(modelData) }
            function onImageChanged()   { root._refreshRecord(modelData) }
            function onUrgencyChanged() { root._refreshRecord(modelData) }
        }
    }
    function _refreshRecord(rec) {
        if (!rec || !rec._live) return
        const n = rec._live
        rec.summary = n.summary || ""
        rec.body    = n.body || ""
        rec.image   = root._stableImage(n.image)
        rec.urgency = n.urgency
        rec.time    = Date.now()
        // Records are plain objects — mutating fields notifies nothing. Re-assign the
        // array so historyGroups and the centre re-read. Content changed; ORDER did
        // NOT — a progress bar shouldn't leap to the top on every tick.
        root.records = root.records.slice()
        root._persist()
    }

    // ── Popup mutations are DEFERRED and BATCHED ──────────────────────────────
    // The toast Repeater's model is bound to `popups`, so assigning `popups` writes
    // the Repeater's model and regenerates its delegates. A toast's exit animation
    // finishes and calls dismiss() — which would assign `popups` FROM INSIDE that
    // delegate's own signal, i.e. write the model while it is mid-regenerate.
    // That re-entrant delegate incubation is the segfault in the backtrace
    // (QQuickRepeater::regenerate → incubate). Applying the new array on the next
    // event-loop turn, outside any binding or incubation, removes the re-entrancy;
    // and because a burst of notifications all fold into one pending array, it also
    // collapses "many at once" into a single regeneration instead of one per event.
    property var _pendingPopups: null
    function _currentPopups() {
        return root._pendingPopups !== null ? root._pendingPopups : root.popups
    }
    function _setPopups(p) {
        root._pendingPopups = p
        Qt.callLater(root._flushPopups)
    }
    function _flushPopups() {
        if (root._pendingPopups === null) return
        const p = root._pendingPopups
        root._pendingPopups = null
        root.popups = p
    }

    // ── Popup lifecycle ───────────────────────────────────────────────────────
    function showPopup(n) {
        const p = root._currentPopups().slice()
        // De-dupe: an app replacing its own notification (same id) shouldn't stack.
        const i = p.findIndex(x => x.id === n.id)
        if (i >= 0) p.splice(i, 1)
        p.unshift(n)
        while (p.length > root.maxPopups) {
            const dropped = p.pop()
            if (dropped && dropped.transient) { try { dropped.dismiss() } catch (e) {} }
        }
        root._setPopups(p)
    }

    // Toast expired or was swiped away KEEPING it. Stops the toast; keeps the record —
    // UNLESS it was transient, which never wanted to be kept.
    //
    // ── Why the try/catch ─────────────────────────────────────────────────────
    // A toast's exit animation now runs for ~200ms BEFORE this fires, and the
    // notification can be gone by then — the app closed it, or a fresh notification
    // rebuilt the popup model and destroyed the delegate. Touching a destroyed
    // Notification throws ("TypeError" on a dead QObject). It's already gone, which
    // is the outcome we wanted, so swallow it rather than let it break the caller.
    function expirePopup(n) {
        root._setPopups(root._currentPopups().filter(x => x !== n))
        // Keep the live object: its record stays in history and still OWNS it, so a
        // later replacement (replaces_id) collapses onto it and a dismiss from the
        // drawer can still tell the app. A transient toast has no record backing it,
        // so end it for real or it would leak, tracked forever.
        try { if (n && n.transient) n.dismiss() } catch (e) {}
    }

    // Full dismiss — removes from history. Accepts EITHER a live Notification (a toast's
    // close button or swipe) or a record (the centre's ✕ / middle-click).
    function dismiss(x) {
        if (!x) return
        if (typeof x.dismiss === "function") {
            // Live notification, from a toast.
            root._setPopups(root._currentPopups().filter(p => p !== x))
            const rec = root.records.find(r => r._live === x)
            if (rec) root._removeRecord(rec)
            try { x.dismiss() } catch (e) {}
        } else {
            // Record, from the centre.
            if (x._live) {
                root._setPopups(root._currentPopups().filter(p => p !== x._live))
                try { x._live.dismiss() } catch (e) {}
            }
            root._removeRecord(x)
        }
    }

    function dismissAllPopups() {
        const p = root._currentPopups().slice()
        root._setPopups([])
        for (let i = 0; i < p.length; i++)
            if (p[i].transient) { try { p[i].dismiss() } catch (e) {} }
    }

    function clearHistory() {
        // Tell any still-live apps, then drop every record in one write.
        for (let i = 0; i < root.records.length; i++) {
            const live = root.records[i]._live
            if (live) { try { live.dismiss() } catch (e) {} }
        }
        root._setPopups([])
        root.records = []
        root._persist()
    }

    // Clear every record belonging to one app — the per-group ✕ in the centre. Batched:
    // partition once, write once, then tell any live apps.
    function clearApp(appName) {
        const keep = [], drop = []
        for (let i = 0; i < root.records.length; i++) {
            const r = root.records[i]
            if (root._appKey(r) === appName) drop.push(r); else keep.push(r)
        }
        if (drop.length === 0) return
        root.records = keep
        root._persist()
        for (let i = 0; i < drop.length; i++) {
            const live = drop[i]._live
            if (live) {
                root._setPopups(root._currentPopups().filter(p => p !== live))
                try { live.dismiss() } catch (e) {}
            }
        }
    }

    function invoke(action) { if (action) action.invoke() }

    // ── Persistence ───────────────────────────────────────────────────────────
    // dnd AND the history records live in one document. A PersistentProperties block
    // has no disk I/O — it survives a hot reload and nothing else — so this is a
    // JsonStore (FileView, atomic, debounced), its own file, one writer, no watch.
    JsonStore {
        id: store
        path: Quickshell.statePath("notifications.json")
        onLoaded: {
            root._loading = true
            const v = store.value ?? ({})
            root.dnd  = v.dnd ?? root.dnd
            root._seq = v.seq ?? 0
            // Rehydrate into clean records: no `_live` (nothing is live yet) and an
            // empty `actions` (restored callbacks are gone). Defaults guard a partial
            // or older file.
            const src = v.records ?? []
            const out = []
            for (let i = 0; i < src.length; i++) {
                const r = src[i]
                out.push({
                    key:     r.key ?? ("r" + i),
                    appName: r.appName || "",
                    appIcon: r.appIcon || "",
                    summary: r.summary || "",
                    body:    r.body || "",
                    // Scrub any volatile provider url a previous version may have saved
                    // — those are the dead handles behind the "unknown handle" flood.
                    image:   root._stableImage(r.image || ""),
                    urgency: r.urgency ?? NotificationUrgency.Normal,
                    time:    r.time ?? 0,
                    actions: [],
                    _live:   null
                })
            }
            root.records = out
            root._loading = false
        }
    }

    property bool _loading: false

    // Strip the fields that can't (or shouldn't) be serialised: `_live` is a QObject,
    // `actions` is empty for records and rebuilt on load.
    function _strip(r) {
        return {
            key: r.key, appName: r.appName, appIcon: r.appIcon,
            summary: r.summary, body: r.body, image: r.image,
            urgency: r.urgency, time: r.time
        }
    }

    function _persist() {
        if (root._loading || !store.ready) return
        store.value = {
            dnd:     root.dnd,
            seq:     root._seq,
            records: root.records.map(root._strip)
        }
    }

    onDndChanged: root._persist()
}
