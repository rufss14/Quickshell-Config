.pragma library

// ── palette.js ────────────────────────────────────────────────────────────────
// Colour maths for the scheme editor. Pure functions, no QML, no state.
//
// Lived inline in ColorSchemePanel.qml as six one-line functions wedged between
// process definitions and UI. Separating it is the standing rule in this repo —
// presentation in QML, logic in JS — and it means the derivation can be checked with
// `node` instead of by looking at the panel and deciding whether the colours seem right.
//
// `.pragma library`: no QML engine context needed, and one shared instance rather than a
// fresh copy per importing file.
// ─────────────────────────────────────────────────────────────────────────────

function hexToRgb(hex) {
    const h = String(hex || "").replace("#", "")
    if (h.length !== 6) return [0, 0, 0]
    return [parseInt(h.substr(0, 2), 16),
            parseInt(h.substr(2, 2), 16),
            parseInt(h.substr(4, 2), 16)]
}

function rgbToHex(rgb) {
    const clamp = v => Math.max(0, Math.min(255, Math.round(v)))
    return "#" + rgb.map(v => clamp(v).toString(16).padStart(2, "0")).join("")
}

function mix(c1, c2, t) {
    return [c1[0] + (c2[0] - c1[0]) * t,
            c1[1] + (c2[1] - c1[1]) * t,
            c1[2] + (c2[2] - c1[2]) * t]
}

// Relative luminance, used to decide whether text on a swatch should be dark or light.
// The 0.2126/0.7152/0.0722 weights are the sRGB ones — green dominates perceived
// brightness, which is why a mid green needs dark text where a mid blue does not.
function luminance(hex) {
    const c = hexToRgb(hex).map(v => {
        const s = v / 255
        return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4)
    })
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]
}

function readableOn(hex) { return luminance(hex) > 0.4 ? "#000000" : "#ffffff" }

// ── The 18-slot palette, from four seeds ──────────────────────────────────────
// background, foreground and two accents produce the full pywal shape. The six mid
// slots are the two accents plus blends of them; the bright half (9-15) is the same
// six lifted toward white, which is what makes "bright red" read as related to "red"
// rather than as an unrelated colour.
function derive(bg, fg, accents) {
    const bgR = hexToRgb(bg), fgR = hexToRgb(fg)
    const a1 = hexToRgb(accents[0])
    const a2 = hexToRgb(accents[1] || accents[0])

    const slots = [a1, a2, mix(a1, a2, 0.5),
                   mix(a1, fgR, 0.25), mix(a2, fgR, 0.25), mix(a1, a2, 0.25)]

    const colors = {}
    colors["color0"] = bg
    // Not pure background: color8 is "dim foreground" in the pywal shape — comments,
    // disabled text — so it has to be readable against the background, not identical to it.
    colors["color8"] = rgbToHex(mix(bgR, fgR, 0.35))
    for (let i = 0; i < 6; i++) {
        colors["color" + (i + 1)] = rgbToHex(slots[i])
        colors["color" + (i + 9)] = rgbToHex(mix(slots[i], [255, 255, 255], 0.18))
    }
    colors["color7"] = fg
    colors["color15"] = rgbToHex(mix(fgR, [255, 255, 255], 0.15))

    return { special: { background: bg, foreground: fg, cursor: fg }, colors: colors }
}

// Slot order for display: the two specials first, then the 16 ramp entries in index
// order. Cursor is deliberately absent — it is always set to the foreground by `derive`,
// and offering it as a separately editable slot invites a combination nothing renders.
var SPECIAL_SLOTS = ["background", "foreground"]

function rampSlots() {
    const out = []
    for (let i = 0; i < 16; i++) out.push("color" + i)
    return out
}

function allSlots() { return SPECIAL_SLOTS.concat(rampSlots()) }

function isSpecial(slot) { return SPECIAL_SLOTS.indexOf(slot) >= 0 }

// Read one slot out of a pywal-shaped object, whichever section it lives in.
function slotValue(palette, slot) {
    if (!palette) return "#000000"
    const section = isSpecial(slot) ? palette.special : palette.colors
    return (section && section[slot]) || "#000000"
}
