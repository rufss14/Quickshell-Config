pragma Singleton
import Quickshell
import QtQuick

// ── Settings (controller) ───────────────────────────────────────────────────
// Single source of truth for whether the settings window is open and which page
// it shows. Anything (a bar button, a keybind) opens the app — optionally
// deep-linking to a page — by calling Settings.open("wifi").
//
// The page REGISTRY lives in SettingsWindow (pages own their components there);
// this singleton only holds routing state so it stays dependency-free and every
// component can import it without cycles.
// ──────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property bool   shown: false
    property string page: "wifi"     // id of the page to show
    property string activeScreen: "" // name of the monitor to show the overlay on

    // Where to anchor the floating panel. Empty edge = centered (the default for
    // most openers). A bar module that wants the window to open "out of" itself
    // passes the bar edge ("left"/"right"/"top"/"bottom") and its normalized
    // position along that edge (0..1) — the window biases toward that side/corner.
    property string anchorEdge: ""
    property real   anchorPos: 0.5

    // Set true while the Keybinds page is capturing a key combo, so the settings
    // window grabs the keyboard EXCLUSIVELY — otherwise the compositor would eat
    // SUPER-combos with its own binds before the app could read them.
    property bool grabKeys: false

    // Which monitor to place the overlay on — the one whose bar button was
    // clicked, or the primary as a fallback.
    function _resolveScreen(screenName) {
        if (screenName && screenName.length) return screenName
        return Quickshell.screens.length ? Quickshell.screens[0].name : ""
    }

    // Open the app, optionally on a specific page id and monitor. `anchorEdge`
    // (+ `anchorPos` 0..1) bias the panel toward a screen side; omit them (the
    // usual case) to open centered.
    function open(pageId, screenName, anchorEdge, anchorPos) {
        if (pageId && pageId.length) root.page = pageId
        root.activeScreen = root._resolveScreen(screenName)
        root.anchorEdge = anchorEdge || ""
        root.anchorPos = (anchorPos === undefined || anchorPos === null) ? 0.5 : anchorPos
        root.shown = true
    }
    function close() { root.shown = false }

    // Toggle: if already open on this page, close; otherwise open there.
    function toggle(pageId, screenName, anchorEdge, anchorPos) {
        if (root.shown && (!pageId || pageId === root.page)) root.shown = false
        else root.open(pageId, screenName, anchorEdge, anchorPos)
    }

    // ── Searchable page catalog ──────────────────────────────────────────────
    // A lightweight metadata list (id/title/glyph + extra search keywords) used by
    // the launcher to surface settings pages as search results and ">" commands.
    // Deep-linking still goes through open()/SettingsWindow's own registry, so this
    // holds NO components — just the searchable text. KEEP IN SYNC with
    // SettingsWindow.allPages (same pattern as BarCatalog ↔ Bar's registry).
    readonly property var pageIndex: [
        { id: "wifi",          title: "Wi-Fi",             glyph: 0xF05A9, keywords: "network internet wireless connection" },
        { id: "bluetooth",     title: "Bluetooth",         glyph: 0xF00AF, keywords: "bt pair device headphones" },
        { id: "sound",         title: "Sound",             glyph: 0xF057E, keywords: "audio volume mixer output input microphone speaker" },
        { id: "battery",       title: "Battery",           glyph: 0xF0079, keywords: "power charge energy profile" },
        { id: "wallpaper",     title: "Appearance",        glyph: 0xF1904, keywords: "wallpaper theme colour color scheme font background" },
        { id: "customization", title: "Panels & Bar",      glyph: 0xF0210, keywords: "bar panel launcher reveal layout modules customise roundness inset" },
        { id: "updates",       title: "Updates",           glyph: 0xF06B0, keywords: "upgrade pacman aur packages" },
        { id: "language",      title: "Language & Region", glyph: 0xF05CA, keywords: "locale region" },
        { id: "keyboard",      title: "Keyboard",          glyph: 0xF030C, keywords: "layout input repeat xkb" },
        { id: "keybinds",      title: "Keybinds",          glyph: 0xF030C, keywords: "shortcuts hotkeys bindings" },
        { id: "plugins",       title: "Plugins",           glyph: 0xF0431, keywords: "addons modules extensions" },
        { id: "about",         title: "About",             glyph: 0xF02FC, keywords: "system info specs hardware" },
    ]
    // Pages whose title OR keywords contain the query (case-insensitive). Empty
    // query → no matches (the launcher shows apps/pinned instead).
    function searchPages(q) {
        var s = (q || "").toLowerCase().trim()
        if (!s.length) return []
        return root.pageIndex.filter(function(p) {
            return p.title.toLowerCase().indexOf(s) !== -1 || p.keywords.indexOf(s) !== -1
        })
    }
}
