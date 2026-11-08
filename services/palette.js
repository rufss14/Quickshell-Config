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
    let h = String(hex || "").replace("#", "")
    // QML stringifies an opaque color as "#rrggbb" but a translucent one as
    // "#aarrggbb". Callers pass Colors roles straight in, so accept both rather
    // than silently returning black for the eight-character form — that failure
    // has no symptom except a colour quietly going dark.
    if (h.length === 8) h = h.substr(2)
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

// Two pywal palettes ({ special: {…}, colors: {…}}, hex strings) blended: t 0 = a, 1 = b.
// What a screen's colours ease through when its workspace changes (PaletteRoles.goal).
// A slot only one side has is taken as it is (no colour to blend with); a value that isn't a
// hex colour is taken from b. Returns a new object; neither input is touched.
function lerpPalette(a, b, t) {
    const A = a || {}, B = b || {}
    const k = Math.max(0, Math.min(1, t))
    const group = (x, y) => {
        const out = {}
        const keys = Object.keys(x || {}).concat(Object.keys(y || {}))
        for (const key of keys) {
            if (key in out) continue
            const p = (x || {})[key], q = (y || {})[key]
            const hex = v => typeof v === "string" && /^#[0-9a-fA-F]{6}$/.test(v)
            out[key] = (hex(p) && hex(q)) ? rgbToHex(mix(hexToRgb(p), hexToRgb(q), k))
                     : (q !== undefined ? q : p)
        }
        return out
    }
    return { special: group(A.special, B.special), colors: group(A.colors, B.colors) }
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

// ── contrast ──────────────────────────────────────────────────────────────────
// WCAG contrast ratio, 1 (identical) to 21 (black on white).
function contrast(hexA, hexB) {
    const a = luminance(hexA)
    const b = luminance(hexB)
    return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05)
}

// ── legible ───────────────────────────────────────────────────────────────────
// Lifts `hex` toward `toward` until it reaches `target` contrast against `bg`,
// and returns it unchanged if it already does.
//
// ── Why the shell needs this at all ───────────────────────────────────────────
// The shell's accent roles are pywal ramp SLOTS — primary is color1, focus is
// color4 — and the ramp is ordered by hue, not by luminance. Nothing guarantees
// the slot that means "this is the active thing" is legible against the surface
// it is drawn on.
//
// Measured on one real wallpaper: color1 was #6B4F53, contrast 2.52 against the
// background — the LOWEST of the sixteen — while color4 sat at 7.47. So the
// active workspace, every hovered pill and every module accent rendered in the
// least visible colour in the palette, and the "live on another monitor" marker
// (focus) outshouted the workspace you were actually on. It read as the bar being
// broken; it was the palette being sampled by index.
//
// Material You does not have this problem because its primary is generated at a
// fixed light TONE for dark schemes. pywal has no tone ladder, so the floor has
// to be enforced here.
//
// Hue is preserved: this walks toward the foreground rather than toward white, so
// a warm palette stays warm. Bisection rather than a fixed step, so the result is
// the *least* adjustment that clears the bar — a palette that is already legible
// comes back untouched.
function legible(hex, bg, target, toward) {
    if (contrast(hex, bg) >= target) return hex

    const dest = toward || "#ffffff"
    // If even the destination cannot reach the target there is nothing useful to
    // return but the destination — better a legible wrong-ish hue than an
    // invisible right one.
    if (contrast(dest, bg) < target) return dest

    // `mix` works on RGB TRIPLES, not hex strings — converting at the boundary
    // rather than inside the loop keeps the twelve bisection steps cheap.
    const from = hexToRgb(hex)
    const to   = hexToRgb(dest)

    let lo = 0, hi = 1
    for (let i = 0; i < 12; i++) {
        const mid = (lo + hi) / 2
        if (contrast(rgbToHex(mix(from, to, mid)), bg) >= target) hi = mid
        else lo = mid
    }
    return rgbToHex(mix(from, to, hi))
}

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

