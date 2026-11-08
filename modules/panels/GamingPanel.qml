pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../services/gamemodewatch.js" as Watch
import "gaming"

// ── GamingPanel ───────────────────────────────────────────────────────────────
// The gamemode pill's panel, redone 2026-11-07 in the shell's Material 3 Expressive dialect, on five pages of
// a SegmentSwitch (the Timer and Media panels' idiom) that slide past each other on one spring:
//
//   Play     the mode as the subject: an M3E shape that morphs and turns while it is on, what is running and for
//            how long, the big button; three stat tiles (this session, today, this week as a bar chart); the
//            GPU/CPU rings and VRAM/RAM bars; and, when RAM is filling, the biggest windows with a polite Close
//   Effects  when it turns on (a gamemoderun game, a Steam game) and what it does — a tile each, with a line of
//            what that setting does right now. Each applies at once, even mid-session (services/Gamemode)
//   Tune     CPU governor, frame cap, MangoHud overlay (with a live preview): each with what the current choice means
//   History  the sessions the mode has run for, newest first, each with the game's picture
//   Setup    what is installed and ready, the fix for what isn't, the game profile, the Steam launch options
//
// The title row on top is `Config.gamemodePanelHeader()` — Settings › Bar › Game mode, like the clock's.
//
// ── It owns no state ──────────────────────────────────────────────────────────
// Same rule as ColorSchemePanel. The switch flips the SAME Gamemode service the bar pill and SUPER+G do;
// the readouts are the SAME refcounted SysInfo the About page samples; the tiles are Config properties
// (persisted, edited from anywhere); the overlay preset, the frame cap and the governor are read straight
// back out of MangoHud.conf / sysfs. Everything real — live-apply, the game's name, the time log, the
// compositor snapshot, the memory scan — is in services/Gamemode.qml; this shows it and calls it.
//
// ── Height ────────────────────────────────────────────────────────────────────
// The pages box is as tall as the page you are on and follows it on a spring, so no page leaves empty room under it.
// Wider than the shared panelWidth (the dock clamps up to panelWidthMax, as the wallpaper gallery does).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    // Reached by the view files in gaming/.
    property alias pagesBox: pagesBox
    property alias pg: pg

    implicitWidth: Tokens.sideCardUnit * 13
    readonly property int margin: Tokens.spacingXl
    readonly property int cardPad: Tokens.spacingMd + Tokens.spacingXs
    implicitHeight: mainCol.implicitHeight + root.margin * 2

    readonly property color accent: Colors.of(QsWindow.window).primary

    // The page, and the spring the pages ride (SpringValue: velocity survives a quick second tap).
    property string page: "play"
    readonly property var _pageOrder: ["play", "effects", "tune", "history", "setup"]
    SpringValue { id: pg; target: root._pageOrder.indexOf(root.page); spec: Motion.springSpatial }

    // Sampling runs only while the panel exists — the Loader in BarPanelDock destroys
    // it on close. Same pattern as AboutPage.
    Component.onCompleted: {
        SysInfo.acquire()
        Gamemode.refreshGovernor()
        Gamemode.refreshGpuLevel()
        Gamemode.refreshProfile()
        Gamemode.refreshScheduler()
        Gamemode.scanHogs()
    }
    Component.onDestruction: SysInfo.release()

    // ── The profile, as one line ──────────────────────────────────────────────
    // What a session will actually ask gamemoded for, read back out of the two
    // gamemode.ini regions. "Complete" = the priority half, plus the GPU half on a
    // machine that has a card for it; the button offers whichever step is missing.
    readonly property bool _profileComplete:
        Gamemode.userProfile.installed
        && (!Gamemode.profileGpuAvailable || Gamemode.systemProfile.installed)
    readonly property string _profileSummary: {
        const parts = []
        if (Gamemode.userProfile.installed)
            parts.push(Gamemode.userProfile.renice > 0 ? "nice −" + Gamemode.userProfile.renice
                                                       : "I/O first")
        if (Gamemode.systemProfile.gpuLevel !== "")
            parts.push("GPU " + Gamemode.systemProfile.gpuLevel)
        return parts.length > 0 ? parts.join(" · ") : "not set up"
    }

    // Steam → game → Properties → Launch Options. gamemoderun wraps the game so the system gamemoded picks it
    // up even when the shell's mode isn't on. Neither tool installed → just "%command%", which wraps nothing —
    // not a real launch option to offer, so the row hides.
    readonly property string _launchOpts: {
        const parts = []
        if (Gamemode.toolsAvailable)    parts.push("gamemoderun")
        if (Gamemode.mangohudAvailable) parts.push("mangohud")
        parts.push("%command%")
        return parts.join(" ")
    }

    // The kernel names its scheduler with a version and a target ("lavd_1.1.4_x86_64_unknown_linux_gnu").
    readonly property string _schedName: Gamemode.scheduler.replace(/_\d.*$/, "")

    // ── The effects, as data ──────────────────────────────────────────────────
    // One list drives the tiles AND the "n of m" count, so they cannot disagree (the old subtitle once counted a
    // wallpaper effect its own row had hidden). `on`/`off` are the tile's second line — what the setting does
    // right now. `blocker` is "" when the effect can do something here, else why not: the tile dims with that
    // reason as its line, and doesn't count (a missing optional tool DISABLES the control with a reason).
    readonly property var _effects: [
        { key: "gamemodeSession",    label: "Performance",          symbol: "speed",
          on: "Governor, GPU clocks, priority",   off: "CPU and GPU left as they are",
          shape: "burst", hint: "A gamemoderun session: the CPU governor, GPU clocks and priority for games" },
        { key: "gamemodeQuiet",      label: "Silence notifications", symbol: "notifications_off",
          on: "Held until the mode ends",         off: "Notifications stay on",
          shape: "clover", hint: "Notifications are held until the mode ends" },
        { key: "gamemodeIdle",       label: "Keep screen awake",    symbol: "visibility",
          on: "The screen won't blank or lock",   off: "The screen may blank",
          shape: "sunny", hint: "Holds an idle inhibitor while the mode is on" },
        { key: "gamemodeWallpaper",  label: "Pause wallpaper",      symbol: "wallpaper",
          on: "Scene stopped, back afterwards",   off: "Scene keeps running",
          shape: "squircle", hint: "Stops the live wallpaper scene and brings it back afterwards" },
        { key: "gamemodeVisualizer", label: "Hide visualiser",      symbol: "equalizer",
          on: "The visualiser stops drawing",     off: "The visualiser keeps drawing",
          shape: "cookie7", hint: "The desktop audio visualiser stops drawing" },
        { key: "gamemodeKeys",       label: "Mute typing sounds",   symbol: "keyboard",
          on: "No key sounds from other apps",    off: "Typing sounds stay on",
          shape: "pentagon", hint: "A game's WASD isn't typing" },
        { key: "gamemodeClips",      label: "Record clips",         symbol: "videocam",
          on: "Replay buffer runs with the mode", off: "Buffer follows its own switch",
          shape: "hexagon", hint: "Keeps the Clips replay buffer running while the mode is on" },
        { key: "gamemodeCompositor", label: "Lighter desktop",      symbol: "blur_on",
          on: "Blur, shadows, animations off",    off: "Desktop untouched",
          shape: "cookie12", hint: "Blur, shadows and animations off in Hyprland, then put back as they were" },
    ]
    function _blocker(key) {
        if (key === "gamemodeWallpaper") return WallpaperEngine.installed ? "" : "linux-wallpaperengine isn't installed"
        if (key === "gamemodeClips")     return !Config.clips ? "Clips is turned off in Settings" : Clips.blocker()
        return ""
    }
    // The wallpaper tile is the one that hides outright: the scene renderer is an optional AUR build.
    function _shown(key) { return key !== "gamemodeWallpaper" || WallpaperEngine.installed }
    // The tile's second line: why not, else what it does now (the performance one names the live governor).
    function _sub(e) {
        const b = root._blocker(e.key)
        if (b !== "") return b
        const on = Config[e.key] === true
        if (e.key === "gamemodeSession" && on && Gamemode.active && Gamemode.cpuGovernor !== "")
            return "CPU on " + Gamemode.cpuGovernor + (Gamemode.gpuPowerLevel !== "" ? " · GPU " + Gamemode.gpuPowerLevel : "")
        return on ? e.on : e.off
    }

    readonly property int _effectTotal: root._effects.filter(e => root._shown(e.key) && root._blocker(e.key) === "").length
    readonly property int _effectCount: root._effects.filter(e => root._shown(e.key) && root._blocker(e.key) === "" && Config[e.key]).length

    readonly property bool _follows: (Config.gamemodeAuto && Gamemode.followAvailable) || Config.gamemodeSteam

    // ── Session timer ─────────────────────────────────────────────────────────
    // Reads Clock.now purely to get re-evaluated once a minute — Gamemode.enabledAt
    // is a fixed epoch stamp, so without a live dependency this would freeze the
    // instant the panel opened. "" while off.
    readonly property string _elapsed: {
        if (!Gamemode.active || Gamemode.enabledAt < 0) return ""
        void Clock.now
        const s = (Date.now() - Gamemode.enabledAt) / 1000
        return s < 60 ? "just started" : Gamemode.duration(s)
    }

    readonly property bool _stalled: Gamemode.sessionStalled || Gamemode.gpuStalled
    readonly property string _heroTitle: root._stalled ? "On, but not tuned"
                                       : Gamemode.active ? "Game mode on" : "Game mode off"
    readonly property string _heroLine: {
        if (Gamemode.sessionStalled) return "The CPU governor didn't change — see Setup"
        if (Gamemode.gpuStalled)     return "The GPU clocks didn't change — see Setup"
        if (Gamemode.active) {
            const who = Gamemode.gameName !== "" ? Gamemode.gameName
                      : Gamemode.auto            ? "A game is running" : "Started by hand"
            return root._elapsed !== "" ? who + " · " + root._elapsed : who
        }
        if (Gamemode.lastSeconds >= 60)
            return "Last: " + (Gamemode.lastGame !== "" ? Gamemode.lastGame : "a session")
                   + " · " + Gamemode.duration(Gamemode.lastSeconds)
        return root._follows ? "Turns on by itself when a game starts" : "Turn it on before you play"
    }

    // What each governor means, for the Tune page's line under its title.
    readonly property var _govAbout: ({
        performance: "Full clocks, always — what games want",
        powersave:   "Idles down to save power and heat",
        schedutil:   "Follows the load, the everyday default",
        ondemand:    "Scales up when busy, down when idle",
        conservative: "Scales gently, favours power saving"
    })
    readonly property var _overlayAbout: ({
        full:    "Frame rate, frame time, CPU, GPU, RAM and more",
        compact: "Frame rate with CPU and GPU load",
        fps:     "Just the frame rate",
        off:     "No overlay in games"
    })

    ColumnLayout {
        id: mainCol
        anchors.top:   parent.top
        anchors.left:  parent.left
        anchors.right: parent.right
        anchors.margins: root.margin
        spacing: Tokens.spacingSm

        // ── Header (Settings › Bar › Game mode hides it) ──────────────────────
        PanelHeader {
            Layout.fillHeight: false
            visible: Config.gamemodePanelHeader()
            symbol:    "sports_esports"
            title:     Translation.tr("Game")
            titleTail: Translation.tr("Mode")
            accent:    root.accent
            subtitle: {
                const l = Gamemode.limits()
                if (l !== "") return l
                return (root._follows ? "Follows games" : "By hand") + " · "
                       + root._effectCount + " of " + root._effectTotal + " effects"
            }
        }

        // ── Pages ─────────────────────────────────────────────────────────────
        // A dot of accent on the Play tab says "on" from any page (`lit`); Setup lights when something stalled.
        SegmentSwitch {
            id: pageSwitch
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: implicitHeight
            accent: root.accent
            model: [
                { value: "play",    label: "Play",    icon: "sports_esports", lit: Gamemode.active },
                { value: "effects", label: "Effects", icon: "auto_awesome" },
                { value: "tune",    label: "Tune",    icon: "tune" },
                { value: "history", label: "History", icon: "history" },
                { value: "setup",   label: "Setup",   icon: "settings_suggest", lit: root._stalled },
            ]
            current: root.page
            onPicked: function (value) { root.page = value }
        }

        Item {
            id: pagesBox
            Layout.fillWidth: true
            Layout.fillHeight: false
            clip: true
            // As tall as the page you are on, not the tallest: the surface grows and shrinks with it on a
            // spring (no overshoot — a panel that bounces its own size reads as a glitch), so there is never
            // empty room under a short page. A page whose content changes (the memory card arriving) is
            // followed the same way.
            readonly property real wanted: [playPage, effectsPage, tunePage, historyPage, setupPage][Math.max(0, root._pageOrder.indexOf(root.page))].implicitHeight
            implicitHeight: hv.value
            SpringValue { id: hv; target: pagesBox.wanted; spec: Motion.springEffects; epsilon: 0.5 }
            Component.onCompleted: hv.jump(pagesBox.wanted)

            // ══ PLAY ══════════════════════════════════════════════════════════
            GamingPlayView {
                id: playPage
                panel: root
            }

            // ══ EFFECTS ═══════════════════════════════════════════════════════
            GamingEffectsView {
                id: effectsPage
                panel: root
            }

            // ══ TUNE ══════════════════════════════════════════════════════════
            GamingTuneView {
                id: tunePage
                panel: root
            }

            // ══ HISTORY ═══════════════════════════════════════════════════════
            GamingHistoryView {
                id: historyPage
                panel: root
            }

            // ══ SETUP ═════════════════════════════════════════════════════════
            GamingSetupView {
                id: setupPage
                panel: root
            }
        }
    }
}
