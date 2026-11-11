.pragma library

// ── modules.js ────────────────────────────────────────────────────────────────
// The ONE catalogue of shell modules — the things that can sit on the top bar or on
// the sidebar. Metadata only: what a module IS, never where it sits (that's
// Config.layout / Config.sidebarLayout, one per surface, both the layout.js algebra).
//
// A module is { id, label, category, blurb, heroable?, native?, bar?, side? }.
//
//   category  which library shelf it sits on (CATEGORIES below)
//   blurb     one plain line (no markup, ≤ ~70 chars) for the library tile; the
//             per-form `description` is the long, rich-text one the inspector shows
//   heroable  may wear the surface's hero chip (Config.barHero / sidebarHero). One
//             flag for both surfaces: the hero is a fact about the module, and the
//             surface it sits on decides which hero string names it
//   native    "bar" | "side": where the library's "+ Add" puts it. Defaults to the bar
//             when it has a bar form; the sidebar-born modules say "side"
//
// `bar` / `side` are its FORMS: the pill the
// top bar draws, the cell the sidebar draws. A module is offered on a surface only if
// it has a form for it, so growing the pool onto the other surface is adding a form
// here (and the widget it names), not a second catalogue entry.
//
//   bar:  { home, description, opts? }   home: "left" | "centre" | "right"
//   side: { home, description, glyph,    home: "start" | "centre" | "end"
//           small?, cells?, opts? }      small/cells: SideRail's sizing (see Config)
//
// `opts` lists the per-module extras that FORM honours (OPTS below), so the inspector
// shows a control only where the widget really reads it — "the widget consumes this"
// is a fact only the widget knows, and it used to be a hand-kept list in the inspector.
//
// `home` is where addModule() puts it when it comes back from the pool; `glyph` is
// how the settings tray draws it. Descriptions are UI text (rich text), per form,
// because "click" means a different thing on a pill and on a cell.
//
// Config.moduleList / Config.sidebarModuleList are forSurface() of this — the shapes
// every consumer already reads — so nothing downstream knows there is one list.
// `bun scripts/test-modules.js` pins that.
//
// A module has one place: on the bar or on the sidebar, never both
// (Config.addModule / sidebarAdd take it off the other).
// ─────────────────────────────────────────────────────────────────────────────

