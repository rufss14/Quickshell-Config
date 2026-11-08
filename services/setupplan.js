.pragma library

// ── setupplan.js ──────────────────────────────────────────────────────────────
// What setting this shell up consists of, as logic rather than QML: the steps and what each one
// needs, what a scan of the machine says (`parseScan`), which steps are done / still to do / blocked
// (`catalogue`), what to run for a selection with its dependencies pulled in (`buildPlan`), and what a
// failed step's output actually means (`explainFailure`). services/Setup.qml gathers the facts and runs
// the jobs; modules/onboard/SetupFlow.qml shows it. Pure functions: `bun scripts/test-setupplan.js`.
//
// ── One plan, one button ──────────────────────────────────────────────────────
// Setup used to be seven pages and about fifteen separate install buttons, one job at a time. Now it is a
// list of steps: the RECOMMENDED ones are ticked, the optional ones are not, and "Set up N things" runs the
// ticked ones in order — pulling in what they need (a step that builds from the AUR needs an AUR helper,
// which needs the base tools), skipping what is already done, and carrying on past a failure for every
// step that did not depend on it.
//
// ── The facts ─────────────────────────────────────────────────────────────────
//   arch, network, pacmanLock, pacmanRunning, diskMiB, sudo, polkitAgent      the machine
//   quickshell, hyprland, qt                                                    versions ("0.3.2")
//   gpu ("AMD"|"Intel"|"NVIDIA"|""), vulkan ["vulkan-radeon"], nvidiaProprietary
//   aurHelper "yay"|"paru"|"none", coreMissing (count), pywal
//   blobInstalled (the .so is on disk), morph (it loads)
//   hyprConfig "bundled"|"minimal"|"other"|"absent", autostart, bindCount
//   themes { gtk: { state, sudo, detail }, … }, palette (colors.json exists)
//   optional { wpe, argos, songrec, spicetify, bridge, awww }  booleans (installed / wired)
// ─────────────────────────────────────────────────────────────────────────────

// The versions this config was last checked against (setup.sh's own): a newer one very likely works, so
// a mismatch is a warning, never a stop.
var TESTED = { quickshell: "0.3.", hyprland: "0.56.", qt: "6.11." }

// ── What a scan said ─────────────────────────────────────────────────────────
// scripts/setup-scan.sh prints `key=value` lines; this reads them. Unknown keys are dropped, a missing
// one stays at its default (so a partial scan is still a scan).
function parseScan(text) {
    var f = { arch: false, network: null, pacmanLock: false, pacmanRunning: false, diskMiB: 0, sudo: false,
              polkitAgent: false, quickshell: "", hyprland: "", qt: "", gpu: "", vulkan: [], nvidiaProprietary: false,
              aurHelper: "none", blobInstalled: false, distro: "" }
    var bools = { arch: 1, pacmanLock: 1, pacmanRunning: 1, sudo: 1, polkitAgent: 1, nvidiaProprietary: 1, blobInstalled: 1 }
    String(text === undefined || text === null ? "" : text).split("\n").forEach(function (line) {
        var i = line.indexOf("=")
        if (i < 1) return
        var k = line.slice(0, i).trim(), v = line.slice(i + 1).trim()
        if (bools[k]) f[k] = v === "1"
        else if (k === "network") f.network = v === "1" ? true : v === "0" ? false : null
        else if (k === "diskMiB") f.diskMiB = Math.max(0, parseInt(v, 10) || 0)
        else if (k === "vulkan") f.vulkan = v.split(/\s+/).filter(function (x) { return /^[a-z0-9][a-z0-9+._-]*$/.test(x) })
        else if (k === "gpu") f.gpu = /^(AMD|Intel|NVIDIA)$/.test(v) ? v : ""
        else if (k === "aurHelper") f.aurHelper = v === "yay" || v === "paru" ? v : "none"
        else if (k === "quickshell" || k === "hyprland" || k === "qt" || k === "distro")
            f[k] = /^[A-Za-z0-9._ -]{0,40}$/.test(v) ? v : ""
    })
    return f
}

