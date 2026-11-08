.pragma library

// ── lens.js ───────────────────────────────────────────────────────────────────
// services/Lens's geometry: the region slurp printed, where each OCR'd line lands on
// the screen, and where the overlay's toolbar fits. Pure; `bun scripts/test-lens.js`.
// ─────────────────────────────────────────────────────────────────────────────

// slurp -f "%x %y %w %h %o" → { x, y, w, h, output } (global, logical px), or null for
// a cancelled drag / nonsense. A region thinner than 4px is a slip, not a selection.
function parseRegion(text) {
    const m = String(text || "").trim().match(/^(-?\d+) (-?\d+) (\d+) (\d+) (\S+)$/)
    if (!m) return null
    const r = { x: +m[1], y: +m[2], w: +m[3], h: +m[4], output: m[5] }
    return r.w >= 4 && r.h >= 4 ? r : null
}

// grim's -g argument for a region.
function grimGeometry(r) { return r.x + "," + r.y + " " + r.w + "x" + r.h }

// The region in a screen's own coordinates (the overlay is per screen).
function local(r, screenX, screenY) {
    return { x: r.x - screenX, y: r.y - screenY, w: r.w, h: r.h }
}

// An OCR line (image pixels) → its box over the region on screen. The capture is at
// the output's scale, so image px / region px is that scale.
function place(line, region, imageW, imageH) {
    const sx = imageW > 0 ? region.w / imageW : 1
    const sy = imageH > 0 ? region.h / imageH : 1
    return { x: region.x + line.x * sx, y: region.y + line.y * sy, w: line.w * sx, h: line.h * sy }
}

// Where the toolbar goes: under the region if it fits, else over it, else inside its
// bottom edge. Centred on the region, kept `margin` inside the screen.
function toolbar(region, barW, barH, screenW, screenH, gap, margin) {
    let x = region.x + (region.w - barW) / 2
    x = Math.max(margin, Math.min(screenW - margin - barW, x))
    let y = region.y + region.h + gap
    if (y + barH > screenH - margin) {
        y = region.y - gap - barH
        if (y < margin) y = region.y + region.h - gap - barH
    }
    return { x: x, y: Math.max(margin, y) }
}

// The text to copy: the translation when it's showing (line by line, same breaks).
function copyText(lines, translated, showTranslation) {
    if (!showTranslation || !translated || translated.length !== lines.length) return lines.map(l => l.text).join("\n")
    return translated.join("\n")
}