var MODULES = [
    { id: "shapeToggle", label: "Bar shape",
      category: "look", blurb: "Rounded or square, edge-to-edge bar corners",
      bar: { home: "left", opts: ["spacing"],
          description:
            "Switches the bar between <b>rounded</b> and <b>square, edge-to-edge</b> corners." },
      side: { home: "start", small: true, cells: 1, glyph: "\u{F0607}",
          description:
            "Switches the top bar between rounded and square corners." } },
    { id: "modeToggle", label: "Bar mode",
      category: "look", blurb: "Floats the bar or welds it onto the screen frame",
      bar: { home: "left", opts: ["spacing"],
          description:
            "Moves the bar between <b>floating</b> and <b>on the frame</b>." },
      side: { home: "start", small: true, cells: 1, glyph: "\u{F059F}",
          description:
            "Moves the top bar between floating and on the frame." } },
    { id: "palette", label: "Colour scheme",
      category: "look", blurb: "The colour scheme drawn from your wallpaper",
      bar: { home: "left", opts: ["spacing"],
          description:
            "Opens the <b>palette panel</b> — the wallpaper-derived scheme and its variants." },
      side: { home: "start", small: true, cells: 1, glyph: "\u{F0E0C}",
          description:
            "The palette panel beside it — the wallpaper-derived scheme and its variants." } },
    { id: "wallpaper", label: "Wallpaper",
      category: "look", blurb: "Pick a wallpaper; the whole palette follows it",
      bar: { home: "left", opts: ["spacing"],
          description:
            "Opens the <b>wallpaper picker</b>. <i>Choosing one re-derives the whole palette.</i>" },
      side: { home: "start", small: true, cells: 1, glyph: "\u{F0E09}",
          description:
            "Opens the wallpaper picker (in the top bar's dock). <i>Choosing one re-derives the whole palette.</i>" } },
    { id: "volume", label: "Volume",
      category: "media", blurb: "Output level: scroll to change it, click for the mixer",
      bar: { home: "left", opts: ["rightClick", "panelHeader"],
          description:
            "<b>Scroll</b> to change volume, <b>click</b> for the mixer, <b>right-click</b> for the slider." },
      side: { home: "end", opts: ["panelHeader"], small: true, cells: 1, glyph: "\u{F057E}",
          description:
            "The output level under the speaker; scroll to change it, click for the mixer beside it. <i>Middle-click: mute.</i>" } },
    { id: "keyboard", label: "Keyboard layout",
      category: "status", blurb: "The active keyboard layout; click to cycle",
      bar: { home: "centre", opts: ["spacing"],
          description:
            "The active <b>xkb layout</b>. Click to cycle through the ones you've configured." },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F030C}",
          description:
            "The active keyboard layout; click to cycle through yours." } },
    { id: "update", label: "Updates",
      category: "status", blurb: "Pending package updates, ready to install",
      bar: { home: "centre",
          description:
            "<b>Pending package count.</b> Click to review and install them." },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F06B0}",
          description:
            "Pending package count; click to review and install them." } },
    { id: "workspaces", label: "Workspaces",
      category: "windows", blurb: "Your workspaces as dots, paging five at a time",
      bar: { home: "centre",
          description:
            "Five dots, paging <b>1–5 / 6–10</b>. <i>The bar's visual anchor — it sits on true centre.</i>" },
      side: { home: "start", small: true, cells: 4, glyph: "\u{F0570}",
          description:
            "The bar's five slots, turned down the edge. <b>Click</b> a slot to go there; drop a window on one to move it." } },
    { id: "reload", label: "Reload",
      category: "power", blurb: "Restarts the shell",
      bar: { home: "centre",
          description:
            "<b>Restarts the shell.</b> <i>Useful while editing the config, easy to hit by accident.</i>" },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F0450}",
          description:
            "Restarts the shell. <i>Refuses while an update is installing.</i>" } },
    { id: "tray", label: "System tray",
      category: "windows", blurb: "Background apps' tray icons",
      bar: { home: "centre", opts: ["spacing"],
          description:
            "Background app icons. <i>Hides itself when nothing is running.</i>" },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F08C6}",
          description:
            "Background app icons, one cell each. <b>Right-click</b> one for its menu. <i>Steps aside when nothing is running.</i>" } },
    { id: "visualizer", label: "Visualizer",
      category: "media", blurb: "A live audio spectrum; click for Now Playing", heroable: true,
      bar: { home: "right",
          description:
            "Audio spectrum. <b>Click</b> opens Now Playing — media, lyrics and translation. <b>Right-click</b> toggles the desktop background." },
      side: { home: "end", small: true, cells: 2, glyph: "\u{F0EA3}",
          description:
            "The cover in its ring and the spectrum, turned. <b>Click</b> opens Now Playing; <b>right-click</b> toggles the desktop background." } },
    { id: "wifi", label: "Wi-Fi",
      category: "status", blurb: "Signal strength; click for networks",
      bar: { home: "right", opts: ["spacing", "rightClick"],
          description:
            "<b>Signal strength</b>, tinted by quality. Click for networks, <b>right-click</b> for the name." },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F0928}",
          description:
            "The network, as its signal; click for networks beside it." } },
    { id: "gamemode", label: "Gamemode",
      category: "power", blurb: "One switch before you play, with live GPU/CPU",
      bar: { home: "right", opts: ["spacing", "panelHeader"],
          description:
            "<b>One switch before you play.</b> Click for the panel — the switch, a live GPU/CPU glance, the per-effect toggles and the MangoHud preset. <b>Right-click</b> toggles it. <i>Everything is restored when you turn it off.</i>" },
      side: { home: "end", opts: ["panelHeader"], small: true, cells: 1, glyph: "\u{F0297}",
          description:
            "Gamemode; click for the gaming panel beside it. <i>Middle-click: switch it.</i>" } },
    { id: "idle", label: "Stay awake",
      category: "power", blurb: "Keeps the screen from blanking while lit",
      bar: { home: "right", opts: ["spacing"],
          description:
            "<b>Stops the screen blanking.</b> Takes your accent while <i>you're</i> holding it, and the info tint while something else is — gamemode holds it too, and a click won't clear that one." },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F0208}",
          description:
            "Keeps the screen awake while lit. <i>Tinted when something else holds it.</i>" } },
    { id: "bluetooth", label: "Bluetooth",
      category: "status", blurb: "Radio state and devices; click to connect",
      bar: { home: "right", opts: ["spacing", "rightClick"],
          description:
            "<b>Radio state</b>, and what's connected. Click for your paired devices, <b>right-click</b> for the name. <i>Hides itself on a machine with no adapter.</i>" },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F00AF}",
          description:
            "Bluetooth; click for devices beside it." } },
    { id: "battery", label: "Battery",
      category: "status", blurb: "Charge level, health and power mode",
      bar: { home: "right", opts: ["rightClick"],
          description:
            "<b>Charge level</b>, red below 15%. Click for health and power mode, <b>right-click</b> for the percentage. <i>Hides itself on a machine with no battery.</i>" },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F0079}",
          description:
            "Charge, under the battery; click for Settings › Battery." } },
    { id: "clock", label: "Clock",
      category: "status", blurb: "The time; click for weather and your calendar", heroable: true,
      bar: { home: "right", opts: ["panelHeader"],
          description:
            "The time. Click for the <b>clock panel</b> — today's weather on a ring of hours you can spin, the week ahead, and your <b>calendar</b>." },
      side: { home: "end", opts: ["panelHeader"], small: true, cells: 2, glyph: "\u{F0150}",
          description:
            "The time; click for the calendar beside it." } },
    { id: "notifications", label: "Notifications",
      category: "status", blurb: "The notification centre and Do Not Disturb",
      bar: { home: "right", opts: ["spacing", "dndOnly"],
          description:
            "Opens the <b>notification centre</b>. <b>Right-click</b> toggles <b>Do Not Disturb</b> — the bell changes icon and colour while it's on." },
      side: { home: "start", small: true, cells: 1, glyph: "\u{F009A}",
          description:
            "A bell with a dot when something's new since you last looked; the notification centre in a panel beside it. <i>Middle-click: Do Not Disturb.</i>" } },
    { id: "overview", label: "Overview",
      category: "windows", blurb: "Opens the overview: windows, search, workspaces",
      bar: { home: "left", opts: ["spacing"],
          description:
            "Opens the <b>overview</b> — recent windows, search, workspaces, power, volume and brightness." },
      side: { home: "start", small: true, cells: 1, glyph: "\u{F003B}",
          description:
            "Opens the overview." } },
    { id: "settings", label: "Settings",
      category: "power", blurb: "Opens Settings",
      bar: { home: "left", opts: ["spacing"],
          description:
            "Opens the <b>settings</b> page of the overview." },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F0493}",
          description:
            "Opens Settings." } },
    { id: "privacy", label: "Microphone",
      category: "status", blurb: "Appears only while an app records your microphone",
      bar: { home: "right", opts: ["spacing"],
          description:
            "Appears when <b>something is using your microphone</b>, and names nothing else — its presence is the signal. Click for the mixer. <i>Invisible while nothing is recording.</i>" },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F036C}",
          description:
            "Lights red while an app is recording your microphone." } },
    { id: "nightlight", label: "Night light",
      category: "look", blurb: "Warms the screen after dark",
      bar: { home: "right", opts: ["spacing"],
          description:
            "Warms the screen after dark. <b>Click</b> to toggle; the schedule and temperature live in <b>Settings → Night light</b>. <i>Hides itself when neither hyprsunset nor gammastep is installed.</i>" },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F0594}",
          description:
            "Warms the screen; click again to clear it." } },
    { id: "clips", label: "Clips",
      category: "tools", blurb: "Clip the last moments, or record the screen", native: "side",
      bar: { home: "right",
          description:
            "<b>Click</b> for the clip recorder. <i>Middle-click: save the buffer.</i>" },
      side: { home: "start", opts: ["peek"], small: true, cells: 1, glyph: "\u{F0567}",
          description:
            "Clip and record with gpu-screen-recorder: a button, its controls in a panel beside it. <i>Clipping itself stays off until you turn it on.</i>" } },
    { id: "dock", label: "Dock",
      category: "windows", blurb: "Pinned and running apps", native: "side",
      bar: { home: "centre",
          description:
            "Pinned and running apps at the bar's size. <b>Hover</b> an app for its windows, <b>right-click</b> for its jump list. <i>No magnification on the bar.</i>" },
      side: { home: "centre", glyph: "\u{F10A9}",
          description:
            "Pinned and running apps." } },
    { id: "nowplaying", label: "Now playing",
      category: "media", blurb: "The playing song's cover in a turning ring", heroable: true, native: "side",
      bar: { home: "right",
          description:
            "The album cover in its turning ring, then <b>previous</b>, <b>play/pause</b> and <b>next</b>. <i>Click the cover: the media panel.</i>" },
      side: { home: "centre", small: true, cells: 1, glyph: "\u{F075A}",
          description:
            "The album cover in a cookie that turns with the beat, in a wavy progress ring. <i>Click: the media panel. Middle-click: play/pause. Scroll: next/previous.</i>" } },
    { id: "stats", label: "System stats",
      category: "tools", blurb: "CPU, GPU, memory and disks at a glance", native: "side",
      bar: { home: "right",
          description:
            "<b>Click</b> for CPU, memory, GPU and disks. <i>Middle-click: the system monitor.</i>" },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F0EE0}",
          description:
            "A glance at CPU, GPU, memory and more; everything in a panel beside it." } },
    { id: "tools", label: "Shell tools",
      category: "windows", blurb: "The app launcher and the keybind cheatsheet", native: "side",
      bar: { home: "right",
          description:
            "<b>Click</b> for the launcher. <i>Middle-click: the keybind cheatsheet.</i>" },
      side: { home: "start", small: true, cells: 2, glyph: "\u{F003B}",
          description:
            "The app launcher and the keybind cheatsheet, a click away." } },
    { id: "power", label: "Power",
      category: "power", blurb: "Lock, suspend, restart or shut down", heroable: true, native: "side",
      bar: { home: "right",
          description:
            "<b>Click</b> for the power menu. <i>Middle-click: lock.</i>" },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F0425}",
          description:
            "One button; click for the power menu over the whole screen — lock, suspend, hibernate, log out, restart, firmware, shut down. <i>All but lock ask twice. Middle-click: lock.</i>" } },
    { id: "voice", label: "Voice",
      category: "media", blurb: "Your mic, or who's talking in a Discord call", heroable: true, native: "side",
      bar: { home: "right",
          description:
            "<b>Click</b> mutes your mic (in a Discord call: your Discord mic). <i>Middle-click in a call: deafen.</i>" },
      side: { home: "end", small: true, glyph: "\u{F036C}",
          description:
            "Your mic. <i>In a Discord call:</i> who's in it, who's talking, mute and deafen; click a face for the call panel, right-click one for that person's volume and mute." } },
    { id: "colour", label: "Colour picker",
      category: "tools", blurb: "Pick a colour off the screen and copy it", heroable: true, native: "side",
      bar: { home: "right",
          description:
            "<b>Click</b> to pick a colour off the screen. <i>Needs hyprpicker.</i>" },
      side: { home: "start", opts: ["peek"], small: true, glyph: "\u{F020A}",
          description:
            "Pick a colour off the screen; the last few stay as swatches to copy again. <i>Needs hyprpicker.</i>" } },
    { id: "clipboard", label: "Clipboard",
      category: "tools", blurb: "Clipboard history; click an entry to copy it again", heroable: true, native: "side",
      bar: { home: "right",
          description:
            "<b>Click</b> for clipboard history; click an entry to copy it again." },
      side: { home: "start", opts: ["peek"], small: true, cells: 1, glyph: "\u{F014D}",
          description:
            "Clipboard history in a panel beside it; click an entry to copy it again." } },
    { id: "timer", label: "Timer",
      category: "tools", blurb: "Countdowns, a stopwatch and alarms", heroable: true, native: "side",
      bar: { home: "right",
          description:
            "<b>Click</b> for the countdown, stopwatch and alarms." },
      side: { home: "start", opts: ["peek"], small: true, cells: 1, glyph: "\u{F051B}",
          description:
            "A countdown, a stopwatch and alarms in a panel beside it; a ring fills while one runs. <i>Middle-click: start or stop.</i>" } },
    { id: "lens", label: "Lens",
      category: "tools", blurb: "Read, copy or translate text off the screen", native: "side",
      bar: { home: "right",
          description:
            "<b>Click</b>, drag a region, and copy, search or translate its text. <i>Middle-click: translate at once. Needs tesseract.</i>" },
      side: { home: "start", small: true, cells: 1, glyph: "\u{F113D}",
          description:
            "Read the text off any part of the screen: drag a region, then copy it, search it, or translate it in place. <i>Middle-click: translate at once. Needs tesseract.</i>" } },
    { id: "claude", label: "Claude Code",
      category: "tools", blurb: "Your Claude Code sessions and who needs you", heroable: true, native: "side",
      bar: { home: "right",
          description:
            "<b>Click</b> for your Claude Code sessions. <i>Middle-click: go to the one that needs you.</i>" },
      side: { home: "end", opts: ["peek"], small: true, cells: 1, glyph: "\u{F06C4}",
          description:
            "Your Claude Code sessions: the mark turns while one works, a dot when one finished or needs your permission; the panel lists them and takes you to their terminal. <i>Middle-click: go to the one that needs you.</i>" } },
    // ── Both surfaces (2026-10-07) ────────────────────────────────────────────
    // The first modules built with BOTH forms from the start: a pill on the top bar and
    // a cell on the sidebar, opening one panel either dock can hold.
    { id: "brightness", label: "Brightness",
      category: "media", blurb: "Screen brightness: scroll to dim, click for all",
      bar: { home: "right",
          description:
            "<b>Scroll</b> to dim the screen this bar is on; <b>click</b> for every display's slider. <i>External monitors need ddcutil.</i>" },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F00DF}",
          description:
            "Scroll to dim this screen; click for every display's slider beside it. <i>External monitors need ddcutil.</i>" } },
    { id: "window", label: "Focused window",
      category: "windows", blurb: "The focused window's icon and title",
      bar: { home: "left",
          description:
            "The window this screen is on: its <b>app icon and title</b>. <b>Click</b> to float, fullscreen, pin, move or close it." },
      side: { home: "start", small: true, cells: 1, glyph: "\u{F01C4}",
          description:
            "The window this screen is on: its app icon with the app's name under it; hover for the title and state. Click to float, fullscreen, pin, move or close it." } },
    { id: "layout", label: "Window layout",
      category: "windows", blurb: "Hyprland's tiling layout; scroll to switch",
      bar: { home: "left",
          description:
            "Hyprland's tiling layout. <b>Scroll</b> to switch between dwindle, master, scrolling and monocle; <b>click</b> for the layouts and their moves. <i>Kept for the next start.</i>" },
      side: { home: "start", small: true, cells: 1, glyph: "\u{F093C}",
          description:
            "Hyprland's tiling layout; scroll to switch, click for the layouts and their moves." } },
    { id: "locks", label: "Submap & locks",
      category: "status", blurb: "Appears while Caps Lock, Num Lock or a submap is on",
      bar: { home: "right",
          description:
            "Appears while a Hyprland <b>submap</b>, <b>Caps Lock</b> or <b>Num Lock</b> is on, and names it. <i>Invisible otherwise.</i>" },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F030C}",
          description:
            "Lights while a Hyprland submap, Caps Lock or Num Lock is on." } },
    { id: "screentime", label: "Screen time",
      category: "tools", blurb: "How long you spend in each app", native: "side",
      bar: { home: "right", opts: ["panelHeader"],
          description:
            "<b>Click</b> for today's apps and the last week." },
      side: { home: "end", opts: ["panelHeader"], small: true, cells: 1, glyph: "\u{F051F}",
          description:
            "How long you spend in each app: today's apps and the last week in a panel beside it; hover for today's total. Counts only while you're at the machine; kept on this computer. <i>Turn tracking on in its panel or settings.</i>" } },
    { id: "inactivity", label: "Idle actions",
      category: "power", blurb: "What happens when you step away from the machine", heroable: true, native: "side",
      bar: { home: "right",
          description:
            "<b>Click</b> to set what happens after you stop using the machine: lock, screen off, suspend, log out, power off or a command, each after its own time. <i>Stay awake and Gamemode pause every rule.</i>" },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F03E5}",
          description:
            "What the machine does when you stop using it: a list of rules, each lock, screen off, suspend, log out, power off or a command after its own time, in a panel beside it. <i>Dim while off; Stay awake and Gamemode pause every rule.</i>" } },
    { id: "tasks", label: "To-do",
      category: "tools", blurb: "Your to-do list", heroable: true, native: "side",
      bar: { home: "right",
          description:
            "<b>Click</b> for your to-do list: add a task, tick it off, clear what's done." },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F0139}",
          description:
            "Your to-do list in a panel beside it; a badge counts what's still open. Kept on this computer." } }
];