// ── Does this machine suit the config ────────────────────────────────────────
// → [{ id, label, have, want, state }], state "ok" | "warn" | "unknown". A version that is not the tested
// one is a warning (the shell is young and so is Hyprland: an untested pair "very likely works").
function compat(f) {
    function row(id, label, have, want) {
        var h = String(have || "")
        return { id: id, label: label, have: h, want: want + "x",
                 state: h === "" ? "unknown" : h.indexOf(want) === 0 ? "ok" : "warn" }
    }
    return [row("quickshell", "Quickshell", f.quickshell, TESTED.quickshell),
            row("hyprland",   "Hyprland",   f.hyprland,   TESTED.hyprland),
            row("qt",         "Qt",         f.qt,         TESTED.qt)]
}

// Things that stop a package step, or are worth saying before it starts. → [{ id, level, text }]
// "fatal" blocks every step that installs packages; "warn" is only said.
function blockers(f) {
    var out = []
    if (!f.arch)
        out.push({ id: "arch", level: "fatal", text: "Setup installs packages with pacman, so it needs Arch Linux (or a derivative). "
                   + "On another distribution, install the packages in the README by hand." })
    if (f.pacmanLock)
        out.push({ id: "lock", level: "fatal", text: "A pacman database lock is in place — another package manager is running, "
                   + "or one crashed and left /var/lib/pacman/db.lck behind." })
    else if (f.pacmanRunning)
        out.push({ id: "running", level: "fatal", text: "pacman is running right now. Wait for it to finish, then re-check." })
    if (f.network === false)
        out.push({ id: "network", level: "fatal", text: "No network: packages, the AUR and the themes are all downloads." })
    if (f.diskMiB > 0 && f.diskMiB < 1500)
        out.push({ id: "disk", level: "fatal", text: "Only " + f.diskMiB + " MB are free — the packages and the plugin build need about 1.5 GB." })
    else if (f.diskMiB > 0 && f.diskMiB < 4000)
        out.push({ id: "disk", level: "warn", text: "Only " + (Math.round(f.diskMiB / 102.4) / 10) + " GB are free. It will fit, but not by much." })
    return out
}

// ── Hyprland: how to wire the shell in ───────────────────────────────────────
// The bundled config REPLACES ~/.config/hypr (backed up first). That is right for a machine with no Hyprland
// config of its own and wrong for one that has; so the default is to leave yours alone and add one file
// (quicktest.lua). `bundled` stays on the bundle (re-running it is how you update it).
function hyprMode(hyprConfig) {
    return hyprConfig === "absent" || hyprConfig === "bundled" ? "full" : "minimal"
}

// ── The catalogue ────────────────────────────────────────────────────────────
// One row per step. `jobs` are the Setup job ids it runs, in order; `deps` the step ids it needs first;
// `root` whether any of it needs your password (or a polkit dialog); `eta` seconds, a guess to say "about
// 6 min" with; `group` where it sits ("essentials" | "yours" | "extras"). `state`:
//   done      already the case (Custom can still redo it)
//   todo      to do
//   blocked   cannot run right now — `why` says what to fix
// Order here IS the order they run in.
var ORDER = ["core", "aurhelper", "aur", "clips", "gamemode", "blob", "hypr", "autostart", "themes", "colours",
             "spotify", "wpe", "argos", "songrec", "awww", "ddc", "beatsync", "discordkeys"]

function _installed(f, k) { return !!(f.optional && f.optional[k]) }
// A feature pack (install-dependencies.sh PACK_PKGS): every one of its packages is installed.
function _pack(f, k) { return !!(f.packs && f.packs[k]) }

