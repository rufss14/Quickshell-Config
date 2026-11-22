pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/palette.js" as Palette
import "colorscheme"

// ── ColorSchemePanel ──────────────────────────────────────────────────────────
// The colour scheme page: build a palette, choose one you saved, let the album paint the shell.
//
// ── Laid out like the wallpaper page ──────────────────────────────────────────
// A column on the LEFT: the loud card (`SchemeWorn`: the palette being built, drawn as the island wears it,
// with light / dark over it and four tools under it) and under it the source rail (`SourceRail`: Palette,
// Presets, Album, Gradient, a sliding pill, each with a figure of its own). The page on show takes the rest:
// `SchemeEditor` (Palette: four colour cards or every slot, the picker, save, peek, Apply),
// `SchemePresets` (cards that are miniatures of what they wear, in three groups), `SchemeAlbum` (the cover
// on a canvas, then where it reaches) and `SchemeGradient` (the bar and islands painted as a gradient). A
// failed apply, or any apply with the log on, takes the page's place (`SchemeProgress`); a question about
// workspaces does too (components/WorkspacePicker).
// How it should look and feel is docs/island-style.md.
//
// ── All logic lives in the ColorScheme service ────────────────────────────────
// The apply pipeline is `scripts/reload-theme.sh`, shared with the wallpaper gallery, driven by `ColorScheme`.
// Colour maths is in `services/palette.js`. This file holds the EDITOR's state (the four seeds, the staged
// slots, undo, ripple, light and dark kept while away) and the views read it through `panel`.
//
// ── Anything you set by hand is held ──────────────────────────────────────────
// Four colours derive a whole palette from four seeds; Every slot edits individual slots. Both write the same
// overrides file, so both survive wallpaper changes, and "Release" undoes either. Held colours are always
// visible (a pin) and always clearable.
//
// ── A scheme per workspace ────────────────────────────────────────────────────
// The workspaces tool of a card in Presets (or a right press on it) folds the page into
// components/WorkspacePicker, which asks which workspaces wear it. Those wear it, the shell on the screen
// showing one and the apps on it, as a workspace's own wallpaper's colours do (services/WorkspaceTheme), in
// memory, with no theming run. A card shows the workspaces wearing it.
//
// ── This wallpaper's palette ──────────────────────────────────────────────────
// The wallpaper tool of the loud card binds the built palette to whatever is on screen (keyed by basename, or
// "scene_<id>" for a Wallpaper Engine scene). Pressed again with nothing changed, it erases the binding and
// regenerates the original with pywal. Handled by ColorScheme + apply-wallpaper.sh's step 1c.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    // Reached by the view files in colorscheme/.
    property alias savedTimer: savedTimer

    // ── As an island page ─────────────────────────────────────────────────────
    // On the island (IslandCard) it has no outer padding: the rail names it and the card has its gutter. Off
    // it, in the bar's plain dock, it is the same page at the same size with a margin round it.
    property bool island: false
    readonly property int bodyW: 780
    readonly property int bodyH: 436
    readonly property int sideW: Math.round(root.bodyW / 3)

    // What the loud card says under its name: a question, a blocker, a run, else what this view is for.
    readonly property string headerLine: root.picking
             ? (root.pickingAlbum ? Translation.tr("Which workspaces follow the album?") : Translation.tr("Which workspaces wear it? The others keep theirs."))
             : root.blocked !== ""
             ? root.blocked
             : root.applyingQuiet
             ? ((ColorScheme.runner.label || Translation.tr("Applying")) + "…")
             : (root.view === "edit" && root.fallbackNote !== "")
             ? root.fallbackNote
             : root.view === "gradient"
             ? (Config.barGradient?.on === true ? Translation.tr("The bar and the islands wear a gradient")
                                                : Translation.tr("A gradient across the bar and the islands"))
             : root.view === "album"
             ? AlbumScheme.reasonText
             : (AlbumScheme.active || AlbumScheme.reason === "held")
             ? AlbumScheme.reasonText
             : root.view === "library"
             ? Translation.tr("%1 saved, %2 classics").arg(ColorScheme.presets.length).arg(ColorScheme.classics.length)
             : root.editorDiffers
             ? (root.mode === "simple" ? Translation.tr("Not applied yet")
                : root.draftCount === 1 ? Translation.tr("1 unsaved change") : Translation.tr("%1 unsaved changes").arg(root.draftCount))
             : root.mode === "simple"
             ? Translation.tr("Four colours make the whole palette")
             : Translation.tr("Pick a slot to hold it")
    // A page of one size, as the wallpaper page is (`body` in config/islands.js says the same to the island).
    implicitWidth:  root.bodyW + (root.island ? 0 : Tokens.spacingMd * 2)
    implicitHeight: root.bodyH + (root.island ? 0 : Tokens.spacingMd * 2)

    property string view: "edit"            // "edit" | "library" | "album" | "gradient"
    property string mode: "simple"          // "simple" | "advanced"

    // One accent for the whole panel — every highlight below follows it, as WallpaperPanel's does.
    readonly property color accent: Colors.of(QsWindow.window).primary

    // The views reach the fields' keys and the typed name through these (the editor holds the fields).
    signal nameWanted(string name)
    signal fieldsBlurRequested()
    // A scheme put on straight from Presets does not carry you to the editor.
    property bool holdView: false

    // ── What the palette is bound to right now ───────────────────────────────
    // A scene covers the still wallpaper completely, so while one runs the "this
    // wallpaper" controls act on the SCENE, keyed "scene_<id>" — the still's name
    // would be wrong. Acquire holds WallpaperEngine's poll while the panel is open.
    Component.onCompleted: {
        WallpaperEngine.acquire()
        // `qs ipc call island part colorScheme library`: open on a view (edit | slots | library | album).
        const part = UiState.islandPartFor("colorScheme")
        if (root.island && part !== "") {
            root.mode = part === "slots" ? "advanced" : "simple"
            root.view = part === "slots" ? "edit" : part
        }
    }
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
        { key: "seedBg", label: Translation.tr("Background"), value: root.seedBg },
        { key: "seedFg", label: Translation.tr("Text"),       value: root.seedFg },
        { key: "seedA",  label: Translation.tr("Accent"),     value: root.seedA  },
        { key: "seedB",  label: Translation.tr("Accent 2"),   value: root.seedB  }
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
    readonly property int libToolsFrom: 6     // schemes it takes before search and sort appear (the classics alone reach it)
    // Groups folded away on the Presets view ("mine", "classic"): kept while the panel lives.
    property var folded: ({})
    function isFolded(group) { return root.folded[group] === true }
    function fold(group) {
        const next = Object.assign({}, root.folded)
        next[group] = !next[group]
        root.folded = next
    }
    property string libQuery: ""
    property string libSort:  "name"          // "name" | "recent"
    // Starred schemes float to the front, in the order chosen (like the wallpaper gallery's favourites).
    property bool libStarOnly: false
    // The Presets tab is three groups: the wallpaper's own colours (pywal), the schemes you saved (in the order
    // chosen) and the classics the shell ships (ColorScheme.classics: fixed order, not renamed or deleted). A
    // star floats a scheme up within its group.
    function _starredFirst(all) {
        const stars = Config.colorFavorites
        return all.filter(p => stars.indexOf(p.name) >= 0).concat(all.filter(p => stars.indexOf(p.name) < 0))
    }
    readonly property var mySchemes: root._starredFirst(root.libSort === "recent"
        ? ColorScheme.presets.slice().sort((a, b) => b.mtime - a.mtime)
        : ColorScheme.presets.slice())
    readonly property var classicSchemes: root._starredFirst(ColorScheme.classics)
    function presetMatches(name) {
        if (root.libStarOnly && Config.colorFavorites.indexOf(name) < 0) return false
        const q = root.libQuery.trim().toLowerCase()
        return q === "" || name.toLowerCase().indexOf(q) >= 0
    }
    readonly property int libMatchesMine:    root.mySchemes.filter(p => root.presetMatches(p.name)).length
    readonly property int libMatchesClassic: root.classicSchemes.filter(p => root.presetMatches(p.name)).length
    // The wallpaper row has no name to star or sort: it answers its own words, and not the star filter.
    readonly property bool libWallShown: !root.libStarOnly && (root.libQuery.trim() === ""
        || "from your wallpaper pywal generated".indexOf(root.libQuery.trim().toLowerCase()) >= 0)
    readonly property int libMatches: root.libMatchesMine + root.libMatchesClassic + (root.libWallShown ? 1 : 0)

    // ── Harmony: Accent 2 from Accent ─────────────────────────────────────────
    // Four ways to pick a second colour that goes with the first, named by what they LOOK like and in
    // order of how far round the colour wheel they go: Similar (30°), Triad (120°), Split (150°),
    // Opposite (180°). Applying one sets Accent 2 to its partner of Accent (kept legible on the
    // background — palette.js `partner`, tested) and selects Accent 2 so the change is where you are
    // looking. Each chip carries a dot of the colour it would give, and stays lit while Accent 2 IS that
    // partner — the dots are the explanation; there is no caption.
    readonly property var harmonies: [
        { kind: "analogous",     label: Translation.tr("Similar")  },
        { kind: "triad",         label: Translation.tr("Triad")    },
        { kind: "split",         label: Translation.tr("Split")    },
        { kind: "complementary", label: Translation.tr("Opposite") }
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
        ? Translation.tr("Only has %1. Save to add a %2 version.")
            .arg(ColorScheme.loadedMode === "light" ? Translation.tr("Light") : Translation.tr("Dark"))
            .arg(Config.themeMode === "light" ? Translation.tr("Light") : Translation.tr("Dark"))
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
            ? Translation.tr("%1 needs a restart").arg(ColorScheme.runner.restartApps[0].label)
            : Translation.tr("%1 apps need a restart").arg(ColorScheme.runner.restartApps.length))
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
            if (!root.holdView) root.view = "edit"
            root.nameWanted(name)
        }
    }

    // A press anywhere lets go of the fields' keys, as a click outside a text box does.
    MouseArea {
        anchors.fill: parent
        propagateComposedEvents: true
        onPressed: function(mouse) {
            root.fieldsBlurRequested()
            mouse.accepted = false
        }
    }

    Item {
        id: frame
        anchors.fill: parent
        anchors.margins: root.island ? 0 : Tokens.spacingMd

        // ══ The left column: the palette worn, and where to go ═══════════════════
        ColumnLayout {
            id: sideCol
            width: root.sideW
            height: parent.height
            spacing: Tokens.spacingMd

            SchemeWorn {
                Layout.fillWidth: true
                Layout.fillHeight: true
                panel: root
                opacity: root.picking ? 0.4 : 1
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            }
            SourceRail {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: 4 * (Tokens.iconXl + Tokens.spacingMd) + Tokens.spacingSm * 2 + Tokens.spacingXs * 2
                opacity: root.picking ? 0.4 : 1
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                current: root.view
                model: [
                    { value: "edit",    label: Translation.tr("Palette"), icon: "palette",   shape: "cookie9",
                      figure: root.contrastGrade, big: false },
                    { value: "library", label: Translation.tr("Presets"), icon: "bookmarks", shape: "clover",
                      figure: String(ColorScheme.presets.length + ColorScheme.classics.length) },
                    { value: "album",   label: Translation.tr("Album"),   icon: "music_note", shape: "sunny",
                      figure: Config.albumScheme ? Translation.tr("On") : Translation.tr("Off"), big: false,
                      live: AlbumScheme.active },
                    { value: "gradient", label: Translation.tr("Gradient"), icon: "opacity", shape: "burst",
                      figure: Config.barGradient?.on === true ? Translation.tr("On") : Translation.tr("Off"), big: false,
                      live: Config.barGradient?.on === true }
                ]
                onPicked: function (v) { root.view = v }
            }
        }

        // ══ The page on show ═════════════════════════════════════════════════════
        Item {
            id: pageArea
            anchors.left: sideCol.right
            anchors.leftMargin: Tokens.spacingMd
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            SchemeEditor {
                id: editor
                anchors.fill: parent
                panel: root
            }
            SchemePresets {
                anchors.fill: parent
                panel: root
            }
            SchemeAlbum {
                anchors.fill: parent
                panel: root
            }
            SchemeGradient {
                anchors.fill: parent
                panel: root
            }
            SchemeProgress {
                anchors.fill: parent
                panel: root
            }
            // Which workspaces wear the scheme (or follow the album): the page folds into the picker.
            WorkspacePicker {
                id: picker
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
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
        }
    }
}
