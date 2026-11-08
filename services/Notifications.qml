pragma Singleton
import Quickshell
import Quickshell.Services.Notifications
import Quickshell.Hyprland
import QtQuick
import "../config"
import "notifyrules.js" as Rules
import "notifyview.js" as View

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
// be running.
//
// A record holds NOTHING but plain data — strings and numbers. That is a hard rule,
// not a description: records are what the notification centre's Repeater renders, and
// a QObject reaching a delegate's `modelData` is what crashed this shell eighteen
// times. The live Notification behind a record (so a dismiss from the drawer can
// still tell the app) lives in the `_liveByKey` side table instead. See its comment.
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
    //
    // This is the USER's setting and only ever the user's: it is written to
    // notifications.json, so anything else that flipped it would be editing a stored
    // preference to express a temporary mood. See the holds below for how services
    // ask for quiet instead.
    property bool dnd: false
    // ── …optionally for a while ───────────────────────────────────────────────
    // Epoch ms at which `dnd` switches itself off; 0 = until you do. Persisted with `dnd`, so a
    // reload keeps "for an hour" meaning an hour — and it can't strand the machine quiet, because
    // it expires (on load too: a stale one is cleared). Checked on the Clock's minute tick, so it
    // ends within a minute of its time. Only ever the user's: a hold (below) is a different thing.
    property real dndUntil: 0
    readonly property string dndLabel: View.untilLabel(root.dndUntil, Clock.now.getTime())
    function toggleDnd() { root.dndUntil = 0; root.dnd = !root.dnd }
    function dndFor(minutes) { root.dndUntil = Date.now() + minutes * 60000; root.dnd = true; root._persist() }
    function dndUntilMorning() { root.dndUntil = View.nextMorning(Date.now(), 8); root.dnd = true; root._persist() }
    function _expireDnd() {
        if (root.dnd && root.dndUntil > 0 && Date.now() >= root.dndUntil) { root.dndUntil = 0; root.dnd = false }
    }

    // ── Muted apps (persisted) ────────────────────────────────────────────────
    // An app here still lands in the history — silently: no toast, no chime. Critical breaks
    // through, as it does for Do Not Disturb. Named by the same key the groups use (_appKey).
    property var mutedApps: []
    function isMuted(app) { return root.mutedApps.indexOf(app) >= 0 }
    function toggleMute(app) { root.mutedApps = View.toggleIn(root.mutedApps, app); root._persist() }

    // ── Quiet holds: temporary DND, owned by whoever asked ────────────────────
    // Gamemode wants notifications suppressed while it is on, and the obvious way to
    // do that — set `dnd`, restore it on exit — is a trap for a persisted property.
    // A reload or a crash mid-session strands the machine in Do Not Disturb, silently,
    // with no memory that anything meant to put it back. The stored preference must
    // outlive the shell; a temporary suppression must not.
    //
    // So holders are named and live in memory only, exactly like the Idle service's
    // (same reasoning, same shape, and the two are usually held together). Nothing
    // here is persisted, so a reload releases every hold by construction.
    property var quietHolds: []

    function holdQuiet(reason) {
        if (root.quietHolds.indexOf(reason) !== -1) return
        // Reassigned, not mutated: push on a bound array does not notify, so the
        // suppression would take effect with nothing on screen changing to say so.
        root.quietHolds = root.quietHolds.concat([reason])
    }

    function releaseQuiet(reason) {
        const i = root.quietHolds.indexOf(reason)
        if (i === -1) return                    // no-op, deliberately
        const next = root.quietHolds.slice()
        next.splice(i, 1)
        root.quietHolds = next
    }

    // ── The question every consumer should actually ask ───────────────────────
    // "Should this machine be quiet right now" — the user's setting OR anyone's hold.
    // The delivery gate and every indicator read THIS; only the right-click toggle and
    // the persistence layer touch `dnd` itself.
    readonly property bool quiet: root.dnd || root.quietHolds.length > 0

    // Quiet because of something other than the user's own switch. Indicators render
    // this differently: a state your click will not clear has to look different from
    // one that will, or the bell reads as a broken button while gamemode is on.
    readonly property bool quietHeldExternally: root.quietHolds.length > 0

    // ── History ─────────────────────────────────────────────────────────────────
    // Newest first, plain records, persisted. `history` keeps the old name the centre
    // reads; `records` is the backing store the persistence layer owns.
    property var records: []
    readonly property var history: root.records
    readonly property int count: root.records.length
    // Bound so the on-disk file can't grow without limit. Oldest fall off the end.
    readonly property int maxHistory: 100
    property int _seq: 0

    // ── Repeats don't stack ─────────────────────────────────────────────────────
    // "Lyrics connected" ×48 made the centre look busier than it was. What counts as the
    // same thing (shell status by app + summary, a battery reminder by device) and when a
    // battery reminder is worth a toast live in notifyrules.js (tested). `list` is
    // newest-first, so the first of each kind seen is the one that stays; the others
    // leave history, releasing any live object as an eviction does.
    function _collapseRepeats(list) {
        const seen = ({})
        return list.filter(r => {
            const k = Rules.collapseKey(r.appName, r.summary)
            if (k === "") return true
            if (seen[k]) { root._releaseLive(r); return false }
            seen[k] = true
            return true
        })
    }

    // Battery key → the level at the last toast for it. Memory only: after a reload the
    // first reminder toasts once more, which is cheaper than another persisted field.
    property var _batteryToasted: ({})

    // A battery reminder that isn't news: its entry in the centre is updated in place
    // (level, wired/wireless name) with its time untouched, so it neither toasts nor
    // re-badges the bell. No entry (cleared by the user) → dropped, not resurrected.
    function _refreshBattery(bkey, n) {
        const i = root.records.findIndex(r => Rules.collapseKey(r.appName, r.summary) === bkey)
        if (i < 0) return
        const list = root.records.slice()
        list[i] = Object.assign({}, list[i], { summary: n.summary || "", body: n.body || "" })
        root.records = list
        root._persist()
    }

    // ── Unseen ──────────────────────────────────────────────────────────────────
    // How many arrived since the history was last looked at — the sidebar's bell
    // badge. A time, not a key: records are re-keyed on load, their times never
    // change. Only the sidebar's panel marks them seen (the overview's centre sits on
    // a page you may never turn to). Persisted with the history, so a reload doesn't
    // re-announce everything.
    property real seenAt: 0
    readonly property int unseen: {
        let n = 0
        for (const r of root.records) if (r.time > root.seenAt) n++
        return n
    }
    // Unseen, per app, for the dock's badges (2026-10-31): counted under the notification's
    // desktop entry and its app name, both lowercased, so the dock can ask by either — a
    // dock key is a window class or desktop id ("vesktop"), an app names itself ("Vesktop").
    readonly property var unseenByApp: {
        const m = ({})
        for (const r of root.records) {
            if (r.time <= root.seenAt) continue
            const entry = String(r.desktopEntry || "").toLowerCase().replace(/\.desktop$/, "")
            const name = String(r.appName || "").toLowerCase()
            if (entry !== "") m[entry] = (m[entry] || 0) + 1
            if (name !== "" && name !== entry) m[name] = (m[name] || 0) + 1
        }
        return m
    }
    function unseenFor(appId, name) {
        const a = String(appId || "").toLowerCase(), n = String(name || "").toLowerCase()
        return root.unseenByApp[a] ?? root.unseenByApp[n] ?? 0
    }
    function markSeen() {
        if (root.unseen === 0) return
        root.seenAt = Date.now()
        root._persist()
    }

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

    // The centre's one-line state, under its title — the overview's card and the
    // sidebar's panel both show it, so it's said once, here.
    readonly property string statusLine:
          root.dnd                  ? "Do Not Disturb" + (root.dndLabel !== "" ? " " + root.dndLabel : "")
        : root.quietHeldExternally  ? "Quiet — held by " + root.quietHolds.join(", ")
        : root.count === 0          ? "All caught up"
        : root.count === 1          ? "1 notification"
        : root.count + " notifications from " + root.historyGroups.length
          + (root.historyGroups.length === 1 ? " app" : " apps")

    // ── Active toasts ─────────────────────────────────────────────────────────
    // Its own list, layered over history: which notifications are currently toasting.
    // These are LIVE Notification objects, not records — a toast needs real actions.
    property var popups: []

    // ── Which monitor the toasts belong to, LATCHED ───────────────────────────
    // Captured when the deck goes from empty to non-empty, and then left alone until
    // it empties again. The hosts used to bind straight to `Hyprland.focusedMonitor`,
    // which meant a toast MIGRATED to whichever screen the pointer wandered onto —
    // you would glance away from the notification and it would follow you, having
    // already left the screen you were reading it on. A notification is a record of
    // something that happened somewhere; it stays where it was delivered.
    //
    // Latched for the whole deck rather than per toast, because a deck is one stack
    // and cannot straddle two outputs. A toast arriving while one is already up joins
    // it where it is.
    property string popupMonitor: ""
    readonly property int maxPopups: 5

    // A critical notification currently toasting — an incoming call is the canonical
    // example (most clients send it at Critical urgency), but this is the general
    // signal, not a Discord-specific one. Critical never auto-dismisses (see
    // timeoutFor below), so this stays true for exactly as long as the thing it's
    // reporting is still going on. Used by the bar's bell to pick its "active" icon.
    readonly property bool hasCritical:
        root.popups.some(n => n.urgency === NotificationUrgency.Critical)

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
        const isPath = ai.indexOf("/") >= 0
        // ── The user's icon theme first ───────────────────────────────────────
        // appIcon is a theme NAME ("dialog-warning"), a path ("/usr/lib/kitty/logo/kitty.png"), or
        // a file:// url. A name goes to Papirus (Icons.pathForIconName), then Qt's lookup. A
        // path is the app's OWN file, which no theme styles, so it is read as the name it carries
        // ("…/kitty.png" → kitty) and offered to Papirus alone — a basename like "icon" must not
        // reach Qt's lookup, which might answer with something unrelated. Then the app's identity through the
        // desktop entry or its name, the way the dock resolves it. Only then the file itself.
        const name = isPath ? ai.replace(/^.*\//, "").replace(/\.[^.]*$/, "") : ai
        const themed = name !== "" ? Icons.pathForIconName(name, !isPath) : ""
        if (themed !== "") return themed
        const byApp = Icons.pathForAppId(n.desktopEntry || "") || Icons.pathForAppId(n.appName || "")
        if (byApp !== "") return byApp
        if (isPath) return ai.indexOf("file://") === 0 ? ai : "file://" + ai
        return ""
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
            // ── Screenshot tools are taken over, not shown twice ──────────────
            // Returns true only when this WAS a screenshot with a readable file, in
            // which case the shell raises its own toast with the picture and actions
            // on it. Anything else — including a screenshot tool's error message —
            // falls through untouched. Dropping it here also means the file never
            // reaches the icon loader, which is what was logging "Could not load icon
            // … QSize(2, 2)" for every shot hyprshot took.
            if (Screenshot.consume(n)) return

            // ── A battery reminder that repeats is not news ───────────────────
            // Left untracked, so the server drops it (like a suppressed transient).
            const bkey = Rules.batteryKey(n.appName, n.summary)
            if (bkey !== "") {
                const level = Rules.batteryLevel(n.body)
                if (!Rules.shouldToast(root._batteryToasted[bkey], level)) {
                    root._refreshBattery(bkey, n)
                    return
                }
                const next = Object.assign({}, root._batteryToasted)
                next[bkey] = level
                root._batteryToasted = next
            }

            const critical = n.urgency === NotificationUrgency.Critical
            // `quiet`, not `dnd`: a gamemode hold suppresses toasts the same way the
            // user's own switch does. Critical still breaks through either way.
            const muted = root.isMuted(root._appKey(n))
            const show = (!root.quiet && !muted) || critical

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
                root._setLive(rec.key, n)
                const list = root._collapseRepeats([rec].concat(root.records))
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

    // ══ The live objects live BESIDE the records, never inside them ═══════════
    // This is the fix for the shell's recurring SIGSEGV, and it needs stating in
    // full because the old shape looked harmless.
    //
    // A record used to carry `_live`: the real Notification QObject, so a dismiss
    // from the drawer could still tell the app. Records are also what the
    // notification centre renders — `model: Notifications.historyGroups`, whose
    // entries are `{ app, items: [rec…], latest: rec }`. When a Repeater realises a
    // delegate, Qt converts that whole structure into JS, walking every nested map
    // and every value inside it. `_live` was one of those values.
    //
    // Every crash dump says exactly that, identically, four times over:
    //
    //     QQmlVMEMetaObject::writeKnownVarProperty        <- writing modelData
    //       ExecutionEngine::fromData
    //         VariantAssociationPrototype::fromQVariantMap   <- the group map
    //           ExecutionEngine::fromData
    //             VariantAssociationPrototype::fromQVariantMap   <- the record map
    //               ExecutionEngine::fromData             <- SEGV here
    //     …called from QQmlDelegateModel incubation, under polishItems.
    //
    // Two levels of map, then a fault reading a value in the inner one. A QObject
    // pointer that has been destroyed reads back as null from JS, but the QVariant
    // holding it is still a raw pointer, and the conversion dereferences it. So any
    // notification destroyed while its record was still in history armed the centre
    // to crash the next time it built a delegate.
    //
    // Records are now what the file header always claimed they were: PLAIN DATA,
    // strings and numbers, nothing else. The live objects sit in this side table,
    // keyed by the record's own `key`. Nothing binds a model to it, so a
    // Notification is never converted into a delegate's modelData again — the class
    // of bug is gone, not just this instance of it.
    //
    // ASSIGNED, never mutated in place, same rule as `records` and `Config.layout`:
    // `_liveKeys` below is derived from it and would not re-evaluate otherwise.
    property var _liveByKey: ({})

    function _setLive(key, n) {
        const next = {}
        for (const k in root._liveByKey) next[k] = root._liveByKey[k]
        next[key] = n
        root._liveByKey = next
    }

    function _dropLive(key) {
        if (root._liveByKey[key] === undefined) return
        const next = {}
        for (const k in root._liveByKey) if (k !== key) next[k] = root._liveByKey[k]
        root._liveByKey = next
    }

    // The live Notification behind a record, or null. Null covers three cases that
    // all want the same treatment: never had one (restored from disk), released, or
    // destroyed by the server since (JS reads a dead QObject back as null).
    function liveFor(rec) {
        if (!rec) return null
        return root._liveByKey[rec.key] ?? null
    }

    // Which record does this live Notification belong to? Replaces the old
    // `records.find(r => r._live === n)`.
    function _recordForLive(n) {
        if (!n) return null
        for (const k in root._liveByKey)
            if (root._liveByKey[k] === n)
                return root.records.find(r => r.key === k) ?? null
        return null
    }

    function _recordFor(n) {
        return {
            key:     "n" + (root._seq++),
            appName: n.appName || "",
            // The spec's `desktop-entry` hint — the one reliable link from a
            // notification to an app. The dock's badges key on it (appName is a
            // display string and matches far less often).
            desktopEntry: n.desktopEntry || "",
            appIcon: n.appIcon || "",
            summary: n.summary || "",
            body:    n.body || "",
            image:   root._stableImage(n.image),
            urgency: n.urgency,
            time:    Date.now(),
            // Empty for records; the toast reads its actions off the live object.
            actions: []
        }
    }

    function _removeRecord(rec) {
        if (!rec) return
        root._dropLive(rec.key)
        root.records = root.records.filter(r => r.key !== rec.key)
        root._persist()
    }

    // A record is leaving history (evicted past maxHistory) — let go of its live
    // object so the server can drop it. Untrack rather than dismiss(): dismiss tells
    // the app the user closed it, but an eviction is us running out of room, not a
    // user action. A still-shown toast is always among the NEWEST records and never
    // evicted, so this can't yank a toast off screen.
    function _releaseLive(rec) {
        if (!rec) return
        const n = root.liveFor(rec)
        if (n) { try { n.tracked = false } catch (e) {} }
        root._dropLive(rec.key)
    }

    // ── Keep a live record's content current ──────────────────────────────────
    // A replacement mutates the live Notification in place and fires no
    // onNotification (server source), so without this the drawer would freeze at the
    // FIRST version of an updating notification — a download stuck at "0%". One
    // Connections per still-live record refreshes its record when the object changes.
    // Rebuilt only when the SET of live records changes, not on every field tick.
    //
    // Modelled on KEYS — plain strings — not on the records, and certainly not on
    // the Notification objects. An Instantiator builds its delegates through the
    // same QQmlDelegateModel machinery a Repeater does, so a model of objects here
    // would convert them exactly like the centre's Repeater did, and would have been
    // a second route to the same crash.
    readonly property var _liveKeys:
        root.records.filter(r => root._liveByKey[r.key]).map(r => r.key)

    Instantiator {
        model: root._liveKeys
        delegate: Connections {
            required property var modelData          // the record's key
            target: root._liveByKey[modelData] ?? null
            function onSummaryChanged() { root._refreshByKey(modelData) }
            function onBodyChanged()    { root._refreshByKey(modelData) }
            function onImageChanged()   { root._refreshByKey(modelData) }
            function onUrgencyChanged() { root._refreshByKey(modelData) }
        }
    }

    function _refreshByKey(key) {
        root._refreshRecord(root.records.find(r => r.key === key) ?? null)
    }

    function _refreshRecord(rec) {
        const n = root.liveFor(rec)
        if (!n) return
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
        // ── Drop wrappers whose notification died underneath them ─────────────
        // A wrapper is a plain JS object; the Notification inside it is a QObject
        // owned by the server. When that QObject is destroyed the wrapper SURVIVES
        // with `n` reading back as null — and a toast bound to a null notif renders
        // as a blank card: no app name, no summary, no body, just the accent dot and
        // a countdown. That is the empty toast.
        //
        // Swept here rather than at each mutation because this is the one funnel every
        // popup change already passes through.
        const wasEmpty = root.popups.length === 0
        root.popups = p.filter(w => w && w.n)
        if (wasEmpty && root.popups.length > 0)
            root.popupMonitor = Hyprland.focusedMonitor?.name ?? ""
    }

    // ── The safety net for a notification that dies mid-toast ─────────────────
    // `_flushPopups` sweeps dead wrappers, but only when something else changes the
    // popup list. A notification destroyed under a toast with nothing else happening
    // would otherwise sit there blank until its own dwell ran out — up to 5s of empty
    // card. This catches it within a second.
    //
    // Polling, which this shell otherwise avoids: there is no signal for "the server
    // destroyed this object" that can be relied on from out here (Notification exposes
    // trackedChanged, but it fires on the way DOWN, before destruction, and reading
    // meaning into that is guessing at Quickshell internals). Gated on toasts actually
    // being up, so it does not exist at all the vast majority of the time, and it walks
    // at most `maxPopups` (5) entries when it does.
    Timer {
        running: root.popups.length > 0
        interval: 1000
        repeat: true
        onTriggered: {
            const live = root.popups.filter(w => w && w.n)
            if (live.length !== root.popups.length) root._setPopups(live)
        }
    }

    // ── Popup lifecycle ───────────────────────────────────────────────────────
    // Entries are { psid, n } wrappers, NOT the bare live Notification — see the
    // note on `psid` below for why.
    function showPopup(n) {
        const p = root._currentPopups().slice()
        // De-dupe: an app replacing its own notification (same id) shouldn't stack.
        //
        // ── Guarded against id 0 ───────────────────────────────────────────────
        // 0 is never a real assigned id — the freedesktop spec only ever uses it as
        // a REQUEST meaning "give me a fresh one" — so it can't identify anything.
        // Matching on it anyway would fold every notification that happens to read
        // back as id 0 onto whatever popup is already showing, one new toast
        // silently evicting the last: many notifications arrive, only one is ever
        // seen. Comparing real (non-zero) ids still catches a genuine replace.
        // (A snoozed record coming back has no `id` at all, and must not match one that has none.)
        const i = (n.id !== undefined && n.id !== 0) ? p.findIndex(w => w.n.id === n.id) : -1
        if (i >= 0) p.splice(i, 1)
        // Transient ones are the volume / brightness OSDs: a chime for turning the
        // volume up would be the opposite of useful.
        else if (!n.transient) Sfx.play("notify")
        // ── psid: our OWN identity, not the id above ──────────────────────────
        // The overlay's ScriptModel needs a stable per-toast key to diff by (see
        // its own comment). `n.id` isn't trustworthy for that either — the same
        // reasoning as the de-dupe guard just above — so this mints one fresh per
        // popup, the same way `_recordFor` mints `key` instead of trusting `id`.
        p.unshift({ psid: "p" + (root._seq++), n })
        while (p.length > root.maxPopups) {
            const dropped = p.pop()
            if (dropped.n && dropped.n.transient) { try { dropped.n.dismiss() } catch (e) {} }
        }
        root._setPopups(p)
    }

    // ── Closing a toast: ALWAYS by psid, never by the notification ────────────
    // This is the fix for the stuck empty toast, and the reason is worth stating
    // plainly because the old code looked correct.
    //
    // Removal used to be `popups.filter(w => w.n !== n)` — identify the toast by the
    // notification object inside it. That works right up until the notification is
    // destroyed while its toast is still on screen (the app closed it, or its record
    // was evicted and untracked). `n` then reads back as null, and:
    //
    //   • the toast renders blank, because every field it binds is null; and
    //   • the delegate's exit animation ends by calling this with that same null, so
    //     the filter compares `w.n !== null` and matches NOTHING.
    //
    // The wrapper was therefore never removed. The blank card stayed on screen, and
    // because it was still in `popups` it also held a slot in the 5-deep stack — which
    // is why it showed up under BURSTS: the more notifications, the more chances for
    // one to die under its own toast, and each one that did permanently occupied a slot.
    //
    // `psid` is our own key, minted per popup in showPopup(), and a plain string. It
    // cannot go stale, cannot collide, and does not care whether the notification it
    // labels still exists. The overlay already keys its ScriptModel by it for exactly
    // this reason; closing by it too makes the two agree on what identifies a toast.
    //
    // `expire` true  — dwell ran out or it was swiped away KEEPING it: stop the toast,
    //                  keep the record.
    // `expire` false — a real dismiss: drop the record too and tell the app.
    function closePopup(psid, expire) {
        const list = root._currentPopups()
        const w = list.find(x => x.psid === psid) ?? null
        root._setPopups(list.filter(x => x.psid !== psid))

        // No wrapper, or its notification already died — the removal above IS the whole
        // job. Nothing left to tell the app about.
        if (!w || !w.n) return
        const n = w.n

        if (expire) {
            // Keep the live object: its record stays in history and still OWNS it, so a
            // later replacement (replaces_id) collapses onto it and a dismiss from the
            // drawer can still tell the app. A transient toast has no record backing it,
            // so end it for real or it would leak, tracked forever.
            try { if (n.transient) n.dismiss() } catch (e) {}
        } else {
            // A snoozed record that came back is a toast over a plain record: no live object,
            // but its key finds the record.
            const rec = root._recordForLive(n) ?? (n.key ? (root.records.find(r => r.key === n.key) ?? null) : null)
            if (rec) root._removeRecord(rec)
            try { n.dismiss() } catch (e) {}
        }
    }

    // Toast expired or was swiped away KEEPING it. Stops the toast; keeps the record —
    // UNLESS it was transient, which never wanted to be kept.
    //
    // Kept for callers that hold a notification rather than a psid (the centre, the
    // OSD paths). Toasts must use closePopup() above — see its comment for why
    // identifying a toast by its notification is the bug, not the interface.
    //
    // ── Why the try/catch ─────────────────────────────────────────────────────
    // A toast's exit animation now runs for ~200ms BEFORE this fires, and the
    // notification can be gone by then — the app closed it, or a fresh notification
    // rebuilt the popup model and destroyed the delegate. Touching a destroyed
    // Notification throws ("TypeError" on a dead QObject). It's already gone, which
    // is the outcome we wanted, so swallow it rather than let it break the caller.
    function expirePopup(n) {
        if (!n) return
        root._setPopups(root._currentPopups().filter(w => w.n !== n))
        try { if (n.transient) n.dismiss() } catch (e) {}
    }

    // Full dismiss — removes from history. Accepts EITHER a live Notification (a toast's
    // close button or swipe) or a record (the centre's ✕ / middle-click).
    function dismiss(x) {
        if (!x) return
        if (typeof x.dismiss === "function") {
            // Live notification, from a toast.
            root._setPopups(root._currentPopups().filter(w => w.n !== x))
            const rec = root._recordForLive(x)
            if (rec) root._removeRecord(rec)
            try { x.dismiss() } catch (e) {}
        } else {
            // Record, from the centre.
            const live = root.liveFor(x)
            if (live) {
                root._setPopups(root._currentPopups().filter(w => w.n !== live))
                try { live.dismiss() } catch (e) {}
            }
            root._removeRecord(x)
        }
    }

    function dismissAllPopups() {
        const p = root._currentPopups().slice()
        root._setPopups([])
        for (let i = 0; i < p.length; i++)
            if (p[i].n && p[i].n.transient) { try { p[i].n.dismiss() } catch (e) {} }
    }

    // clearHistory / clearApp return what they removed, so the centre can offer it
    // back (restore). The apps were already told; a restored record is plain history.
    function clearHistory() {
        const dropped = root.records
        // Tell any still-live apps, then drop every record in one write.
        for (let i = 0; i < root.records.length; i++) {
            const live = root.liveFor(root.records[i])
            if (live) { try { live.dismiss() } catch (e) {} }
        }
        root._setPopups([])
        root._liveByKey = ({})
        root.records = []
        root._persist()
        return dropped
    }

    // Clear every record belonging to one app — the per-group ✕ in the centre.
    function clearApp(appName) {
        return root.clearRecs(root.records.filter(r => root._appKey(r) === appName))
    }

    // Clear these records — a group's Clear, a selection, an app. Batched: partition once, write
    // once, then tell any live apps. Returns what it removed, for Undo.
    function clearRecs(recs) {
        const gone = ({})
        for (const r of recs) gone[r.key] = true
        const keep = [], drop = []
        for (const r of root.records) (gone[r.key] ? drop : keep).push(r)
        if (drop.length === 0) return []
        root.records = keep
        root._persist()
        for (let i = 0; i < drop.length; i++) {
            const live = root.liveFor(drop[i])
            if (live) {
                root._setPopups(root._currentPopups().filter(w => w.n !== live))
                try { live.dismiss() } catch (e) {}
            }
            // The record is gone from history, so its slot in the side table has to go
            // with it — otherwise the table outlives every record it describes and
            // keeps the notifications tracked forever.
            root._dropLive(drop[i].key)
        }
        return drop
    }

    // ── Snooze ────────────────────────────────────────────────────────────────
    // Takes a notification out of the history for a while and brings it back — at the top, as
    // new, with a toast (unless the machine is quiet by then) — when the time is up. The app is
    // NOT told it was dismissed (it is untracked, like an eviction): snoozing is the user
    // deferring it, not closing it, so a chat app keeps its unread. The live object is let go, so
    // a woken record is plain history: its actions are gone, as after a reload.
    // Persisted, so a reload doesn't eat a snooze.
    property var snoozed: []      // [{ rec, wakeAt }]
    function snooze(rec, minutes) {
        if (!rec) return
        root._releaseLive(rec)
        root._setPopups(root._currentPopups().filter(w => !w.n || w.n.key !== rec.key))
        root.snoozed = root.snoozed.concat([{ rec: root._strip(rec), wakeAt: Date.now() + minutes * 60000 }])
        root._removeRecord(rec)        // writes the document, snoozed list included
    }
    function _wake() {
        const sp = View.splitSnoozed(root.snoozed, Date.now())
        if (sp.due.length === 0) return
        root.snoozed = sp.waiting
        const now = Date.now()
        // Oldest-snoozed first, each a millisecond newer than the last, so they keep their order.
        const back = sp.due.map((s, i) => Object.assign({}, s.rec, { key: "n" + (root._seq++), time: now + i }))
        const list = root._collapseRepeats(back.slice().reverse().concat(root.records))
        while (list.length > root.maxHistory) root._releaseLive(list.pop())
        root.records = list
        root._persist()
        // showPopup puts each on top, so the last one shown ends up first.
        if (!root.quiet) for (const r of back) root.showPopup(r)
    }
    Connections {
        target: Clock
        function onNowChanged() { root._expireDnd(); root._wake() }
    }

    // Reply from the centre: only while the app still holds the notification AND offers a
    // reply (Notification.hasInlineReply). Done with it afterwards, like an action.
    function reply(rec, text) {
        const live = root.liveFor(rec)
        if (!live || !live.hasInlineReply || String(text).trim() === "") return
        live.sendInlineReply(text)
        root.dismiss(rec)
    }

    // Put removed records back — the centre's Undo. Merged by time, so they land where
    // they were; a key already present (restored twice) is skipped. They come back as
    // records only: the apps were told they were dismissed, so their actions are gone.
    function restore(recs) {
        if (!recs || recs.length === 0) return
        const have = ({})
        for (const r of root.records) have[r.key] = true
        const list = root.records.concat(recs.filter(r => !have[r.key]))
        list.sort((a, b) => b.time - a.time)
        while (list.length > root.maxHistory) root._releaseLive(list.pop())
        root.records = list
        root._persist()
    }

    function invoke(action) { if (action) action.invoke() }

    // The freedesktop "default" action — what clicking the notification means.
    // `actions` is a QList<NotificationAction*>, not a JS array: it has `.length` and
    // index access but none of the Array methods, so `.find()` throws.
    function defaultAction(n) {
        const a = n ? n.actions : null
        if (!a) return null
        for (let i = 0; i < a.length; i++)
            if (a[i].identifier === "default") return a[i]
        return null
    }

    // A click on a record in the centre. While the app still holds the notification,
    // its default action — what clicking the toast does. Once only the record is left
    // (a reload, or the app let it go), the app itself: Taskbar focuses its window or
    // starts it, keyed the way the dock's badges are. Either way the row has done its
    // job and leaves history.
    function activate(rec) {
        if (!rec) return
        const def = root.defaultAction(root.liveFor(rec))
        if (def) def.invoke()
        else Taskbar.activate(Taskbar.keyForAny([rec.desktopEntry, rec.appName]))
        root.dismiss(rec)
    }

    // "now" / "5m" / "3h" / "2d" since an epoch-ms time. Bind through Clock.now to tick.
    function ago(t) {
        const s = Math.max(0, Math.floor((Date.now() - t) / 1000))
        if (s < 60)    return "now"
        if (s < 3600)  return Math.floor(s / 60) + "m"
        if (s < 86400) return Math.floor(s / 3600) + "h"
        return Math.floor(s / 86400) + "d"
    }

    // ── Persistence ───────────────────────────────────────────────────────────
    // dnd AND the history records live in one document. A PersistentProperties block
    // has no disk I/O — it survives a hot reload and nothing else — so this is a
    // JsonStore (FileView, atomic, debounced), its own file, one writer, no watch.
    JsonStore {
        id: store
        path: Quickshell.statePath("notifications.json")
        onLoaded: {
            const v = store.value ?? ({})

            // ── Anything that arrived while the file was still being read ─────
            // The server binds the D-Bus name the moment the shell loads, so it can
            // receive a notification BEFORE this read completes — and login, when a
            // dozen autostarted things announce themselves, is exactly that window.
            // `root.records = out` used to overwrite the list outright, so those
            // notifications toasted normally and then were simply not in history.
            const early = root.records

            root._loading = true
            root.dnd  = v.dnd ?? root.dnd
            root.dndUntil = v.dndUntil ?? 0
            root.mutedApps = v.muted ?? []
            root.snoozed = (v.snoozed ?? []).filter(s => s && s.rec && s.wakeAt > 0)
            // A document from before `seenAt` existed: what's there was seen already
            // (otherwise the first launch after an upgrade badges the whole history).
            root.seenAt = v.seenAt !== undefined ? Math.max(root.seenAt, v.seenAt) : Date.now()
            // Never backwards. `_seq` also mints popup keys, and an early record has
            // already taken one from a counter that started at 0 — so the restored
            // value can be BEHIND where we actually are.
            root._seq = Math.max(root._seq, v.seq ?? 0)
            // Rehydrate into clean records: nothing is live yet (the side table starts
            // empty and is only filled by onNotification), and an
            // empty `actions` (restored callbacks are gone). Defaults guard a partial
            // or older file.
            const src = v.records ?? []
            const out = []
            for (let i = 0; i < src.length; i++) {
                const r = src[i]
                out.push({
                    key:     r.key ?? ("r" + i),
                    appName: r.appName || "",
                    desktopEntry: r.desktopEntry || "",
                    appIcon: r.appIcon || "",
                    summary: r.summary || "",
                    body:    r.body || "",
                    // Scrub any volatile provider url a previous version may have saved
                    // — those are the dead handles behind the "unknown handle" flood.
                    image:   root._stableImage(r.image || ""),
                    urgency: r.urgency ?? NotificationUrgency.Normal,
                    time:    r.time ?? 0,
                    actions: []
                })
            }
            // Re-key the early arrivals off the restored counter. They were minted from
            // a counter starting at 0, so "n0"/"n1" almost certainly already belong to
            // a restored record — and `_removeRecord` filters by key, so one duplicate
            // would make dismissing either row delete both.
            for (let i = 0; i < early.length; i++)
                early[i].key = "n" + (root._seq++)

            // Early arrivals are the NEWEST, so they lead. Trimmed to the same bound
            // every other write respects; the tail being dropped here is restored
            // records, which hold no live object to release.
            root.records = root._collapseRepeats(early.concat(out)).slice(0, root.maxHistory)
            root._loading = false
            // A "for an hour" that ran out while the shell was off, a snooze that came due.
            root._expireDnd()
            root._wake()

            // The merge above is a real change to what's on disk (re-keyed early
            // records, a possibly advanced seq), and nothing else would write it until
            // the next notification arrived.
            root._persist()
        }
    }

    property bool _loading: false

    // Strip the fields that shouldn't be serialised: `actions` is empty for records and
    // rebuilt on load. (There is no QObject to strip any more — that's the point of the
    // `_liveByKey` side table.)
    function _strip(r) {
        return {
            key: r.key, appName: r.appName, desktopEntry: r.desktopEntry, appIcon: r.appIcon,
            summary: r.summary, body: r.body, image: r.image,
            urgency: r.urgency, time: r.time
        }
    }

    function _persist() {
        if (root._loading || !store.ready) return
        store.value = {
            dnd:     root.dnd,
            dndUntil: root.dndUntil,
            muted:   root.mutedApps,
            snoozed: root.snoozed,
            seq:     root._seq,
            seenAt:  root.seenAt,
            records: root.records.map(root._strip)
        }
    }

    onDndChanged: root._persist()
}