function catalogue(f, mode) {
    var m = mode || hyprMode(f.hyprConfig)
    var themeTodo = Object.keys(f.themes || {}).filter(function (id) { return f.themes[id].state === "todo" })
    var themeRoot = themeTodo.some(function (id) { return f.themes[id].sudo })
    var bl = blockers(f)
    var fatal = bl.filter(function (b) { return b.level === "fatal" })
    var net = f.network === false
    // A step that installs a package cannot run past a fatal blocker.
    var pkgWhy = fatal.length ? fatal[0].text : ""
    var needHelper = f.aurHelper === "none"

    function mk(id, group, title, detail, o) {
        var s = { id: id, group: group, title: title, detail: detail, jobs: o.jobs || [], deps: o.deps || [], root: !!o.root,
                  eta: o.eta || 15, done: !!o.done, recommended: !!o.recommended, optional: group === "extras",
                  why: o.why || "", verb: o.verb || "Set up", hint: o.hint || "" }
        s.state = s.done ? "done" : s.why !== "" ? "blocked" : "todo"
        // A blocked step that is also done is just done.
        return s
    }
    var steps = []

    steps.push(mk("core", "essentials", "System packages",
        f.coreMissing > 0 ? f.coreMissing + (f.coreMissing === 1 ? " package is" : " packages are") + " missing — the shell, its fonts, the screen recorder, the tools it calls"
                          : "Everything the shell needs from the repositories is installed",
        { jobs: ["core"], root: true, eta: Math.max(30, f.coreMissing * 6), done: f.coreMissing === 0, recommended: true,
          why: f.coreMissing > 0 ? pkgWhy : "", verb: "Install" }))

    if (needHelper)
        steps.push(mk("aurhelper", "essentials", "AUR helper",
            "paru, so AUR packages can be built — installed once, from the AUR",
            { jobs: ["aurhelper"], deps: ["core"], root: true, eta: 120, done: false, recommended: !f.pywal,
              why: pkgWhy, verb: "Install" }))
    steps.push(mk("aur", "essentials", "Theming tools",
        f.pywal ? "pywal16 is installed — wallpapers and colour schemes can repaint everything"
                : "pywal16 — without it a wallpaper or a colour scheme changes nothing outside the shell",
        { jobs: ["aur"], deps: needHelper ? ["aurhelper"] : [], root: true, eta: 90, done: f.pywal, recommended: true,
          why: f.pywal ? "" : pkgWhy, verb: "Install" }))

    // Feature packs the shell ships ticked: most people want them, but they're nobody's requirement.
    steps.push(mk("clips", "yours", "Clips",
        _pack(f, "clips") ? "The recorder is installed — replay buffer, recordings and the clip editor"
                          : "A replay buffer and screen recorder, with a built-in editor to trim and export",
        { jobs: ["pack-clips"], root: true, eta: 40, done: _pack(f, "clips"), recommended: true,
          why: _pack(f, "clips") ? "" : pkgWhy, verb: "Install" }))
    steps.push(mk("gamemode", "yours", "Game Mode",
        _pack(f, "gamemode") ? "gamemode and MangoHud are installed"
                             : "gamemode and MangoHud — the Game Mode toggle, the performance overlay and the Gaming panel",
        { jobs: ["pack-gamemode"], root: true, eta: 20, done: _pack(f, "gamemode"), recommended: true,
          why: _pack(f, "gamemode") ? "" : pkgWhy, verb: "Install" }))

    steps.push(mk("blob", "yours", "The fused bar (Morph plugin)",
        f.morph ? "Built and loaded — the bar melts into its panels"
        : f.blobInstalled ? "Installed but not loading — it needs a rebuild after a Qt update"
        :                   "Compiled once (a few minutes): the bar and its open panels fuse into one shape",
        { jobs: ["pack-blob", "blob"], deps: ["core"], root: true, eta: 260, done: f.morph, recommended: true,
          why: f.morph ? "" : pkgWhy, verb: f.blobInstalled ? "Rebuild" : "Build",
          hint: "Compiles C++ against your Qt, then installs one file into /usr/lib/qt6/qml." }))

    var hyprDone = m === "full" ? f.hyprConfig === "bundled" : f.hyprConfig === "minimal"
    steps.push(mk("hypr", "yours", m === "full" ? "Hyprland config" : "Hyprland keybinds",
        m === "full"
            ? (f.hyprConfig === "absent" ? "No Hyprland config yet — installs the bundled one: monitors, keybinds, animations, rules"
               : f.hyprConfig === "bundled" ? "The bundled config is active"
               : "Replaces ~/.config/hypr with the bundled config (yours is backed up first)")
            : (f.hyprConfig === "minimal" ? "quicktest.lua is in place — add require(\"quicktest\") to your hyprland.lua if you haven't"
               : "Keeps your config and adds one file, quicktest.lua, with just the shell's keybinds and rules"),
        { jobs: [m === "full" ? "hypr" : "hyprMin"], eta: 5, done: hyprDone, recommended: true, verb: "Set up",
          hint: m === "full" ? "Backs up whatever is in ~/.config/hypr before replacing it."
                             : "Then add  require(\"quicktest\")  near the top of your hyprland.lua." }))

    steps.push(mk("autostart", "yours", "Start with your session",
        f.autostart ? "Hyprland launches the shell at login" : "Nothing launches the shell when you log in",
        { jobs: ["auto"], eta: 3, done: f.autostart, recommended: true }))

    steps.push(mk("themes", "yours", "Theme your apps",
        themeTodo.length ? themeTodo.length + (themeTodo.length === 1 ? " app can" : " apps can") + " follow the shell's colours: "
                           + themeTodo.map(function (id) { return { gtk: "GTK", qt: "Qt", discord: "Discord", spotify: "Spotify", steam: "Steam" }[id] || id }).join(", ")
                         : "Every installed app that can follow the colours already does",
        { jobs: ["theme-all"], root: themeRoot, eta: 60, done: themeTodo.length === 0, recommended: true, verb: "Set up" }))

    steps.push(mk("colours", "yours", "Colours from your wallpaper",
        f.palette ? "A palette is in place" : "Paints the shell, your terminal and every themed app once, from the wallpaper on screen",
        { jobs: ["colours"], deps: f.pywal ? [] : ["aur"], eta: 15, done: f.palette, recommended: true, verb: "Apply" }))

    // ── Extras: each one is somebody's choice, none ticked ────────────────────
    var extraWhy = function (installed) { return installed ? "" : pkgWhy }
    steps.push(mk("spotify", "extras", "Spotify lyrics, word by word",
        "Spicetify and a small extension, so lyrics follow Spotify's own playhead",
        { jobs: ["spicetify", "bridge"], eta: 60, done: _installed(f, "spicetify") && _installed(f, "bridge"), verb: "Set up" }))
    steps.push(mk("wpe", "extras", "Wallpaper Engine",
        "Animated Workshop scenes as the wallpaper (images work fine without it)",
        { jobs: ["wpe"], deps: needHelper ? ["aurhelper"] : [], root: true, eta: 120, done: _installed(f, "wpe"),
          why: extraWhy(_installed(f, "wpe")), verb: "Install" }))
    steps.push(mk("argos", "extras", "Offline lyrics translation",
        "Translates lyrics on this machine instead of sending each line to a web service",
        { jobs: ["argos"], deps: needHelper ? ["aurhelper"] : [], root: true, eta: 120, done: _installed(f, "argos"),
          why: extraWhy(_installed(f, "argos")), verb: "Install" }))
    steps.push(mk("songrec", "extras", "Song recognition",
        "The Now-Playing panel's “what is this song?” buttons",
        { jobs: ["songrec"], deps: needHelper ? ["aurhelper"] : [], root: true, eta: 90, done: _installed(f, "songrec"),
          why: extraWhy(_installed(f, "songrec")), verb: "Install" }))
    steps.push(mk("awww", "extras", "Keep the wallpaper up while the shell restarts",
        "awww holds a still of the wallpaper on screen when the shell is not running",
        { jobs: ["awww"], deps: needHelper ? ["aurhelper"] : [], root: true, eta: 60, done: _installed(f, "awww"),
          why: extraWhy(_installed(f, "awww")), verb: "Install" }))

    steps.push(mk("ddc", "extras", "External monitor brightness",
        "ddcutil, so a desktop monitor gets a brightness slider (laptop screens work without it)",
        { jobs: ["pack-ddc"], root: true, eta: 15, done: _pack(f, "ddc"), why: extraWhy(_pack(f, "ddc")), verb: "Install" }))
    steps.push(mk("beatsync", "extras", "Wallpaper effects on the beat",
        "numpy, so the wallpaper's music effects keep time with the song (without it they follow cava, a little late)",
        { jobs: ["pack-beatsync"], root: true, eta: 20, done: _pack(f, "beatsync"), why: extraWhy(_pack(f, "beatsync")), verb: "Install" }))
    steps.push(mk("discordkeys", "extras", "Discord share and camera buttons",
        "xdotool and wtype, so the Discord call card can press Discord's own screen-share and camera keybinds",
        { jobs: ["pack-discordkeys"], root: true, eta: 15, done: _pack(f, "discordkeys"), why: extraWhy(_pack(f, "discordkeys")), verb: "Install" }))

    steps.forEach(function (st) { st.touches = touchesFor(st.id, f, m) })

    // Dependencies that failed to be reachable make a step blocked too: a step needing a helper that
    // cannot be installed cannot run. (buildPlan pulls the dependency in; this only says why not.)
    return steps.sort(function (a, b) { return ORDER.indexOf(a.id) - ORDER.indexOf(b.id) })
}

