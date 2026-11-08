pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../config"
import "screentime.js" as St

// ── ScreenTime ────────────────────────────────────────────────────────────────
// How long you spend in each app: the sidebar's Screen time module (SideScreenTime →
// ScreenTimePanel) and Settings › Sidebar › Screen time (ScreenTimePage) are the views.
//
// ── What counts ───────────────────────────────────────────────────────────────
// The FOCUSED window's app (Hyprland.activeToplevel — an event, nothing polled), while
// you're not away: an IdleMonitor (`Config.screenTimeIdleMinutes`, respecting inhibitors,
// so a video you're watching still counts) and not while locked. The running span is
// credited every `tick` and on every change; a span longer than two ticks (a suspend) is
// clipped, so a closed lid isn't an afternoon in Firefox.
//
// ── What's kept ───────────────────────────────────────────────────────────────
// `Quickshell.statePath("screen-time.json")`: { version, days: { "YYYY-MM-DD": { app id:
// seconds } } } — app ids and seconds, never a window title, `Config.screenTimeKeepDays`
// of them. Written once a minute (a JsonStore, debounced), not per tick. Off by default
// (`Config.screenTime`): nothing is recorded until you turn it on.
//
// Eager in shell.qml so it counts from launch whether or not a view is open. Logic:
// screentime.js (`bun scripts/test-screentime.js`). Diagnose: `qs ipc -c
// ~/.config/quicktest call screentime status` (counts only, never an app name).
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property bool enabled: Config.screenTime
    readonly property int tick: 30000
    readonly property int flushMs: 60000

    JsonStore {
        id: store
        path: Quickshell.statePath("screen-time.json")
        defaults: ({ version: 1, days: {} })
        onLoaded: if (!root.loaded) { root.days = St.clean(store.value); root.loaded = true }
    }
    Component.onCompleted: if (store.ready && !root.loaded) { root.days = St.clean(store.value); root.loaded = true }

    // In memory, ahead of the file by at most a flush.
    property var days: ({})
    property bool loaded: false
    property bool _dirty: false

    // ── Counting ──────────────────────────────────────────────────────────────
    // `?? ""` outside too: this is a `string`, and a toplevel with no app id yet must give "" and not `undefined`.
    readonly property string app: St.appKey(Hyprland.activeToplevel?.wayland?.appId ?? "") ?? ""
    readonly property bool away: idle.isIdle || Lock.locked
    readonly property bool counting: root.enabled && root.loaded && root.app !== "" && !root.away

    property string _app: ""
    property real _since: 0

    // Credit what's been running and start the next span.
    function _settle() {
        const now = Date.now()
        if (root._app !== "" && root._since > 0) {
            root.days = St.credit(root.days, root._app, root._since, now, root.tick * 2 + 5000)
            root._dirty = true
        }
        root._app = root.counting ? root.app : ""
        root._since = now
    }
    onCountingChanged: root._settle()
    onAppChanged: root._settle()

    Timer {
        interval: root.tick
        repeat: true
        running: root.counting
        onTriggered: root._settle()
    }
    Timer {
        interval: root.flushMs
        repeat: true
        running: root.enabled
        onTriggered: root._flush()
    }
    function _flush() {
        if (!root._dirty) return
        root.days = St.prune(root.days, Config.screenTimeKeepDays, Date.now())
        store.value = ({ version: 1, days: root.days })
        root._dirty = false
    }
    Component.onDestruction: { root._settle(); root._flush(); store.flush() }

    IdleMonitor {
        id: idle
        enabled: root.enabled
        timeout: Math.max(60, Config.screenTimeIdleMinutes * 60)
        respectInhibitors: true
    }

    // ── What the views read ───────────────────────────────────────────────────
    // Clock ticks once a minute; `days` moves every tick while counting.
    readonly property string todayKey: St.dayKey(Clock.now.getTime())
    readonly property var today: root.days[root.todayKey] ?? ({})
    readonly property real todayTotal: St.total(root.today)
    readonly property var week: St.lastDays(root.days, Clock.now.getTime(), 7)
    readonly property real weekAverage: {
        let s = 0, n = 0
        for (const d of root.week) if (d.seconds > 0) { s += d.seconds; n++ }
        return n > 0 ? s / n : 0
    }

    function dayFor(key) { return root.days[key] ?? ({}) }

    // ── Names for what ran ────────────────────────────────────────────────────
    // A Steam game's window class is `steam_app_<id>`; its title is in the library's
    // appmanifest. Read once, the first time a list asks for one (nothing at all for someone
    // who never plays through Steam), then answered from memory. Paths are arguments, never
    // spliced into the script.
    property var  gameNames: ({})
    // A plain object, not a property: nameOf() is called from bindings, and a property read
    // AND written there would be a binding loop. The write is deferred out of the evaluation.
    readonly property var _asked: ({ done: false })
    function nameOf(app) {
        const g = St.gameName(app, root.gameNames)
        if (g !== "" && St.steamId(app) !== "" && !root._asked.done) {
            root._asked.done = true
            Qt.callLater(function () { steamNames.running = true })
        }
        return g
    }
    Process {
        id: steamNames
        command: ["sh", "-c",
            'for base in "$1/Steam" "$2/.steam/steam" "$2/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do '
            + '[ -d "$base/steamapps" ] || continue; '
            + '{ echo "$base"; sed -n \'s/.*"path"[[:space:]]*"\\(.*\\)"/\\1/p\' "$base/steamapps/libraryfolders.vdf" 2>/dev/null; } '
            + '| while IFS= read -r lib; do grep -sm1 -H \'"name"\' "$lib"/steamapps/appmanifest_*.acf; done; done; exit 0',
            "sh",
            Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share"),
            Quickshell.env("HOME") || ""]
        stdout: StdioCollector { onStreamFinished: root.gameNames = St.steamNames(text) }
    }
    function topApps(key, n) { return St.top(root.dayFor(key), n) }
    function duration(s) { return St.duration(s) }
    function short(s) { return St.short(s) }
    // Today's seconds for one app id (a window's class), 0 for one never counted.
    function todayFor(appId) {
        const k = St.appKey(appId)
        return k !== "" ? (root.today[k] ?? 0) : 0
    }

    // Forget everything recorded (the page's ArmLatch).
    function clear() {
        root._settle()
        root.days = ({})
        store.value = ({ version: 1, days: {} })
        root._dirty = false
    }

    IpcHandler {
        target: "screentime"
        function status(): string {
            return "enabled=" + root.enabled + " loaded=" + root.loaded + " counting=" + root.counting
                 + " away=" + root.away + " days=" + Object.keys(root.days).length
                 + " appsToday=" + Object.keys(root.today).length
                 + " minutesToday=" + Math.floor(root.todayTotal / 60)
        }
    }
}
