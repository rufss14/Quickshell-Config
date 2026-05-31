pragma Singleton
import Quickshell
import QtQuick

Singleton {
    id: theme

    // ── Robust alpha helper (accepts both hex strings AND QColor objects) ──
    function pw(input, alpha) {
        if (!input) return Qt.rgba(1, 1, 1, alpha)

        // Handle QColor objects directly
        if (input.r !== undefined && input.g !== undefined && input.b !== undefined) {
            return Qt.rgba(input.r, input.g, input.b, alpha)
        }

        // Handle hex string
        const hex = String(input).trim()
        if (hex.length < 7 || !hex.startsWith("#")) {
            return Qt.rgba(1, 1, 1, alpha)
        }

        return Qt.rgba(
            parseInt(hex.substring(1, 3), 16) / 255,
            parseInt(hex.substring(3, 5), 16) / 255,
            parseInt(hex.substring(5, 7), 16) / 255,
            alpha
        )
    }

    // ── Live pywal data ───────────────────────────────────────────────────────
    readonly property var pal: PywalColors.data

    // ── Raw palette ───────────────────────────────────────────────────────────
    readonly property color bg:     pal?.special?.background || "#1a1b26"
    readonly property color fg:     pal?.colors?.color7      || "#a9b1d6"
    readonly property color color1: pal?.colors?.color1      || "#f7768e"
    readonly property color color2: pal?.colors?.color2      || "#9ece6a"
    readonly property color color3: pal?.colors?.color3      || "#e0af68"
    readonly property color color4: pal?.colors?.color4      || "#7aa2f7"
    readonly property color color9: pal?.colors?.color9      || "#7dcfff"

    // ── Derived colors ────────────────────────────────────────────────────────
    readonly property color pillBg:      pw(pal?.colors?.color7 || "#a9b1d6", 0.07)
    readonly property color barBorder:   pw(pal?.colors?.color9 || "#7dcfff", 0.10)
    readonly property color dimFg:       pw(pal?.colors?.color7 || "#a9b1d6", 0.25)
    readonly property color wsEmpty:     pw(pal?.colors?.color1 || "#f7768e", 0.10)
    readonly property color wsOccupied:  pw(pal?.colors?.color1 || "#f7768e", 0.30)
    readonly property color wsFocused:   pw(pal?.colors?.color1 || "#f7768e", 1.00)
    readonly property color hoverAccent: pw(pal?.colors?.color1 || "#f7768e", 0.25)
    readonly property color hoverFull:   pw(pal?.colors?.color1 || "#f7768e", 1.0)

    // ── Unified button states (use these in ALL bar buttons) ──────────────────
    // idle
    readonly property color btnFg:       pw(pal?.colors?.color7 || "#a9b1d6", 0.70)
    readonly property color btnBg:       "transparent"
    // hovered
    readonly property color btnHoverBg:  pw(pal?.colors?.color1 || "#f7768e", 0.18)
    readonly property color btnHoverFg:  pw(pal?.colors?.color1 || "#f7768e", 1.00)
    // pressed / clicked
    readonly property color btnPressBg:  pw(pal?.colors?.color1 || "#f7768e", 0.35)
    readonly property color btnPressFg:  pw(pal?.colors?.color1 || "#f7768e", 1.00)
    // active (panel is open)
    readonly property color btnActiveBg: pw(pal?.colors?.color1 || "#f7768e", 0.22)
    readonly property color btnActiveFg: pw(pal?.colors?.color1 || "#f7768e", 1.00)

    // ── Typography ────────────────────────────────────────────────────────────
    readonly property string fontFamily: "CodeNewRoman Nerd Font Propo"
    readonly property int    fontSize:   13

    // ── Geometry ──────────────────────────────────────────────────────────────
    readonly property int barHeight:   40
    readonly property int pillHeight:  24
    readonly property int pillPadding: 12
    readonly property int barMargin:   4
    readonly property int barRadius:   18
    readonly property int pillRadius:  12

    function radius(barShape) {
        return barShape ? 4 : pillRadius
    }

    // ── Animation durations ───────────────────────────────────────────────────
    readonly property int animFast:   150
    readonly property int animNormal: 200
    readonly property int animSlow:   250
}
