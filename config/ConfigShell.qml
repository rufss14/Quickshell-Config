import Quickshell
import Quickshell.Io
import QtQuick
import "layout.js" as Layout
import "modules.js" as Catalogue
// ConfigShell — part of Config, split out of Config.qml by area (2026-11-08). The parts form
// one inheritance chain (ConfigShell ← ConfigEdges ← ConfigBarLayout ← ConfigSystem ←
// ConfigDesktop ← Config), so every property still lives on the one `Config` singleton
// and nothing that reads `Config.x` changed. A name declared further down the chain is
// reached as `root.x` here (a base file can't see it statically; `root` is the same object).
Singleton {
    id: root

    // ══ Bar — look ════════════════════════════════════════════════════════════
    property bool barShape: false          // true = square corners, flush to the edges

    // ── barLayout: the bar's two silhouettes ──────────────────────────────────
    // The bar is ONE surface, always — the pill shapes (three pills, or a pill per
    // group, with `barMode` and `barSpacing` beside them) were scrapped, for the top
    // bar and the sidebar both (the user's call). What's left is where it sits:
    //
    //   unified          one bar, floating clear of the frame
    //   unifiedAnchored  one bar welded into the frame — the frame's top edge
    //
    // A document from before carries a pills name, or no barLayout and the old
    // `frameMerge`: layout.js `unifiedLayout` maps each to its unified twin.
    //
    // ── This replaced `frameMerge` ────────────────────────────────────────────
    // That was a bool meaning "weld the pill to the band", which is exactly the
    // anchored axis. Keeping both would be two sources of truth for one fact.
    // The `barLayout` entry in `_persisted` reads an old config's frameMerge so an
    // existing install keeps the look it had.
    property string barLayout: "unifiedAnchored"

    readonly property bool barAnchored: root.barLayout === "unifiedAnchored"

    // ── barExtent / barSurfaceHeight ──────────────────────────────────────────
    // `barThickness` is the SPACE THE BAR OWNS. These two say what is actually
    // drawn in it, and every "where does the bar end" site reads one of them.
    //
    // Floating, the bar owns barThickness and draws a pill inset by barInset — so a
    // 44px bar shows a 32px pill. Anchored, the bar has no inset, and drawing the
    // full 44 made it visibly FATTER than the same bar one mode over: same
    // preference, 37% more mass. That is what "way too thick" was. An anchored bar
    // now takes the pill's height and reserves exactly that, so switching modes
    // changes the bar's SHAPE and never its weight.
    //
    // Floored so a thin bar with a large inset cannot collapse to nothing.
    readonly property int barExtent:
        root.barAnchored ? Math.max(24, root.barThickness - root.barInset * 2)
                         : root.barThickness

    // The height of the surface drawn inside that extent — a pill, or the anchored
    // bar itself, which fills its extent completely.
    readonly property int barSurfaceHeight:
        root.barAnchored ? root.barExtent
                         : root.barThickness - (root.barShape ? 0 : root.barInset) * 2

    // Where something that must sit UNDER the top bar starts (the reload card, the snip tool's
    // tray): BarToastHost's rule — flush under an anchored bar, a hair below a floating one.
    readonly property int belowBar: root.barAnchored ? root.barSurfaceHeight : (root.barExtent + 2)

    // ── The height every bar CONTROL sizes itself to ──────────────────────────
    // `Tokens.pillHeight` (24, fixed) was scattered across nine widget files as
    // a literal, so a composite widget (VolumePill, WorkspacesPill, TrayPill...)
    // never grew with `barIconScale` the way IconButton's own content-driven
    // height does — every icon-only toggle got taller at the Big preset, every
    // composite widget stayed at 24, and the group's shared inner pill (sized
    // to the tallest child) came out a different height in every group
    // depending on which kind of widget happened to be in it.
    //
    // Matches IconButton's own default `contentExtent` formula (an icon with no
    // label/symbol/glyph set falls through to `iconSize`) so a plain toggle and
    // a composite widget agree without either reading the other's code.
    readonly property int barPillHeight:
        Math.round(Math.max(Tokens.pillHeight,
                             Tokens.iconMd * root.barIconScale + Tokens.spacingSm * 2))

    // ── Per-monitor resolution scale ──────────────────────────────────────────
    // The bar — thickness, inset, icon/font scale, everything below that
    // determines how big its content reads — was tuned by eye at 1920x1080. A
    // screen that isn't gets this multiplier on top of the user's own choices, so
    // the bar reads the same physical size everywhere instead of shrinking to a
    // sliver on a 4K panel or overflowing a 1366x768 laptop screen.
    //
    // Fit-both-axes — the SMALLER of width/1920 and height/1080 — rather than
    // either alone: an ultrawide at 1080p gets no boost from its extra width
    // (nothing scales past what the vertical room actually allows), and a
    // narrower-than-16:9 screen scales down by its width instead of overflowing
    // while chasing the height ratio.
    //
    // Read off Quickshell.screens[0], not per-Bar-instance: every Bar shares this
    // one Config, so a mixed-resolution multi-monitor rig gets one consistent bar
    // rather than each screen disagreeing about what "the bar" should look like.
    // Clamped well short of the raw ratio so a tiny preview screen or an 8K panel
    // can't turn the bar into a sliver or a slab.
    readonly property real resScaleMin: 0.7
    readonly property real resScaleMax: 1.6
    readonly property real resScale: {
        const scr = Quickshell.screens[0]
        if (!scr || !scr.width || !scr.height) return 1.0
        const fit = Math.min(scr.width / 1920, scr.height / 1080)
        return Math.max(root.resScaleMin, Math.min(root.resScaleMax, fit))
    }

    readonly property var barLayoutOrder: ["unified", "unifiedAnchored"]
    readonly property var barLayoutLabels: ({
        "unified":         "Floating bar",
        "unifiedAnchored": "Bar on frame"
    })

    // Cycles in the order above — the bar module and the keybind both use this, so
    // there is one definition of "next mode".
    function cycleBarLayout() {
        const i = root.barLayoutOrder.indexOf(root.barLayout)
        root.barLayout = root.barLayoutOrder[(i + 1) % root.barLayoutOrder.length]
    }

    // Defaults synced to the "Rufss" preset (the bar actually in use), so an untouched
    // config, a Reset, and the built-in "Default" all match it. barInset already
    // equalled its Rufss value via the token; barThickness/barRoundness did not (this is
    // the second time this exact comment has had to correct itself against drift — see
    // layout.js's defaultLayout() for the other instance. Check the actual preset file
    // before trusting a "synced to X" claim; these two do not update each other.)
    //
    // ── Pref vs effective, and why these two split ────────────────────────────
    // `barThicknessPref`/`barInsetPref` are the raw pixel counts the user actually
    // set (Fine-tune slider, a bar preset, `applyBarSize`) — these are what gets
    // saved and compared against a preset's own numbers. `barThickness`/`barInset`
    // below are what everything else in the shell reads: the pref scaled by
    // `resScale`, so the same 58px "Big" bar reads as 58px on the 1920x1080 this
    // shell was tuned at and proportionally bigger or smaller anywhere else — with
    // no other file needing to know the difference, because every consumer
    // (BarRegion, BarGroup, ScreenFrame, CheatsheetPopup, FrameFusion, Bar.qml itself…)
    // already reads `Config.barThickness`/`Config.barInset` by these exact names.
    property int barThicknessPref: 58
    property int barRoundness: 17
    property int barInsetPref:     Tokens.barMargin    // 4

    readonly property int barThickness: Math.round(root.barThicknessPref * root.resScale)
    readonly property int barInset:     Math.round(root.barInsetPref * root.resScale)

    // ── Border width, the bar/frame's own chrome ──────────────────────────────
    // Was a flat `Tokens.borderChrome` (2px) — a scoped constant, deliberately NOT
    // the shell-wide `Tokens.borderWidth` hairline (see that token's own comment:
    // bumped once already to match Hyprland's `border_size = 2`, and 40 other
    // files/62 usages were left alone on purpose). This is the user-facing knob
    // for exactly that scoped value, same pattern as barRoundness/barInset: a
    // Tokens default, and this is where the user's own departure from it lives.
    //
    // Split in two on request: the PILLS (BarGroup, BarRegion) read `barBorderWidth`;
    // the RING (BarFrameEdge, ScreenFrame) reads `frameBorderWidth`, below. They used
    // to be one number on purpose — "so a pill's border, the frame's stroke and the
    // fillet's weld line can't drift out of step" — and that purpose hasn't gone away,
    // it's just no longer the only thing that matters. The one place the old
    // single-number reasoning still bites: FrameFusion's seam fillet is one arc of
    // constant stroke width bridging a pill border to a band border. When the two
    // differ, that arc cannot match both ends at once — the tangent nearer the band
    // will read a hair too thin or thick against BarFrameEdge's actual stroke.
    // FrameFusion follows `barBorderWidth` (the fillet is the pill's own border,
    // extended), so the mismatch shows up specifically as a width step right where
    // the fillet meets the band — visible only on a FUSED/merged bar, and only when
    // the two sliders are set far apart.
    property int barBorderWidth: Tokens.borderChrome

    // The ring's stroke: the top band (BarFrameEdge, drawn inside the bar's own
    // window) and the side/bottom strips (ScreenFrame). Same default as
    // `barBorderWidth` so an untouched config draws exactly as before either split.
    property int frameBorderWidth: Tokens.borderChrome

    // Shared by both sliders. Tokens.borderChrome (2) is the default; below
    // Tokens.borderWidth (1) the shell-wide hairline the border stops reading as
    // chrome at all, and past ~4 a pill or a ring strip starts looking outlined
    // rather than bordered.
    readonly property int borderWidthMax: 4

    function toggleShape() { root.barShape = !root.barShape }


    // How solid the pills are. Worth almost nothing without a compositor blur behind it
    // — see the namespace note in Bar.qml — because all it reveals otherwise is the
    // wallpaper.
    property real barOpacity: root.surfaceOpacity

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
    //
    // Raw preference, as set by the user — see the `barThicknessPref` note above
    // for why this splits from the `barFontScale`/`barIconScale` every widget
    // actually reads (below): those compose this with `resScale`.
    property real barFontScalePref: 1.18   // Rufss default
    property real barIconScalePref: 1.32   // Rufss default

    readonly property real barFontScale: root.barFontScalePref * root.resScale
    readonly property real barIconScale: root.barIconScalePref * root.resScale

    // ── barSize: three scales instead of five independent sliders ────────────
    // Thickness, roundness, inset, icon scale and font scale move TOGETHER —
    // that is what "how big is the bar" actually means. Five separate sliders
    // let you land on combinations nothing was designed for (a razor-thin bar
    // with huge icons, a fat bar with hairline text), so the page's primary
    // control is now one of these three; the sliders still exist underneath
    // (Settings → Bar → Size → Fine-tune) for anyone who wants to depart from
    // the three, same as the "Borders and frame" Disclosure just above it.
    //
    // `normal` is rufss's own hand-tuned bar (unchanged from the values this
    // file shipped with). `big` started as nucleus-shell's own measurements
    // (density 50, module height 34, radius 17) but landed at the top of
    // every slider's range instead: with a group's own pill now the only
    // thing on screen (see BarGroup/BarRegion — inner per-control pills are
    // gone, IconButton.container), that pill IS the visible size, and
    // nucleus's numbers read small once nothing smaller was competing with
    // them for attention.
    // Re-tuned narrower than the original spread: small/normal both read as too
    // small at the old 32/40, and 40→64 for normal→big was a bigger jump than
    // small→normal was, so the three didn't feel like one evenly-graduated
    // scale. Small and normal moved up, big came down a little, closing the
    // gaps to roughly even (8, 12) instead of the old (8, 24).
    readonly property var barSizePresets: ({
        small: {
            barThickness: 38, barRoundness: 10, barInset: 4,
            barFontScale: 0.95, barIconScale: 1.08
        },
        normal: {
            barThickness: 46, barRoundness: 14, barInset: Tokens.barMargin,
            barFontScale: 1.05, barIconScale: 1.22
        },
        big: {
            barThickness: 58, barRoundness: 17, barInset: 4,
            barFontScale: 1.18, barIconScale: 1.32
        }
    })
    readonly property var barSizeOrder: ["small", "normal", "big"]
    readonly property var barSizeLabels: ({ small: "Small", normal: "Normal", big: "Big" })

    function applyBarSize(name) {
        const p = root.barSizePresets[name]
        if (!p) return
        root.barThicknessPref = p.barThickness
        root.barRoundness     = p.barRoundness
        root.barInsetPref     = p.barInset
        root.barFontScalePref = p.barFontScale
        root.barIconScalePref = p.barIconScale
    }

    // Which preset the current five values match, so the picker can highlight
    // it — "" (none highlighted) once a Fine-tune slider has moved any of them
    // off a preset's exact values, same as a hand-edited config not matching
    // any saved bar preset.
    //
    // Compared against the *Pref values, not the resolution-scaled ones below —
    // otherwise this could never match on any screen but 1920x1080, and the
    // picker would show no preset selected on every other monitor.
    readonly property string barSizeName: {
        for (const name of root.barSizeOrder) {
            const p = root.barSizePresets[name]
            if (p.barThickness === root.barThicknessPref && p.barRoundness === root.barRoundness
             && p.barInset === root.barInsetPref && p.barFontScale === root.barFontScalePref
             && p.barIconScale === root.barIconScalePref) return name
        }
        return ""
    }

    // ══ Appearance — shell-wide ══════════════════════════════════════════════════
    // Settings → Appearance. These reach Tokens itself (see Tokens.qml), not one
    // widget's slice of it — every one of the ~1200 places across 90 files that reads
    // `Tokens.spacingMd`/`radiusCard`/`fontBody`/etc. moves with these, because none
    // of those properties changed name. Bar-only multipliers (barFontScale/
    // barIconScale above, barOpacity below) still exist and still compose on top —
    // this sets where the whole shell starts, they adjust the bar further from there.
    //
    // The three faces (prose, numerals, the big clock). "" ⇒ Tokens' own default, and so
    // is a name that isn't installed on THIS machine — Tokens checks, because Qt falls
    // back to a system font silently on a bad name and nothing else would show it. Not
    // validated here: this is the stored preference, and a config copied from another
    // machine should keep its choice until that font turns up.
    property string fontFamily:      ""
    property string fontMonoFamily:  ""
    property string fontBlockFamily: ""

    property real fontScale:    1.0
    property real densityScale: 1.0
    property real radiusScale:  1.0
    // The corner ladder: "default" (4/8/12/16/24, the card following Hyprland's window rounding)
    // or "ii" (6/12/17/23/30, End-4's — rounder, and no longer locked to the windows).
    property string cornerStyle: "default"
    // What holds an icon in a panel header and a settings section: "default" (a rounded square
    // in headers, the cookie in sections — as it always was), or one shape for both:
    // "squircle", "cookie", "clover", "circle".
    property string iconShape: "default"

    // ── shadowScale ───────────────────────────────────────────────────────────
    // How hard every surface casts. Same family as the three above and as
    // barOpacity: a shell-wide preference, not a per-widget knob, and every one of
    // the ~113 Surfaces moves with it because none of them names a shadow size.
    //
    // 0 is a supported setting, not just the bottom of a range — it turns shadows
    // off entirely AND collapses Tokens.shadowRoom(), so the windows that grew to
    // give a shadow somewhere to land stop reserving bleed they no longer need. It
    // is the escape hatch for a machine where ~20 live RectangularShadows cost more
    // than the depth is worth.
    property real shadowScale: 1.0
    readonly property real shadowScaleMin: 0.0
    readonly property real shadowScaleMax: 1.5

    // Clamped in the UI, not here — same split as motionScale (Config enforces
    // nothing; the slider's own `from`/`to` do). Below the minimum the settings UI
    // reading these tokens becomes the thing you can't see well enough to fix; above
    // the maximum a "card" stops reading as one.
    readonly property real fontScaleMin:    0.8
    readonly property real fontScaleMax:    1.3
    readonly property real densityScaleMin: 0.75
    readonly property real densityScaleMax: 1.5
    readonly property real radiusScaleMin:  0.5
    readonly property real radiusScaleMax:  1.5

    // The panel/card equivalent of `barOpacity` — everything at `elevationCard` and
    // above (settings, panels, popups, the launcher) rather than just the bar's own
    // pills. Reads Defaults.surfaceOpacity for its raw constant, not a literal 0.97 —
    // see Defaults.qml for why that value had to move out of Tokens.
    property real surfaceOpacity: Defaults.surfaceOpacity
    readonly property real surfaceOpacityMin: 0.5

    // High contrast: an accessibility switch, not a look. Text and accents are held to 7:1,
    // borders go solid and 2px, and every surface is drawn opaque, whatever the opacity
    // sliders say (the sliders keep their values, so switching it off gives the look back).
    // Read through Tokens (borderWidth, the *Opacity values) and PaletteRoles, never here.
    // Like motionReduced, not part of a bar preset or a look bundle.
    property bool highContrast: false

    // A shell-wide fallback accent, in the same vocabulary as every per-module and
    // per-widget accent: a ROLE NAME from `accentRoles` below, never a hex string.
    // "" keeps today's behaviour (every widget's own hardcoded default, usually
    // Colors.primary) — this only matters to a widget that reads it explicitly.
    property string accentRole: ""

    // ── Screen frame ──────────────────────────────────────────────────────────
    // Wraps the screen in a thin ring of the bar's material: a band along the top
    // (drawn by the bar itself, behind its pills), strips down the sides and along
    // the bottom, and concave corners where ring meets content. Purely visual; the
    // strips reserve their own space with the compositor so windows tile inside.
    property bool screenFrame:    true
    property int  frameThickness: 12
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
    // ── Removed: `barFrame` ───────────────────────────────────────────────────
    // This was "draw the top band without the ring's side and bottom strips" — the
    // band-only look. It has no meaning now: in the ANCHORED modes there is no band
    // at all (the bar itself occupies the top strip), and in the FLOATING modes a
    // band with nothing continuing down the sides is a stripe behind the pills
    // rather than a frame. Every site that asked `screenFrame || barFrame` now asks
    // `screenFrame`.
    //
    // Not migrated: an old config carrying `barFrame: true` simply loses it, and the
    // frame reads as off. That is the honest outcome — the look it selected no
    // longer exists.

    // ── Is a top BAND drawn behind the bar? ───────────────────────────────────
    // Only in the floating modes. Anchored, the BAR is the frame's top edge: it runs
    // the full width at full bar height, and the side strips meet its underside on
    // concave arcs. Drawing a band as well would put a second horizontal edge
    // through the middle of the thing that replaced it.
    readonly property bool frameBandVisible: root.screenFrame && !root.barAnchored

    // ── Whether the pill actually WELDS to whichever band is showing ──────────
    // `screenFrame`/`barFrame` decide if a band exists; this decides, independently,
    // whether the pill fuses into it or just floats cleanly below it. They used to
    // be the same switch — turning on Screen frame always welded the pill, with no
    // way to have the ring without the weld — which is also why the old "Merge
    // frame and pill" toggle went dead/locked the moment Screen frame was on: it
    // WAS Screen frame's own effect, not a separate choice. Default true so an
    // untouched config (or one from before this existed) looks exactly like it did.
    // ── Superseded by barLayout ───────────────────────────────────────────────
    // This was the "weld the pill into the band" switch, which is now the anchored
    // half of `barLayout`. It survives ONLY as a migration source: an existing
    // config.json carries frameMerge and no barLayout, and reading it here is what
    // keeps that install looking the way it did. Nothing else may read it —
    // `frameFused` now derives from `barAnchored`.
    //
    // Not persisted any more (see _persisted), so it disappears from config.json on
    // the next write and the migration becomes a no-op for everyone thereafter.
    property bool frameMerge: true

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
    // `barAnchored`, not `frameMerge`: welding is now the anchored half of barLayout.
    // The other two conditions are unchanged — there has to BE a band to weld to, and
    // the pill has to actually reach it.
    //
    // This is also what makes modes 2 and 4 degrade honestly rather than break: with
    // no band showing, `frameFused` is false and an anchored mode renders as its
    // floating twin instead of welding to nothing.
    // ── Now simply: is the bar flush against the screen's edges? ──────────────
    // It used to be a three-way test — a band has to exist, the user has to want the
    // weld, and the pill has to actually REACH the band — because fusing meant
    // welding a floating pill into a thin stripe above it, and a large `barInset`
    // left the pill too far away to weld.
    //
    // None of that survives the anchored redesign. The bar no longer reaches toward
    // a band; it IS the top edge, flush at y=0 and running the full width, so there
    // is no distance to fail to cross and nothing to be too far from. `barInset` is
    // simply not consulted in these modes (the settings slider says so).
    //
    // It also no longer requires a frame. An anchored bar with no side strips is a
    // solid top bar flush to the screen — a coherent look, not a broken one.
    readonly property bool frameFused: root.barAnchored

    // ── Who draws the line under the bar ──────────────────────────────────────
    // Exactly one thing may, or two strokes land on the same pixel and their
    // antialiased edges composite twice — a hardened, ragged line rather than a
    // sharper one. Three files need the answer (Bar, BarFrameEdge, FrameFusion),
    // so it is derived once here.
    //
    //   floating          the pills draw their own borders, all four sides. The
    //                     band above them has an underside of its own, which is
    //                     BarFrameEdge's, at a different y. No conflict.
    //   unifiedAnchored   + frame: the FRAME draws it, as one unbroken stroke —
    //                     up the left stub, round the arc, under the bar, round,
    //                     down the right stub. Nothing to join, so nothing to
    //                     misjoin. The bar goes borderless (its bleed already
    //                     clips the other three sides away).
    //                     no frame: there is no stub and no arc, so the bar's own
    //                     bottom border is the only candidate and draws in full.
    //
    // The unified+frame case was briefly given to the bar, to fix "Bar on frame
    // has no border" — which was real, but was the no-frame case only. Handing the
    // whole mode over meant erasing the bar's border at both ends and redrawing
    // the frame's arc on top of itself, and that double-stroke is what made the
    // top corners choppy.
    readonly property bool barDrawsUnderline:
        !(root.barAnchored && root.screenFrame)



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
    // ── The apron: extra bar-window height below the bar ─────────────────────
    // Anchored, it holds the CONCAVE CORNERS where the side strips meet the bar's
    // underside — those arcs hang `frameCornerRadius` px below the bar, and an arc
    // crossing a layer-shell surface boundary is clipped mid-curve.
    //
    // Floating, there is nothing below the pills to draw, so it is zero and the
    // shadow bleed (Bar.qml) sets the window height on its own.
    // `+ frameBorderWidth`, not just the radius: the corner's FILL reaches
    // `frameCornerRadius` below the bar, but the stroke that outlines it rides at
    // `radius + borderWidth/2` and is `borderWidth` wide. Reserving only the radius
    // leaves the last row of the arc outside the window, and a layer-shell surface
    // clips it flat — the same mid-curve clipping the fillets used to suffer, one
    // pixel wide and on the most visible corner of the shell.
    readonly property int frameApron:
        root.barAnchored ? root.frameCornerRadius + root.frameBorderWidth : 0

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
}
