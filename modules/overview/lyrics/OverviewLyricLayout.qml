import QtQuick
import Quickshell
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/lyricsmotion.js" as LyricMotion
import "../../../services/romajialign.js" as RomajiAlign
import "../../../services/mediasource.js" as MediaSource
import "../../../services/clockfmt.js" as ClockFmt
import "../../../state"

// ── One type size for the whole card ──────────────────────────────────────
// Measured, not estimated from character counts: the face is proportional, so "iiii"
// and "WWWW" are nothing like the same width and a count-based guess clips the wide
// ones. FontMetrics measures the real string without needing the item to exist, which
// also keeps this off any rendered child — binding to a child's implicitWidth and
// feeding it back up is the re-entry that bit CavaBG.
// ── Qt lays the text out; this file only animates it ──────────────────────
// Everything here used to be hand-rolled: per-character widths, where a line breaks,
// how a right-aligned line is offset. That is Qt's text engine reimplemented, and it
// was wrong in a different way for every script — the lyrics face has no Japanese
// glyphs so the measurements were fiction, CJK has no spaces to break on, a line
// mixing scripts defeated the whole-line tests, and an aligned line was offset without
// being resized. Each fix was correct and the next script found a new hole.
//
// So the engine decides now. A TextEdit — Text has no positionToRectangle(), only
// TextEdit and TextInput do — is handed the line and asked where every glyph landed.
// Shaping, font fallback, per-script line breaking and alignment all come for free and
// stay correct for scripts nobody here has tested.
//
// The font settings below MUST match the glyphs exactly, letterSpacing included, or
// the positions describe a layout that is not the one on screen.
// (Was OverviewLyrics's inline `LyricLayout`.)
TextEdit {
    readOnly: true
    activeFocusOnPress: false
    selectByMouse: false
    // TextEdit carries padding by default; a lyric line is not a text box.
    padding: 0
    wrapMode: TextEdit.Wrap
    font.family:        Tokens.fontFamily
    font.pixelSize:     Tokens.fontHeadline
    font.bold:          true
    font.letterSpacing: 0.4
    // Laid out, never painted. The animated glyphs are what you see.
    opacity: 0
}