// ── What a step will do, in plain words ──────────────────────────────────────
// The drawer on each step's card: the commands it runs, the files it writes, what it asks root for. Written
// from the scripts' own headers — a step that touches your system should be able to say how. → [{ k, t }],
// k "cmd" | "file" | "net" | "root" | "note".
function touchesFor(id, f, m) {
    var helper = f.aurHelper && f.aurHelper !== "none" ? f.aurHelper : "paru"
    function aurPkg(pkg) {
        return [{ k: "cmd", t: helper + " -S --needed " + pkg },
                { k: "net", t: "Builds from the AUR — a few minutes, and it needs the network" },
                { k: "root", t: "pacman asks for root once for the package; the build itself runs as you" }]
    }
    function pack(key) {
        var names = (f.packPkgs && f.packPkgs[key]) || ""
        return [{ k: "root", t: "Runs as root: scripts/install-dependencies.sh --pack " + key },
                { k: "cmd", t: names ? "pacman -S --needed " + names : "pacman -S --needed — this pack's packages, from the repositories" }]
    }
    switch (id) {
    case "clips":       return pack("clips")
    case "gamemode":    return pack("gamemode")
    case "ddc":         return pack("ddc")
    case "beatsync":    return pack("beatsync")
    case "discordkeys": return pack("discordkeys")
    case "core":
        return [{ k: "root", t: "Runs as root: scripts/install-dependencies.sh --core" },
                { k: "cmd", t: "pacman -S --needed — the repository packages, in one transaction (retried one by one if a single name fails)" },
                { k: "cmd", t: f.vulkan && f.vulkan.length ? "The Vulkan driver for your GPU: " + f.vulkan.join(", ")
                                                           : "A software Vulkan driver (no GPU was recognised)" },
                { k: "cmd", t: "otf-codenewroman-nerd, the text font — only if it is missing" }]
    case "aurhelper":
        return [{ k: "net", t: "Clones paru-bin from aur.archlinux.org into a temporary folder" },
                { k: "cmd", t: "makepkg builds it as you, not as root" },
                { k: "root", t: "Only the final  pacman -U  is root" }]
    case "aur":
        return aurPkg("quickshell python-pywal16")
    case "blob":
        return pack("blob").concat([{ k: "cmd", t: "cmake builds the plugin/ folder in a temporary directory, as you" },
                { k: "file", t: "/usr/lib/qt6/qml/Quicktest/Blobs — one folder, installed as root" },
                { k: "note", t: "It is loaded when the shell starts, so it needs a restart (ALT+Q) to show" }])
    case "hypr":
        if (m === "full")
            return [{ k: "file", t: "~/.config/hypr — every file of the bundled hypr/ folder, with this repo's path filled in" },
                    { k: "file", t: "~/.config/hypr.bak.<time> — a full copy of what is there now, made BEFORE anything is written" },
                    { k: "cmd", t: "hyprctl monitors → hardware.lua, if Hyprland is running (your real screens)" },
                    { k: "file", t: "An old hyprland.conf is renamed hyprland.conf.disabled — Lua and hyprlang can't both be active" },
                    { k: "note", t: "Undo: restore the backup from this page" }]
        return [{ k: "file", t: "~/.config/hypr/quicktest.lua — just the shell's keybinds and window rules" },
                { k: "file", t: "An existing quicktest.lua is copied to quicktest.lua.bak.<time> first" },
                { k: "note", t: "Your own hyprland.lua is NOT edited — you add  require(\"quicktest\")  yourself" }]
    case "autostart":
        return [{ k: "file", t: "One line in your Hyprland autostart that starts the shell (qs -p <this folder>)" },
                { k: "note", t: "It only edits a file it can read with confidence; otherwise it prints the line for you to place" },
                { k: "cmd", t: "scripts/install-autostart.sh --uninstall removes exactly that line again" }]
    case "themes":
        var names = { gtk: "GTK colour files", qt: "a Qt (qt6ct) colour scheme", discord: "the Midnight theme for your Discord client (downloaded at a pinned commit)",
                      spotify: "Spicetify with the QuickSpice theme", steam: "the Simply Dark skin (downloaded at a pinned commit)" }
        var todo = Object.keys(f.themes || {}).filter(function (k) { return f.themes[k].state === "todo" })
        var out = todo.map(function (k) { return { k: "file", t: names[k] || k } })
        out.push({ k: "note", t: "Third-party themes are downloaded, never bundled; the recolouring that maps the palette on is this shell's own" })
        return out
    case "colours":
        return [{ k: "cmd", t: "pywal extracts a palette from the wallpaper on screen" },
                { k: "file", t: "The palette file in your cache folder; the shell, Hyprland's borders, your terminal and the apps themed above repaint from it" }]
    case "spotify":
        return [{ k: "cmd", t: "Spicetify is installed into ~/.spicetify — no root" },
                { k: "file", t: "quickshell-bridge.js is copied into Spicetify's Extensions folder" },
                { k: "cmd", t: "spicetify config extensions … && spicetify apply — patches the Spotify client, which restarts it" }]
    case "wpe":     return aurPkg("linux-wallpaperengine")
    case "argos":   return aurPkg("python-argostranslate")
    case "songrec": return aurPkg("songrec")
    case "awww":    return aurPkg("awww")
    }
    return []
}

