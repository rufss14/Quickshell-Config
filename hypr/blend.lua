-- ══════════════════════════════════════════════
--  blend.lua — the one file ~/.config/hypr and ~/.config/quicktest share
--
--  Every value here is read by BOTH sides:
--    · Hyprland  — appearance.lua / animation.lua require() this table directly.
--    · Quickshell — services/Blend.qml parses this file (regex, no Lua runtime)
--      and feeds config/Defaults.qml + config/Motion.qml.
--
--  So a window's corner, border, translucency and blur stay identical to the
--  bar's and the panels' by construction — change a number here and both move.
--
--  Edit → `hyprctl reload` repaints windows; Quickshell repaints live (FileView).
--  Keep the shape flat: `key = number`, `key = { n, n, ... }`. Comments after a
--  value are fine; nothing else parses on the Quickshell side.
-- ══════════════════════════════════════════════

return {
    -- ── Geometry ── window shape ⇢ shell surface shape ──────────────────────
    rounding       = 16,   -- ⇢ Tokens.radiusCard (shell scales it by radiusScale)
    rounding_power = 2,
    border_size    = 2,    -- ⇢ Tokens.borderChrome (bar pills + screen frame)
    gaps_in        = 4,
    gaps_out       = 8,

    -- ── Translucency ── window fill ⇢ shell surface fill ────────────────────
    -- active_opacity is the shell's surface opacity (bar + cards default here).
    active_opacity   = 0.97,
    inactive_opacity = 0.93,

    -- ── Blur ── the compositor blur behind windows AND shell surfaces ───────
    blur_size     = 5,
    blur_passes   = 3,
    blur_vibrancy = 0.7,

    -- ── Border / shadow colour ── which wal palette index each one takes ────
    -- Consumed by scripts/wal-reload.sh when it regenerates palette.lua.
    border_active_wal   = 4,
    border_inactive_wal = 2,
    shadow_wal          = 0,

    -- ── Motion ─────────────────────────────────────────────────────────────
    -- The window/workspace/fade ease, shared with Motion.emphasizedDecel so a
    -- window sliding in and a panel sliding in bend the same way (Quickshell
    -- appends the fixed 1.0, 1.0 tail). Per-animation SPEED stays in
    -- animation.lua — the shell's settings page edits those sliders directly,
    -- and Hyprland "speed" has no clean millisecond mapping anyway.
    curve_points = { 0.05, 0.7, 0.1, 1.0 },
}
