pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "../config"
import "../state"
import "hud.js" as H

// ── Hud ───────────────────────────────────────────────────────────────────────
// Small widgets — performance, clips, voice, your input — that live as cards in the
// overview, above and below the workspaces, and that you can PIN to be drawn over a fullscreen game.
// (The desktop widgets are the opposite: under the windows.)
//
//     qs ipc -c ~/.config/quicktest call hud open        # the overview, a card inspected
//
// ── Everything is in the overview ─────────────────────────────────────────────
// Since 2026-10-20 there is no SUPER+G edit overlay. The cards (modules/hud/HudCard, two
// strips framing the grid) are where you use them; a card's tune chip puts it in the island (`inspecting`), where
// HudInspector places it on a map of the screen and sets its options; a card's move chip
// (or the inspector's) starts ARRANGING (`arranging`): the overview steps back and the real
// widgets are dragged where they really go (modules/hud/HudArrange). Pinned widgets are
// drawn by modules/hud/HudLayer — each one either over a fullscreen window on the focused
// monitor (`where: "games"`), or always, as a plain overlay on the overlay's home monitor
// (`where: "always"`, `homeScreen`).
//
// The rules are services/hud.js, the FPS line is mangohud.js; the layout is saved in
// hud.json (XDG_STATE_HOME — personal, never in the repo) and not in Config: it is
// rewritten on every drag, which is what Config's document is NOT for.
//
// Edits are refused until the file has been read, so an early change can't be saved
// over the real layout.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property var _layout: H.normalise(null)
    readonly property var layout: root._layout
    readonly property var catalog: H.CATALOG
    readonly property bool ready: store.ready

    readonly property bool anyPinned: H.anyPinned(root._layout)
    readonly property bool anyAlways: H.ids().some(id => root._layout.widgets[id].pinned
                                                      && root._layout.widgets[id].where === "always")

    // Where "always" widgets are drawn: the monitor they were last arranged on, while it is
    // connected; the focused one otherwise. (A plain loop: Quickshell.screens is a QML list.)
    readonly property string homeScreen: {
        const names = []
        const sc = Quickshell.screens
        for (let i = 0; i < sc.length; i++) names.push(sc[i].name)
        return H.homeScreen(root._layout.home, names, Hyprland.focusedMonitor?.name ?? "")
    }

    // Arranging: the overview hides its own furniture and the widgets are dragged on the real
    // screen (HudArrange). `arrangeFocus` is the one that was asked for (drawn ringed, and the
    // one the arrow keys nudge) — "" = whichever was touched last. Not saved.
    property bool arranging: false
    property string arrangeFocus: ""
    function arrange(on, id) {
        root.arranging = on
        root.arrangeFocus = on ? (id ?? "") : ""
        if (on) { root.inspecting = ""; Switcher.select(-1); UiState.overviewOpen = true }
    }
    readonly property int pinnedCount: H.ids().filter(id => H.visible(root._layout.widgets[id])).length

    // The widget the overview's island is inspecting ("" = none). Picking a window takes
    // the island over (Switcher), and a closed overview forgets it. Not saved.
    property string inspecting: ""
    function inspect(id) {
        root.inspecting = root.inspecting === id ? "" : id
        if (root.inspecting !== "") Switcher.select(-1)
    }
    Connections {
        target: Switcher
        function onSelectedAddressChanged() { if (Switcher.selectedAddress !== "") root.inspecting = "" }
    }
    Connections {
        target: UiState
        function onOverviewOpenChanged() {
            if (UiState.overviewOpen) return
            root.inspecting = ""
            root.arranging = false
        }
    }

    function open() {
        if (root.inspecting === "") root.inspecting = H.CATALOG[0].id
        UiState.overviewOpen = true
    }
    function close()  { UiState.overviewOpen = false }
    function toggle() { if (UiState.overviewOpen) root.close(); else root.open() }

    function _patch(id, p) {
        if (!store.ready) return
        const next = H.set(root._layout, id, p)
        if (next === root._layout) return
        root._layout = next
        store.value = next
    }

    function pin(id, on)     { root._patch(id, { pinned: on }) }
    function passThrough(id, on) { root._patch(id, { clickthrough: on }) }
    function setWhere(id, w)     { root._patch(id, { where: w }) }
    // `screen` (a monitor name, optional) is where it was placed: "always" widgets live there.
    function move(id, cx, cy, screen) {
        root._patch(id, { cx: cx, cy: cy })
        root._home(screen)
    }
    function _home(name) {
        if (!store.ready || !name) return
        const next = H.setHome(root._layout, name)
        if (next === root._layout) return
        root._layout = next
        store.value = next
    }
    // One of hud.js ANCHORS, kept wholly on a W×H screen for a w×h widget.
    function place(id, anchor, w, h, W, H2, screen) {
        const a = H.ANCHORS[anchor]
        if (!a) return
        const c = H.clampCentre(a[0], a[1], w, h, W, H2)
        root.move(id, c.cx, c.cy, screen)
    }
    function setOpt(id, key, value) {
        const o = {}
        o[key] = value
        root._patch(id, { opts: o })
    }

    JsonStore {
        id: store
        path: Quickshell.statePath("hud.json")
        onLoaded: root._layout = H.normalise(store.value)
    }

    IpcHandler {
        target: "hud"
        function toggle(): void { root.toggle() }
        function open(): void   { root.open() }
        function close(): void  { root.close() }
        function arrange(): void { root.arrange(true, "") }
        function status(): string {
            return "inspecting=" + root.inspecting + " arranging=" + root.arranging
                 + " home=" + root.homeScreen
                 + " pinned=" + H.ids().filter(id => H.visible(root._layout.widgets[id]))
                                    .map(id => id + ":" + root._layout.widgets[id].where).join(",")
        }
    }
}
