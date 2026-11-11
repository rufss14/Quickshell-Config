import QtQuick
import "../services/palette.js" as Palette
import "../services/contrast.js" as Contrast

// ── PaletteRoles ──────────────────────────────────────────────────────────────
// Every colour role of the shell, derived from ONE pywal palette (`data`): the raw
// ramp, the accents, surfaces, outlines, content, states, status, the frame material.
// `Colors` (the singleton) holds one for the shared palette and one per screen, so a
// screen whose workspace has its own wallpaper wears that wallpaper's colours while the
// other screen wears its own (services/WorkspaceTheme). A visual file reads its own
// screen's through `Colors.of(QsWindow.window)`; a service reads `Colors.x`, the shared.
//
// The rules and the reasons for every role are in the comments below — they moved here
// from Colors.qml unchanged.
// ─────────────────────────────────────────────────────────────────────────────
QtObject {
    id: root

    // { special: {…}, colors: { color0…color15 } } — what this palette is made from.
    property var data: ({})

    // ── Easing to a new palette ───────────────────────────────────────────────
    // A screen whose workspace changes to another wallpaper shouldn't snap to its colours:
    // assign the palette it should wear to `goal` (instead of `data`) and `data` blends there
    // over `easeMs`, every role following (services/palette.js lerpPalette). A change that
    // arrives mid-ease starts from the colours worn at that moment. 0 ms (animations off,
    // or Motion.snap under a wallpaper wave's snapshots) is an instant switch.
    //
    // In `steps` steps, not per frame: each step re-evaluates every colour binding on the
    // screen, and twelve over a third of a second reads as continuous.
    property var goal: null
    property int easeMs: 0
    // Settable: a quick ease (Colors' peek) wants the same twelve steps squeezed into a shorter time,
    // so that each lands about a frame apart instead of one jump every 28ms.
    property int steps: 12
    property var _from: ({})
    property real _t: 1
    property int _stepShown: 12
    onGoalChanged: {
        if (root.goal === null) return
        const hasNow = !!(root.data?.special || root.data?.colors)
        if (root.easeMs <= 0 || !hasNow) {
            root._ease.stop()
            root._t = 1
            root.data = root.goal
            return
        }
        root._from = root.data
        root._stepShown = 0
        root._t = 0
        root._ease.restart()
    }
    on_TChanged: {
        if (root.goal === null) return
        if (root._t >= 1) { root.data = root.goal; root._stepShown = root.steps; return }
        const s = Math.floor(root._t * root.steps)
        if (s === root._stepShown) return
        root._stepShown = s
        root.data = Palette.lerpPalette(root._from, root.goal, root._t)
    }
    property Animation _ease: NumberAnimation {
        target: root
        property: "_t"
        from: 0
        to: 1
        duration: Math.max(1, root.easeMs)
        easing.type: Motion.ambient
    }

    // ── Raw ramp ──────────────────────────────────────────────────────────────
    // The unmapped pywal ramp. Nothing outside this file should use these —
    // they exist so the semantic roles below have something to be defined *in
    // terms of*, and so the color-scheme editor can show the raw ramp.
    // ── The fallback is monochrome, on purpose ────────────────────────────────
    // The shell never wears a built-in COLOUR scheme. With no colors.json, Wallpaper
    // runs pywal on the current wallpaper (Wallpaper._bootstrapPalette); these slots
    // are only what shows before that lands, or for good when it can't run (no pywal,
    // no wallpaper, theming off, the run failed). Black ground, white ink, greys for
    // the accents — and a palette missing one slot falls through to its grey here.
    // primary (ramp1) and focus (ramp4) still differ, by lightness, because the two
    // must never be the same colour (Colors.qml, "The two accents").
    // The sixteen ANSI slots, also what ansi() falls back to.
    readonly property var _mono: ["#000000", "#ffffff", "#d0d0d0", "#b0b0b0",
                                  "#909090", "#c0c0c0", "#e0e0e0", "#ffffff",
                                  "#404040", "#ffffff", "#d0d0d0", "#b0b0b0",
                                  "#909090", "#c0c0c0", "#e0e0e0", "#ffffff"]
    readonly property color base:  data?.special?.background || root._mono[0]
    readonly property color text:  data?.colors?.color7      || root._mono[7]
    readonly property color ramp0: data?.colors?.color0      || root._mono[0]
    readonly property color ramp1: data?.colors?.color1      || root._mono[1]
    readonly property color ramp2: data?.colors?.color2      || root._mono[2]
    readonly property color ramp3: data?.colors?.color3      || root._mono[3]
    readonly property color ramp4: data?.colors?.color4      || root._mono[4]
    readonly property color ramp5: data?.colors?.color5      || root._mono[5]
    readonly property color ramp9: data?.colors?.color9      || root._mono[9]

    // ── The terminal's own sixteen ─────────────────────────────────────────────
    // The ANSI palette, straight off the pywal ramp — which is exactly what the
    // terminal is themed with, so a preview drawn in these colours is drawn in the
    // colours the terminal will actually use.
    //
    // The roles above deliberately don't cover this: they map the ramp onto shell
    // semantics (primary, danger, focus), and ANSI 0-15 is not a semantic space —
    // "green" in a fastfetch keyColor means literally colour 2, not "success".
    // Reaching for `ramp2` there would be a coincidence that breaks the first time
    // the roles are remapped.
    //
    // 8-15 are the bright half. pywal only emits sixteen when it feels like it, so
    // a missing bright colour falls back to its normal-intensity twin rather than
    // to black — which is what the terminal does anyway on a palette that short.
    function ansi(i) {
        const n = Math.max(0, Math.min(15, Math.round(i)))
        const c = root.data?.colors ?? {}
        const hit = c["color" + n]
        if (hit) return hit
        if (n >= 8) {
            const dim = c["color" + (n - 8)]
            if (dim) return dim
        }
        // The monochrome fallback the roles above use, so a preview shown with no
        // palette is greyscale rather than an unreadable black-on-black rectangle.
        return root._mono[n]
    }

    // Re-tint a role at a given alpha. The one legal way to make a translucent
    // variant of a color — hand-rolling Qt.rgba(c.r, c.g, c.b, a) at call sites
    // is how alpha values drift out of sync across widgets.
    function alpha(c, a) {
        if (!c) return Qt.rgba(1, 1, 1, a)
        return Qt.rgba(c.r, c.g, c.b, a)
    }

    // Scale a color's EXISTING alpha, rather than replacing it.
    //
    // The distinction matters wherever a translucent role is drawn outside the item
    // whose `opacity:` normally covers it. `alpha(outline, barOpacity)` looks like it
    // dims the outline; it actually discards outline's own 0.22 and returns the text
    // colour at barOpacity — about four times too strong. Item opacity MULTIPLIES,
    // so anything imitating it must multiply too. (That bug shipped once: the screen
    // frame's border rendered far brighter than the pill borders it continues.)
    function fade(c, mult) {
        if (!c) return Qt.rgba(1, 1, 1, mult)
        return Qt.rgba(c.r, c.g, c.b, c.a * mult)
    }

    // Blend `t` of `b` into `a`, staying fully OPAQUE.
    //
    // This is the counterpart to alpha(): use alpha() when you genuinely want to see
    // through something (a hover wash over a surface, a dim over the desktop), and
    // mix() when you want a solid colour that merely *looks* a shade lighter. Reaching
    // for alpha() to lighten a fill only works while the thing behind it happens to be
    // `base` — which is precisely the assumption the overview broke.
    function mix(a, b, t) {
        if (!a) return b
        if (!b) return a
        return Qt.rgba(a.r + (b.r - a.r) * t,
                       a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t,
                       1.0)
    }

    // ── NAMING RULE: no property may start with "on" + an uppercase letter ────
    // QML reserves that form for signal handlers.
    //
    // These roles were originally named after Material's convention — the
    // foreground for a surface was "on-surface", the foreground for a primary
    // fill was "on-primary". In QML that is a trap: because `surface` and
    // `primary` exist as properties, QML generates their change signals, and a
    // property declared with the reserved prefix is swallowed as handler syntax.
    // It never receives its binding and sits at a default-constructed BLACK.
    //
    // It fails SILENTLY — no warning, no error, just #000000. Every piece of
    // body text in this shell rendered black until this was caught.
    //
    // The roles are unchanged; only the names are. Do not reintroduce the
    // Material spelling.

    // ── Role lookup ───────────────────────────────────────────────────────────
    // name → colour, for the one caller that picks a role at RUNTIME rather than at
    // author time: the per-module accent in settings, where the choice is data.
    //
    // Deliberately a whitelist and not `root[name]`. A generic property lookup would
    // resolve "surface" or "outlineFocus" — or, worse, let a config file name any
    // property on this singleton and get it painted into the bar. This returns
    // `fallback` for anything it doesn't recognise, so a stale role name from an older
    // config degrades to the module's own default instead of a black pill.
    function role(name, fallback) {
        switch (name) {
            case "primary": return root.primary
            case "focus":   return root.focus
            case "primaryContainer": return root.primaryContainer
            case "ramp1":   return root.ramp1
            case "ramp2":   return root.ramp2
            case "ramp3":   return root.ramp3
            case "ramp4":   return root.ramp4
            case "ramp5":   return root.ramp5
            case "ramp9":   return root.ramp9
            case "vivid":   return root.vivid
            case "fg":      return root.fg
            default:        return fallback
        }
    }

    // ── Accents ───────────────────────────────────────────────────────────────
    // ── The ramp is ordered by HUE, so a slot guarantees nothing about legibility ──
    // `primary` and `focus` are pywal slots — color1 and color4 — and pywal has no
    // tone ladder. Nothing makes the slot that means "this is the active thing"
    // visible against the surface it is drawn on.
    //
    // Measured on one real wallpaper: color1 came out #6B4F53, contrast 2.52 against
    // the background — the LOWEST of all sixteen — while color4 sat at 7.47. So every
    // active state in the shell (the focused workspace, every hovered pill, every
    // module's default accent) rendered in the least visible colour available, and
    // the workspace marker for "live on your other monitor" outshouted the workspace
    // you were actually on. It looked like the bar was broken. It was the palette
    // being sampled by index.
    //
    // `legible()` enforces a floor and does nothing when the slot already clears it —
    // an already-bright palette comes back byte-identical. 4.5 because `fgOnPrimary`
    // (= base) is drawn ON primary, so this is a text contrast, not a decorative one.
    // It walks toward `text` rather than white, so a warm palette stays warm.
    //
    // Material You has no such problem: its primary is generated at a fixed light
    // TONE for dark schemes. This is the equivalent floor for a hue-ordered ramp.
    //
    // High contrast (Config.highContrast) raises every text floor in this file from 4.5 to
    // 7:1 (WCAG AAA), lifts the secondary text roles to match, and draws outlines solid.
    readonly property bool _hc: Config.highContrast
    readonly property real _textFloor: root._hc ? 7.0 : 4.5
    readonly property color primary:
        Palette.legible(String(root.ramp1), String(root.base), root._textFloor, String(root.text))
    readonly property color fgOnPrimary: base   // text/icon drawn ON a primary fill
    // The ramp's most colourful slot, made legible the same way — for a TINT meant to carry the
    // scheme's colour (the wallpaper effects' glow, WallFx; 2026-10-31). `primary` is the first
    // slot made legible, and on a muted wallpaper that is near grey (#4F374B, saturation 0.18,
    // while #811E47 at 0.62 sat two slots on).
    // Chroma as HSV saturation × value. Not an accent: states stay on `primary`.
    readonly property color vivid: {
        const c = [root.ramp1, root.ramp2, root.ramp3, root.ramp4, root.ramp5]
        let best = c[0]
        for (const x of c)
            if (x.hsvSaturation * x.hsvValue > best.hsvSaturation * best.hsvValue) best = x
        return Palette.legible(String(best), String(root.base), root._textFloor, String(root.text))
    }
    readonly property color focus:
        Palette.legible(String(root.ramp4), String(root.base), root._textFloor, String(root.text))

    // ── Surfaces ──────────────────────────────────────────────────────────────
    // Elevation → fill. Higher levels sit closer to the user, so they lift away
    // from what's behind them by getting *lighter*, not by gaining a shadow.
    //
    // ── These are OPAQUE, and that is the whole point ─────────────────────────
    // They used to be `alpha(text, 0.07)` / `alpha(text, 0.10)` — i.e. a 7%-opaque
    // grey. That works only under one unstated assumption: that the surface is
    // sitting directly on top of `base`. A pill inside the bar is, so it looked
    // right, and the bug hid for as long as everything lived in the bar.
    //
    // The overview broke that assumption. Its dock, cards, popovers and workspace
    // cells sit on a semi-transparent backdrop over the live desktop — so a 90%-
    // transparent fill let the wallpaper straight through, and the whole overlay
    // read as frosted GLASS with no palette in it at all.
    //
    // Mixing against `base` instead produces the identical colour where the old
    // code happened to work (a 7% white over base IS base mixed 7% toward white),
    // and a correct one everywhere else. Nothing is left to guess what's behind it.
    //
    // The secondary mix toward `primary` is what makes the greys read as *this
    // wallpaper's* greys — a Material-You tonal surface rather than a neutral one.
    readonly property color surface:          mix(base, primary, 0.03)   // bar, dock, cards
    readonly property color surfaceContainer: mix(mix(base, text, 0.07), primary, 0.08)
    readonly property color surfaceHigh:      mix(mix(base, text, 0.12), primary, 0.10)
    // A SECTION card — a panel's flat container for a group of controls (the clock and colours panels).
    // surfaceContainer at Tokens.sectionAlpha, so the cookies drifting behind the panel read through it.
    // Not for controls (a switch, a tray of chips), which stay solid.
    readonly property color section: alpha(surfaceContainer, Tokens.sectionAlpha)

    // ── The accent's container (Material 3's primaryContainer) ────────────────
    // A quiet fill in the accent's hue, for the ONE emphasised thing in a region that is
    // not a button: a desktop tile's hero (today's date, the current hour, a gauge's disc).
    // `primary` itself is too loud for a resting fill that size. Mixed from `base`, so it
    // follows a light scheme too: a pale tint there, a deep one here.
    // `fgOnPrimaryContainer` is the accent pulled toward the text colour, then guaranteed
    // 4.5:1 on the container — text on it, so the text floor.
    readonly property color primaryContainer: mix(surfaceContainer, primary, 0.26)
    readonly property color fgOnPrimaryContainer:
        Palette.legible(String(mix(primary, text, 0.6)), String(root.primaryContainer), root._textFloor, String(root.text))

    function surfaceFor(elevation) {
        switch (elevation) {
            case Tokens.elevationNested: return root.surfaceContainer
            case Tokens.elevationPopup:  return root.surfaceHigh
            default:                     return root.surface
        }
    }

    // ── Outlines ──────────────────────────────────────────────────────────────
    // outline       — a surface against the desktop/wallpaper behind it.
    // outlineNested — a surface against *another surface*. Must be stronger:
    //                 at 0.12 alpha over a card's own fill (rather than over a
    //                 wallpaper) a border reads as nothing at all, and the
    //                 nested thing looks like the parent simply changed size.
    // outlineFocus  — hovered / open / keyboard-selected. This is the `focus`
    //                 accent's primary job.
    // The two levels must stay clearly APART. A bar group pill (outline) contains
    // inset pills (outlineNested); if their borders read as the same weight, the
    // nesting collapses visually and the bar looks like one flat mass. Raising one
    // means raising the other.
    // outlineBar    — a TRANSLUCENT surface sitting on the wallpaper: the bar's
    //                 pills, the dock, the screen frame. Their fill is see-through
    //                 by design, so the border is the only thing actually drawing
    //                 the shape's edge against arbitrary wallpaper behind it, and
    //                 it has to carry that alone. `outline`'s 0.22 was tuned for an
    //                 opaque fill, where the edge is already legible without it.
    // ── Mode-aware alphas ─────────────────────────────────────────────────────
    // These translucencies were tuned on dark palettes, and the SAME alpha is
    // perceptually weaker the other way round: 30% of dark text over white is
    // barely a smudge, where 30% of light text over near-black still reads.
    // Only the weakest roles compensate — the strong ones (0.7+) survive the
    // flip fine, and per-mode-tuning everything would be a second theme.
    readonly property bool _lightMode: Config.themeMode === "light"

    // Under high contrast the ladder keeps its order (outline < nested < bar) at full strength.
    readonly property color outline:       alpha(text, root._hc ? 0.6 : root._lightMode ? 0.32 : 0.22)
    readonly property color outlineBar:    alpha(text, root._hc ? 1.0 : 0.85)
    readonly property color outlineNested: alpha(text, root._hc ? 0.75 : 0.36)
    // Raised to sit at outlineBar's weight: hover should read as a change of HUE,
    // not a change of strength. At 0.55 against a 0.85 idle border, hovering a bar
    // pill visibly DIMMED its outline — the opposite of what a focus state says.
    readonly property color outlineFocus:  alpha(focus, root._hc ? 1.0 : 0.85)

    function outlineFor(elevation) {
        if (elevation >= Tokens.elevationNested) return root.outlineNested
        if (elevation <= Tokens.elevationBar)    return root.outlineBar
        return root.outline
    }

    // ── Content ───────────────────────────────────────────────────────────────
    // Formerly onSurface / onSurfaceVariant / onSurfaceDim — see the rule above.
    readonly property color fg:      text                // primary text
    // ── The contrast guard ─────────────────────────────────────────────────────
    // fgMuted and fgDim are an alpha of `text`, so their contrast follows the wallpaper: over the
    // bundled schemes the same alpha gave 3.7:1 to 6.3:1, and an untested wallpaper can land lower.
    // The alphas below are FLOORS: where one already reaches its target over the lightest common
    // ground (surfaceHigh — the worst case, as scripts/check-contrast.py measures) nothing changes;
    // where it doesn't, it is lifted to the least alpha that does (services/contrast.js, tested).
    // fgMuted stays at least `+0.06` above fgDim, so the two never collapse into one.
    // fgFaint is MEANT to recede and is not guarded. Under high contrast the targets are 4.5
    // (fgDim) and 7 (fgMuted), and fgFaint is raised so a disabled control is still legible.
    readonly property real _dimAlpha: Contrast.alphaFor(text, surfaceHigh, root._hc ? 4.5 : 4.0,
                                                        root._lightMode ? 0.68 : 0.66)
    readonly property real _mutedAlpha: Math.max(Contrast.alphaFor(text, surfaceHigh, root._hc ? 7.0 : 4.5, 0.72),
                                                 Math.min(1, root._dimAlpha + 0.06))
    readonly property color fgMuted: alpha(text, root._mutedAlpha)   // secondary text, idle icons
    // Measured against the lightest common ground (surfaceHigh) on every bundled scheme
    // (scripts/check-contrast.py): fgMuted 4.2-5.4:1, fgDim 4.0-6.3:1 (contrast.js lifts either
    // role on a palette that falls short) — secondary text and placeholders, fine for UI but
    // under AA for small body copy — and fgFaint ~2:1, which is only for things that are
    // MEANT to recede (a disabled control, a decorative glyph). Real text never uses fgFaint.
    readonly property color fgDim:   alpha(text, root._dimAlpha)   // tertiary text, placeholder (floor 0.66 / 0.68 light)
    readonly property color fgFaint: alpha(text, root._hc ? 0.55 : root._lightMode ? 0.45 : 0.30)   // disabled, decorative

    // ── Interactive states ────────────────────────────────────────────────────
    // One ladder, used by every control in the shell. A control is exactly one
    // of: idle → hovered → pressed, and orthogonally active (toggled on).
    readonly property color stateIdleFg:     fgMuted
    readonly property color stateHoverBg:    alpha(primary, 0.18)
    readonly property color stateHoverFg:    primary
    readonly property color statePressBg:    alpha(primary, 0.35)
    readonly property color statePressFg:    primary
    readonly property color stateActiveBg:   alpha(primary, 0.22)
    readonly property color stateActiveFg:   primary

    // ── Status ────────────────────────────────────────────────────────────────
    // Semantic, not decorative. `danger` shares a hue with `primary` because
    // pywal's ramp1 is the only reliably-red slot — that collision is inherent
    // to the source palette, not a naming accident, and it's why destructive
    // actions must also carry an icon or label rather than leaning on color.
    readonly property color success: ramp2
    readonly property color warning: ramp3
    readonly property color danger:  ramp1
    readonly property color info:    ramp9

    // ── Workspaces ────────────────────────────────────────────────────────────
    // A three-step ramp of one hue, so occupancy reads as intensity rather than
    // as three unrelated colors.
    readonly property color wsEmpty:    alpha(primary, 0.10)
    readonly property color wsOccupied: alpha(primary, 0.30)
    readonly property color wsFocused:  primary

    // ── Screen frame material ─────────────────────────────────────────────────
    // The pills' Surface recipe, baked flat — because the frame is drawn as loose
    // fills and strokes across three files (BarFrameEdge, FrameFusion, ScreenFrame)
    // rather than as one Item an `opacity:` could cover. Defined once here so the
    // ring cannot drift from the pills it fuses with.
    //
    // ── BOTH of Surface's translucencies, not just one ────────────────────────
    // Baking the bar opacity alone is not enough: `Surface` also carries a plain
    // `opacity: Tokens.surfaceOpacity` (Surface.qml:63), the shell-wide
    // translucency preference, and item opacity multiplies EVERYTHING — fill and
    // border alike.
    //
    // A pill draws its fill at barOpacity × surfaceOpacity and its border at
    // outlineBar's own 0.85 × surfaceOpacity, so the ring must too. One factor short,
    // at the 0.97/0.97 defaults, is a pill at α 0.941 against a frame at α 0.970: the
    // same colour on paper, measurably not on screen, along every edge the two share.
    // Both are Tokens' DRAWN values, so high contrast makes the ring solid with the pills.
    //
    // `fade`, not `alpha`: it MULTIPLIES the role's existing alpha, which is what
    // item opacity does. See fade()'s own comment.
    readonly property real frameAlpha: Tokens.barOpacity * Tokens.surfaceOpacity
    readonly property color frameFill: fade(surfaceFor(Tokens.elevationBar), root.frameAlpha)
    readonly property color frameLine: fade(outlineFor(Tokens.elevationBar), Tokens.surfaceOpacity)

    // ── Shadow ────────────────────────────────────────────────────────────────
    // The one colour in this file that is NOT wallpaper-derived, and the reason is
    // physical rather than stylistic: a shadow is occlusion, not a tint. Material 3's
    // own `shadow` role is #000000 in every generated scheme, light and dark alike —
    // Material 2 tinted it toward the primary and abandoned that, because a coloured
    // shadow reads as a glow rather than as depth.
    //
    // So this is a named role with a comment saying why, the same sanctioned shape as
    // DiscordCallBar's discordRed/discordGreen — not a hardcoded hex that slipped
    // past the palette rule.
    //
    // What DOES change with the mode is strength, not hue. Over a near-white light
    // palette the shadow is most of what separates a card from its background, so it
    // carries more of the work; over a dark palette the surfaces already separate by
    // fill, and past ~0.55 the shadow reads as soot rather than as lift.
    //
    // Both numbers are tuned against TRANSLUCENT surfaces (see Tokens.shadowSpread —
    // a RectangularShadow fills its whole rect, including under the surface, so at a
    // low Config.barOpacity some of the shadow shows THROUGH the pill it belongs to).
    readonly property color shadow: "#000000"
    readonly property real  shadowStrength: root._lightMode ? 0.34 : 0.55
    readonly property color shadowCast:     alpha(root.shadow, root.shadowStrength)
}
