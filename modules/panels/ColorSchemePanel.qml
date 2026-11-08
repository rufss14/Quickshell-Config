pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../services/palette.js" as Palette
import "colorscheme"

// ── ColorSchemePanel ──────────────────────────────────────────────────────────
// The palette editor.
//
// ── All logic lives in the ColorScheme service ────────────────────────────────
// This file was 1308 lines and owned everything: six Processes, a bash pipeline built by
// string concatenation, colour maths, and the UI. That pipeline was a SECOND COPY of the
// wallpaper one and had rotted. It now lives in `scripts/reload-theme.sh`, shared with the
// wallpaper gallery, driven by `ColorScheme`. Colour maths moved to `services/palette.js`.
//
// ── Anything you set by hand is held ──────────────────────────────────────────
// Simple derives a whole palette from four seeds; Advanced edits individual slots. Both
// write the same overrides file, so both survive wallpaper changes, and "Release all"
// undoes either. Held colours are always visible and always clearable.
//
// ── Looks like the wallpaper gallery and the media panel ──────────────────────
// The recipe those two wear: header actions are ChipTrays of ChipButtons, the page switch
// is a SegmentSwitch (spring indicator), fields are pill InputFields, and every view comes
// in through a ViewEnter (it rises and fades up, the footer a beat behind the card). An
// opt-in per-step apply log is gated by Config.colorApplyDebug — a FAILED apply always
// surfaces its log regardless. No hero: the wallpaper panel shows a picture because there
// is one to show; here the palette IS the content, laid out in the workbench.
//
// ── Palette | Presets | Album ────────────────────────────────────────────────
// The switch under the header chooses between EDIT (the workbench — picker in one
// bounded card so it stops reading as a floating gradient column), LIBRARY (saved
// presets, their own view so the editor isn't sharing height with a grid of cards) and
// ALBUM (follow the cover, and how far it reaches).
// Presets get a first-class switch rather than being a mode because that's the more
// frequent trip; Palette-vs-Slots is a header button. Picking a preset drops back
// into EDIT with its seeds loaded and the card flagged. Colour SOURCES (follow album
// cover, rebuild from wallpaper, release held) are header buttons; the "why" of an
// album-cover state rides the subtitle.
//
// ── A scheme per workspace ──────────────────────────────────────────────────
// RIGHT-click a card in the library (left-click still loads it into the editor): the library folds
// into components/WorkspacePicker, which asks which workspaces wear it. Those wear it — the shell on
// the screen showing one, and the apps on it — as a workspace's own wallpaper's colours do
// (services/WorkspaceTheme), in memory, with no theming run. A card shows the workspaces wearing it.
//
// ── This wallpaper's palette ────────────────────────────────────────────────
// The footer's "Save for wallpaper / scene" binds the built palette to whatever is on
// screen (keyed by basename, or "scene_<id>" for a Wallpaper Engine scene). Reset
// erases the binding and regenerates the original with pywal. Handled by
// ColorScheme + apply-wallpaper.sh's step 1c — see there.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    // Reached by the view files in colorscheme/.
    property alias savedTimer: savedTimer

    implicitWidth:  608
    // Hugs its content — no fillHeight anywhere, every sub-view contributes its own
    // height (capped). BarPanelDock reads implicitHeight, so the panel grows/shrinks
    // as the editor, library or progress view takes over.
    implicitHeight: mainCol.implicitHeight + Tokens.spacingMd * 2

    property string view: "edit"            // "edit" | "library" | "album"
    property string mode: "simple"          // "simple" | "advanced"

    // One accent for the whole panel — every highlight below follows it, as WallpaperPanel's does.
    readonly property color accent: Colors.of(QsWindow.window).primary

    // Gutter on the right where the library's scrollbar sits, clear of the cards.
    readonly property int contentPad: 16

    // ── What the palette is bound to right now ───────────────────────────────
    // A scene covers the still wallpaper completely, so while one runs the "this
    // wallpaper" controls act on the SCENE, keyed "scene_<id>" — the still's name
    // would be wrong. Acquire holds WallpaperEngine's poll while the panel is open.
    Component.onCompleted:   WallpaperEngine.acquire()
    // A peek is only ever held: if the panel goes while it is, the shell must not stay wearing it.
    Component.onDestruction: { WallpaperEngine.release(); ColorScheme.endPeek(); ColorScheme.cancelPick() }

    // ── Choosing a scheme's workspaces ───────────────────────────────────────
    // `ColorScheme.pending` is the scheme being placed. The library gives way to the picker; the name
    // is held so the picker keeps its swatch through the fold back out.
    // The same picker also chooses the ALBUM's workspaces (Album › Where › Chosen workspaces).
    property bool pickingAlbum: false
    readonly property bool picking: ColorScheme.pending !== "" || root.pickingAlbum
    property string pickingName: ""
    onPickingChanged: {
        if (root.picking) {
            if (!root.pickingAlbum) root.pickingName = ColorScheme.pending
            Qt.callLater(() => picker.forceActiveFocus())
        }
    }

    // A scene gamemode has paused is still the palette's real subject — nothing
    // about editing/saving a scheme needs the renderer literally painting
    // frames right now, and falling back to the static image underneath would
    // edit/save against the wrong key entirely. `_sceneId` is the stable id:
    // WallpaperEngine.current reads "" once the process is actually stopped,
    // so it falls back to Config.wpeCurrent, the same source the wallpaper
    // panel's own paused hero already trusts — but ONLY while paused, and only
    // when that fallback actually names something. wallpaperPaused is true for
    // a plain static-wallpaper session now too (the takeover card shows either
    // way), and someone who's never touched Wallpaper Engine has an empty
    // Config.wpeCurrent — without this guard they'd get a blank "scene_" key
    // instead of falling through to their real, static Wallpaper.current.
    // ColorScheme owns the key (it needs it to know what a rebuild would produce).
    readonly property string _sceneId:     ColorScheme.sceneId
    readonly property bool   sceneOnScreen: ColorScheme.sceneOnScreen
    readonly property string paletteKey:   ColorScheme.paletteKey
    readonly property bool wpHasPalette:
        root.paletteKey !== "" && ColorScheme.wallPaletteKeys.indexOf(root.paletteKey) !== -1

    // ── The palette the editor reflects ─────────────────────────────────────
    // Normally the one on disk (ColorScheme.live). While the album cover is driving
    // the shell it's the ALBUM's palette instead — `Colors.baseData` is fileData with the
    // overlay merged — so the cover's colours land in the seeds and slots and can be
    // tweaked, applied, or saved as a preset. It follows track changes until you touch
    // a colour, which pins that seed.
    readonly property var editBase: AlbumScheme.active
        ? (Colors.baseData ?? ColorScheme.live)
        : ColorScheme.live

    // ── Simple mode: four seeds ───────────────────────────────────────────────
    property string seedBg: Palette.slotValue(root.editBase, "background")
    property string seedFg: Palette.slotValue(root.editBase, "foreground")
    property string seedA:  Palette.slotValue(root.editBase, "color1")
    property string seedB:  Palette.slotValue(root.editBase, "color4")
    property int    seedIndex: 0            // which seed the picker drives

    // Editing any seed means you're no longer using the loaded scheme verbatim.
    onSeedBgChanged: root.dropLoaded()
    onSeedFgChanged: root.dropLoaded()
    onSeedAChanged:  root.dropLoaded()
    onSeedBChanged:  root.dropLoaded()

    readonly property var seeds: [
        { key: "seedBg", label: "Background", value: root.seedBg },
        { key: "seedFg", label: "Text",       value: root.seedFg },
        { key: "seedA",  label: "Accent",     value: root.seedA  },
        { key: "seedB",  label: "Accent 2",   value: root.seedB  }
    ]

    // A scheme loaded from disk previews and applies EXACTLY what was saved. Deriving from
    // its four seeds instead would show a different palette from the one whose name you
    // clicked. Any seed edit drops back to deriving.
    property var loadedPalette: null

    readonly property var derived: root.loadedPalette
        ?? Palette.derive(root.seedBg, root.seedFg, [root.seedA, root.seedB])

    // What Advanced will actually produce: the live palette with staged edits laid over it.
    readonly property var stagedPalette: {
        const out = ({ special: ({}), colors: ({}) })
        for (const slot of Palette.allSlots()) {
            const v = root.slotColor(slot)
            if (Palette.isSpecial(slot)) out.special[slot] = v
            else                         out.colors[slot]  = v
        }
        out.special["cursor"] = out.special["foreground"]
        return out
    }

    // The palette the Apply button will commit, in either mode. The preview shows this.
    readonly property var pending: root.mode === "simple" ? root.derived : root.stagedPalette

    function dropLoaded() { root.loadedPalette = null }

    // ── The colour the picker, the hex field and the swatches are all pointing at ──
    // Simple: the chosen seed. Advanced: the chosen slot (with any staged edit laid over it).
    // `setCurrent` is the ONE place that writes it back — the picker and the hex field used to
    // each carry their own copy of this branch.
    readonly property string curHex: root.mode === "simple"
        ? root.seeds[root.seedIndex].value
        : root.slotColor(root.selectedSlot)

    function setCurrent(hex) {
        if (root.mode === "simple") {
            const k = root.seeds[root.seedIndex].key
            if      (k === "seedBg") root.seedBg = hex
            else if (k === "seedFg") root.seedFg = hex
            else if (k === "seedA")  root.seedA  = hex
            else                     root.seedB  = hex
        } else {
            root.stage(root.selectedSlot, hex)
        }
    }

    // ── Advanced mode: staged per-slot edits ──────────────────────────────────
    property var    draft: ({})             // { slot: hex } — uncommitted
    property string selectedSlot: "background"

    readonly property int draftCount: Object.keys(root.draft).length

    function slotColor(slot) {
        if (root.draft[slot] !== undefined) return root.draft[slot]
        return Palette.slotValue(root.editBase, slot)
    }

    function stage(slot, hex) {
        const next = Object.assign({}, root.draft)
        next[slot] = hex.toLowerCase()
        root.draft = next                   // reassigned, not mutated — QML re-evaluates
    }                                       // bindings on a property CHANGE only

    function discardDraft() { root.remember(); root.draft = ({}) }

    // ── Undo ─────────────────────────────────────────────────────────────────
    // A stack of what the editor held before each step: a picker drag (the whole drag is one step),
    // a typed hex, Shuffle, a harmony, a scheme loaded from the library, a discarded draft. Seeds
    // are NOT saved anywhere, so without this a Shuffle you did not like took your accents with it.
    // Both modes' state rides in a step (the four seeds, the loaded scheme, the staged slots), so one
    // undo is the same in Palette and in Slots. Capped; there is no redo.
    property var history: []
    readonly property int historyMax: 30

    function snapshot() {
        return { bg: root.seedBg, fg: root.seedFg, a: root.seedA, b: root.seedB,
                 loaded: root.loadedPalette, draft: root.draft }
    }
    function _same(x, y) {
        return x.bg === y.bg && x.fg === y.fg && x.a === y.a && x.b === y.b
            && x.loaded === y.loaded && x.draft === y.draft
    }
    function remember() {
        const now = root.snapshot()
        const h = root.history
        // A press that did not move anything is not a step.
        if (h.length > 0 && root._same(h[h.length - 1], now)) return
        root.history = h.slice(-(root.historyMax - 1)).concat([now])
    }
    function undo() {
        if (root.history.length === 0) return
        root.ripple()
        const h = root.history.slice()
        const step = h.pop()
        root.history = h
        root.seedBg = step.bg
        root.seedFg = step.fg
        root.seedA  = step.a
        root.seedB  = step.b
        root.draft  = step.draft
        root.loadedPalette = step.loaded     // AFTER the seeds — assigning them fires dropLoaded()
    }

    // Whole pipeline is pywal — reload-theme.sh calls `wal`. Without it every
    // apply fails at the palette step, so the controls say why instead.
    readonly property string blocked: Wallpaper.pywalBlocker()

    // ── How readable the palette about to be applied is ──────────────────────────
    // Its text on its background, graded the way WCAG names it (palette.js contrastGrade).
    readonly property real   textContrast: Palette.contrast(Palette.slotValue(root.pending, "background"),
                                                            Palette.slotValue(root.pending, "foreground"))
    readonly property string contrastGrade: Palette.contrastGrade(root.textContrast)

    // ── Shuffle: a fresh pair of accents ───────────────────────────────────────
    // Background and text stay as they are; the two accents are redrawn, related by a random
    // harmony and each lifted to stay legible on that background (palette.js suggestAccents,
    // tested). The chip's icon rolls once.
    property real _shufflePhase: 0
    NumberAnimation {
        id: shuffleSpin
        target: root; property: "_shufflePhase"
        from: 0; to: 360
        duration: Motion.spatialSlow; easing.type: Motion.travel
    }
    function shuffleAccents() {
        root.remember()
        root.ripple()
        const a = Palette.suggestAccents(root.seedBg, root.seedFg)
        root.seedA = a[0]
        root.seedB = a[1]
        shuffleSpin.restart()
    }

    // ── The presets library: search and sort ───────────────────────────────────
    // Local to the panel (reset each time it opens). Searching hides cards rather than rebuilding the
    // list, so what is left glides together instead of every card re-arriving per keystroke; sorting
    // reorders the model, which does rebuild it — and re-arrives, which is what a sort should look like.
    readonly property int libToolsFrom: 6     // schemes it takes before search and sort appear
    property string libQuery: ""
    property string libSort:  "name"          // "name" | "recent"
    // Starred schemes float to the front, in the order chosen (like the wallpaper gallery's favourites).
    property bool libStarOnly: false
    readonly property var sortedPresets: {
        const all = root.libSort === "recent"
            ? ColorScheme.presets.slice().sort((a, b) => b.mtime - a.mtime)
            : ColorScheme.presets.slice()
        const stars = Config.colorFavorites
        return all.filter(p => stars.indexOf(p.name) >= 0).concat(all.filter(p => stars.indexOf(p.name) < 0))
    }
    function presetMatches(name) {
        if (root.libStarOnly && Config.colorFavorites.indexOf(name) < 0) return false
        const q = root.libQuery.trim().toLowerCase()
        return q === "" || name.toLowerCase().indexOf(q) >= 0
    }
    readonly property int libMatches: ColorScheme.presets.filter(p => root.presetMatches(p.name)).length

    // ── Harmony: Accent 2 from Accent ─────────────────────────────────────────
    // Four ways to pick a second colour that goes with the first, named by what they LOOK like and in
    // order of how far round the colour wheel they go: Similar (30°), Triad (120°), Split (150°),
    // Opposite (180°). Applying one sets Accent 2 to its partner of Accent (kept legible on the
    // background — palette.js `partner`, tested) and selects Accent 2 so the change is where you are
    // looking. Each chip carries a dot of the colour it would give, and stays lit while Accent 2 IS that
    // partner — the dots are the explanation; there is no caption.
    readonly property var harmonies: [
        { kind: "analogous",     label: "Similar"  },
        { kind: "triad",         label: "Triad"    },
        { kind: "split",         label: "Split"    },
        { kind: "complementary", label: "Opposite" }
    ]
    function partnerOf(kind) { return Palette.partner(root.seedA, root.seedBg, root.seedFg, kind) }
    function applyHarmony(kind) {
        root.remember()
        root.ripple()                    // before the change: it only counts for the tick it lands in
        root.seedB = root.partnerOf(kind)
        root.seedIndex = 3
    }

    // ── A discrete change ripples ─────────────────────────────────────────────
    // Shuffle, a harmony, a scheme loaded, an undo: the swatches bump one after another and the ribbon
    // re-colours as a wave, so a jump of colour reads as something that happened, left to right.
    // (A drag, or typing a hex, is continuous and tracks instead — see `rippleOn`.) True only for the
    // tick in which the change lands.
    signal rippled()
    property bool rippleOn: false
    function ripple() {
        root.rippleOn = true
        root.rippled()
        Qt.callLater(function () { root.rippleOn = false })
    }

    // ── "Saved" ──────────────────────────────────────────────────────────────
    property bool justSaved: false
    Timer { id: savedTimer; interval: 1200; onTriggered: root.justSaved = false }

    // ── Back to what the shell is wearing ─────────────────────────────────────
    // The editor holds edits (four seeds, staged slots, a loaded scheme) that are not the colours in use.
    // This is the way back: re-read them from what the shell is wearing right now (the album's, while
    // it drives the shell), drop the staged slots and the loaded scheme. One undo step, so it can itself
    // be undone. Greyed while the editor already matches.
    readonly property bool editorDiffers:
           root.draftCount > 0 || root.loadedPalette !== null
        || root.seedBg.toLowerCase() !== Palette.slotValue(root.editBase, "background").toLowerCase()
        || root.seedFg.toLowerCase() !== Palette.slotValue(root.editBase, "foreground").toLowerCase()
        || root.seedA.toLowerCase()  !== Palette.slotValue(root.editBase, "color1").toLowerCase()
        || root.seedB.toLowerCase()  !== Palette.slotValue(root.editBase, "color4").toLowerCase()
    property real _syncPhase: 0
    NumberAnimation {
        id: syncSpin
        target: root; property: "_syncPhase"
        from: 0; to: 360
        duration: Motion.spatialSlow; easing.type: Motion.travel
    }
    function syncToCurrent() {
        root.remember()
        root.ripple()
        root.seedBg = Palette.slotValue(root.editBase, "background")
        root.seedFg = Palette.slotValue(root.editBase, "foreground")
        root.seedA  = Palette.slotValue(root.editBase, "color1")
        root.seedB  = Palette.slotValue(root.editBase, "color4")
        root.draft  = ({})
        root.loadedPalette = null
        ColorScheme.setLoadedName("")
        syncSpin.restart()
    }

    // ── Light / dark ──────────────────────────────────────────────────────────
    // The editor holds ONE palette at a time — the one for the shell's current mode — and keeps what you
    // were making in the OTHER mode while you are away: flip to Light, build it, flip back, and the dark
    // one is where you left it. Saving writes the current mode's palette, and the other's too if you
    // made one (`stash`); a mode you never touched is left out, so a scheme only gains a second mode
    // when you built it. The mode itself is Config.themeMode, flipped by ColorScheme.switchMode from
    // wherever (this panel, Settings, a keybind) — so this reacts to the CHANGE, not to a click.
    property var stash: ({ dark: null, light: null })       // mode → { snap, palette } — kept while away

    // Seeds from a palette, the way loading a scheme does (and the loaded-scheme marker AFTER them).
    function loadVariant(p) {
        root.seedBg = Palette.slotValue(p, "background")
        root.seedFg = Palette.slotValue(p, "foreground")
        root.seedA  = Palette.slotValue(p, "color1")
        root.seedB  = Palette.slotValue(p, "color4")
        root.draft  = ({})
        root.loadedPalette = p
    }
    function enterTheme(to) {
        root.ripple()
        const st = root.stash[to]
        if (st) {                                  // what you were making here, back as you left it
            root.seedBg = st.snap.bg; root.seedFg = st.snap.fg
            root.seedA  = st.snap.a;  root.seedB  = st.snap.b
            root.draft  = st.snap.draft
            root.loadedPalette = st.snap.loaded
            return
        }
        const v = ColorScheme.currentPreset()?.variants?.[to]
        if (v) { root.loadVariant(v); return }     // the scheme being edited has a version for it
        // Otherwise the new mode's palette is on its way from the shell (re-derived from the wallpaper).
        if (Config.wallTheming) { root._awaitLive = true; awaitTimer.restart() }
    }
    property bool _awaitLive: false
    Timer { id: awaitTimer; interval: 10000; onTriggered: root._awaitLive = false }
    Connections {
        target: Colors
        function onFileDataChanged() {
            if (!root._awaitLive) return
            root._awaitLive = false
            awaitTimer.stop()
            root.syncToCurrent()
            root.history = []
        }
    }
    Connections {
        target: Config
        function onThemeModeChanged() {
            const to = Config.themeMode
            const from = to === "light" ? "dark" : "light"
            // Keep what was being made in the mode just left — if it IS something made.
            const s = Object.assign({}, root.stash)
            s[from] = root.editorDiffers ? { snap: root.snapshot(), palette: root.pending } : null
            root.stash = s
            root.history = []                      // a step back would cross the mode
            root.enterTheme(to)
        }
    }

    // What Save writes: this mode's palette, and the other mode's if it was made.
    function saveVariants() {
        const here = Config.themeMode === "light" ? "light" : "dark"
        const away = here === "light" ? "dark" : "light"
        const v = ({})
        v[here] = root.pending
        if (root.stash[away]) v[away] = root.stash[away].palette
        return v
    }

    // A scheme that has only the OTHER mode loads that one — say so, and say what Save will do.
    readonly property string fallbackNote:
        root.loadedPalette !== null && ColorScheme.loadedName !== "" && !ColorScheme.loadedExact
        ? "Only has " + (ColorScheme.loadedMode === "light" ? "Light" : "Dark")
          + " — Save to add this as its " + (Config.themeMode === "light" ? "Light" : "Dark") + " version"
        : ""

    // ── Copy the colour in use ────────────────────────────────────────────────
    property bool justCopied: false
    Timer { id: copiedTimer; interval: 1200; onTriggered: root.justCopied = false }
    function copyCurrent() {
        Clipboard.copyText(root.curHex)
        root.justCopied = true
        copiedTimer.restart()
    }

    // ── "Applied" ────────────────────────────────────────────────────────────
    // An apply THIS panel started, landing: the Apply chip turns into a tick for a moment, so
    // the end of the run is something you see and not only the colours having changed. Only for
    // our own apply (a wallpaper change finishing is not news here), and not for a failed one —
    // that takes the body over with its log instead.
    property bool _applyPending: false
    property bool justApplied:   false
    // A dwell, not motion: how long the tick stays up. Not scaled by the animation preference.
    Timer { id: appliedTimer; interval: 1800; onTriggered: root.justApplied = false }
    Connections {
        target: ColorScheme
        function onBusyChanged() {
            if (ColorScheme.busy || !root._applyPending) return
            root._applyPending = false
            if (root.applyFailed) return
            root.justApplied = true
            appliedTimer.restart()
        }
    }

    // ── Applying ──────────────────────────────────────────────────────────────
    function applyCurrent() {
        if (ColorScheme.busy || root.blocked !== "") return
        // Pending only if the apply actually started a run: one that found nothing to do never
        // goes busy, and would otherwise tick for the next unrelated run to finish.
        root._applyPending = true
        Qt.callLater(function () { if (!ColorScheme.busy) root._applyPending = false })
        // An Apply is for the whole shell: workspaces with a scheme of their own outrank it, so they are let go.
        ColorScheme.releaseForApply()
        if (root.mode === "simple") {
            ColorScheme.applyPalette(root.pending, "Colour scheme")
        } else {
            if (root.draftCount > 0) ColorScheme.pinMany(root.draft)
            root.discardDraft()
            ColorScheme.reload("Pinned colours")
        }
    }

    // ── Progress ─────────────────────────────────────────────────────────────
    // A FAILED run always takes over the body. A run in PROGRESS only takes over when
    // Config.colorApplyDebug is on; otherwise a "Applying…" note sits in the header.
    readonly property bool applyFailed:   ColorScheme.runner.failed && !ColorScheme.busy
    readonly property bool showProgress:  root.applyFailed || (ColorScheme.busy && Config.colorApplyDebug)
    readonly property bool applyingQuiet: ColorScheme.busy && !Config.colorApplyDebug

    // Which apps still hold the old colours, for the subtitle (the header's restart chip is
    // just an icon — a text pill there pushed WallpaperPanel's header past its width).
    readonly property string restartNote: ColorScheme.runner.needsRestart && !ColorScheme.busy
        ? (ColorScheme.runner.restartApps.length === 1
            ? ColorScheme.runner.restartApps[0].label + " needs a restart"
            : ColorScheme.runner.restartApps.length + " apps need a restart")
        : ""

    property bool showDetails: false
    onShowProgressChanged: if (!root.showProgress) root.showDetails = false

    Connections {
        target: ColorScheme.runner
        function onFailedChanged() { if (ColorScheme.runner.failed) root.showDetails = true }
    }

    // ── Rebuild-from-wallpaper: spin the button while it works ────────────────
    // ── What the refresh chip does ────────────────────────────────────────────
    // Normally: rebuild the palette from the wallpaper. While the ALBUM is driving the shell it
    // reloads the album's colours instead (AlbumScheme.reload — a fresh extraction of the cover on
    // screen): rebuilding from the wallpaper there handed the shell back to the wallpaper, and in the
    // "Everything" reach overwrote colors.json — which IS the album's palette then — with it.
    readonly property bool albumDriving: AlbumScheme.active
    property bool _regenSpinning: false
    property real _regenPhase:    0
    // Spins for a beat after a click; for the album it keeps going for as long as the extraction runs.
    readonly property bool regenSpin: root._regenSpinning || (root.albumDriving && AlbumScheme.extracting)
    Timer { id: _regenSpinTimer; interval: 850; onTriggered: root._regenSpinning = false }
    NumberAnimation {
        target: root; property: "_regenPhase"
        from: 0; to: 360; duration: 850
        loops: Animation.Infinite
        running: root.regenSpin
    }
    function doRegen() {
        const album = root.albumDriving
        if (album) { if (!AlbumScheme.reload()) return }
        else if (ColorScheme.settled) return
        root._regenSpinning = true
        _regenSpinTimer.restart()
        if (!album) ColorScheme.regenerate()
    }

    // Picking a scheme from the library fills the seeds and drops you back in the editor
    // to adjust or apply it.
    Connections {
        target: ColorScheme
        function onSchemeLoaded(name, p) {
            root.remember()
            root.ripple()
            root.seedBg = Palette.slotValue(p, "background")
            root.seedFg = Palette.slotValue(p, "foreground")
            root.seedA  = Palette.slotValue(p, "color1")
            root.seedB  = Palette.slotValue(p, "color4")
            root.loadedPalette = p          // AFTER the seeds — assigning them fires dropLoaded()
            root.mode = "simple"
            root.view = "edit"
            workbench.schemeName.setText(name)
        }
    }

    MouseArea {
        anchors.fill: parent
        propagateComposedEvents: true
        onPressed: function(mouse) {
            if (workbench.schemeName.editing) workbench.schemeName.blur()
            if (workbench.hexField.editing)   workbench.hexField.blur()
            mouse.accepted = false
        }
    }

    // ── Rigid, not filling ────────────────────────────────────────────────────
    // Pinned to the top at its OWN height, never `anchors.fill`. The dock's card animates its
    // height to the view's `implicitHeight`, and a column that fills it hands the surplus
    // (while the card is taller than the content, i.e. whenever a tab switch shrinks the
    // panel) to every child that defaults to fillHeight — so the header, and the switch under
    // it, slid down and back on each tab change. This way the card's edge simply reveals or
    // trims the content, and the header never moves.
    ColumnLayout {
        id: mainCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.spacingMd
        spacing: Tokens.spacingSm

        // ══ Header ════════════════════════════════════════════════════════════
        PanelHeader {
            Layout.fillHeight: false
            icon:      Icons.asset("Palette")
            glyph:     "󰸌"
            title:     Translation.tr("Colours")
            titleTail: root.view === "library" ? "Library"
                     : root.view === "album"   ? "Album"
                     : root.mode === "simple"  ? "Scheme" : "Slots"
            accent:    root.accent
            subtitle:  root.picking
                     ? (root.pickingAlbum ? "Which workspaces follow the album?" : "Which workspaces wear it? The others keep theirs.")
                     : root.blocked !== ""
                     ? root.blocked
                     : root.applyingQuiet
                     ? ((ColorScheme.runner.label || "Applying") + "…")
                     : root.restartNote !== ""
                     ? root.restartNote
                     : (root.view === "edit" && root.fallbackNote !== "")
                     ? root.fallbackNote
                     : root.view === "album"
                     ? AlbumScheme.reasonText
                     : (AlbumScheme.active || AlbumScheme.reason === "held")
                     ? AlbumScheme.reasonText
                     : root.view === "library"
                     ? (ColorScheme.presets.length + " saved · click to load · right-click for workspaces")
                     : root.mode === "simple"
                     ? "Four colours, whole palette"
                     : root.draftCount > 0
                     ? root.draftCount + " unsaved change" + (root.draftCount !== 1 ? "s" : "")
                     : "Hold individual colours"

            BusyDot {
                Layout.alignment: Qt.AlignVCenter
                running: root.applyingQuiet
                tint: root.accent
            }

            // ── Light / dark ──────────────────────────────────────────────────
            // The shell's mode — the same one Settings › Appearance flips, through the same
            // ColorScheme.switchMode: the palette is re-derived in it, or, if the scheme being worn is a
            // saved one that holds the other mode too, THAT version is applied. Like Settings, off
            // while wallpaper theming is off (nothing would change) or a palette is being made.
            ChipTray {
                groupShown: !root.showProgress && !root.picking
                ChipButton {
                    symbol:  "light_mode"
                    on:      Config.themeMode === "light"
                    tint:    root.accent
                    enabled: Config.wallTheming && !Wallpaper.applying && !ColorScheme.busy
                    onActivated: ColorScheme.switchMode("light")
                }
                ChipButton {
                    symbol:  "dark_mode"
                    on:      Config.themeMode === "dark"
                    tint:    root.accent
                    enabled: Config.wallTheming && !Wallpaper.applying && !ColorScheme.busy
                    onActivated: ColorScheme.switchMode("dark")
                }
            }

            // ── Group 1: acts on the live palette ─────────────────────────────
            // Round chips on one pill (ChipTray / ChipButton — the wallpaper and media
            // panels' header): off is an icon on the tray, on is a filled disc with the
            // icon filled in.
            ChipTray {
                groupShown: !root.showProgress && !root.picking

                // Apps that need restarting — one icon, not a text pill (the subtitle names
                // the apps): hoisted by the title, it reads as a consequence of the apply
                // rather than a control competing with it. The chip beside it is "leave them".
                ChipButton {
                    visible: ColorScheme.runner.needsRestart && !ColorScheme.busy
                    symbol:  "restart_alt"
                    on:      true
                    tint:    Colors.of(QsWindow.window).warning
                    onActivated: ColorScheme.runner.restartAll()
                }
                ChipButton {
                    visible: ColorScheme.runner.needsRestart && !ColorScheme.busy
                    symbol:  "close"
                    tint:    Colors.of(QsWindow.window).warning
                    onActivated: ColorScheme.runner.dismissRestart()
                }
                ChipButton {
                    symbol:  "refresh"
                    tint:    root.accent
                    // Greyed while every colour is locked and showing: nothing to rebuild. With the
                    // album driving, it is greyed only while the cover is being read.
                    enabled: root.albumDriving ? !AlbumScheme.extracting
                                               : (!ColorScheme.busy && !ColorScheme.settled)
                    iconAngle: root.regenSpin ? root._regenPhase : 0
                    onActivated: root.doRegen()
                }
                // Always here. Lit = colours are held against the wallpaper (a scheme
                // applied now persists); unlit = a scheme applied now is temporary.
                // Click locks what is showing, or releases back to the wallpaper.
                ChipButton {
                    symbol:  ColorScheme.locked ? "lock" : "lock_open"
                    on:      ColorScheme.locked
                    tint:    root.accent
                    enabled: !ColorScheme.busy
                    onActivated: ColorScheme.toggleLock()
                }
            }

            // ── Group 2: editor mode + debug ──────────────────────────────────
            // A lit chip IS the on state — the debug log, or the editor mode in use.
            // Picking a mode also brings you back to the editor.
            ChipTray {
                groupShown: !root.showProgress && !root.picking

                ChipButton {
                    symbol:  "terminal"
                    on:      Config.colorApplyDebug
                    tint:    root.accent
                    onActivated: Config.colorApplyDebug = !Config.colorApplyDebug
                }
                ChipButton {
                    symbol:  "palette"
                    fillIcon: false          // filled, the paint dots turn to a blob
                    on:      root.view === "edit" && root.mode === "simple"
                    tint:    root.accent
                    onActivated: { root.mode = "simple"; root.view = "edit" }
                }
                ChipButton {
                    symbol:  "format_list_bulleted"
                    on:      root.view === "edit" && root.mode === "advanced"
                    tint:    root.accent
                    onActivated: { root.mode = "advanced"; root.view = "edit" }
                }
            }
        }

        // ══ Palette | Presets | Album ════════════════════════════════════════
        // The primary switch (SegmentSwitch: a pill, with a filled indicator that slides to the
        // chosen segment on a spring). Presets and Album each get a first-class tab rather
        // than being a mode or a header toggle — both are frequent destinations, and
        // Album carries its own configuration now. Album's icon stays filled while the music
        // is driving the shell, so "something is live in there" shows from any tab.
        SegmentSwitch {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.rightMargin: root.contentPad
            visible: !root.showProgress && !root.picking
            accent: root.accent
            model: [
                { value: "edit",    label: root.mode === "advanced" ? "Slots" : "Palette",
                  icon: root.mode === "advanced" ? "format_list_bulleted" : "palette",
                  fillIcon: root.mode === "advanced" },     // chosen, the paint dots of `palette` fill in to a blob
                { value: "library", label: "Presets", icon: "bookmarks" },
                { value: "album",   label: "Album",   icon: "music_note", lit: AlbumScheme.active }
            ]
            current: root.view
            onPicked: function (v) { root.view = v }
        }

        // ══ WORKBENCH — build a palette ══════════════════════════════════════
        // A flat container, no outline — the wallpaper hero's treatment: the card is a ground
        // for the controls, not a frame round them.
        ColorSchemeWorkbench {
            id: workbench
            panel: root
        }

        // ══ LIBRARY — saved schemes, their own tab ══════════════════════════
        // Each card is a miniature of the palette it holds — ITS background, its name in ITS
        // text colour, a ribbon of its colours — so a preset reads as what it will look like and
        // not as a label. Kept tight: the ribbon sits right under the name, and the card is only as
        // tall as the two. The loaded one wears the ring (as the editor's swatches do). Edit and
        // delete spring in over the card's right edge under the pointer — the name and ribbon give
        // way — and delete asks twice (ArmLatch). With a handful of schemes, search and sort appear.
        ColorSchemeLibrary {
            id: libraryPane
            panel: root
        }

        // ══ WORKSPACES — which ones wear the scheme right-clicked ════════════
        WorkspacePicker {
            id: picker
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.rightMargin: root.contentPad
            visible: root.picking
            shown: root.picking
            scheme: root.pickingAlbum ? "" : root.pickingName
            album: root.pickingAlbum
            onApplied: list => {
                if (root.pickingAlbum) { Config.albumWorkspaces = list.slice(); root.pickingAlbum = false }
                else ColorScheme.assign(root.pickingName, list)
            }
            onCancelled: { if (root.pickingAlbum) root.pickingAlbum = false; else ColorScheme.cancelPick() }
        }

        // ══ ALBUM — follow the cover, and how far it reaches ═════════════════
        ColorSchemeAlbum {
            id: albumPane
            panel: root
        }

        // ══ Progress — replaces the editor / library while a run is in flight ═
        Flickable {
            id: progressPane
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Math.min(progressCol.implicitHeight, 260)
            contentHeight: progressCol.implicitHeight
            clip: true
            interactive: root.showProgress
            visible: root.showProgress

            ColumnLayout {
                id: progressCol
                width: progressPane.width
                spacing: 1

                RowLayout {
                    Layout.fillHeight: false
                    Layout.fillWidth: true
                    Layout.bottomMargin: Tokens.spacingXs
                    spacing: Tokens.spacingSm

                    BusyDot { running: ColorScheme.busy; tint: Colors.of(QsWindow.window).primary }
                    StyledText {
                        Layout.fillWidth: true
                        text: ColorScheme.busy
                            ? (ColorScheme.runner.label || "Applying") + "…"
                            : ColorScheme.runner.failedCount > 0
                            ? ColorScheme.runner.failedCount + " step"
                              + (ColorScheme.runner.failedCount !== 1 ? "s" : "") + " failed"
                            : "The run stopped early"
                        variant: "caption"
                        font.weight: Font.DemiBold
                        color: ColorScheme.busy ? Colors.of(QsWindow.window).fg : Colors.of(QsWindow.window).warning
                        elide: Text.ElideRight
                    }
                    PanelButton {
                        variant: "ghost"; accent: Colors.of(QsWindow.window).primary
                        symbol: root.showDetails ? "keyboard_arrow_up" : "keyboard_arrow_down"
                        label: Translation.tr("Details")
                        onActivated: root.showDetails = !root.showDetails
                    }
                    PanelButton {
                        visible: !ColorScheme.busy
                        variant: "ghost"; accent: Colors.of(QsWindow.window).primary
                        label: Translation.tr("Dismiss")
                        onActivated: ColorScheme.runner.clearResult()
                    }
                }

                Repeater {
                    model: root.showDetails ? ColorScheme.runner.steps : []
                    delegate: RowLayout {
                        id: stepRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Tokens.spacingSm

                        MaterialIcon {
                            name: stepRow.modelData.status === "ok"   ? "check"
                                : stepRow.modelData.status === "fail" ? "close"
                                : stepRow.modelData.status === "skip" ? "sleep"
                                : "hourglass_empty"
                            color: stepRow.modelData.status === "ok"   ? Colors.of(QsWindow.window).success
                                 : stepRow.modelData.status === "fail" ? Colors.of(QsWindow.window).danger
                                 : Colors.of(QsWindow.window).fgDim
                            variant: "caption"
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: stepRow.modelData.text
                            variant: "caption"
                            emphasis: stepRow.modelData.status === "skip" ? "dim" : "normal"
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        // ══ Footer ══════════════════════════════════════════════════════════
        // Pills end to end: where the palette on screen comes from, a tray of the secondary
        // actions, and Apply as the one filled chip (the same look as SegmentSwitch's indicator).
        RowLayout {
            id: footer
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.view === "edit" && !root.showProgress
            spacing: Tokens.spacingMd

            readonly property bool staged:    root.mode === "advanced" && root.draftCount > 0
            readonly property bool showState: Config.wallTheming
                                              && (root.paletteKey !== "" || AlbumScheme.active)

            // A beat behind the card above it.
            ViewEnter { target: footer; active: footer.visible; delay: Motion.stagger * 5 }

            ChipTray {
                groupShown: footer.staged
                ChipButton {
                    symbol: "undo"
                    label:  Translation.tr("Discard")
                    tint:   root.accent
                    onActivated: root.discardDraft()
                }
            }

            // ── Where the palette on screen comes from ─────────────────────
            // "Album cover" while the music is driving the shell (the seeds above are
            // the cover's colours then — Save keeps them as a preset); otherwise
            // "Custom" = a palette saved for this wallpaper/scene, "Native" = pywal's
            // extraction. Fills the row as its flexible element. When what it says changes
            // (a new wallpaper, the album taking over) the line is replaced rather than
            // rewritten in place (SwapFade, keeping its own copy of what it shows).
            Rectangle {
                id: statusChip
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.iconXl + Tokens.spacingMd
                visible: footer.showState && !footer.staged
                radius: height / 2
                color: Colors.of(QsWindow.window).surfaceContainer

                readonly property bool album:    AlbumScheme.active
                readonly property bool accented: statusChip.album || root.wpHasPalette
                readonly property string glyphName: statusChip.album ? "music_note"
                    : root.wpHasPalette ? "palette" : "format_paint"
                readonly property string msg: statusChip.album
                    ? "Album cover colours"
                    : (root.wpHasPalette ? "Custom scheme" : "Native scheme")
                      + " · " + (root.sceneOnScreen
                                 ? WallpaperEngine.titleFor(root._sceneId)
                                 : Wallpaper.current)

                property string shownMsg:      ""
                property string shownGlyph:    ""
                property bool   shownAccented: false
                Component.onCompleted: {
                    statusChip.shownMsg      = statusChip.msg
                    statusChip.shownGlyph    = statusChip.glyphName
                    statusChip.shownAccented = statusChip.accented
                }

                SwapFade {
                    target:   statusRow
                    key:      statusChip.msg
                    shownKey: statusChip.shownMsg
                    onSwapped: {
                        statusChip.shownMsg      = statusChip.msg
                        statusChip.shownGlyph    = statusChip.glyphName
                        statusChip.shownAccented = statusChip.accented
                    }
                }

                RowLayout {
                    id: statusRow
                    anchors.fill: parent
                    anchors.leftMargin:  Tokens.spacingLg
                    anchors.rightMargin: Tokens.spacingLg
                    spacing: Tokens.spacingSm

                    MaterialIcon {
                        name: statusChip.shownGlyph
                        fill: statusChip.shownAccented && statusChip.shownGlyph !== "palette" ? 1 : 0
                        color: statusChip.shownAccented ? root.accent : Colors.of(QsWindow.window).fgDim
                        variant: "caption"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: statusChip.shownMsg
                        variant: "caption"; emphasis: "dim"; elide: Text.ElideRight
                    }
                }
            }
            Item { Layout.fillWidth: true; visible: footer.staged || !footer.showState }

            // ── Bind / reset — one tight tray ──────────────────────────────
            ChipTray {
                groupShown: footer.showState && !footer.staged
                ChipButton {
                    visible: root.wpHasPalette
                    symbol:  "restart_alt"
                    label:   Translation.tr("Use native")
                    tint:    root.accent
                    enabled: !ColorScheme.busy
                    onActivated: ColorScheme.clearWallpaperPalette(root.paletteKey,
                                                                   root.sceneOnScreen)
                }
                ChipButton {
                    symbol:  "wallpaper"
                    label:   root.wpHasPalette
                           ? "Update saved"
                           : ("Save for this " + (root.sceneOnScreen ? "scene" : "wallpaper"))
                    tint:    root.accent
                    enabled: !ColorScheme.busy
                    onActivated: ColorScheme.saveWallpaperPalette(root.paletteKey, root.pending,
                                                                  root.sceneOnScreen)
                }
            }

            ChipTray {
                // Hold to wear the pending scheme on the whole shell; let go and it is gone
                // (ColorScheme.peek — a preview layer, nothing written).
                ChipButton {
                    symbol: "visibility"
                    label:  Translation.tr("Peek")
                    on:     ColorScheme.peeking
                    tint:   root.accent
                    enabled: !ColorScheme.busy
                    onPressedChanged: if (pressed) ColorScheme.peek(root.pending); else ColorScheme.endPeek()
                }
                // After a landed apply it turns into a tick (Verdict: the one "it worked" colour that
                // does not follow the wallpaper) and settles back.
                ChipButton {
                    symbol: root.justApplied ? "check" : "palette"
                    fillIcon: false          // filled, the paint dots turn to a blob
                    on:     true
                    tint:   root.justApplied ? Verdict.tint(true) : root.accent
                    label:  root.justApplied
                          ? "Applied"
                          : root.mode === "simple"
                          ? "Apply scheme"
                          : root.draftCount > 0
                          ? "Hold " + root.draftCount + " colour" + (root.draftCount !== 1 ? "s" : "")
                          : "Re-apply"
                    enabled: !ColorScheme.busy
                    onActivated: root.applyCurrent()
                }
            }
        }
    }
}
