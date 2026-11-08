-- ══════════════════════════════════════════════
--  hyprland.lua — entry point
--
--  Hyprland always loads $XDG_CONFIG_HOME/hypr/hyprland.lua directly, so this
--  file's name is fixed. Everything else is require()'d below, each in its own
--  Lua scope — a mistake in one module can't take the rest down, only globals
--  cross that boundary (env.lua, palette.lua).
--
--  Order matters:
--    · env before binds/rules   — they read mainMod and the app aliases
--    · palette before appearance — appearance reads the wal_color* globals
--    · blend is require()'d by appearance + animation themselves (shared table)
--
--  The modules:
--    autostart   on-start hook (launches Quickshell, portals, wallpaper)
--    env         app aliases + environment variables
--    hardware    monitors, input, devices, layout defaults
--    palette     generated wal colours  (scripts/wal-reload.sh)
--    appearance  window shape / opacity / blur / shadow  (reads blend + palette)
--    animation   curves + per-leaf timing               (reads blend)
--    binds       keybindings
--    rules       window + layer + plugin rules
--
--  blend.lua is the file this config shares with ~/.config/quicktest — edit a
--  number there and both the window and the matching shell surface move.
-- ══════════════════════════════════════════════

require("autostart")
require("env")
require("hardware")
require("palette")
require("appearance")
require("animation")
require("binds")
require("rules")