// ── A report you can paste ───────────────────────────────────────────────────
// For a bug report: the machine, the plan and how each step ended, with the last lines of whatever failed.
// `x` = { home, now (ms), polkit (bool: the run used polkit) }. The home directory is shown as "~", so a report
// pasted into an issue doesn't carry a username. No secret ever enters it: the password is never stored, and
// only each step's own output is quoted.
function formatReport(f, run, x) {
    x = x || {}
    var home = String(x.home || "")
    function scrub(t) { return home ? String(t).split(home).join("~") : String(t) }
    var L = []
    L.push("Quicktest setup report")
    if (x.now) L.push("Generated: " + new Date(x.now).toISOString())
    L.push("")
    L.push("Machine")
    L.push("  arch: " + (f.arch ? "yes" : "no") + "   network: " + (f.network === null ? "unknown" : f.network ? "ok" : "none")
           + "   disk free: " + (f.diskMiB ? Math.round(f.diskMiB / 102.4) / 10 + " GB" : "unknown"))
    L.push("  Quickshell " + (f.quickshell || "?") + "   Hyprland " + (f.hyprland || "?") + "   Qt " + (f.qt || "?"))
    L.push("  gpu: " + (f.gpu || "none recognised") + (f.vulkan && f.vulkan.length ? " (" + f.vulkan.join(", ") + ")" : "")
           + (f.nvidiaProprietary ? "   proprietary NVIDIA driver" : ""))
    L.push("  aur helper: " + (f.aurHelper || "none") + "   polkit agent: " + (f.polkitAgent ? "yes" : "no") + "   sudo: " + (f.sudo ? "yes" : "no"))
    L.push("  hyprland config: " + (f.hyprConfig || "absent") + "   morph plugin: " + (f.morph ? "loaded" : f.blobInstalled ? "installed, not loading" : "not installed"))
    var items = (run && run.items) || []
    L.push("")
    L.push("Plan (" + items.length + (items.length === 1 ? " step" : " steps") + (x.polkit ? ", root through polkit" : "") + ")")
    if (!items.length) L.push("  nothing ran")
    items.forEach(function (it) {
        var mark = it.state === "ok" ? "ok" : it.state === "failed" ? "FAILED" : it.state === "skipped" ? "skipped" : it.state
        var secs = it.endedAt && it.startedAt ? "  (" + Math.max(1, Math.round((it.endedAt - it.startedAt) / 1000)) + " s)" : ""
        L.push("  [" + mark + "] " + it.title + secs)
        if (it.state === "skipped" && it.why) L.push("      " + scrub(it.why))
        if (it.state === "failed") {
            if (it.explain) L.push("      " + it.explain.title + " — " + it.explain.text)
            var tail = (it.log || []).slice(-12)
            if (tail.length) {
                L.push("      last output:")
                tail.forEach(function (l) { L.push("        " + scrub(typeof l === "string" ? l : l.text)) })
            }
        }
    })
    return L.join("\n")
}

