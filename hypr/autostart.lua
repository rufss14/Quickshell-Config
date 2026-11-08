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
    -- Quickshell, with the environment it needs. shell-env.sh is the single copy
    -- of QSG_RHI_BACKEND / QML_IMPORT_PATH — reload-quickshell.sh sources the
    -- same file, so a reloaded shell and a booted one agree.
    hl.exec_cmd("bash -c 'source @QUICKSHELL_DIR@/scripts/shell-env.sh && exec qs -p @QUICKSHELL_DIR@'")

    hl.exec_cmd("/usr/lib/xdg-desktop-portal -r")
    hl.exec_cmd("systemctl --user start graphical-session.target")

    -- Colours from the current wallpaper (needs python-pywal16).
    hl.exec_cmd("python3 ~/.config/hypr/scripts/wal-colors.py")

    -- Optional extras — uncomment once installed:
    --   hl.exec_cmd("hyprpm reload")            -- if you use hyprpm plugins
    --   hl.exec_cmd("sleep 0.5 && awww restore")-- awww wallpaper daemon (AUR)
    --   hl.exec_cmd("awww-daemon")
end)
