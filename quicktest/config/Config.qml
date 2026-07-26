pragma Singleton
import Quickshell
import QtQuick

// ── Config ────────────────────────────────────────────────────────────────────
// The user's PREFERENCES — the things the settings app writes and the shell reads.
// Persisted, and the single source of truth for all of them.
//
// ── Config vs UiState ─────────────────────────────────────────────────────────
// UiState answers "what is the shell showing right NOW" (which panel is open, is the
// overview up) — transient, and deliberately not restored across a reload. This answers
// "how has the user set the shell up" — durable, and restored every time.
//
// `barShape`/`barMode` used to live in UiState, which even said so itself: "Only the
// appearance preferences persist. Panel state is transient by design." Those two were
// the odd ones out in a file about transient state, and now that there are twenty more
// of them they've moved here where they belong.
//
// Defaults mirror Tokens — Tokens stays the design system's baseline, and this is the
// user's departure from it. (Tokens must never import Config: the tokens are what the
// defaults are DEFINED as, so the dependency only runs one way.)
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── The shell's own version ───────────────────────────────────────────────
    // Hand-maintained, and it has to be: this config isn't a git checkout (no .git
    // anywhere), so there's nothing to derive a version FROM at runtime. Upstream is
    // https://github.com/rufss14/Quickshell-Config, which tags releases — v0.1, v0.2 —
    // and the update check compares this string against the newest tag there.
    //
    // BUMP THIS when you tag a release, or the shell will report itself as whatever
    // the last person to think about it said. It is the one number here that a
    // machine can't check for you.
    readonly property string version: "0.3"
    readonly property string repo:    "rufss14/Quickshell-Config"

    // ══ Bar — look ════════════════════════════════════════════════════════════
    property bool barShape: false          // true = square corners, flush to the edges
    property bool barMode:  true           // true = merged group pills instead of one per group

    // Defaults synced to the "rufss" preset (the bar actually in use), so an untouched
    // config, a Reset, and the built-in "Default" all match it. barThickness/barInset
    // already equalled their rufss values via the tokens; barRoundness did not (10 vs 12).
    property int barThickness: Tokens.barHeight    // 40
    property int barRoundness: 10
    property int barInset:     Tokens.barMargin    // 4

    // ── Border width, the bar/frame's own chrome ──────────────────────────────
    // Was a flat `Tokens.borderChrome` (2px) — a scoped constant, deliberately NOT
    // the shell-wide `Tokens.borderWidth` hairline (see that token's own comment:
    // bumped once already to match Hyprland's `border_size = 2`, and 40 other
    // files/62 usages were left alone on purpose). This is the user-facing knob
    // for exactly that scoped value, same pattern as barRoundness/barInset: a
    // Tokens default, and this is where the user's own departure from it lives.
    // Every piece of bar/frame chrome (BarGroup, BarRegion, BarFrameEdge,
    // ScreenFrame, FrameFusion) reads THIS now, never Tokens.borderChrome
    // directly — one number, so a pill's border, the frame's stroke and the
    // fillet's weld line can't drift out of step with each other.
    property int barBorderWidth: Tokens.borderChrome

    function toggleShape() { root.barShape = !root.barShape }
    function toggleMode()  { root.barMode  = !root.barMode }

    // ── The gap BETWEEN pills ─────────────────────────────────────────────────
    // This used to be barInset. One number was doing two unrelated jobs: how far the bar
    // floats off the screen edge, and how far its pills sit from each other. You could
    // not change either without changing the other, which is why the bar had no spacing
    // control — it had half of one, wearing the inset's name.
    //
    // The "rufss" default is 10. Merged mode (the default now) ignores this anyway — its
    // groups are separated by a divider inside one pill, not by a gap in the bar — so it
    // only takes effect if you switch to split mode.
    property int barSpacing: 10

    // How solid the pills are. Worth almost nothing without a compositor blur behind it
    // — see the namespace note in Bar.qml — because all it reveals otherwise is the
    // wallpaper.
    property real barOpacity: Tokens.surfaceOpacity

    // ── Liquid glass on the bar's pills ───────────────────────────────────────
    // Gives every bar pill GlassOverlay's treatment: graded body, sheen, rim.
    //
    // ── Only the LIGHT half, never refraction ─────────────────────────────────
    // Refraction needs a TEXTURE of whatever is behind the surface. The desktop tiles
    // have one — they sit on the layer-shell background, so the wallpaper is genuinely
    // all that is behind them — and they use it. The bar sits ABOVE windows, and the
    // shell cannot sample those, so the diffuse half has to come from the compositor's
    // own blur. That needs a Hyprland layer rule on `quickshell-bar`, which is currently
    // `blur = false` there. Without it this is lighting on a near-opaque pill.
    //
    // ── Why the screen FRAME is deliberately excluded ─────────────────────────
    // The obvious move is one preference for both, since the frame is a ring of the
    // bar's material. It is excluded for a concrete reason, not an oversight:
    //
    //   • Its rim is ALREADY lit harder than the glass rim — `outlineBar` is
    //     alpha(text, 0.85) against GlassOverlay's 0.32 — so the one cue that matters
    //     most is present on the ring today.
    //   • A graded BODY cannot be added safely. FrameFusion hides the band's border at
    //     a fused pill by painting flat `frameFill` over it; grade the band and that
    //     eraser stops matching, leaving a visible patch at exactly the seam that took
    //     several rounds to get right. The side strips are `frameDepth` px wide (10 by
    //     default), where a gradient is indistinguishable from a flat tint anyway.
    //
    // Default OFF: this is the always-visible chrome, and it should not change under
    // someone because they updated.
    property bool barGlass: false

    // ── Where the centre region pins itself ───────────────────────────────────
    // true  — the group holding `workspaces` sits on true screen centre, and its
    //         neighbours balance around it. A tray icon appearing shifts the region, not
    //         the dots.
    // false — the region centres as a whole, dots included, so they drift whenever
    //         anything beside them changes width.
    //
    // The dots are the bar's visual anchor, so true is the default. With workspaces off
    // the bar there's nothing to anchor and the region centres itself regardless.
    property bool barCentreAnchor: true

    // Multipliers on the type and icon scales rather than pixel counts: the ratios
    // between Tokens' sizes are the design, and absolute overrides would let you break
    // them one widget at a time. Same shape as motionScale, for the same reason.
    //
    // These are separate because a Nerd Font glyph is an ICON that happens to be a
    // character — the bar's glyphs scale with the icons they are, not with the clock.
    property real barFontScale: 1.0
    property real barIconScale: 1.15   // rufss default

    // ── Screen frame ──────────────────────────────────────────────────────────
    // Wraps the screen in a thin ring of the bar's material: a band along the top
    // (drawn by the bar itself, behind its pills), strips down the sides and along
    // the bottom, and concave corners where ring meets content. Purely visual; the
    // strips reserve their own space with the compositor so windows tile inside.
    property bool screenFrame:    false
    property int  frameThickness: 10
    // The ring's inner corner radius — a real preference now, not a derivation.
    // 22 is what the old auto rule (frameThickness + barRoundness) produced at the
    // defaults, kept as the default so nothing changes for an untouched config.
    property int  frameRoundness: 22

    function toggleFrame() { root.screenFrame = !root.screenFrame }

    // ── Bar frame: just the band, none of the ring ────────────────────────────
    // `screenFrame` reserves compositor space down the sides and along the
    // bottom, which is a real desktop-layout decision, not a cosmetic one. This
    // is the "I just want the merged bar/pill look" toggle: it turns on
    // BarFrameEdge (the top band, drawn INSIDE the bar's own window — see that
    // file's header for why it has to live there) without ScreenFrame's strips.
    // `screenFrame` still implies the band, so turning the full ring on doesn't
    // also require this.
    property bool barFrame: false

    function toggleBarFrame() { root.barFrame = !root.barFrame }

    // ── Whether the pill actually WELDS to whichever band is showing ──────────
    // `screenFrame`/`barFrame` decide if a band exists; this decides, independently,
    // whether the pill fuses into it or just floats cleanly below it. They used to
    // be the same switch — turning on Screen frame always welded the pill, with no
    // way to have the ring without the weld — which is also why the old "Merge
    // frame and pill" toggle went dead/locked the moment Screen frame was on: it
    // WAS Screen frame's own effect, not a separate choice. Default true so an
    // untouched config (or one from before this existed) looks exactly like it did.
    property bool frameMerge: true

    function toggleFrameMerge() { root.frameMerge = !root.frameMerge }

    // ── The EFFECTIVE ring thickness ──────────────────────────────────────────
    // The slider's value, clamped so the band always leaves room in the bar for a
    // pill: fused, the pill lives between the band's underside and the bar's
    // bottom, and a band deeper than `barThickness − barInset − 16` squeezes that
    // space negative — the pill inverts and vanishes. Clamped here, once, rather
    // than assigned back to the pref, so lowering barThickness thins the ring and
    // raising it again restores exactly what the user asked for. Every piece of
    // frame geometry reads THIS, never frameThickness.
    readonly property int frameDepth:
        Math.max(root.frameThicknessMin,
                 Math.min(root.frameThickness,
                          root.barThickness - root.barInset - 16))

    // Capped by what fits: the TOP corners hang below the band inside the bar's
    // own window, and a radius past the bar's bottom edge gets clipped mid-arc.
    // One value for all four so the ring stays self-consistent — the bottom pair
    // could go larger (they live in the full-screen overlay), but a ring with two
    // corner sizes reads as a mistake, not a feature.
    readonly property int frameCornerRadius:
        Math.max(0, Math.min(root.frameRoundness,
                             root.barThickness - root.frameDepth))

    // Pills fuse with the band (borders between them vanish, flared fillets at the
    // joins) only when the user wants that (`frameMerge`) AND they actually reach
    // it. Floating mode reaches it whenever the inset is smaller than the band; a
    // large inset leaves an honest gap instead and falls back to the ring passing
    // behind. Square mode ALWAYS reaches it — a square pill runs flush to the screen
    // edge with no inset of its own, so without SOME clearance it would simply
    // overlap the band instead of sitting below it. That clearance (the group's
    // `bandClear`/`fuseDrop`) applies whenever a band is visible, whether or not
    // this is true — a merge-off pill still has to clear the band, it just clears
    // it without welding. `barFrame` gets the same fusion as `screenFrame` — it
    // draws the identical band, just without the side/bottom strips.
    readonly property bool frameFused:
        (root.screenFrame || root.barFrame) && root.frameMerge &&
        (root.barShape || root.barInset < root.frameDepth)

    // ── The EFFECTIVE merge state ─────────────────────────────────────────────
    // `barMode` stays the user's stored preference; actually WELDING to the band
    // forces merging on top of it. A split bar fused to the band puts a flared join
    // on both sides of every group — a dozen of them across the bar — and the band
    // reads as more notch than band. One pill per region gives the frame six clean
    // joins instead, which is what makes the ring look like it grew the bar rather
    // than got chewed by it.
    //
    // Reads `frameFused`, not just "is a band showing": with `frameMerge` off the
    // pill floats below the band instead of welding to it, so there is no flared
    // join to avoid and no reason to force split groups into one pill.
    //
    // Derived, not assigned, so turning the frame back off restores the user's own
    // choice rather than leaving them merged with no memory of why.
    readonly property bool barMerged: root.barMode || root.frameFused

    // The flare radius where a pill's side sweeps into the band.
    //
    // Scales with the band rather than sitting at a fixed 6: a 6px shoulder against
    // a 24px band reads as a nick in the material, not as the pill growing out of
    // it, and 6 against a 4px band overhangs. Capped by barRoundness so it stays in
    // the bar's corner language, and following it down to 0 so square palettes get
    // square joins instead of a mismatched curve — square mode has no rounded
    // corners anywhere else, so a fillet there would be the one curve in a square
    // bar, not a join.
    //
    // Also capped by the room actually left in the pill once fused — the arc
    // reaches `fr` px DOWN the pill's side border below the seam, and the pill is
    // only ever guaranteed `barThickness - barInset - frameDepth` px tall there
    // (frameDepth's own clamp keeps that at 16 minimum, never less, but says
    // nothing about MORE). Without this second cap, cranking Frame thickness and
    // Roundness both toward their maximums made barRoundness/frameDepth alone
    // agree on a radius bigger than the pill — the arc overshot past the pill's
    // own bottom edge into whatever sits below it. That is the "corners degrade as
    // the radius grows" bug: the two sliders are perfectly plausible to raise
    // together, and the higher they go, the further past the pill the arc reached.
    readonly property int frameFilletRadius:
        root.barShape ? 0
            : Math.max(0, Math.min(root.barRoundness, root.frameDepth,
                                   root.barThickness - root.barInset - root.frameDepth))

    // ── The apron: extra bar-window height below the bar ──────────────────────
    // Fused, the fillets where an edge pill's bottom sweeps into the side strips
    // need room BELOW the pill, and the bar's window used to end `barInset` px
    // under it — which capped those fillets at 4px, a notch rather than a sweep,
    // with the arc's last row antialiased against the window edge. The window now
    // extends this far past barThickness (exclusive zone and input mask stay at
    // barThickness, so nothing else notices), which is exactly the room the
    // fillet needs at full hover-grow: growY tops out at barInset, so
    // pillBottom + fillet ≤ barThickness + apron with zero slack.
    readonly property int frameApron:
        root.frameFused ? root.frameFilletRadius : 0

    // The fillet where an edge pill's BOTTOM sweeps into the side strip it has
    // merged with. Full-size now — the apron above exists precisely so this no
    // longer has to fit inside `barInset`.
    readonly property int frameEdgeFilletRadius: root.frameFilletRadius

    // Sensible bounds for the settings sliders — a 12px bar can't fit a pill, and a
    // 96px one stops being a bar.
    readonly property int barThicknessMin: 28
    readonly property int barThicknessMax: 64
    readonly property int barRoundnessMax: 20
    readonly property int barInsetMax:     12
    readonly property int barSpacingMax:   16
    // Below 4 the frame is a hairline that reads as a rendering glitch; above 24 it
    // stops framing and starts eating the screen.
    readonly property int frameThicknessMin: 4
    readonly property int frameThicknessMax: 24
    // Past 40 the corner arc is most of a screen-height's curve and the "ring"
    // reads as a vignette. 0 is legitimate: a square ring for square palettes.
    readonly property int frameRoundnessMax: 40

    // Below ~0.5 the outline is doing all the work and the pill stops reading as a
    // surface at all.
    readonly property real barOpacityMin: 0.5

    readonly property real barScaleMin: 0.8
    readonly property real barScaleMax: 1.4

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
    property var layout: root.defaultLayout()

    // ── The default ───────────────────────────────────────────────────────────
    // This IS the "rufss" bar — the layout actually in use — kept in sync with
    // presets/bar.json's "rufss" snapshot so the built-in "Default" preset, a Reset,
    // and a fresh install all land on the real bar rather than an older arrangement.
    // It deliberately leaves `shapeToggle` and `modeToggle` in the available pool
    // (they're reachable from the settings page, and off the bar by choice), so the
    // default is no longer the WHOLE catalogue — it's the curated bar.
    //
    // The middle group of the centre is update / workspaces / reload, with workspaces
    // in the middle of it. That's deliberate: the centre region positions itself so the
    // group CONTAINING workspaces lands on true screen centre, so anything sharing that
    // group is balanced around the dots rather than pushing them off-centre. Keyboard
    // and tray are their own groups on either side, which is why they can change width
    // freely — a tray icon appearing or a layout tag changing from "us" to "de" shifts
    // the region, not the dots.
    //
    // ── Why keyboard and tray sit exactly here ────────────────────────────────
    // This function briefly omitted them, and the comment here claimed that was
    // deliberate ("they're both situational"). It wasn't the original design. Bar.qml
    // still records the layout this replaces: the centre offset used to be computed as
    // `keyboardGroup.width + gap + mainGroup.width / 2`, which only makes sense with
    // keyboard as its own group BEFORE the anchor — and the same comment cites drift
    // "every time an app added or removed a tray icon", which only happens with tray on
    // the bar. Tray trails the anchor because the old formula never accounted for its
    // width, so it cannot have led it.
    function defaultLayout() {
        return {
            left:   [["settings", "overview"], ["wallpaper", "palette"], ["volume", "visualizer"]],
            centre: [["keyboard"], ["update", "workspaces", "reload"], ["tray"]],
            right:  [["notifications", "wifi"], ["clock"]]
        }
    }

    readonly property var regionIds: ["left", "centre", "right"]

    function regionLabel(region) {
        return region === "left" ? "Left" : region === "centre" ? "Centre" : "Right"
    }

    // A deep copy, because every mutator works on a throwaway and then assigns it. A
    // shallow copy would share the inner group arrays with the live layout, so a splice
    // would mutate what's on screen before the assignment — which is exactly the
    // in-place mutation the model forbids.
    function _clone(l) {
        const out = {}
        for (const r of root.regionIds) out[r] = (l[r] ?? []).map(g => g.slice())
        return out
    }

    // Groups only exist to hold modules. Dragging the last one out of a group leaves an
    // empty pill sitting in the bar, so emptied groups are dropped on every write
    // rather than at each call site remembering to.
    function _prune(l) {
        for (const r of root.regionIds) l[r] = l[r].filter(g => g.length > 0)
        return l
    }

    // ── Where is this module right now? ───────────────────────────────────────
    // Returns { region, group, index } or null. The drag UI and the bar both need to
    // answer this, and neither should be scanning the structure by hand.
    function locate(id) {
        for (const r of root.regionIds) {
            const groups = root.layout[r] ?? []
            for (let g = 0; g < groups.length; g++) {
                const i = groups[g].indexOf(id)
                if (i !== -1) return { region: r, group: g, index: i }
            }
        }
        return null
    }

    function isPlaced(id) { return root.locate(id) !== null }

    readonly property var availableModules:
        root.moduleList.filter(m => !root.isPlaced(m.id))

    // ── Mutators ──────────────────────────────────────────────────────────────
    // All of them take the module OUT first and put it back somewhere. Move and insert
    // are the same operation with a different destination, and writing them separately
    // is how you end up with a module existing twice.
    function _extract(l, id) {
        for (const r of root.regionIds) {
            for (const g of l[r]) {
                const i = g.indexOf(id)
                if (i !== -1) { g.splice(i, 1); return }
            }
        }
    }

    // Drop onto a gap: the module becomes its own group at `groupIndex` in `region`.
    function moveToOwnGroup(id, region, groupIndex) {
        const l = root._clone(root.layout)
        root._extract(l, id)
        root._prune(l)
        const at = Math.max(0, Math.min(groupIndex, l[region].length))
        l[region].splice(at, 0, [id])
        root.layout = l
    }

    // Drop onto another module: join its group at `index`. This is the phone-folder
    // gesture — dropping one thing on another is what makes them a cluster, so grouping
    // never needs a mode or a modifier key.
    function moveIntoGroup(id, region, groupIndex, index) {
        const l = root._clone(root.layout)

        // Where it was matters: pulling it out of the SAME group shifts everything
        // after it down one, so an index captured before the extract would land the
        // module one slot too far right. Everywhere else is unaffected.
        const from = root.locate(id)
        const sameGroup = from && from.region === region && from.group === groupIndex
        const adjusted  = (sameGroup && from.index < index) ? index - 1 : index

        root._extract(l, id)

        // The group may have just been emptied and pruned away — but pruning first
        // would renumber the groups after it and invalidate `groupIndex`. So target
        // the group, THEN prune.
        const g = l[region][groupIndex]
        if (!g) { root.layout = root._prune(l); return }
        g.splice(Math.max(0, Math.min(adjusted, g.length)), 0, id)

        root.layout = root._prune(l)
    }

    function removeModule(id) {
        const l = root._clone(root.layout)
        root._extract(l, id)
        root.layout = root._prune(l)
    }

    // Putting a module back from the available pool. Its own group at the end of the
    // region it belongs to by default — a returning module shouldn't silently join a
    // cluster it was never part of.
    function addModule(id) {
        const m = root.moduleList.find(x => x.id === id)
        if (!m || root.isPlaced(id)) return
        const l = root._clone(root.layout)
        l[m.home].push([id])
        root.layout = l
    }

    // ══ Bar — the module catalogue ════════════════════════════════════════════
    // Metadata only: what a module IS, never where it sits. `home` is just where
    // addModule() puts it when it comes back from the pool.
    //
    // The description is here rather than in the settings page because it's a fact
    // about the module, and the page is a view. It also means adding a module is one
    // entry in one list.
    readonly property var moduleList: [
        { id: "shapeToggle", home: "left",   label: "Bar shape",
          description: "Switches the bar between <b>floating pills</b> and <b>square, edge-to-edge</b> corners." },
        { id: "modeToggle",  home: "left",   label: "Bar mode",
          description: "Merges each region's groups into <b>one pill</b>, separated by dividers." },
        { id: "palette",     home: "left",   label: "Colour scheme",
          description: "Opens the <b>palette panel</b> — the wallpaper-derived scheme and its variants." },
        { id: "wallpaper",   home: "left",   label: "Wallpaper",
          description: "Opens the <b>wallpaper picker</b>. <i>Choosing one re-derives the whole palette.</i>" },
        { id: "volume",      home: "left",   label: "Volume",
          description: "<b>Scroll</b> to change volume, <b>click</b> for the mixer, <b>right-click</b> for the slider." },
        { id: "keyboard",    home: "centre", label: "Keyboard layout",
          description: "The active <b>xkb layout</b>. Click to cycle through the ones you've configured." },
        { id: "update",      home: "centre", label: "Updates",
          description: "<b>Pending package count.</b> Click to review and install them." },
        { id: "workspaces",  home: "centre", label: "Workspaces",
          description: "Five dots, paging <b>1–5 / 6–10</b>. <i>The bar's visual anchor — it sits on true centre.</i>" },
        { id: "reload",      home: "centre", label: "Reload",
          description: "<b>Restarts the shell.</b> <i>Useful while editing the config, easy to hit by accident.</i>" },
        { id: "tray",        home: "centre", label: "System tray",
          description: "Background app icons. <i>Hides itself when nothing is running.</i>" },
        { id: "visualizer",  home: "right",  label: "Visualizer",
          description: "Audio spectrum. <b>Right-click</b> for media controls, <b>click</b> for the desktop background." },
        { id: "wifi",        home: "right",  label: "Wi-Fi",
          description: "<b>Signal strength</b>, tinted by quality. Click for networks, <b>right-click</b> for the name." },
        { id: "clock",       home: "right",  label: "Clock",
          description: "The time. Click to toggle the <b>big desktop clock</b> behind your windows." },
        { id: "notifications", home: "right", label: "Notifications",
          description: "Opens the <b>notification centre</b>. <b>Right-click</b> toggles <b>Do Not Disturb</b> — the bell changes icon and colour while it's on." },
        { id: "overview",    home: "left",   label: "Overview",
          description: "Opens the <b>overview</b> — workspaces, media, calendar and power." },
        { id: "settings",    home: "left",   label: "Settings",
          description: "Opens the <b>settings</b> page of the overview." }
    ]

    function moduleInfo(id) {
        return root.moduleList.find(m => m.id === id) ?? null
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
            barMode:         true,
            barThickness:    Tokens.barHeight,     // 40, == rufss
            barRoundness:    10,
            barInset:        Tokens.barMargin,     // 4, == rufss
            barSpacing:      10,
            barOpacity:      Tokens.surfaceOpacity, // 0.97, == rufss
            barCentreAnchor: true,
            barFontScale:    1.0,
            barIconScale:    1.15,
            layout:          root.defaultLayout()
        }
    })

    // What the page renders: the built-in first, then whatever you've saved.
    readonly property var allPresets: [root.defaultPreset].concat(root.presets)

    property var presets: []

    function _snapshot() {
        return {
            barShape:        root.barShape,
            barMode:         root.barMode,
            barThickness:    root.barThickness,
            barRoundness:    root.barRoundness,
            barInset:        root.barInset,
            barSpacing:      root.barSpacing,
            barOpacity:      root.barOpacity,
            barCentreAnchor: root.barCentreAnchor,
            barFontScale:    root.barFontScale,
            barIconScale:    root.barIconScale,
            layout:          root._clone(root.layout)
        }
    }

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
    // bare `c.barSpacing` would then assign `undefined` — which an int property reads as
    // 0 and a real one as NaN, so an old preset would silently flatten the bar instead
    // of leaving the setting alone.
    //
    // Falling back to defaultPreset rather than to the LIVE value on purpose: loading a
    // preset twice from different starting states has to land in the same place, or it
    // isn't a preset.
    function loadPreset(name) {
        const p = root.allPresets.find(x => x.name === name)
        if (!p) return
        const c = p.config
        const d = root.defaultPreset.config

        root.barShape        = c.barShape        ?? d.barShape
        root.barMode         = c.barMode         ?? d.barMode
        root.barThickness    = c.barThickness    ?? d.barThickness
        root.barRoundness    = c.barRoundness    ?? d.barRoundness
        root.barInset        = c.barInset        ?? d.barInset
        root.barSpacing      = c.barSpacing      ?? d.barSpacing
        root.barOpacity      = c.barOpacity      ?? d.barOpacity
        root.barCentreAnchor = c.barCentreAnchor ?? d.barCentreAnchor
        root.barFontScale    = c.barFontScale    ?? d.barFontScale
        root.barIconScale    = c.barIconScale    ?? d.barIconScale

        // Cloned on the way out as well as in: handing the live layout the preset's own
        // array would let a later edit to the bar rewrite the stored preset.
        root.layout          = root._clone(c.layout ?? d.layout)
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

    // Serialise with object keys in a stable order, at every depth.
    //
    // Plain JSON.stringify follows INSERTION order, which was fine while presets only
    // ever came from _snapshot() and every one of them was built by the same literal.
    // They come off disk now, and the file is meant to be hand-edited — so the moment
    // you reorder two keys in presets/bar.json by hand, a byte-identical preset stops
    // matching and the active dot goes out. Same data, different string.
    function _canonical(v) {
        if (Array.isArray(v)) return "[" + v.map(root._canonical).join(",") + "]"
        if (v !== null && typeof v === "object")
            return "{" + Object.keys(v).sort()
                .map(k => JSON.stringify(k) + ":" + root._canonical(v[k])).join(",") + "}"
        return JSON.stringify(v)
    }

    // Does the bar currently match this preset? Drives the "which one am I on"
    // indicator. Structural comparison because these are plain data all the way down,
    // and a hand-rolled deep-equal is a bug farm for something this shallow.
    function presetActive(name) {
        const p = root.allPresets.find(x => x.name === name)
        return p ? root._canonical(p.config) === root._canonical(root._snapshot()) : false
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

    // ── Right-click state ─────────────────────────────────────────────────────
    // Three modules toggle a second face on right-click: the visualizer swaps its
    // spectrum for media controls, and wifi and volume expand. That state is transient
    // by design — it resets on reload, which is right if it's a peek and wrong if it's
    // how you actually want the module to sit.
    //
    // `rightPersist` opts a module into remembering. Off (default): the widget keeps
    // its own local state and a reload forgets it. On: the widget's state IS this
    // value, so right-clicking writes here and it survives.
    readonly property var rightClickModules: [
        { id: "visualizer", label: "Show media controls", off: "Spectrum",  on: "Media controls" },
        { id: "wifi",       label: "Show the network",    off: "Icon only", on: "Icon + SSID"    },
        { id: "volume",     label: "Show the slider",     off: "Icon only", on: "Icon + slider"  }
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

    // ══ Motion ════════════════════════════════════════════════════════════════
    // Motion.qml reads these, which is the one place the dependency runs this way
    // round. Tokens must never import Config because the tokens ARE the defaults; but
    // duration is different — the effective duration genuinely is the designed one
    // scaled by a preference, and there is no other place that could live without every
    // Behavior in the shell multiplying it by hand.
    //
    // Config still doesn't import Motion, so there's no cycle: the numbers below are
    // plain literals, not derived from the design system.
    property real motionScale: 1.0        // 0.5 = twice as fast, 2.0 = half speed
    property bool motionEnabled: true     // false ⇒ every duration collapses to 0
    property bool barHoverGrow:  true     // the bar pill's grow-on-hover

    readonly property real motionScaleMin: 0.25
    readonly property real motionScaleMax: 2.0

    function resetMotion() {
        root.motionScale   = 1.0
        root.motionEnabled = true
        root.barHoverGrow  = true
    }

    // ══ Sound ═════════════════════════════════════════════════════════════════
    // The desktop spectrum behind your windows (modules/panels/CavaBG.qml).
    //
    // This lived in UiState as `cavaBgOpen`, which was the wrong home: UiState answers
    // "what is the shell showing right now" and holds nothing across a restart, so the
    // background silently switched itself off on every login. It's a preference — you
    // turn it on because you want it, not for the current session — so it belongs here,
    // where things are written to disk.
    property bool cavaBg: false

    // ══ Wallpaper engine ══════════════════════════════════════════════════════
    // Options for the linux-wallpaperengine renderer (Settings → Wallpaper).
    //
    // These exist as preferences because the renderer has NO IPC — every one of them
    // is a startup argument, so the only way to have them survive is to own the launch
    // and rebuild the command from stored values. See services/WallpaperEngine.qml.
    //
    // Which workshop item to restore. The service reads what's ACTUALLY running from
    // the live process instead of trusting this — the user can start the renderer by
    // hand — so this is the restore value, not a claim about the current state.
    property string wpeCurrent: ""
    // Start the wallpaper when the shell does. Off by default: something else may
    // already be launching it, and two renderers fight over the same layer surface.
    property bool wpeAutoStart: false

    // 60 rather than the monitor's refresh rate. A wallpaper is the least important
    // thing on screen and the frame rate is pure GPU cost; raise it if you want it.
    property int  wpeFps: 60
    // ── V-Sync ────────────────────────────────────────────────────────────────
    // linux-wallpaperengine (r627) has NO vsync flag — checked against --help, not
    // assumed. But vsync for an OpenGL program is a DRIVER setting, not an app one,
    // and both driver stacks honour an environment variable: `vblank_mode` (Mesa,
    // for AMD/Intel) and `__GL_SYNC_TO_VBLANK` (NVIDIA). On: the launch prepends
    // both, forcing the renderer to sync to the display and cutting tearing. Off:
    // nothing is set, so the driver keeps its own default — today's behaviour, so
    // false changes nothing for an untouched config.
    property bool wpeVsync: false
    // ── Which monitor the scene renders on ────────────────────────────────────
    // "" = every screen (one --screen-root each); otherwise a single screen name.
    // Rendering on ONE screen is also the fix for scenes whose audio doubles across
    // a multi-monitor setup — one scene instance, one soundtrack. Guarded against a
    // stale name in the service, exactly like wallTarget.
    property string wpeTarget: ""
    property bool wpeMute: false
    property int  wpeVolume: 50
    // The renderer MUTES ITSELF whenever any other application plays a sound,
    // unless told not to — which read as "wallpaper audio doesn't work" the
    // moment anything (a notification, Discord) made a noise. True = pass
    // --noautomute, the flag the user's own manual launches always carried.
    property bool wpeKeepAudio: true
    // The renderer stops rendering while an app is fullscreen. Right for a game,
    // wrong if you actually want to keep seeing the wallpaper.
    property bool wpePauseFullscreen: true
    // Wallpapers that react to whatever is playing. Costs an audio capture.
    property bool wpeAudioProcessing: true
    // Scene wallpapers that follow the cursor. Both cost real work every frame.
    property bool wpeMouse:    true
    property bool wpeParallax: true
    // Derive the shell's palette from the scene's preview image when a scene is
    // applied — an animated wallpaper recolours the shell the same way a static
    // one does. On by default: a wallpaper that doesn't theme the shell is the
    // surprising case here, not the normal one.
    property bool wpeScenePalette: true

    // ── The master theming switch ─────────────────────────────────────────────
    // Off: picking a wallpaper changes the PICTURE and nothing else — no pywal,
    // no app repaints, the palette on disk stays put. For people who want their
    // colours hand-picked (or held by a saved scheme) while still changing
    // wallpapers freely.
    property bool wallTheming: true

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
    property string wallTarget: ""

    // ── Wallpaper shuffle ─────────────────────────────────────────────────────
    // Slideshow: apply a random image from the library every N minutes. Each
    // change is a full palette re-derivation (that's the point), so the floor is
    // high — a shell repainting itself every two minutes is a lava lamp.
    property bool wallShuffle: false
    property int  wallShuffleMins: 30

    readonly property int wallShuffleMinsMin: 5
    readonly property int wallShuffleMinsMax: 180

    readonly property int wpeFpsMin: 24
    readonly property int wpeFpsMax: 240

    // ══ Settings ══════════════════════════════════════════════════════════════
    property bool railCollapsed: false

    // Which settings page to reopen on.
    //
    // Stored as the page's FILE, never its index. The rail's length changes with the
    // hardware — no Wi-Fi device means no Wi-Fi page, and a battery appearing inserts one
    // mid-list — so a saved index can silently come back pointing at a different page.
    // SettingsCard already had to guard against exactly that at runtime; persisting the
    // index would have made it survive restarts too.
    property string settingsPage: "BarPage.qml"
    function toggleRail() { root.railCollapsed = !root.railCollapsed }


    // ══ Desktop widgets ═══════════════════════════════════════════════════════
    // The master switch. Placement and content live in DesktopWidgets' own store —
    // that grows with what you type into a note, and has no business being rewritten
    // into this document every time a slider moves.
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

    // Snap step for dragging, in pixels. Not the tile size: tiles are 168px, and
    // snapping at that granularity would give you nine possible positions on a screen.
    // 40 is fine enough to place things deliberately and coarse enough that two
    // widgets dropped near each other actually line up.
    property int widgetGrid: 40

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

    // ══ Persistence ═══════════════════════════════════════════════════════════
    // ── What was wrong before ─────────────────────────────────────────────────
    // All of this was one PersistentProperties block. That type has NO disk I/O — it
    // carries values from one config generation to the next across a hot reload, in
    // memory, and that is all it does. So every setting on this page — presets, the
    // layout, thickness, motion, the lot — was lost the moment the shell exited. The
    // saved-preset list looked like it worked right up until you logged out.
    //
    // ── Two documents ─────────────────────────────────────────────────────────
    //   prefs    The live settings. Rewritten on every slider drag, so it lives in the
    //            STATE dir — deliberately OUTSIDE the shell directory, because the docs
    //            for `watchFiles` say "the configuration will be reloaded whenever any
    //            files change" and don't scope that to QML. A file that changes on every
    //            frame of a drag is not one to gamble on.
    //   presets  Named snapshots. Written only when you press Save, and meant to be
    //            read, hand-edited, shared and backed up — so it sits in the shell
    //            directory beside colorschemes/, where you'd look for it.
    //
    // Both go through the same JsonStore. Neither is watched: we are the only writer.

    JsonStore {
        id: prefsStore
        path: Quickshell.statePath("config.json")

        onLoaded: {
            const v = prefsStore.value ?? {}
            root._loading = true

            // `?? root.x` rather than a bare assign: a key absent from the document
            // (first run, or one added by a later version of this file) must keep the
            // property's own default, not overwrite it with undefined.
            root.barShape        = v.barShape        ?? root.barShape
            root.barMode         = v.barMode         ?? root.barMode
            root.barThickness    = v.barThickness    ?? root.barThickness
            root.barRoundness    = v.barRoundness    ?? root.barRoundness
            root.barInset        = v.barInset        ?? root.barInset
            root.barSpacing      = v.barSpacing      ?? root.barSpacing
            root.barOpacity      = v.barOpacity      ?? root.barOpacity
            root.barCentreAnchor = v.barCentreAnchor ?? root.barCentreAnchor
            root.barFontScale    = v.barFontScale    ?? root.barFontScale
            root.barIconScale    = v.barIconScale    ?? root.barIconScale
            root.railCollapsed   = v.railCollapsed   ?? root.railCollapsed
            root.motionScale     = v.motionScale     ?? root.motionScale
            root.motionEnabled   = v.motionEnabled   ?? root.motionEnabled
            root.barHoverGrow    = v.barHoverGrow    ?? root.barHoverGrow
            root.barGlass        = v.barGlass        ?? root.barGlass
            root.cavaBg          = v.cavaBg          ?? root.cavaBg
            root.settingsPage    = v.settingsPage    ?? root.settingsPage
            root.widgetsEnabled  = v.widgetsEnabled  ?? root.widgetsEnabled
            root.widgetGrid      = v.widgetGrid      ?? root.widgetGrid
            root.widgetOpacity   = v.widgetOpacity   ?? root.widgetOpacity
            root.widgetRoundness = v.widgetRoundness ?? root.widgetRoundness
            root.widgetGlass     = v.widgetGlass     ?? root.widgetGlass
            root.weatherPlace    = v.weatherPlace    ?? root.weatherPlace
            root.weatherLat      = v.weatherLat      ?? root.weatherLat
            root.weatherLon      = v.weatherLon      ?? root.weatherLon
            root.weatherMetric   = v.weatherMetric   ?? root.weatherMetric
            root.screenFrame     = v.screenFrame     ?? root.screenFrame
            root.frameThickness  = v.frameThickness  ?? root.frameThickness
            root.frameRoundness  = v.frameRoundness  ?? root.frameRoundness
            root.barFrame        = v.barFrame        ?? root.barFrame
            root.frameMerge      = v.frameMerge      ?? root.frameMerge
            root.wpeCurrent         = v.wpeCurrent         ?? root.wpeCurrent
            root.wpeAutoStart       = v.wpeAutoStart       ?? root.wpeAutoStart
            root.wpeFps             = v.wpeFps             ?? root.wpeFps
            root.wpeVsync           = v.wpeVsync           ?? root.wpeVsync
            root.wpeTarget          = v.wpeTarget          ?? root.wpeTarget
            root.wpeMute            = v.wpeMute            ?? root.wpeMute
            root.wpeVolume          = v.wpeVolume          ?? root.wpeVolume
            root.wpeKeepAudio       = v.wpeKeepAudio       ?? root.wpeKeepAudio
            root.wpePauseFullscreen = v.wpePauseFullscreen ?? root.wpePauseFullscreen
            root.wpeAudioProcessing = v.wpeAudioProcessing ?? root.wpeAudioProcessing
            root.wpeMouse           = v.wpeMouse           ?? root.wpeMouse
            root.wpeParallax        = v.wpeParallax        ?? root.wpeParallax
            root.wpeScenePalette    = v.wpeScenePalette    ?? root.wpeScenePalette
            root.themeMode          = v.themeMode          ?? root.themeMode
            root.wallTheming        = v.wallTheming        ?? root.wallTheming
            root.wallTarget         = v.wallTarget         ?? root.wallTarget
            root.wallShuffle        = v.wallShuffle        ?? root.wallShuffle
            root.wallShuffleMins    = v.wallShuffleMins    ?? root.wallShuffleMins


            if (v.moduleSettings) root.moduleSettings = v.moduleSettings

            // ── A saved layout can't be trusted, and this is why ──────────────
            // It was written by a previous version of this file. Modules added since
            // aren't in it (they'd silently never appear), and modules REMOVED since
            // still are (the bar would try to build a widget that no longer exists).
            // So it's reconciled against the catalogue rather than assigned: keep what
            // still exists, append what's new to its home region.
            if (v.layout && Object.keys(v.layout).length > 0)
                root.layout = root._reconcile(v.layout, v.knownModules ?? [])

            root._loading = false
        }
    }

    JsonStore {
        id: presetsStore
        path: Quickshell.shellPath("presets/bar.json")

        // An object rather than a bare array, so the file has somewhere to grow a
        // version tag or a second kind of preset without breaking every reader.
        defaults: ({ presets: [] })

        onLoaded: {
            const list = (presetsStore.value ?? {}).presets
            if (!Array.isArray(list)) return

            root._loading = true
            // Hand-editable file: drop anything without the shape the rest of this
            // section assumes, rather than letting a malformed entry reach loadPreset()
            // and throw on `c.layout`.
            root.presets = list.filter(p => p && typeof p.name === "string" && p.config)
            root._loading = false
        }
    }

    // Guards the write-back while the stores are populating us. Without it, restoring
    // nine properties one at a time would queue nine documents built from a half-applied
    // state. The debounce would collapse them to one correct write, so this is about not
    // doing pointless work rather than correctness.
    property bool _loading: false

    function _writePrefs() {
        if (root._loading || !prefsStore.ready) return
        prefsStore.value = {
            barShape:        root.barShape,
            barMode:         root.barMode,
            barThickness:    root.barThickness,
            barRoundness:    root.barRoundness,
            barInset:        root.barInset,
            barSpacing:      root.barSpacing,
            barOpacity:      root.barOpacity,
            barCentreAnchor: root.barCentreAnchor,
            barFontScale:    root.barFontScale,
            barIconScale:    root.barIconScale,
            railCollapsed:   root.railCollapsed,
            motionScale:     root.motionScale,
            motionEnabled:   root.motionEnabled,
            barHoverGrow:    root.barHoverGrow,
            barGlass:        root.barGlass,
            cavaBg:          root.cavaBg,
            settingsPage:    root.settingsPage,
            widgetsEnabled:  root.widgetsEnabled,
            widgetGrid:      root.widgetGrid,
            widgetOpacity:   root.widgetOpacity,
            widgetRoundness: root.widgetRoundness,
            widgetGlass:     root.widgetGlass,
            weatherPlace:    root.weatherPlace,
            weatherLat:      root.weatherLat,
            weatherLon:      root.weatherLon,
            weatherMetric:   root.weatherMetric,
            screenFrame:     root.screenFrame,
            frameThickness:  root.frameThickness,
            frameRoundness:  root.frameRoundness,
            barFrame:        root.barFrame,
            frameMerge:      root.frameMerge,
            wpeCurrent:         root.wpeCurrent,
            wpeAutoStart:       root.wpeAutoStart,
            wpeFps:             root.wpeFps,
            wpeVsync:           root.wpeVsync,
            wpeTarget:          root.wpeTarget,
            wpeMute:            root.wpeMute,
            wpeVolume:          root.wpeVolume,
            wpeKeepAudio:       root.wpeKeepAudio,
            wpePauseFullscreen: root.wpePauseFullscreen,
            wpeAudioProcessing: root.wpeAudioProcessing,
            wpeMouse:           root.wpeMouse,
            wpeParallax:        root.wpeParallax,
            wpeScenePalette:    root.wpeScenePalette,
            themeMode:          root.themeMode,
            wallTheming:        root.wallTheming,
            wallTarget:         root.wallTarget,
            wallShuffle:        root.wallShuffle,
            wallShuffleMins:    root.wallShuffleMins,


            moduleSettings:  root.moduleSettings,
            layout:          root.layout,

            // The catalogue as it stood when this was last written. Kept BESIDE the
            // layout, not inside it: every mutator rebuilds the layout through _clone(),
            // which only copies the three regions, so a marker stored in the layout
            // object would be dropped by the first drag and never seen again.
            knownModules:  root.moduleList.map(m => m.id)
        }
    }

    function _writePresets() {
        if (root._loading || !presetsStore.ready) return
        presetsStore.value = { presets: root.presets }
    }

    function _reconcile(saved, priorKnown) {
        const known = root.moduleList.map(m => m.id)
        const seen  = []
        const out   = {}

        for (const r of root.regionIds) {
            out[r] = (saved[r] ?? [])
                .map(g => g.filter(id => {
                    // Also drops DUPLICATES. A layout listing a module twice would build
                    // the widget twice, and for the tray or the visualizer that means two
                    // of the thing plus two of whatever process sits behind it.
                    if (known.indexOf(id) === -1 || seen.indexOf(id) !== -1) return false
                    seen.push(id)
                    return true
                }))
                .filter(g => g.length > 0)
        }

        // ── "You removed this" vs "this didn't exist yet" ─────────────────────
        // Both look identical in a saved layout — the module simply isn't there — and
        // they want opposite treatment. `priorKnown` is what the catalogue held last
        // time this config was written, so a module missing from BOTH the layout and
        // priorKnown is genuinely new and gets appended; a module missing from the
        // layout but present in priorKnown was deliberately removed and stays gone.
        //
        // An empty priorKnown means a config written before this was tracked. Treat
        // its absences as deliberate rather than re-adding everything the user took
        // out — the layout is the better evidence of intent than a marker we never
        // wrote.
        const prior = priorKnown.length > 0 ? priorKnown : known
        for (const m of root.moduleList) {
            if (seen.indexOf(m.id) === -1 && prior.indexOf(m.id) === -1)
                out[m.home].push([m.id])
        }

        return out
    }

    // Every preference funnels into one document, so each of these is the same call.
    // `knownModules` is stamped alongside the layout on every write, which is what lets
    // the next upgrade tell a module the user removed from one that didn't exist yet.
    onBarShapeChanged:       root._writePrefs()
    onBarModeChanged:        root._writePrefs()
    onBarThicknessChanged:   root._writePrefs()
    onBarRoundnessChanged:   root._writePrefs()
    onBarInsetChanged:       root._writePrefs()
    onBarSpacingChanged:     root._writePrefs()
    onBarOpacityChanged:     root._writePrefs()
    onBarCentreAnchorChanged: root._writePrefs()
    onBarFontScaleChanged:   root._writePrefs()
    onBarIconScaleChanged:   root._writePrefs()
    onLayoutChanged:         root._writePrefs()
    onRailCollapsedChanged:  root._writePrefs()
    onModuleSettingsChanged: root._writePrefs()
    onMotionScaleChanged:    root._writePrefs()
    onMotionEnabledChanged:  root._writePrefs()
    onBarHoverGrowChanged:   root._writePrefs()
    onCavaBgChanged:         root._writePrefs()
    onSettingsPageChanged:   root._writePrefs()
    onWidgetsEnabledChanged: root._writePrefs()
    onWidgetGridChanged:     root._writePrefs()
    onWidgetOpacityChanged:  root._writePrefs()
    onWidgetRoundnessChanged: root._writePrefs()
    onWidgetGlassChanged:    root._writePrefs()
    onBarGlassChanged:       root._writePrefs()
    onWeatherPlaceChanged:   root._writePrefs()
    onWeatherLatChanged:     root._writePrefs()
    onWeatherLonChanged:     root._writePrefs()
    onWeatherMetricChanged:  root._writePrefs()
    onScreenFrameChanged:    root._writePrefs()
    onFrameThicknessChanged: root._writePrefs()
    onFrameRoundnessChanged: root._writePrefs()
    onBarFrameChanged:       root._writePrefs()
    onFrameMergeChanged:     root._writePrefs()
    onWpeCurrentChanged:         root._writePrefs()
    onWpeAutoStartChanged:       root._writePrefs()
    onWpeFpsChanged:             root._writePrefs()
    onWpeVsyncChanged:           root._writePrefs()
    onWpeTargetChanged:          root._writePrefs()
    onWpeMuteChanged:            root._writePrefs()
    onWpeVolumeChanged:          root._writePrefs()
    onWpeKeepAudioChanged:       root._writePrefs()
    onWpePauseFullscreenChanged: root._writePrefs()
    onWpeAudioProcessingChanged: root._writePrefs()
    onWpeMouseChanged:           root._writePrefs()
    onWpeParallaxChanged:        root._writePrefs()
    onWpeScenePaletteChanged:    root._writePrefs()
    onThemeModeChanged:          root._writePrefs()
    onWallThemingChanged:        root._writePrefs()
    onWallTargetChanged:         root._writePrefs()
    onWallShuffleChanged:        root._writePrefs()
    onWallShuffleMinsChanged:    root._writePrefs()


    onPresetsChanged:        root._writePresets()
}