// ── HSL, harmony, and accent suggestions ──────────────────────────────────────
// The colours panel's Shuffle. Hue is the one thing a person picking two accents wants
// related, so these work in HSL: `harmony` turns an accent into a partner at a named angle
// on the wheel with the same saturation and lightness, and `suggestAccents` draws a pair
// that is both related and legible on the background.
function rgbToHsl(rgb) {
    const r = rgb[0] / 255, g = rgb[1] / 255, b = rgb[2] / 255
    const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn
    const l = (mx + mn) / 2
    if (d === 0) return [0, 0, l]
    const s = d / (1 - Math.abs(2 * l - 1))
    let h
    if (mx === r)      h = ((g - b) / d) % 6
    else if (mx === g) h = (b - r) / d + 2
    else               h = (r - g) / d + 4
    h *= 60
    return [h < 0 ? h + 360 : h, s, l]
}

function hslToRgb(h, s, l) {
    const hh = (((h % 360) + 360) % 360) / 60
    const c = (1 - Math.abs(2 * l - 1)) * s
    const x = c * (1 - Math.abs(hh % 2 - 1))
    const m = l - c / 2
    const k = Math.floor(hh)
    const p = [[c, x, 0], [x, c, 0], [0, c, x], [0, x, c], [x, 0, c], [c, 0, x]][k % 6]
    return [(p[0] + m) * 255, (p[1] + m) * 255, (p[2] + m) * 255]
}

// The angle, in degrees round the wheel, each named relationship sits at.
var HARMONIES = { analogous: 30, split: 150, triad: 120, complementary: 180 }

// `hex` turned `HARMONIES[kind]` degrees, keeping its saturation and lightness.
function harmony(hex, kind) {
    const hsl = rgbToHsl(hexToRgb(hex))
    return rgbToHex(hslToRgb(hsl[0] + (HARMONIES[kind] || 0), hsl[1], hsl[2]))
}

// The second accent as a named harmony of the first, lifted to stay legible on `bg`. What the
// panel's harmony chips apply, and what its lit one is compared against.
function partner(accent, bg, fg, kind) {
    return legible(harmony(accent, kind), bg, 3, fg)
}

// A pair of accents for a palette whose background and text are fixed: a random hue, a
// lightness chosen for the background (lighter accents on a dark ground, deeper on a light
// one), and a partner at a random harmony. Both are lifted to 3:1 against the background —
// the large-text floor, which is what an accent is — toward the foreground so the hue holds.
// `rand` is injectable so a test can pin it; the panel passes nothing and gets Math.random.
function suggestAccents(bg, fg, rand) {
    const r = rand || Math.random
    const dark = luminance(bg) < 0.4
    const s = 0.45 + 0.35 * r()
    const l = dark ? 0.58 + 0.14 * r() : 0.32 + 0.14 * r()
    const a = legible(rgbToHex(hslToRgb(r() * 360, s, l)), bg, 3, fg)
    const kinds = Object.keys(HARMONIES)
    return [a, partner(a, bg, fg, kinds[Math.floor(r() * kinds.length) % kinds.length])]
}

// WCAG's name for a text/background contrast ratio — "AAA" 7, "AA" 4.5, "Large" 3 (big text
// only), "Low" below that.
function contrastGrade(ratio) {
    return ratio >= 7 ? "AAA" : ratio >= 4.5 ? "AA" : ratio >= 3 ? "Large" : "Low"
}

