import QtQuick
import "../config"

// ── BarLabel ──────────────────────────────────────────────────────────────────
// The bar's one label style (2026-10-31, the user's pick: "one label style"): Material's
// label role — medium weight, the bar's font scale — with tabular digits. Before it, the
// volume level and the clock were bold, the battery, wifi and bluetooth labels a regular
// caption, and the keyboard layout a bold body size: four looks for one job.
//
// Tabular digits keep a number's width still as it changes — the clock's seconds, a level
// going 9% → 10% — where a proportional font's "1" is a third narrower than its "0"
// (Adwaita Sans at 14px: "1111" 23px, "0000" 36px; with tnum both 36px, measured on Qt 6.12).
// `font.features` takes an object; the parentheses keep the binding from parsing as a block.
//
// A label that means something quieter (the date under the clock, an artist under a title)
// stays a plain StyledText: medium weight is for the primary line.
// ─────────────────────────────────────────────────────────────────────────────
StyledText {
    variant:       "label"
    sizeScale:     Config.barFontScale
    font.weight:   Font.Medium
    font.features: ({ tnum: 1 })
}
