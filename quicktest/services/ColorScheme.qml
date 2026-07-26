pragma Singleton
import Quickshell
import "../config"
import Quickshell.Io
import QtQuick

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
// ── Everything you set by hand persists ───────────────────────────────────────
// Pinning one slot and applying a whole scheme are the SAME operation at different
// scales — both write the overrides file, both survive wallpaper changes, both are undone
// by "Release all". An earlier cut made schemes non-persistent on the theory that a whole
// palette isn't a pin; that just meant applying a scheme and then changing wallpaper threw
// the scheme away, which is not what anyone wants from a colour scheme.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property string shellDir:   Quickshell.env("HOME") + "/.config/quicktest"
    readonly property string schemesDir: root.shellDir + "/colorschemes"
    readonly property string overridesPath: root.shellDir + "/theming/pywal-overrides.json"
    readonly property string walJson: Quickshell.env("HOME") + "/.cache/wal/colors.json"

    // ── Live palette ──────────────────────────────────────────────────────────
    // Read from the Colors singleton rather than re-parsing colors.json: it already watches
    // that file and every widget in the shell is bound to it, so a second reader would be a
    // second source of truth that goes stale.
    readonly property var live: Colors.data ?? ({})

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

    readonly property bool busy: runnerInstance.running

    // Push whatever is in colors.json out to every app. Used after pinning, since the
    // pipeline merges overrides itself — there is nothing else to write.
    function reload(label) {
        runnerInstance.run(["bash", Quickshell.shellPath("scripts/reload-theme.sh")],
                           label ?? "Colour change")
    }

    // ── Applying a scheme IS pinning every slot ───────────────────────────────
    // Originally this wrote colors.json directly and deliberately did NOT persist, on the
    // reasoning that a whole palette isn't a "pin" and the next wallpaper should replace
    // it. That was a distinction the user never asked for and did not want: applying a
    // scheme and then changing wallpaper threw the scheme away.
    //
    // A scheme is simply an edit of all 18 slots, so it goes through the same overrides
    // file as a single pinned colour. That also deletes a whole write path — reload-theme.sh
    // merges overrides into colors.json itself, so there is nothing else to write.
    //
    // "Release all" is what hands control back to the wallpaper, and the banner showing
    // 18 held colours is the honest description of what applying a scheme did.
    function applyPalette(paletteObj, label) {
        if (runnerInstance.running) return

        const flat = ({})
        for (const k in (paletteObj.special ?? ({})))
            if (k !== "cursor") flat[k] = paletteObj.special[k]
        for (const k in (paletteObj.colors ?? ({})))
            flat[k] = paletteObj.colors[k]

        root.pinMany(flat)
        root.reload(label ?? "Colour scheme")
    }

    // Rebuild from the current wallpaper. Goes through the wallpaper script so the
    // per-wallpaper corrections and the override merge both still happen — the old version
    // ran `wal -i` itself and skipped the overrides entirely, which silently discarded
    // exactly the edits this panel exists to make.
    function regenerate() {
        if (runnerInstance.running) return
        runnerInstance.run(["bash", "-c",
            'CUR=$(cat "$HOME/.cache/current_wallpaper_name" 2>/dev/null); '
          + 'W="$HOME/wallpapers/walls/$CUR"; '
          + '[ -f "$W" ] || W="$HOME/wallpapers/pywallpaper.jpg"; '
          + 'exec bash "' + Quickshell.shellPath("scripts/apply-wallpaper.sh") + '" "$W"'],
            "Rebuild from wallpaper")
    }

    // ── Saved schemes ─────────────────────────────────────────────────────────
    // [{ name, palette }] — the palette rides along so the library can show each
    // scheme's real colours without a second read per chip.
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
          + "    print(f[:-5] + '\\t' + json.dumps(p, separators=(',',':')))\n",
            root.schemesDir]

        property var _rows: []
        stdout: SplitParser {
            onRead: function(line) {
                const tab = line.indexOf("\t")
                if (tab < 0) return
                const name = line.substring(0, tab)
                try {
                    presetList._rows = presetList._rows.concat([
                        { name: name, palette: JSON.parse(line.substring(tab + 1)) }])
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
        }
    }

    // Names are sanitised to a safe set AND passed as an argument rather than interpolated
    // into the command — the old version built the path inside a shell string, so a name
    // with a quote in it wrote somewhere unintended.
    function sanitiseName(name) {
        return (name ?? "").trim().replace(/[^a-zA-Z0-9 _.-]/g, "")
    }

    function saveScheme(name, paletteObj) {
        const n = root.sanitiseName(name)
        if (n === "") {
            runnerInstance.notify("Name required", "Give the scheme a name first.", "normal")
            return false
        }
        if (schemeSaver.running) return false
        schemeSaver.payload = JSON.stringify(paletteObj, null, 2)
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
    function useScheme(preset) {
        if (!preset || !preset.palette) return
        root._loadedScheme = preset.palette
        root.schemeLoaded(preset.name, preset.palette)
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
                const p = JSON.parse(schemeReader._buf)
                root._loadedScheme = p
                root.schemeLoaded(schemeReader.sname, p)
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
            if (code === 0) root.refreshPresets()
            else runnerInstance.notify("Delete failed",
                                       "“" + schemeDeleter.sname + "” is still there.", "critical")
        }
    }
}
