-- ══════════════════════════════════════════════
--  hardware.lua — monitors, input, devices, layout defaults
--
--  Everything tied to a machine's physical setup, plus the layout engine
--  defaults (structural, not appearance — see appearance.lua for gaps/rounding).
--
--  MONITORS.  scripts/install-hypr-config.sh auto-fills the line(s) below from
--  `hyprctl monitors` when Hyprland is running (re-run it, or
--  scripts/hypr-monitors.py hardware.lua, to refresh after plugging a screen).
--  If it couldn't reach hyprctl you get the one generic line — edit it, e.g.
--      hl.monitor({ output = "DP-1", mode = "2560x1440@144", position = "0x0",  scale = 1 })
--      hl.monitor({ output = "HDMI-A-1", mode = "preferred",  position = "auto", scale = 1 })
-- ══════════════════════════════════════════════

-- ── Monitors ────────────────────────────────────
-- Empty output = "all of them". preferred mode, auto placement, no scaling.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

-- ── Input ───────────────────────────────────────
hl.config({
    input = {
        kb_layout    = "us",          -- add more comma-separated, e.g. "us,pt"
        follow_mouse = 1,
        sensitivity  = 0,
        touchpad     = { natural_scroll = false },
    },
    binds = {
        -- Hyprland discards further scroll-bind events for 300ms after one fires,
        -- which makes wheel-volume and wheel-workspace crawl behind a fast flick.
        -- 0 = one step per click. 50–100 if that feels twitchy.
        scroll_event_delay = 0,
    },
    -- A focus change does NOT move the pointer. Hyprland's default warps it to the
    -- centre of whatever took focus — so every dock click (and every overview
    -- window pick) teleported the mouse away from where you'd just clicked, which
    -- no taskbar does. Keyboard focus moves (SUPER+arrows) stop warping too.
    cursor = {
        no_warps = true,
    },
})

-- Per-device tweaks go here, keyed by the name from `hyprctl devices`, e.g.
--   hl.device({ name = "my-mouse", sensitivity = -0.5 })

-- ── Dynamic cursors (optional plugin) ───────────
-- Tilt/rotate/stretch and shake-to-find are configured by the SHELL, at runtime, from
-- Settings › Cursor (services/CursorEffects.qml → `hyprctl eval`), and re-applied after
-- every config reload. Nothing to uncomment here — a second copy of these values in this
-- file would just be reset by the shell the next time it applied its own. Install the
-- plugin itself with hyprpm; the settings page prints the commands.

-- ── Layout engine ───────────────────────────────
hl.config({
    dwindle = { preserve_split = true },
    master  = { new_status = "master" },
    misc    = {
        force_default_wallpaper = -1,
        disable_hyprland_logo   = false,
        -- ── Gaming ──────────────────────────────────
        -- vrr = 2: adaptive sync on fullscreen windows only. Full-time (1) can
        -- flicker on a mixed-refresh dual-monitor setup and on the desktop with
        -- animations; fullscreen-only is the safe win. Needs a FreeSync/G-Sync
        -- panel — harmless on one without.
        vrr          = 2,
    },
    render  = {
        -- Let a fullscreen game scan out straight to the display, skipping the
        -- compositor's blit — lower latency and GPU load. 1 = when nothing is on
        -- top of it (a notification/OSD briefly disables it, then it resumes).
        direct_scanout = 1,
    },
})
