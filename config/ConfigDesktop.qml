import Quickshell
import Quickshell.Io
import QtQuick
import "layout.js" as Layout
import "modules.js" as Catalogue
// ConfigDesktop — part of Config, split out of Config.qml by area (2026-11-08). The parts form
// one inheritance chain (ConfigShell ← ConfigEdges ← ConfigBarLayout ← ConfigSystem ←
// ConfigDesktop ← Config), so every property still lives on the one `Config` singleton
// and nothing that reads `Config.x` changed. A name declared further down the chain is
// reached as `root.x` here (a base file can't see it statically; `root` is the same object).
ConfigSystem {
    id: root

    // ══ Theme mode ════════════════════════════════════════════════════════════
    // "dark" | "light" — whether pywal derives a dark or a light palette from
    // the wallpaper. This is the Windows-style mode switch: same picture, the
    // whole shell flips. Changing it re-runs palette extraction with pywal's -l
    // flag; the wallpaper itself is untouched.
    property string themeMode: "dark"

    // ── Which monitor image applies target ────────────────────────────────────
    // "" = every screen; otherwise a screen name (DP-2, HDMI-A-1…). Static
    // images only — awww sets outputs natively. The palette stays global: the
    // shell has one palette, and it follows whichever wallpaper applied last.
    // Only meaningful with the awww renderer (wallShellRender off): the shell
    // renderer draws Wallpaper.currentPath on every screen.
    property string wallTarget: ""

    // ── A wallpaper per workspace (services/Wallpaper) ────────────────────────
    // { "3": "/path/pic.png" } — workspaces with their own picture, and its colours
    // while you're on them (services/WorkspaceTheme). Every other workspace shows the
    // shared wallpaper. A plain pick in the gallery (Choose workspaces off) clears it.
    property var    wallWorkspaces: ({})
    // { "3": "Scheme name" } — workspaces with their own saved colour scheme (the Colours panel's
    // library, right-click a card): the shell on the screen showing it, and the apps on it, wear
    // that scheme's colours (services/WorkspaceTheme). A scheme beats the workspace's wallpaper
    // colours; the picture stays. Every other workspace wears the shared palette.
    property var    schemeWorkspaces: ({})
    // { "code": { name: "Code", icon: "code" } } — an APP's own name and icon, keyed by its
    // app id (Taskbar.keyFor): the workspace it's on wears it — on its overview cell, and its
    // icon in place of the number in the bar's WorkspacesPill — so the label goes wherever
    // the app goes (the user's call, 2026-10-20: tie them to apps, not workspace numbers).
    // Set from the overview's window inspector. Either may be "".
    property var    appLabels: ({})

    // ── Audio: per-output volume limit and memory (services/Audio) ────────────
    // Both keyed by the sink's PipeWire node NAME — stable across reboots, unlike its id.
    //   audioDeviceCaps   { "<node.name>": 0.6 }  the loudest this output may be set to.
    //                                              Absent = no limit. Headphones, mostly.
    //   audioDeviceLevels { "<node.name>": 0.45 } where its volume was last left, so
    //                                              switching to it puts it back.
    property var  audioDeviceCaps:     ({})
    property var  audioDeviceLevels:   ({})
    property bool audioRememberLevels: true

    // ── Who draws the static wallpaper ────────────────────────────────────────
    // true  — the shell renders it (modules/desktop/WallpaperView), which is what
    //         makes the parallax below possible. apply-wallpaper.sh is passed
    //         --no-daemon and never touches awww.
    // false — hand the picture to the awww daemon like before. The shell surface
    //         hides itself; parallax has nothing to move.
    // Scenes (Wallpaper Engine) always render themselves regardless.
    property bool wallShellRender: true

    // ── Material wallpaper (shell renderer only) ──────────────────────────────
    // Draw the wallpaper as flat Material shapes in the screen's own palette tones
    // (components/MaterialWallpaper, after End-4's default) instead of the picture. The
    // picture is still the current wallpaper — it keeps colouring the palette, and is back
    // the moment this goes off — it just isn't shown. A scene still plays over it.
    property bool wallMaterial: false
    // Its style (Wallpaper panel › Material). The colour is a ROLE NAME from `accentRoles`, never a
    // hex ("" = the palette's primary); the rest are the multipliers services/materialwall.js reads,
    // and the seed is which arrangement (0 = the composition as authored).
    property string wallMaterialRole:     ""
    property real   wallMaterialContrast: 1.0     // 0.5–1.5
    property real   wallMaterialSoftness: 1.0     // 0.4–1.8
    property real   wallMaterialSize:     1.0     // 0.7–1.4
    property int    wallMaterialSeed:     0
    // A second colour (a role name, "" = just the one) for the second stack and the edge shapes.
    property string wallMaterialRole2:    ""
    // Which Material shape each slot of the composition wears (a key of services/materialwall.js
    // FORMS); "" = the composition's own, so a default is never baked into the saved config.
    property string wallMaterialStack:    ""
    property string wallMaterialCentre:   ""
    property string wallMaterialSide:     ""
    property string wallMaterialCorner:   ""
    // Motion. Both are a frame loop on a full-screen surface, so they are OFF until asked for; the
    // speed multiplies the clock for both, the spin is 0–1 of a few degrees a second.
    // Looks: a faint wash of the colour over the ground behind the shapes (0–0.3), and the whole
    // picture flipped left to right (for a screen whose bar or widgets sit on the other side).
    property real   wallMaterialBackdrop:   0.0
    property bool   wallMaterialMirror:     false
    property bool   wallMaterialDrift:      false
    property real   wallMaterialDriftSpeed: 1.0   // 0.2–3
    property real   wallMaterialSpin:       0.0   // 0–1
    // Keep a still of it on awww, so it stays on screen while the shell is not running
    // (services/MaterialFallback). Needs awww; off or missing, nothing is left behind.
    property bool   wallMaterialFallback: true
    // Looks the user saved ([{ name, style }], a style as services/materialwall.js STYLE) and which of
    // them a colour scheme wears ({ "<scheme name>": "<look key>" }, a built-in look's id or "my:<name>").
    // Both are read through services/MaterialPresets, which cleans whatever the file holds.
    property var    wallMaterialSaved: []
    property var    wallMaterialLinks: ({})

    // ── Wallpaper parallax (shell renderer only) ──────────────────────────────
    // The wallpaper is zoomed past the screen edge and the surplus is panned:
    // horizontally by the focused workspace (1→10 across the image), and by a
    // small amount toward the pointer. zoom 1.0 = no surplus = no movement.
    property bool wallParallax:      true
    // Horizontal pan as the focused workspace changes (1→10 across the image).
    // Off keeps the zoom and the pointer drift but holds still on a workspace
    // switch.
    property bool wallParallaxWorkspace: true
    property real wallParallaxZoom:  1.10   // 1.0–1.5; >1 needed for any motion
    // Pointer influence, 0–1, as a fraction of the panning surplus. 0 disables
    // the cursor poll entirely (see services/Pointer). Kept small — this is a
    // drift, not a joystick.
    property real wallParallaxMouse: 0.12

    // ── Depth clock (shell renderer only) ─────────────────────────────────────
    // A big clock BETWEEN the picture and whatever stands in front of it in the picture — a
    // subject, a leg, a lamp post — so the time reads as part of the scene. The cutout and the
    // clock's place come from services/WallpaperDepth (models, set up once from Settings ›
    // Wallpaper); a picture with nothing in front of the clock's spot just doesn't get one.
    property bool wallDepth: false
    // How it looks. Size is a multiplier on the clock's own (a fraction of the screen's height);
    // `Depth` is how far the clock stays behind when the picture pans (0 = rides it, 1 = stays put
    // on the screen), which is what makes it slide behind the subject; both need the parallax on.
    property real   wallDepthScale:  1.0
    property real   wallDepthDepth:  0.5
    // How soft the clock's edge is where the subject covers it, in screen pixels (0 = as sharp as the mask).
    // A little blur hides the pixels of the edge; too much and the clock seems to glow through the subject.
    property real   wallDepthSoft:   1.2
    property bool   wallDepthDate:   true
    property bool   wallDepthHour12: false
    // "auto" = whichever end of the palette reads on THIS picture; "primary" / "text" = that role.
    property string wallDepthInk:    "auto"
    // Where you put it: { "<wallpaper path>": [centre x, top y] } in screen fractions. A picture
    // without an entry takes the automatic spot.
    property var    wallDepthPlaces: ({})
    // Analyse the whole library in the background (nice'd, one at a time), so a new wallpaper is
    // ready the moment it is picked.
    property bool   wallDepthPrepare: false

    // ── Favourite wallpapers ─────────────────────────────────────────────────
    // Image basenames and Workshop scene ids you've starred. The only thing that
    // reads them is the gallery, which floats them to the front of their tab —
    // purely an ordering hint, no other behaviour hangs off it.
    property var wallFavorites: []
    property var wpeFavorites:  []
    // Workshop ids removed with "unsubscribe" asked for — see WallpaperEngine.removeAndUnsubscribe.
    property var wpeUnsubPending: []

    function wallFavToggle(name) {
        const a = root.wallFavorites.slice()
        const i = a.indexOf(name)
        if (i < 0) a.push(name); else a.splice(i, 1)
        root.wallFavorites = a
    }
    function wpeFavToggle(id) {
        const a = root.wpeFavorites.slice()
        const i = a.indexOf(id)
        if (i < 0) a.push(id); else a.splice(i, 1)
        root.wpeFavorites = a
    }

    // ── Wallpaper shuffle ─────────────────────────────────────────────────────
    // Slideshow: apply a random image from the library every N minutes. Each
    // change is a full palette re-derivation (that's the point), so the floor is
    // high — a shell repainting itself every two minutes is a lava lamp.
    property bool wallShuffle: false
    property int  wallShuffleMins: 30
    // Shuffle among the starred wallpapers only (the whole library while none is starred).
    property bool wallShuffleFavs: false
    // The gallery's order: "name" is the library's own, "new" puts the newest file (scene: subscription) first.
    property string wallSort: "name"

    // ── Music effects on the wallpaper (modules/desktop/WallFx; 2026-10-31) ─────
    // The wallpaper moved by what's playing, one look per sound (services/wallfx.js SOUNDS:
    // kick → zoom & pulse, bass → rumble, snare → shockwave, hats → shimmer, vocals → bloom,
    // loudness → glow, hardest hits → glitch, breakdowns → blur, strobe opt-in). No presets
    // (the user: "the effects should adapt to the song itself") — the song weighs them; the
    // user sets the intensity, and `wallFxMix` trims a sound: id → 0..2, absent = auto (1),
    // 0 = off; Strobe's absent is off. (Replaced `wallFxEffects`, the per-effect strengths the
    // presets set — a stale key in an old config is just ignored.)
    // Pictures and scenes the shell draws (a scene playing from its window); not a scene the
    // layer renderer draws, which is another program's surface.
    property bool wallFx: false
    property real wallFxIntensity: 0.7
    property var  wallFxMix: ({})
    // Holds the effects back against the music, in ms (0–300), for speakers slower than the
    // screen (Bluetooth). Nothing lands earlier: an effect fires on a sound once it's heard
    // (services/MusicPulse → scripts/music-pulse.py --offset-ms).
    property int  wallFxSyncMs: 0

    // Show the wallpaper panel's per-step apply log while a wallpaper is being
    // applied. Off by default: the panel just stays on the gallery with a small
    // "Applying…" note. A FAILED apply still surfaces its log regardless — that
    // account must never be hidden (see UpdatesPage / the wallpaper panel).
    property bool wallApplyDebug: false

    // Same story for the colours panel's per-step apply log — off by default,
    // failures always surface, a quiet "Applying…" note otherwise.
    property bool colorApplyDebug: false

    // ── Starred colour schemes ───────────────────────────────────────────────
    // Names of the saved schemes you've starred. The colours panel's library floats them to the
    // front (and can show only them) — an ordering hint like the wallpaper favourites, nothing else
    // hangs off it. ColorScheme keeps it in step when a scheme is renamed or deleted.
    property var colorFavorites: []
    function colorFavToggle(name) {
        const a = root.colorFavorites.slice()
        const i = a.indexOf(name)
        if (i < 0) a.push(name); else a.splice(i, 1)
        root.colorFavorites = a
    }

    // The audio mixer's "past 100%" switch (output and per-app faders up to 150%).
    // Persisted so the panel reopens the way you left it; the output LEVEL itself is
    // restored above 100% only while this is on (Audio.qml); off, a level clamps to 100%.
    property bool mixerBoost: false

    // ══ System updates ════════════════════════════════════════════════════════
    // Packages to skip on the next upgrade. NOT pacman's IgnorePkg — that means a
    // root edit to /etc/pacman.conf (a bad line breaks pacman) and it persists
    // silently until someone remembers to undo it. This is a `--ignore` on the run
    // the shell builds, shown in the list and cleared with a click. Names only;
    // defaults to [] so a fork of this config inherits no holds.
    property var updateHold: []

    // ── How the update check runs ─────────────────────────────────────────────
    // Minutes between the automatic checks (0 = only when asked: the panel's refresh chip). Each is a
    // network call (`checkupdates` syncs a throwaway database), so it is a setting, not a constant.
    property int updateCheckMins: 10
    // Quiet hours: no AUTOMATIC check between these two times of day ("23:00" → "07:00" wraps midnight).
    // Asking by hand still works, and so does the check at shell start.
    property bool   updateQuiet: false
    property string updateQuietFrom: "23:00"
    property string updateQuietTo:   "07:00"
    // Take a snapshot (snapper or timeshift, whichever is installed) before "Update everything". If the
    // snapshot fails the upgrade does not start. Off unless asked; the panel only offers it where a
    // snapshot tool exists.
    property bool updateSnapshot: false

    // Shell updates (services/ShellUpdate): look for a newer signed release of
    // `repo` every 6 hours. A scheduled network call, so it can be switched off.
    // `shellUpdateNotified` is the last version announced, so a reload doesn't
    // announce it again.
    property bool   shellUpdateCheck:    true
    property string shellUpdateNotified: ""

    readonly property int wallShuffleMinsMin: 5
    readonly property int wallShuffleMinsMax: 180

    readonly property int wpeFpsMin: 24
    readonly property int wpeFpsMax: 240

    // ══ Where the wallpaper library lives ═════════════════════════════════════
    // Both of these were hardcoded to `$HOME/wallpapers/...` — in the Wallpaper
    // service, in apply-wallpaper.sh, and (reconstructed a third time) in
    // ColorScheme.regenerate(). That is the author's own layout, and this config is
    // published: on a fresh install the directory doesn't exist, `find` returns
    // nothing, and the gallery is simply empty with nothing saying why.
    //
    // "" means "use the default", which is still ~/wallpapers/walls — so an existing
    // setup is unchanged and only someone who needs a different layout has to care.
    // Resolution (including `~` expansion) is Wallpaper.libraryDir's job; nothing
    // else should rebuild these paths for itself.
    property string wallLibraryDir: ""

    // A COPY of the current wallpaper, kept at one stable path so things outside the
    // shell (fastfetch, a lock screen, a script) can point at "the wallpaper" without
    // knowing which file it currently is. Nothing inside this repo reads it — it is
    // purely an export for other tools.
    //
    // It is NOT derived from wallLibraryDir: the whole point is that it stays put
    // while the library moves, and a path that follows the library would break the
    // external consumer every time the library changed.
    //
    // "" is the default here too (~/wallpapers/pywallpaper.jpg) rather than an
    // expanded absolute path — a default that resolved $HOME would be PERSISTED with
    // this machine's home directory baked into it, which is the bug this section is
    // fixing. The script skips the copy when the target's directory doesn't exist, so
    // an install with no ~/wallpapers writes nothing rather than failing.
    property string wallExportPath: ""

    // ══ Screenshots ═══════════════════════════════════════════════════════════
    // Which notification app-names are screenshot tools. When one of these arrives the
    // shell takes it over: its plain "Screenshot saved" toast is replaced with one that
    // has the picture and something to do with it.
    //
    // A LIST, not a literal, for the same reason discord-rpc.json's windowClasses is
    // one: this config is published, and the tool people use here is not the tool they
    // use. hyprshot, grimblast, flameshot and swappy all announce themselves
    // differently, and matching one name would silently do nothing for everyone else.
    // Matched case-insensitively.
    property var screenshotApps: ["hyprshot", "grimblast", "grim", "flameshot", "swappy", "satty"]

    // Where the shell's own capture and its edited copies are written. "" = the default,
    // ~/Screenshots — resolved by Screenshot.saveDir, never rebuilt by a caller.
    property string screenshotDir: ""

    // The shell as the session's polkit authentication agent (services/AuthAgent): the
    // password dialog for pkexec and friends is drawn by the shell. Off by default —
    // a session has one agent, and enabling this only works once the other one
    // (hyprpolkitagent, polkit-gnome…) is out of the autostart. The Setup page says so.
    property bool polkitAgent: false

    // When a configuration reload gets a card at the top of the screen (modules/panels/
    // ReloadPopup): "failures" (default — a failed hot reload otherwise only reaches the
    // log), "all" (a blink on success too), or "off".
    property string reloadPopup: "failures"

    // The shell's own language (services/Translation): "auto" follows the system locale, or a
    // code that has a file in translations/ ("fr_FR"). Anything without a translation reads as
    // English. Not the system locale (Settings › Devices › Language sets that one).
    property string uiLanguage: "auto"

    // The snip tool (services/Snip): which action Enter does ("copy" · "save" · "edit" · "text" ·
    // "translate" · "record") — the last one you clicked.
    property string snipAction: "save"

    // How long the post-capture toast stays before fading. Long enough to react to,
    // short enough that a burst of shots doesn't build a wall. 0 keeps it until
    // dismissed.
    property int screenshotToastMs: 6000

    // ══ Night light ═══════════════════════════════════════════════════════════
    // Warms the display after dark. See services/NightLight.qml for which backend
    // actually does it and why the shell owns the schedule rather than the tool.
    property bool nightLight: false
    // The lens (services/Lens): which languages tesseract reads — "auto" (default: whatever is
    // installed, narrowed by the script it sees; scripts/lens.py), or a fixed "eng+jpn" (only
    // installed ones are used) — and what it translates into ("" = the lyrics' language).
    // "eng" was the default until 2026-10-10 and is read as "auto" on load: it could only ever
    // read English, and nothing said so.
    property string lensOcrLangs: "auto"
    property string lensTranslateLang: ""
    // Screen time (services/ScreenTime): seconds per app per day, from the focused
    // window. Off by default — nothing is recorded until you turn it on. Kept this many
    // days; you count as away (not counted) after this many idle minutes.
    // Snap zones (services/Snap): a floating window SUPER-dragged to a screen edge or
    // corner fills that half, quarter or the whole area. Tiled windows are left alone.
    property bool snapZones: true
    // …and, off the zones, a floating window you SUPER-drag lands on the desktop widgets'
    // grid (`widgetGrid`) — the same dots, from the same monitor corner.
    property bool snapToGrid: false
    property bool screenTime: false
    property int  screenTimeKeepDays: 30
    property int  screenTimeIdleMinutes: 5
    // Anti-flashbang (services/AntiFlash): dim the screen while what's on it is very
    // bright. Off by default — it puts a Hyprland screen shader in place while dimming.
    property bool antiFlash: false
    // Only during Night light's night window (its schedule).
    property bool antiFlashNightOnly: false
    // Mean brightness (0..1) above which it dims, and the lowest gain it goes to.
    property real antiFlashThreshold: 0.55
    property real antiFlashFloor: 0.45

    // Kelvin. 6500 is neutral (no adjustment at all); lower is warmer. 4000 is a
    // noticeable but still colour-accurate warmth — the value most people settle on
    // — rather than the aggressive 3000 that makes photographs unusable.
    property int nightLightTemp: 4000

    readonly property int nightLightTempMin: 2500
    readonly property int nightLightTempMax: 6500

    // Follow the clock instead of being a manual switch. Off by default: a shell that
    // changes your screen colour on a schedule you didn't ask for is startling the
    // first evening, and this is a preference, not a default.
    property bool nightLightAuto: false

    // Sunset→sunrise when the weather service knows where you are, so the schedule
    // tracks the actual season. Falls back to the fixed times below when it doesn't —
    // a location is optional in this shell and "auto" must still mean something
    // without one.
    property bool nightLightFollowSun: true

    // "HH:MM", used when following the sun is off or unavailable. Crossing midnight is
    // the normal case here, not an edge case.
    property string nightLightFrom: "20:00"
    property string nightLightTo:   "07:00"

    // ══ Cursor ════════════════════════════════════════════════════════════════
    // A generated XCursor theme in the shell's colours. See services/Cursor.qml. Off by
    // default: turning it on writes ~/.local/share/icons/quicktest and replaces the
    // user's system cursor, which is not something a published config should do on
    // first launch.
    property bool cursorTheme: false

    // Which colour fills the cursor: "accent" (Colors.primary), "text" (Colors.fg), or
    // "custom" (cursorCustom below). The outline is always the shell background.
    property string cursorColor: "accent"
    property string cursorCustom: "#ffffff"

    // Pixels, as XCURSOR_SIZE. The theme ships 24/32/48/64/96 and the compositor picks
    // the nearest, so any value in range is honest.
    property int cursorSize: 24
    readonly property int cursorSizeMin: 16
    readonly property int cursorSizeMax: 48

    // ── Cursor effects ─────────────────────────────────────────────────────────
    // The motion effects from the hypr-dynamic-cursors plugin: the pointer tilts,
    // rotates or stretches with its speed, and can grow when shaken so you can find
    // it. The plugin is a separate, optional install (see services/CursorEffects.qml);
    // with it missing the controls say so and nothing here does anything.
    property bool cursorEffects: false

    // "tilt" | "rotate" | "stretch" | "none" (shake-to-find only). Validated in
    // services/cursoreffects.js before it reaches Hyprland.
    property string cursorEffectMode: "tilt"

    // Percent of the plugin's own defaults; higher reaches the full effect at a lower
    // pointer speed.
    property int cursorEffectSensitivity: 100
    readonly property int cursorEffectSensitivityMin: 50
    readonly property int cursorEffectSensitivityMax: 200

    property bool cursorShake: true

    // ══ Cursor — presets ══════════════════════════════════════════════════════
    // Named snapshots of how the cursor LOOKS and MOVES, saved in presets/cursor.json
    // like the bar's are in presets/bar.json (same { name, config } array, same
    // built-in "Default" that can't be deleted, same rename/delete/active behaviour).
    //
    // ── What a preset holds, and what it deliberately doesn't ─────────────────────
    // Colour, size, effect mode, sensitivity and shake. NOT the two master switches
    // (`cursorTheme`, `cursorEffects`): loading a preset called "Calm" must not
    // silently replace your system cursor or load a compositor plugin. Those stay
    // where you set them. (A Shell preset, which is the whole config, does carry them.)
    readonly property string cursorDefaultPresetName: "Default"

    // Literals, equal to the property defaults above — the same arrangement as
    // `defaultPreset` for the bar, and for the same reason: "Default" is computed, not
    // stored, so it can never be edited out of existence.
    readonly property var cursorDefaultPreset: ({
        name: root.cursorDefaultPresetName,
        builtin: true,
        config: {
            cursorColor:             "accent",
            cursorCustom:            "#ffffff",
            cursorSize:              24,
            cursorEffectMode:        "tilt",
            cursorEffectSensitivity: 100,
            cursorShake:             true
        }
    })

    property var cursorPresets: []
    readonly property var cursorAllPresets: [root.cursorDefaultPreset].concat(root.cursorPresets)

    function _cursorSnapshot() {
        return {
            cursorColor:             root.cursorColor,
            cursorCustom:            root.cursorCustom,
            cursorSize:              root.cursorSize,
            cursorEffectMode:        root.cursorEffectMode,
            cursorEffectSensitivity: root.cursorEffectSensitivity,
            cursorShake:             root.cursorShake
        }
    }

    function saveCursorPreset(name) {
        const trimmed = (name ?? "").trim()
        if (trimmed === "" || trimmed === root.cursorDefaultPresetName) return
        const next = root.cursorPresets.filter(p => p.name !== trimmed)
        next.push({ name: trimmed, config: root._cursorSnapshot() })
        next.sort((a, b) => a.name.localeCompare(b.name))
        root.cursorPresets = next
    }

    // Every field falls back to the built-in's, never to the live value: loading a
    // preset twice from different starting points has to land in the same place. And
    // because presets/cursor.json is hand-editable, what comes out of it is checked
    // before it is assigned — a colour that isn't #RRGGBB would reach the generator, and
    // a size or sensitivity outside its range would be a slider stuck off its track.
    function loadCursorPreset(name) {
        const p = root.cursorAllPresets.find(x => x.name === name)
        if (!p) return
        const c = p.config
        const d = root.cursorDefaultPreset.config
        const num = (v, lo, hi, dflt) => {
            const n = Math.round(Number(v))
            return isFinite(n) ? Math.max(lo, Math.min(hi, n)) : dflt
        }

        root.cursorColor  = ["accent", "text", "custom"].indexOf(c.cursorColor) >= 0
                          ? c.cursorColor : d.cursorColor
        root.cursorCustom = /^#[0-9a-fA-F]{6}$/.test(c.cursorCustom ?? "") ? c.cursorCustom : d.cursorCustom
        root.cursorSize   = num(c.cursorSize, root.cursorSizeMin, root.cursorSizeMax, d.cursorSize)
        root.cursorEffectMode = ["tilt", "rotate", "stretch", "none"].indexOf(c.cursorEffectMode) >= 0
                          ? c.cursorEffectMode : d.cursorEffectMode
        root.cursorEffectSensitivity = num(c.cursorEffectSensitivity,
            root.cursorEffectSensitivityMin, root.cursorEffectSensitivityMax, d.cursorEffectSensitivity)
        root.cursorShake  = typeof c.cursorShake === "boolean" ? c.cursorShake : d.cursorShake
    }

    function deleteCursorPreset(name) {
        if (name === root.cursorDefaultPresetName) return
        root.cursorPresets = root.cursorPresets.filter(p => p.name !== name)
    }

    // Keeps the stored config and changes only the name — save-under-a-new-name-then-
    // delete would re-snapshot the CURRENT cursor into it (see renamePreset).
    function renameCursorPreset(from, to) {
        const trimmed = (to ?? "").trim()
        if (trimmed === "" || trimmed === from) return
        if (from === root.cursorDefaultPresetName || trimmed === root.cursorDefaultPresetName) return
        if (!root.cursorPresets.some(p => p.name === from)) return
        if (root.cursorPresets.some(p => p.name === trimmed)) return
        const next = root.cursorPresets.map(p => p.name === from
            ? { name: trimmed, config: p.config } : p)
        next.sort((a, b) => a.name.localeCompare(b.name))
        root.cursorPresets = next
    }

    function cursorPresetActive(name) {
        const p = root.cursorAllPresets.find(x => x.name === name)
        return p ? root._canonical(p.config) === root._canonical(root._cursorSnapshot()) : false
    }

    // ══ Settings ══════════════════════════════════════════════════════════════
    property bool railCollapsed: false

    // Which settings page to reopen on.
    //
    // Stored as the page's FILE, never its index. The rail's length changes with the
    // hardware — no Wi-Fi device means no Wi-Fi page, and a battery appearing inserts one
    // mid-list — so a saved index can silently come back pointing at a different page.
    // SettingsCard already had to guard against exactly that at runtime; persisting the
    // index would have made it survive restarts too.
    // Home rather than Bar as the first-run landing: Bar was a reasonable guess at
    // "the page you most likely want", but it is a guess, and someone opening settings
    // for the first time lands in the middle of the deepest page in the app. Home
    // carries the search field, so the default is now "ask me what you're looking for"
    // instead. Anyone who reopens settings still returns to wherever they last were —
    // this default only applies until that has happened once.
    property string settingsPage: "AppearancePage.qml"
    function toggleRail() { root.railCollapsed = !root.railCollapsed }

    // ── Pinned views ──────────────────────────────────────────────────────────
    // File names of the settings views pinned to the top of the rail, in the order
    // they were pinned. Files, not indices, for the same reason `settingsPage` is a
    // file: the catalogue renumbers whenever a dongle appears, and an index would
    // silently point at a different view. A pin for a view that no longer exists
    // (hardware went away) is filtered out on read rather than deleted — plug the
    // adapter back in and your pin is still there.
    property var settingsPinned: []

    function toggleSettingsPin(file) {
        if (file === "") return
        const out = []
        let found = false
        for (const f of root.settingsPinned) {
            if (f === file) { found = true; continue }
            out.push(f)
        }
        if (!found) out.push(file)
        root.settingsPinned = out          // reassigned, never mutated: QML notifies on change
    }

    function settingsPinnedHas(file) { return root.settingsPinned.indexOf(file) !== -1 }

    // ── Window vs docked panel ───────────────────────────────────────────────
    // `settingsPanel` false: settings is a floating xdg-toplevel window. true: a
    // full-height layer-shell panel welded to the screen frame at
    // `settingsPanelSide` ("left" / "center" / "right"). The panel is a layer
    // surface — it sits above windows but not the bar, which it does not overlap.
    property bool   settingsPanel:     false
    property string settingsPanelSide: "right"    // "left" | "center" | "right"

    // ── First-run setup ───────────────────────────────────────────────────────
    // false until the user has dismissed the setup page ("Got it, don't show again").
    // shell.qml opens Settings on SetupPage.qml once, on a machine where the shell
    // isn't wired into Hyprland yet (Setup.hyprReady) and this is still false.
    property bool setupSeen: false

    // Separate from setupSeen on purpose: setupSeen alone does NOT stop the wizard
    // reopening on a half-set-up machine (shell.qml's _maybeShowFirstRun keeps
    // nagging until Setup.coreReady too — deliberately, so an interrupted setup
    // isn't silently abandoned). This is the actual escape hatch: a checkbox on
    // the wizard's first page for someone who wants to run the shell without ever
    // finishing setup, and doesn't want to be asked again every reload.
    property bool setupAutoOpenDisabled: false


    // ══ Desktop widgets ═══════════════════════════════════════════════════════
    // The master switch. Placement and content live in DesktopWidgets' own store —
    // that grows with what you type into a note, and has no business being rewritten
    // into this document every time a slider moves.
    // ── Discord ───────────────────────────────────────────────────────────────
    // Off ⇒ the RPC helper never starts, so nothing connects to Discord's socket and
    // no call panel is built. On is only half the story: the panel also needs
    // ~/.local/state/quicktest/secrets/discord-rpc.json, and says so itself when it's missing.
    property bool discordEnabled: true

    // ── Claude Code presence ──────────────────────────────────────────────────
    // Off ⇒ the helper never starts, so nothing connects to Discord's socket and no
    // presence is published. On is only half the story: it also needs
    // `presenceClientId` in discord-rpc.json, and the page says so when it's missing.
    //
    // Default OFF, unlike discordEnabled. This one broadcasts what you are working on
    // to everyone on your friends list — including the folder name — so it is opt-in on
    // a fresh install rather than something a shell config decides for you.
    property bool claudePresenceEnabled: false

    // Which string is the card's first line: the session's short name ("RPC-
    // implementation") or its fuller AI-generated title ("Add Discord Rich Presence for
    // Claude Code terminal"). The name is what the CLI itself shows, so it's the
    // default; the title reads better to someone who isn't you.
    property bool claudePresenceUseAiTitle: false

    // Append "· workspace N" to the second line. Only meaningful under Hyprland, and
    // the helper omits it silently when it can't place the terminal.
    property bool claudePresenceShowWorkspace: true

    // The model in use and how full the context window is, appended to the same line.
    // The token figure is the CURRENT context, not a session total — see the helper for
    // why summing every turn's cache reads produces a huge and meaningless number.
    property bool claudePresenceShowModel:  true
    property bool claudePresenceShowTokens: true

    // Append "· +N more" when other interactive sessions are running alongside the
    // one shown. Without it the card looks like a single terminal even with three
    // open, which is a stranger piece of information to withhold than the workspace
    // or token count already on that line.
    property bool claudePresenceShowSessionCount: true

    // ── Counter-Strike 2 presence ────────────────────────────────────────────
    // Off ⇒ the helper never starts. On is only half the story: it also needs the
    // game's Game State Integration feed, which `scripts/install-cs2-gsi.sh` turns on
    // — the page says so when the feed hasn't been seen. Default OFF, like
    // claudePresenceEnabled and for the same reason: it broadcasts what you're playing
    // to your whole friends list, so it's opt-in rather than a shell-config default.
    //
    // The card titles itself from Valve's own registered "Counter-Strike 2" Discord
    // app, so unlike the Claude Code card there is no application for you to create.
    property bool cs2PresenceEnabled: false

    // "CT 7 : 5 T" on the second line.
    property bool cs2PresenceShowScore: true

    // "12/8 K/D" on the same line — your kills and deaths this match. Only ever your
    // own: the helper ignores the stat block while you're spectating someone dead.
    property bool cs2PresenceShowKd: true

    // The game mode in front of the map name ("Competitive · Dust II" vs "Dust II").
    property bool cs2PresenceShowMode: true

    property bool widgetsEnabled: true

    // How solid the tiles are. Same reasoning as barOpacity, and the same mechanism —
    // it feeds Surface.fillOpacity, so the fill fades while the border stays crisp.
    property real widgetOpacity: 0.72

    // Tile corner radius. Defaults to the token (22, an iOS home-screen widget's
    // corner-to-edge ratio at this size); exposed because "how round" is exactly the
    // kind of taste the bar page already lets you set.
    property int widgetRoundness: Tokens.radiusWidget

    // Liquid glass, or a plain translucent tile. On, the fill is graded and the tile
    // carries a continuous rim and a soft sheen; off, it is one flat fill and a border,
    // which is what these were before. A preference rather than a decision because the
    // two suit different wallpapers — glass wants something with tonal variation behind
    // it, and reads as noise over a flat or very busy one.
    property bool widgetGlass: true

    // ── Hover parallax ────────────────────────────────────────────────────────
    // A tile leans under the pointer and its content shifts the other way (WidgetFrame).
    // The whole effect is one switch plus one strength, because the two halves only make
    // sense together — a tile that tilts with fixed content, or content that drifts on a
    // flat tile, reads as a bug. 1.0 is the designed amount (5° of tilt, a few pixels of
    // shift); the strength scales both, 0.25 for a hint and 2 for a lot. A preference,
    // not a decision: it is the most "motion" on the desktop, and some people want none.
    // Separate from `barHoverGrow` (the swell) and from `motionEnabled`, which still
    // wins — animations off means no parallax whatever this says.
    property bool widgetParallax: true
    property real widgetParallaxStrength: 1.0

    // The staggered spring pop when the desktop's tiles first appear (launch, reload, a
    // tile added). Off, they are simply there.
    property bool widgetEntrance: true

    // Snap step for dragging, in pixels. Not the tile size: tiles are 168px, and
    // snapping at that granularity would give you nine possible positions on a screen.
    // 40 is fine enough to place things deliberately and coarse enough that two
    // widgets dropped near each other actually line up.
    property int widgetGrid: 40

    // Same idiom as `resetModule` — restores the shell-wide widget material to what
    // an untouched config starts at. Does NOT touch placement, content, or any
    // per-widget override in `opts` — those are what "Match shell" (WidgetsPage,
    // per selected widget) and removing a tile are for, respectively.
    function resetWidgetsAppearance() {
        root.widgetOpacity   = 0.72
        root.widgetRoundness = Tokens.radiusWidget
        root.widgetGlass     = true
        root.widgetGrid      = 40
        root.widgetParallax         = true
        root.widgetParallaxStrength = 1.0
        root.widgetEntrance         = true
    }

    // ── Weather ───────────────────────────────────────────────────────────────
    // Coordinates are the source of truth; `weatherPlace` is only the label to show,
    // and an empty one is what the widget reads as "not set up yet". Storing the
    // coordinate rather than the city name means no re-geocoding on every fetch — and
    // the forecast endpoint takes numbers regardless.
    property string weatherPlace: ""
    property real   weatherLat:   0
    property real   weatherLon:   0
    // Display only. The service always stores metric, so this can flip with no refetch.
    property bool   weatherMetric: true

    // ISO 3166 alpha-2 of the weather location ("PT"), saved with the place when it's
    // picked — and filled in once by Weather.backfillCountry() for a place picked
    // before this existed. The calendar's special dates follow it, NOT the system
    // locale: a locale names a language's country, so en_US in Portugal would show
    // US holidays.
    property string weatherCountry: ""

    // ── Calendar ──────────────────────────────────────────────────────────────
    // The palette ROLE your own events wear, never a hex.
    property string calendarLocalColor: "focus"
    // Subscribed calendars: [{ id, name, url, color }] — `color` a palette ROLE name (Calendar.feedRoles),
    // `url` an https address (ics.js feedUrl checked it on the way in). Edited only through
    // Calendar.addFeed / removeFeed / setFeedColor; the settings page lists them. The URL can be a secret
    // address, so it is stored here (state dir, never the repo) and never logged.
    property var calendarFeeds: []

    // ── World clocks ──────────────────────────────────────────────────────────
    // IANA zone names, in the order shown ("Asia/Tokyo"). WorldClock checks every one before it is stored.
    property var worldClocks: []
}
