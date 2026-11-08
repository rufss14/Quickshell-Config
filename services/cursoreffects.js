.pragma library

// ── cursoreffects.js ──────────────────────────────────────────────────────────
// The Lua that configures the hypr-dynamic-cursors plugin, built from the shell's
// three cursor-effect settings.
//
// ── Why this is a string builder with a whitelist ─────────────────────────────
// `hyprctl eval` runs whatever it is given as Lua inside the compositor. The values
// come from the shell's own config file, which is user-editable JSON — so nothing
// reaches the string except a mode from a fixed list and integers this file clamps.
// A hand-edited `"cursorEffectMode": "tilt\"}) os.execute(…)"` falls back to tilt
// instead of becoming code. (Same rule as Discord's credentials going over stdin, not
// argv: a value that crosses into another program is validated on the way.)
//
// ── Sensitivity, in one number ────────────────────────────────────────────────
// The plugin's own knobs are `limit`s: the pointer speed, in px/s, at which the effect
// is FULL. Tilt and stretch have different defaults (5000 and 3000), so one slider
// scales both around them. 100 = the plugin's own defaults; higher reaches the full
// effect at a lower speed, i.e. feels more reactive.
//
// Spellings verified against the plugin's README: the namespace is `dynamic_cursors`
// (underscore), and `activation` is left at its defaults. The `if hl.plugin…` guard is
// the README's own: the table doesn't exist until the plugin is loaded.
//
// Tested: `bun scripts/test-cursoreffects.js`.
// ─────────────────────────────────────────────────────────────────────────────

var MODES = ["tilt", "rotate", "stretch", "none"]
var TILT_LIMIT = 5000
var STRETCH_LIMIT = 3000

function _int(v, lo, hi, dflt) {
    var n = Math.round(Number(v))
    if (!isFinite(n)) return dflt
    return Math.max(lo, Math.min(hi, n))
}

// opts: { enabled, mode, sensitivity (percent), shake }
function lua(opts) {
    var o = opts || {}
    var mode = MODES.indexOf(o.mode) >= 0 ? o.mode : "tilt"
    var pct = _int(o.sensitivity, 50, 200, 100)
    var on = o.enabled === true
    var shake = o.shake === true

    return "if hl.plugin.dynamic_cursors then hl.config({ plugin = { dynamic_cursors = { "
        + "enabled = " + on + ", "
        + "mode = \"" + mode + "\", "
        + "tilt = { limit = " + Math.round(TILT_LIMIT * 100 / pct) + " }, "
        + "stretch = { limit = " + Math.round(STRETCH_LIMIT * 100 / pct) + " }, "
        + "shake = { enabled = " + shake + " } "
        + "} } }) end"
}
