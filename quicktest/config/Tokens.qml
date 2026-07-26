pragma Singleton
import Quickshell
import QtQuick

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
    readonly property int spacingXs:  2
    readonly property int spacingSm:  4
    readonly property int spacingMd:  8
    readonly property int spacingLg:  12
    readonly property int spacingXl:  16
    readonly property int spacingXxl: 24

    // ── Radius ────────────────────────────────────────────────────────────────
    // The corner language. `pill` is the interactive-control corner, `card` is
    // the surface corner. card > pill deliberately: a control sitting inside a
    // surface must round *tighter* than the surface, or the two corners fight.
    readonly property int radiusXs:   4
    readonly property int radiusSm:   8
    readonly property int radiusPill: 12
    readonly property int radiusCard: 16
    readonly property int radiusLg:   20
    readonly property int radiusFull: 999
    // Desktop widget tiles. Larger than radiusCard on purpose: these are 168px squares
    // floating on a wallpaper with no surrounding chrome, and at card radius they read
    // as slightly-rounded boxes rather than as the soft tiles macOS and iOS use. 22 on
    // a 168 tile is about the same corner-to-edge ratio as an iOS home-screen widget.
    readonly property int radiusWidget: 22

    // barShape "square mode" collapses every corner to this single value.
    readonly property int radiusSquare: 4

    // Resolves a corner for the current bar shape. Passing `radiusCard` from a
    // panel and `radiusPill` from a control is what keeps square-mode coherent
    // instead of each widget hardcoding its own square fallback.
    function corner(squareMode, normal) {
        return squareMode ? root.radiusSquare : normal
    }

    // ── Type ──────────────────────────────────────────────────────────────────
    // One family, five sizes. `body` is the base — everything else is defined
    // relative to how it reads next to body, not by arbitrary preference.
    // The installed family is "CodeNewRoman Nerd Font". There is no "… Propo" variant on
    // this system, and naming one meant Qt silently fell back: measured, the Propo string
    // rendered ASCII to exactly the same width as a deliberately bogus font name, while
    // the real family measured differently. The whole shell was in a fallback face and it
    // was invisible, because Qt's PER-CHARACTER fallback still found the Nerd glyphs — so
    // every icon looked right and only the letterforms were wrong.
    readonly property string fontFamily: "CodeNewRoman Nerd Font"
    readonly property string fontMono:   "CodeNewRoman Nerd Font Mono"

    // Below the reading scale. Numerals stamped inside a badge or a workspace dot, where
    // the container is the constraint and the digit only has to fit — not be read at
    // arm's length. It exists because those sites were writing 7 and 8 straight into
    // font.pixelSize: there was no tier down here, so they invented one each.
    readonly property int fontMicro:     8
    readonly property int fontCaption:  11   // badges, secondary metadata
    readonly property int fontLabel:    12   // button labels, list subtitles
    readonly property int fontBody:     13   // base — bar text, list items
    readonly property int fontTitle:    15   // panel headers, icons in pills
    readonly property int fontHeadline: 18   // panel hero text
    readonly property int fontDisplay:  24   // clock face, big numerals

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

    // (barPillHeight() lived here — the GROUP PILL's height, bar height less the
    // margin it floats in. BarGroup/BarRegion derive that from Config now, since both
    // inputs became user settings. Do not confuse the group pill's height with
    // pillHeight above: BarGroup used pillHeight once and every pill in the bar
    // rendered 24px instead of 32.)

    // Standard width for an icon-only control in the bar.
    readonly property int pillIconWidth: 40

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

    readonly property int borderWidth: 1

    // The bar pills and the screen frame — the shell's OUTER chrome — draw their
    // border at this width instead of borderWidth, so the shell's edge and the
    // compositor's window borders read as one system. Matches Hyprland's
    // `border_size` (2). Fine controls (cards, toggles, badges, the launcher)
    // stay on the 1px borderWidth hairline: a 2px border tuned for the outermost
    // surface reads as heavy on a nested control.
    readonly property int borderChrome: 2

    // Surfaces are drawn at slightly-under-opaque so the compositor blur and
    // the wallpaper underneath stay faintly present — this is what stops the
    // shell reading as a flat sheet pasted over the desktop.
    readonly property real surfaceOpacity: 0.97
}
