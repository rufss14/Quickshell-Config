pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../services/palette.js" as Palette

// ── Colors ───────────────────────────────────────────────────────────────────
// The only place in the shell that knows what a color is.
//
// Source of truth is pywal/wallust's ~/.cache/wal/colors.json, watched live —
// re-theming the wallpaper re-themes the shell with no reload. Widgets never
// read colors.json, never read `color4`, and never write a hex literal. They
// ask for a *role*: `Colors.primary`, `Colors.surface`, `Colors.fg`.
//
// ── The two accents ───────────────────────────────────────────────────────────
// This shell has two accent roles, and they are not interchangeable:
//
//   primary (color1) — INTERACTIVE. "You can act on this, or you already have."
//                      Button fills and foregrounds, active/pressed states,
//                      the focused workspace, toggle-on states, badges.
//
//   focus   (color4) — SELECTION / ATTENTION. "This is the thing you're
//                      pointing at or the thing that's open." Hover outlines,
//                      focus rings, the open-panel border, keyboard selection
//                      in the launcher, slider tracks and handles.
//
// The test: if the color is filling a control the user clicks, it's `primary`.
// If it's outlining or highlighting a thing to tell them where they are, it's
// `focus`. A control that is both hovered and active shows a `focus` outline
// around a `primary` fill — which is exactly why they must be different hues.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── Source ────────────────────────────────────────────────────────────────
    // `fileData` is what is actually on disk; `data` is what the shell WEARS. They
    // differ only while something has pushed a transient overlay (see below), and the
    // roles are all defined in terms of `data` (config/PaletteRoles).
    property var fileData: ({})

    // Whether colors.json gave the shell a palette: "loading" until the first read
    // settles, then "ok", or "missing" — absent, unreadable, not JSON, or no colours in
    // it. Read by Wallpaper, which runs pywal when it is "missing" rather than leave the
    // shell in PaletteRoles' monochrome fallback. Once "ok", a later bad read (a write
    // caught half-done) keeps the palette already worn and never goes back to missing.
    property string fileState: "loading"

    // ── Transient overlay ─────────────────────────────────────────────────────
    // A palette held in memory that outranks colors.json without replacing it. The
    // album-cover colour scheme is the one user (services/AlbumScheme.qml): the shell
    // follows the music, and the moment playback stops the overlay is dropped and the
    // wallpaper's palette is simply back — no process, no file write, no regeneration.
    //
    // Doing it on disk instead would mean OVERWRITING colors.json with the album's
    // colours and then re-running pywal against the wallpaper to undo it — several
    // seconds of work, per track, to return to a palette we never actually lost. It
    // would also make every track change a permanent edit to the file the colour-scheme
    // editor is editing.
    //
    // Merged rather than swapped so a partial overlay is legal, and so a palette that
    // is missing a slot falls through to the wallpaper's rather than to black.
    property var overlay: ({})

    // ── Preview ───────────────────────────────────────────────────────────────
    // A palette held on top of EVERYTHING — the file, a workspace's palette and the album
    // overlay — for as long as it is set: the colour panel's Peek (hold to see the pending
    // scheme on the whole shell; let go and it is gone). It is not `overlay` because that one is
    // the album's: a track change reassigns it, so a preview sharing it would be overwritten
    // mid-peek and restore a stale album afterwards. Clear it with `({})`; ColorScheme owns it.
    property var preview: ({})

    // ── A peek eases fast ─────────────────────────────────────────────────────
    // The shell eases to a new palette in twelve steps over Motion.emphasized (340ms) — a step every
    // 28ms, which reads as stepping, not blending, when the whole shell is changing under your
    // thumb. A peek (hold a button, see it, let go) uses Motion.exit (200ms) for the same twelve:
    // one per frame at 60Hz, and quicker to answer. `fastEase()` is called BEFORE the preview is
    // set or cleared (ColorScheme.peek/endPeek), so the ease it starts is already the quick one,
    // and it drops back to the normal one a moment after the ease has ended.
    property bool _fast: false
    readonly property int easeMs: root._fast ? Motion.exit : Motion.emphasized
    function fastEase() {
        root._fast = true
        fastTimer.restart()
    }
    Timer { id: fastTimer; interval: Motion.exit + 120; onTriggered: root._fast = false }
    readonly property bool previewing: !!(root.preview?.special || root.preview?.colors)

    // What the shell wears WITHOUT a preview: the file, with the album's overlay over it. The
    // colour panel's editor reads this, so a peek cannot feed its own colours back into the seeds.
    readonly property var baseData: {
        const ov = root.overlay ?? ({})
        if (!ov.special && !ov.colors) return root.fileData
        return root._merge(root.fileData, ov)
    }
    readonly property var data: root.previewing ? root._merge(root.baseData, root.preview) : root.baseData
    function _merge(base, top) {
        const b = base ?? ({})
        return ({
            special: Object.assign({}, b.special ?? ({}), top.special ?? ({})),
            colors:  Object.assign({}, b.colors  ?? ({}), top.colors  ?? ({}))
        })
    }

    // ── Per screen: a workspace's own wallpaper ───────────────────────────────
    // screen name → palette (services/WorkspaceTheme): each screen wears the palette of
    // the workspace it SHOWS — over the file, under the album overlay — so two monitors
    // can wear two palettes at once. In memory only: a switch never writes colors.json.
    //
    // A visual file asks for its own screen's roles with `Colors.of(QsWindow.window)`
    // (QsWindow is Quickshell's attached window lookup, reactive); with no window or no
    // screen it gets this singleton — the shared palette, which every SERVICE reads
    // directly (Colors.primary): the cursor theme, the wave's apps, the scheme editor.
    property var screenOverlays: ({})

    function _screenData(name) {
        const ws = root.screenOverlays[name]
        if (!ws || (!ws.special && !ws.colors)) return root.data
        const d = root._merge(root._merge(root.fileData, ws), root.overlay ?? ({}))
        return root.previewing ? root._merge(d, root.preview) : d
    }

    Variants {
        id: perScreen
        model: Quickshell.screens
        delegate: PaletteRoles {
            required property var modelData
            // Eased, not snapped: a workspace's wallpaper (or the album's colours) takes the
            // screen over the length of a wallpaper's own crossfade. Motion.emphasized is 0
            // with animations off and under a wallpaper wave's snapshots, so those stay
            // instant.
            easeMs: root.easeMs
            goal: root._screenData(modelData?.name ?? "")
        }
    }

    function of(win) {
        const name = win?.screen?.name ?? ""
        if (name === "") return root
        const list = perScreen.instances
        for (let i = 0; i < list.length; i++)
            if ((list[i].modelData?.name ?? "") === name) return list[i]
        return root
    }

    // Is the palette on screen something other than what is on disk? Read by the
    // colour panel, which must not present a transient album or workspace palette as
    // if it were the saved one.
    readonly property bool overlaid: !!(root.overlay?.special || root.overlay?.colors)
                                     || root.previewing
                                     || Object.keys(root.screenOverlays).length > 0

    FileView {
        id: colorsFile
        // XDG_CACHE_HOME, as apply-wallpaper.sh writes it — a literal ~/.cache read a
        // different file from the one the pipeline wrote whenever that was set.
        path: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache"))
              + "/wal/colors.json"

        // Stated, not left to the default: without preload FileView does not read the
        // file until something calls text(), `onLoaded` never fires, and the palette
        // silently stays empty — every role on its monochrome fallback regardless of
        // the wallpaper. (Quickshell 0.3.1 defaults it to true; older builds did not.)
        preload: true

        // …and the FIRST read is synchronous (Component.onCompleted below): with a pywal
        // palette on disk, the shell must never draw a frame in the monochrome fallback,
        // not even on a reload. Read in the background, every surface used to come up in
        // the fallback and then ColorAnimation its way into the real palette — a visible
        // flash on each start. blockLoading makes that first text() call read the file
        // there and then (FileView::loadSync, which emits `loaded` before returning), and
        // this singleton is created by the first binding that needs a colour — so before
        // anything is drawn. ~1 KB; Quickshell's docs name exactly this case ("files the
        // program must have available"). Later reads are untouched: once loaded, nothing
        // blocks, and the inotify reloads stay asynchronous.
        blockLoading: true

        // Native inotify watch — no `cat`, no `inotifywait` subprocess.
        watchChanges: true
        onFileChanged: reload()

        onLoaded: {
            try {
                const doc = JSON.parse(colorsFile.text())
                if (!doc?.colors) throw new Error("no colours in it")
                root.fileData = doc
                root.fileState = "ok"
            } catch (e) {
                console.warn("Colors: colors.json is not a palette —", e)
                if (root.fileState !== "ok") root.fileState = "missing"
            }
        }
        onLoadFailed: function(error) {
            console.warn("Colors: could not read colors.json —", error)
            if (root.fileState !== "ok") root.fileState = "missing"
        }
    }

    Component.onCompleted: colorsFile.text()

    // Force a re-read. Only needed by things that rewrite colors.json behind
    // our back and want the UI updated before inotify catches up.
    function reload() { colorsFile.reload() }

    // ── The shared palette's roles ────────────────────────────────────────────
    // Defined (and documented) in config/PaletteRoles; forwarded here so a service's
    // `Colors.primary` reads exactly what it always did. Generated from PaletteRoles'
    // member list — add a role there, add its line here.
    PaletteRoles {
        id: main
        data: root.data
    }

    readonly property color base: main.base
    readonly property color text: main.text
    readonly property color ramp0: main.ramp0
    readonly property color ramp1: main.ramp1
    readonly property color ramp2: main.ramp2
    readonly property color ramp3: main.ramp3
    readonly property color ramp4: main.ramp4
    readonly property color ramp5: main.ramp5
    readonly property color ramp9: main.ramp9
    function ansi(i) { return main.ansi(i) }
    function alpha(c, a) { return main.alpha(c, a) }
    function fade(c, mult) { return main.fade(c, mult) }
    function mix(a, b, t) { return main.mix(a, b, t) }
    function role(name, fallback) { return main.role(name, fallback) }
    readonly property color primary: main.primary
    readonly property color fgOnPrimary: main.fgOnPrimary
    readonly property color vivid: main.vivid
    readonly property color focus: main.focus
    readonly property color surface: main.surface
    readonly property color surfaceContainer: main.surfaceContainer
    readonly property color surfaceHigh: main.surfaceHigh
    readonly property color section: main.section
    readonly property color primaryContainer: main.primaryContainer
    readonly property color fgOnPrimaryContainer: main.fgOnPrimaryContainer
    function surfaceFor(elevation) { return main.surfaceFor(elevation) }
    readonly property bool _lightMode: main._lightMode
    readonly property color outline: main.outline
    readonly property color outlineBar: main.outlineBar
    readonly property color outlineNested: main.outlineNested
    readonly property color outlineFocus: main.outlineFocus
    function outlineFor(elevation) { return main.outlineFor(elevation) }
    readonly property color fg: main.fg
    readonly property color fgMuted: main.fgMuted
    readonly property color fgDim: main.fgDim
    readonly property color fgFaint: main.fgFaint
    readonly property color stateIdleFg: main.stateIdleFg
    readonly property color stateHoverBg: main.stateHoverBg
    readonly property color stateHoverFg: main.stateHoverFg
    readonly property color statePressBg: main.statePressBg
    readonly property color statePressFg: main.statePressFg
    readonly property color stateActiveBg: main.stateActiveBg
    readonly property color stateActiveFg: main.stateActiveFg
    readonly property color success: main.success
    readonly property color warning: main.warning
    readonly property color danger: main.danger
    readonly property color info: main.info
    readonly property color wsEmpty: main.wsEmpty
    readonly property color wsOccupied: main.wsOccupied
    readonly property color wsFocused: main.wsFocused
    readonly property real frameAlpha: main.frameAlpha
    readonly property color frameFill: main.frameFill
    readonly property color frameLine: main.frameLine
    readonly property color shadow: main.shadow
    readonly property color shadowCast: main.shadowCast
    readonly property real shadowStrength: main.shadowStrength
}
