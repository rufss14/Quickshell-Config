import QtQuick
import Quickshell
import "../config"

// ── StyledText ────────────────────────────────────────────────────────────────
// Text that already knows the shell's font.
//
// Every Text element in the shell repeated `font.family: Theme.fontFamily` —
// 228 times — and picked a pixelSize from nowhere in particular. Defaulting both
// means a plain `StyledText { text: "..." }` is already correct, and a widget
// only writes a size when it genuinely means something other than body.
//
// `variant` maps to the type scale rather than to a raw number, so "this is a
// caption" survives a change to what caption *is*.
// ─────────────────────────────────────────────────────────────────────────────
Text {
    id: root

    // "micro" | "caption" | "label" | "body" | "title" | "headline" | "display"
    property string variant: "body"

    // ── sizeScale ─────────────────────────────────────────────────────────────
    // A multiplier on whatever the variant resolves to. 1.0 everywhere except the bar,
    // which passes Config.barFontScale for text and Config.barIconScale for the Nerd
    // Font glyphs it also renders through this component.
    //
    // It's a property rather than StyledText reading Config itself, because this is used
    // by the overview, the panels and the notifications too — none of which have any
    // business resizing when the BAR's font slider moves.
    //
    // Not named `scale`: Item.scale already exists and is a render transform, which would
    // stretch the glyph rather than ask for a bigger one.
    property real sizeScale: 1.0

    // "normal" | "muted" | "dim" — how loud this text is against its surface.
    property string emphasis: "normal"

    // ── rich ──────────────────────────────────────────────────────────────────
    // Opt into <b>, <i>, <u> and <font color> in `text`. Off by default, and that
    // default is load-bearing: Text.StyledText silently swallows anything that looks
    // like markup, so a plain label containing "<3" or an app title like "a > b" would
    // render wrong — and only for the unlucky strings. Prose that this file authors can
    // opt in; anything carrying a name, a title, or a path from elsewhere must not.
    //
    // Text.StyledText, not Text.RichText: it's a small subset parsed by a fast path,
    // which is all this needs, and it can't pull in an external resource.
    property bool rich: false
    textFormat: root.rich ? Text.StyledText : Text.PlainText

    readonly property int baseSize: {
        switch (variant) {
            case "micro":    return Tokens.fontMicro
            case "caption":  return Tokens.fontCaption
            case "label":    return Tokens.fontLabel
            case "title":    return Tokens.fontTitle
            case "headline": return Tokens.fontHeadline
            case "display":  return Tokens.fontDisplay
            default:         return Tokens.fontBody
        }
    }

    font.family: Tokens.fontFamily
    font.pixelSize: Math.round(root.baseSize * root.sizeScale)

    color: {
        switch (emphasis) {
            case "muted": return Colors.of(QsWindow.window).fgMuted
            case "dim":   return Colors.of(QsWindow.window).fgDim
            default:      return Colors.of(QsWindow.window).fg
        }
    }

    Behavior on color { ColorAnimation { duration: Motion.respond } }
}
