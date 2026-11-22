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
// Two readers need it: SettingsCard (the rail) and search, which
// has to resolve a result's `file` to a page NAME and know whether that page
// currently exists. One list, so twenty strings that get renamed have one home.
//
// ── Two halves, joined here ───────────────────────────────────────────────────
//   catalogue  hand-written below. Sections, their pages, glyphs, keywords, and the
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
    // its page without a restart — and unplugging it removes the page AND its rows
    // from the search index, so a result can never navigate somewhere that isn't
    // there. A desktop simply has no Battery page rather than a charge stuck at 0%.
    readonly property bool hasBattery: UPower.displayDevice?.isLaptopBattery ?? false
    readonly property bool hasWifi: Net.hasWifi
    // Via the service rather than Bluetooth.adapters directly, so this and
    // Bar.moduleVisible() are literally the same expression — the page and the bar
    // pill appear together or not at all.
    readonly property bool hasBluetooth: Bt.available

    // ── The catalogue: seven sections, each a list of pages ───────────────────
    // The rail lists SECTIONS; the current one unfolds in place to list its pages, and
    // every page is one rail row — there are no tabs above a page. Each section answers
    // one question:
    //   Look & feel     how the shell looks, sounds and feels (and how warm the screen is)
    //   Wallpaper       what's behind it
    //   Bar & islands   the bar, the sidebar, and everything that opens out of them
    //   Desktop         widgets, the desktop menu, the lock screen, and Hyprland itself
    //   Devices         hardware attached to this machine
    //   Apps            the launcher, clips, screen time, and the apps the shell talks to
    //   System          packages, setup (and presets), storage, language, the machine underneath
    //
    // A PAGE is a page FILE plus an optional `anchor`, and its KEY is `file` or
    // `file#anchor` (keyOf). Several pages may share one file through anchors; the file is
    // loaded once and reads UiState.settingsAnchor to show the right part, so moving
    // between them never reloads it. A bare file names the first page with that file, so
    // `Config.settingsPage`, a pin and `UiState.openSettingsTo(file)` written before
    // anchors existed keep landing — nothing that opens settings to a particular place
    // (battery pill, disk widget, IPC) has to change.
    //
    // `views` holds a section's pages (the field keeps its name for memberPages and
    // settingssearch.js, which read it).
    //
    // `parts` / `sections` (optional) say which search entries of a SHARED file a page
    // shows: by source file stem (the index's `part`) or by card title. An entry nobody
    // claims belongs to the file's first page (settingssearch.js pageOfEntry).
    //
    // `keywords` carries the terms that should FIND a page without being its name —
    // including every earlier name of it or its section ("hyprland", "misc", "tuning",
    // "behaviour"), so a rename never costs someone who already knew the old word.
    //
    // `shape` is the MorphShape the section's badge blooms into while it is open; each
    // section has its own.
    //
    // `available: false` hides a page; a section whose pages are all hidden is dropped.
    readonly property var _catalogue: [
        { label: "Look & feel", glyph: "󰉼", icon: "palette", shape: "cookie9", views: [
            { file: "AppearancePage.qml", label: "Colours", glyph: "󰸌", icon: "palette",
              detail: "Palette, light and dark, album colours, schemes, looks",
              keywords: "appearance theme colour color colours colors palette pywal wal wallpaper dark light mode album cover icon tint look feel scheme schemes catppuccin mocha latte gruvbox dracula alucard nord tokyo night rose pine solarized generated custom saved classic classics preset export import" },
            { file: "ShapePage.qml", label: "Type, shape & motion", glyph: "󰛖", icon: "text_fields",
              detail: "Font, scale, spacing, corners, surfaces",
              keywords: "style font family text scale size density spacing rounding radius roundness shadow opacity transparency settings window panel type shape motion animation reduced appearance" },
            { file: "NightLightPage.qml", label: "Night light", glyph: "󰖔", icon: "dark_mode",
              detail: "Screen warmth and schedule",
              keywords: "night light blue warmth temperature gamma sunset sunrise hyprsunset gammastep eyes appearance" },
            { file: "CursorPage.qml", label: "Cursor", glyph: "\u{F01C0}", icon: "mouse",
              detail: "Mouse pointer in the shell's colours",
              keywords: "cursor mouse pointer arrow hand xcursor hyprcursor colour color theme size accent hover effects animation tilt rotate stretch shake find dynamic-cursors hyprpm plugin appearance" },
            { file: "SoundEffectsPage.qml", label: "Sound effects", glyph: "󰕾", icon: "notifications_active",
              detail: "Swooshes, typing, timer and alarm, shutter",
              keywords: "sound effects sfx swoosh whoosh typing keyboard click key clicks typewriter noise audio feedback ui sounds panel open close notification chime volume mute timer alarm bell beep screenshot shutter clip saved capture mixer level appearance" }
        ] },

        // Four pages on ONE file: WallpaperPage reads UiState.settingsAnchor ("" = the gallery)
        // and moving between them never reloads it, so a half-made pick survives. `parts` say
        // which of its source files each page shows, so a search hit lands on the right one.
        { label: "Wallpaper", glyph: "󰸉", icon: "wallpaper", shape: "clover", views: [
            { file: "WallpaperPage.qml", label: "Gallery", glyph: "󰸉", icon: "image",
              detail: "Your images and scenes, favourites, the library",
              parts: ["WallpaperPage", "WallpaperGalleryView", "WallpaperPageTile", "WallpaperBrowseView", "WallpaperPropertiesView"],
              keywords: "wallpaper background picture image images gallery library folder browse import add favourite favourites star refresh scenes list" },
            { file: "WallpaperPage.qml", anchor: "placement", label: "Placement & motion", glyph: "󰸉", icon: "tune",
              detail: "Fill, parallax, shuffle, per workspace, the depth clock",
              parts: ["WallpaperAppearanceView", "WallpaperWorkspaces"],
              keywords: "wallpaper appearance drawn by renderer fill fit parallax zoom pointer workspace per workspace follow shuffle timer slideshow depth clock material monitor motion" },
            { file: "WallpaperPage.qml", anchor: "scenes", label: "Scenes", glyph: "\u{F0567}", icon: "movie",
              detail: "Wallpaper Engine scenes: renderer, frame rate, sound, properties",
              parts: ["WallpaperEngineView"],
              keywords: "wallpaper engine workshop steam scene scenes live animated video renderer frame rate fps vsync v-sync mute volume audio properties linux-wallpaperengine" },
            { file: "WallpaperPage.qml", anchor: "music", label: "Music on the desktop", glyph: "󰲹", icon: "music_note",
              detail: "Wallpaper effects that move with the song",
              parts: ["WallpaperEffectsView", "WallFxSoundRow"],
              keywords: "wallpaper music effects audio visualizer visualiser cava beat glow blur zoom shake rumble shockwave shimmer pulse glitch bloom strobe breakdown adapt song sound map intensity sync bpm tempo latency delay kick snare clap hi-hat drums bass vocals" }
        ] },

        { label: "Bar & islands", glyph: "󰍜", icon: "dashboard", shape: "sunny", views: [
            { file: "BarPage.qml", label: "Modules", glyph: "󰮐", icon: "dashboard",
              detail: "What's on the bar and the sidebar, and every module's settings",
              keywords: "panel taskbar topbar statusbar sidebar side modules layout arrange drag group region pill widget library catalogue add remove hero accent inner pill spacing peek dock taskbar launcher pinned pins running apps previews thumbnails magnify magnification trash downloads stats system monitor cpu gpu ram memory network temperature alert bar" },
            { file: "BarStylePage.qml", label: "Style", glyph: "󰸌", icon: "layers",
              detail: "How both look — the sidebar follows the bar unless unlinked",
              keywords: "bar sidebar size height thickness roundness corners opacity translucent inner pill preset square text icon scale link unlink same as bar override islands music glow rim" },
            { file: "SidebarPage.qml", label: "Sidebar", glyph: "\u{F06FD}", icon: "vertical_split",
              detail: "The sidebar's edge, size and auto-hide; where the bar centres",
              keywords: "sidebar side edge position left right bottom autohide auto-hide hide dodge reveal empty workspace reserve space exclusive icon size anchor centre workspaces behaviour behavior dock" },
            { file: "IslandPage.qml", label: "Islands", glyph: "󰕮", icon: "pip",
              detail: "The bar's islands: which pages each one holds, in what order, and how they open",
              keywords: "island islands handle notch hover click bar top card rail pages arrange order drag board move panel side left right centre middle placement alone column hide dashboard weather media music performance switches pill live delay linger size effects per island override desktop panel popup resize zoom reset backdrop cookies panels settings window docked" },
            { file: "HotCornerPage.qml", label: "Hot corner", glyph: "󰕮", icon: "crop_free",
              detail: "A panel that slides out of a screen corner",
              keywords: "hot corner screen corner edge pointer hover panel quick settings volume brightness switches toggles media pinned apps capture screenshot record slide out desktop" }
        ] },

        { label: "Desktop", glyph: "󰕮", icon: "widgets", shape: "squircle", views: [
            { file: "WidgetsPage.qml", label: "Widgets", glyph: "󰕮", icon: "dashboard",
              detail: "Place and tune desktop widgets, and how they all look",
              keywords: "desktop widgets clock notes calendar overlay gallery add arrange style opacity roundness glass snap grid parallax weather location city celsius layout preset hover grow entrance calendars ics" },
            { file: "DeskMenuPage.qml", label: "Desktop menu", glyph: "󰕮", icon: "menu_open",
              detail: "What a right-click on the desktop opens",
              keywords: "desktop menu right click context menu wallpapers pictures buttons switches night light do not disturb game mode lock places edit widgets displays settings" },
            { file: "LockPage.qml", label: "Lock screen", glyph: "󰌾", icon: "lock",
              detail: "Auto-lock and PAM",
              keywords: "lock screen idle timeout password pam screensaver security avatar desktop" },
            // Hyprland, named for the category and not the product: "hyprland" is in
            // `keywords` for anyone who already knows the product name.
            { file: "HyprlandPage.qml", label: "Keybinds", glyph: "󰌋", icon: "keyboard",
              detail: "Read, rebind and add Hyprland keybinds",
              keywords: "hyprland compositor wm keybind bind shortcut hotkey window manager desktop" },
            { file: "HyprTuningPage.qml", label: "Windows", glyph: "󰂵", icon: "rounded_corner",
              detail: "Gaps, borders, blur, input, animations",
              keywords: "hyprland compositor wm gaps border rounding opacity blur shadow input sensitivity focus scroll animation speed window windows tiling tuning desktop" }
        ] },

        { label: "Devices", glyph: "󰾰", icon: "devices", shape: "cookie6", views: [
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
            { file: "TabletPage.qml", label: "Tablet", glyph: "\u{F03EB}", icon: "tablet",
              detail: "Pen pressure, express keys, live pen",
              keywords: "tablet drawing pen stylus wacom huion xp-pen intuos pressure express keys buttons pad digitizer opentabletdriver otd stroke draw art area mapping profile" },
            { file: "BatteryPage.qml", label: "Battery & power", glyph: "󰁽", icon: "battery_full",
              detail: "Health and profile",
              available: root.hasBattery,
              keywords: "battery power charge health profile saver laptop" }
        ] },

        { label: "Apps", glyph: "󰐱", icon: "apps", shape: "hexagon", views: [
            { file: "LauncherPage.qml", label: "Launcher", glyph: "󰀻", icon: "apps",
              detail: "Ask AI, run commands, web search, history",
              keywords: "launcher app search ask ai chat gemini claude chatgpt grok openai anthropic api key provider model terminal command run web search engine duckduckgo history frecency forget super r apps tools" },
            { file: "ClipsPage.qml", label: "Clips", glyph: "\u{F0567}", icon: "video_library",
              detail: "Replay buffer, clip it, record, the clip library",
              keywords: "clips clip replay buffer instant replay medal shadowplay record recording screen recorder capture video gpu-screen-recorder save last seconds highlight gallery library trim cut rename share copy fps bitrate quality codec h264 hevc av1 mp4 mkv microphone mic desktop audio region slurp portal monitor folder videos sidebar apps tools" },
            { file: "ScreenTimePage.qml", label: "Screen time", glyph: "\u{F051F}", icon: "hourglass_top",
              detail: "How long you spend in each app; history and what's kept",
              keywords: "screen time usage apps hours minutes today week history wellbeing digital tracking focus idle away tools" },
            { file: "MiscPage.qml", label: "Lyrics", glyph: "󰲹", icon: "queue_music",
              detail: "Lyrics sources and translation",
              keywords: "misc extras lyrics translate spotify netease lrclib bridge subtitle karaoke apps tools" },
            { file: "DiscordPage.qml", label: "Discord", glyph: "󰙯", icon: "headset",
              detail: "Call controls, your app, keybinds, rich presence",
              keywords: "discord voice call mute deafen screenshare camera rpc client secret vesktop webcord legcord apps tools rich presence claude code cs2 counter strike game status activity" }
        ] },

        { label: "System", glyph: "󰒓", icon: "settings", shape: "pentagon", views: [
            { file: "UpdatesPage.qml", label: "Updates", glyph: "󰚰", icon: "update",
              detail: "Packages and upgrades",
              keywords: "update upgrade pacman aur flatpak packages yay paru sync" },
            // On a fresh clone this is where you install the core packages and see
            // the Hyprland lines to paste. It still reports missing optional tools. The
            // shell presets (save every setting, carry them to another machine) are its last
            // card: "set up this machine" and "set up the next one" are one trip.
            { file: "SetupPage.qml", label: "Setup & presets", glyph: "󰄬", icon: "checklist",
              detail: "Install and wire up the shell, presets for another machine",
              keywords: "setup install missing dependencies optional tools requirements blocker first run wizard packages hyprland shell preset presets export import portable backup config settings transfer sync machine migrate" },
            // Two pages on one file: StoragePage reads UiState.settingsAnchor. The package list
            // is a card on that file, claimed by its title (`sections`), so its rows land on
            // Packages and the rest on Storage.
            { file: "StoragePage.qml", label: "Storage", glyph: "󰋊", icon: "hard_drive",
              detail: "Disks and cleanup",
              keywords: "storage disk drive space cleanup cache trash mount filesystem home folder reclaim" },
            { file: "StoragePage.qml", anchor: "packages", label: "Packages", glyph: "󰚰", icon: "inventory_2",
              detail: "What you installed on purpose, and what to remove",
              sections: ["Installed on purpose"],
              keywords: "packages package installed explicit pacman aur remove uninstall orphans list size" },
            { file: "LanguagePage.qml", label: "Language & region", glyph: "󰗊", icon: "translate",
              detail: "Locale and formats",
              keywords: "language locale region timezone format translation" },
            { file: "AboutPage.qml", label: "About", glyph: "󰋼", icon: "info",
              detail: "This machine",
              keywords: "about version specs system info hardware credits repo" }
        ] }
    ]

    // ── Members: page files shown as groups of a composed page ────────────────
    // A page may list `members` — files with page names of their own that render as
    // GROUPS stacked inside it. They are not rail rows (the rail only knows the host)
    // but they ARE addressable: search finds their rows, a pin names one, and
    // `openSettingsTo("SomePage.qml")` still works. Each resolves to its host (hostOf).
    // Nothing lists members today: anchors (keyOf) are how one file holds several rail
    // rows, and `aliasPlate` is how a file that was folded into another lands on its card.
    //
    // Search needs them as records of their own, so they carry the section they appear
    // under, like any other page.
    readonly property var memberPages: {
        const out = []
        for (const p of root.navPages)
            for (const v of p.views)
                for (const m of (v.members ?? []))
                    out.push(Object.assign({ page: p.label, pageGlyph: p.glyph, host: v.file, key: m.file }, m))
        return out
    }

    // Files that are gone, and the page that took their place — so a remembered page
    // or a pin naming one still lands somewhere sensible. A target may carry its own
    // `#anchor`; scripts/check-settings-links.py fails on a target that is not a page.
    readonly property var aliases: ({
        "SidebarDockPage.qml": "SidebarPage.qml",
        // The dock and the stats are modules like the rest: their settings are in
        // Bar › Modules' inspector (UiState.openSettingsTo picks them).
        "DockPage.qml": "BarPage.qml",
        "SidebarStatsPage.qml": "BarPage.qml",
        "ShellPresetPage.qml": "SetupPage.qml",     // its card is Setup's last one
        "WidgetStylePage.qml": "WidgetsPage.qml",  // Widgets holds the style options
        "NetworkTrafficPage.qml": "NetworkPage.qml", // the speed test is on Network
        "ColorSchemesPage.qml": "AppearancePage.qml",  // Colours holds the schemes
        "BarPanelsPage.qml": "IslandPage.qml",         // Islands holds the panel options
        "DiscordPresencePage.qml": "DiscordPage.qml"   // Discord holds rich presence
    })

    // An aliased file that was folded into a page as one of its cards: a link to the old
    // file lands on the new page AND reveals that card (SettingsCard.goTo sets
    // UiState.settingsTarget). { oldFile: card title }, beside its `aliases` entry.
    readonly property var aliasPlate: ({
        "ColorSchemesPage.qml": "Classics",
        "BarPanelsPage.qml": "Panels",
        "DiscordPresencePage.qml": "Claude Code"
    })

    // The card a link to `key` should reveal ("" for none): the plate of the file it
    // names, or of any file its alias chain passes through.
    function plateOf(key) {
        let file = root._split(key).file
        for (let hops = 0; hops < 8 && file !== ""; hops++) {
            if (root.aliasPlate[file] !== undefined) return root.aliasPlate[file]
            if (root.aliases[file] === undefined) break
            file = root._split(root.aliases[file]).file
        }
        return ""
    }

    // ── Settings that live outside the app ────────────────────────────────────
    // Panels and island pages carry settings the app has no row for (they belong next to
    // the thing they change). Search still finds them: each is a result that says where it
    // lives and opens that place (UiState.openElsewhere). Hand-written, because the panels
    // are not in the generated index; keep each title the control's own label.
    //
    //   where  the place's human name, said as "In the <where> island/panel" (or "In the
    //          overview"); scored like a page name, so "gaming" finds the Gaming switches
    //   open   { page, part }  an island page (config/islands.js), on a part where the page
    //                          supports one (`qs ipc … island part`); off a rail, its panel
    //          { panel }       a bar panel itself, in its column (Now Playing: the island's
    //                          Media page is the player, the settings are on the panel)
    //          { overview }    the overview
    //
    // A plain literal, no bindings or Translation: scripts/test-settingssearch.js reads it
    // straight out of this file and pins it.
    readonly property var elsewhere: [
        // Game Mode (services/gamefx.js EFFECTS, GamingEffectsView)
        { title: "Performance", where: "Gaming", open: { page: "gaming" },
          keywords: "game mode gamemode gamemoderun governor cpu gpu clocks priority session" },
        { title: "Silence notifications", where: "Gaming", open: { page: "gaming" },
          keywords: "game mode gamemode do not disturb dnd quiet hold notifications" },
        { title: "Keep screen awake", where: "Gaming", open: { page: "gaming" },
          keywords: "game mode gamemode idle inhibitor blank lock screensaver" },
        { title: "Pause wallpaper", where: "Gaming", open: { page: "gaming" },
          keywords: "game mode gamemode scene stop live wallpaper engine" },
        { title: "Hide visualiser", where: "Gaming", open: { page: "gaming" },
          keywords: "game mode gamemode visualizer cava spectrum" },
        { title: "Mute typing sounds", where: "Gaming", open: { page: "gaming" },
          keywords: "game mode gamemode keyboard key sounds sfx clicks" },
        { title: "Record clips", where: "Gaming", open: { page: "gaming" },
          keywords: "game mode gamemode replay buffer clips recording" },
        { title: "Lighter desktop", where: "Gaming", open: { page: "gaming" },
          keywords: "game mode gamemode blur shadows animations compositor hyprland" },
        { title: "Start with gamemoderun games", where: "Gaming", open: { page: "gaming" },
          keywords: "game mode gamemode automatic auto follow games launch" },
        { title: "Start with Steam games", where: "Gaming", open: { page: "gaming" },
          keywords: "game mode gamemode automatic auto steam proton launch" },

        // The tablet's daily half, on the bottom-left island (IslandTablet)
        { title: "Tablet screen and area", where: "Tablet", open: { page: "tablet", part: "map" },
          keywords: "tablet pen wacom screen monitor output area active area map mapping rotate rotation orientation relative absolute left handed aspect ratio" },
        { title: "Tablet profiles", where: "Tablet", open: { page: "tablet", part: "profiles" },
          keywords: "tablet pen wacom profile profiles preset presets switch drawing" },
        { title: "Tablet test pad", where: "Tablet", open: { page: "tablet", part: "test" },
          keywords: "tablet pen wacom test draw scribble pressure try" },

        // Now Playing's Settings tab (MediaPanel): lyrics extras and karaoke
        { title: "Romanize lyrics", where: "Now Playing", open: { panel: "media" },
          keywords: "lyrics romanization romanize romaji pinyin kanji japanese korean chinese latin letters" },
        { title: "Allow Google romanization", where: "Now Playing", open: { panel: "media" },
          keywords: "lyrics romanization romanize online google kanji" },
        { title: "Cache romanizations", where: "Now Playing", open: { panel: "media" },
          keywords: "lyrics romanization romanize cache keep" },
        { title: "Translation language", where: "Now Playing", open: { panel: "media" },
          keywords: "lyrics translate translation language target code en es ja" },
        { title: "Cache translations", where: "Now Playing", open: { panel: "media" },
          keywords: "lyrics translate translation cache keep week" },
        { title: "Sing along", where: "Now Playing", open: { panel: "media" },
          keywords: "karaoke sing microphone mic score game osu lyrics" },
        { title: "Match the words", where: "Now Playing", open: { panel: "media" },
          keywords: "karaoke words recognition speech timing score" },
        { title: "Hear the Discord call", where: "Now Playing", open: { panel: "media" },
          keywords: "karaoke discord call voice friends" },
        { title: "Song language", where: "Now Playing", open: { panel: "media" },
          keywords: "karaoke language speech model recognition" },
        { title: "Speech model", where: "Now Playing", open: { panel: "media" },
          keywords: "karaoke speech model download vosk recognition words" },
        { title: "I'm on headphones", where: "Now Playing", open: { panel: "media" },
          keywords: "karaoke headphones speakers echo check" },
        { title: "Karaoke mods", where: "Now Playing", open: { panel: "media" },
          keywords: "karaoke mods modifiers hidden hd hard rock hr time hell th osu" },

        // The mixer (EqualizerPanel)
        { title: "Boost past 100%", where: "Equalizer", open: { page: "equalizer", part: "options" },
          keywords: "mixer volume boost louder over 100 amplify audio" },
        { title: "Remember each output's volume", where: "Equalizer", open: { page: "equalizer", part: "options" },
          keywords: "mixer volume remember levels per device output headphones speakers audio" },
        { title: "Restart audio", where: "Equalizer", open: { page: "equalizer", part: "options" },
          keywords: "mixer pipewire wireplumber restart audio sound broken" },
        { title: "Volume limit", where: "Equalizer", open: { page: "equalizer", part: "devices" },
          keywords: "mixer device volume cap caps limit maximum max balance left right output" },

        // Colour scheme (ColorSchemePanel, SchemeAlbum)
        { title: "Where the album colours go", where: "Colour scheme", open: { page: "colorScheme", part: "album" },
          keywords: "album cover colour color scope everywhere workspaces spotify scheme music" },
        { title: "After the music stops", where: "Colour scheme", open: { page: "colorScheme", part: "album" },
          keywords: "album cover colour color hold linger keep stay seconds minutes scheme music" },
        { title: "Album colours apply to", where: "Colour scheme", open: { page: "colorScheme", part: "album" },
          keywords: "album cover colour color this shell everything apps gtk qt scheme" },
        { title: "Colour scheme per workspace", where: "Colour scheme", open: { page: "colorScheme", part: "library" },
          keywords: "colour color scheme palette workspace workspaces per workspace different" },
        { title: "Edit a colour scheme", where: "Colour scheme", open: { page: "colorScheme", part: "edit" },
          keywords: "colour color scheme palette custom edit slots create own" },

        // Wallpaper (WallpaperPanel, WallpaperMaterial)
        { title: "Sort wallpapers", where: "Wallpaper", open: { page: "wallpaper", part: "images" },
          keywords: "wallpaper sort order name newest colour color gallery" },
        { title: "Show favourites only", where: "Wallpaper", open: { page: "wallpaper", part: "images" },
          keywords: "wallpaper favourites favorites starred filter gallery" },
        { title: "Shuffle starred only", where: "Wallpaper", open: { page: "wallpaper", part: "images" },
          keywords: "wallpaper shuffle favourites favorites starred random" },
        { title: "Material Wallpaper looks", where: "Wallpaper", open: { page: "wallpaper", part: "material" },
          keywords: "material wallpaper style preset looks save shapes generated" },
        { title: "Material Wallpaper colour", where: "Wallpaper", open: { page: "wallpaper", part: "material" },
          keywords: "material wallpaper colour color main accent shapes contrast ground tint" },
        { title: "Material Wallpaper shapes", where: "Wallpaper", open: { page: "wallpaper", part: "material" },
          keywords: "material wallpaper shapes background centre side corner softness size mirror" },
        { title: "Material Wallpaper motion", where: "Wallpaper", open: { page: "wallpaper", part: "material" },
          keywords: "material wallpaper motion drift spin speed animate keep shell closes" },

        // Clock (ClockPanel's Clocks view)
        { title: "World clocks", where: "Clock", open: { page: "clock" },
          keywords: "world clock clocks time zone zones timezone city cities" },
        { title: "Alarms", where: "Clock", open: { page: "clock" },
          keywords: "alarm alarms wake up repeat clock timer" },

        // The overview's window inspector (WorkspaceLabels)
        { title: "App labels", where: "overview", open: { overview: true },
          keywords: "app label labels workspace name icon rename window inspector" }
    ]

    // ── Page keys ─────────────────────────────────────────────────────────────
    // `file` or `file#anchor`. Everything that remembers or requests a page holds one.
    function keyOf(v) {
        return v.anchor ? v.file + "#" + v.anchor : v.file
    }

    function _split(key) {
        const s = String(key ?? "")
        const i = s.indexOf("#")
        return i < 0 ? { file: s, anchor: "" } : { file: s.slice(0, i), anchor: s.slice(i + 1) }
    }

    // Follows `aliases` until the file part is not one. The requested anchor survives
    // unless the alias target names its own. Guarded: a cycle in the table would
    // otherwise hang every lookup, so it stops and says so.
    function _resolveAlias(key) {
        let k = root._split(key)
        for (let hops = 0; root.aliases[k.file] !== undefined; hops++) {
            if (hops >= 8) {
                console.warn("SettingsIndex: alias cycle at", k.file)
                break
            }
            const t = root._split(root.aliases[k.file])
            k = { file: t.file, anchor: t.anchor !== "" ? t.anchor : k.anchor }
        }
        return k
    }

    // The FILE that actually renders `key`: itself, its host, or what replaced it.
    function hostOf(key) {
        const file = root._resolveAlias(key).file
        const m = root.memberPages.find(function (x) { return x.file === file })
        return m ? m.host : file
    }

    // The rail page (a record of `pages`) that `key` lands on, or undefined:
    // the exact page, else the first page of the file that renders it — a bare file, an
    // old alias, a member, or an anchor that no longer exists all land there.
    function entryFor(key) {
        const k = root._resolveAlias(key)
        if (k.file === "") return undefined
        if (k.anchor !== "") {
            const exact = root.pages.find(function (p) { return p.file === k.file && p.anchor === k.anchor })
            if (exact) return exact
        }
        const host = root.hostOf(k.file)
        return root.pages.find(function (p) { return p.file === host })
    }

    // ── What the rail draws ───────────────────────────────────────────────────
    // The catalogue with unavailable pages filtered out. Availability is a FILTER,
    // not a concat chain: a gated page stays where it belongs instead of being
    // forced to the end of its section. Each page record carries its `key`.
    readonly property var navPages: root._catalogue
        .map(function (p) {
            return { label: p.label, glyph: p.glyph, icon: p.icon, shape: p.shape,
                     views: p.views
                         .filter(function (v) { return v.available !== false })
                         .map(function (v) { return Object.assign({ key: root.keyOf(v), anchor: v.anchor ?? "" }, v) }) }
        })
        .filter(function (p) { return p.views.length > 0 })

    // ── Every available page, flat, in rail order ─────────────────────────────
    // What search, key lookups and the card's ↑↓ walk. Each record carries the name
    // of the section it belongs to (`page`), which is the search result's group.
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
    // …and the settings outside the app, for the one caller that can open them.
    readonly property var _searchableEverywhere:
        root.searchable.concat(Search.elsewhereEntries(root.elsewhere))

    // ── Ask this, don't reimplement it ────────────────────────────────────────
    // The ranking lives in settingssearch.js with its cases pinned
    // (`bun scripts/test-settingssearch.js`). This is the only entry point.
    //
    // `everywhere` adds the elsewhere results. Off by default: the launcher and the
    // assistant open a result by its `file`, which an elsewhere result has none of.
    function search(query, limit, everywhere) {
        return Search.search(everywhere ? root._searchableEverywhere : root.searchable,
                             query, limit === undefined ? 20 : limit)
    }

    // Ranked results folded by view, and the highlight split — both in the .js so
    // the tests pin them.
    function group(results) { return Search.groupResults(results) }
    function splitMatch(text, query) { return Search.splitMatch(text, query) }

    // ── Pinned pages ──────────────────────────────────────────────────────────
    // Config holds the page keys; this resolves them to live page records, drops any
    // whose page isn't currently available, and keeps the user's pin order. The rail
    // renders this above the sections.
    readonly property var pinned: {
        const out = []
        for (const f of Config.settingsPinned) {
            const v = root.pageFor(f)
            // A pin saved under an old (aliased) file and one under its page's key are one pin.
            if (v && !out.some(function (p) { return p.key === v.key })) out.push(v)
        }
        return out
    }

    // Pins are compared by the page they resolve to, not by the saved string.
    function isPinned(key) {
        const e = root.entryFor(key)
        return !!e && root.pinned.some(function (p) { return p.key === e.key })
    }
    function togglePin(key) {
        const e = root.entryFor(key)
        if (!e) return
        const rest = Config.settingsPinned.filter(function (f) {
            const v = root.entryFor(f)
            return !(v && v.key === e.key)
        })
        Config.settingsPinned = rest.length < Config.settingsPinned.length ? rest : rest.concat([e.key])
    }

    // The record for a key — a rail page, or a member (search shows a member under its
    // own name) — or undefined.
    function pageFor(key) {
        const e = root.entryFor(key)
        if (e) return e
        const file = root._resolveAlias(key).file
        return root.memberPages.find(function (p) { return p.file === file })
    }

    // The section a key's page belongs to, or undefined.
    function navPageFor(key) {
        const e = root.entryFor(key)
        if (!e) return undefined
        return root.navPages.find(function (p) {
            return p.views.some(function (v) { return v.key === e.key })
        })
    }
}
