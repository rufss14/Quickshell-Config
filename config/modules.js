.pragma library

// ── modules.js ────────────────────────────────────────────────────────────────
// The ONE catalogue of shell modules — the things that can sit on the top bar or on
// the sidebar. Metadata only: what a module IS, never where it sits (that's
// Config.layout / Config.sidebarLayout, one per surface, both the layout.js algebra).
//
// A module is { id, label, bar?, side? }. `bar` / `side` are its FORMS: the pill the
// top bar draws, the cell the sidebar draws. A module is offered on a surface only if
// it has a form for it, so growing the pool onto the other surface is adding a form
// here (and the widget it names), not a second catalogue entry.
//
//   bar:  { home, description }          home: "left" | "centre" | "right"
//   side: { home, description, glyph,    home: "start" | "centre" | "end"
//           small?, cells? }             small/cells: SideRail's sizing (see Config)
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
      bar: { home: "left",
          description:
            "Switches the bar between <b>rounded</b> and <b>square, edge-to-edge</b> corners." },
      side: { home: "start", small: true, cells: 1, glyph: "\u{F0607}",
          description:
            "Switches the top bar between rounded and square corners." } },
    { id: "modeToggle", label: "Bar mode",
      bar: { home: "left",
          description:
            "Moves the bar between <b>floating</b> and <b>on the frame</b>." },
      side: { home: "start", small: true, cells: 1, glyph: "\u{F059F}",
          description:
            "Moves the top bar between floating and on the frame." } },
    { id: "palette", label: "Colour scheme",
      bar: { home: "left",
          description:
            "Opens the <b>palette panel</b> — the wallpaper-derived scheme and its variants." },
      side: { home: "start", small: true, cells: 1, glyph: "\u{F0E0C}",
          description:
            "The palette panel beside it — the wallpaper-derived scheme and its variants." } },
    { id: "wallpaper", label: "Wallpaper",
      bar: { home: "left",
          description:
            "Opens the <b>wallpaper picker</b>. <i>Choosing one re-derives the whole palette.</i>" },
      side: { home: "start", small: true, cells: 1, glyph: "\u{F0E09}",
          description:
            "Opens the wallpaper picker (in the top bar's dock). <i>Choosing one re-derives the whole palette.</i>" } },
    { id: "volume", label: "Volume",
      bar: { home: "left",
          description:
            "<b>Scroll</b> to change volume, <b>click</b> for the mixer, <b>right-click</b> for the slider." },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F057E}",
          description:
            "The output level under the speaker; scroll to change it, click for the mixer beside it. <i>Middle-click: mute.</i>" } },
    { id: "keyboard", label: "Keyboard layout",
      bar: { home: "centre",
          description:
            "The active <b>xkb layout</b>. Click to cycle through the ones you've configured." },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F030C}",
          description:
            "The active keyboard layout; click to cycle through yours." } },
    { id: "update", label: "Updates",
      bar: { home: "centre",
          description:
            "<b>Pending package count.</b> Click to review and install them." },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F06B0}",
          description:
            "Pending package count; click to review and install them." } },
    { id: "workspaces", label: "Workspaces",
      bar: { home: "centre",
          description:
            "Five dots, paging <b>1–5 / 6–10</b>. <i>The bar's visual anchor — it sits on true centre.</i>" } },
    { id: "reload", label: "Reload",
      bar: { home: "centre",
          description:
            "<b>Restarts the shell.</b> <i>Useful while editing the config, easy to hit by accident.</i>" },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F0450}",
          description:
            "Restarts the shell. <i>Refuses while an update is installing.</i>" } },
    { id: "tray", label: "System tray",
      bar: { home: "centre",
          description:
            "Background app icons. <i>Hides itself when nothing is running.</i>" } },
    { id: "visualizer", label: "Visualizer",
      bar: { home: "right", hero: true,
          description:
            "Audio spectrum. <b>Click</b> opens Now Playing — media, lyrics and translation. <b>Right-click</b> toggles the desktop background." } },
    { id: "wifi", label: "Wi-Fi",
      bar: { home: "right",
          description:
            "<b>Signal strength</b>, tinted by quality. Click for networks, <b>right-click</b> for the name." },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F0928}",
          description:
            "The network, as its signal; click for networks beside it." } },
    { id: "gamemode", label: "Gamemode",
      bar: { home: "right",
          description:
            "<b>One switch before you play.</b> Click for the panel — the switch, a live GPU/CPU glance, the per-effect toggles and the MangoHud preset. <b>Right-click</b> toggles it. <i>Everything is restored when you turn it off.</i>" },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F0297}",
          description:
            "Gamemode; click for the gaming panel beside it. <i>Middle-click: switch it.</i>" } },
    { id: "idle", label: "Stay awake",
      bar: { home: "right",
          description:
            "<b>Stops the screen blanking.</b> Takes your accent while <i>you're</i> holding it, and the info tint while something else is — gamemode holds it too, and a click won't clear that one." },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F0208}",
          description:
            "Keeps the screen awake while lit. <i>Tinted when something else holds it.</i>" } },
    { id: "bluetooth", label: "Bluetooth",
      bar: { home: "right",
          description:
            "<b>Radio state</b>, and what's connected. Click for your paired devices, <b>right-click</b> for the name. <i>Hides itself on a machine with no adapter.</i>" },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F00AF}",
          description:
            "Bluetooth; click for devices beside it." } },
    { id: "battery", label: "Battery",
      bar: { home: "right",
          description:
            "<b>Charge level</b>, red below 15%. Click for health and power mode, <b>right-click</b> for the percentage. <i>Hides itself on a machine with no battery.</i>" },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F0079}",
          description:
            "Charge, under the battery; click for Settings › Battery." } },
    { id: "clock", label: "Clock",
      bar: { home: "right", hero: true,
          description:
            "The time. Click for the <b>clock panel</b> — today's weather on a ring of hours you can spin, the week ahead, and your <b>calendar</b>." },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F0150}",
          description:
            "The time; click for the calendar beside it." } },
    { id: "notifications", label: "Notifications",
      bar: { home: "right",
          description:
            "Opens the <b>notification centre</b>. <b>Right-click</b> toggles <b>Do Not Disturb</b> — the bell changes icon and colour while it's on." },
      side: { home: "start", small: true, cells: 1, glyph: "\u{F009A}",
          description:
            "A bell with a dot when something's new since you last looked; the notification centre in a panel beside it. <i>Middle-click: Do Not Disturb.</i>" } },
    { id: "overview", label: "Overview",
      bar: { home: "left",
          description:
            "Opens the <b>overview</b> — recent windows, search, workspaces, power, volume and brightness." },
      side: { home: "start", small: true, cells: 1, glyph: "\u{F003B}",
          description:
            "Opens the overview." } },
    { id: "settings", label: "Settings",
      bar: { home: "left",
          description:
            "Opens the <b>settings</b> page of the overview." },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F0493}",
          description:
            "Opens Settings." } },
    { id: "privacy", label: "Microphone",
      bar: { home: "right",
          description:
            "Appears when <b>something is using your microphone</b>, and names nothing else — its presence is the signal. Click for the mixer. <i>Invisible while nothing is recording.</i>" },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F036C}",
          description:
            "Lights red while an app is recording your microphone." } },
    { id: "nightlight", label: "Night light",
      bar: { home: "right",
          description:
            "Warms the screen after dark. <b>Click</b> to toggle; the schedule and temperature live in <b>Settings → Night light</b>. <i>Hides itself when neither hyprsunset nor gammastep is installed.</i>" },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F0594}",
          description:
            "Warms the screen; click again to clear it." } },
    { id: "clips", label: "Clips",
      bar: { home: "right",
          description:
            "<b>Click</b> for the clip recorder. <i>Middle-click: save the buffer.</i>" },
      side: { home: "start", small: true, cells: 1, glyph: "\u{F0567}",
          description:
            "Clip and record with gpu-screen-recorder: a button, its controls in a panel beside it. <i>Clipping itself stays off until you turn it on.</i>" } },
    { id: "dock", label: "Dock",
      side: { home: "centre", glyph: "\u{F10A9}",
          description:
            "Pinned and running apps." } },
    { id: "nowplaying", label: "Now playing",
      side: { home: "centre", small: true, cells: 1, glyph: "\u{F075A}",
          description:
            "The album cover in a cookie that turns with the beat, in a wavy progress ring. <i>Click: the media panel. Middle-click: play/pause. Scroll: next/previous.</i>" } },
    { id: "stats", label: "System stats",
      bar: { home: "right",
          description:
            "<b>Click</b> for CPU, memory, GPU and disks. <i>Middle-click: the system monitor.</i>" },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F0EE0}",
          description:
            "A glance at CPU, GPU, memory and more; everything in a panel beside it." } },
    { id: "tools", label: "Shell tools",
      bar: { home: "right",
          description:
            "<b>Click</b> for the launcher. <i>Middle-click: the keybind cheatsheet.</i>" },
      side: { home: "start", small: true, cells: 2, glyph: "\u{F003B}",
          description:
            "The app launcher and the keybind cheatsheet, a click away." } },
    { id: "power", label: "Power",
      bar: { home: "right",
          description:
            "<b>Click</b> for the power menu. <i>Middle-click: lock.</i>" },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F0425}",
          description:
            "One button; click for the power menu over the whole screen — lock, suspend, hibernate, log out, restart, firmware, shut down. <i>All but lock ask twice. Middle-click: lock.</i>" } },
    { id: "voice", label: "Voice",
      bar: { home: "right",
          description:
            "<b>Click</b> mutes your mic (in a Discord call: your Discord mic). <i>Middle-click in a call: deafen.</i>" },
      side: { home: "end", small: true, glyph: "\u{F036C}",
          description:
            "Your mic. <i>In a Discord call:</i> who's in it, who's talking, mute and deafen; click a face for the call panel, right-click one for that person's volume and mute." } },
    { id: "colour", label: "Colour picker",
      bar: { home: "right",
          description:
            "<b>Click</b> to pick a colour off the screen. <i>Needs hyprpicker.</i>" },
      side: { home: "start", small: true, glyph: "\u{F020A}",
          description:
            "Pick a colour off the screen; the last few stay as swatches to copy again. <i>Needs hyprpicker.</i>" } },
    { id: "clipboard", label: "Clipboard",
      bar: { home: "right",
          description:
            "<b>Click</b> for clipboard history; click an entry to copy it again." },
      side: { home: "start", small: true, cells: 1, glyph: "\u{F014D}",
          description:
            "Clipboard history in a panel beside it; click an entry to copy it again." } },
    { id: "timer", label: "Timer",
      bar: { home: "right",
          description:
            "<b>Click</b> for the countdown, stopwatch and alarms." },
      side: { home: "start", small: true, cells: 1, glyph: "\u{F051B}",
          description:
            "A countdown, a stopwatch and alarms in a panel beside it; a ring fills while one runs. <i>Middle-click: start or stop.</i>" } },
    { id: "lens", label: "Lens",
      bar: { home: "right",
          description:
            "<b>Click</b>, drag a region, and copy, search or translate its text. <i>Middle-click: translate at once. Needs tesseract.</i>" },
      side: { home: "start", small: true, cells: 1, glyph: "\u{F113D}",
          description:
            "Read the text off any part of the screen: drag a region, then copy it, search it, or translate it in place. <i>Middle-click: translate at once. Needs tesseract.</i>" } },
    { id: "claude", label: "Claude Code",
      bar: { home: "right",
          description:
            "<b>Click</b> for your Claude Code sessions. <i>Middle-click: go to the one that needs you.</i>" },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F06C4}",
          description:
            "Your Claude Code sessions: the mark turns while one works, a dot when one finished or needs your permission; the panel lists them and takes you to their terminal. <i>Middle-click: go to the one that needs you.</i>" } },
    // ── Both surfaces (2026-10-07) ────────────────────────────────────────────
    // The first modules built with BOTH forms from the start: a pill on the top bar and
    // a cell on the sidebar, opening one panel either dock can hold.
    { id: "brightness", label: "Brightness",
      bar: { home: "right",
          description:
            "<b>Scroll</b> to dim the screen this bar is on; <b>click</b> for every display's slider. <i>External monitors need ddcutil.</i>" },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F00DF}",
          description:
            "Scroll to dim this screen; click for every display's slider beside it. <i>External monitors need ddcutil.</i>" } },
    { id: "window", label: "Focused window",
      bar: { home: "left",
          description:
            "The window this screen is on: its <b>app icon and title</b>. <b>Click</b> to float, fullscreen, pin, move or close it." },
      side: { home: "start", small: true, cells: 1, glyph: "\u{F01C4}",
          description:
            "The window this screen is on: its app icon with the app's name under it; hover for the title and state. Click to float, fullscreen, pin, move or close it." } },
    { id: "layout", label: "Window layout",
      bar: { home: "left",
          description:
            "Hyprland's tiling layout. <b>Scroll</b> to switch between dwindle, master, scrolling and monocle; <b>click</b> for the layouts and their moves. <i>Kept for the next start.</i>" },
      side: { home: "start", small: true, cells: 1, glyph: "\u{F093C}",
          description:
            "Hyprland's tiling layout; scroll to switch, click for the layouts and their moves." } },
    { id: "locks", label: "Submap & locks",
      bar: { home: "right",
          description:
            "Appears while a Hyprland <b>submap</b>, <b>Caps Lock</b> or <b>Num Lock</b> is on, and names it. <i>Invisible otherwise.</i>" },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F030C}",
          description:
            "Lights while a Hyprland submap, Caps Lock or Num Lock is on." } },
    { id: "screentime", label: "Screen time",
      bar: { home: "right",
          description:
            "<b>Click</b> for today's apps and the last week." },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F051F}",
          description:
            "How long you spend in each app: today's apps and the last week in a panel beside it; hover for today's total. Counts only while you're at the machine; kept on this computer. <i>Turn tracking on in its panel or settings.</i>" } },
    { id: "inactivity", label: "Idle actions",
      bar: { home: "right",
          description:
            "<b>Click</b> to set what happens after you stop using the machine: lock, screen off, suspend, log out, power off or a command, each after its own time. <i>Stay awake and Gamemode pause every rule.</i>" },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F03E5}",
          description:
            "What the machine does when you stop using it: a list of rules, each lock, screen off, suspend, log out, power off or a command after its own time, in a panel beside it. <i>Dim while off; Stay awake and Gamemode pause every rule.</i>" } },
    { id: "tasks", label: "To-do",
      bar: { home: "right",
          description:
            "<b>Click</b> for your to-do list: add a task, tick it off, clear what's done." },
      side: { home: "end", small: true, cells: 1, glyph: "\u{F0139}",
          description:
            "Your to-do list in a panel beside it; a badge counts what's still open. Kept on this computer." } }
];

// The catalogue as one surface sees it: entries flattened to { id, label, ...form },
// in catalogue order, for the modules that have a form there.
function forSurface(surface) {
    return MODULES.filter(m => m[surface]).map(m => Object.assign({ id: m.id, label: m.label }, m[surface]));
}

// Does `id` have a form for `surface` ("bar" | "side")?
function hasForm(id, surface) {
    return MODULES.some(m => m.id === id && m[surface]);
}
