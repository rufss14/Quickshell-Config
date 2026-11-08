-- ══════════════════════════════════════════════
--  rules.lua — window + layer rules
--
--  The two quickshell layer_rule lines matter (blur behind the overview, none
--  behind the bar). The game/app rules below are the maintainer's own — kept as
--  worked examples of the syntax; delete or replace them freely.
-- ══════════════════════════════════════════════

-- ── Plugins ─────────────────────────────────────
-- Confined floats: keeps floating windows within the visible work
-- area. Always registered; only takes effect once the plugin is
-- loaded via hyprpm and hyprctl reload runs. Toggled from the dock
-- button, which manages the hyprpm load/unload + reload itself.
--
-- The plugin is opt-in — only windows this rule matches get confined —
-- and it confines them even while they are fullscreen. That capped
-- fullscreen games at 1892x1022 on the 1920x1080 screen (work area minus
-- the bar reservation, gaps and border), leaving the wallpaper visible
-- around them, so games are matched out via `negative:`. The rule is read
-- when a window maps, so a game must be relaunched (or the plugin
-- reloaded) for a change here to reach an already-open window.
if hl.plugin.confined_floats ~= nil then
    hl.window_rule({
        -- steam_proton = winewayland app_id, shared by every proton game.
        match = { class = [[negative:^(osu!\.exe|steam_proton)$]] },
        ["confined-floats:confine"] = true,
    })
end
-- ── Quickshell ──────────────────────────────────
-- The overview: blur ONLY behind its cards. layer_rule has no strength knob (that's the
-- global decoration:blur, shared with real windows), but `ignore_alpha` skips every
-- pixel at or under that alpha — and Overview.qml's dim is 0.5, so the desktop between
-- the cards stays sharp while the cards (surfaceOpacity, ~0.97) stay frosted. Raise the
-- dim past 0.6 and the whole screen blurs again.
-- No `no_anim` here, deliberately (tried 2026-10-24, reverted): the compositor's blur has no
-- strength of its own — it follows the layer's alpha, which Hyprland's layer fade animates.
-- With the fade off the blur switched on and off in one frame. Leave the fade alone.
hl.layer_rule({ match = { namespace = "^quickshell-overview$" }, blur = true, ignore_alpha = 0.6 })
hl.layer_rule({ match = { namespace = "^quickshell-bar$" }, blur = false })

-- The settings window is the shell's one real toplevel (a FloatingWindow, not a
-- layer surface — a layer overlay sat above the bar and broke the Bar page's
-- arrange drag). Float it and centre it; a settings dialog tiled between two
-- terminals is not what anyone wants. class org.quickshell, title Settings.
hl.window_rule({
    match  = { class = [[^org\.quickshell$]], title = "^Settings$" },
    float  = true,
    center = true,
})

-- The lyrics window (modules/lyrics/LyricsWindow.qml) is the shell's other real
-- toplevel — same float+centre treatment, matched on its own title. Unlike
-- Settings it's meant to be dragged and resized to taste and left there for the
-- session; centring only ever applies at MAP time, so a resize afterwards sticks.
hl.window_rule({
    match  = { class = [[^org\.quickshell$]], title = "^Lyrics$" },
    float  = true,
    center = true,
})

-- ── Games ───────────────────────────────────────
-- Any fullscreen window is allowed to tear IF it asks to (the tearing protocol —
-- games do, a video player or a maximised browser does not). Pairs with
-- appearance.lua's `allow_tearing = true`; this is the split Hyprland's own wiki
-- recommends. With `misc:vrr = 2` (hardware.lua) adaptive sync covers the in-range
-- case and tearing only shows above the refresh ceiling.
hl.window_rule({ match = { fullscreen = 1 }, immediate = true })

-- Proton / Wine / gamescope clients: drop the desktop chrome that costs frames.
-- steam_proton is the winewayland app_id every Proton title shares.
hl.window_rule({
    match   = { class = [[^(steam_proton|gamescope|.*\.exe)$]] },  -- RE2, case-sensitive
    no_blur = true,
    no_anim = true,
    opaque  = true,
})

-- Native Linux CS2 maps as class `cs2`, which the Proton rule above never matches — so
-- it was the one game still drawn with the desktop's translucency and blur, and still
-- animated in. Same chrome drop as every other game here.
hl.window_rule({
    match      = { class = "^(cs2)$" },
    immediate  = true,
    fullscreen = true,
    no_blur    = true,
    no_anim    = true,
    opaque     = true,
})

-- Genshin Impact (an-anime-game-launcher). AAGL launches it with
-- `-screen-fullscreen 0 -popupwindow` (the launcher's "borderless" toggle),
-- so the game maps as a plain window and never asks for fullscreen itself.
-- The confine exclusion above is what lets it actually cover the screen;
-- this rule just saves a SUPER+F on every launch.
hl.window_rule({
    match = { class = "^steam_proton$", title = "^Genshin Impact$" },
    fullscreen = true,
})

-- Minecraft / Java performance tuning.
hl.window_rule({
    match = { class = [[.*[Mm]inecraft.*|java.*]] }, -- RE2 regex, case-sensitive
    fullscreen = true,
    no_blur    = true,
    no_anim    = true,
    opaque     = true,
    immediate  = true, -- reduces input latency (tearing allowed)
})

-- Pin Minecraft to workspace 1 and keep it exclusive there.
hl.window_rule({
    match      = { class = [[.*[Mm]inecraft.*]] },
    workspace  = "1",
    fullscreen = true,
})

-- ── Browser ─────────────────────────────────────
-- Zen Browser Picture-in-Picture. Keeping it floating, static, and
-- blur-free is what fixes the "creates instance then disappears"
-- issue the PiP window used to have.
hl.window_rule({
    match = {
        class = "^zen$",
        title = "^Picture-in-Picture$",
    },
    float   = true,
    no_anim = true,
    no_blur = true,
    opaque  = true,
})