// The catalogue as one surface sees it: entries flattened to
// { id, label, category, blurb, heroable, ...form },
// in catalogue order, for the modules that have a form there.
function forSurface(surface) {
    return MODULES.filter(m => m[surface]).map(m => Object.assign(
        { id: m.id, label: m.label, category: m.category, blurb: m.blurb,
          heroable: m.heroable === true }, m[surface]));
}

// Does `id` have a form for `surface` ("bar" | "side")?
function hasForm(id, surface) {
    return MODULES.some(m => m.id === id && m[surface]);
}

// ── Library shelves ───────────────────────────────────────────────────────────
// In shelf order. `symbol` is a Material Symbols name already cut into the shell's
// font (services/icons.js) — a new one needs `material-symbols-map.py --emit`.
var CATEGORIES = [
    { id: "status",  label: "Status",          symbol: "info" },
    { id: "media",   label: "Media",           symbol: "music_note" },
    { id: "windows", label: "Windows",         symbol: "view_quilt" },
    { id: "tools",   label: "Tools",           symbol: "widgets" },
    { id: "look",    label: "Look",            symbol: "palette" },
    { id: "power",   label: "Power & session", symbol: "power_settings_new" }
];

// The extras a form can honour (`opts`). The inspector draws one control per key.
//   spacing      group spacing (Config.groupSpacing) — the widget lays out by it
//   rightClick   remember the right-click face (Config.rightClickModules)
//   dndOnly      notifications: show only while Do Not Disturb
//   panelHeader  the module's panel has a switchable title row
//   peek         an event card beside the cell (Config.peek*)
var OPTS = ["spacing", "rightClick", "dndOnly", "panelHeader", "peek"];

