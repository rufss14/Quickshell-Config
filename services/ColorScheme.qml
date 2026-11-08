pragma Singleton
import Quickshell
import "../config"
import Quickshell.Io
import QtQuick
import "palette.js" as Palette

// ── ColorScheme ───────────────────────────────────────────────────────────────
// The palette editor's logic: overrides, saved schemes, and pushing a palette out.
//
// ── The bug this exists to fix ────────────────────────────────────────────────
// `theming/pywal-overrides.json` was READ by the wallpaper pipeline and WRITTEN BY
// NOTHING. The directory did not even exist. So:
//
//   1. You edit a colour  -> the panel wrote ~/.cache/wal/colors.json directly. Looks right.
//   2. You change wallpaper -> `wal -i` regenerates colors.json from scratch. Edit is gone.
//   3. The pipeline merges pywal-overrides.json... which never existed, so it skips.
//
// A consumer with no producer. That is the whole of "the overrides aren't working". This
// service is the missing writer: a pinned colour goes into the overrides file, which the
// pipeline already merges on every single apply, so it survives wallpaper changes until
// it's explicitly cleared.
//
// ── The lock decides whether a scheme persists ───────────────────────────────
// "Locked" is not a setting: it is whether any colour is pinned (`locked`, from the
// overrides file). Pinning a slot, or applying a scheme WHILE locked, keeps the colours
// through wallpaper changes until "Release all". Applying a scheme while unlocked is
// temporary — it becomes the live palette, the next wallpaper replaces it — and the
// header's lock button turns "what is showing" into pins (lock()) or hands the colours
// back to the wallpaper (releaseAll()).
//
// History: schemes persisted always (applied = pinned all 18 slots), because a temporary
// scheme was thrown away by the next wallpaper change. That made every apply a lock the
// user then had to undo; it is now their choice, one click after applying.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property string shellDir:   Quickshell.shellDir
    readonly property string schemesDir: root.shellDir + "/colorschemes"
    readonly property string overridesPath: root.shellDir + "/theming/pywal-overrides.json"
    readonly property string walJson: Quickshell.env("HOME") + "/.cache/wal/colors.json"

    // ── Live palette ──────────────────────────────────────────────────────────
    // Read from the Colors singleton rather than re-parsing colors.json: it already watches
    // that file and every widget in the shell is bound to it, so a second reader would be a
    // second source of truth that goes stale.
    //
    // `fileData`, not `data`: this is what the EDITOR edits, and it must be the palette on
    // disk. `data` can be wearing a transient album-cover overlay, and seeding the editor
    // from that would mean a pin taken while music was playing silently made the current
    // track's colour permanent.
    readonly property var live: Colors.fileData ?? ({})

    // ── Overrides ─────────────────────────────────────────────────────────────
    // { special: { background, foreground, cursor }, colors: { color0..color15 } }
    readonly property var  overrides: root._overrides
    readonly property int  overrideCount: {
        let n = 0
        for (const section of ["special", "colors"])
            n += Object.keys(root._overrides[section] ?? ({})).length
        return n
    }
    property var _overrides: ({ special: ({}), colors: ({}) })
    // Colours are held against the wallpaper. Derived, so it can never disagree with
    // the file: an editor pin lights the lock just like a locked scheme does.
    readonly property bool locked: root.overrideCount > 0

    // ── "Already there" ───────────────────────────────────────────────────────
    // A refresh (rebuild from the wallpaper, or the rebuild after releasing the lock)
    // would produce exactly what is on screen, so it doesn't run. What it would produce:
    //   · the pins, over
    //   · the palette saved for this wallpaper/scene (apply-wallpaper.sh restores it
    //     instead of extracting), over
    //   · nothing we can predict — a pywal extraction. Not guessed at: without every
    //     slot covered by the two above, a refresh runs.
    // Compared to the palette ON DISK. Pinned alone isn't enough: AlbumScheme's
    // system-wide mode writes the album's colours into colors.json, and regenerate() is
    // how the real look comes back.
    readonly property var _slots: ["background", "foreground"]
        .concat(Array.from({ length: 16 }, (_, i) => "color" + i))
    readonly property bool settled: {
        const want = Object.assign({}, root._flat(root._savedPalette ?? ({})),
                                   root._flat(root._overrides))
        return root._slots.every(sl => want[sl] !== undefined)
            && root._unchanged(want, false)
    }

    // { special, colors } → { slot: hex }, without the cursor (it follows foreground).
    function _flat(p) {
        const out = ({})
        for (const k in (p.special ?? ({}))) if (k !== "cursor") out[k] = p.special[k]
        for (const k in (p.colors ?? ({})))  out[k] = p.colors[k]
        return out
    }

    // Would `map` change nothing? Each slot already showing that colour and, when
    // `pinned`, already pinned to it.
    function _unchanged(map, pinned) {
        const hex = v => String(v ?? "").toLowerCase()
        for (const slot in map) {
            const sec = root._sectionOf(slot)
            if (pinned !== false && hex((root._overrides[sec] ?? ({}))[slot]) !== hex(map[slot]))
                return false
            if (hex((root.live[sec] ?? ({}))[slot]) !== hex(map[slot])) return false
        }
        return true
    }

    FileView {
        id: overridesFile
        path: root.overridesPath
        watchChanges: true
        onFileChanged: overridesFile.reload()
        onLoaded: {
            // ── Don't let the watcher clobber our own newer state ─────────────
            // This watches a file WE write, so every save comes back as a change event.
            // Measured: pinning two slots in one tick left memory correct (2 entries) and
            // then 900ms later the watcher reloaded the FIRST write — which had only one —
            // and overwrote the newer value. The second pin appeared to have been dropped.
            //
            // While a write is in flight or pending, memory is by definition ahead of the
            // file, so the file has nothing to tell us. Only adopt it when we're idle,
            // which is exactly the case where the change came from somewhere else (an
            // external edit, or a fresh load at startup).
            if (overridesWriter.running || root._overridesDirty) return

            try {
                const d = JSON.parse(overridesFile.text())
                root._overrides = ({ special: d.special ?? ({}), colors: d.colors ?? ({}) })
            } catch (e) {
                console.warn("[ColorScheme] overrides file is not valid JSON:", e)
            }
        }
        // A missing file is the normal state on a fresh install, not an error worth logging.
        onLoadFailed: root._overrides = ({ special: ({}), colors: ({}) })
    }

    function isOverridden(slot) {
        const section = root._sectionOf(slot)
        return (root._overrides[section] ?? ({}))[slot] !== undefined
    }

    function _sectionOf(slot) {
        return slot.indexOf("color") === 0 ? "colors" : "special"
    }

    // Pin a slot to a colour. Written through the same path as clearing, so the file can
    // never be half-updated by two different writers.
    function pin(slot, hex) {
        const next = ({ special: Object.assign({}, root._overrides.special),
                        colors:  Object.assign({}, root._overrides.colors) })
        next[root._sectionOf(slot)][slot] = hex
        root._writeOverrides(next)
    }

    function unpin(slot) {
        const next = ({ special: Object.assign({}, root._overrides.special),
                        colors:  Object.assign({}, root._overrides.colors) })
        delete next[root._sectionOf(slot)][slot]
        root._writeOverrides(next)
    }

    // Pin several slots as ONE write. The editor stages edits and commits them together,
    // and calling pin() in a loop would issue a write per slot — the coalescing below
    // would collapse them correctly, but only after starting a process for each.
    function pinMany(map) {
        const next = ({ special: Object.assign({}, root._overrides.special),
                        colors:  Object.assign({}, root._overrides.colors) })
        for (const slot in map) next[root._sectionOf(slot)][slot] = map[slot]
        root._writeOverrides(next)
    }

    // ── Releasing has to REGENERATE, not just reload ──────────────────────────
    // Clearing the overrides file is only half of it. `reload-theme.sh` merges overrides
    // into the EXISTING colors.json — and colors.json still holds the scheme, because
    // applying the scheme is what put it there. Merging an empty override set over the
    // scheme leaves the scheme exactly where it was, so releasing appeared to do nothing.
    //
    // The wallpaper's own colours only come back by re-running pywal against the current
    // wallpaper, which is what `regenerate()` does.
    //
    // Sequenced, not fired together: the overrides write is asynchronous, and regenerating
    // before it lands would merge the OLD overrides straight back in and undo the release.
    function releaseAll() {
        root._regenAfterWrite = true
        root._writeOverrides(({ special: ({}), colors: ({}) }))
    }

    // The lock button: hold what is on screen now (nothing changes visually, so no
    // reload), or hand everything back to the wallpaper.
    function toggleLock() {
        if (root.locked) { root.releaseAll(); return }
        const flat = root._flat(root.live)
        if (Object.keys(flat).length > 0) root.pinMany(flat)
    }

    // Releasing one slot has the same problem — colors.json still carries the pinned value.
    function release(slot) {
        root._regenAfterWrite = true
        const next = ({ special: Object.assign({}, root._overrides.special),
                        colors:  Object.assign({}, root._overrides.colors) })
        delete next[root._sectionOf(slot)][slot]
        root._writeOverrides(next)
    }

    property bool _regenAfterWrite: false

    // Kept for callers that only want the file changed without a rebuild.
    function clearOverrides() {
        root._writeOverrides(({ special: ({}), colors: ({}) }))
    }

    // Written via a process rather than FileView.setText() because the directory may not
    // exist yet — `theming/` genuinely did not, which is part of why this never worked.
    Process {
        id: overridesWriter
        running: false
        property string payload: ""
        environment: ({ "CS_OVERRIDES": overridesWriter.payload })
        command: ["bash", "-c",
            'mkdir -p "$(dirname "$1")" && printf %s "$CS_OVERRIDES" > "$1"',
            "_", root.overridesPath]
        onExited: function(code) {
            if (code !== 0) {
                root.runner.notify("Could not save overrides",
                                   "Writing " + root.overridesPath + " failed.", "critical")
                root._overridesDirty = false
                // Cleared here too, or a failed release leaves the flag armed and the NEXT
                // successful write — a pin, say — would regenerate from the wallpaper and
                // throw away the edit that just succeeded.
                root._regenAfterWrite = false
                return
            }
            // Something changed while we were writing — write again, with whatever the
            // state is NOW. See _writeOverrides.
            if (root._overridesDirty) {
                root._overridesDirty = false
                root._flushOverrides()
                return
            }
            overridesFile.reload()

            // The release path waits for this moment: the file is now genuinely on disk, so
            // a rebuild will read the cleared set rather than the one we just replaced.
            if (root._regenAfterWrite) {
                root._regenAfterWrite = false
                root.regenerate()
            }
        }
    }

    // Set when a write is requested while one is already in flight.
    property bool _overridesDirty: false

    // ── Coalesced, not dropped ────────────────────────────────────────────────
    // The first version bailed out with `if (overridesWriter.running) return`, which
    // SILENTLY LOST the write. Measured: pinning two slots in the same tick produced an
    // overrideCount of 1 — the second pin vanished. Pinning a background and a foreground
    // in quick succession is completely ordinary, so this was a real data-loss path.
    //
    // Coalescing rather than queueing is right here because `_overrides` is the whole
    // state, not a delta: if three writes pile up, the last one already contains the other
    // two, so replaying them in order would be pointless work ending at the same file.
    function _writeOverrides(obj) {
        root._overrides = obj                      // optimistic, so the UI responds at once
        if (overridesWriter.running) {
            root._overridesDirty = true
            return
        }
        root._flushOverrides()
    }

    function _flushOverrides() {
        overridesWriter.payload = JSON.stringify(root._overrides, null, 2)
        overridesWriter.running = false
        overridesWriter.running = true
    }

    // ── Applying ──────────────────────────────────────────────────────────────
    // One runner, shared shape with the wallpaper gallery.
    readonly property ThemeRunner runner: runnerInstance
    ThemeRunner {
        id: runnerInstance
        appName: "Colors"
        icon: "Palette"
        onFinished: function(code) {
            if (code === 0 && runnerInstance.failedCount === 0)
                runnerInstance.notify("Colours applied",
                                      (runnerInstance.label || "The palette") + " is live.", "low")
            else if (code === 0)
                runnerInstance.notify("Applied, partly",
                                      runnerInstance.failedCount + " app"
                                      + (runnerInstance.failedCount !== 1 ? "s" : "")
                                      + " could not be recoloured.", "normal")
            else
                runnerInstance.notify("Apply failed",
                                      "Nothing was changed. Open the colours panel for details.",
                                      "critical")
        }
    }

    readonly property bool busy: runnerInstance.running || schemeWriter.running

    // Every run here changes colours and nothing else, so each arrives as the
    // colours-only wave: the shell's old look eaten away from the bottom middle,
    // glowing in the new accent (services/WallWave.qml, via ThemeRunner). No water —
    // the picture isn't changing.
    readonly property var _wave: ({ image: "", recolor: true })

    // Push whatever is in colors.json out to every app. Used after pinning, since the
    // pipeline merges overrides itself — there is nothing else to write.
    function reload(label) {
        runnerInstance.run(["bash", Quickshell.shellPath("scripts/reload-theme.sh")],
                           label ?? "Colour change", root._wave)
    }

    // ── Applying a scheme: pinned only while locked ───────────────────────────
    // Locked: a scheme is an edit of all 18 slots, so it goes through the overrides file
    // like any pinned colour (reload-theme.sh merges them) and survives wallpaper changes.
    // Unlocked: nothing is written to the overrides file. The palette goes to a staging
    // file and reload-theme.sh `--palette` commits it as the live colors.json, so the
    // next wallpaper's extraction replaces it. Staged in a file, not live colors.json
    // directly, so the shell still recolours on the wave rather than snapping.
    function applyPalette(paletteObj, label) {
        if (runnerInstance.running || schemeWriter.running) return

        if (root.locked) {
            const flat = root._flat(paletteObj)
            if (root._unchanged(flat)) return           // the locked scheme, re-applied: nothing to do

            root.pinMany(flat)
            root.reload(label ?? "Colour scheme")
            return
        }

        root._schemeLabel = label ?? "Colour scheme"
        schemeWriter.payload = JSON.stringify({ special: paletteObj.special ?? ({}),
                                                colors:  paletteObj.colors  ?? ({}) })
        schemeWriter.running = true
    }

    property string _schemeLabel: ""
    readonly property string stagedPalettePath: Quickshell.cachePath("scheme-palette.json")

    // The payload goes over the environment (as AlbumScheme's does), not argv.
    Process {
        id: schemeWriter
        running: false
        property string payload: ""
        environment: ({ "CS_SCHEME": schemeWriter.payload })
        command: ["bash", "-c", 'mkdir -p "$(dirname "$1")" && printf %s "$CS_SCHEME" > "$1"',
                  "_", root.stagedPalettePath]
        onExited: function(code) {
            if (code !== 0) {
                root.runner.notify("Could not apply the scheme",
                                   "Writing " + root.stagedPalettePath + " failed.", "critical")
                return
            }
            runnerInstance.run(["bash", Quickshell.shellPath("scripts/reload-theme.sh"),
                                "--palette", root.stagedPalettePath],
                               root._schemeLabel, root._wave)
        }
    }

    // Rebuild from the current wallpaper. Goes through the wallpaper script so the
    // per-wallpaper corrections and the override merge both still happen — the old version
    // ran `wal -i` itself and skipped the overrides entirely, which silently discarded
    // exactly the edits this panel exists to make.
    // It used to rebuild the wallpaper's path in shell — reading the marker file itself
    // and joining it onto a hardcoded `$HOME/wallpapers/walls`, with `pywallpaper.jpg`
    // as the fallback. That was a third copy of a path the Wallpaper service already
    // resolves, so it broke the moment the library moved, and it broke silently: both
    // candidates simply don't exist on an install that has no ~/wallpapers, and the
    // script was then handed a path to nothing.
    //
    // `Wallpaper.currentPath` is the answer to the same question, resolved once, and
    // it is legitimately "" while a scene is driving the desktop (there is no still
    // image to rebuild from). That case now REPORTS instead of running the pipeline
    // against a missing file.
    function regenerate() {
        if (root.settled) return
        if (runnerInstance.running) return

        // A scene owns the desktop — rebuild from ITS preview, through the same route
        // the theme-mode switch uses. (Restores a saved scene palette if there is one;
        // "Use native" in the panel is how you drop that.) A scene gamemode has
        // paused still counts: it's the real subject, and repalette() already knows
        // how to reach its preview without the process running. wallpaperPaused
        // alone doesn't prove there IS a scene though — a plain static-wallpaper
        // session holds the card too now, and Config.wpeCurrent is "" for
        // anyone who's never touched Wallpaper Engine.
        const pausedSceneId = Gamemode.wallpaperPaused ? Config.wpeCurrent : ""
        if (WallpaperEngine.running || pausedSceneId !== "") {
            if (!Config.wpeScenePalette) {
                runnerInstance.notify("Scene colours are off",
                                      "Turn on “Scene colours” in the wallpaper settings "
                                    + "to theme from the scene.", "normal")
                return
            }
            WallpaperEngine.repalette()
            return
        }

        const wall = Wallpaper.currentPath
        if (!wall) {
            runnerInstance.notify("Nothing to rebuild from",
                                  "No still wallpaper is set, or the library is empty.", "normal")
            return
        }

        // `--palette-only`: the picture is already on screen and re-setting it is
        // redundant work. This still runs the whole palette pipeline, so the
        // per-wallpaper corrections and the override merge that this function exists
        // to preserve both happen exactly as before.
        //
        // The mode flags travel too. Without them the script defaults to dark, so
        // "Rebuild from wallpaper" in light mode used to quietly flip the shell to
        // dark — the one button whose entire job is to not change anything else.
        runnerInstance.run(["bash", Quickshell.shellPath("scripts/apply-wallpaper.sh"),
                            "--palette-only"]
                           .concat(Wallpaper.modeFlags()).concat([wall]),
                           "Rebuild from wallpaper", root._wave)
    }

    // Recolour the shell from a picture WITHOUT making it the wallpaper — what
    // Gamemode.queueImage() calls so a fresh pick's colours land right away
    // even though the picture itself stays held back behind the takeover card
    // until gamemode ends. Own runner (this file's, not Wallpaper's `apply()`
    // pipeline), so it can never contend with the real apply Gamemode fires
    // later when the hold lets go.
    function regenerateFrom(path) {
        if (!Config.wallTheming || runnerInstance.running || !path) return
        runnerInstance.run(["bash", Quickshell.shellPath("scripts/apply-wallpaper.sh"),
                            "--palette-only"]
                           .concat(Wallpaper.modeFlags()).concat([path]),
                           "Recolouring", root._wave)
    }

    // ── Saved schemes ─────────────────────────────────────────────────────────
    // [{ name, mtime, palette, variants }] — the palette rides along so the library can show each
    // scheme's real colours without a second read per chip; `mtime` (epoch seconds, last saved)
    // is what the library's "Recent" sort orders by. `palette` is the file's top level (the primary
    // variant, as an old reader would see it); `variants` is { dark, light }, each a palette or null —
    // what the library and the loader actually use (palette.js unpackScheme: a legacy file holds ONE).
    readonly property var  presets: root._presets
    readonly property bool listing: presetList.running
    property var _presets: []

    function refreshPresets() {
        if (presetList.running) return
        presetList._rows = []
        presetList.running = true
    }

    Process {
        id: presetList
        running: true
        // ── Names AND palettes in one pass ────────────────────────────────────
        // The library shows each scheme's actual colours, so listing names alone would
        // mean a second read per scheme the moment the drawer opened. One python call
        // emits `name<TAB>{compact json}` per line — a scheme is ~700 bytes, so reading
        // all of them costs less than the process spawns would.
        command: ["python3", "-c",
            "import json,os,sys\n"
          + "d=sys.argv[1]\n"
          + "os.makedirs(d, exist_ok=True)\n"
          + "for f in sorted(os.listdir(d)):\n"
          + "    if not f.endswith('.json'): continue\n"
          + "    try:\n"
          + "        p=json.load(open(os.path.join(d,f)))\n"
          + "    except Exception:\n"
          + "        continue\n"
          + "    print(f[:-5] + '\\t' + str(int(os.path.getmtime(os.path.join(d,f)))) + '\\t' + json.dumps(p, separators=(',',':')))\n",
            root.schemesDir]

        property var _rows: []
        stdout: SplitParser {
            onRead: function(line) {
                const tab = line.indexOf("\t")
                const tab2 = line.indexOf("\t", tab + 1)
                if (tab < 0 || tab2 < 0) return
                const name = line.substring(0, tab)
                try {
                    const obj = JSON.parse(line.substring(tab2 + 1))
                    presetList._rows = presetList._rows.concat([
                        { name: name,
                          mtime: parseInt(line.substring(tab + 1, tab2)) || 0,
                          palette: obj,
                          variants: Palette.unpackScheme(obj) }])
                } catch (e) {
                    // A damaged scheme is skipped rather than breaking the whole list.
                    console.warn("[ColorScheme] skipping unreadable scheme:", name)
                }
            }
        }
        onExited: function(code) {
            const rows = presetList._rows.slice()
            rows.sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()))
            root._presets = rows
            presetList._rows = []
            root.presetsReady = true
        }
    }

    // True once the library has been listed at least once. A workspace's scheme is looked up BY NAME
    // in `presets`, which is empty until then — and "not there yet" must not read as "deleted", or
    // every screen would wear the wallpaper's colours for the moment it takes to list them.
    property bool presetsReady: false

    // ══ A scheme per workspace ════════════════════════════════════════════════
    // `Config.schemeWorkspaces` { "3": "Name" }: those workspaces wear that saved scheme — the shell on
    // the screen showing one, and the apps on it — through services/WorkspaceTheme, in memory, as a
    // workspace's own wallpaper does. A scheme is held BY NAME, so saving over it updates every
    // workspace wearing it; one that is deleted or renamed is just not worn (the wallpaper's colours
    // show again). No theming pipeline runs and nothing is written to colors.json or the overrides.
    //
    // Chosen like a wallpaper's: right-click a library card → `pending` → the library folds into the
    // workspace picker → Apply → `assign`. Left-click still loads it into the editor.
    property string pending: ""
    readonly property bool perWorkspace: Object.keys(Config.schemeWorkspaces).length > 0
    // The workspaces wearing a scheme of their own, sorted.
    readonly property var marked: Object.keys(Config.schemeWorkspaces).map(Number)
        .filter(n => n > 0).sort((a, b) => a - b)

    // The palette `name` is worn as in the shell's current mode (a scheme with only the other mode
    // shows that one — the same rule as loading it), or null when there is no such scheme.
    function schemePalette(name) {
        const p = root._presets.find(x => x.name === name)
        return p ? (Palette.pickVariant(p.variants ?? Palette.unpackScheme(p.palette), Config.themeMode).palette ?? null) : null
    }
    // What workspace `ws` wears: { name, palette } — null when it has none, or its scheme is gone.
    function schemeFor(ws) {
        const name = Config.schemeWorkspaces[String(ws)] ?? ""
        const pal = name !== "" ? root.schemePalette(name) : null
        return pal ? { name: name, palette: pal } : null
    }
    // The workspaces wearing `name`.
    function workspacesOf(name) {
        return root.marked.filter(n => Config.schemeWorkspaces[String(n)] === name)
    }

    function choose(name) { if (root._presets.some(x => x.name === name)) root.pending = name }
    function cancelPick() { root.pending = "" }

    // The picker's Apply: `name` for these workspaces; the rest keep what they wear.
    function assign(name, list) {
        root.pending = ""
        const ws = []
        for (const v of list || []) {
            const n = Math.floor(Number(v))
            if (n > 0 && ws.indexOf(n) < 0) ws.push(n)
        }
        if (ws.length === 0 || !root._presets.some(x => x.name === name)) return
        // EVERY workspace is not ten exceptions, it is the shell's own scheme: ten entries would each outrank
        // the shell's palette, so nothing applied afterwards could show through (the Wallpaper picker's rule
        // for the same case). Applied as the shell's colours, with no per-workspace entries left.
        if (ws.length >= Wallpaper.pickable && ws.every(n => n <= Wallpaper.pickable)) {
            root.forgetAllWorkspaces()
            root.useScheme(root._presets.find(x => x.name === name))
            const pal = root.schemePalette(name)
            if (pal) root.applyPalette(pal, "Scheme · " + name)
            return
        }
        const m = Object.assign({}, Config.schemeWorkspaces)
        for (const n of ws) m[String(n)] = name
        Config.schemeWorkspaces = m
    }

    function forgetWorkspace(ws) {
        if (!(String(ws) in Config.schemeWorkspaces)) return
        const m = Object.assign({}, Config.schemeWorkspaces)
        delete m[String(ws)]
        Config.schemeWorkspaces = m
    }
    // A scheme renamed (or, with `to` "", deleted): its workspaces follow it (or are let go).
    function _renameWorkspaces(from, to) {
        if (!root.workspacesOf(from).length) return
        const m = {}
        for (const k in Config.schemeWorkspaces) {
            const v = Config.schemeWorkspaces[k]
            if (v !== from) m[k] = v
            else if (to !== "") m[k] = to
        }
        Config.schemeWorkspaces = m
    }
    function forgetAllWorkspaces() {
        if (root.perWorkspace) Config.schemeWorkspaces = ({})
    }
    // A deliberate Apply is for the whole shell, so workspaces with a scheme of their own are let go first —
    // they outrank the shell's palette, so otherwise the Apply would seem to do nothing. (The Wallpaper
    // service does the same for a gallery click.) A light/dark switch does not come through here.
    function releaseForApply() { root.forgetAllWorkspaces() }

    // ── Light / dark ──────────────────────────────────────────────────────────
    // The shell's mode is `Config.themeMode`; flipping it from anywhere — the colours panel, Settings ›
    // Appearance, the launcher's Theme action, `wallpaper theme` over IPC — goes through here. It sets
    // the mode and then re-derives the palette in it from the wallpaper, as it always did, UNLESS the
    // scheme the shell is wearing is a saved one that holds the other mode too: then THAT version is
    // applied, so a scheme you made in both stays itself when the mode changes.
    function currentPreset() { return root._presets.find(p => p.name === root._loadedName) ?? null }

    function switchMode(mode) {
        if (mode !== "light" && mode !== "dark") return
        if (Config.themeMode === mode) return
        const p = root.currentPreset()
        // "Wearing" = the version for the mode being LEFT is what is on screen; a scheme that was only
        // looked at in the editor must not be applied by a mode flip.
        const wearing = !!p && !!p.variants[Config.themeMode] && root._unchanged(root._flat(p.variants[Config.themeMode]), false)
        const next = p ? p.variants[mode] : null
        Config.themeMode = mode
        if (wearing && next) {
            root._loadedMode = mode
            root._loadedExact = true
            root.applyPalette(next, "Scheme · " + (mode === "light" ? "Light" : "Dark"))
        } else {
            Wallpaper.reapplyPalette()
        }
    }

    // ── Peek ──────────────────────────────────────────────────────────────────
    // Wears `palette` on the whole shell for as long as it is held (Colors.preview, a layer over
    // everything), and puts it all back the moment it is let go. In memory only: no process, no
    // file, nothing for a wallpaper change or the album to trip over.
    property bool peeking: false
    function peek(palette) {
        if (!palette) return
        Colors.fastEase()
        Colors.preview = palette
        root.peeking = true
    }
    function endPeek() {
        if (!root.peeking) return
        Colors.fastEase()
        Colors.preview = ({})
        root.peeking = false
    }

    // Names are sanitised to a safe set AND passed as an argument rather than interpolated
    // into the command — the old version built the path inside a shell string, so a name
    // with a quote in it wrote somewhere unintended.
    function sanitiseName(name) {
        return (name ?? "").trim().replace(/[^a-zA-Z0-9 _.-]/g, "")
    }

    // `variants` is { dark?, light? } — the palettes to write. A mode left out keeps what the scheme
    // already holds for it (so updating a scheme's light version never costs it its dark one); a plain
    // palette is read as the current mode's.
    function saveScheme(name, variants) {
        const n = root.sanitiseName(name)
        if (n === "") {
            runnerInstance.notify("Name required", "Give the scheme a name first.", "normal")
            return false
        }
        if (schemeSaver.running) return false
        if (variants && (variants.special || variants.colors)) {
            const one = ({})
            one[Config.themeMode === "light" ? "light" : "dark"] = variants
            variants = one
        }
        const had = root._presets.find(p => p.name === n)?.variants ?? ({ dark: null, light: null })
        const packed = Palette.packScheme({ dark:  variants?.dark  ?? had.dark,
                                            light: variants?.light ?? had.light })
        if (!packed) return false
        schemeSaver.payload = JSON.stringify(packed, null, 2)
        schemeSaver.sname = n
        schemeSaver.running = false
        schemeSaver.running = true
        return true
    }

    Process {
        id: schemeSaver
        running: false
        property string payload: ""
        property string sname: ""
        environment: ({ "CS_PAYLOAD": schemeSaver.payload })
        command: ["bash", "-c",
            'mkdir -p "$1" && printf %s "$CS_PAYLOAD" > "$1/$2.json"',
            "_", root.schemesDir, schemeSaver.sname]
        onExited: function(code) {
            if (code === 0) {
                runnerInstance.notify("Scheme saved", "“" + schemeSaver.sname + "” saved.", "low")
                root._loadedName = schemeSaver.sname   // you're now editing what you just saved
                // …and it now holds the mode you were in, whatever it held when it was loaded.
                root._loadedMode = Config.themeMode === "light" ? "light" : "dark"
                root._loadedExact = true
                root.refreshPresets()
            } else {
                runnerInstance.notify("Save failed", "Check the name and permissions.", "critical")
            }
        }
    }

    function schemeExists(name) {
        const n = root.sanitiseName(name)
        return root._presets.some(p => p.name === n)
    }

    // ── Loading a saved scheme ────────────────────────────────────────────────
    readonly property var loadedScheme: root._loadedScheme
    property var _loadedScheme: null
    signal schemeLoaded(string name, var palette)

    // The library already holds every scheme's palette, so using one is instant and needs
    // no file read at all — loadScheme() below stays for anything addressing a scheme by
    // name alone.
    //
    // Picks the variant for the shell's current mode (palette.js pickVariant). A scheme that holds only
    // the OTHER mode loads that one — `loadedMode` says which, and `loadedExact` is false — and the
    // panel tells you, rather than the load being refused.
    property string _loadedMode: ""
    property bool   _loadedExact: true
    readonly property string loadedMode:  root._loadedMode
    readonly property bool   loadedExact: root._loadedExact
    function useScheme(preset) {
        if (!preset) return
        const pick = Palette.pickVariant(preset.variants ?? Palette.unpackScheme(preset.palette), Config.themeMode)
        if (!pick.palette) return
        root._loadedScheme = pick.palette
        root._loadedName = root.sanitiseName(preset.name)
        root._loadedMode = pick.mode
        root._loadedExact = pick.exact
        root.schemeLoaded(preset.name, pick.palette)
    }

    function loadScheme(name) {
        if (schemeReader.running) return
        schemeReader.sname = root.sanitiseName(name)
        schemeReader._buf = ""
        schemeReader.running = false
        schemeReader.running = true
    }

    Process {
        id: schemeReader
        running: false
        property string sname: ""
        property string _buf: ""
        command: ["cat", root.schemesDir + "/" + schemeReader.sname + ".json"]
        // Read whole rather than by line: JSON pretty-printed across 30 lines has to be
        // reassembled before it can be parsed.
        stdout: SplitParser {
            onRead: function(line) { schemeReader._buf += line + "\n" }
        }
        onExited: function(code) {
            if (code !== 0) {
                runnerInstance.notify("Could not open scheme",
                                      "“" + schemeReader.sname + "” could not be read.", "critical")
                return
            }
            try {
                const pick = Palette.pickVariant(Palette.unpackScheme(JSON.parse(schemeReader._buf)), Config.themeMode)
                if (!pick.palette) throw new Error("no palette in it")
                root._loadedScheme = pick.palette
                root._loadedName = schemeReader.sname
                root._loadedMode = pick.mode
                root._loadedExact = pick.exact
                root.schemeLoaded(schemeReader.sname, pick.palette)
            } catch (e) {
                runnerInstance.notify("Scheme is damaged",
                                      "“" + schemeReader.sname + "” is not valid JSON.", "critical")
            }
            schemeReader._buf = ""
        }
    }

    function deleteScheme(name) {
        if (schemeDeleter.running) return
        schemeDeleter.sname = root.sanitiseName(name)
        schemeDeleter.running = false
        schemeDeleter.running = true
    }

    Process {
        id: schemeDeleter
        running: false
        property string sname: ""
        command: ["rm", "-f", root.schemesDir + "/" + schemeDeleter.sname + ".json"]
        onExited: function(code) {
            if (code === 0) {
                if (root._loadedName === schemeDeleter.sname) root._loadedName = ""
                // A deleted scheme is no longer starred.
                Config.colorFavorites = Config.colorFavorites.filter(n => n !== schemeDeleter.sname)
                // …and its workspaces go back to what they showed.
                root._renameWorkspaces(schemeDeleter.sname, "")
                root.refreshPresets()
            } else {
                runnerInstance.notify("Delete failed",
                                      "“" + schemeDeleter.sname + "” is still there.", "critical")
            }
        }
    }

    // ── Renaming ──────────────────────────────────────────────────────────────
    // mv, not copy-then-delete: a crash mid-way can't leave two files or none.
    // `-n` refuses to clobber, so the name-taken check below is belt-and-braces.
    function renameScheme(oldName, newName) {
        const o = root.sanitiseName(oldName)
        const n = root.sanitiseName(newName)
        if (o === "" || n === "" || o === n) return false
        if (root._presets.some(p => p.name === n)) {
            runnerInstance.notify("Name taken", "“" + n + "” already exists.", "normal")
            return false
        }
        if (schemeRenamer.running) return false
        schemeRenamer.oldn = o
        schemeRenamer.newn = n
        schemeRenamer.running = false
        schemeRenamer.running = true
        return true
    }

    Process {
        id: schemeRenamer
        running: false
        property string oldn: ""
        property string newn: ""
        command: ["mv", "-n",
                  root.schemesDir + "/" + schemeRenamer.oldn + ".json",
                  root.schemesDir + "/" + schemeRenamer.newn + ".json"]
        onExited: function(code) {
            if (code === 0) {
                if (root._loadedName === schemeRenamer.oldn) root._loadedName = schemeRenamer.newn
                // The star goes with the scheme to its new name.
                Config.colorFavorites = Config.colorFavorites.map(n => n === schemeRenamer.oldn ? schemeRenamer.newn : n)
                root._renameWorkspaces(schemeRenamer.oldn, schemeRenamer.newn)
                root.refreshPresets()
            } else {
                runnerInstance.notify("Rename failed",
                                      "“" + schemeRenamer.oldn + "” is unchanged.", "critical")
            }
        }
    }

    // Which saved scheme the editor currently has loaded, "" for none. Set on
    // schemeLoaded; the panel shows an "Editing <name>" state and Save writes straight
    // back. Cleared by the panel when the user forks or edits away from it.
    property string _loadedName: ""
    readonly property string loadedName: root._loadedName
    function setLoadedName(n) { root._loadedName = n }

    // ══ Per-wallpaper palettes ═══════════════════════════════════════════════
    // A palette bound to ONE wallpaper (or scene) by KEY. `apply-wallpaper.sh`
    // checks `theming/wallpaper-palettes/<key>.json` before running pywal, so
    // returning to that wallpaper restores your colours instead of re-extracting.
    // Distinct from the overrides file — held colours that survive EVERY wallpaper
    // — this one is scoped and swaps with the picture.
    //
    // Key: an image's basename, or "scene_<id>" for a Wallpaper Engine scene (every
    // workshop preview is called preview.*, so basenames would all collide). The
    // caller — the colours panel — decides which, since only it knows whether a
    // scene is currently on screen.
    readonly property string wallPalettesDir: root.shellDir + "/theming/wallpaper-palettes"

    // ── What the palette is bound to right now ────────────────────────────────
    // A scene covers the still wallpaper, so while one runs (or gamemode has paused it)
    // the key is "scene_<id>". WallpaperEngine.current reads "" once the process has
    // stopped, hence the Config.wpeCurrent fallback — but only while paused, and only
    // when it names something, or a plain static-wallpaper session (empty wpeCurrent)
    // would get a blank "scene_" key.
    readonly property string sceneId:
        WallpaperEngine.current !== "" ? WallpaperEngine.current
        : Gamemode.wallpaperPaused     ? Config.wpeCurrent
        : ""
    readonly property bool   sceneOnScreen: WallpaperEngine.running || root.sceneId !== ""
    readonly property string paletteKey: root.sceneOnScreen
        ? (root.sceneId !== "" ? "scene_" + root.sceneId : "")
        : Wallpaper.current

    // The palette saved for that key, parsed — null when there is none. Read into a
    // plain property on load (not text() in a binding, which isn't reactive).
    property var _savedPalette: null
    FileView {
        id: savedPaletteFile
        path: root.hasPaletteFor(root.paletteKey)
            ? root.wallPalettesDir + "/" + root.paletteKey + ".json" : ""
        watchChanges: true
        onFileChanged: savedPaletteFile.reload()
        onPathChanged: root._savedPalette = null
        onLoaded: {
            try { root._savedPalette = JSON.parse(savedPaletteFile.text()) }
            catch (e) { root._savedPalette = null }
        }
        onLoadFailed: root._savedPalette = null
    }

    property var _wallPaletteKeys: []
    readonly property var wallPaletteKeys: root._wallPaletteKeys
    function hasPaletteFor(key) {
        return key !== "" && root._wallPaletteKeys.indexOf(key) !== -1
    }

    function refreshWallPalettes() {
        if (wallPaletteList.running) return
        wallPaletteList._rows = []
        wallPaletteList.running = true
    }

    Process {
        id: wallPaletteList
        running: true
        command: ["bash", "-c",
            'd="$1"; mkdir -p "$d"; for f in "$d"/*.json; do [ -e "$f" ] && basename "$f" .json; done',
            "_", root.wallPalettesDir]
        property var _rows: []
        stdout: SplitParser {
            onRead: function(line) {
                if (line !== "") wallPaletteList._rows = wallPaletteList._rows.concat([line])
            }
        }
        onExited: function() { root._wallPaletteKeys = wallPaletteList._rows.slice() }
    }

    // Bind `paletteObj` to `key`, then recolour now. `isScene` picks the recolour
    // route (a scene re-derives through WallpaperEngine, an image through Wallpaper).
    function saveWallpaperPalette(key, paletteObj, isScene) {
        if (!key || wallPaletteWriter.running) return
        wallPaletteWriter.wkey    = key
        wallPaletteWriter.wscene  = isScene === true
        wallPaletteWriter.op      = "save"
        wallPaletteWriter.payload = JSON.stringify(paletteObj, null, 2)
        wallPaletteWriter.running = false
        wallPaletteWriter.running = true
    }

    // Erase the binding and regenerate the ORIGINAL palette — deleting the file
    // then letting the pipeline run pywal again, which is all "back to normal" is.
    function clearWallpaperPalette(key, isScene) {
        if (!root.hasPaletteFor(key) || wallPaletteWriter.running) return
        wallPaletteWriter.wkey    = key
        wallPaletteWriter.wscene  = isScene === true
        wallPaletteWriter.op      = "clear"
        wallPaletteWriter.payload = ""
        wallPaletteWriter.running = false
        wallPaletteWriter.running = true
    }

    Process {
        id: wallPaletteWriter
        running: false
        property string wkey:    ""
        property bool   wscene:  false
        property string op:      "save"
        property string payload: ""
        environment: ({ "WP_PAYLOAD": wallPaletteWriter.payload })
        command: ["bash", "-c",
            'd="$1"; f="$d/$2.json"; mkdir -p "$d"; '
          + 'if [ "$3" = clear ]; then rm -f "$f"; else printf %s "$WP_PAYLOAD" > "$f"; fi',
            "_", root.wallPalettesDir, wallPaletteWriter.wkey, wallPaletteWriter.op]
        onExited: function(code) {
            root.refreshWallPalettes()
            if (code !== 0) {
                runnerInstance.notify("Couldn't update the wallpaper palette",
                                      "Writing failed.", "critical")
                return
            }
            // Re-run the palette pipeline so it takes effect immediately — clear
            // re-extracts with pywal, save restores the file we just wrote.
            if (wallPaletteWriter.wscene) WallpaperEngine.repalette()
            else                         Wallpaper.reapplyPalette()
            runnerInstance.notify(
                wallPaletteWriter.op === "clear" ? "Back to the original colours"
                                                 : "Colours saved for this wallpaper",
                wallPaletteWriter.op === "clear"
                    ? "The extracted palette has been regenerated."
                    : "It'll theme to this palette whenever it's on screen.",
                "low")
        }
    }
}