// ── Health: what has drifted since setup ─────────────────────────────────────
// The things that used to work or were set up and no longer do, plus the things that quietly don't work and say
// nothing. `f` = the plan's facts; `x` = { rivalNotifiers, rivalBars, rivalAgents (names), polkitConfig (bool),
// barBlur ("on"|"off"|"absent"), barOpacity }. → [{ id, level: "bad"|"warn"|"info", text, page }] — `page` is
// the wizard page that fixes it (-1: nothing to click, the text says what to do). Most urgent first.
function health(f, x) {
    x = x || {}
    var out = []
    function add(id, level, text, page) { out.push({ id: id, level: level, text: text, page: page }) }
    if (f.coreMissing > 0)
        add("core", "bad", f.coreMissing + (f.coreMissing === 1 ? " package the shell needs is" : " packages the shell needs are") + " missing", 1)
    if ((x.rivalNotifiers || []).length)
        add("notifier", "bad", x.rivalNotifiers.join(", ") + " is running — the shell can't show notifications while another daemon owns them. Quit it and drop it from your autostart.", -1)
    if (f.blobInstalled && !f.morph)
        add("morph", "warn", "The Morph plugin is installed but isn't loading — usually after a Qt update. Rebuild it.", 2)
    if (f.hyprConfig !== "absent" && !f.autostart)
        add("autostart", "warn", "Nothing starts the shell when you log in", 3)
    if (f.hyprConfig !== "absent" && !(f.bindCount > 0))
        add("binds", "warn", "No keybind opens the launcher or the overview", 3)
    if (!f.pywal)
        add("pywal", "warn", "pywal is missing — wallpapers and colour schemes won't repaint other apps", 1)
    else if (!f.palette)
        add("palette", "warn", "There is no colour palette yet, so the shell is wearing its monochrome fallback", 5)
    if (x.polkitConfig && (x.rivalAgents || []).length)
        add("agents", "warn", "Two password agents are running (" + x.rivalAgents.join(", ") + "); a session should have one", -1)
    if ((x.rivalBars || []).length)
        add("bars", "info", x.rivalBars.join(", ") + " is running alongside this bar", -1)
    if (x.barOpacity !== undefined && x.barOpacity < 0.999 && x.barBlur && x.barBlur !== "on")
        add("blur", "info", "The bar is translucent but no Hyprland rule blurs behind it", 3)
    compat(f).forEach(function (c) {
        if (c.state === "warn") add("ver-" + c.id, "info", c.label + " " + c.have + " isn't the version this was tested on (" + c.want + ") — very likely fine", -1)
    })
    var rank = { bad: 0, warn: 1, info: 2 }
    return out.sort(function (a, b) { return rank[a.level] - rank[b.level] })
}

