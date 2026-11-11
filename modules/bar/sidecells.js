.pragma library

// ── sidecells.js ──────────────────────────────────────────────────────────────
// Which file draws a module's SIDEBAR cell, by id — the registry SideGroupHost kept
// inline, moved here so the settings library (modules/settings/ModuleLibrary) builds
// the same cells from the same table (2026-11-08). File names only: a caller resolves them
// against modules/bar/ itself (`Qt.resolvedUrl` belongs to the QML calling it).
//
// Loaded by URL rather than as typed components, on purpose: a cell that fails to load
// blanks its own slot and logs why, where a typed reference would make the HOST fail to
// exist — and Bar.qml with it (the "Type … unavailable" cascade, CLAUDE.md).
//
// "" for a module with no cell of its own (the dock is DockHost's).
// ─────────────────────────────────────────────────────────────────────────────

var FILES = {
    stats: "SideStats.qml", clips: "SideClips.qml", power: "SidePower.qml",
    tools: "SideTools.qml", voice: "SideVoice.qml", colour: "SideColour.qml",
    notifications: "SideNotifications.qml", clipboard: "SideClipboard.qml",
    timer: "SideTimer.qml", lens: "SideLens.qml", claude: "SideClaude.qml",
    screentime: "SideScreenTime.qml", inactivity: "SideInactivity.qml",
    tasks: "SideTasks.qml", brightness: "SideBrightness.qml", window: "SideWindow.qml",
    layout: "SideLayout.qml", locks: "SideLocks.qml", nowplaying: "SideNowPlaying.qml",
    clock: "SideClock.qml", workspaces: "SideWorkspaces.qml", tray: "SideTray.qml",
    visualizer: "SideVisualizer.qml"
};

// The bar's one-click modules, as cells — one file, keyed by id.
var GENERIC = ["shapeToggle", "modeToggle", "palette", "wallpaper", "volume", "keyboard",
               "update", "reload", "wifi", "bluetooth", "battery", "clock", "overview",
               "settings", "privacy", "nightlight", "idle", "gamemode"].filter(id => id !== "clock");

function file(id) {
    if (FILES[id] !== undefined) return FILES[id];
    return GENERIC.indexOf(id) !== -1 ? "SideBarModule.qml" : "";
}
