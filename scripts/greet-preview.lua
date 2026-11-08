-- greet-preview.lua — look at the greeter without going near your login.
--
--     start-hyprland -- --config ~/.config/quicktest/scripts/greet-preview.lua
--
-- Hyprland runs as an ordinary Wayland client when WAYLAND_DISPLAY is already set, so
-- this opens a NESTED compositor in a window on your desktop and starts greet.qml
-- inside it.
--
-- Through `start-hyprland` rather than `Hyprland` directly, which warns "Hyprland is
-- being launched without start-hyprland. This is highly advised against." — it is the
-- watchdog wrapper, and it is also exactly how /etc/greetd/config.toml already launches
-- the real greeter session, so the preview and the deployment differ by one path.
--
-- Everything after `--` goes to Hyprland; nothing before it is needed here.
--
-- ── Why nested, and not just `qs -p greet.qml` ───────────────────────────────
-- GreetScreen takes WlrKeyboardFocus.Exclusive, because a login screen that ignores
-- the password you started typing at it is not a login screen. Run directly in your
-- session, that grab is real: the rest of your desktop stops receiving keys, and the
-- way out is Ctrl+Alt+F2 and `pkill`. Nested, the grab is confined to the nested
-- compositor's window, and closing the window ends it.
--
-- GREETD_SOCK is not set in here, so services/Greet.qml comes up in demo mode: the
-- whole surface draws, and nothing can be submitted. That is the intended state for
-- design work — see the note on `demoMode`.
--
-- ── Why Lua and not hyprlang ─────────────────────────────────────────────────
-- Hyprland 0.56 ships a full Lua config manager (src/config/lua/) and a Lua default
-- config at /usr/share/hypr/hyprland.lua; hyprlang is on the way out. A preview
-- harness written in the format that is being retired would need rewriting exactly
-- once, on the day it stopped working, which is the day you would least want to be
-- debugging a login screen.
--
-- Validate any edit to this file WITHOUT running it (no wrapper needed — this one does
-- not start a compositor):
--     Hyprland --verify-config -c scripts/greet-preview.lua
--
-- Super+Q closes the preview. Killing the window works too.

hl.config({
    animations = {
        enabled = false,
    },

    decoration = {
        rounding = 0,
        blur = {
            enabled = false,
        },
    },

    general = {
        gaps_in     = 0,
        gaps_out    = 0,
        border_size = 0,
    },

    misc = {
        disable_hyprland_logo    = true,
        disable_splash_rendering = true,
        background_color         = "rgb(000000)",
        -- Nested Hyprland has no real seat to watch; the watchdog only produces noise.
        disable_watchdog_warning = true,
    },

    ecosystem = {
        no_update_news   = true,
        no_donation_nag  = true,
    },
})

hl.bind("SUPER + Q", hl.dsp.exit())

-- ── The greeter itself ──────────────────────────────────────────────────────
-- On the start event rather than at the top level: a top-level hl.exec_cmd would run
-- during `--verify-config` too, which would spawn a greeter every time you checked
-- this file for syntax errors. Inside the callback it is just a closure until
-- Hyprland actually comes up.
--
-- Through $HOME rather than a literal path, since this config is published — and
-- resolved in Lua rather than left for a shell to expand, because exec_cmd is not
-- guaranteed to go through one.
hl.on("hyprland.start", function()
    hl.exec_cmd("qs -p " .. os.getenv("HOME") .. "/.config/quicktest/greet.qml")
end)