// The steps to tick when nobody has chosen: the recommended ones that are still to do.
function defaultSelection(steps) {
    return steps.filter(function (s) { return s.state === "todo" && s.recommended }).map(function (s) { return s.id })
}

// ── A plan: what to run for a selection ──────────────────────────────────────
// `selected` are step ids (Custom may select a DONE step to redo it). Dependencies that are not done are
// pulled in (`auto: true`); blocked steps are left out and reported; the result is in catalogue order.
// → { run: [step…], blocked: [{ id, why }], root: bool, eta: seconds, count }
function buildPlan(steps, selected) {
    var by = {}
    steps.forEach(function (s) { by[s.id] = s })
    var want = {}, blocked = []
    function add(id, auto) {
        var s = by[id]
        if (!s || want[id]) return
        // A blocked step cannot run; neither can anything that needs it.
        if (s.state === "blocked") { blocked.push({ id: id, why: s.why }); return }
        want[id] = { auto: !!auto }
        s.deps.forEach(function (d) { if (by[d] && by[d].state !== "done") add(d, true) })
    }
    (selected || []).forEach(function (id) { add(id, false) })
    var run = steps.filter(function (s) { return want[s.id] }).map(function (s) {
        return Object.assign({}, s, { auto: want[s.id].auto, redo: s.state === "done" })
    })
    // A dependency that is blocked takes its dependents with it.
    var dropped = {}
    blocked.forEach(function (b) { dropped[b.id] = true })
    run = run.filter(function (s) {
        var lost = s.deps.find(function (d) { return dropped[d] })
        if (lost) { dropped[s.id] = true; blocked.push({ id: s.id, why: "Needs " + by[lost].title + ", which can't run: " + by[lost].why }); return false }
        return true
    })
    return { run: run, blocked: blocked, root: run.some(function (s) { return s.root }),
             eta: run.reduce(function (n, s) { return n + s.eta }, 0), count: run.length }
}

