pragma Singleton
import QtQuick

// ── Panels ────────────────────────────────────────────────────────────────────
// Global singleton that holds references to all overlay panel windows and
// their open/closed state. StatusBarRoot (and hotkeys, etc.) toggle the open
// flags here; OverlayRoot owns the actual PanelWindow popup instances and
// binds to these flags to show/hide them.
// ─────────────────────────────────────────────────────────────────────────────
QtObject {
    // Panel content references (set by OverlayRoot on creation)
    property var updatePanel:     null
    property var wallpaperPanel:  null
    property var brightnessPanel: null
    property var wifiPanel:       null
    property var equalizerPanel:  null
    property var bgmPanel:        null

    // Which screen most recently triggered an open — set by OverlayRoot
    property var  activeScreen:   null

    // Open/closed state — toggled by StatusBarRoot, read by OverlayRoot
    property bool wallpaperOpen:  false
    property bool brightnessOpen: false
    property bool equalizerOpen:  false
    property bool wifiOpen:       false
    property bool clockOpen:      false
    property bool bgmOpen:        false

    // BGM playback state — written by BgmPanel, read by BgmButton
    property string bgmCurrentTrack: ""
    property bool   bgmIsPlaying:    false
    property string bgmCoverPath:    ""   // "file:///tmp/qs_bgm_cover.jpg?<timestamp>" or ""
}
