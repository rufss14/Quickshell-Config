pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

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
    property var data: ({})

    FileView {
        id: colorsFile
        path: Quickshell.env("HOME") + "/.cache/wal/colors.json"

        // REQUIRED. FileView is lazy: without preload it does not read the file
        // until something calls text(), so `onLoaded` never fires on its own and
        // the palette silently stays empty — every role falls through to its
        // built-in fallback and the shell renders in Tokyo Night regardless of
        // the wallpaper. This is the line that makes the palette actually load.
        preload: true

        // Native inotify watch — no `cat`, no `inotifywait` subprocess.
        watchChanges: true
        onFileChanged: reload()

        onLoaded: {
            try {
                root.data = JSON.parse(colorsFile.text())
            } catch (e) {
                console.warn("Colors: colors.json is not valid JSON —", e)
            }
        }
        onLoadFailed: function(error) {
            console.warn("Colors: could not read colors.json —", error,
                         "· falling back to built-in defaults")
        }
    }

    // Force a re-read. Only needed by things that rewrite colors.json behind
    // our back and want the UI updated before inotify catches up.
    function reload() { colorsFile.reload() }

    // ── Raw ramp ──────────────────────────────────────────────────────────────
    // The unmapped pywal ramp. Nothing outside this file should use these —
    // they exist so the semantic roles below have something to be defined *in
    // terms of*, and so the color-scheme editor can show the raw ramp.
    // Fallbacks are Tokyo Night, used only until colors.json first loads.
    readonly property color base:  data?.special?.background || "#1a1b26"
    readonly property color text:  data?.colors?.color7      || "#a9b1d6"
    readonly property color ramp0: data?.colors?.color0      || "#15161e"
    readonly property color ramp1: data?.colors?.color1      || "#f7768e"
    readonly property color ramp2: data?.colors?.color2      || "#9ece6a"
    readonly property color ramp3: data?.colors?.color3      || "#e0af68"
    readonly property color ramp4: data?.colors?.color4      || "#7aa2f7"
    readonly property color ramp5: data?.colors?.color5      || "#bb9af7"
    readonly property color ramp9: data?.colors?.color9      || "#7dcfff"

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
            case "ramp2":   return root.ramp2
            case "ramp3":   return root.ramp3
            case "ramp5":   return root.ramp5
            case "ramp9":   return root.ramp9
            default:        return fallback
        }
    }

    // ── Accents ───────────────────────────────────────────────────────────────
    readonly property color primary:     ramp1
    readonly property color fgOnPrimary: base   // text/icon drawn ON a primary fill
    readonly property color focus:       ramp4

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

    readonly property color outline:       alpha(text, root._lightMode ? 0.32 : 0.22)
    readonly property color outlineBar:    alpha(text, 0.85)
    readonly property color outlineNested: alpha(text, 0.36)
    // Raised to sit at outlineBar's weight: hover should read as a change of HUE,
    // not a change of strength. At 0.55 against a 0.85 idle border, hovering a bar
    // pill visibly DIMMED its outline — the opposite of what a focus state says.
    readonly property color outlineFocus:  alpha(focus, 0.85)

    function outlineFor(elevation) {
        if (elevation >= Tokens.elevationNested) return root.outlineNested
        if (elevation <= Tokens.elevationBar)    return root.outlineBar
        return root.outline
    }

    // ── Content ───────────────────────────────────────────────────────────────
    // Formerly onSurface / onSurfaceVariant / onSurfaceDim — see the rule above.
    readonly property color fg:      text                // primary text
    readonly property color fgMuted: alpha(text, 0.70)   // secondary text, idle icons
    readonly property color fgDim:   alpha(text, root._lightMode ? 0.45 : 0.30)   // disabled, placeholder

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
    // The pills' Surface recipe, with barOpacity baked into the FILL only —
    // because the frame is drawn as loose fills and strokes across three files
    // (BarFrameEdge, FrameFusion, ScreenFrame) rather than as one Item an
    // `opacity:` could cover. The border is deliberately NOT faded: it is the same
    // border a pill draws, and Surface applies barOpacity to its fill alone for
    // exactly the same reason. Defined once here so the ring cannot drift from the
    // pills it fuses with.
    readonly property color frameFill: fade(surfaceFor(Tokens.elevationBar), Config.barOpacity)
    readonly property color frameLine: outlineFor(Tokens.elevationBar)
}
