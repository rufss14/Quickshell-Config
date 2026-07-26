pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// ── UiState ───────────────────────────────────────────────────────────────────
// The single answer to "what is the shell currently showing".
//
// This state used to live in three places: `barShape`/`barMode` were per-screen
// PersistentProperties inside StatusBarRoot — a *global* preference stored once
// per monitor, so two monitors could disagree — and every panel's open/closed flag
// lived in a `Panels` singleton buried in overlay/modules/.
//
// It is all here now, and nowhere else.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ══ Panels ════════════════════════════════════════════════════════════════
    // Which screen owns the currently-open panels. Panels render only on this
    // screen; null means "all screens" (an IPC/keybind invocation has no screen
    // context to attribute).
    property var activeScreen: null

    // Left group — mutually exclusive
    property bool wallpaperOpen:   false
    property bool colorSchemeOpen: false
    property bool equalizerOpen:   false

    // Right group. Only wifi lives here now — the clock button toggles the
    // desktop clock instead, and the calendar moved into the overview.
    property bool wifiOpen: false

    // Center — system update
    property bool updateOpen:         false
    property int  pendingUpdateCount: 0
    // Bumped on every click. A plain boolean toggle wouldn't fire a change when
    // clicked twice in a row, so re-clicking Update while it's already open would
    // do nothing instead of restarting the check.
    property int  updateRequestId:    0

    // ── Desktop clock ─────────────────────────────────────────────────────────
    // A background-layer surface, not a panel: it sits behind every window and is
    // toggled by the bar's clock pill. Transient by design — restoring it across a
    // reload would be surprising.
    property bool desktopClockOpen: false
    function toggleDesktopClock() { root.desktopClockOpen = !root.desktopClockOpen }

    // Standalone overlays
    property bool launcherOpen: false

    // ── Desktop widget arrange mode ───────────────────────────────────────────
    // Transient by design: it is a mode you are IN, not a setting. Restoring it across
    // a reload would drop you onto a dimmed desktop with a grid on it and no memory of
    // asking for that. Entering it closes the overview — the settings page that starts
    // it is inside an overlay covering the very desktop you are arranging.
    property bool widgetArrange: false
    function startArranging() {
        root.overviewOpen   = false
        root.widgetArrange  = true
    }


    // ── Overview ──────────────────────────────────────────────────────────────
    // The full-screen overlay: workspace grid, dock, calendar, timer, power.
    // Transient.
    //
    // There is no `overviewPanel` any more. The overview briefly had a
    // panel-over-the-grid mode for the calendar and the power menu; both are now
    // cards/buttons ON the overlay, so nothing in the overview is behind a panel and
    // the overlay has exactly one piece of state: open or not.
    property bool overviewOpen: false
    function toggleOverview() { root.overviewOpen = !root.overviewOpen }

    // ── Opening the overview to a specific page ────────────────────────────────
    // Bar modules (Settings, Notifications) jump straight to a page. `overviewTarget`
    // names it ("settings" | "notifs" | "main"); `overviewNav` is bumped on every
    // request so the Overview navigates even when it's ALREADY open (a plain string
    // that didn't change wouldn't fire). Overview maps the target to its page index.
    property string overviewTarget: "main"
    property int    overviewNav:    0
    function openOverviewTo(target) {
        root.overviewTarget = target
        root.overviewNav++
        root.overviewOpen = true
    }

    // ── The active panel in each group, as a key ──────────────────────────────
    // The panel host sizes and swaps its container from these. Deriving one key
    // from the booleans (rather than having the host inspect four flags) is what
    // lets the Accordion sequence a swap: it only has to watch one string.
    readonly property string leftPanel:
          wallpaperOpen   ? "wallpaper"
        : colorSchemeOpen ? "colorScheme"
        : equalizerOpen   ? "equalizer"
        : ""

    readonly property string rightPanel: wifiOpen ? "wifi" : ""

    // ── Accordion toggles ─────────────────────────────────────────────────────
    // Opening one panel closes its siblings — they share a container window, so
    // only one can be shown at a time. Toggling the already-open one closes it,
    // matching how every icon-toggle in this shell behaves.
    //
    // There is no toggleCenter(): the center slot only ever hosts the update
    // panel, so it has no sibling to enforce exclusivity against.
    function toggleLeft(name) {
        const key     = name + "Open"
        const wasOpen = root[key]
        root.wallpaperOpen   = false
        root.colorSchemeOpen = false
        root.equalizerOpen   = false
        root[key] = !wasOpen
    }

    function toggleRight(name) {
        const key     = name + "Open"
        const wasOpen = root[key]
        root.wifiOpen = false
        root[key] = !wasOpen
    }

    function closeLeft() {
        root.wallpaperOpen   = false
        root.colorSchemeOpen = false
        root.equalizerOpen   = false
    }

    function closeRight() {
        root.wifiOpen = false
    }

    // ══ Nothing here persists ═════════════════════════════════════════════════
    // Panel state is transient by design — a reload should not reopen whatever you
    // happened to have open. The appearance PREFERENCES that used to live here
    // (barShape/barMode) moved to Config, which is where durable settings belong.

    // ══ IPC ═══════════════════════════════════════════════════════════════════
    // `qs ipc -c ~/.config/quicktest call launcher toggle`
    // activeScreen is cleared so the launcher shows on every screen — a raw
    // keybind carries no screen context.
    property var _ipc: IpcHandler {
        target: "launcher"

        function toggle(): void {
            root.activeScreen = null
            root.launcherOpen = !root.launcherOpen
        }
        function open(): void {
            root.activeScreen = null
            root.launcherOpen = true
        }
        function close(): void {
            root.launcherOpen = false
        }
    }

    // `qs ipc -c ~/.config/quicktest call overview toggle`
    //
    // Same target name the old standalone overview process used, so an existing
    // Hyprland keybind keeps working — it just no longer starts a second shell.
    property var _overviewIpc: IpcHandler {
        target: "overview"

        function toggle(): void { root.overviewOpen = !root.overviewOpen }
        function open(): void    { root.overviewOpen = true }
        function close(): void   { root.overviewOpen = false }
    }
}