// The modules whose panel has a switchable title row (Config.panelHeader): each honours `panelHeader` on
// either form, so it isn't repeated in every `opts`. Not the panels whose header IS their controls
// (colours, wallpaper, Bluetooth, notifications, clips, media, voice, updates): hiding it would hide what they do.
var PANELS = ["volume", "wifi", "gamemode", "clock", "stats", "clipboard", "timer", "claude",
              "brightness", "window", "layout", "screentime", "inactivity", "tasks"];

// One module, whole: its module-level facts plus both forms as they are (null when it
// has none). `native` resolved. null for an unknown id.
function info(id) {
    const m = MODULES.find(x => x.id === id);
    if (!m) return null;
    return {
        id: m.id, label: m.label, category: m.category, blurb: m.blurb,
        heroable: m.heroable === true,
        native: m.native || (m.bar ? "bar" : "side"),
        bar: m.bar || null, side: m.side || null
    };
}

// Does a form of `id` honour option `key`? `surface` "bar" | "side".
function hasOpt(id, surface, key) {
    const m = MODULES.find(x => x.id === id);
    const f = m && m[surface];
    if (key === "panelHeader") return !!f && PANELS.indexOf(id) !== -1;
    return !!(f && f.opts && f.opts.indexOf(key) !== -1);
}

// Library search: case-insensitive, every whitespace-separated word must hit the
// label, the blurb, the shelf's name or the id.
function matches(m, query) {
    const q = String(query || "").toLowerCase().trim();
    if (q === "") return true;
    const cat = CATEGORIES.find(c => c.id === m.category);
    const hay = [m.label, m.blurb, cat ? cat.label : "", m.id].join(" ").toLowerCase();
    return q.split(/\s+/).every(w => hay.indexOf(w) !== -1);
}

// The library's shelves: [{ id, label, symbol, modules: [info…] }], in CATEGORIES
// order, empty shelves left out. `filter` "all" | "unused"; `placedFn(id)` says
// whether a module is on either surface (Config's, so this stays pure).
function shelves(query, filter, placedFn) {
    const out = [];
    for (const c of CATEGORIES) {
        const mods = MODULES
            .filter(m => m.category === c.id && matches(m, query)
                         && (filter !== "unused" || !(placedFn && placedFn(m.id))))
            .map(m => info(m.id));
        if (mods.length > 0)
            out.push({ id: c.id, label: c.label, symbol: c.symbol, modules: mods });
    }
    return out;
}
