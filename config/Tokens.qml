pragma Singleton
import Quickshell
import QtQuick
import "../services/icons.js" as IconMap

// ── Tokens ────────────────────────────────────────────────────────────────────
// The shell's design vocabulary: spacing, radius, type, and elevation.
//
// Nothing in this file knows about color (see Palette) or time (see Motion).
// Every widget in the shell sizes and spaces itself from these values — a
// literal `8` or `12` appearing in a QML file is a bug, because it means that
// widget has opted out of the scale and will drift the moment the scale moves.
//
// The scales are geometric, not arbitrary: spacing steps by 4 (the smallest
// unit that survives fractional scaling on a HiDPI Wayland output), and radius
// steps to stay in a fixed ratio with the surfaces it rounds, so a card nested
// in a card never has to guess its own corner.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── Spacing ───────────────────────────────────────────────────────────────
    // xs  hairline gaps (icon → its own badge)
    // sm  intra-component (icon → its label)
    // md  between siblings in a row/column
    // lg  component → its container's edge (the default padding)
    // xl  between logical groups inside one surface
    // xxl section separation inside a large panel
    //
    // Scaled by `Config.densityScale` (Settings → Appearance) — a preference the
    // whole shell shares, not a per-widget knob. Untouched (1.0) these are exactly
    // the constants below; every one of the ~960 places that reads `Tokens.spacingMd`
    // etc. moves with the slider for free, because none of them changed name.
    readonly property int spacingXs:  Math.round(2  * Config.densityScale)
    readonly property int spacingSm:  Math.round(4  * Config.densityScale)
    readonly property int spacingMd:  Math.round(8  * Config.densityScale)
    readonly property int spacingLg:  Math.round(12 * Config.densityScale)
    readonly property int spacingXl:  Math.round(16 * Config.densityScale)
    readonly property int spacingXxl: Math.round(24 * Config.densityScale)

    // ── Radius ────────────────────────────────────────────────────────────────
    // The corner language: four roles, plus one for the smallest details. Pick by what
    // the thing IS, not by what number looks right:
    //
    //   radiusXs    inner detail — a checkbox, a tick chip, a progress cap
    //   radiusSm    row — a list row, a text field, an icon chip, a stepper button
    //   radiusPill  control — a button, a chip, a toggle track, a bar pill
    //   radiusCard  card — every surface: panels, popups, toasts, settings sections
    //   radiusXl    hero — the one big card at the top of a page, and nothing else
    //
    // Each role must round TIGHTER than the one it sits inside, or the two corners
    // fight: a control in a card, a row in a card, a card in a hero.
    //
    // `radiusCard` is Hyprland's window `rounding` (from the shared blend.lua), so a
    // card corner and a window corner match; keep blend.rounding within a few px of
    // radiusPill (12) so card > pill holds. There used to be a 20 and a 32 between
    // card and hero; every surface that wore them is a card now, and the hero is 24.
    //
    // All scaled by `Config.radiusScale`, same reasoning as spacing above. `radiusFull`
    // (999, the "pill"/circle sentinel) and `radiusSquare` (square mode's collapsed
    // corner) are deliberately EXEMPT — scaling a sentinel changes what it means, and
    // square mode's whole point is a small fixed corner regardless of the shell's
    // roundness preference elsewhere.
    // ── Square corners are global (2026-10-18) ──────────────────────────────────
    // `Config.barShape` ("Square corners") used to square only the bar and the few things that asked
    // (`Tokens.corner(Config.barShape, …)`); a panel, a card or a button stayed rounded beside it. The whole
    // ladder below now collapses to `radiusSquare` while it is on, so everything built from a role — every
    // Surface, card, chip, field — follows without each one asking. `radiusFull` (999: circles, the round
    // dots and toggles) is the one rung left alone.
    readonly property bool _square: Config.barShape
    readonly property int radiusXs:   root._square ? root.radiusSquare : Math.round((root._roundII ? 6 : 4) * Config.radiusScale)
    // Config.cornerStyle "ii" swaps the whole ladder for End-4's rounder one (6 / 12 / 17 / 23 /
    // 30 against 4 / 8 / 12 / 16 / 24): more nesting room, a softer shell. In that style the
    // card corner is ii's own and no longer follows Hyprland's window rounding, so a card
    // and a window beside it differ by a few px; "default" keeps them locked together.
    readonly property bool _roundII: Config.cornerStyle === "ii"
    readonly property int radiusSm:   root._square ? root.radiusSquare : Math.round((root._roundII ? 12 : 8)  * Config.radiusScale)
    readonly property int radiusPill: root._square ? root.radiusSquare : Math.round((root._roundII ? 17 : 12) * Config.radiusScale)
    // How opaque a SECTION card is (see PaletteRoles.section): 1 = solid, as the panels were; a little
    // under, and the drifting cookies behind the panel show through the cards instead of stopping at them.
    readonly property real sectionAlpha: Config.highContrast ? 1 : 0.85

    // ── State layers: Material 3's calibrated alphas ──────────────────────────
    // The wash a control wears over its own fill, in its content colour, per state. These
    // are the spec's numbers (hover 8%, focus 10%, pressed 10%, dragged 16%) and StateLayer's
    // defaults. A control too small for 8% to read (a 24px bar button) raises its own hover,
    // as IconButton does; it doesn't move these.
    readonly property real stateHover: 0.08
    readonly property real stateFocus: 0.10
    readonly property real statePress: 0.10
    readonly property real stateDrag:  0.16
    readonly property int radiusCard: root._square ? root.radiusSquare : Math.round((root._roundII ? 23 : (Blend.v.rounding || 16)) * Config.radiusScale)
    readonly property int radiusXl:   root._square ? root.radiusSquare : Math.round((root._roundII ? 30 : 24) * Config.radiusScale)
    readonly property int radiusFull: 999
    // Desktop widget tiles: 168px squares floating on a wallpaper with no surrounding
    // chrome, so they take the iOS-widget corner-to-edge ratio instead of a role.
    //
    // Reads Defaults, not a literal 22 — Config.widgetRoundness's own default reads
    // THIS property, so the raw constant has to live somewhere Config can borrow from
    // without Tokens reading Config right back for the same value. See Defaults.qml.
    readonly property int radiusWidget: root._square ? root.radiusSquare : Math.round(Defaults.radiusWidget * Config.radiusScale)

    // barShape "square mode" collapses every corner to this single value. Not scaled —
    // same reasoning as radiusFull.
    readonly property int radiusSquare: 4

    // Resolves a corner for the current bar shape. Passing `radiusCard` from a
    // panel and `radiusPill` from a control is what keeps square-mode coherent
    // instead of each widget hardcoding its own square fallback.
    function corner(squareMode, normal) {
        return squareMode ? root.radiusSquare : normal
    }

    // ── Type ──────────────────────────────────────────────────────────────────
    // Seven sizes. `body` is the base — everything else is defined relative to how it
    // reads next to body, not by arbitrary preference. Three faces, below.
    // ── Three faces, each one the user's to change ────────────────────────────
    // Settings → Type & shape picks them from what is installed. Three, not one,
    // because they do three different jobs and "the monospace variant of whatever font
    // the user just typed" does not exist — most fonts have none — so the mono and the
    // display face are chosen on their own rather than derived:
    //
    //   fontFamily  prose and labels                 Config.fontFamily
    //   fontMono    numerals that must line up       Config.fontMonoFamily
    //                (throughput, the clock)
    //   fontBlock   the huge lockscreen/greeter clock Config.fontBlockFamily
    //
    // "" in Config means "the default below". A NAME THAT ISN'T INSTALLED ALSO MEANS
    // THE DEFAULT: a config.json copied from another machine, or a font uninstalled
    // since, used to leave the shell in Qt's silent fallback face with nothing saying so
    // (its per-character fallback still finds the Nerd glyphs, so only the letterforms
    // were wrong). `installed()` is what the picker uses to say so out loud.
    //
    // Evaluated against the installed list once: fonts do not come and go while the
    // shell runs.
    readonly property var _installed: Qt.fontFamilies()
    // Every installed family worth offering, for the font picker. Names starting with
    // "." are system-internal faces fontconfig lists but nothing should pick, and the
    // bundled icon faces (below) are not prose.
    readonly property var families: {
        const list = root._installed.filter(n => n !== "" && n[0] !== "."
            && n !== root.fontSymbols && n !== root.fontGlyphs)
        // The bundled prose face (below) may register after `_installed` was read.
        if (root.fontUi !== "" && list.indexOf(root.fontUi) === -1) list.unshift(root.fontUi)
        return list
    }
    function installed(name) {
        return name !== "" && (name === root.fontUi || root._installed.indexOf(name) !== -1)
    }
    function _pick(name, fallback) { return root.installed(name) ? name : fallback }

    // The installed family is "CodeNewRoman Nerd Font". There is no "… Propo" variant
    // on this system, and naming one meant Qt silently fell back: measured, the Propo
    // string rendered ASCII to exactly the same width as a deliberately bogus font name.
    // The 2026-10-31 pass made the bundled Google Sans Flex (`fontUi`, below) the default over
    // Adwaita Sans/Inter so every install read the same with nothing to install; reverted
    // 2026-11-01, back to Adwaita Sans as the user's actual pick — same walk-the-installed-list
    // shape as defaultBlock below, so a machine without it still gets the bundled face rather
    // than Qt's silent fallback.
    readonly property string defaultFamily: root.installed("Adwaita Sans") ? "Adwaita Sans"
        : root.fontUi !== "" ? root.fontUi : "CodeNewRoman Nerd Font"
    readonly property string defaultMono:   "CodeNewRoman Nerd Font Mono"
    readonly property string fontFamily: root._pick(Config.fontFamily,     root.defaultFamily)
    readonly property string fontMono:   root._pick(Config.fontMonoFamily, root.defaultMono)

    // ── The block face, for one job: a huge clock ─────────────────────────────
    // Not a prose family. This exists because a lockscreen clock at 120px is not
    // reading text, it is a piece of the composition, and CodeNewRoman's mono is a
    // TYPEWRITER shape — narrow, humanist, thin at display size. A geometric extra-bold
    // is what "blocky" actually means: square terminals, closed apertures, heavy stems.
    //
    // ── Resolved here, not handed to Qt as a fallback list ────────────────────
    // The obvious build is a list bound to `font.families`, and it does not exist: the
    // QML `font` value type in Qt 6.11 has `family`, singular, and assigning `families`
    // is a hard load error — which is a load error in the LOCKSCREEN, the one file in
    // this shell that must never fail to load.
    //
    // So the fallback is walked here instead, against the installed list, so this
    // resolves to a name known to exist and the consumer just sets `font.family`. This
    // config is published and JetBrains Mono is not guaranteed
    // anywhere; without the walk, a machine without it lands on Qt's default sans rather
    // than on the shell's own mono.
    readonly property string defaultBlock: {
        const have = root._installed
        const wanted = ["JetBrains Mono ExtraBold", "JetBrains Mono", root.defaultMono]
        for (let i = 0; i < wanted.length; i++)
            if (have.indexOf(wanted[i]) !== -1) return wanted[i]
        return root.defaultFamily
    }

    // The user's pick wins; otherwise the walk above.
    readonly property string fontBlock: root._pick(Config.fontBlockFamily, root.defaultBlock)

    // ── The icon faces: the shell's own, never installed ──────────────────────
    // Both live in assets/fonts/, cut by `scripts/material-symbols-map.py --emit`
    // out of the fonts on the machine that ran it, with family names of their own:
    //
    //   fontSymbols  Quicktest Symbols — the Material Symbols this tree names
    //   fontGlyphs   Quicktest Glyphs  — every Nerd Font codepoint it spells (brand
    //                marks, the About page's Codicons, MDI glyphs drawn as glyphs)
    //
    // An installed icon font is NOT used, on purpose: otf-codenewroman-nerd 3.5.0
    // shifted every glyph ID under the running shell and drew every icon as a
    // different one, and an AUR rebuild of Material Symbols can rename a ligature
    // just as quietly. A file in the repo only changes when the repo does.
    //
    // A held FontLoader, not one per icon: the load is once, and `name` is the
    // family the file declares. Local files load synchronously, so `Ready` is
    // already true by the first binding that reads it.
    //
    // `""` only if a file is missing — a broken checkout, not a supported state.
    // AboutPage reports it; MaterialIcon then draws in Qt's fallback face.
    // After regenerating the fonts, restart the shell (ALT+Q) rather than relying
    // on a hot reload: Qt keeps the previous file registered under the same family.
    readonly property FontLoader _symbolsFace: FontLoader {
        source: Qt.resolvedUrl("../assets/fonts/QuicktestSymbols.ttf")
    }
    readonly property FontLoader _glyphsFace: FontLoader {
        source: Qt.resolvedUrl("../assets/fonts/QuicktestGlyphs.otf")
    }
    readonly property string fontSymbols:
        root._symbolsFace.status === FontLoader.Ready ? root._symbolsFace.name : ""
    readonly property string fontGlyphs:
        root._glyphsFace.status === FontLoader.Ready ? root._glyphsFace.name : ""

    // ── The bundled prose face ────────────────────────────────────────────────
    // Google Sans Flex (assets/fonts/GoogleSansFlex.ttf, unmodified, OFL — its licence beside
    // it): a variable font with weight, width, optical size, slant and roundness axes. Loaded
    // like the icon faces, so the default type doesn't depend on what a machine has installed.
    readonly property FontLoader _uiFace: FontLoader {
        source: Qt.resolvedUrl("../assets/fonts/GoogleSansFlex.ttf")
    }
    readonly property string fontUi:
        root._uiFace.status === FontLoader.Ready ? root._uiFace.name : ""
    readonly property bool hasSymbols: root.fontSymbols !== "" && root.fontGlyphs !== ""

    // The face for a string that may be an icon glyph: the glyph face if it starts
    // with one, the prose face otherwise. For the few Text elements that show a
    // `glyph` straight (IconButton's glyph path, a ContextMenu row) — a glyph there
    // used to come from whichever installed font Qt fell back to.
    function glyphFamily(text) {
        return IconMap.isGlyph(text) ? root.fontGlyphs : root.fontFamily
    }

    // ── Variable-font axis defaults ───────────────────────────────────────────
    // Axis values are still type: a literal 400 sitting in a widget is the same
    // bug a literal 8 would be. The bundled face keeps three live axes, FILL 0–1,
    // wght 100–700 and opsz 20–48 (MaterialIcon sets it from the icon's size); GRAD (0) is
    // pinned INTO the file when it is cut (PINNED_AXES in the generator).
    //
    // FILL has no default here on purpose: it is per-icon STATE (a bell fills when
    // do-not-disturb turns on), so it belongs to the call site, not to the scale.
    readonly property int symbolWeight: 400
    // How much sturdier a fully FILLED icon is drawn than an outlined one (wght units on
    // top of symbolWeight, scaled by the fill): ii goes from regular to semibold, 400 → 600.
    readonly property int symbolFillBoost: 200

    // Below the reading scale. Numerals stamped inside a badge or a workspace dot, where
    // the container is the constraint and the digit only has to fit — not be read at
    // arm's length. It exists because those sites were writing 7 and 8 straight into
    // font.pixelSize: there was no tier down here, so they invented one each.
    // Scaled by `Config.fontScale`. This composes with, and does not replace,
    // `StyledText.sizeScale` — the mechanism `Config.barFontScale`/`barIconScale`
    // already use for the bar's own extra multiplier. A shell-wide scale sets where
    // everything starts; the bar's sliders adjust further from there, same as they
    // always have.
    readonly property int fontMicro:     Math.round(10 * Config.fontScale)   // the floor: nothing renders below this
    readonly property int fontCaption:   Math.round(11 * Config.fontScale)   // badges, secondary metadata
    readonly property int fontLabel:     Math.round(12 * Config.fontScale)   // button labels, list subtitles
    readonly property int fontBody:      Math.round(13 * Config.fontScale)   // base — bar text, list items
    readonly property int fontTitle:     Math.round(15 * Config.fontScale)   // panel headers, icons in pills
    readonly property int fontHeadline:  Math.round(18 * Config.fontScale)   // panel hero text
    readonly property int fontDisplay:   Math.round(24 * Config.fontScale)   // clock face, big numerals

    // Above the reading scale. The single large number a desktop widget is built
    // around — a calendar's day, a countdown's count, a clock's digits, a timer.
    // A 168px tile is looked at from further than a panel and carries one figure,
    // so it wants a tier the panels never needed: every widget was writing 34–62
    // straight into font.pixelSize and inventing its own. `Md` is the number that
    // shares its tile with a header and a caption; `Lg` is the number that IS the
    // tile. Both still pair with `fontSizeMode: Text.HorizontalFit` at the call
    // site so an eight-character string (seconds, AM/PM) can't overrun.
    readonly property int fontNumeralMd:  Math.round(38 * Config.fontScale)
    readonly property int fontNumeralLg:  Math.round(56 * Config.fontScale)
    // The two clock faces that stand alone on a screen: the lock and greeter time, and the
    // desktop clock. Too big for the numeral tiers, and each was a literal before.
    readonly property int fontHero:       Math.round(132 * Config.fontScale)
    readonly property int fontClock:      Math.round(72 * Config.fontScale)

    // ── Icon sizing ───────────────────────────────────────────────────────────
    readonly property int iconSm: 14
    readonly property int iconMd: 16
    readonly property int iconLg: 20
    readonly property int iconXl: 28

    // ── Bar / control geometry ────────────────────────────────────────────────
    // barHeight and barMargin are the DEFAULTS Config starts from, not the live
    // values — the bar reads Config.barThickness/barInset, which the user can change
    // in Settings. Tokens must never import Config for this reason: the tokens are
    // what the defaults are defined as.
    readonly property int barHeight:   40
    readonly property int barMargin:   4

    // pillHeight is the height of a CONTROL (a button, the clock, the wifi pill)
    // — the thing that sits *inside* a group's pill. It is NOT the height of the
    // pill itself.
    readonly property int pillHeight:  24
    readonly property int pillPadding: 12
    // The room a Scrollbar needs at a page's edge: its hover width and a margin each side.
    // Content kept clear of it is never covered by it (2026-10-31: settings' bars sat over
    // the right-hand tiles).
    readonly property int scrollRoom: 8 + root.spacingSm * 2

    // (barPillHeight() lived here — the GROUP PILL's height, bar height less the
    // margin it floats in. BarGroup/BarRegion derive that from Config now, since both
    // inputs became user settings. Do not confuse the group pill's height with
    // pillHeight above: BarGroup used pillHeight once and every pill in the bar
    // rendered 24px instead of 32.)

    // Standard width for an icon-only control in the bar.
    readonly property int pillIconWidth: 40

    // What the sidebar's hover cards (the stats' and the clips') are measured in —
    // five of these wide, their badges three quarters of one. NOT the sidebar's
    // cell: that follows the top bar's size, and a card that shrank with it would be
    // too narrow to read. The dock button's own default size, where they started.
    readonly property int sideCardUnit: Math.round(48 * Config.densityScale)

    // fieldHeight is a single-line TEXT INPUT's height (components/InputField.qml).
    // Taller than pillHeight: a field holds a text baseline with room above and below
    // it, where a pill holds a glyph.
    //
    // A token rather than the literal `32` it replaced, which was written out four
    // times — InputField and the three page-local copies of it (DiscordPage's
    // CredField, WidgetsPage's OptField, HyprlandPage's Field). OptField had already
    // drifted to `pillHeight + spacingSm`, so one page's text boxes were 4px shorter
    // than every other page's.
    //
    // NOT density-scaled, deliberately, and for the same reason pillHeight and
    // barHeight above aren't: in this shell a CONTROL is a fixed size and the space
    // around it is what breathes. (Worth revisiting as a set — the padding inside a
    // field does scale while the field does not — but that is a decision about every
    // control at once, not one to smuggle in here.)
    readonly property int fieldHeight: 32

    // ── Elevation ─────────────────────────────────────────────────────────────
    // Layering is expressed as a level, not as a pile of per-widget border and
    // shadow values. Palette turns a level into actual colors; this is just the
    // ladder. Higher level = closer to the user = stronger separation from what
    // is behind it.
    //   0  the bar/dock surface sitting on the desktop
    //   1  a panel/card floating above the bar
    //   2  a control nested inside a card (needs to out-contrast the card fill)
    //   3  a popup/menu floating above a card
    readonly property int elevationBar:    0
    readonly property int elevationCard:   1
    readonly property int elevationNested: 2
    readonly property int elevationPopup:  3

    // ── Elevation → cast shadow ───────────────────────────────────────────────
    // Material 3 expresses depth as a dp level with a shadow attached; this shell
    // expressed it as fill tone and border weight and cast nothing at all. These
    // four functions are the bridge, and they are the only place a shadow's size
    // is decided.
    //
    // ── The ladder is NOT monotone, deliberately ──────────────────────────────
    // M3's levels are literally "distance from the user", so bigger is always
    // further forward. The `elevation*` values above are SEMANTIC, and one of them
    // breaks that: `elevationNested` means a control sitting INSIDE a card. It is
    // not floating above anything — it is flush with the surface it is cut into —
    // so it must cast nothing. Mapping it to "higher than a card" would put a
    // shadow under every inset pill in the bar and every row of every settings
    // page, which reads as grime rather than as depth.
    //
    //   Bar    (0)  a pill/dock sitting on the wallpaper — a hint of lift
    //   Card   (1)  a panel floating above the bar
    //   Nested (2)  inside a card. Nothing.
    //   Popup  (3)  a menu floating above a card
    //
    // Scaled by Config.shadowScale, same shape as densityScale/radiusScale above.
    function shadowDp(elevation) {
        const dp = elevation === root.elevationNested ? 0
                 : elevation === root.elevationCard   ? 6
                 : elevation === root.elevationPopup  ? 12
                 :                                      2
        return dp * Config.shadowScale
    }

    // The three curves that turn a dp into pixels. Taken from caelestia, which took
    // them from M3's elevation overlays — a shadow does not scale linearly with
    // height, it spreads faster than it darkens.
    //
    // `shadowSpread` going NEGATIVE is the load-bearing one: it insets the shadow's
    // rect so the blur has somewhere to bloom without the solid centre showing
    // through the surface. Every surface in this shell is translucent
    // (Tokens.surfaceOpacity, Config.barOpacity), so unlike an opaque M3 card, what
    // sits under the fill is visible. This is the lever if shadows read as dirt
    // rather than as lift.
    function shadowBlur(dp)    { return Math.pow(dp * 5, 0.7) }
    function shadowSpread(dp)  { return -dp * 0.3 + Math.pow(dp * 0.1, 2) }
    function shadowOffsetY(dp) { return dp / 2 }

    // ── The one function both sides call ──────────────────────────────────────
    // How far a shadow reaches past its surface, in whole pixels.
    //
    // A PanelWindow is a Wayland surface and paint STOPS at its edge, so a window
    // sized exactly to its content clips the shadow off flat. The windows that had
    // no slack (a floating card sized exactly to its content) grow by this much, and the shadow draws
    // from the same three curves the reservation was computed from.
    //
    // That shared call is the whole point. `leadHeight()`/`unitsFor()` exist in
    // OverviewLyrics for exactly this reason: when the side that RESERVES room and
    // the side that DRAWS disagree by a single pixel, the symptom is "still
    // clipping" and it survives several rounds of fixing, because each side looks
    // correct on its own. Do not inline either half.
    function shadowRoom(elevation) {
        const dp = root.shadowDp(elevation)
        if (dp <= 0) return 0
        return Math.ceil(root.shadowBlur(dp) + root.shadowOffsetY(dp)
                         + Math.max(0, root.shadowSpread(dp)))
    }

    readonly property int borderWidth: Config.highContrast ? 2 : 1   // 2px under high contrast

    // The bar pills and the screen frame — the shell's OUTER chrome — draw their
    // border at this width instead of borderWidth, so the shell's edge and the
    // compositor's window borders read as one system. IS Hyprland's `border_size`,
    // from the shared blend.lua — no longer a copy that drifts. Fine controls
    // (cards, toggles, badges, the launcher) stay on the 1px borderWidth hairline:
    // a 2px border tuned for the outermost surface reads as heavy on a nested control.
    readonly property int borderChrome: Blend.v.border_size || 2

    // Surfaces are drawn at slightly-under-opaque so the compositor blur and
    // the wallpaper underneath stay faintly present — this is what stops the
    // shell reading as a flat sheet pasted over the desktop.
    //
    // Reads Config directly (a value, not a multiplier — same shape as barOpacity),
    // for the same reason radiusWidget reads Defaults: Config.barOpacity's own
    // default already borrows THIS property, so the raw constant lives in
    // Defaults.qml, one level below both.
    readonly property real surfaceOpacity: Config.highContrast ? 1 : Config.surfaceOpacity

    // The bar's and the sidebar's own opacity, as DRAWN: the user's value, or solid under
    // high contrast. Draw with these; the Config values are what the sliders edit. (A
    // desktop widget's is WidgetFrame.effOpacity, which also has a per-tile override.)
    readonly property real barOpacity:  Config.highContrast ? 1 : Config.barOpacity
    readonly property real sideOpacity: Config.highContrast ? 1 : Config.sideOpacity
}
