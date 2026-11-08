import QtQuick
import QtQuick.Effects

// ── MonoIconEffect ────────────────────────────────────────────────────────────
// What Config.colorizeIcons means for a full-colour app icon (2026-10-31, the user's pick:
// "how end-4's shell does it" — its dock and tray desaturate 0.8 and lay the accent over
// at a tenth). The icon is kept whole: 80% desaturated, a tenth of the palette's primary
// on top. Its shapes and its lights and darks survive, so a logo on a disc still reads as
// one. Colorizing outright (colorization 1.0 — a multiply onto the icon's luminance, see
// TintedIcon) sank those into flat blobs; cutting a glyph out (ThemedAppIcon) drew some
// icons blank and left the rest in colour.
//
// Then, the same day, tried pulled into the scheme's colour (a colorize toward the palette's
// `vivid`) and turned back: the user preferred them GREY — fully desaturated, lifted a little so
// a dark disc doesn't sink. The shapes and the lights and darks are the icon; colour isn't.
//
// A layer effect, so an icon drawn as itself pays for no offscreen pass:
//     layer.enabled: Config.colorizeIcons
//     layer.effect:  MonoIconEffect {}
// ─────────────────────────────────────────────────────────────────────────────
MultiEffect {
    saturation: -1.0
    brightness: 0.15
}