// ── Schemes that hold both modes ──────────────────────────────────────────────
// A saved scheme is a file in colorschemes/. It used to be ONE pywal-shaped palette
// ({ special, colors }); it can now hold a dark AND a light one. The shape stays readable by
// anything that knows the old one — scripts/check-contrast.py, a shell that has not updated, the
// update script that ships schemes — by keeping the primary variant at the TOP LEVEL, exactly where
// the old format had its only palette, and adding the full set beside it:
//
//     { "special": …, "colors": …,                 ← the dark one if there is one, else the light
//       "variants": { "dark": {…}, "light": {…} } }
//
// A file with no `variants` is a legacy scheme: its mode is read off its background (a dark ground is
// a dark scheme), so the whole bundled library keeps working untouched and a scheme only gains its
// second mode when someone saves it.
//
// `unpackScheme` / `packScheme` are the two ends, `pickVariant` is "which one do I wear in this mode".
function schemeMode(p) {
    return luminance(slotValue(p, "background")) < 0.4 ? "dark" : "light"
}

// Just the palette: a variant carries no other keys of its own.
function bareScheme(p) {
    return { special: p.special || {}, colors: p.colors || {} }
}

// → { dark: palette | null, light: palette | null }
function unpackScheme(obj) {
    const out = { dark: null, light: null }
    if (!obj) return out
    const v = obj.variants
    if (v && (v.dark || v.light)) {
        for (const m of ["dark", "light"])
            if (v[m] && v[m].colors) out[m] = bareScheme(v[m])
        return out
    }
    if (obj.special || obj.colors) out[schemeMode(obj)] = bareScheme(obj)
    return out
}

// { dark?, light? } → the object to write, or null when there is nothing to write.
function packScheme(variants) {
    const dark = variants && variants.dark, light = variants && variants.light
    const primary = dark || light
    if (!primary) return null
    const bare = bareScheme(primary)
    const out = { special: bare.special, colors: bare.colors, variants: {} }
    if (dark)  out.variants.dark  = bareScheme(dark)
    if (light) out.variants.light = bareScheme(light)
    return out
}

// The variant to wear in `mode`. `exact` is false when the scheme has only the OTHER mode, which is
// what comes back then (the caller says so); `palette` is null only for an empty scheme.
function pickVariant(variants, mode) {
    const want = mode === "light" ? "light" : "dark"
    const other = want === "light" ? "dark" : "light"
    if (variants && variants[want])  return { palette: variants[want],  mode: want,  exact: true }
    if (variants && variants[other]) return { palette: variants[other], mode: other, exact: false }
    return { palette: null, mode: want, exact: false }
}

// ── Which saved scheme is the shell wearing? ──────────────────────────────────
// Nothing records "scheme X is applied" (an unlocked apply is a staged palette that the next wallpaper
// replaces, a locked one is pins), so it is read back from the colours: the saved scheme whose palette
// the live one IS. Compared slot by slot over the 16 colours and the background and foreground (the
// cursor follows the foreground), as the mean difference per colour channel out of 255; a scheme
// counts when that is within `tol` (the pipeline may nudge a slot, so not exact) and the nearest one
// wins. `schemes` is [{ name, variants }] (as ColorScheme.presets holds them) and `mode` picks the
// variant a scheme wears. "" when no scheme is near.
function schemeDistance(a, b) {
    let sum = 0, n = 0
    const slots = ["background", "foreground"].concat(rampSlots())
    for (const slot of slots) {
        const x = hexToRgb(slotValue(a, slot)), y = hexToRgb(slotValue(b, slot))
        sum += Math.abs(x[0] - y[0]) + Math.abs(x[1] - y[1]) + Math.abs(x[2] - y[2])
        n += 3
    }
    return n > 0 ? sum / n : Infinity
}

function findScheme(live, schemes, mode, tol) {
    // A palette that isn't whole (still loading) is nothing's twin, not black's.
    if (!live || !live.colors || !live.special || !live.colors.color15) return ""
    const limit = tol === undefined ? 3 : tol
    let best = "", bestD = Infinity
    for (const s of schemes || []) {
        const pick = pickVariant(s.variants, mode)
        if (!pick.palette) continue
        const d = schemeDistance(live, pick.palette)
        if (d <= limit && d < bestD) { best = s.name; bestD = d }
    }
    return best
}
