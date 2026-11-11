-- ══════════════════════════════════════════════
--  autostart.lua — one-time setup once Hyprland is up
--
--  Keep every hl.exec_cmd inside the hyprland.start callback, never at file
--  scope (it would run before the compositor is ready).
--
--  @QUICKSHELL_DIR@ is rewritten to the real repo path by
--  scripts/install-hypr-config.sh.
-- ══════════════════════════════════════════════

hl.on("hyprland.start", function()
    -- Quickshell, through shell-run.sh: it sources shell-env.sh (the one copy of the
    -- launch environment, shared with reload-quickshell.sh) and starts the shell
    -- again if it crashes while starting.
    hl.exec_cmd("@QUICKSHELL_DIR@/scripts/shell-run.sh")

    hl.exec_cmd("/usr/lib/xdg-desktop-portal -r")
    hl.exec_cmd("systemctl --user start graphical-session.target")

    -- Colours from the current wallpaper (needs python-pywal16).
    hl.exec_cmd("python3 ~/.config/hypr/scripts/wal-colors.py")

    -- Optional extras — uncomment once installed:
    --   hl.exec_cmd("hyprpm reload")            -- if you use hyprpm plugins
    --   hl.exec_cmd("sleep 0.5 && awww restore")-- awww wallpaper daemon (AUR)
    --   hl.exec_cmd("awww-daemon")
end)