// "about 6 min", "under a minute", "about 1 h 5 min".
function etaText(seconds) {
    var s = Math.max(0, Math.round(Number(seconds) || 0))
    if (s < 45) return "under a minute"
    var m = Math.round(s / 60)
    if (m < 60) return "about " + m + " min"
    return "about " + Math.floor(m / 60) + " h" + (m % 60 ? " " + (m % 60) + " min" : "")
}

// ── What went wrong ──────────────────────────────────────────────────────────
// A non-zero exit says THAT a step failed. This reads its own output for the causes that are not the shell's
// to fix and says what to do. → { title, text, retry } — `retry` false when trying again cannot help until
// something is fixed (a lock, a missing network). null = nothing recognised: the caller says the log has it.
// First match wins, most specific first. (The updater has its own, updatelog.js `failureHint`; these are
// the setup-shaped ones, so the two overlap on purpose rather than import each other.)
function explainFailure(stepId, lines) {
    var t = (lines || []).map(function (l) { return typeof l === "string" ? l : (l && l.text) || "" }).join("\n")
    if (/unable to lock database/i.test(t))
        return { title: "pacman is busy", retry: false,
                 text: "Another package manager is running, or one crashed and left /var/lib/pacman/db.lck behind. "
                     + "Close it (or remove the file if nothing is running), then try again." }
    if (/failed retrieving file .*returned error: 404/i.test(t))
        return { title: "Your mirrors are out of sync", retry: false,
                 text: "A mirror answered 404 for files it should have. Put an up-to-date mirror first in /etc/pacman.d/mirrorlist "
                     + "(the reflector package ranks them), then try again." }
    if (/could not resolve host|failed retrieving file|connection timed out|temporary failure in name resolution|network is unreachable/i.test(t))
        return { title: "Couldn't download", retry: true,
                 text: "The connection dropped or a mirror didn't answer. Check the network and try again." }
    if (/invalid or corrupted package \(pgp signature\)|unknown trust|could not be looked up|keyring/i.test(t))
        return { title: "A package signature didn't verify", retry: true,
                 text: "Refreshing the keyring usually fixes it:  sudo pacman -S archlinux-keyring" }
    if (/no space left on device/i.test(t))
        return { title: "The disk is full", retry: false, text: "Free some space (pacman -Sc clears its cache), then try again." }
    if (/conflicting files|exists in filesystem/i.test(t))
        return { title: "A file is in the way", retry: false,
                 text: "A package wants a file another one (or you) already put there. The log names it." }
    if (/target not found|could not find all required packages|unable to satisfy dependency|breaks dependency/i.test(t))
        return { title: "A package isn't available", retry: false,
                 text: "pacman can't find it or satisfy its dependencies — often a stale sync database. Run  sudo pacman -Syu  and try again." }
    if (/sudo: .*(incorrect password|a password is required|no password was provided|try again)|authentication failure|sorry, try again/i.test(t))
        return { title: "The password wasn't accepted", retry: true,
                 text: "Nothing was installed. Retype it (each wrong try counts toward a ten-minute sudo lockout)." }
    if (/not authorized|authorization failed|dismissed|request dismissed/i.test(t) && /polkit|pkexec|authenticat/i.test(t))
        return { title: "The authentication dialog was dismissed", retry: true, text: "Try again and enter your password in the dialog." }
    if (/cmake error|qt6shadertools|could not find .*qt6|ninja: build stopped|make(\[\d+\])?: \*\*\*/i.test(t))
        return { title: "The plugin didn't build", retry: false,
                 text: "The compile failed — usually a missing build tool or a Qt version the plugin wasn't written for. The log has the compiler's own words." }
    if (/makepkg|==> error|failed to build|aur.archlinux.org/i.test(t) && /error|failed/i.test(t))
        return { title: "An AUR package didn't build", retry: false,
                 text: "The AUR build failed. The log above its last line says why; an out-of-date AUR package is the usual cause." }
    return null
}
