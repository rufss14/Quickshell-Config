-- greet-session.lua — the Hyprland session greetd runs the greeter inside.
--
-- Installed to /etc/greetd/greet-session.lua by `greet-export.sh --system`, and named
-- by /etc/greetd/config.toml:
--
--     [default_session]
--     command = "start-hyprland -- --config /etc/greetd/greet-session.lua"
--     user = "greeter"
--
-- ── This is the greeter's compositor, not yours ──────────────────────────────
-- greetd cannot draw. It runs a session as the unprivileged `greeter` user and the
-- greeter draws inside it — so there has to be a compositor, and it is this one. It
-- exists only to host a single fullscreen layer surface for the few seconds before
-- someone logs in, which is why nearly everything here is switched off.
--
-- ── No keybinds, on purpose ──────────────────────────────────────────────────
-- Not one, apart from what Hyprland does natively. A keybind here is reachable by
-- whoever is standing at the machine BEFORE they have authenticated — an exec bind is
-- a shell, and a shell on a login screen is not a login screen. The greeter's own
-- restart/shut-down buttons are the deliberate exception, and they go through logind,
-- which is a decision made in QML where it can be reasoned about.
--
-- Validate without running it:
--     Hyprland --verify-config -c scripts/greet-session.lua

hl.config({
    -- Nothing animates. The greeter is up for seconds and every frame it spends on a
    -- window transition is a frame it is not spending on first paint.
    animations = {
        enabled = false,
    },

    decoration = {
        rounding = 0,
        blur = {
            -- The greeter blurs its OWN backdrop, in-process, at quarter resolution.
            -- A compositor blur on top would be a second full-screen blur pass over
            -- the same pixels for no visible difference.
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
        -- Black, not a colour: this is what shows for the instant before the greeter's
        -- own surface paints, and a coloured flash reads as a glitch.
        background_color         = "rgb(000000)",
        -- greetd does not hand start-hyprland a watchdog fd, so the warning is
        -- structural here rather than something to fix. Same setting, same reason, as
        -- the sysc-greet config that shipped before this one.
        disable_watchdog_warning = true,
    },

    ecosystem = {
        no_update_news  = true,
        no_donation_nag = true,
    },

    input = {
        kb_layout    = "us",
        repeat_delay = 400,
        repeat_rate  = 40,
        touchpad = {
            natural_scroll = false,
        },
    },
})

-- ── The greeter ─────────────────────────────────────────────────────────────
-- A SNAPSHOT of the shell at /var/lib/greeter/shell, not a path into anyone's home.
-- Two reasons, and the second is the important one:
--
--   · /home is unreadable to the `greeter` user on a normally-permissioned system,
--     so a path into it would work on the machine that built it and nowhere else.
--   · your login screen must not live-track a repo you are actively editing. A shell
--     that fails to load is an inconvenience at 2pm and a machine you cannot log into
--     at 2am. Re-run `greet-export.sh --system` to move the snapshot forward, as a
--     deliberate act, once the shell is known good.
--
-- `; hyprctl dispatch exit` rather than `&&`: if Quickshell exits NON-zero the
-- compositor still needs to go away, so greetd notices the session ended and starts a
-- fresh greeter. With `&&` a crashed greeter would leave an empty black compositor
-- sitting there forever, which looks exactly like a hung machine.
--
-- Inside hl.on("hyprland.start") rather than at the top level, so `--verify-config`
-- checks this file instead of launching a greeter.
-- ── One script, because the teardown is not a one-liner ─────────────────────
-- This was `qs … ; hyprctl dispatch exit` inline, and that inline version is where
-- five seconds of every login were going: Quickshell exited, the compositor did not
-- follow, and greetd paid its full five-second timeout waiting for the SESSION to end
-- rather than the process. Measured at 5.005s, three logins running.
--
-- greet-run.sh times every step into /var/lib/greeter/greet.log — which outlives the
-- session, unlike anything under /run/user/961 — and carries a backstop that does not
-- depend on hyprctl working. See its header.
hl.on("hyprland.start", function()
    hl.exec_cmd("/var/lib/greeter/shell/scripts/greet-run.sh")
end)
