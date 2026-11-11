pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick
import "../config"
import "settingssearch.js" as Search

// ── SettingsIndex ─────────────────────────────────────────────────────────────
// What pages the settings app has, and what is on them.
//
// ── Why the catalogue lives in a singleton ────────────────────────────────────
// Two readers need it: SettingsCard (the rail, the view strip) and search, which
// has to resolve a result's `file` to a page NAME and know whether that page
// currently exists. One list, so twenty strings that get renamed have one home.
//
// ── Two halves, joined here ───────────────────────────────────────────────────
//   catalogue  hand-written below. Pages, their views, glyphs, keywords, and the
//              hardware gating. This is the part a person edits.
//   entries    generated into settings-index.json by scripts/build-settings-index.py
//              from the page sources — every Section and every SettingRow/SliderRow.
//              Never hand-edited, because it would immediately disagree with the
//              pages it describes.
//
// The join happens in settingssearch.js so it can be tested; see the note there for
// why the page's NAME is deliberately not baked into the generated file.
//
// ── A missing index is not an error ───────────────────────────────────────────
// The JSON is committed, so it is normally present. If it is absent or malformed,
// search falls back to page-level results only — every page is still findable by
// name and keyword. It does not throw and it does not disable the field, because a
// search box that silently does nothing is worse than one that finds less.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── Hardware gating ───────────────────────────────────────────────────────
    // Live bindings, so a USB Wi-Fi adapter or a Bluetooth dongle appearing inserts
    // its view without a restart — and unplugging it removes the view AND its rows
    // from the search index, so a result can never navigate somewhere that isn't
    // there. A desktop simply has no Battery view rather than a charge stuck at 0%.
    readonly property bool hasBattery: UPower.displayDevice?.isLaptopBattery ?? false
    readonly property bool hasWifi: Net.hasWifi
    // Via the service rather than Bluetooth.adapters directly, so this and
    // Bar.moduleVisible() are literally the same expression — the view and the bar
    // pill appear together or not at all.
    readonly property bool hasBluetooth: Bt.available

    // ── The catalogue: eight pages, each one or more views ────────────────────
    // The rail lists PAGES; a page with more than one view gets a segmented strip
    // above its content. It used to be twenty-three rail entries under six group
    // headings, which is a directory rather than a map — eight entries need no
    // headings at all, and each answers one question:
    //   Appearance      how the shell looks, sounds and feels (and how warm the screen is)
    //   Wallpaper       what's behind it
    //   Bar             the bar: its modules, its look, where its panels open
    //   Sidebar & dock  the edge the bar doesn't own
    //   Desktop         widgets, the lock screen, and Hyprland itself
    //   Devices         hardware attached to this machine
    //   Apps & tools    the launcher, clips, screen time, and the apps the shell talks to
    //   System          packages, setup (and presets), storage, language, the machine underneath
    //
    // (Regrouped 2026-10-26: no page carries more than six tabs — Devices had eight — and
    // each view sits under the page that describes it.)
    //
    // A VIEW is still one page file, and file names are unique across the whole
    // catalogue — so `Config.settingsPage` and `UiState.openSettingsTo(file)` keep
    // naming a file, and the page it belongs to is derived. Nothing that opens
    // settings to a particular place (battery pill, disk widget, IPC) had to change.
    //
    // `keywords` carries the terms that should FIND a view without being its name —
    // including every name it used to have ("hyprland", "misc", "home"), so a
    // rename never costs someone who already knew the old word.
    //
    // `available: false` hides a view; a page whose views are all hidden is dropped.
    readonly property var _catalogue: [
        { label: "Appearance", glyph: "󰉼", icon: "palette", views: [
            { file: "AppearancePage.qml", label: "Theme", glyph: "󰸌", icon: "palette",
              detail: "Palette, light and dark, album colours, accent",
              keywords: "appearance theme colour color palette pywal wallpaper dark light mode album cover accent icon tint" },
            { file: "ShapePage.qml", label: "Type & shape", glyph: "󰛖", icon: "text_fields",
              detail: "Font, scale, spacing, corners, surfaces",
              keywords: "style font family text scale size density spacing rounding radius roundness shadow opacity transparency settings window panel" },
            { file: "NightLightPage.qml", label: "Night light", glyph: "󰖔", icon: "dark_mode",
              detail: "Screen warmth and schedule",
              keywords: "night light blue warmth temperature gamma sunset sunrise hyprsunset gammastep eyes" },
            { file: "CursorPage.qml", label: "Cursor", glyph: "\u{F01C0}", icon: "mouse",
              detail: "Mouse pointer in the shell's colours",
              keywords: "cursor mouse pointer arrow hand xcursor hyprcursor colour color theme size accent hover effects animation tilt rotate stretch shake find dynamic-cursors hyprpm plugin" },
            { file: "SoundEffectsPage.qml", label: "Sound effects", glyph: "󰕾", icon: "notifications_active",
              detail: "Swooshes, typing, timer and alarm, shutter",
              keywords: "sound effects sfx swoosh whoosh typing keyboard click key clicks typewriter noise audio feedback ui sounds panel open close notification chime volume mute timer alarm bell beep screenshot shutter clip saved capture mixer level" }
        ] },

        { label: "Wallpaper", glyph: "󰸉", icon: "wallpaper", views: [
            { file: "WallpaperPage.qml", label: "Wallpaper", glyph: "󰸉",
              detail: "Images and scenes",
              keywords: "background picture slideshow wallpaper engine workshop scene parallax workspace per workspace shuffle gallery renderer monitor music effects audio visualizer cava beat glow blur zoom shake rumble shockwave shimmer pulse glitch bloom strobe breakdown adapt song sound map intensity sync bpm tempo latency delay kick snare clap hi-hat drums bass vocals" }
        ] },

        { label: "Bar & sidebar", glyph: "󰍜", icon: "dashboard", views: [
            { file: "BarPage.qml", label: "Modules", glyph: "󰮐", icon: "dashboard",
              detail: "What's on the bar and the sidebar, and every module's settings",
              keywords: "panel taskbar topbar statusbar sidebar side modules layout arrange drag group region pill widget library catalogue add remove hero accent inner pill spacing peek dock taskbar launcher pinned pins running apps previews thumbnails magnify magnification trash downloads stats system monitor cpu gpu ram memory network temperature alert" },
            { file: "BarStylePage.qml", label: "Style", glyph: "󰸌", icon: "layers",
              detail: "How both look — the sidebar follows the bar unless unlinked",
              keywords: "bar sidebar size height thickness roundness corners opacity translucent inner pill preset square text icon scale link unlink same as bar override islands music glow rim" },
            { file: "SidebarPage.qml", label: "Behaviour", glyph: "\u{F06FD}", icon: "view_quilt",
              detail: "The sidebar's edge, size and auto-hide; where the bar centres",
              keywords: "sidebar side edge position left right bottom autohide auto-hide hide dodge reveal empty workspace reserve space exclusive icon size anchor centre workspaces" },
            { file: "BarPanelsPage.qml", label: "Panels", glyph: "\u{F0574}", icon: "view_quilt",
              detail: "Which side each panel opens on, and resizes",
              keywords: "panel side left right centre middle placement popup resize zoom size reset" }
        ] },

        { label: "Desktop", glyph: "󰕮", icon: "widgets", views: [
            { file: "WidgetsPage.qml", label: "Widgets", glyph: "󰕮", icon: "dashboard",
              detail: "Place and tune desktop widgets, and how they all look",
              keywords: "desktop widgets clock notes calendar overlay gallery add arrange style opacity roundness glass snap grid parallax weather location city celsius layout preset hover grow entrance calendars ics" },
            { file: "LockPage.qml", label: "Lock screen", glyph: "󰌾", icon: "lock",
              detail: "Auto-lock and PAM",
              keywords: "lock screen idle timeout password pam screensaver security avatar" },
            // Hyprland, named for the category and not the product: "hyprland" is in
            // `keywords` for anyone who already knows the product name.
            { file: "HyprlandPage.qml", label: "Keybinds", glyph: "󰌋", icon: "keyboard",
              detail: "Read, rebind and add Hyprland keybinds",
              keywords: "hyprland compositor wm keybind bind shortcut hotkey window manager" },
            { file: "HyprTuningPage.qml", label: "Tuning", glyph: "󰂵", icon: "rounded_corner",
              detail: "Gaps, borders, blur, input, animations",
              keywords: "hyprland compositor wm gaps border rounding opacity blur shadow input sensitivity focus scroll animation speed window tiling" }
        ] },

        { label: "Devices", glyph: "󰾰", icon: "devices", views: [
            { file: "SoundPage.qml", label: "Sound", glyph: "󰕾", icon: "volume_up",
              detail: "Output, input, apps",
              keywords: "audio volume speaker microphone mic pipewire output input mute desktop visualiser visualizer cava spectrum bars waveform dots ring album cover peaks caps glow music only colour opacity" },
            { file: "NetworkPage.qml", label: "Network", glyph: "󰈀", icon: "lan",
              detail: "Ethernet, Wi-Fi, speed test, DNS",
              available: root.hasWifi || Net.hasWired,
              keywords: "network wifi wi-fi wireless internet connection ethernet lan cable ssid password dns gateway mac address speed test bandwidth throughput download upload signal latency traffic" },
            { file: "BluetoothPage.qml", label: "Bluetooth", glyph: "󰂯", icon: "bluetooth",
              detail: "Devices and pairing",
              available: root.hasBluetooth,
              keywords: "bluetooth pair headphones earbuds controller mouse keyboard" },
            { file: "DisplaysPage.qml", label: "Displays", glyph: "󰍹", icon: "monitor",
              detail: "Arrangement, resolution, refresh, scale, rotation",
              keywords: "display displays monitor monitors screen screens resolution mode refresh rate hz scale scaling hidpi rotation rotate portrait arrange arrangement position layout vrr freesync gsync adaptive sync multi monitor" },
            { file: "KeyboardPage.qml", label: "Keyboard & mouse", glyph: "󰌌", icon: "keyboard",
              detail: "Layouts, repeat, pointer speed, touchpad",
              keywords: "keyboard layout xkb repeat delay input variant mouse pointer sensitivity speed acceleration accel flat adaptive left handed scroll touchpad trackpad tap click drag natural scrolling palm typing two finger right click" },
            { file: "BatteryPage.qml", label: "Battery", glyph: "󰁽", icon: "battery_full",
              detail: "Health and profile",
              available: root.hasBattery,
              keywords: "battery power charge health profile saver laptop" }
        ] },

        { label: "Apps & tools", glyph: "󰐱", icon: "apps", views: [
            { file: "LauncherPage.qml", label: "Launcher", glyph: "󰀻", icon: "apps",
              detail: "Ask AI, run commands, web search, history",
              keywords: "launcher app search ask ai chat gemini claude chatgpt grok openai anthropic api key provider model terminal command run web search engine duckduckgo history frecency forget super r" },
            { file: "ClipsPage.qml", label: "Clips", glyph: "\u{F0567}", icon: "video_library",
              detail: "Replay buffer, clip it, record, the clip library",
              keywords: "clips clip replay buffer instant replay medal shadowplay record recording screen recorder capture video gpu-screen-recorder save last seconds highlight gallery library trim cut rename share copy fps bitrate quality codec h264 hevc av1 mp4 mkv microphone mic desktop audio region slurp portal monitor folder videos sidebar" },
            { file: "ScreenTimePage.qml", label: "Screen time", glyph: "\u{F051F}", icon: "hourglass_top",
              detail: "How long you spend in each app; history and what's kept",
              keywords: "screen time usage apps hours minutes today week history wellbeing digital tracking focus idle away" },
            { file: "MiscPage.qml", label: "Lyrics", glyph: "󰲹", icon: "queue_music",
              detail: "Lyrics sources and translation",
              keywords: "misc extras lyrics translate spotify netease lrclib bridge subtitle karaoke" },
            { file: "DiscordPage.qml", label: "Discord", glyph: "󰙯", icon: "headset",
              detail: "Call controls: your app, keybinds",
              keywords: "discord voice call mute deafen screenshare camera rpc client secret vesktop webcord legcord" },
            { file: "DiscordPresencePage.qml", label: "Presence", glyph: "󰚩", icon: "sports_esports",
              detail: "Claude Code and Counter-Strike 2 rich presence",
              keywords: "discord rich presence claude code cs2 counter strike game status activity" }
        ] },

        { label: "System", glyph: "󰒓", icon: "settings", views: [
            { file: "UpdatesPage.qml", label: "Updates", glyph: "󰚰", icon: "update",
              detail: "Packages and upgrades",
              keywords: "update upgrade pacman aur flatpak packages yay paru sync" },
            // On a fresh clone this is where you install the core packages and see
            // the Hyprland lines to paste. It still reports missing optional tools. The
            // shell presets (save every setting, carry them to another machine) are its last
            // card: "set up this machine" and "set up the next one" are one trip.
            { file: "SetupPage.qml", label: "Setup", glyph: "󰄬", icon: "checklist",
              detail: "Install and wire up the shell, presets for another machine",
              keywords: "setup install missing dependencies optional tools requirements blocker first run wizard packages hyprland shell preset presets export import portable backup config settings transfer sync machine migrate" },
            { file: "StoragePage.qml", label: "Storage", glyph: "󰋊", icon: "hard_drive",
              detail: "Disks and cleanup",
              keywords: "storage disk drive space cleanup cache trash mount filesystem" },
            { file: "LanguagePage.qml", label: "Language", glyph: "󰗊", icon: "translate",
              detail: "Locale and formats",
              keywords: "language locale region timezone format translation" },
            { file: "AboutPage.qml", label: "About", glyph: "󰋼", icon: "info",
              detail: "This machine",
              keywords: "about version specs system info hardware credits repo" }
        ] }
    ]

    // ── Members: old views that became groups of a composed page ──────────────
    // A view may list `members` — files that used to be pages of their own and are now
    // GROUPS stacked inside it. They are not in `navPages` (the rail and the tab strip
    // only know the host) but they ARE addressable: search finds their rows, a pin
    // names one, and `openSettingsTo("DockPage.qml")` still works. Each resolves to its
    // host (hostOf) and the host scrolls to the group (UiState.settingsGroup).
    //
    // Search needs them as records of their own — "Dock" is a result — so they carry
    // the page they appear under, like any other view.
    readonly property var memberPages: {
        const out = []
        for (const p of root.navPages)
            for (const v of p.views)
                for (const m of (v.members ?? []))
                    out.push(Object.assign({ page: p.label, pageGlyph: p.glyph, host: v.file }, m))
        return out
    }

    // Files that are gone, and the view that took their place — so a remembered page
    // or a pin naming one still lands somewhere sensible.
    readonly property var aliases: ({
        "SidebarDockPage.qml": "SidebarPage.qml",
        // The dock and the stats are modules like the rest since 2026-11-08: their
        // settings are in Bar › Modules' inspector (UiState.openSettingsTo picks them).
        "DockPage.qml": "BarPage.qml",
        "SidebarStatsPage.qml": "BarPage.qml",
        "ShellPresetPage.qml": "SetupPage.qml",     // its card is Setup's last one now
        "WidgetStylePage.qml": "WidgetsPage.qml",  // the Style view was merged into Widgets
        "NetworkTrafficPage.qml": "NetworkPage.qml" // Traffic is gone; its speed test is on Network
    })

    // The file of the view that actually renders `file`: itself, its host, or what
    // replaced it.
    function hostOf(file) {
        if (root.aliases[file] !== undefined) return root.aliases[file]
        const m = root.memberPages.find(function (x) { return x.file === file })
        return m ? m.host : file
    }

    // ── What the rail draws ───────────────────────────────────────────────────
    // The catalogue with unavailable views filtered out. Availability is a FILTER,
    // not a concat chain: a gated view stays where it belongs instead of being
    // forced to the end of its page.
    readonly property var navPages: root._catalogue
        .map(function (p) {
            return { label: p.label, glyph: p.glyph, icon: p.icon,
                     views: p.views.filter(function (v) { return v.available !== false }) }
        })
        .filter(function (p) { return p.views.length > 0 })

    // ── Every available view, flat ────────────────────────────────────────────
    // What search and file lookups walk. Each record carries the name of the page
    // it belongs to (`page`), which is the search result's group.
    readonly property var pages: {
        const out = []
        for (const p of root.navPages)
            for (const v of p.views)
                out.push(Object.assign({ page: p.label, pageGlyph: p.glyph }, v))
        return out
    }

    // ── The generated half ────────────────────────────────────────────────────
    property var indexEntries: []
    // False until the file has been read or confirmed absent, so the UI can say
    // "page names only" rather than silently returning fewer results.
    property bool indexLoaded: false

    FileView {
        path: Quickshell.shellPath("modules/settings/settings-index.json")
        // REQUIRED. FileView is lazy: without preload it does not read until
        // something calls text(), so onLoaded never fires and the index is silently
        // empty. Same trap already documented in Pins.qml, Colors.qml and JsonStore.
        preload: true
        // An absent index is a degraded state, not a failure worth logging on every
        // start — search still works on page names.
        printErrors: false

        onLoaded: {
            try {
                const doc = JSON.parse(this.text())
                root.indexEntries = Array.isArray(doc?.entries) ? doc.entries : []
            } catch (e) {
                console.warn("SettingsIndex: malformed settings-index.json —", e)
                root.indexEntries = []
            }
            root.indexLoaded = true
        }

        onLoadFailed: {
            root.indexEntries = []
            root.indexLoaded = true
        }
    }

    // Everything searchable, page records and generated records merged. A plain
    // property rather than a function so bindings have something to depend on, and
    // so the merge runs once per change instead of once per keystroke.
    readonly property var searchable:
        Search.buildEntries(root.pages.concat(root.memberPages), root.indexEntries)

    // ── Ask this, don't reimplement it ────────────────────────────────────────
    // The ranking lives in settingssearch.js with its cases pinned
    // (`bun scripts/test-settingssearch.js`). This is the only entry point.
    function search(query, limit) {
        return Search.search(root.searchable, query, limit === undefined ? 20 : limit)
    }

    // Ranked results folded by view, and the highlight split — both in the .js so
    // the tests pin them.
    function group(results) { return Search.groupResults(results) }
    function splitMatch(text, query) { return Search.splitMatch(text, query) }

    // ── Pinned views ──────────────────────────────────────────────────────────
    // Config holds the file names; this resolves them to live view records, drops any
    // whose view isn't currently available, and keeps the user's pin order. The rail
    // renders this above the page list.
    readonly property var pinned: {
        const out = []
        for (const f of Config.settingsPinned) {
            const v = root.pageFor(f)
            if (v) out.push(v)
        }
        return out
    }

    // The view record for a file, or undefined.
    function pageFor(file) {
        // A pin or a remembered page naming a file that moved on (ShellPresetPage) is the view that took it.
        const f = root.aliases[file] ?? file
        return root.pages.find(function (p) { return p.file === f })
            ?? root.memberPages.find(function (p) { return p.file === f })
    }

    // The rail page a file's view belongs to, or undefined.
    function navPageFor(file) {
        const host = root.hostOf(file)
        return root.navPages.find(function (p) {
            return p.views.some(function (v) { return v.file === host })
        })
    }
}
