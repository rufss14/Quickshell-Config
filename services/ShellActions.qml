pragma Singleton
import QtQuick
import Quickshell
import "../config"
import "../state"

// ── ShellActions ──────────────────────────────────────────────────────────────
// What the shell can DO, findable from the launcher by typing: "night light", "lock",
// "clip", "random wallpaper", "mute mic". Each is a call into the service that already
// owns the job — nothing here does the work itself.
//
// `table` is the searchable part (name, keywords, what it does, its icon); the launcher
// folds it into its own index (launcher.js, kind "action", ranked a hair under an app
// that matches as well — services/Launcher). `stateOf` gives a toggle's state for the
// row's chip, live; `blockerOf` says why one can't run (a missing tool, no adapter) and
// the row shows that instead of running it (the blocker() contract).
//
// Nothing destructive runs from Enter: shutting down, rebooting and logging out are
// ONE entry, "Power menu", which opens the two-step menu.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property var table: [
        { id: "nightlight", name: "Night light", symbol: "nights_stay",
          keywords: ["warm", "redshift", "blue light", "hyprsunset", "gammastep"],
          detail: "Warm the screen" },
        { id: "dnd", name: "Do not disturb", symbol: "notifications_off",
          keywords: ["notifications", "quiet", "silence", "dnd", "focus"],
          detail: "Hold back notification pop-ups" },
        { id: "gamemode", name: "Game mode", symbol: "sports_esports",
          keywords: ["gaming", "performance", "games"],
          detail: "Performance governor, quiet shell" },
        { id: "awake", name: "Stay awake", symbol: "coffee",
          keywords: ["caffeine", "idle", "inhibit", "sleep", "screen off"],
          detail: "Keep the screen from locking or sleeping" },
        { id: "lens", name: "Read text on screen", symbol: "text_fields",
          keywords: ["lens", "ocr", "copy text", "scan"],
          detail: "Drag over any text to copy it" },
        { id: "lensTranslate", name: "Translate text on screen", symbol: "translate",
          keywords: ["lens", "ocr", "translate"],
          detail: "Drag over text to translate it in place" },
        { id: "colour", name: "Pick a colour", symbol: "colorize",
          keywords: ["color", "picker", "eyedropper", "hex", "hyprpicker"],
          detail: "Copy any pixel's colour" },
        { id: "clip", name: "Save a clip", symbol: "movie",
          keywords: ["clips", "replay", "shadowplay", "last seconds"],
          detail: "Keep what just happened" },
        { id: "record", name: "Screen recording", symbol: "videocam",
          keywords: ["record", "video", "capture", "clips"],
          detail: "Start or stop recording the screen" },
        { id: "clipsLibrary", name: "Clips library", symbol: "movie",
          keywords: ["clips", "library", "gallery", "recordings", "videos", "replays"],
          detail: "Every clip and recording — click one to play it" },
        { id: "clipping", name: "Clipping", symbol: "replay",
          keywords: ["replay buffer", "clips", "shadowplay"],
          detail: "Keep a replay buffer running" },
        { id: "lock", name: "Lock screen", symbol: "lock",
          keywords: ["lock", "away"],
          detail: "Lock the session now" },
        { id: "power", name: "Power menu", symbol: "power_settings_new",
          keywords: ["shut down", "shutdown", "power off", "restart", "reboot", "log out", "logout",
                     "suspend", "sleep", "hibernate"],
          detail: "Shut down, restart, log out…" },
        { id: "overview", name: "Overview", symbol: "grid_view",
          keywords: ["workspaces", "windows", "switch", "expose"],
          detail: "Every window and workspace" },
        { id: "wallpaper", name: "Wallpapers", symbol: "wallpaper",
          keywords: ["background", "gallery", "wallpaper"],
          detail: "Pick a wallpaper" },
        { id: "shuffle", name: "Random wallpaper", symbol: "shuffle",
          keywords: ["wallpaper", "background", "next", "shuffle"],
          detail: "Another picture from your library" },
        { id: "scheme", name: "Colour scheme", symbol: "palette",
          keywords: ["colors", "colours", "palette", "theme"],
          detail: "Edit or pick the palette" },
        { id: "theme", name: "Light or dark mode", symbol: "dark_mode",
          keywords: ["dark mode", "light mode", "theme"],
          detail: "Flip the palette's mode" },
        { id: "wifi", name: "Wi-Fi", symbol: "wifi",
          keywords: ["wireless", "network", "wlan", "internet"],
          detail: "Turn Wi-Fi on or off" },
        { id: "bluetooth", name: "Bluetooth devices", symbol: "bluetooth",
          keywords: ["bluetooth", "pair", "headphones", "devices"],
          detail: "Connect and pair" },
        { id: "mute", name: "Mute sound", symbol: "volume_off",
          keywords: ["volume", "audio", "speakers", "silence"],
          detail: "Mute or unmute the output" },
        { id: "micMute", name: "Mute microphone", symbol: "mic_off",
          keywords: ["mic", "microphone", "input"],
          detail: "Mute or unmute the mic" },
        { id: "sidebar", name: "Hide the sidebar", symbol: "visibility_off",
          keywords: ["dock", "sidebar", "hide"],
          detail: "Sink the dock and its modules into the frame" },
        { id: "notifications", name: "Notifications", symbol: "notifications",
          keywords: ["notification centre", "history", "inbox"],
          detail: "What came in" },
        { id: "updates", name: "Update the system", symbol: "update",
          keywords: ["upgrade", "pacman", "yay", "paru", "updates"],
          detail: "Check and install updates" },
        { id: "settings", name: "Settings", symbol: "settings",
          keywords: ["preferences", "configure", "options"],
          detail: "Open the settings app" },
        { id: "reload", name: "Reload the shell", symbol: "refresh",
          keywords: ["restart quickshell", "reload", "refresh"],
          detail: "Restart Quickshell" }
    ]

    // A toggle's state for the row's chip ("" = not a toggle). A binding on it is live:
    // it reads the owning service's own properties.
    function stateOf(id) {
        switch (id) {
        case "nightlight": return Config.nightLight ? "On" : "Off"
        case "dnd":        return Notifications.dnd ? "On" : "Off"
        case "gamemode":   return Gamemode.active ? "On" : "Off"
        case "awake":      return Idle.manual ? "On" : "Off"
        case "record":     return Clips.recording ? "Recording" : ""
        case "clipping":   return Config.clipsBuffer ? "On" : "Off"
        case "theme":      return Config.themeMode === "light" ? "Light" : "Dark"
        case "wifi":       return Net.wifiEnabled ? "On" : "Off"
        case "mute":       return Audio.muted ? "Muted" : ""
        case "micMute":    return Audio.micMuted ? "Muted" : ""
        case "sidebar":    return UiState.sidebarHidden ? "Hidden" : ""
        default:           return ""
        }
    }

    // Why it can't run here, or "".
    function blockerOf(id) {
        switch (id) {
        case "nightlight":    return NightLight.blocker()
        case "lens":
        case "lensTranslate": return Lens.blocker()
        case "colour":        return ColorPicker.blocker()
        case "clip":
        case "record":
        case "clipping":      return Clips.blocker()
        case "shuffle":       return Wallpaper.wallpapers.length > 1 ? "" : "No other pictures in your library"
        case "theme":         return !Config.wallTheming ? "Theming from the wallpaper is off"
                                   : Wallpaper.applying ? "A wallpaper is still applying" : ""
        case "wifi":          return Net.hasWifi ? "" : "No Wi-Fi adapter"
        case "bluetooth":     return Bt.available ? "" : "No Bluetooth adapter"
        case "mute":
        case "micMute":       return Audio.ready ? "" : "Audio isn't ready"
        default:              return ""
        }
    }

    // Does it; false when it couldn't. The launcher has already closed (a lens or a
    // picker needs the screen clear), so anything visual waits a beat.
    function run(id) {
        if (root.blockerOf(id) !== "") return false
        switch (id) {
        case "nightlight":    NightLight.toggle(); break
        case "dnd":           Notifications.toggleDnd(); break
        case "gamemode":      Gamemode.toggle(); break
        case "awake":         Idle.toggleManual(); break
        case "lens":          root._later(() => Lens.start("text")); break
        case "lensTranslate": root._later(() => Lens.start("translate")); break
        case "colour":        root._later(() => ColorPicker.pick()); break
        case "clip":          Clips.saveClip(0); break
        case "clipsLibrary":  Clips.openGallery(); break
        case "record":        Clips.toggleRecord(); break
        case "clipping":      Clips.setClipping(!Config.clipsBuffer); break
        case "lock":          Session.lock(); break
        case "power":         UiState.powerMenuOpen = true; break
        case "overview":      UiState.overviewOpen = true; break
        case "wallpaper":     UiState.openPanel("wallpaper"); break
        case "shuffle":       Wallpaper.shuffleNow(true); break
        case "scheme":        UiState.openPanel("colorScheme"); break
        case "theme":
            ColorScheme.switchMode(Config.themeMode === "light" ? "dark" : "light")
            break
        case "wifi":          Net.toggleWifi(); break
        case "bluetooth":     UiState.openPanel("bluetooth"); break
        case "mute":          Audio.toggleMute(); break
        case "micMute":       Audio.toggleMicMute(); break
        case "sidebar":       UiState.sidebarHidden = !UiState.sidebarHidden; break
        case "notifications": UiState.openPanel("notifications"); break
        case "updates":
            UiState.pendingUpdateCount = Updates.total
            UiState.updateRequestId++
            break
        case "settings":      UiState.openSettingsWindow(); break
        case "reload":
            Quickshell.execDetached(["bash", Quickshell.shellPath("scripts/reload-quickshell.sh")])
            break
        default:              return false
        }
        return true
    }

    // One surface-close's worth of time, so the launcher's card is gone before a
    // region picker or a colour picker freezes the screen.
    function _later(fn) {
        laterTimer.fn = fn
        laterTimer.restart()
    }
    Timer {
        id: laterTimer
        property var fn: null
        interval: Motion.exit + Motion.respond
        onTriggered: { const f = laterTimer.fn; laterTimer.fn = null; if (f) f() }
    }
}
