import Quickshell
import Quickshell.Io
import QtQuick
import "layout.js" as Layout
import "modules.js" as Catalogue
import "surfaces.js" as Surfaces
// ConfigBarLayout — part of Config, split out of Config.qml by area (2026-11-08). The parts form
// one inheritance chain (ConfigShell ← ConfigEdges ← ConfigBarLayout ← ConfigSystem ←
// ConfigDesktop ← Config), so every property still lives on the one `Config` singleton
// and nothing that reads `Config.x` changed. A name declared further down the chain is
// reached as `root.x` here (a base file can't see it statically; `root` is the same object).
ConfigEdges {
    id: root

    // ══ Bar — the layout ══════════════════════════════════════════════════════
    // Region → groups → module ids. A group is a cluster sharing one pill; the bar
    // renders exactly this, so what you see here is what's on screen.
    //
    // ── Membership IS visibility ──────────────────────────────────────────────
    // There is no separate on/off map any more. A module in the layout is shown, a
    // module absent from it is not, and that's the whole rule. The previous design had
    // `modules` (an on/off map) beside a fixed order baked into Bar.qml, which meant
    // order, grouping and visibility were three facts that could disagree with each
    // other — and only one of them was editable. One list can't contradict itself.
    //
    // Anything in `moduleList` but not in `layout` is what the settings page offers in
    // its "available" pool. That falls out of the model rather than being tracked.
    //
    // ── Replaced, never mutated ───────────────────────────────────────────────
    // Every mutator below rebuilds the structure and assigns it. Mutating in place
    // wouldn't fire the change signal, and the bar would quietly keep the old layout —
    // this is the single most important rule in this file.
    //
    // ── The algebra itself lives in config/layout.js ──────────────────────────
    // Everything below is a wrapper: it passes `layout` in and assigns what comes back.
    // Those transformations are pure functions over plain data, which is what makes
    // them testable — `bun scripts/test-layout.js`, 36 cases. The two that needed it
    // most are reconcile()'s removed-vs-new rule and moveIntoGroup()'s index
    // adjustment, and NEITHER can be verified by looking at the bar: one silently
    // resurrects a module you removed, the other is off by one in a single direction.
    //
    // The wrappers stay because `Config.moveIntoGroup(id, …)` is the API 95 files use.
    // Only the implementation moved.
    property var layout: Layout.defaultLayout()

    readonly property var regionIds: Layout.REGIONS

    function defaultLayout() { return Layout.defaultLayout() }

    // UI text, so it stays here — layout.js has no business knowing what a region is
    // called in English.
    function regionLabel(region) {
        return region === "left" ? "Left" : region === "centre" ? "Centre" : "Right"
    }

    // Still used by _snapshot(), which hands a preset its own copy of the layout.
    function _clone(l) { return Layout.clone(l, root.regionIds) }

    // moduleSettings/groupSettings are plain `{id: {key: value}}` maps, not the
    // region-shaped layout `_clone`/Layout.clone expects (it would flatten them to
    // `{}`). A JSON round-trip is enough — every value in here is a string, bool,
    // or number.
    function _cloneFlatSettings(m) { return JSON.parse(JSON.stringify(m ?? {})) }

    // Returns { region, group, index } or null. The drag UI and the bar both need to
    // answer this, and neither should be scanning the structure by hand.
    function locate(id)   { return Layout.locate(root.layout, id, root.regionIds) }
    function isPlaced(id) { return root.locate(id) !== null }
    // The dock on either surface. `dockEnabled` (ConfigEdges) stays "the dock on the
    // SIDEBAR" — the sidebar's host, its reserve and its window cell read it; what the
    // dock needs wherever it is (the apps' badge feed, LauncherEntry) reads this.
    readonly property bool dockPlaced: root.dockEnabled || root.isPlaced("dock")

    readonly property var availableModules:
        root.moduleList.filter(m => !root.isPlaced(m.id))

    // ── Mutators ──────────────────────────────────────────────────────────────
    // Each is "transform, then assign". The assignment is what fires the change signal
    // the bar is bound to, and it is the entire reason these are wrappers rather than
    // direct calls at the call site.
    function moveToOwnGroup(id, region, groupIndex) {
        root._leaveSidebar(id)
        root.layout = Layout.moveToOwnGroup(root.layout, id, region, groupIndex, root.regionIds)
    }

    function moveIntoGroup(id, region, groupIndex, index) {
        root._leaveSidebar(id)
        root.layout = Layout.moveIntoGroup(root.layout, id, region, groupIndex, index, root.regionIds)
    }

    function removeModule(id) {
        root.layout = Layout.removeModule(root.layout, id, root.regionIds)
    }

    // `null` means there was nothing to do — an unknown id, or one already on the bar.
    // Skipping the assignment skips the change signal, and the write, with it.
    function addModule(id) {
        const next = Layout.addModule(root.layout, id, root.moduleList, root.regionIds)
        if (!next) return
        root._leaveSidebar(id)
        root.layout = next
    }

    // ══ Bar — the module catalogue ════════════════════════════════════════════
    // Metadata only: what a module IS, never where it sits. `home` is just where
    // addModule() puts it when it comes back from the pool.
    //
    // The description is here rather than in the settings page because it's a fact
    // about the module, and the page is a view. It also means adding a module is one
    // entry in one list.
    readonly property var moduleList: Catalogue.forSurface("bar")

    function moduleInfo(id) {
        return root.moduleList.find(m => m.id === id) ?? null
    }

    // ── Which surface, and putting a module on one ────────────────────────────
    // "bar" | "side" | "" (off). A module has one place (modules.js), so this is an
    // answer, not a list.
    function surfaceOf(id) {
        return root.isPlaced(id) ? "bar" : root.sidebarPlaced(id) ? "side" : ""
    }
    // "bar" | "side" → its home on that surface (each add takes it off the other);
    // anything else → off both. No-op for a surface it has no form on.
    function placeModule(id, surface) {
        if (surface === "bar")       root.addModule(id)
        else if (surface === "side") root.sidebarAdd(id)
        else { root.removeModule(id); root.sidebarRemove(id) }
    }

    // ══ Bar — presets ═════════════════════════════════════════════════════════
    // A named snapshot of everything on the Bar page. Stored as a plain array of
    // { name, config } rather than a map, because the settings page renders them in
    // order and a map has no order to render.
    //
    // Saving under an existing name replaces it — that's what "save" means when the
    // name is the identity, and a confirm dialog for something this reversible would
    // be ceremony.
    // ── The built-in ──────────────────────────────────────────────────────────
    // "Default" is always in the list and can't be deleted — it's the way back, and a
    // way back you can delete isn't one. It's computed from defaultLayout() rather than
    // stored, so it can never drift from what Reset does.
    readonly property string defaultPresetName: "Default"

    readonly property var defaultPreset: ({
        name: root.defaultPresetName,
        builtin: true,
        config: {
            barShape:        false,
            // Rufss's own tuned bar, hand-picked as the shipped default — see
            // presets/bar.json's "Rufss" entry, which this now matches. A literal here
            // (58, 17, ...) rather than a Token because these are one preset's specific
            // choices, not shell-wide design constants; Tokens.borderChrome stays
            // symbolic because it already tracks the live Hyprland border size and
            // happens to equal the same number.
            barThickness:    58,
            barRoundness:    17,
            barInset:        Tokens.barMargin,     // 4, == Rufss
            barBorderWidth:  Tokens.borderChrome,
            barOpacity:      0.98,                 // == Rufss
            barCentreAnchor: true,
            barFontScale:    1.18,
            barIconScale:    1.32,
            barInnerPill:    true,
            screenFrame:     true,
            barLayout:       "unifiedAnchored",
            frameThickness:  12,
            frameRoundness:  22,
            frameBorderWidth: Tokens.borderChrome,
            motionEnabled:   true,
            barHoverGrow:    true,
            motionScale:     1.0,
            layout:          root.defaultLayout(),
            barHero:         "clock",
            moduleSettings:  {},
            groupSettings:   {},
            panelPlacement:  {},
            panelZoom:       {}
        }
    })

    // What the page renders: the built-in first, then whatever you've saved.
    readonly property var allPresets: [root.defaultPreset].concat(root.presets)

    property var presets: []

    // ══ Shell presets — the WHOLE config, portable ════════════════════════════
    // A bar preset (above) is one page's worth of settings. A SHELL preset is every
    // persisted preference — exactly what `_dumpPrefs()` writes to config.json — saved
    // under a name in `presets/shell.json`.
    //
    // ── Why it lives in the repo dir ─────────────────────────────────────────
    // Same place, and the same reasoning, as `presets/bar.json`: written only on Save,
    // meant to be read, committed and shared. The live config.json is in the STATE dir
    // because it churns on every slider drag; a shell preset does not. Move to another
    // machine = commit `presets/shell.json`, `git pull` there, Apply in Settings →
    // Shell preset.
    //
    // Does NOT carry saved bar presets (`presets/bar.json`) or desktop-widget placement
    // (`widgets.json`) — those are their own files with their own portability. The
    // Shell preset page says so.
    property var shellPresets: []

    // The built-in Shell preset, shipped in presets/shell.json. Reserved: it can't be
    // overwritten, renamed or deleted from the UI, and it's applied once on a fresh
    // profile (see _maybeApplyDefaultPreset) so a new clone lands on the intended setup
    // rather than the bare property defaults.
    readonly property string defaultShellPresetName: "Default"

    // Stamped after the one-time check below, so it never runs twice and never fights a
    // later hand edit. Persisted.
    property bool defaultPresetApplied: false

    // True only when config.json was absent/empty at startup — a genuine first boot.
    // Set in prefsStore.onLoaded before the migrating write-back fills the document.
    property bool _firstBoot: false

    // On the very first boot, apply the built-in preset so a fresh clone lands on the
    // intended setup rather than the bare property defaults. Runs once — the flag is
    // stamped either way, so an existing config is never disturbed. Called from each
    // store's onLoaded because prefs and shellPresets can settle in either order.
    function _maybeApplyDefaultPreset() {
        if (root.defaultPresetApplied) return
        if (!root.prefsLoaded || !root._shellPresetsStore.ready) return
        root.defaultPresetApplied = true
        const p = root.shellPresets.find(x => x.name === root.defaultShellPresetName)
        if (root._firstBoot && p && p.config) root.applyShellPreset(root.defaultShellPresetName)
        else root._writePrefs()   // nothing applied, but persist the flag
    }

    // Build one from the current live config. `version` is stamped so the page can flag
    // a preset saved by an older shell.
    function saveShellPreset(name) {
        const trimmed = (name ?? "").trim()
        // The built-in name is reserved — same contract as the bar presets' "Default".
        if (trimmed === "" || trimmed === root.defaultShellPresetName) return
        const next = root.shellPresets.filter(p => p.name !== trimmed)
        next.push({ name: trimmed, version: root.version, config: root._dumpPrefs() })
        next.sort((a, b) => a.name.localeCompare(b.name))
        root.shellPresets = next
    }

    // Apply one. `_applyPrefsDoc` is the same loop `prefsStore.onLoaded` runs, so every
    // setting falls back to its current value — a preset from an older shell just leaves
    // newer settings alone. Live bindings pick the changes up; no reload needed, same as
    // `loadPreset`. The write-back persists the result to config.json.
    function applyShellPreset(name) {
        const p = root.shellPresets.find(x => x.name === name)
        if (!p || !p.config) return
        root._loading = true
        root._applyPrefsDoc(p.config)
        root._loading = false
        root._writePrefs()
    }

    // ── A look file (services/Look.qml, services/look.js) ─────────────────────
    // `style`: { property: value }, every key vetted against look.js's whitelist; `bar`: a
    // bar snapshot or null. One write at the end, like applyShellPreset.
    //
    // The user's MOTION settings are kept: loadPreset falls back to the default for a key the
    // snapshot lacks, and a look carries no motion, so without this an import would turn
    // animations back on for someone who had switched them off.
    function applyLook(style, bar) {
        root._loading = true
        if (bar) root._applyBarSnapshot(Object.assign({}, bar,
            { motionEnabled: root.motionEnabled, motionScale: root.motionScale }))
        for (const k in style) if (root[k] !== undefined) root[k] = style[k]
        root._loading = false
        root._writePrefs()
    }

    // Puts every preference back to a `_dumpPrefs()` taken before applyLook (its undo).
    function restorePrefs(doc) {
        if (!doc) return
        root._loading = true
        root._applyPrefsDoc(doc)
        root._loading = false
        root._writePrefs()
    }

    function deleteShellPreset(name) {
        if (name === root.defaultShellPresetName) return
        root.shellPresets = root.shellPresets.filter(p => p.name !== name)
    }

    // ── Putting one back ──────────────────────────────────────────────────────
    // For the settings page's undo. NOT saveShellPreset(name): that snapshots the
    // CURRENT preferences, so undoing a delete would silently replace the preset's
    // stored settings with whatever the machine happens to be set to now. This takes
    // the record that was deleted, exactly as it was.
    function restoreShellPreset(rec) {
        if (!rec || !rec.name || !rec.config) return
        if (root.shellPresets.some(p => p.name === rec.name)) return
        const next = root.shellPresets.slice()
        next.push({ name: rec.name, version: rec.version ?? root.version, config: rec.config })
        next.sort((a, b) => a.name.localeCompare(b.name))
        root.shellPresets = next
    }

    // Keeps the stored config, changes only the name — same contract as renamePreset:
    // not save-new-then-delete, which would re-snapshot the CURRENT config into it.
    function renameShellPreset(from, to) {
        const trimmed = (to ?? "").trim()
        if (trimmed === "" || trimmed === from) return
        if (from === root.defaultShellPresetName || trimmed === root.defaultShellPresetName) return
        if (root.shellPresets.some(p => p.name === trimmed)) return
        const i = root.shellPresets.findIndex(p => p.name === from)
        if (i === -1) return
        const next = root.shellPresets.map(p => p.name === from
            ? { name: trimmed, version: p.version, config: p.config }
            : p)
        next.sort((a, b) => a.name.localeCompare(b.name))
        root.shellPresets = next
    }

    // Does the live config match this preset? Canonical compare (key-order independent —
    // presets/shell.json is hand-editable), same `_canonical` the bar presets use.
    function shellPresetActive(name) {
        const p = root.shellPresets.find(x => x.name === name)
        return p ? root._canonical(p.config) === root._canonical(root._dumpPrefs()) : false
    }

    function _snapshot() {
        return {
            barShape:        root.barShape,
            // The raw preference, not the resolution-scaled value — a preset saved
            // on a 4K screen must not bake that screen's resScale into the number,
            // or loading it back on 1920x1080 would double-shrink the bar.
            barThickness:    root.barThicknessPref,
            barRoundness:    root.barRoundness,
            barInset:        root.barInsetPref,
            barBorderWidth:  root.barBorderWidth,
            barOpacity:      root.barOpacity,
            barCentreAnchor: root.barCentreAnchor,
            barFontScale:    root.barFontScalePref,
            barIconScale:    root.barIconScalePref,
            barInnerPill:    root.barInnerPill,
            screenFrame:     root.screenFrame,
            barLayout:       root.barLayout,
            frameThickness:  root.frameThickness,
            frameRoundness:  root.frameRoundness,
            frameBorderWidth: root.frameBorderWidth,
            motionEnabled:   root.motionEnabled,
            barHoverGrow:    root.barHoverGrow,
            motionScale:     root.motionScale,
            layout:          root._clone(root.layout),
            moduleSettings:  root._cloneFlatSettings(root.moduleSettings),
            groupSettings:   root._cloneFlatSettings(root.groupSettings),
            panelPlacement:  root._cloneFlatSettings(root.panelPlacement),
            panelZoom:       root._cloneFlatSettings(root.panelZoom),
            // Both surfaces travel with a preset (2026-11-08). Optional on the way in —
            // see _presetOptional — so a preset saved before leaves them alone.
            barHero:         root.barHero,
            sidebarHero:     root.sidebarHero,
            sidebarLayout:   Layout.clone(root.sidebarLayout, root.sidebarRegionIds),
            sidebarStyle:    root._cloneFlatSettings(root.sidebarStyle),
            sidebarIslands:  root.sidebarIslands,
            barMusicReact:   root.barMusicReact
        }
    }

    // Snapshot keys added after presets already existed: a preset that doesn't carry
    // one leaves that setting alone on load, and isn't compared on it (presetActive).
    readonly property var _presetOptional: ["barHero", "sidebarHero", "sidebarLayout",
                                            "sidebarStyle", "sidebarIslands", "barMusicReact"]

    function savePreset(name) {
        const trimmed = (name ?? "").trim()
        // The built-in name is reserved. Letting it be overwritten would leave no way
        // back to the default except Reset, which is the button this list exists to
        // make unnecessary.
        if (trimmed === "" || trimmed === root.defaultPresetName) return
        const next = root.presets.filter(p => p.name !== trimmed)
        next.push({ name: trimmed, config: root._snapshot() })
        next.sort((a, b) => a.name.localeCompare(b.name))
        root.presets = next
    }

    // ── Every field falls back to the built-in's ──────────────────────────────
    // A preset is only guaranteed to hold what its own version of this file knew how to
    // write. Presets saved before a setting existed simply don't mention it, and the
    // file is hand-editable so a key can go missing for less interesting reasons too. A
    // bare `c.barRoundness` would then assign `undefined` — which an int property reads as
    // 0 and a real one as NaN, so an old preset would silently flatten the bar instead
    // of leaving the setting alone.
    //
    // Falling back to defaultPreset rather than to the LIVE value on purpose: loading a
    // preset twice from different starting states has to land in the same place, or it
    // isn't a preset.
    function loadPreset(name) {
        const p = root.allPresets.find(x => x.name === name)
        if (!p) return
        root._applyBarSnapshot(p.config)
    }

    // The body of loadPreset, for a snapshot that doesn't come from the preset list: a look
    // file (applyLook). The caller has already checked the values' types (services/look.js).
    function _applyBarSnapshot(c) {
        const d = root.defaultPreset.config

        root.barShape        = c.barShape        ?? d.barShape
        root.barThicknessPref = c.barThickness    ?? d.barThickness
        root.barRoundness    = c.barRoundness    ?? d.barRoundness
        root.barInsetPref     = c.barInset        ?? d.barInset
        root.barBorderWidth  = c.barBorderWidth  ?? d.barBorderWidth
        root.barOpacity      = c.barOpacity      ?? d.barOpacity
        root.barCentreAnchor = c.barCentreAnchor ?? d.barCentreAnchor
        root.barFontScalePref = c.barFontScale    ?? d.barFontScale
        root.barIconScalePref = c.barIconScale    ?? d.barIconScale
        root.barInnerPill    = c.barInnerPill    ?? d.barInnerPill
        root.screenFrame     = c.screenFrame     ?? d.screenFrame
        // A pills shape, or no barLayout and the old frameMerge: its unified twin
        // (layout.js unifiedLayout), as the main config's _persisted entry does.
        root.barLayout       = Layout.unifiedLayout(c.barLayout, c.frameMerge)
        root.frameThickness  = c.frameThickness  ?? d.frameThickness
        root.frameRoundness  = c.frameRoundness  ?? d.frameRoundness
        root.frameBorderWidth = c.frameBorderWidth ?? d.frameBorderWidth
        root.motionEnabled   = c.motionEnabled   ?? d.motionEnabled
        root.barHoverGrow    = c.barHoverGrow    ?? d.barHoverGrow
        root.motionScale     = c.motionScale     ?? d.motionScale

        // Cloned on the way out as well as in: handing the live layout the preset's own
        // array would let a later edit to the bar rewrite the stored preset.
        root.layout          = root._clone(c.layout ?? d.layout)

        // Per-module settings (accent, inner-pill override, right-click persist state,
        // notifications' DND-only) are bar state exactly like layout is, so they travel
        // with the preset the same way — including on Reset, which is loadPreset(default)
        // and must clear a customised accent rather than leave it stuck.
        // Hero flags inside an old preset's moduleSettings become the bar's hero string
        // (surfaces.js) and are stripped; a preset that has the string just uses it.
        const ms = c.moduleSettings ?? d.moduleSettings ?? {}
        root.moduleSettings  = root._cloneFlatSettings(Surfaces.stripHeroFlags(ms))
        root.barHero         = typeof c.barHero === "string" ? c.barHero
                             : c.moduleSettings ? Surfaces.heroFromFlags(c.moduleSettings, c.layout ?? d.layout,
                                                                        root.regionIds, root._heroable)
                             : d.barHero

        // The sidebar only when the preset has it (Reset — the built-in — has neither,
        // so it never clears the sidebar). Reconciled like a loaded one, then the bar's
        // copy of any module on both wins: the preset's bar is what was just asked for.
        if (c.sidebarLayout && typeof c.sidebarLayout === "object")
            root.sidebarLayout = Layout.reconcile(c.sidebarLayout, [], root.sidebarModuleList,
                                                  root.sidebarRegionIds)
        if (typeof c.sidebarHero === "string") root.sidebarHero = c.sidebarHero
        if (c.sidebarStyle && typeof c.sidebarStyle === "object")
            root.sidebarStyle = Surfaces.cleanStyle(c.sidebarStyle)
        if (typeof c.sidebarIslands === "boolean") root.sidebarIslands = c.sidebarIslands
        if (typeof c.barMusicReact === "boolean")  root.barMusicReact  = c.barMusicReact
        root._dedupeSurfaces()

        // Per-group spacing overrides — see Config.groupSettings. Travels with the
        // preset exactly like moduleSettings, including on Reset.
        root.groupSettings   = root._cloneFlatSettings(c.groupSettings ?? d.groupSettings ?? {})

        // Which side each panel opens on — see Config.panelPlacement. Same reasoning:
        // it's bar state, so Reset (loadPreset(default)) has to clear an override
        // rather than leave a panel stuck on a side the built-in preset never chose.
        root.panelPlacement  = root._cloneFlatSettings(c.panelPlacement ?? d.panelPlacement ?? {})

        // Per-panel size overrides — see Config.panelZoom. Bar state like the two
        // above, so Reset clears it rather than leaving a panel at a size the
        // built-in preset never chose.
        root.panelZoom       = root._cloneFlatSettings(c.panelZoom ?? d.panelZoom ?? {})
    }

    function deletePreset(name) {
        if (name === root.defaultPresetName) return
        root.presets = root.presets.filter(p => p.name !== name)
    }

    // Rename keeps the preset's stored config and only changes what it's called — which
    // is the entire point, and why this isn't save-under-new-name-then-delete: that
    // would silently re-snapshot the CURRENT bar into the renamed preset and quietly
    // discard whatever was actually saved in it.
    //
    // Sorted after the rename for the same reason savePreset sorts: the list is rendered
    // in array order, so a renamed preset that kept its slot would sit out of place until
    // the next restart.
    function renamePreset(from, to) {
        const trimmed = (to ?? "").trim()
        if (trimmed === "" || trimmed === from) return

        // The built-in is computed, not stored — there's nothing to rename, and letting
        // a saved preset take the name would leave two entries called "Default" and no
        // way back to the real one.
        if (from === root.defaultPresetName || trimmed === root.defaultPresetName) return

        const i = root.presets.findIndex(p => p.name === from)
        if (i === -1) return

        // Renaming onto an existing name would produce two presets with the same
        // identity, and every lookup here is find-by-name. Refuse rather than merge.
        if (root.presets.some(p => p.name === trimmed)) return

        const next = root.presets.map(p => p.name === from
            ? { name: trimmed, config: p.config }
            : p)
        next.sort((a, b) => a.name.localeCompare(b.name))
        root.presets = next
    }

    // Stable, key-order-independent serialisation. See layout.js for why presets need
    // it: presets/bar.json is meant to be hand-edited, and reordering two keys there
    // must not stop a byte-identical preset from matching.
    function _canonical(v) { return Layout.canonical(v) }

    // Does the bar currently match this preset? Drives the "which one am I on"
    // indicator. Structural comparison because these are plain data all the way down,
    // and a hand-rolled deep-equal is a bug farm for something this shallow.
    function presetActive(name) {
        const p = root.allPresets.find(x => x.name === name)
        if (!p) return false
        // Retired hero flags in an old preset aren't a difference: loading strips them.
        const c = Object.assign({}, p.config)
        if (c.moduleSettings) c.moduleSettings = Surfaces.stripHeroFlags(c.moduleSettings)
        return Layout.presetMatches(c, root._snapshot(), root._presetOptional)
    }

    // Reset IS the built-in preset — same values, one definition. They drifted apart
    // once already; defining reset as "load the thing that can never drift" is what
    // stops it happening again.
    function resetBar() { root.loadPreset(root.defaultPresetName) }

    // ══ Bar — per-module settings ═════════════════════════════════════════════
    // moduleId → { accent, rightPersist, rightState }. Sparse, and read through the
    // accessors below: a module you've never touched has no entry at all, which is what
    // makes "reset this module" a delete rather than a hunt for the right defaults.
    //
    // Same replace-never-mutate rule as `layout`, for the same reason.
    property var moduleSettings: ({})

    function _moduleSetting(id, key, fallback) {
        const m = root.moduleSettings[id]
        return (m && m[key] !== undefined) ? m[key] : fallback
    }

    function setModuleSetting(id, key, value) {
        const next = {}
        for (const k in root.moduleSettings) next[k] = Object.assign({}, root.moduleSettings[k])
        if (!next[id]) next[id] = {}
        next[id][key] = value
        root.moduleSettings = next
    }

    function resetModule(id) {
        const next = {}
        for (const k in root.moduleSettings) if (k !== id) next[k] = root.moduleSettings[k]
        root.moduleSettings = next
    }

    function moduleCustomised(id) {
        const m = root.moduleSettings[id]
        return m !== undefined && Object.keys(m).length > 0
    }

    // ── Notifications module: show only while DND is on ───────────────────────
    // A per-module preference (stored in moduleSettings like accent/right-click):
    // when set, the notifications pill hides itself unless Do Not Disturb is
    // active — a discreet "DND is on" indicator rather than a permanent bell. The
    // bar's moduleVisible() reads this.
    function notifShowOnlyDnd() {
        return root._moduleSetting("notifications", "showOnlyDnd", false) === true
    }
    function setNotifShowOnlyDnd(v) {
        root.setModuleSetting("notifications", "showOnlyDnd", !!v)
    }

    // ── A module's panel: its title row ───────────────────────────────────────
    // Whether a module's panel opens with its PanelHeader (icon, two-word title, subtitle, actions) or goes
    // straight to its hero. On by default; off buys the height back. One setting per module (Settings ›
    // Modules › the module), stored in moduleSettings like accent and right-click. A panel whose header
    // carries its only actions keeps them: it shows the actions in a slim row instead (see each panel).
    function panelHeader(id) {
        return root._moduleSetting(id, "panelHeader", true) === true
    }
    function setPanelHeader(id, v) {
        root.setModuleSetting(id, "panelHeader", !!v)
    }
    function clockPanelHeader()      { return root.panelHeader("clock") }
    function gamemodePanelHeader()   { return root.panelHeader("gamemode") }
    function mixerPanelHeader()      { return root.panelHeader("volume") }
    function screentimePanelHeader() { return root.panelHeader("screentime") }

    // ── Accent ────────────────────────────────────────────────────────────────
    // A ROLE NAME, never a hex string. The brief is explicit that colour flows from the
    // wallpaper-derived palette and is never hardcoded — a colour picker here would let
    // you pin #ff0000 into the config and it would survive every future wallpaper,
    // which is the exact failure the palette exists to prevent.
    //
    // So the choice is "which of this palette's roles", and every answer re-derives
    // itself when the wallpaper changes. "" means the module's own default.
    readonly property var accentRoles: [
        { id: "",        label: "Default"  },
        { id: "primary", label: "Primary"  },
        { id: "focus",   label: "Focus"    },
        { id: "ramp2",   label: "Green"    },
        { id: "ramp3",   label: "Yellow"   },
        { id: "ramp5",   label: "Magenta"  },
        { id: "ramp9",   label: "Cyan"     }
    ]

    function moduleAccentRole(id) { return root._moduleSetting(id, "accent", "") }

    // Resolves to a colour, falling back to the caller's own default. Colors owns the
    // name→colour mapping; this only knows which name was chosen.
    function moduleAccent(id, fallback) {
        const role = root.moduleAccentRole(id)
        return role === "" ? fallback : Colors.role(role, fallback)
    }

    // ── Inner pill ────────────────────────────────────────────────────────────
    // `barInnerPill` is the bar-wide switch (Settings → Bar → Look); the
    // per-module setting (module inspector) narrows it further. Either one off
    // means off — a module can opt itself out, but no per-module setting can
    // override the bar-wide switch back on. The switch is the module's surface's: on
    // the sidebar, `sideInnerPill` (the bar's unless unlinked, ConfigEdges), whose pill
    // SideRegionPills splits round an opted-out module as BarGroup does on the bar.
    property bool barInnerPill: true
    function moduleInnerPill(id) {
        const on = root.surfaceOf(id) === "side" ? root.sideInnerPill : root.barInnerPill
        return on && root._moduleSetting(id, "innerPill", true) === true
    }
    function setModuleInnerPill(id, v) { root.setModuleSetting(id, "innerPill", !!v) }

    // ── Hero ──────────────────────────────────────────────────────────────────
    // A module whose chip is primaryContainer instead of the inner pill — a surface's one
    // emphasised pill, as a desktop tile's hero (2026-10-31, Material 3 Expressive). Only a
    // module the catalogue calls `heroable` (config/modules.js). Independent of the inner
    // pill: a hero draws its chip even with that switched off.
    //
    // ONE per surface (2026-11-08): `barHero` here and `sidebarHero` (ConfigEdges) each
    // name a module or "". It used to be a `hero` flag per module in moduleSettings, so
    // two could be on at once; the persisted load and loadPreset turn old flags into this
    // string (surfaces.js heroFromFlags). The string follows its module between surfaces
    // (_leaveBar / _leaveSidebar → Surfaces.moveHero). The clock is the default.
    property string barHero: "clock"

    function _heroable(id) { return Catalogue.info(id)?.heroable === true }

    // Is `id` the hero of the surface it stands on?
    function moduleHero(id) {
        if (!root._heroable(id)) return false
        const on = root.surfaceOf(id)
        return on === "bar" ? root.barHero === id : on === "side" ? root.sidebarHero === id : false
    }
    // On: it becomes its surface's hero (the old one stops being). Off: that surface has none.
    function setModuleHero(id, v) {
        if (!root._heroable(id)) return
        const on = root.surfaceOf(id)
        if (on === "bar")       root.barHero     = v ? id : (root.barHero === id ? "" : root.barHero)
        else if (on === "side") root.sidebarHero = v ? id : (root.sidebarHero === id ? "" : root.sidebarHero)
    }

    // One place per module, after a load or a preset put layouts in from outside the
    // mutators (layout.js dedupeAcross: the bar's copy wins).
    function _dedupeSurfaces() {
        const side = Layout.dedupeAcross(root.layout, root.sidebarLayout, root.regionIds, root.sidebarRegionIds)
        if (side !== root.sidebarLayout) root.sidebarLayout = side
    }

    // ── Group spacing ─────────────────────────────────────────────────────────
    // A per-GROUP (not per-module) pixel gap between adjacent bare icons — the
    // module inspector shows one slider for the whole cluster, because "how far
    // apart are these icons" is a property of the group, not of any one member.
    //
    // A group has no id of its own (BarArrange freely splits/merges/reorders
    // them), so it's keyed by its own CURRENT membership — every module id is
    // unique across the whole layout, so the sorted member list already names
    // exactly one group. Dragging a module in or out of a group changes that
    // group's key, which starts it fresh at "unset"; the old key's entry is
    // simply never looked up again. That's the right failure mode: a spacing you
    // tuned for "these six icons" shouldn't silently keep applying once the set
    // of icons it was tuned for has changed.
    //
    // -1 is the sentinel for "unset — every member keeps its own default
    // spacing", the same idiom the accent role's "" already uses.
    property var groupSettings: ({})

    // On whichever surface it stands: a sidebar group is keyed the same way (ids are
    // unique across both surfaces, one place per module).
    function _groupMembers(id) {
        const loc = root.locate(id)
        if (loc) return root.layout[loc.region][loc.group]
        const s = root.sidebarLocate(id)
        return s ? root.sidebarLayout[s.region][s.group] : []
    }

    // Exposed for the inspector, which lists who a spacing change affects.
    function groupMembers(id) { return root._groupMembers(id) }

    function _groupKey(id) {
        const members = root._groupMembers(id)
        return members.length > 0 ? members.slice().sort().join(",") : ""
    }

    function groupSpacing(id) {
        const key = root._groupKey(id)
        if (key === "") return -1
        const g = root.groupSettings[key]
        return (g && g.spacing !== undefined) ? g.spacing : -1
    }

    function setGroupSpacing(id, px) {
        const key = root._groupKey(id)
        if (key === "") return
        const next = {}
        for (const k in root.groupSettings) next[k] = Object.assign({}, root.groupSettings[k])
        if (!next[key]) next[key] = {}
        next[key].spacing = Math.max(0, Math.round(px))
        root.groupSettings = next
    }

    function clearGroupSpacing(id) {
        const key = root._groupKey(id)
        if (key === "" || !root.groupSettings[key]) return
        const next = {}
        for (const k in root.groupSettings) if (k !== key) next[k] = root.groupSettings[k]
        root.groupSettings = next
    }

    // ── Panel placement ───────────────────────────────────────────────────────
    // Which column — the bar's left dock, right dock, or the centre slot it
    // otherwise shares with the update/launcher panels — each accordion panel
    // opens in. Defaults to the side its own bar button already lives on — the
    // wallpaper, colour scheme, equalizer and Now Playing pills sit left of
    // centre; wifi, bluetooth and gaming sit right — but a module can be dragged
    // to the other side of the bar (see BarArrange) without its panel following
    // automatically, so this exists for the case where you'd rather it did. None
    // default to "center": that's purely an option to move a panel to, and it
    // still loses that slot to the update/launcher panels when both want it — see
    // BarPanelDock's centerAccordion.
    //
    // A plain {name: "left"|"right"|"center"} map, only for overrides: a name
    // that agrees with its default is never written, so an untouched shell has an
    // empty map and `defaultPanelSide` is the only thing consulted. "update" and
    // "launcher" aren't in here — they already own the centre slot outright and
    // have no other side to pick.
    readonly property var _defaultPanelSides: ({
        wallpaper:   "left",
        colorScheme: "left",
        equalizer:   "left",
        media:       "left",
        wifi:        "right",
        bluetooth:   "right",
        gaming:      "right",
        clock:       "right",
        notifications: "right",
        brightness:  "right",
        window:      "left",
        layout:      "left",
        stats:       "right",
        clipboard:   "right",
        timer:       "right",
        claude:      "right",
        screentime:  "right",
        inactivity:  "right",
        tasks:       "right",
        clips:       "right"
    })
    readonly property var panelNames: Object.keys(root._defaultPanelSides)

    property var panelPlacement: ({})

    function defaultPanelSide(name) { return root._defaultPanelSides[name] || "left" }

    function panelSide(name) {
        const v = root.panelPlacement[name]
        return (v === "left" || v === "right" || v === "center") ? v : root.defaultPanelSide(name)
    }

    function setPanelSide(name, side) {
        if (side !== "left" && side !== "right" && side !== "center") return
        const next = Object.assign({}, root.panelPlacement)
        if (side === root.defaultPanelSide(name)) delete next[name]
        else next[name] = side
        root.panelPlacement = next
    }

    // ── Panel zoom ────────────────────────────────────────────────────────────
    // How big each panel is drawn, as a plain multiplier on its natural size. The
    // grip in a panel's outer bottom corner writes it; Settings → Bar resets it.
    //
    // ── Why a multiplier and not a width/height ───────────────────────────────
    // Every panel but the wallpaper gallery is CONTENT-HUGGING: BarPanelDock reads
    // its `implicitHeight` and the panel decides how tall it is. A stored width and
    // height would have to overrule that, which either clips the content or leaves
    // dead space under it — and the ratio would drift the moment the content
    // changed (UpdatePanel grows while an upgrade runs). One multiplier can't: it
    // scales both axes by the same number, so the shape is exactly preserved at
    // every size and the panel still sizes itself to its content underneath.
    //
    // It's spent as a render scale on the card's content (BarDock.contentZoom),
    // NOT as a font/spacing scale. StyledText.sizeScale is the other kind and is
    // deliberately not what this is: asking for a bigger glyph re-lays-out the
    // panel, which is exactly the reflow this is avoiding.
    //
    // Same sparse-map contract as panelPlacement above: a panel at 1.0 is never
    // written, so an untouched shell has an empty map, and "reset" is just
    // deleting the key.
    readonly property real panelZoomMin: 0.8
    readonly property real panelZoomMax: 1.5

    // ── Drifting cookies behind every panel ───────────────────────────────────
    // Soft shapes on one shared plane that every open panel looks onto (services/Drift,
    // components/DriftShapes). Costs a frame loop while any panel is open, so it has a
    // switch of its own: `motionEnabled` freezes it, this removes it.
    property bool panelCookies: true

    // …and the same field behind the bar, the sidebar and the screen frame (modules/bar/FrameDrift).
    // An experiment: the bar never closes, so unlike a panel's it keeps the field's frame loop — and
    // the bar window's redraw — running for as long as it is on.
    property bool barCookies: true
    // Where they come from. "panels": a shape shows on the bar/sidebar/frame only when it has
    // drifted out of a panel, and drifts on until it leaves the screen (nothing there when no panel
    // is open, so the field need not run); "everywhere": a field of their own there, each shape
    // coming and going on a slow life. Either way a shape is drawn at one strength on both sides of
    // a join (services/drift.js `strength`). Anything else is read as "panels".
    property string barCookiesFrom: "panels"

    // panelNames minus nothing, plus the two that own the centre slot outright and
    // so have no placement row of their own. They still resize.
    readonly property var panelZoomNames: root.panelNames.concat(["update", "launcher"])

    property var panelZoom: ({})

    function panelZoomFor(name) {
        const v = root.panelZoom[name]
        if (typeof v !== "number" || !isFinite(v)) return 1.0
        return Math.max(root.panelZoomMin, Math.min(v, root.panelZoomMax))
    }

    // ── Snapped, but finely ───────────────────────────────────────────────────
    // To a TENTH of a percent, not a whole one. This is written live on every frame
    // of a grip drag, and a whole percent is ~5px on a 535-wide panel — coarse
    // enough to see the card advance in steps while the pointer moves smoothly.
    //
    // It is still snapped, because the point of rounding here is that a drag which
    // lands on 1.0000001 writes NOTHING: the key is deleted and the panel is
    // genuinely back to untouched, rather than carrying an invisible override that
    // Reset would still have to clear and the settings page would still list.
    function setPanelZoom(name, z) {
        if (typeof z !== "number" || !isFinite(z)) return
        const clamped = Math.max(root.panelZoomMin, Math.min(z, root.panelZoomMax))
        const snapped = Math.round(clamped * 1000) / 1000
        const next = Object.assign({}, root.panelZoom)
        if (snapped === 1) delete next[name]
        else next[name] = snapped
        root.panelZoom = next
    }

    function resetPanelZoom(name) { root.setPanelZoom(name, 1) }

    function resetPanelZooms() { root.panelZoom = ({}) }

    function panelZoomed(name) { return root.panelZoom[name] !== undefined }

    readonly property bool anyPanelZoomed: Object.keys(root.panelZoom).length > 0

    // ── Right-click state ─────────────────────────────────────────────────────
    // Four modules toggle a second face on right-click: wifi, volume, battery and
    // bluetooth expand. That state is transient by design — it resets on reload,
    // which is right if it's a peek and wrong if it's how you actually want the
    // module to sit.
    //
    // The visualizer used to be a fifth (spectrum ↔ media controls) but that face
    // is gone — right-click there now toggles Config.cavaBg, a real shell-wide
    // setting that already persists on its own, not a per-widget local look this
    // mechanism is for. Removed rather than relabelled.
    //
    // `rightPersist` opts a module into remembering. Off (default): the widget keeps
    // its own local state and a reload forgets it. On: the widget's state IS this
    // value, so right-clicking writes here and it survives.
    readonly property var rightClickModules: [
        { id: "wifi",       label: "Show the network",    off: "Icon only", on: "Icon + SSID"    },
        { id: "volume",     label: "Show the slider",     off: "Icon only", on: "Icon + slider"  },
        { id: "battery",    label: "Show the percentage", off: "Icon only", on: "Icon + percent" },
        { id: "bluetooth",  label: "Show what's connected", off: "Icon only", on: "Icon + device" }
    ]

    function hasRightClick(id) {
        return root.rightClickModules.some(m => m.id === id)
    }

    function rightClickInfo(id) {
        return root.rightClickModules.find(m => m.id === id) ?? null
    }

    function modulePersist(id)      { return root._moduleSetting(id, "rightPersist", false) === true }
    function moduleRightState(id)   { return root._moduleSetting(id, "rightState",   false) === true }
    function setModulePersist(id, v) { root.setModuleSetting(id, "rightPersist", !!v) }
    function setModuleRightState(id, v) {
        // Only meaningful while the module is opted in. Writing it otherwise would
        // store a value the widget isn't reading, so it'd look like the setting had no
        // effect — which is worse than not offering it.
        if (root.modulePersist(id)) root.setModuleSetting(id, "rightState", !!v)
    }
}
