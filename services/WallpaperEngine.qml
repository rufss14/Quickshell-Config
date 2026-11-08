pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "../config"
import "workspacetheme.js" as WsJs

// ── WallpaperEngine ───────────────────────────────────────────────────────────
// The Steam Workshop wallpaper library (linux-wallpaperengine), and running one.
//
// ── There is no IPC. Changing wallpaper means RESTARTING the process ──────────
// Checked against `--help` rather than assumed: every option this renderer has —
// the background, volume, fps, layer, the lot — is a startup argument. There is no
// socket, no control file, no signal. So "apply" here is genuinely kill-and-relaunch,
// and the UI has to be honest that a change costs a visible restart of the wallpaper.
//
// ── The SIGPIPE trap: why the child's output is redirected to a file ──────────
// The first version launched with a bare `setsid --fork <renderer>` and every
// apply produced a renderer that died ~1.6 seconds later. Measured, not guessed:
// a 150ms trace showed running at t+450ms and dead by t+2100ms. The detached
// child INHERITS the Process's stdout/stderr pipes; once setsid exits, Quickshell
// closes the read ends; the renderer logs chattily during startup, and its first
// write into the closed pipe is a SIGPIPE — silent death, nothing in any log.
// The launch now routes the child's output into a real file, which both breaks
// the pipe dependency and finally makes failures diagnosable (see lastError).
//
// ── Killing it safely is the other dangerous part of this file ────────────────
// There are TWO similarly named programs on this machine:
//
//     linux-wallpaperengine    the layer-shell renderer  (what we drive)
//     linux-wallpaper-engine   a separate Electron GUI   (leave alone)
//
// Linux truncates a process's `comm` to 15 characters, and BOTH become exactly
// "linux-wallpaper" — `pkill -x` on that name matches EIGHT processes here,
// including the Electron app. So we match the full command line on the
// UNHYPHENATED spelling, anchored so a process that merely MENTIONS the name
// (like the bash stage of our own launcher, where the name follows a space)
// can never match. Every command is an argv array — no shell string ever
// contains an unquoted path.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // …and ONLY the layer renderer: every launch of ours starts `--layer background`
    // (_launchCommand), which a scene in a window of its own (services/ScenePreload,
    // `--window`) never does. Without that, stopping or relaunching the layer renderer
    // killed every preloaded window too, and its argv parser read them as a scene
    // playing on every screen.
    readonly property string _procPattern: "(^|/)linux-wallpaperengine --layer( |$)"

    readonly property string workshopDir:
        Quickshell.env("HOME") + "/.local/share/Steam/steamapps/workshop/content/431960"
    readonly property string assetsDir:
        Quickshell.env("HOME") + "/.local/share/Steam/steamapps/common/wallpaper_engine/assets"
    // Where the renderer's own output goes. Truncated on every launch, so it only
    // ever describes the CURRENT (or most recent) run.
    readonly property string logFile:
        Quickshell.env("HOME") + "/.cache/quicktest-wpe.log"
    // Wallpaper Engine's own wordmark, out of Steam's cache — nothing vendored, so
    // no trademark ships with this config. Absent on a machine that doesn't own the
    // app, and every consumer must survive that (PanelHeader falls back to a glyph).
    readonly property string logoFile:
        Quickshell.env("HOME")
        + "/.local/share/Steam/appcache/librarycache/431960/logo.png"

    // ── The library ───────────────────────────────────────────────────────────
    // [{ id, title, type, preview, base, props, texdir }] — `type` normalised to lowercase,
    // `preview` an absolute path, `base`/`props`/`texdir` only for a preset (see the scanner). Sorted by title, which is what the filmstrip is ordered by.
    readonly property var  items:    root._items
    readonly property bool scanning: scanProc.running
    // Workshop items that are NOT standalone wallpapers — see the scanner below.
    readonly property int  skipped:  root._skipped

    property var _items: []
    // The installed scenes ({ id, title, preview, … }), read-only for others (the overview's AI picks by title).
    readonly property var scenes: root._items
    property int _skipped: 0

    function rescan() {
        if (scanProc.running) return
        scanProc.running = true
        binProbe.running = true
    }

    // ── Is the renderer actually installed? ───────────────────────────────────
    // This config is published, and linux-wallpaperengine is an AUR build plenty
    // of installs won't have. Without this, applying a scene on a machine that has
    // the Workshop content but not the renderer runs the entire stop → start →
    // verify journey — some seven seconds — before a log tail finally reports
    // "command not found". Same contract as Discord.pressBlocker(): a missing
    // optional tool DISABLES the control with a reason instead of failing on click.
    //
    // Assumed present until the probe says otherwise, so nothing flashes a
    // "not installed" warning during the first frames after a reload.
    readonly property bool installed: root._installed
    property bool _installed: true
    property bool _probed: false

    function blocker() {
        if (!root._probed || root._installed) return ""
        return "linux-wallpaperengine isn't installed — scenes can't be rendered"
    }

    Process {
        id: binProbe
        running: true
        command: ["bash", "-c", "command -v linux-wallpaperengine"]
        onExited: function(code) {
            root._installed = (code === 0)
            root._probed = true
        }
    }

    // ── Scanning ──────────────────────────────────────────────────────────────
    // scripts/wpe-scan.py reads every project.json in one pass (tested by
    // scripts/test-wpe-scan.py). Two things it has to get right, both found by
    // reading the REAL library: `type` is inconsistently cased ("scene"/"Scene"),
    // and some items are PRESETS (Steam's "Category: Preset") — a `dependency` on
    // another workshop item plus a blob of its property values, with no file of
    // their own. linux-wallpaperengine knows nothing of presets, so a preset item
    // carries `base` (the scene that actually renders) and `props` (its values, in
    // --set-property's wire format) and _launchCommand plays it as base + props.
    // A preset's own PICTURES can't ride on --set-property (the renderer stores such a
    // value and never reads it); the scanner writes each as a .tex in a project folder
    // under texturesDir
    // and plays from a folder built around them — see the scanner's docstring.
    // What is still skipped — unreadable, or a preset whose base isn't installed —
    // is counted, not silently dropped: an item visible in Steam vanishing here
    // would read as a bug.
    Process {
        id: scanProc
        running: true
        command: ["python3", Quickshell.shellPath("scripts/wpe-scan.py"), root.workshopDir, root.texturesDir]

        property var _rows: []
        property int _skip: 0

        stdout: SplitParser {
            onRead: function(line) {
                const parts = line.split("\t")
                if (parts[0] === "SKIPPED") {
                    scanProc._skip = parseInt(parts[1]) || 0
                } else if (parts[0] === "ITEM" && parts.length >= 8) {
                    let props = ({})
                    try { props = JSON.parse(parts[5]) || ({}) } catch (e) {}
                    scanProc._rows = scanProc._rows.concat([{
                        id:      parts[1],
                        type:    parts[2],
                        preview: parts[3],
                        // "" for a normal scene; for a preset, the scene it plays on.
                        base:    parts[4],
                        props:   props,
                        // A preset with pictures: the project folder built for it
                        // ("" = none) — what --bg is given instead of the base.
                        texdir:  parts[6],
                        // Title last: it's the only field that can contain anything,
                        // so a tab inside it can't shift the others.
                        title:   parts.slice(7).join(" ")
                    }])
                }
            }
        }

        onExited: function(code) {
            root._items   = scanProc._rows.slice()
            root._skipped = scanProc._skip
            scanProc._rows = []
            scanProc._skip = 0
            // The startup probe races this scan; a preset running as its base is
            // only recognisable once the items are known (see _parseRunning).
            if (root._running) root.probe()
        }
    }

    function itemFor(id) { return root._items.find(i => i.id === id) ?? null }

    // ── A still frame of whatever is on screen right now ──────────────────────
    // "" when no scene is up, or when the running scene has no preview on disk.
    //
    // This exists because a scene has no still image ANYWHERE else: Wallpaper.currentPath
    // is deliberately empty while the renderer is driving (see its own note), so anything
    // that needs to draw the wallpaper — the lockscreen, which cannot see the background
    // layer through a session-lock surface — has nothing to point at and falls back to a
    // flat colour. The Workshop preview is the honest answer: it is the still the author
    // published OF this scene, and it is already what the palette is derived from, so the
    // lock and the shell's colours come from the same picture.
    readonly property string currentPreview: {
        if (!root._running || root._current === "") return ""
        const it = root.itemFor(root._current)
        return it ? it.preview : ""
    }

    function titleFor(id) {
        const it = root.itemFor(id)
        return it ? it.title : (id === "" ? "" : id)
    }

    // ── Is it running, and on what? ───────────────────────────────────────────
    // Read back from the RUNNING process's own command line, not from what we last
    // asked for — the user can (and does) start this renderer by hand, and a page
    // reporting our own last request as truth would confidently show the wrong
    // wallpaper. Config.wpeCurrent is only the restore-on-login value.
    //
    // "A scene is on screen" includes the shared scene when it plays from a window of its
    // own (`windowDrawn`, below) — this is the one answer the panels, Game Mode and the
    // palette code read, and none of them care which kind of renderer is behind it.
    // `layerUp` is the layer renderer alone, for the one reader that does: WallpaperView.
    readonly property bool running:   root._running || root.windowDrawn
    readonly property bool layerUp:   root._running
    readonly property string current: root._current !== "" ? root._current
                                    : root.windowDrawn ? root.windowShared : ""
    // Per-screen scene ids read back from the running process's own argv — the
    // screens covered by a Config.wpeMonitors override. Screens using the
    // DEFAULT scene are NOT in here; `current` already names that one.
    readonly property var runningMonitors: root._runningMonitors
    property var _runningMonitors: ({})

    // True once the first pgrep has come back — i.e. `running` is now a real
    // answer and not just its "false" default. The shell-rendered wallpaper waits
    // for this before painting on reload, so a scene that survived the reload
    // isn't briefly covered by the last still image. (Distinct from `_probed`
    // above, which is the INSTALL check.)
    readonly property bool probed: root._runProbed
    property bool _runProbed: false

    property bool   _running: false
    property string _current: ""

    // Refcounted like the other on-demand services: an external process has nothing
    // to subscribe to, so this is a genuine poll and must not run while nobody is
    // looking. Acquired by the settings page while visible.
    property int _refs: 0
    function acquire() { root._refs++; if (root._refs === 1) { poll.start(); root.probe() } }
    function release() { root._refs = Math.max(0, root._refs - 1); if (root._refs === 0) poll.stop() }

    Timer {
        id: poll
        interval: 2000
        repeat: true
        onTriggered: root.probe()
    }

    // `onDone` is a one-shot callback for a caller that needs a FRESH answer
    // right now, not whatever `running`/`current` last happened to be — e.g.
    // Gamemode.enable(), which only refreshes on its own while a panel has
    // acquire()d the poll or mid apply/stop, so a scene started (or changed)
    // since the last probe wouldn't be reflected yet. Chained onto an in-flight
    // probe rather than starting a second pgrep, so every caller waiting on
    // "the next answer" gets it from the same probe.
    function probe(onDone) {
        if (probeProc.running) {
            if (onDone) probeProc._pending.push(onDone)
            return
        }
        probeProc._line = ""
        probeProc._pids = []
        if (onDone) probeProc._pending.push(onDone)
        probeProc.running = true
    }

    Process {
        id: probeProc
        command: ["pgrep", "-a", "-f", root._procPattern]

        property string _line: ""
        property var _pids: []            // every match, not just the first line
        property var _pending: []

        stdout: SplitParser {
            onRead: function(line) {
                if (probeProc._line === "") probeProc._line = line
                const pid = parseInt(line)
                if (pid > 0) probeProc._pids.push(pid)
            }
        }

        onExited: function(code) {
            const wasRunning = root._running
            // pgrep exits 1 when nothing matched — "not running", not an error.
            // A scene still LOADING over nothing (no old one playing) isn't running as
            // far as the wallpaper is concerned: WallpaperView hides itself the moment
            // this turns true, and until the scene maps that would leave no wallpaper.
            root._running = (code === 0 && probeProc._line !== "") && !root._loadingBare
            if (root._running) {
                const parsed = root._parseRunning(probeProc._line)
                root._current           = parsed.defaultId
                root._runningMonitors   = parsed.perScreen
                root._runningMap        = parsed.screens
            } else {
                root._current         = ""
                root._runningMonitors = ({})
                root._runningMap      = ({})
            }
            root._runProbed = true
            root._dropDuplicates(probeProc._pids)
            root._verifyStep()
            const callbacks = probeProc._pending
            probeProc._pending = []
            for (const cb of callbacks) cb()
            // ── Catching a DELAYED crash, not just a failed start ──────────────
            // The verify loop above only proves the renderer came up within its
            // first few probes — it does not keep watching. Some scenes fork
            // fine, run for a second or two, and THEN segfault (measured: workshop
            // scene 3661092645 survives its first probe easily, decodes a frame,
            // and dies moments later) — invisible to "never came up." `_phase ===
            // "idle"` is what distinguishes this from a deliberate stop()/apply():
            // both of those hold `_phase` at "stopping"/"starting" for their own
            // probes, so a running→gone transition witnessed while idle can only
            // be something dying on its own. `_expectRunning` is the second half
            // of that: it's true only once WE verified a launch as up, so a
            // wallpaper started outside the shell entirely is left alone.
            if (wasRunning && !root._running && root._phase === "idle" && root._expectRunning)
                root._handleUnexpectedCrash()
        }
    }

    // ── Two layer renderers at once ───────────────────────────────────────────
    // There is only ever one: a single process serves every screen, and a change runs the
    // new one beside the old one for the length of a fade and then retires the old one by the
    // pids it recorded (_retireOld). Those pids live in this singleton, so a reload that
    // lands inside that fade forgets them — the old renderer then plays on forever beneath
    // the new one (seen: two, 5 s apart, one of them with a stale --disable-parallax, both
    // playing the soundtrack). So: more than one, seen idle on two probes running (the first
    // might be a change that has just begun), and the newer one wins, as it does in a fade.
    // Window-mode renderers don't match _procPattern, so none of ScenePreload's is touched.
    property int _dupSeen: 0
    function _dropDuplicates(pids) {
        if (pids.length < 2 || root._phase !== "idle" || root._overlap) { root._dupSeen = 0; return }
        if (++root._dupSeen < 2) { dupRecheck.restart(); return }
        root._dupSeen = 0
        const keep = Math.max.apply(null, pids)
        const stale = pids.filter(p => p !== keep)
        console.warn("WallpaperEngine: " + pids.length + " renderers were playing; ending the older "
                     + stale.join(", ") + " and keeping " + keep)
        Quickshell.execDetached(["kill"].concat(stale.map(String)))
    }

    Timer { id: dupRecheck; interval: 3000; onTriggered: root.probe() }

    // One probe at startup so `running`/`probed` reflect reality within a frame or
    // two of the shell loading, not only once the settings page is opened or the
    // 4s autostart timer fires. `_procPattern` is a constant, so this needs
    // nothing from Config.
    Component.onCompleted: root.probe()

    // ── Reading back WHICH scene plays WHERE ──────────────────────────────────
    // The renderer can run a different --bg per --screen-root/--screen-span in one
    // process (checked against --help's own multi-screen example), so a single
    // "last --bg wins" regex stopped being enough once a launch can carry several.
    // Walk the argv pairing each --bg with the screen(s) named by the LAST
    // --screen-root/--screen-span before it; a --bg with nothing preceding it (the
    // bare positional form, used when there are no named screens at all) is the
    // DEFAULT scene.
    function _parseRunning(line) {
        const toks = line.split(/\s+/)
        let pendingScreens = null
        const rawPerScreen = {}
        let bareDefault = ""
        for (let i = 0; i < toks.length; i++) {
            if (toks[i] === "--screen-root" && toks[i + 1]) {
                pendingScreens = [toks[i + 1]]
                i++
            } else if (toks[i] === "--screen-span" && toks[i + 1]) {
                pendingScreens = toks[i + 1].split(",")
                i++
            } else if (toks[i] === "--bg" && toks[i + 1]) {
                const parts = toks[i + 1].replace(/\/+$/, "").split("/")
                const id = parts[parts.length - 1] ?? ""
                if (pendingScreens) {
                    for (const s of pendingScreens) rawPerScreen[s] = id
                    pendingScreens = null
                } else {
                    bareDefault = id
                }
                i++
            }
        }

        // ── The bare positional form is NOT how a multi-monitor default plays ──
        // _launchCommand's "remaining screens" loop (below) gives the default
        // scene its own NAMED --screen-root/--bg per screen too, same as a real
        // per-monitor override — the bare form only survives on a screen-less
        // launch. So a screen named here isn't necessarily an override; it's an
        // override only if Config actually assigned it one. Anything else named
        // here is the default wearing a screen name, and folds back into it
        // (they all carry the same id, since _launchCommand hands every
        // "remaining" screen the identical default id).
        const overridden = ({})
        for (const m of (Config.wpeMonitors || []))
            for (const s of (m.screens || [])) overridden[s] = true

        // A preset runs as its base, so argv names the base. If what we're
        // configured to play here is a preset on that base, it's that preset —
        // otherwise Refresh would re-apply the plain base and drop the preset.
        const asked = (ran, wanted) =>
            (wanted !== "" && root.itemFor(wanted)?.base === ran) ? wanted : ran

        const perScreen = {}
        let defaultId = bareDefault
        for (const s in rawPerScreen) {
            if (overridden[s]) perScreen[s] = asked(rawPerScreen[s], root.monitorFor(s))
            else if (defaultId === "") defaultId = rawPerScreen[s]
        }
        return { defaultId: asked(defaultId, Config.wpeCurrent), perScreen: perScreen, screens: rawPerScreen }
    }

    // What WILL play on a screen once (re)applied — the CONFIGURED assignment,
    // not necessarily what's live right now (see runningMonitors for that).
    function titleForScreen(screenName) {
        const id = root.monitorFor(screenName)
        return id !== "" ? root.titleFor(id) : root.titleFor(Config.wpeCurrent)
    }

    // One line describing what's configured for a screen — the Monitors
    // section's per-row label in both the settings page and the bar panel.
    // Kept here rather than duplicated in each: it reads Config.wpeMonitors
    // directly (monitorFor() alone can't tell a span from a solo assignment).
    function assignmentLabel(screenName) {
        const spanEntry = (Config.wpeMonitors || []).find(m =>
            m.screens.indexOf(screenName) !== -1 && m.screens.length > 1)
        if (spanEntry) {
            const others = spanEntry.screens.filter(s => s !== screenName)
            return "Spanned with " + others.join(", ") + " · " + root.titleFor(spanEntry.id)
        }
        const id = root.monitorFor(screenName)
        if (id !== "") return root.titleFor(id)
        return Config.wpeCurrent !== ""
            ? "Default · " + root.titleFor(Config.wpeCurrent)
            : "Default (nothing set)"
    }

    // ── Custom scene properties ────────────────────────────────────────────────
    // Many Workshop scenes expose author-defined sliders/colours/checkboxes/combos
    // (what `--list-properties`/`--set-property` are for). Read straight from
    // `project.json`'s `general.properties` rather than shelling out to
    // `--list-properties` and parsing its text — verified against the real,
    // installed source (Property.h) that it's the same data plus more (order,
    // combo options) and needs no renderer launch to read.
    //
    // Wire format verified by reading Property::update(string) in the installed
    // renderer's own source, so overrides can't silently no-op:
    //   slider  → std::stof(value)              e.g. "0.75"
    //   bool    → value == "true" || value == "1"
    //   color   → "r g b" FLOATS, always with a "." (see _wire). NOT "#RRGGBB": the
    //             renderer's ColorBuilder reads a 6-digit hex as if it were RGBA
    //             (`>> 24 & 0xFF` first), so #dcddff arrives as (0, dc, dd) — cyan.
    //             8 digits is no way out (std::stoi throws above 0x7FFFFFFF), and an
    //             all-integer "1 1 1" is read as 0–255. The STORE stays "#rrggbb"
    //             (it's what the editor shows); it's converted on the way to argv.
    //   combo   → must exactly equal one option's `value`
    readonly property string _propertiesDir: Quickshell.shellPath("theming/wallpaper-properties")

    readonly property var    propertySchema:    root._propSchema
    readonly property string propertySchemaFor: root._propSchemaId
    readonly property bool   propertiesLoading: schemaProc.running
    property var    _propSchema:   []
    property string _propSchemaId: ""

    // Public: make sure a scene's override map is cached, for the properties
    // editor to read via overrideFor(). _loadOverrides (below) is otherwise
    // only reached from the launch path, for a scene about to run.
    function loadOverridesFor(id, cb) {
        root._loadOverrides([id], cb || function() {})
    }

    function loadPropertySchema(id) {
        if (!id || schemaProc.running) return
        root._propSchemaId = id
        schemaProc.command = ["python3", "-c", `
import json, sys
SUPPORTED = {"slider", "color", "bool", "combo"}
try:
    d = json.load(open(sys.argv[1] + "/project.json", encoding="utf-8", errors="replace"))
except Exception:
    print("[]")
    sys.exit(0)
props = d.get("general", {}).get("properties", {})
out = []
for key, p in props.items():
    if not isinstance(p, dict) or p.get("type") not in SUPPORTED:
        continue
    t = p.get("type")
    row = {"key": key, "type": t, "text": p.get("text") or key, "order": p.get("order", 0)}
    if t == "slider":
        row["min"] = p.get("min", 0)
        row["max"] = p.get("max", 1)
        row["step"] = p.get("step", 0.1)
        row["value"] = p.get("value", 0)
    elif t == "bool":
        row["value"] = bool(p.get("value"))
    elif t == "color":
        parts = str(p.get("value", "0 0 0")).replace(",", " ").split()
        try:
            r, g, b = (float(x) for x in parts[:3])
        except Exception:
            r, g, b = 0.0, 0.0, 0.0
        clamp = lambda x: max(0, min(255, round(x * 255)))
        row["value"] = "#%02x%02x%02x" % (clamp(r), clamp(g), clamp(b))
    elif t == "combo":
        row["options"] = [{"label": o.get("label") or o.get("value", ""), "value": o.get("value", "")}
                           for o in (p.get("options") or []) if isinstance(o, dict)]
        row["value"] = p.get("value", "")
    out.append(row)
out.sort(key=lambda r: r.get("order", 0))
print(json.dumps(out))
`, root.workshopDir + "/" + (root.itemFor(id)?.base || id)]
        schemaProc.running = true
    }

    // A preset is its base scene with other values: the editor lists the base's
    // properties, and a preset's own values stand in for the base's defaults.
    // `props` is wire format (see the scanner), so it's turned back per type.
    function _withPreset(rows, id) {
        const props = root.itemFor(id)?.props
        if (!props) return rows
        for (const r of rows) {
            const v = props[r.key]
            if (v === undefined) continue
            r.value = r.type === "bool"   ? (v === "1" || v === "true")
                    : r.type === "slider" ? Number(v)
                    : v
        }
        return rows
    }

    Process {
        id: schemaProc
        stdout: StdioCollector {
            onStreamFinished: {
                try { root._propSchema = root._withPreset(JSON.parse(text) || [], root._propSchemaId) }
                catch (e) { root._propSchema = [] }
            }
        }
    }

    // ── The override cache ────────────────────────────────────────────────────
    // Every JSON read in this codebase is async, but _launchCommand runs
    // synchronously — so overrides for whatever's about to launch are loaded
    // into this cache FIRST (see _afterDrain()) rather than read inline.
    //
    // Always REASSIGNED whole, never mutated key-by-key — QML only emits a `var`
    // property's change signal on assignment, exactly the reason Config.wpeMonitors
    // is rewritten as a whole array everywhere else in this file rather than
    // pushed into. Mutating this in place would leave the properties editor
    // (Stage 4) never seeing its own writes reflected back.
    property var _propOverrideCache: ({})   // sceneId -> { key: "value string" }
    property var _overrideLoadCb: null

    // The value the editor should show for one property, or undefined if it's
    // at the scene's own default (nothing overridden).
    function overrideFor(id, key) {
        const ov = root._propOverrideCache[id]
        return ov ? ov[key] : undefined
    }

    // Resolves once every id in `ids` has a cache entry (possibly {}). One
    // Process for the whole batch — reads each `<id>/project.json`'s sibling
    // override file in a bash loop and prints "id\njson\n" pairs, the same
    // one-process-not-one-per-item shape as the scan Process above, rather than
    // a Process per scene id.
    function _loadOverrides(ids, cb) {
        const need = []
        for (const id of ids) if (id !== "" && root._propOverrideCache[id] === undefined) need.push(id)
        if (need.length === 0) { cb(); return }
        root._overrideLoadCb = cb
        overrideReadProc._lines = []
        overrideReadProc.command = ["bash", "-c",
            'd="$1"; shift; for id in "$@"; do echo "$id"; cat "$d/$id.json" 2>/dev/null || echo "{}"; done',
            "_", root._propertiesDir].concat(need)
        overrideReadProc.running = true
    }

    Process {
        id: overrideReadProc
        property var _lines: []
        stdout: SplitParser {
            onRead: function(line) { overrideReadProc._lines = overrideReadProc._lines.concat([line]) }
        }
        onExited: function(code) {
            // Lines alternate id / that id's JSON. Payloads are flat {key:value}
            // maps written by _writeOverrides via JSON.stringify with no `indent`,
            // so each is genuinely one line — `cat` never straddles a pair.
            const lines = overrideReadProc._lines
            const next = Object.assign({}, root._propOverrideCache)
            for (let i = 0; i + 1 < lines.length; i += 2) {
                try { next[lines[i]] = JSON.parse(lines[i + 1]) || {} }
                catch (e) { next[lines[i]] = {} }
            }
            root._propOverrideCache = next
            overrideReadProc._lines = []
            const cb = root._overrideLoadCb
            root._overrideLoadCb = null
            if (cb) cb()
        }
    }

    // Repeated ["--set-property", "key=value"] pairs for a cached scene — a
    // plain concat, no transform, because the store already holds the exact
    // wire-format string. A preset's own values go underneath the user's overrides
    // and the two are merged into ONE entry per key: the renderer collects them
    // into a flat map, and which of two repeats of a key wins isn't something to
    // lean on. Not cached yet / nothing overridden / no preset → nothing.
    function _propertyArgs(id) {
        const m = Object.assign({}, root.itemFor(id)?.props, root._propOverrideCache[id])
        let args = []
        for (const k in m) args = args.concat(["--set-property", k + "=" + root._wire(m[k])])
        return args
    }

    // "#rrggbb" → "0.274510 0.211765 0.501961" (see the wire-format note above).
    // Matched on the value's shape, not the property's type — the store doesn't
    // carry types — so a text or combo value that is literally "#rrggbb" would be
    // converted too. Nothing in the library does that.
    function _wire(v) {
        const m = /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})$/i.exec(String(v))
        return m ? [m[1], m[2], m[3]].map(h => (parseInt(h, 16) / 255).toFixed(6)).join(" ")
                 : v
    }

    property bool propertyWriting: propWriter.running

    function setPropertyOverride(id, key, value) {
        if (!id || !key) return
        const ov = Object.assign({}, root._propOverrideCache[id] || {})
        ov[key] = String(value)
        const cache = Object.assign({}, root._propOverrideCache)
        cache[id] = ov
        root._propOverrideCache = cache
        root._writeOverrides(id, ov)
        root._optionChangedFor(id)
    }

    function clearPropertyOverride(id, key) {
        if (!id || !key || !root._propOverrideCache[id]) return
        const ov = Object.assign({}, root._propOverrideCache[id])
        delete ov[key]
        const cache = Object.assign({}, root._propOverrideCache)
        cache[id] = ov
        root._propOverrideCache = cache
        root._writeOverrides(id, ov)
        root._optionChangedFor(id)
    }

    // A running scene (default OR any monitor) whose overrides just changed
    // needs a Refresh to pick them up — same needsRefresh contract as every
    // other launch-arg change.
    function _optionChangedFor(id) {
        if (!root.running) return
        const showing = root.current === id
            || Object.keys(root._runningMonitors).some(s => root._runningMonitors[s] === id)
        if (showing) root._optionsDirty = true
    }

    // Mirrors ColorScheme.qml's wallPaletteWriter exactly: mkdir -p + printf
    // %s "$PAYLOAD" > file, the payload riding the environment rather than
    // shell string interpolation.
    Process {
        id: propWriter
        running: false
        property string wid:     ""
        property string payload: ""
        environment: ({ "WPE_PROP_PAYLOAD": propWriter.payload })
        command: ["bash", "-c",
            'd="$1"; mkdir -p "$d"; printf %s "$WPE_PROP_PAYLOAD" > "$d/$2.json"',
            "_", root._propertiesDir, propWriter.wid]
    }

    function _writeOverrides(id, ov) {
        propWriter.wid     = id
        propWriter.payload = JSON.stringify(ov)
        propWriter.running = false
        propWriter.running = true
    }

    // ── Running one: an explicit state machine ────────────────────────────────
    // The first version derived `busy` from the two Processes' running flags, and
    // since pkill and a forking setsid each exit within milliseconds, busy was
    // false for essentially the whole apply — the UI showed nothing happening
    // while everything happened. The phase is explicit now, and covers the whole
    // journey: stop → gap → start → VERIFIED up (or failed, with the reason).
    //
    //   idle | starting | crossfading | stopping | verifying
    // (`starting`: the new renderer is loading ALONGSIDE the old one — see "The
    // crossfade" below; `crossfading`: it has mapped and Hyprland is fading it in.
    // `stopping` is also the old renderer being let go once the fade is done.)
    readonly property bool busy: root._phase !== "idle"
    // Read-only mirror of the phase for the UI. The settings page only needs
    // "busy", but the wallpaper PANEL replaces its gallery with a progress view
    // for the whole stop → start → verify journey, which is several seconds —
    // long enough that "Restarting…" for all of it reads as stuck.
    readonly property string phase: root._phase
    property string _phase: "idle"

    // Why the last apply failed, or "" — the tail of the renderer's own log,
    // surfaced in the UI. A start that dies is no longer silent.
    property string lastError: ""

    // Dismiss a reported failure. A function rather than letting callers write
    // `lastError = ""` themselves, so the one place it is cleared stays greppable.
    function clearError() { root.lastError = "" }

    property string _pendingId: ""   // queued behind the stop — the DEFAULT scene, may be ""
    // Distinguishes "apply() queued a (re)start" from "stop() just wants it gone" —
    // both leave _pendingId "" when there's no default scene (a monitors-only
    // setup), so _pendingId alone can no longer tell _afterDrain what to do.
    property bool   _pendingStart: false
    property string _verifyId:  ""   // being verified; used to kick the palette
    property int    _verifyTries: 0
    property int    _drainTries:  0

    // ── The particle-crash retry ────────────────────────────────────────────
    // `_particlesRetryUsed` marks that the one-shot particles-off mitigation has
    // been spent for the CURRENT apply session — set the moment a retry is
    // KICKED OFF (by either _verifyStep's "never came up" path or
    // _handleUnexpectedCrash's "came up, then died" path below) and never reset
    // except by a genuinely new apply()/stop(). This is deliberately NOT reset on
    // a successful verification: without that, a scene that crashes, recovers,
    // then crashes again later for an unrelated reason would retry forever.
    // `particlesAutoDisabledFor` is what the UI reads to explain why a scene
    // that's actually running looks different than expected.
    property bool   _particlesRetryUsed: false
    property string _particlesAutoDisabledFor: ""
    readonly property string particlesAutoDisabledFor: root._particlesAutoDisabledFor

    // True only once WE have verified a launch as up — the signal
    // _handleUnexpectedCrash needs to tell "something we started just died" from
    // "the user clicked stop" or "nothing of ours was ever running". Cleared by
    // apply()/stop() (a deliberate transition is starting) and by
    // _handleUnexpectedCrash itself (so one crash can't fire it twice).
    property bool   _expectRunning: false

    // `id` is the DEFAULT scene and may be "" — a setup with only per-monitor
    // overrides (Config.wpeMonitors) and no default has nothing to pass here.
    //
    // ── Suppressed while gamemode holds the wallpaper ──────────────────────────
    // A public apply() while Gamemode.wallpaperPaused is true never launches
    // anything — it hands the request to Gamemode's queue instead, which applies
    // it for real the moment the hold lets go. Starting a heavy scene process
    // mid-session would work against the whole point of pausing it, and it would
    // render invisibly behind the takeover card anyway. This is a public/internal
    // split rather than a check inside the launch logic itself: Gamemode's OWN
    // restore has to bypass it (that's `_applyNow`), or it would refuse its own
    // call the moment it tries to actually apply the queued or restored scene.
    // Every OTHER caller — the panel, the autostart timer, Wallpaper's own
    // periodic shuffle (which calls straight through Wallpaper.apply(), not this
    // one, but the same shape applies there) — goes through the public name and
    // is gated automatically, with nothing to remember to check.
    function apply(id) {
        if (Gamemode.wallpaperPaused) { Gamemode.queueScene(id); return }
        root._applyNow(id)
    }
    function _applyNow(id) {
        if (root.busy) return
        if (!id && (Config.wpeMonitors || []).length === 0) return
        // Autostart calls this on login too, so refusing SILENTLY would be a
        // wallpaper that never appears and never says why. lastError is exactly
        // the field for "the last start didn't happen, here's the reason".
        if (root.blocker() !== "") { root.lastError = root.blocker(); return }
        Config.wpeCurrent = id
        // Playing a scene is keeping it: a re-download is no longer something to warn about.
        if (id !== "") root._forgetUnsub(id)
        // The mirror of Wallpaper.apply disabling autostart for a still image: picking
        // a scene means the scene is the wallpaper, so it should come back on login.
        // "Start with the shell" stays the explicit override. The autostart timer only
        // calls this when it's already on, so that path is a no-op (QML dedupes).
        // Only when id is non-empty: a monitors-only apply() shouldn't flip this on
        // by itself — assignMonitor()/spanMonitors() do that for their own case.
        if (id !== "") Config.wpeAutoStart = true
        // Applying is the way back from Stop. Set before windowPlanned is asked below.
        root._heldStopped = false
        // The scene plays from a window of its own: no layer launch (see "The shared scene").
        if (id !== "" && id === root.windowShared && root.windowPlanned) { root._applyWindow(id); return }
        root.lastError  = ""
        root._pendingId = id
        root._pendingStart = true
        root._expectRunning = false
        root._particlesRetryUsed = false
        root._particlesAutoDisabledFor = ""
        watchdogTimer.stop()
        // The new scene is started ALONGSIDE the one playing and fades in over it —
        // nothing is stopped first (see "The crossfade"). Its colours ride the wave
        // from the moment it maps (_gotMapped), so the front and the fade play together.
        root._phase = "starting"
        snapProc.command = ["pgrep", "-f", root._procPattern]
        snapProc._pids = []
        snapProc.running = true
    }

    function stop() {
        if (root.busy) return
        // A scene in a window of its own is stopped by no longer wanting it (ScenePreload
        // follows windowShared); it stays stopped until the next apply().
        root._heldStopped = true
        root._stopLayer()
    }
    function _stopLayer() {
        if (root.busy) return
        root.lastError  = ""
        root._pendingId = ""
        root._pendingStart = false
        root._expectRunning = false
        root._particlesRetryUsed = false
        root._particlesAutoDisabledFor = ""
        watchdogTimer.stop()
        root._phase = "stopping"
        stopProc.running = true
    }

    Process {
        id: stopProc
        command: ["pkill", "-f", root._procPattern]
        onExited: function(code) {
            // pkill only SIGNALS the renderer; it can keep holding the audio
            // device for a moment while it tears down. Starting the replacement
            // now (as the old code did, on a flat 350ms timer) briefly runs TWO
            // instances, and the scene's soundtrack plays twice — an audible
            // echo. So we DRAIN first: poll until nothing matches the pattern,
            // and only then continue. 1 = nothing was running, which is fine.
            root._drainTries = 0
            drainTimer.start()
        }
    }

    // ── Draining: wait for the old renderer to actually be GONE ────────────────
    // Not just signalled — gone. This is what guarantees a single instance, which
    // is what guarantees the audio plays once.
    Timer {
        id: drainTimer
        interval: 150
        repeat: true
        onTriggered: { if (!drainProc.running) drainProc.running = true }
    }

    Process {
        id: drainProc
        command: ["pgrep", "-f", root._procPattern]
        onExited: function(code) {
            // pgrep exits 1 when nothing matched — the old renderer has exited.
            if (code !== 0) { drainTimer.stop(); root._afterDrain(); return }
            root._drainTries++
            // Still alive after a few polls means it's ignoring SIGTERM (stuck in
            // audio teardown). Escalate once to SIGKILL.
            if (root._drainTries === 4) killProc.running = true
            // If even that won't clear it, stop waiting rather than hang the apply
            // forever — one stubborn instance beats a frozen UI.
            if (root._drainTries >= 12) { drainTimer.stop(); root._afterDrain() }
        }
    }

    Process {
        id: killProc
        command: ["pkill", "-9", "-f", root._procPattern]
    }

    function _afterDrain() {
        if (root._pendingStart) {
            root._phase = "starting"
            // Property overrides for whatever's about to launch must be IN THE
            // CACHE before _launchCommand runs (it's synchronous and can't wait
            // on a file read of its own) — load them first, then start. The
            // drain/settle delays already in this path give a tiny local read
            // plenty of room to finish before it would matter.
            const ids = [root._pendingId].concat((Config.wpeMonitors || []).map(m => m.id))
                                         .concat(Object.values(root.effective()))
            root._loadOverrides(ids, () => startTimer.start())
        } else {
            root._phase = "idle"
            root.probe()
        }
    }

    // A short settle after the process is confirmed gone: the compositor releases
    // the dead renderer's layer surface a beat later, and starting into that gap
    // gave two surfaces fighting for the screen.
    Timer {
        id: startTimer
        interval: 250
        repeat: false
        onTriggered: {
            // _particlesRetryUsed is always false here — apply()/stop() just
            // reset it — so this is Config.wpeParticles's own value, unmodified.
            startProc.command = root._launchCommand(root._pendingId, root._particlesRetryUsed)
            root._verifyId  = root._pendingId
            root._pendingId = ""
            root._pendingStart = false
            // The launch command was just built from the CURRENT options, so the
            // running scene is about to match Config again — nothing pending.
            root._optionsDirty = false
            startProc.running = true
        }
    }

    // ── Live options: applied on demand, not on every change ───────────────────
    // The renderer has no IPC, so changing a render option genuinely means
    // RELAUNCHING the scene — a visible flicker. Doing that on every slider tick or
    // toggle is jarring, so a change to a running scene is only MARKED pending; the
    // settings page's Refresh button relaunches with the collected options. That
    // also lets a run of edits (fps + volume + monitor) cost ONE restart instead of
    // one each. wpeCurrent (the scene itself) is handled by apply() and the scene
    // palette is a separate path — neither belongs here; everything below is a
    // genuine launch argument.
    property bool _optionsDirty: false
    readonly property bool needsRefresh: root.running && !root.busy && root._optionsDirty

    function _optionChanged() {
        // Only meaningful while a scene is up — options for a stopped renderer just
        // ride along on the next Start, so there is nothing to refresh.
        if (root.running) root._optionsDirty = true
    }

    // Relaunch the running scene so the changed options take effect. The page's
    // Refresh button. A no-op unless a scene is up and something actually changed.
    // `root.current === ""` alone no longer means "nothing to restart" — a
    // monitors-only setup (no default scene) still has to survive a monitor's
    // scaling/clamp changing.
    function refresh() {
        if (!root.needsRefresh) return
        if (root.current === "" && (Config.wpeMonitors || []).length === 0) return
        // The SCENE hasn't changed, only render options — so the palette already on
        // disk is still correct. Skip re-deriving it, or a refresh would repaint
        // fourteen apps for an identical result. (Light/dark takes repalette().)
        root._skipPaletteOnce = true
        root.apply(root.current)
    }

    // The fps the renderer is launched with: Config.wpeFps, capped while the battery
    // saver is on. The saver switching relaunches a running scene once, and only when
    // the cap changes the number; a slider change still just marks Refresh pending.
    readonly property int launchFps: PowerSaver.active ? Math.min(Config.wpeFps, PowerSaver.wpeFpsCap) : Config.wpeFps
    Connections {
        target: PowerSaver
        function onActiveChanged() {
            if (Config.wpeFps <= PowerSaver.wpeFpsCap) return
            root._optionChanged()
            root.refresh()
        }
    }

    Connections {
        target: Config
        function onWpeFpsChanged()             { root._optionChanged() }
        function onWpeVsyncChanged()           { root._optionChanged() }
        function onWpeTargetChanged()          { root._optionChanged() }
        function onWpeMonitorsChanged()        { root._optionChanged() }
        function onWpeScalingChanged()         { root._optionChanged() }
        function onWpeClampChanged()           { root._optionChanged() }
        function onWpeMuteChanged()            { root._optionChanged() }
        function onWpeVolumeChanged()          { root._optionChanged() }
        function onWpeKeepAudioChanged()       { root._optionChanged() }
        function onWpePauseFullscreenChanged() { root._optionChanged() }
        function onWpeAudioProcessingChanged() { root._optionChanged() }
        // The shell's own pan has no launch argument: only the layer renderer reads these.
        function onWpeMouseChanged()           { if (!root.windowPlanned) root._optionChanged() }
        function onWpeParallaxChanged()        { if (!root.windowPlanned) { root._optionChanged(); parallaxApply.restart() } }
        function onWpeParticlesChanged()       { root._optionChanged() }
    }

    // Parallax is the one option worth applying by itself: a switch you flip to SEE what it does.
    // The relaunch is the crossfade (the new renderer maps over the old, which keeps playing
    // until it has), with the palette left alone — so nothing blinks. Debounced, so flipping
    // it twice costs one relaunch; held off while a run is in flight.
    Timer {
        id: parallaxApply
        interval: 700
        onTriggered: {
            if (!root._running || root.windowPlanned) return
            if (root.busy) { parallaxApply.restart(); return }
            root.refresh()
        }
    }

    Process {
        id: startProc
        onExited: function(code) {
            // Alongside the old one: nothing to verify by pgrep (the old renderer
            // already matches). The crossfade's own check finds the NEW pids.
            if (root._overlap) { root._watchNew(); return }
            // setsid has forked and gone; the renderer is now on its own. Whether
            // it SURVIVED is a separate question — hence verification.
            root._phase = "verifying"
            root._verifyTries = 0
            verifyTimer.start()
        }
    }

    // ── Verification ──────────────────────────────────────────────────────────
    // The SIGPIPE bug above is exactly why this exists: a launch can succeed and
    // the renderer still die moments later. Probe once a second; alive → done,
    // and the scene palette kicks off. Still dead after 5 tries → declare failure
    // and read the renderer's log for the reason.
    Timer {
        id: verifyTimer
        interval: 1000
        repeat: true
        onTriggered: root.probe()
    }

    function _verifyStep() {
        if (root._phase !== "verifying") return
        if (root._running) {
            verifyTimer.stop()
            root._phase = "idle"
            root.lastError = ""
            root._expectRunning = true
            // A retry (below, or from _handleUnexpectedCrash) succeeded — note it
            // for the UI, which reads particlesAutoDisabledFor to explain why this
            // scene looks plainer than its preview.
            if (root._particlesRetryUsed) root._particlesAutoDisabledFor = root._verifyId
            const id = root._verifyId
            root._verifyId = ""
            root._kickScenePalette(id)
            // If this start was taking the scene's first still, pick it up for next time.
            if (id !== "" && !root._stills[id]) stillsRescan.restart()
            // See _handleUnexpectedCrash: "came up" alone isn't proof it STAYS
            // up, and the only other thing watching (the 2s `poll` timer) is
            // gated on a settings panel being open — autostart has none. Keep
            // sampling for a few more seconds so a delayed crash is still caught
            // even when nobody's looking, without holding up the state above.
            root._watchdogChecks = 0
            watchdogTimer.restart()
            return
        }
        root._verifyTries++
        if (root._verifyTries >= 5) {
            verifyTimer.stop()
            if (root._tryParticlesRetry()) return
            root._phase = "idle"
            root._verifyId = ""
            // A failed start never reaches the palette kick; a flag left set would
            // skip the next scene's colours as if it were a restart.
            root._skipPaletteOnce = false
            tailProc.running = true
        }
    }

    // ── One automatic retry, particles off ────────────────────────────────────
    // A verified, reproducible crash class in the renderer itself: some Workshop
    // scenes segfault inside CParticle construction (checked with coredumpctl
    // against a real failing scene — this isn't a guess). --disable-particles is
    // the CLI's own documented mitigation and was never wired up before. Shared
    // by _verifyStep's "never came up" path and _handleUnexpectedCrash's "came
    // up, then died" path below — _particlesRetryUsed being set (and staying set
    // for the rest of this apply session) is what stops either one from looping
    // forever, and it's only attempted when the user's own Config.wpeParticles
    // is on (off already means there's nothing left to try that particles
    // caused). Relaunches directly — no drain — because by the time either
    // caller reaches this, the old process is already confirmed gone.
    function _tryParticlesRetry() {
        if (root._particlesRetryUsed || !Config.wpeParticles) return false
        root._particlesRetryUsed = true
        root._verifyTries = 0
        root._phase = "starting"
        // Mid-crossfade the old renderer is still up and the failed one is gone:
        // start again alongside, and the watch begins afresh.
        if (root._overlap) { root._newPids = []; root._seenNew = false; root._startedAt = Date.now() }
        startProc.command = root._launchCommand(root._verifyId, true)
        startProc.running = true   // its own onExited re-enters "verifying" (or the watch)
        return true
    }

    // ── Watching for a DELAYED crash after a successful verify ─────────────────
    // Ticks root.probe() a few more times right after "up" is first declared.
    // Its OWN onExited (in probeProc) is what actually notices a running→gone
    // transition and calls _handleUnexpectedCrash — this timer only has to keep
    // samples coming for a few seconds, independent of whether any UI panel is
    // open (see the comment on _expectRunning).
    property int _watchdogChecks: 0
    readonly property int _watchdogChecksNeeded: 5   // ~6s of coverage at 1200ms

    Timer {
        id: watchdogTimer
        interval: 1200
        repeat: true
        onTriggered: {
            root._watchdogChecks++
            if (root._watchdogChecks > root._watchdogChecksNeeded || !root._expectRunning) {
                watchdogTimer.stop()
                return
            }
            root.probe()
        }
    }

    // Called from probeProc.onExited when something WE verified as running has
    // gone away on its own — see the comment there for exactly what rules that
    // out a deliberate stop()/apply().
    function _handleUnexpectedCrash() {
        root._expectRunning = false
        watchdogTimer.stop()
        // _verifyId was already cleared back to "" by the SUCCESSFUL verify that
        // preceded this — it names "what's currently being verified", not "what
        // was last confirmed running", and by this point nothing is verifying.
        // Restore it from Config.wpeCurrent (the same source apply() itself
        // reads) so _tryParticlesRetry rebuilds the launch for the right scene
        // instead of an empty one — an empty default id with no monitors
        // configured is what produced "At least one background ID must be
        // specified" the first time this path was exercised.
        root._verifyId = Config.wpeCurrent
        if (root._tryParticlesRetry()) return
        // Already tried the mitigation this apply session, or the user already
        // has particles off — nothing left to automatically try. Read the
        // renderer's own log so this isn't a silent "it just stopped".
        tailProc.running = true
    }

    Process {
        id: tailProc
        command: ["tail", "-n", "4", root.logFile]

        property var _lines: []
        stdout: SplitParser {
            onRead: function(line) { tailProc._lines = tailProc._lines.concat([line]) }
        }
        onExited: function(code) {
            const t = tailProc._lines.join("\n").trim()
            root.lastError = t !== "" ? t : "The renderer exited without logging anything."
            tailProc._lines = []
        }
    }

    // ── Colours from the scene ────────────────────────────────────────────────
    // The scene is animated, but its Workshop preview is an honest still of it —
    // so the shell's palette can follow an animated wallpaper the same way it
    // follows a static one: pywal on the preview, then the shared reload
    // pipeline. `--palette-only` stops the script from touching the actual
    // wallpaper (the scene is covering it) or recording the preview as the
    // current static image (which would make the images tab lie).
    readonly property bool paletteApplying: paletteRunner.running

    ThemeRunner {
        id: paletteRunner
        appName: "Scene colours"
        icon: "wallpaper"

        onFinished: function(code) {
            if (code !== 0)
                paletteRunner.notify("Scene colours failed",
                    "Could not derive a palette from the scene's preview.", "normal")
        }
    }

    // Set for the autostart path: on login the palette on disk already IS this
    // scene's, so re-deriving it would repaint every themed app for an identical
    // result — pure churn at the worst moment.
    property bool _skipPaletteOnce: false

    function _kickScenePalette(id) {
        if (root._skipPaletteOnce) { root._skipPaletteOnce = false; return }
        if (!Config.wallTheming) return
        if (!Config.wpeScenePalette || paletteRunner.running) return
        // A monitors-only launch (no default scene) has no `id` to key the palette
        // on — fall back to the first monitor override rather than deriving
        // nothing at all.
        const paletteId = id !== "" ? id
            : ((Config.wpeMonitors && Config.wpeMonitors.length > 0) ? Config.wpeMonitors[0].id : "")
        const it = root.itemFor(paletteId)
        if (!it || it.preview === "") return
        paletteRunner.run(root._paletteCommand(paletteId, it.preview), it.title,
                          { image: "", recolor: true })
    }

    // Colours from a scene's Workshop PREVIEW, keyed "scene_<id>" so a palette saved
    // for the scene wins. The preview even when a full-res still exists (the water
    // uses that): pywal caches palettes per picture, and switching the source would
    // quietly re-derive — and change — every scene's colours.
    function _paletteCommand(id, preview) {
        const flags = Config.themeMode === "light" ? ["--light"] : []
        return ["bash", Quickshell.shellPath("scripts/apply-wallpaper.sh"),
                "--palette-only", "--palette-key", "scene_" + id]
               .concat(flags).concat([preview])
    }

    // ══ Stills ════════════════════════════════════════════════════════════════
    // The first time a scene plays, the renderer saves a full-resolution frame of it
    // (`--screenshot`, 30 frames in; it keeps playing). Kept in the cache; a still that's
    // lost is simply taken again. Nothing draws them any more — a scene no longer arrives
    // as water (see "The crossfade") — they're kept for the day something wants a picture.
    // Where the scanner writes a preset's pictures as .tex files, one folder per preset.
    readonly property string texturesDir:
        (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache"))
        + "/quickshell-quicktest/wpe-textures"
    readonly property string stillsDir:
        (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache"))
        + "/quickshell-quicktest/wpe-stills"
    property var _stills: ({})

    // The picture the water spreads for a scene: its still, else its preview, else
    // "" (no water — the scene just swaps, as it always did).
    function stillFor(id) {
        if (!/^[0-9]+$/.test(String(id))) return ""
        if (root._stills[id]) return root.stillsDir + "/" + id + ".png"
        const it = root.itemFor(id)
        return it && it.preview ? it.preview : ""
    }

    Process {
        id: stillsProc
        running: true
        command: ["bash", "-c",
            'mkdir -p "$1" && cd "$1" && for f in *.png; do [ -s "$f" ] && echo "${f%.png}"; done; true',
            "_", root.stillsDir]
        property var _rows: ({})
        stdout: SplitParser {
            onRead: function(line) { if (/^[0-9]+$/.test(line)) stillsProc._rows[line] = true }
        }
        onExited: {
            root._stills = stillsProc._rows
            stillsProc._rows = ({})
        }
    }
    // The renderer writes a new still ~30 frames after it starts; look again then.
    Timer {
        id: stillsRescan
        interval: 4000
        onTriggered: { stillsProc.running = false; stillsProc.running = true }
    }

    // ══ The crossfade ═════════════════════════════════════════════════════════
    // A new scene is started ALONGSIDE the one playing, loads while that keeps
    // animating, and fades in over it — so there is never a still, and never a swap
    // from a picture of the scene to the scene itself (that swap was the "adjusting"
    // after the water: a frame taken 30 frames in, framed by the shell, replaced by
    // the real thing at its first frame). The water used to wait for the old scene to
    // be stopped and the new one to LOAD, several seconds of a frozen picture.
    //
    // The fade is Hyprland's own: it eases every freshly mapped layer surface in
    // (`fade`, speed 10 — hypr/animation.lua — a second), and the new scene maps over
    // the old one because the later surface is the upper one. Nothing here draws it.
    // (A layer rule can't hold the new scene UNDER the old for a cleverer reveal: rules
    // match on namespace only, both renderers share one, and a rule re-sorts the
    // surfaces already mapped too. Measured, not assumed.)
    //
    // The old renderer is let go by PID, once the fade is done. `pkill -f` — what stop()
    // uses — would take the new one with it.
    //
    // Its colours go on the wave once it maps (_startColours), the same as a still's,
    // minus the water: the picture changes by the fade, the shell by the front.
    //
    // ── Audio ─────────────────────────────────────────────────────────────────
    // Two scenes at once play two soundtracks. The new renderer's PipeWire stream is
    // muted (matched on application.process.id) from when it appears until the old
    // one is gone, then unmuted. There is a blip between the stream appearing and the
    // next 150ms tick. The mute is the stream's own, and PipeWire may remember it, so
    // it is undone on every way out — including this singleton being destroyed.
    property bool   _overlap: false     // a renderer is coming up beside the old one
    property var    _oldPids: []        // what was playing when this change began
    property var    _newPids: []        // what is not in _oldPids
    property bool   _seenNew: false
    property bool   _mapped: false      // the new renderer has a surface on screen
    property double _startedAt: 0
    property double _mapSeenAt: 0
    // Hyprland's layer fade-in (animation.lua: fade, speed 10 = 1s) and a margin. If that
    // setting changes, this is the number to follow.
    readonly property int _fadeMs: 1200
    // A scene loading over NOTHING (no old one): `running` stays false until it maps, so
    // the shell's own wallpaper stays up under the load (see probeProc).
    readonly property bool _loadingBare: root._overlap && !root._mapped && root._oldPids.length === 0

    // The scene's colours, on the wave, from the moment the scene maps and starts to fade
    // in — started any earlier they changed seconds ahead of the wallpaper (a scene takes
    // as long to load as it takes), and a scene that then failed left the old one wearing
    // the new one's palette. Not for a
    // restart of the same scene (the palette on disk is already its own), nor with
    // animations off, nor for a scene with no preview — those take the plain kick once
    // it is up. Sets the skip flag so that kick doesn't paint a second time.
    function _startColours(id) {
        if (!WallWave.enabled || root._skipPaletteOnce || Gamemode.wallpaperPaused) return
        if (!Config.wallTheming || !Config.wpeScenePalette || paletteRunner.running) return
        const it = root.itemFor(id)
        if (it === null || it.preview === "") return
        // Set BEFORE the run, and not from `paletteRunner.running` afterwards: that is a
        // binding on the child's `running`, which Quickshell only notifies once the child
        // has STARTED, so it still reads false right after run(). Checked that way the
        // flag was never set and the kick at the end of the change painted a second wave
        // (the "it refreshes after" — the log showed two colour waves per scene change).
        // run() can't refuse here: it only does so while it is already running, and that
        // is guarded above.
        root._skipPaletteOnce = true
        paletteRunner.run(root._paletteCommand(id, it.preview), it.title,
                          { image: "", recolor: true })
    }

    // What is playing right now, read fresh — `running` is a cache. These are the ones
    // that go once the new scene has faded in.
    Process {
        id: snapProc
        property var _pids: []
        stdout: SplitParser {
            onRead: function(line) {
                const p = parseInt(line)
                if (p > 0) snapProc._pids.push(p)
            }
        }
        onExited: {
            root._oldPids = snapProc._pids
            root._newPids = []
            root._seenNew = false
            root._mapped = false
            root._mapSeenAt = 0
            root._overlap = true
            // Property overrides must be in the cache before _launchCommand runs
            // (it's synchronous) — same as before the launch always.
            const ids = [root._pendingId].concat((Config.wpeMonitors || []).map(m => m.id))
                                         .concat(Object.values(root.effective()))
            root._loadOverrides(ids, () => root._launchNew())
        }
    }

    function _launchNew() {
        startProc.command = root._launchCommand(root._pendingId, root._particlesRetryUsed)
        root._verifyId  = root._pendingId
        root._pendingId = ""
        root._pendingStart = false
        // Built from the CURRENT options, so the running scene will match Config again.
        root._optionsDirty = false
        root._startedAt = Date.now()
        root._coloursStarted = false
        root._openAt = 0
        // A scene seen before: start its colours early enough that the front leaves as
        // the scene starts to fade in. One not seen yet starts them at the map.
        const known = root._loadMsFor(root._verifyId)
        if (known > 0) {
            colourTimer.interval = Math.max(0, known - WallWave.leadMs)
            colourTimer.restart()
        }
        startProc.running = true   // its onExited starts the watch
    }

    // ── When the colours start ────────────────────────────────────────────────
    // The wave takes WallWave.leadMs to get its front moving after it is asked for, and
    // the scene's fade starts the moment it maps — so asked for AT the map, the scene is
    // up before the front leaves ("the wallpaper shows up early and then the wave comes").
    // So it is asked for that much BEFORE: how long this scene took to map last time is
    // remembered (wpe-load-times.json, state — never config.json), smoothed.
    property bool _coloursStarted: false
    function _beginColours() {
        if (root._coloursStarted) return
        root._coloursStarted = true
        root._startColours(root._verifyId)
    }
    Timer {
        id: colourTimer
        onTriggered: if (root._overlap && root._phase === "starting") root._beginColours()
    }

    JsonStore {
        id: loadStore
        path: Quickshell.statePath("wpe-load-times.json")
        defaults: ({})
    }
    // Hand-editable, so only a plausible number is believed.
    function _loadMsFor(id) {
        const v = loadStore.value[id]
        return (typeof v === "number" && v > 0 && v < 60000) ? v : 0
    }
    function _learnLoad(id, ms) {
        if (id === "" || !loadStore.ready || !(ms > 0) || ms >= 60000) return
        const old = root._loadMsFor(id)
        const next = {}
        for (const k in loadStore.value) next[k] = loadStore.value[k]
        next[id] = Math.round(old > 0 ? (old + ms) / 2 : ms)
        loadStore.value = next
    }

    // When the new renderer's surface really mapped. Hyprland says so (`openlayer`), which
    // is exact; the once-a-second check that finds it afterwards isn't.
    property double _openAt: 0
    Connections {
        target: Hyprland
        enabled: root._overlap && !root._mapped
        function onRawEvent(event) {
            if (event.name !== "openlayer" || root._openAt > 0) return
            if (String(event.data).indexOf("quickshell") === 0) return
            root._openAt = Date.now()
        }
    }

    // ── Waiting for it to come up, and to draw ────────────────────────────────
    // One question once a second, until the new surface is on screen: which renderer
    // pids exist that weren't there before, and does Hyprland list a layer surface
    // owned by one of them. A timer, not an event, because a renderer that dies has no
    // event — and nothing here is visible: the old scene is still playing, so a late
    // answer only delays letting it go.
    function _watchNew() { checkTimer.restart(); root._check() }
    function _check() { if (!checkProc.running) checkProc.running = true }

    Timer {
        id: checkTimer
        interval: 1000
        repeat: true
        onTriggered: root._check()
    }

    Process {
        id: checkProc
        // Line 1: every renderer pid. Then `hyprctl layers -j`.
        command: ["bash", "-c", 'pgrep -f "$1" | tr "\\n" " "; echo; exec hyprctl layers -j',
                  "_", root._procPattern]
        stdout: StdioCollector {
            onStreamFinished: root._checked(text)
        }
    }

    function _checked(text) {
        if (!root._overlap || root._phase !== "starting") return
        const nl = text.indexOf("\n")
        const all = (nl < 0 ? text : text.slice(0, nl)).trim().split(/\s+/)
                        .filter(s => s !== "").map(Number)
        const fresh = all.filter(p => root._oldPids.indexOf(p) === -1)
        if (fresh.length > 0) {
            root._newPids = fresh
            root._seenNew = true
        } else if (root._seenNew || Date.now() - root._startedAt > 10000) {
            // Came up and went (or never came up at all). The old scene is untouched.
            root._newFailed()
            return
        } else {
            return
        }
        let n = 0
        try {
            const mons = JSON.parse(text.slice(nl + 1))
            for (const m in mons)
                for (const lvl in mons[m].levels)
                    for (const s of mons[m].levels[lvl])
                        if (fresh.indexOf(s.pid) !== -1) n++
        } catch (e) { n = 0 }
        if (n === 0) {
            // Alive for 30s and still no surface: a renderer that hung loading.
            if (Date.now() - root._startedAt > 30000) root._newFailed()
            return
        }
        if (root._mapSeenAt === 0) root._mapSeenAt = Date.now()
        // Every screen it covers — or a second after the first, so one that never draws
        // can't hold the old scene up for good.
        const want = root._launchScreens.length > 0 ? root._launchScreens.length
                   : Config.wpeTarget === "" ? Math.max(1, root.screenNames().length) : 1
        if (n >= want || Date.now() - root._mapSeenAt > 1500) root._gotMapped()
    }

    function _gotMapped() {
        checkTimer.stop()
        root._mapped = true
        root._phase = "crossfading"
        root._learnLoad(root._verifyId, (root._openAt > 0 ? root._openAt : Date.now()) - root._startedAt)
        colourTimer.stop()
        root._beginColours()
        root.probe()          // `running` may say true now
        fadeTimer.restart()
    }

    Timer {
        id: fadeTimer
        interval: root._fadeMs
        onTriggered: root._retireOld()
    }

    // Only the pids this change recorded, and only while their command line still names
    // the renderer — a pid can be reused in the seconds a scene takes to load.
    function _retireOld() {
        if (root._oldPids.length === 0) { root._finishSwap(); return }
        root._phase = "stopping"
        retireProc.command = ["bash", "-c",
            'live=(); for p in "$@"; do grep -qa linux-wallpaperengine "/proc/$p/cmdline" 2>/dev/null && live+=("$p"); done; '
            + '[ ${#live[@]} -gt 0 ] || exit 0; kill "${live[@]}" 2>/dev/null; '
            + 'for _ in $(seq 30); do a=0; for p in "${live[@]}"; do kill -0 "$p" 2>/dev/null && a=1; done; '
            + '[ $a = 0 ] && exit 0; sleep 0.1; done; kill -9 "${live[@]}" 2>/dev/null; exit 0',
            "_"].concat(root._oldPids.map(String))
        retireProc.running = true
    }
    Process {
        id: retireProc
        onExited: root._finishSwap()
    }

    function _finishSwap() {
        root._overlap = false
        root._unmuteIncoming()
        root._phase = "idle"
        root.lastError = ""
        root._expectRunning = true
        if (root._particlesRetryUsed) root._particlesAutoDisabledFor = root._verifyId
        const id = root._verifyId
        root._verifyId = ""
        root._oldPids = []
        root._newPids = []
        root._kickScenePalette(id)
        if (id !== "" && !root._stills[id]) stillsRescan.restart()
        root.probe()
        // Same as a normal verify: keep sampling a few seconds for a delayed crash.
        root._watchdogChecks = 0
        watchdogTimer.restart()
    }

    // The new renderer didn't make it. The old scene is still playing, which is the
    // point of doing it this way: a failed change leaves the wallpaper as it was.
    function _newFailed() {
        checkTimer.stop()
        fadeTimer.stop()
        colourTimer.stop()
        if (root._newPids.length > 0)
            Quickshell.execDetached(["kill"].concat(root._newPids.map(String)))
        root._unmuteIncoming()
        if (root._tryParticlesRetry()) return
        root._overlap = false
        root._phase = "idle"
        root._verifyId = ""
        root._oldPids = []
        root._newPids = []
        root._skipPaletteOnce = false
        tailProc.running = true
        root.probe()
    }

    // ── The new scene's own soundtrack, held back until the old one is gone ───
    property var _mutedNodes: []
    Timer {
        id: muteTimer
        interval: 150
        repeat: true
        running: root._overlap && root._newPids.length > 0 && !Config.wpeMute
        onTriggered: root._muteIncoming()
    }
    function _muteIncoming() {
        const mine = ({})
        for (const p of root._newPids) mine[String(p)] = true
        for (const n of Audio.streams) {
            const pid = n.properties ? n.properties["application.process.id"] : undefined
            if (pid === undefined || !mine[String(pid)] || !n.audio || n.audio.muted) continue
            n.audio.muted = true
            root._mutedNodes.push(n)
        }
    }
    function _unmuteIncoming() {
        for (const n of root._mutedNodes) {
            try { if (n && n.audio) n.audio.muted = false } catch (e) {}
        }
        root._mutedNodes = []
    }
    Component.onDestruction: root._unmuteIncoming()

    // Re-derive the palette from the current scene — the theme-mode switch's
    // route when a scene is what's colouring the shell. `_kickScenePalette`
    // only ever reads the scene's WORKSHOP PREVIEW off disk — it never needed
    // the renderer process alive, so a scene gamemode has paused can still be
    // recoloured from; `running` alone would silently no-op for exactly the
    // case Gamemode.wallpaperPaused names. Config.wpeCurrent is the same
    // stable fallback WallpaperPanel's hero already trusts while paused.
    function repalette() {
        if (root.running) { root._kickScenePalette(root.current); return }
        if (Gamemode.wallpaperPaused) root._kickScenePalette(Config.wpeCurrent)
    }

    // ── Autostart ─────────────────────────────────────────────────────────────
    // NOTE: a lazy singleton's timers only exist once something references it —
    // shell.qml holds that reference now, which is the only reason this can fire
    // on login rather than on first opening the settings page.
    //
    // The delay outwaits Config's async JSON load: firing at onCompleted would
    // read wpeAutoStart's default (false) and the setting would never work — the
    // same restore-before-load trap that broke the remembered settings page.
    Timer {
        interval: 4000
        repeat: false
        running: true
        onTriggered: {
            if (!Config.wpeAutoStart) return
            // A monitors-only setup (no default scene) still needs restoring.
            if (Config.wpeCurrent === "" && (Config.wpeMonitors || []).length === 0) return
            autoProbe.running = true
        }
    }

    Process {
        id: autoProbe
        command: ["pgrep", "-f", root._procPattern]
        onExited: function(code) {
            // 0 = already running. Leave it alone; the user's wallpaper is up.
            if (code === 0) { root.probe(); return }
            root._skipPaletteOnce = true
            root.apply(Config.wpeCurrent)
        }
    }

    // ── The command ───────────────────────────────────────────────────────────
    // `setsid --fork` detaches it (the wallpaper must outlive a shell reload);
    // the bash stage exists ONLY to point the child's output at a real file —
    // see the SIGPIPE note at the top. "$0"/"$@" keep every argument out of the
    // shell string, so no path is ever re-parsed.
    //
    // `--layer background` is deliberate and load-bearing: the renderer defaults
    // to `bottom`, which is ABOVE the background layer — that is what buried
    // CavaBG. With the shell owning the launch, the ordering is a fact, not a
    // race against whoever mapped last.
    //
    // ── One process, several scenes ───────────────────────────────────────────
    // `--help`'s own multi-screen example (`--screen-root A --bg X --screen-root B
    // --bg Y`) is a SINGLE invocation, so per-monitor scenes don't need a second
    // process — just more --screen-root/--bg pairs. Config.wpeMonitors entries go
    // first (each with its own scaling/clamp, or a --screen-span when an entry
    // covers more than one screen); the DEFAULT scene (`id`, may be "" when only
    // monitor overrides are configured) fills whatever screens neither entry
    // claims, carrying Config.wpeScaling/wpeClamp instead.
    // `forceNoParticles` is the crash-retry path (see _verifyStep): overrides
    // Config.wpeParticles for exactly one launch attempt without touching the
    // user's actual preference.
    // The renderer's arguments for ONE scene in a window of its own (services/ScenePreload):
    // silent (the shell shows the picture, not the sound) unless it is the shared scene,
    // same scene properties and quality switches as the layer renderer. `w`×`h` is the window's size in pixels.
    // What `--bg` is for a scene in a window: its id, or a preset's own folder. Also how
    // ScenePreload recognises a renderer it started before (the command line says it).
    function windowBg(id) {
        const it = root.itemFor(id)
        return (it?.texdir || it?.base) ? (it.texdir || (root.workshopDir + "/" + it.base)) : id
    }
    function windowArgs(id, w, h) {
        const it = root.itemFor(id)
        const bg = root.windowBg(id)
        let a = ["--window", "0x0x" + Math.round(w) + "x" + Math.round(h),
                 "--assets-dir", root.assetsDir, "--bg", bg, "--fps", String(root.launchFps)]
        if (id === root.windowShared && !Config.wpeMute) {
            // The shared scene is THE wallpaper: its sound and its audio-reactive layers are
            // wanted, exactly as the layer renderer played them. Every other window is silent.
            a = a.concat(["--volume", String(Config.wpeVolume)])
            if (Config.wpeKeepAudio) a = a.concat(["--noautomute"])
            if (!Config.wpeAudioProcessing) a = a.concat(["--no-audio-processing"])
        } else {
            a = a.concat(["--silent", "--no-audio-processing"])
        }
        if (!Config.wpePauseFullscreen) a = a.concat(["--no-fullscreen-pause"])
        if (!Config.wpeParticles) a = a.concat(["--disable-particles"])
        if (it !== null && it.type === "web") a = a.concat(["--no-sandbox"])
        return a.concat(root._propertyArgs(id))
    }

    function _launchCommand(id, forceNoParticles) {
        // A preset renders as its base scene; its values ride on _propertyArgs. One
        // with pictures plays from a folder of its own (the scanner builds it: the
        // base's files linked, plus the pictures as .tex), which also makes argv name
        // the preset itself.
        const bgDir = sceneId => {
            const it = root.itemFor(sceneId)
            return it?.texdir || (root.workshopDir + "/" + (it?.base || sceneId))
        }
        let args = ["--layer", "background",
                    "--assets-dir", root.assetsDir]

        const allScreens = root.screenNames()
        // Same "a stale pin resets rather than silently vanishing" rule
        // targetScreens() already applies to wpeTarget — a monitor unplugged
        // since it was assigned drops out here instead of being asked for by name.
        const monitors = (Config.wpeMonitors || []).filter(m =>
            m.screens && m.screens.length > 0
            && m.screens.every(s => allScreens.indexOf(s) !== -1))

        const covered = ({})
        for (const m of monitors) for (const s of m.screens) covered[s] = true

        // ── A caveat worth knowing, not worth working around ──────────────────
        // --set-property has no --screen-root-style scoping in the renderer
        // (checked in its source: ApplicationContext.cpp collects it into ONE
        // flat map for the whole process; WallpaperApplication::setupPropertiesForProject
        // applies any override key to WHATEVER project defines a property by that
        // name). Two different monitors running two scenes that happen to share a
        // property key — both from a common base scene, say — would both take the
        // same overridden value. Real, but only matters for that specific
        // collision; grouping each scene's own --set-property right after its own
        // --bg below is for readability, not correctness.
        root._launchScreens = []
        if (root.wsMode) {
            // ── Scenes per workspace: one --screen-root per screen that plays one ──
            // (effective(): each screen's workspace's own scene, else the shared one;
            // a screen whose workspace has a PICTURE isn't given to the renderer at all.)
            // No spans here — a workspace belongs to one screen. A screen's own
            // scaling/clamp comes from its Config.wpeMonitors entry when it plays that
            // entry's scene, else the default's.
            const eff = root.effective()
            const done = []
            for (const s of Object.keys(eff).sort()) {
                const sid = eff[s]
                const cfg = (Config.wpeMonitors || []).find(m => m.screens.length === 1 && m.screens[0] === s && m.id === sid)
                args = args.concat(["--screen-root", s, "--bg", bgDir(sid)])
                const sc = cfg ? cfg.scaling : Config.wpeScaling
                const cl = cfg ? cfg.clamp : Config.wpeClamp
                if (sc && sc !== "default") args = args.concat(["--scaling", sc])
                if (cl && cl !== "clamp")   args = args.concat(["--clamp", cl])
                if (done.indexOf(sid) < 0) { done.push(sid); args = args.concat(root._propertyArgs(sid)) }
            }
            root._launchScreens = Object.keys(eff)
        } else {
            for (const m of monitors) {
                args = m.screens.length > 1
                    ? args.concat(["--screen-span", m.screens.join(","), "--bg", bgDir(m.id)])
                    : args.concat(["--screen-root", m.screens[0], "--bg", bgDir(m.id)])
                if (m.scaling && m.scaling !== "default") args = args.concat(["--scaling", m.scaling])
                if (m.clamp   && m.clamp   !== "clamp"  ) args = args.concat(["--clamp", m.clamp])
                args = args.concat(root._propertyArgs(m.id))
            }

            if (allScreens.length === 0) {
                // No screens report usable names at all → the bare positional form,
                // unchanged from before per-monitor scenes existed. Monitor overrides
                // can't be expressed without a screen name, so only the default plays.
                if (monitors.length === 0 && id !== "") {
                    args = args.concat(["--bg", bgDir(id)])
                    args = args.concat(root._propertyArgs(id))
                }
            } else if (id !== "") {
                // One --bg per --screen-root for whatever screens no override claimed.
                const remaining = root.targetScreens().filter(s => !covered[s])
                for (const s of remaining) {
                    args = args.concat(["--screen-root", s, "--bg", bgDir(id)])
                    if (Config.wpeScaling !== "default") args = args.concat(["--scaling", Config.wpeScaling])
                    if (Config.wpeClamp   !== "clamp"  ) args = args.concat(["--clamp", Config.wpeClamp])
                }
                if (remaining.length > 0) args = args.concat(root._propertyArgs(id))
            }
        }

        args = args.concat(["--fps", String(root.launchFps)])

        if (Config.wpeMute) {
            args = args.concat(["--silent"])
        } else {
            args = args.concat(["--volume", String(Config.wpeVolume)])
            // Without this the renderer silences itself whenever ANY other app
            // plays a sound — which reads as "audio doesn't work", because
            // something is nearly always making a sound.
            if (Config.wpeKeepAudio) args = args.concat(["--noautomute"])
        }

        if (!Config.wpePauseFullscreen) args = args.concat(["--no-fullscreen-pause"])
        if (!Config.wpeAudioProcessing) args = args.concat(["--no-audio-processing"])
        if (!Config.wpeMouse)    args = args.concat(["--disable-mouse"])
        if (!Config.wpeParallax) args = args.concat(["--disable-parallax"])
        if (!Config.wpeParticles || forceNoParticles) args = args.concat(["--disable-particles"])

        // The scene's first still, for its water next time (see "The water").
        if (id !== "" && /^[0-9]+$/.test(id) && !root._stills[id])
            args = args.concat(["--screenshot", root.stillsDir + "/" + id + ".png",
                                "--screenshot-delay", "30"])

        // ── "web" scenes need CEF told to stand its sandbox down ───────────────
        // linux-wallpaperengine embeds CEF (Chromium) for web-type scenes, and CEF's
        // sandbox needs its `chrome-sandbox` helper to be setuid-root — which this
        // AUR install (and most others) never sets up. Verified with coredumpctl:
        // WITHOUT this flag, every web-type scene here crashes deterministically
        // inside CefInitialize (SIGTRAP in AdjustLinuxOOMScore/ImmediateCrash)
        // before it even reaches its own content — this is the browser process
        // failing to START, not a per-scene bug. `--no-sandbox` reaches CEF for
        // free: CefMainArgs wraps THIS PROCESS'S OWN argc/argv (see
        // WebBrowserContext.cpp), so CEF's own switch parser sees it directly, and
        // the app's own argument parser was checked empirically to tolerate an
        // arg it doesn't itself define rather than rejecting the whole command
        // line. Added whenever a web scene is part of THIS launch — unconditional,
        // not just a crash-retry, because the failure is deterministic, not flaky.
        const allLaunchIds = monitors.map(m => m.id).concat(id !== "" ? [id] : [])
                                     .concat(root.wsMode ? Object.values(root.effective()) : [])
        if (allLaunchIds.some(i => { const it = root.itemFor(i); return it !== null && it.type === "web" }))
            args = args.concat(["--no-sandbox"])

        // ── V-Sync is a driver setting, so it rides on the ENVIRONMENT ─────────
        // The renderer has no vsync flag; the GL driver does. `env` prepends the
        // assignments to the process, covering both stacks — Mesa's vblank_mode=3
        // (always sync) and NVIDIA's __GL_SYNC_TO_VBLANK=1. Off: no env at all,
        // so the driver keeps its own default.
        const vsyncEnv = Config.wpeVsync
            ? "vblank_mode=3 __GL_SYNC_TO_VBLANK=1 "
            : ""

        return ["setsid", "--fork", "bash", "-c",
                'mkdir -p "' + root.stillsDir + '" 2>/dev/null; '
                + 'exec env ' + vsyncEnv + '"$0" "$@" > ' + '"' + root.logFile + '"' + " 2>&1",
                "linux-wallpaperengine"].concat(args)
    }

    // ══ Scenes per workspace ══════════════════════════════════════════════════
    // A workspace's own wallpaper can be a scene (Config.wallWorkspaces "scene:<id>",
    // services/Wallpaper). services/WorkspaceTheme sets `workspaceScreens` — screen →
    // the scene its ACTIVE workspace asks for, or "" when that workspace's own is a
    // picture (no scene on that screen); a screen not listed follows the shared
    // wallpaper. `effective()` is then what each screen should play
    // (workspacetheme.js effectiveScenes, `bun scripts/test-workspacetheme.js`).
    //
    // The renderer has no IPC, so a different map is a RELAUNCH — through the same
    // crossfade an apply uses (the old process keeps playing until the new one has
    // mapped and faded in, then is let go by pid), `syncMs` after the last switch so
    // flicking through workspaces costs one. Never the shared palette: `_skipPaletteOnce`
    // (a workspace's colours are WorkspaceTheme's, in memory). Nothing starts while Game
    // Mode holds the wallpaper paused. WallpaperView keeps a picture (the scene's still)
    // on a screen until the renderer really covers it (`coversScreen`).
    //
    // The shared wallpaper counts as a scene when one was applied as THE wallpaper —
    // `Config.wpeAutoStart`, which an image apply turns off — so a scene started by
    // hand with "Start with the shell" off isn't the shared one; and nothing here
    // touches the renderer unless some workspace has (or just had) a scene or a
    // picture of its own (`_wsTouched`).
    property var workspaceScreens: ({})
    readonly property bool wsMode: Object.keys(root.workspaceScreens).length > 0
    readonly property bool sharedIsScene: Config.wpeAutoStart && (Config.wpeCurrent !== "" || (Config.wpeMonitors || []).length > 0)
    readonly property int syncMs: 450

    // ── The shared scene, in a window of its own ──────────────────────────────
    // The layer renderer hears the pointer only over a bare desktop (its mouse comes from
    // a wl_pointer on its own background surface), and only moves a scene whose author
    // switched camera parallax on — 3 of the 36 scenes installed here did. So the scene
    // applied as THE wallpaper plays from a window instead (services/ScenePreload), and
    // WallpaperView draws a live capture of it, panned by the shell's own pointer
    // parallax: any scene, anywhere on the desktop, the same switch as a workspace's scene.
    //
    //   windowShared   the scene that WOULD play this way ("" = layer renderer, as ever).
    //                  Kept under the water of a picture applied over it (Wallpaper's
    //                  _stopSceneOnLanding) until that lands, then stopped like any scene.
    //                  Held back by: Config.wpePreload off, the awww renderer (nothing
    //                  draws the capture), per-monitor overrides (those are the layer
    //                  renderer's spans), a missing scene, and Stop being pressed.
    //   windowPlanned  ...and nothing says it can't: the layer renderer then isn't started
    //                  for it (effective()), whether or not its window is up yet.
    //   windowDrawn    ...and its window is up and captured. Only now does the layer
    //                  renderer playing it (a shell reload mid-scene, a fallback that
    //                  recovered) let go, and `running` start to say yes.
    //
    // Sound: the shared scene's window is the one window that isn't silent (windowArgs).
    // Colours: a layer scene's ride its map; this one's start when its window has a frame
    // (_windowColoursDue), in the same two steps — the wave, then the plain kick.
    //
    // Falls back by itself: a scene that won't stay up in a window (ScenePreload.failed),
    // or a refused window rule (ruleBad), makes windowPlanned false and the layer renderer
    // takes the scene over through the ordinary workspace sync below.
    property bool _heldStopped: false      // Stop was pressed; the next apply clears it
    readonly property string windowShared:
        (Config.wpePreload && Config.wallShellRender && !root._heldStopped
         && (root.sharedIsScene || (Wallpaper._stopSceneOnLanding > 0 && Config.wpeCurrent !== ""))
         && Config.wpeCurrent !== "" && (Config.wpeMonitors || []).length === 0
         && root.itemFor(Config.wpeCurrent) !== null && root.blocker() === "")
        ? Config.wpeCurrent : ""
    readonly property bool windowPlanned:
        root.windowShared !== "" && !ScenePreload.failed[root.windowShared] && !ScenePreload.ruleBad
    readonly property bool windowDrawn:
        root.windowPlanned && ScenePreload.usable(root.windowShared)
        && ScenePreload.windows[root.windowShared] !== undefined

    // The shared scene as seen from one screen: Config.wpeTarget pins a scene to one
    // screen, and the others keep their picture (a pin to an unplugged screen resets to all,
    // as targetScreens() does).
    function windowSceneOn(screenName) {
        if (root.windowShared === "") return ""
        const t = Config.wpeTarget
        return (t === "" || t === screenName || root.screenNames().indexOf(t) < 0) ? root.windowShared : ""
    }

    onWindowPlannedChanged: { root._wsTouched = true; wsSync.restart() }
    onWindowDrawnChanged:   { root._wsTouched = true; wsSync.restart(); root._windowColoursDue() }

    // The colours of the scene just applied, held until its window has a frame.
    property string _windowColoursFor: ""
    function _windowColoursDue() {
        const id = root._windowColoursFor
        if (id === "" || ScenePreload.windows[id] === undefined) return
        root._windowColoursFor = ""
        root._startColours(id)
        root._kickScenePalette(id)
    }
    Connections {
        target: ScenePreload
        function onWindowsChanged() { root._windowColoursDue() }
    }

    // apply() for a scene that plays from a window: ScenePreload already follows
    // Config.wpeCurrent, so there is no launch here — only the layer renderer's stop (the
    // workspace sync lets it go once the window is up), a restart for options that only
    // apply at launch, and the colours.
    function _applyWindow(id) {
        root.lastError = ""
        root._expectRunning = false
        root._windowColoursFor = id
        if (root._optionsDirty && ScenePreload.pids[id] !== undefined) ScenePreload.restart(id)
        root._optionsDirty = false
        root._wsTouched = true
        wsSync.restart()
        root._windowColoursDue()
    }

    property var _runningMap: ({})        // screen → scene id, read back from argv
    property var _launchScreens: []       // the screens the last launch covers (ws mode)
    property bool _wsTouched: false

    function _shared() {
        const per = {}
        for (const m of (Config.wpeMonitors || [])) for (const s of (m.screens || [])) per[s] = m.id
        const all = root.screenNames()
        const target = (Config.wpeTarget === "" || all.indexOf(Config.wpeTarget) < 0) ? all : [Config.wpeTarget]
        // The shared scene isn't the layer renderer's while it plays from a window.
        return { isScene: root.sharedIsScene && !root.windowPlanned, defaultId: Config.wpeCurrent, perScreen: per, target: target }
    }
    function effective() { return WsJs.effectiveScenes(root.screenNames(), root.workspaceScreens, root._shared()) }
    // The scene a screen should play ("" = a picture).
    function sceneOn(screenName) { return root.effective()[screenName] ?? "" }
    // Is the renderer drawing on this screen now?
    function coversScreen(screenName) {
        if (!root._running) return false
        const keys = Object.keys(root._runningMap)
        return keys.length === 0 || keys.indexOf(screenName) >= 0
    }

    onWorkspaceScreensChanged: { if (root.wsMode) root._wsTouched = true; wsSync.restart() }
    Connections {
        target: Gamemode
        function onWallpaperPausedChanged() { if (!Gamemode.wallpaperPaused) wsSync.restart() }
    }
    Timer {
        id: wsSync
        interval: root.syncMs
        onTriggered: root._syncWorkspaces()
    }
    function _syncWorkspaces() {
        if (!root._wsTouched) return
        if (Gamemode.wallpaperPaused || !root._runProbed) return
        if (root.busy) { wsSync.restart(); return }
        if (root.blocker() !== "") return
        const eff = root.effective()
        const want = WsJs.sceneKey(eff)
        // What argv will name: a preset with no texture folder of its own runs as its
        // base (see _parseRunning), so compare in argv's terms or every switch relaunches.
        const asArgv = {}
        for (const k in eff) {
            const it = root.itemFor(eff[k])
            asArgv[k] = it && !it.texdir && it.base ? it.base : eff[k]
        }
        if (!root.wsMode) root._wsTouched = false
        if (want === "") {
            // Nothing left for the layer renderer — but a scene on its way to a window
            // keeps playing from here until the window has a frame to take over from.
            if (root._running && (!root.windowPlanned || root.windowDrawn)) root._stopLayer()
            return
        }
        if (root._running && WsJs.sceneKey(asArgv) === WsJs.sceneKey(root._runningMap)) return
        root._relaunch()
    }

    // apply()'s crossfade without touching Config or the shared palette.
    function _relaunch() {
        root.lastError = ""
        root._skipPaletteOnce = true
        root._pendingId = root.sharedIsScene ? Config.wpeCurrent : ""
        root._pendingStart = true
        root._expectRunning = false
        root._particlesRetryUsed = false
        root._particlesAutoDisabledFor = ""
        watchdogTimer.stop()
        root._phase = "starting"
        snapProc.command = ["pgrep", "-f", root._procPattern]
        snapProc._pids = []
        snapProc.running = true
    }

    // The screens the scene should render on. "" = all named screens; a pinned
    // name = just that one, unless it has been unplugged since — in which case the
    // pref is reset and every screen renders, rather than the wallpaper silently
    // landing on a monitor that no longer exists (the wallTarget lesson).
    function targetScreens() {
        const all = root.screenNames()
        if (Config.wpeTarget === "") return all
        if (all.indexOf(Config.wpeTarget) !== -1) return [Config.wpeTarget]
        Config.wpeTarget = ""
        return all
    }

    function screenNames() {
        const out = []
        for (const s of Quickshell.screens)
            if (s.name && s.name !== "") out.push(s.name)
        return out
    }

    // ── Per-monitor scene assignment ──────────────────────────────────────────
    // Config.wpeMonitors is a plain array the four functions below rewrite as a
    // whole (QML's change notification is on the property, not on mutations
    // inside it) — never mutated in place. Editing while a scene is already
    // running only marks it dirty (see the Connections block above); nothing
    // restarts until Refresh, same as every other launch-arg change.
    //
    // Which scene is CONFIGURED for a screen, or "" for "plays the default".
    function monitorFor(screenName) {
        const hit = (Config.wpeMonitors || []).find(m => m.screens.indexOf(screenName) !== -1)
        return hit ? hit.id : ""
    }

    // Drops screenName out of whatever entry currently claims it (splitting a
    // span if that's what it was part of), then gives it its own single-screen
    // entry. Mirrors apply()'s autostart-on-pick behaviour: assigning a scene
    // means it should come back on login.
    function assignMonitor(screenName, id) {
        if (!screenName || !id) return
        let list = (Config.wpeMonitors || [])
            .map(m => ({ screens: m.screens.filter(s => s !== screenName),
                         id: m.id, scaling: m.scaling, clamp: m.clamp }))
            .filter(m => m.screens.length > 0)
        list.push({ screens: [screenName], id: id, scaling: "default", clamp: "clamp" })
        Config.wpeMonitors = list
        Config.wpeAutoStart = true
    }

    // Back to "plays the default scene".
    function unassignMonitor(screenName) {
        Config.wpeMonitors = (Config.wpeMonitors || [])
            .map(m => ({ screens: m.screens.filter(s => s !== screenName),
                         id: m.id, scaling: m.scaling, clamp: m.clamp }))
            .filter(m => m.screens.length > 0)
    }

    // One scene stretched across 2+ screens as a single --screen-span, replacing
    // whatever those screens were individually assigned before.
    function spanMonitors(screenNames, id) {
        if (!screenNames || screenNames.length < 2 || !id) return
        let list = (Config.wpeMonitors || [])
            .map(m => ({ screens: m.screens.filter(s => screenNames.indexOf(s) === -1),
                         id: m.id, scaling: m.scaling, clamp: m.clamp }))
            .filter(m => m.screens.length > 0)
        list.push({ screens: screenNames.slice(), id: id, scaling: "default", clamp: "clamp" })
        Config.wpeMonitors = list
        Config.wpeAutoStart = true
    }

    // Scaling/clamp for whichever entry currently covers screenName — a no-op if
    // that screen isn't overridden (the default assignment's mode is
    // Config.wpeScaling/wpeClamp instead, set directly).
    function setMonitorMode(screenName, scaling, clamp) {
        Config.wpeMonitors = (Config.wpeMonitors || []).map(m =>
            m.screens.indexOf(screenName) !== -1
                ? { screens: m.screens, id: m.id, scaling: scaling, clamp: clamp }
                : m)
    }

    // ── Removing a workshop wallpaper from disk ───────────────────────────────
    // What this CAN'T do is unsubscribe — that's a Steam-account action with no
    // local API (appworkshop_431960.acf lists INSTALLED items only; the subscription
    // list lives on Steam's servers), and a deleted-but-still-subscribed item comes
    // back on Steam's next workshop sync. So removal also opens the item's workshop
    // page, where Unsubscribe is one click; the UI says so rather than letting the
    // reappearance read as a bug.
    //
    // removeAndUnsubscribe() is the one entry the UI calls. It remembers the id in
    // Config.wpeUnsubPending, so a scene that Steam puts back is recognised
    // (stillSubscribed) and says so, instead of looking like the delete failed.
    // The list is only a hint — nothing reads it but that check — so it is capped,
    // never pruned on a timer, and cleared per id when the scene is applied.
    readonly property bool removing: rmProc.running

    function removeAndUnsubscribe(id) { root.removeAndUnsubscribeMany([id]) }

    // Up to three items get their own Workshop page; more than that would be a wall of
    // tabs, so the subscribed-items list opens once instead and the user unsubscribes
    // there.
    function removeAndUnsubscribeMany(ids) {
        const ok = (ids || []).filter(id => /^[0-9]+$/.test(id))
        if (ok.length === 0 || rmProc.running) return
        Config.wpeUnsubPending = (Config.wpeUnsubPending || [])
            .filter(x => ok.indexOf(x) === -1).concat(ok).slice(-200)
        if (ok.length <= 3) ok.forEach(id => root.openWorkshop(id))
        else                root._openUrl("https://steamcommunity.com/my/myworkshopfiles/"
                                          + "?appid=431960&browsefilter=mysubscriptions")
        root.removeMany(ok)
    }

    // Deleted earlier, asked to unsubscribe, and installed again: Steam still has the
    // subscription. Only meaningful after a rescan, which the panels do on open.
    function stillSubscribed(id) {
        return (Config.wpeUnsubPending || []).indexOf(id) !== -1 && root.itemFor(id) !== null
    }

    function _forgetUnsub(id) {
        const cur = Config.wpeUnsubPending || []
        if (cur.indexOf(id) !== -1) Config.wpeUnsubPending = cur.filter(x => x !== id)
    }

    function remove(id) { root.removeMany([id]) }

    function removeMany(ids) {
        // Each id becomes part of an `rm -rf` path, so it is validated to be a
        // bare workshop id — digits, nothing else — no matter what the caller
        // passes. A path fragment smuggled in here would be catastrophic.
        ids = (ids || []).filter(id => /^[0-9]+$/.test(id))
        if (ids.length === 0 || rmProc.running) return

        // Removing the scene that's on screen — the default OR any monitor's
        // override — stops the renderer first, or it keeps painting from open
        // file handles while the files vanish.
        const playingHere = root.running && ids.some(id => root.current === id
            || Object.keys(root._runningMonitors).some(s => root._runningMonitors[s] === id))
        if (playingHere) root.stop()
        if (ids.indexOf(Config.wpeCurrent) !== -1) Config.wpeCurrent = ""
        // A deleted scene must stop being requested, not just stop playing —
        // otherwise the next apply/autostart asks for files that no longer exist.
        if ((Config.wpeMonitors || []).some(m => ids.indexOf(m.id) !== -1))
            Config.wpeMonitors = (Config.wpeMonitors || []).filter(m => ids.indexOf(m.id) === -1)

        rmProc.command = ["rm", "-rf"].concat(ids.map(id => root.workshopDir + "/" + id))
        rmProc.running = true
    }

    Process {
        id: rmProc
        onExited: function(code) { root.rescan() }
    }

    function openWorkshop(id) {
        if (!/^[0-9]+$/.test(id)) return
        root._openUrl("https://steamcommunity.com/sharedfiles/filedetails/?id=" + id)
    }

    // Inside the Steam client when it is running — that is where the user is signed
    // in, which a default browser may not be — else in the browser. `pgrep -x steam`
    // rather than a bare steam:// URL, which would LAUNCH Steam just to show a page.
    // The URL rides as $1, never spliced into the script.
    function _openUrl(url) {
        Quickshell.execDetached(["sh", "-c",
            'pgrep -x steam >/dev/null && exec xdg-open "steam://openurl/$1"; exec xdg-open "$1"',
            "sh", url])
    }

    // The Workshop's front page for Wallpaper Engine — where new scenes come from.
    function openWorkshopHub() {
        Quickshell.execDetached(["xdg-open",
            "https://steamcommunity.com/app/431960/workshop/"])
    }
}
