pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import QtQuick
import "dock.js" as DockJs
import "xbel.js" as Xbel

// ── Taskbar ───────────────────────────────────────────────────────────────────
// What the dock knows: which apps to draw, in what order, which of their windows
// is where, and what a click on one does. Both docks — the persistent one
// (modules/bar/DockHost) and the overview's (OverviewDock) — draw this through
// the shared DockIconStrip, and neither holds any of it.
//
// The ordering, grouping, cycling and drag arithmetic is in dock.js, where
// `bun scripts/test-dock.js` can reach it. This file only gathers the facts and
// dispatches.
//
// ── Event-driven, with no refresh loop ────────────────────────────────────────
// The dock used to group `Hypr.windows`, whose app class comes out of each
// toplevel's `lastIpcObject` — which Quickshell only fills after
// `refreshToplevels()`, so the persistent dock held Hypr's 250ms refresh loop
// for as long as it was enabled: four socket round-trips a second, forever, to
// learn the app of each window. Everything needed here is pushed over the event
// socket instead: `wayland.appId` (the foreign-toplevel handle's app id — the
// same class hyprctl reports, XWayland included), `activated`, `urgent` and
// `workspace` all notify on their own. `lastIpcObject` is read only in the
// instant before a new window's wayland handle is matched.
//
// ── One key per app: its desktop-entry id ─────────────────────────────────────
// A window reports a CLASS ("Spotify", "org.gnome.Nautilus"); the launcher pins
// by desktop-entry ID ("spotify"). keyFor() maps both onto the entry id whenever
// an entry matches, so a pinned app and its running window are recognised as the
// same app, and a pin made in the dock is one the launcher can resolve. Apps with
// no desktop entry keep their class — they still show, they just can't be
// launched or pinned (see canPin).
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ══ Canonical keys ════════════════════════════════════════════════════════
    // Memoised: keyFor() runs for every window on every regroup. Dropped whenever
    // the entry set changes — the scan is asynchronous, so a key resolved before
    // it lands is the raw class, and a newly installed app can claim a class too.
    // Reassigned rather than cleared in place so the bindings that read it (via
    // keyFor) re-run and pick the fresh answers up.
    // Null-prototype, like every app-keyed map here: an app id is an arbitrary
    // string, and on a plain {} a key like "constructor" is found before anything
    // was ever put there.
    property var _keyCache: Object.create(null)

    function keyFor(appId) {
        if (!appId) return ""
        const hit = root._keyCache[appId]
        if (hit !== undefined) return hit
        const entry = DesktopEntries.heuristicLookup(appId)
        const key = entry ? entry.id : appId
        root._keyCache[appId] = key
        return key
    }

    // byId first: a canonical key IS an entry id, and heuristicLookup would also
    // accept it but walks every entry's StartupWMClass on a miss.
    function entryFor(key) {
        if (!key) return null
        return DesktopEntries.byId(key) ?? DesktopEntries.heuristicLookup(key)
    }

    function nameFor(key) { return Icons.nameForAppId(key) }
    function iconFor(key) { return Icons.pathForAppId(key) }

    // Launching and pinning both need a desktop entry to exist — pinning because a
    // pin is only useful if clicking it can start the app again. The strip greys
    // the menu item out with this as its reason rather than offering a pin that
    // could never launch.
    function canPin(key) { return root.entryFor(key) !== null }

    // The entry's own actions (Desktop Action groups): "New Window", "New Private
    // Window", and so on — what Windows calls the jump list.
    function actionsFor(key) {
        const entry = root.entryFor(key)
        return entry ? entry.actions : []
    }

    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() {
            root._keyCache = Object.create(null)
            root._migratePins()
        }
    }

    // ══ Focus recency ═════════════════════════════════════════════════════════
    // address → a counter bumped each time that window takes focus. A plain click
    // on an app goes to its most recently focused window (Windows does the same);
    // Hyprland keeps that history too, but only in `lastIpcObject`, which is the
    // refresh loop this file exists to avoid. Tracked from the moment the shell
    // starts, which is as far back as it matters.
    property var _seq: ({})
    property int _seqTop: 0

    function _touch(t) {
        if (!t || !t.address) return
        const next = Object.assign({}, root._seq)
        next[t.address] = ++root._seqTop
        root._seq = next
    }

    Connections {
        target: Hyprland
        function onActiveToplevelChanged() {
            root._touch(Hyprland.activeToplevel)
            root._seeActive()
        }
    }

    // Closed windows drop out of the history, so it can't grow for the life of the
    // session.
    Connections {
        target: Hyprland.toplevels
        function onValuesChanged() {
            const live = Hyprland.toplevels.values
            const next = {}
            for (let i = 0; i < live.length; i++) {
                const a = live[i].address
                if (root._seq[a] !== undefined) next[a] = root._seq[a]
            }
            if (Object.keys(next).length !== Object.keys(root._seq).length)
                root._seq = next
        }
    }

    Component.onCompleted: {
        root._touch(Hyprland.activeToplevel)
        root._seeActive()
        root._migratePins()
    }

    // ══ Windows, grouped by app ═══════════════════════════════════════════════
    // Re-evaluates on its own whenever a window opens or closes, takes focus, asks
    // for attention, or changes workspace — every one of those reads below is a
    // notifying property. Title is deliberately NOT read here: titles change
    // constantly (a terminal's, a browser tab's) and nothing about grouping depends
    // on them; the preview tiles bind a window's title themselves.
    //
    // Special workspaces (scratchpads) have negative ids and are left out, the same
    // rule Hypr.windows applies: a scratchpad terminal is a tool, not a task.
    readonly property var _grouped: {
        const seq = root._seq
        const tops = Hyprland.toplevels.values
        const items = []
        for (let i = 0; i < tops.length; i++) {
            const t = tops[i]
            const ws = t.workspace
            if (!ws || ws.id < 0) continue

            // `class` by bracket, same as Hypr.geometryOf: it's a reserved word.
            const ipc = t.wayland ? null : t.lastIpcObject
            const appId = t.wayland ? t.wayland.appId : (ipc ? (ipc["class"] ?? "") : "")
            const key = root.keyFor(appId)
            if (!key) continue

            items.push({ key: key, ref: t, activated: t.activated, urgent: t.urgent,
                         seq: seq[t.address] ?? 0, monitor: t.monitor?.name ?? "",
                         workspace: ws.id })
        }
        return { all: DockJs.group(items), perMonitor: DockJs.groupPerMonitor(items),
                 perWorkspace: DockJs.groupBy(items, "workspace") }
    }

    // key → { key, windows, recent, focused, urgent, count }. A fresh object on
    // every regroup: bind to `groups[key]`, and hand `windows` to a ScriptModel
    // (it diffs by identity, so a preview's live captures survive the regroup).
    readonly property var groups:  root._grouped.all.byKey
    // Running apps, first-seen order.
    readonly property var running: root._grouped.all.order

    // The same, split by monitor name — { name: { order, byKey } } — for a dock set
    // to show only the windows on its own screen (Config.dockScope).
    readonly property var monitorGroups: root._grouped.perMonitor
    // …and by workspace id, for "this workspace only" (Config.dockScope).
    readonly property var workspaceGroups: root._grouped.perWorkspace

    // Pins, canonicalised. Written back through pin()/unpin()/movePin() only, so
    // the file converges on entry ids.
    readonly property var pinned: DockJs.dedupe(Pins.ids.map(id => root.keyFor(id)))

    // What the dock draws, in order — see dock.js order(). Unique keys, so it can
    // feed a ScriptModel directly.
    readonly property var apps: DockJs.order(root.pinned, root.running)

    function isPinned(key) { return root.pinned.indexOf(key) >= 0 }
    // Whether the dock draws this app at all: pinned, or running (dock.js order()). Whether
    // there IS a dock on the edge is Config's (dockEnabled) — the caller asks that.
    function onDock(key) { return !!key && (root.isPinned(key) || root.groups[key] !== undefined) }
    function groupFor(key) { return root.groups[key] ?? null }

    // ══ Things known by other names ═══════════════════════════════════════════
    // A PipeWire stream, an MPRIS player and a notification each name their app
    // their own way (a binary, a desktop entry, a display name). This tries each
    // candidate against the dock's keys and prefers one that's RUNNING, so a stream
    // from "zen-bin" lands on the "zen" icon rather than on a key of its own that
    // no button draws. Falls back to the first candidate's key.
    function keyForAny(names) {
        const cands = DockJs.idCandidates(names)
        for (let i = 0; i < cands.length; i++) {
            const k = root.keyFor(cands[i])
            if (root.groups[k]) return k
        }
        return cands.length > 0 ? root.keyFor(cands[0]) : ""
    }

    // ══ Sound ═════════════════════════════════════════════════════════════════
    // key → { streams, muted, level }: which apps are playing audio right now —
    // the speaker on their icon, and what scrolling over them turns up or down.
    // Audio already tracks every node (its PwObjectTracker), so `audio.muted` and
    // the volumes read here are live.
    readonly property var audio: {
        const ss = Audio.streams
        const items = []
        for (let i = 0; i < ss.length; i++) {
            const n = ss[i]
            const p = n.properties || {}
            items.push({
                key: root.keyForAny([Audio.appIdFor(n), p["application.process.binary"],
                                     p["application.id"], p["application.name"]]),
                ref: n,
                muted: n.audio?.muted ?? false,
                level: Audio.levelOf(n)
            })
        }
        return DockJs.audioByKey(items)
    }

    function toggleMute(key) {
        const a = root.audio[key]
        if (!a) return
        const to = !a.muted
        for (let i = 0; i < a.streams.length; i++)
            if (a.streams[i].audio) a.streams[i].audio.muted = to
    }

    // One scroll notch on an app: exactly what the bar's media pill does to its
    // player — every one of the app's streams stepped from ITS OWN level by
    // Audio.steppedLevel (5% steps that land on multiples of 5), mute left alone.
    // Returns { level, muted } of the first stream for the OSD, or null.
    function stepVolume(key, up) {
        const a = root.audio[key]
        if (!a || a.streams.length === 0) return null
        for (let i = 0; i < a.streams.length; i++) {
            const n = a.streams[i]
            Audio.setNodeVolume(n, Audio.steppedLevel(Audio.levelOf(n), up), false)
        }
        const first = a.streams[0]
        return { level: Audio.levelOf(first), muted: first.audio ? first.audio.muted : false }
    }

    // ══ Media ═════════════════════════════════════════════════════════════════
    // key → the MPRIS player the preview's controls reach (the playing one, if the
    // app exposes several — a browser does, per tab).
    readonly property var players: {
        const ps = Mpris.players.values
        const items = []
        for (let i = 0; i < ps.length; i++) {
            const p = ps[i]
            items.push({ key: root.keyForAny([p.desktopEntry, p.identity]),
                         ref: p, playing: p.isPlaying })
        }
        return DockJs.playerByKey(items)
    }

    function media(key, action) {
        const p = root.players[key]
        if (!p) return
        switch (action) {
            case "toggle":   if (p.canTogglePlaying) p.togglePlaying(); break
            case "next":     if (p.canGoNext)        p.next();          break
            case "previous": if (p.canGoPrevious)    p.previous();      break
        }
    }

    // ══ Notification badges ═══════════════════════════════════════════════════
    // key → how many notifications arrived since that app was last in front of
    // you (and since the shell started — restored history isn't news). Nothing is
    // dismissed to clear a badge: looking at the app is what clears it, and the
    // notifications stay in the centre's history.
    readonly property double _since: Date.now()
    property var _seenAt: Object.create(null)
    property string _activeKey: ""

    // Both ends of a focus change count as "seen now": the app you just left saw
    // everything up to this moment, and the one you arrived at is in front of you.
    function _seeActive() {
        const t = Hyprland.activeToplevel
        const key = t ? root.keyFor(t.wayland ? t.wayland.appId : "") : ""
        const now = Date.now()
        const next = Object.assign(Object.create(null), root._seenAt)
        if (root._activeKey !== "") next[root._activeKey] = now
        if (key !== "") next[key] = now
        root._activeKey = key
        root._seenAt = next
    }

    readonly property var badges: {
        const recs = Notifications.records
        const items = []
        for (let i = 0; i < recs.length; i++)
            items.push({ key: root.keyForAny([recs[i].desktopEntry, recs[i].appName]),
                         time: recs[i].time })
        return DockJs.badgeCounts(items, root._seenAt, root._since)
    }

    // ══ What apps report about themselves ═════════════════════════════════════
    // key → LauncherEntry state { count, countVisible, progress, progressVisible,
    // urgent }: a download's progress, Telegram's unread count, "look at me".
    readonly property var reported: {
        const e = LauncherEntry.entries
        const out = Object.create(null)
        for (const id in e) {
            const k = root.keyForAny([id])
            if (k) out[k] = e[id]
        }
        return out
    }

    // ══ Windows, stepped ══════════════════════════════════════════════════════
    // Scrolling over a running app: its next (or previous) window. A lone window
    // is simply brought forward.
    function cycleWindows(key, dir, monitor, groups) {
        const g = (groups ?? root.groups)[key] ?? root.groups[key]
        if (!g) return
        const t = DockJs.cycle(g.windows, Hyprland.activeToplevel, dir)
        root.focus(t ?? (g.focused ? null : g.windows[0]), monitor)
    }

    // ══ Launch feedback ═══════════════════════════════════════════════════════
    // key → when it was launched, for an app that has no window yet. The icon
    // pulses until its first window lands, so a slow-starting app doesn't look
    // like a click that did nothing. Cleared by the window arriving, or by the
    // timeout for an app that never opens one (it failed, or its window class
    // doesn't lead back to the entry that launched it).
    property var launching: Object.create(null)
    readonly property int launchTimeout: 15000

    function isLaunching(key) { return root.launching[key] !== undefined }

    function _settleLaunches() {
        const keys = Object.keys(root.launching)
        if (keys.length === 0) return
        const now = Date.now()
        const next = Object.create(null)
        let changed = false
        for (let i = 0; i < keys.length; i++) {
            const k = keys[i]
            if (root.groups[k] || now - root.launching[k] >= root.launchTimeout) changed = true
            else next[k] = root.launching[k]
        }
        if (changed) root.launching = next
    }

    onGroupsChanged: root._settleLaunches()

    // Only the timeout needs a timer — a window arriving is already an event. A
    // coarse repeating sweep, alive only while something is launching, rather than
    // a single-shot aimed at the deadline: QTimer may fire a few percent early, and
    // a sweep that found nothing due yet would leave the icon pulsing for good.
    Timer {
        interval: 1000
        repeat: true
        running: Object.keys(root.launching).length > 0
        onTriggered: root._settleLaunches()
    }

    // ══ Actions ═══════════════════════════════════════════════════════════════
    // A plain click on an app, in Windows' terms:
    //   not running          → launch it
    //   running, not focused → its most recently focused window
    //   running, focused     → the next of its windows (Hyprland has no minimize,
    //                          so this cycles instead; one window → nothing)
    // `monitor` is the monitor the click came from — see Hypr.goToToplevel.
    // `groups` is the caller's view (a per-monitor dock's); an app it doesn't have
    // falls back to the whole session's, so a pin for an app open on ANOTHER screen
    // switches to it rather than starting a second copy.
    function activate(key, monitor, groups) {
        const g = (groups ?? root.groups)[key] ?? root.groups[key]
        if (!g) return root.launch(key)
        if (g.focused) {
            const n = DockJs.next(g.windows, Hyprland.activeToplevel)
            if (n) root.focus(n, monitor)
        } else {
            root.focus(g.recent, monitor)
        }
        return true
    }

    // Start the app — a second instance if it's already running (middle-click,
    // the menu's "New window"). False when there is no entry to start it from.
    function launch(key) {
        const entry = root.entryFor(key)
        if (!entry) return false
        entry.execute()
        if (!root.groups[key]) {
            const next = Object.assign(Object.create(null), root.launching)
            next[key] = Date.now()
            root.launching = next
        }
        return true
    }

    // ══ Files ═════════════════════════════════════════════════════════════════
    // "Open this with that app": a file dropped on its icon, a recent file in its
    // jump list. Built from the entry's own Exec line (dock.js execArgv — spec
    // field codes and quoting), because DesktopEntry.execute() takes no files.
    //
    // Refused, not attempted, when the app can't take a file: its Exec has no file
    // code (it would start and ignore the file — a drop that looks like it
    // worked), or it runs in a terminal (the argv would need wrapping in one).
    function acceptsFiles(key) {
        const e = root.entryFor(key)
        return e !== null && !e.runInTerminal && DockJs.execArgv(e.execString, []).acceptsFiles
    }

    function openWith(key, paths) {
        const e = root.entryFor(key)
        if (!e || e.runInTerminal || paths.length === 0) return false
        const r = DockJs.execArgv(e.execString, paths)
        if (!r.acceptsFiles || r.argv.length === 0) return false
        Quickshell.execDetached(r.argv)
        return true
    }

    // The files this app opened most recently (newest first) — the jump list's
    // "Recent". Asked when a menu opens, never bound: the store is parsed lazily.
    readonly property int recentLimit: 5
    function recentFor(key) {
        const all = Xbel.byApp(Recents.entries(), names => root.keyForAny(names), root.recentLimit)
        return all[key] ?? []
    }

    function runAction(key, index) {
        const actions = root.actionsFor(key)
        if (index < 0 || index >= actions.length) return
        actions[index].execute()
    }

    function focus(toplevel, monitor) { if (toplevel) Hypr.goToToplevel(toplevel, monitor) }
    function close(toplevel)          { if (toplevel) Hypr.closeWindow(toplevel.address) }

    // Bring a window to the workspace you're looking at — the one showing on the
    // dock's monitor (the focused workspace if that's unknown) — and focus it there.
    // Already here: just focus it.
    function bringHere(toplevel, monitor) {
        if (!toplevel) return
        const here = monitor?.activeWorkspace?.id ?? Hypr.focusedWorkspaceId
        if (here === undefined || here === null || here < 0) return
        if ((toplevel.workspace?.id ?? -1) !== here)
            Hypr.moveWindowToWorkspace(toplevel.address, here)
        Hypr.focusWindow(toplevel.address)
    }

    function closeAll(key, groups) {
        const g = (groups ?? root.groups)[key]
        if (!g) return
        // Snapshot first: each close regroups, re-deriving g.windows under the loop.
        const addrs = g.windows.map(t => t.address)
        for (let i = 0; i < addrs.length; i++) Hypr.closeWindow(addrs[i])
    }

    // ══ Pins ══════════════════════════════════════════════════════════════════
    // All three write the CANONICAL list, so each edit also finishes migrating any
    // class-keyed pins it touches.
    function pin(key, at) {
        if (!key || !root.canPin(key)) return
        const next = root.pinned.filter(k => k !== key)
        const i = (at === undefined || at < 0) ? next.length : Math.min(at, next.length)
        next.splice(i, 0, key)
        Pins.replace(next)
    }

    function unpin(key) {
        if (!root.isPinned(key)) return
        Pins.replace(root.pinned.filter(k => k !== key))
    }

    // Remove-then-insert, with `to` read against the final list — the index the
    // dragged icon was dropped on (see dock.js dropTarget/shift, which draw it).
    function movePin(from, to) {
        const next = root.pinned.slice()
        if (from < 0 || from >= next.length || from === to) return
        const moved = next.splice(from, 1)[0]
        next.splice(Math.max(0, Math.min(to, next.length)), 0, moved)
        Pins.replace(next)
    }

    // ── One-time migration of class-keyed pins ────────────────────────────────
    // The old dock pinned by window class, the launcher by entry id, into the same
    // file. Once both the file and the entry scan have answered, the stored list is
    // rewritten as entry ids (order kept, duplicates collapsed to the first) —
    // after which the launcher's pin strip finds pins the dock made, and vice versa.
    //
    // Waits on BOTH: before the file loads there is nothing to migrate (and writing
    // would replace the user's pins with an empty list); before the scan lands every
    // key resolves to itself and the rewrite would be a no-op that then never runs
    // again. A pin whose app is no longer installed resolves to itself and is kept.
    property bool _pinsMigrated: false

    function _migratePins() {
        if (root._pinsMigrated || !Pins.loaded) return
        if (DesktopEntries.applications.values.length === 0) return
        root._pinsMigrated = true

        const canonical = DockJs.dedupe(Pins.ids.map(id => root.keyFor(id)))
        if (JSON.stringify(canonical) !== JSON.stringify(Pins.ids))
            Pins.replace(canonical)
    }

    Connections {
        target: Pins
        function onLoadedChanged() { root._migratePins() }
    }
}
