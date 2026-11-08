-- ══════════════════════════════════════════════
--  env.lua — app aliases + environment
--
--  Loaded first of the real modules. Declares the globals that binds.lua and
--  rules.lua read (mainMod, terminal, …) and every hl.env() call. Nothing here
--  depends on anything else.
--
--  Aliases are globals ON PURPOSE — require()'d files each get their own scope
--  and globals are the only thing that crosses it. Quickshell's hypr-config.py
--  reads the bare `name = "value"` lines below to resolve keybind app names.
-- ══════════════════════════════════════════════

-- ── Aliases ─────────────────────────────────────
-- Swap these for whatever you have installed. The app launcher is the shell's
-- own (SUPER + R), so there is no `menu` here.
mainMod     = "SUPER"
terminal    = "kitty"
fileManager = "nautilus"
browser     = "zen-browser"

-- ── Environment ─────────────────────────────────
-- One place for every hl.env(). HYPRCURSOR_SIZE used to be set here and again in
-- the theme module — harmless while they agreed, but a second source of truth
-- that drifts on the next edit.
hl.env("XCURSOR_SIZE",        "24")
hl.env("HYPRCURSOR_SIZE",     "24")
-- ── The cursor theme, for every client Hyprland launches ──
-- Qt, GTK, Electron and XWayland clients read XCURSOR_THEME when they START, and nothing
-- else tells them which theme to use, so without this every app but Hyprland's own
-- surfaces shows the default arrow. Only set once Settings › Cursor has generated the
-- theme: pointing clients at a theme that isn't on disk gives them NO cursor, which is
-- worse than the default. pcall'd because a config error here would take the whole
-- config down with it. Existing windows keep what they loaded — restart them.
pcall(function()
    local data = os.getenv("XDG_DATA_HOME") or ((os.getenv("HOME") or "") .. "/.local/share")
    local f = io.open(data .. "/icons/quicktest/index.theme", "r")
    if f then
        f:close()
        hl.env("XCURSOR_THEME", "quicktest")
    end
end)
-- ── Live GTK4 recolouring, for every client Hyprland launches ──
-- scripts/gtk-live/build.sh builds a GIO module that lets an already-open GTK4 / libadwaita
-- app (Nautilus, Mission Center…) reload gtk.css when a theme run rewrites it. GTK4 only
-- scans GIO modules at app START, so the app has to be launched with this set. Only once the
-- module exists, same as the cursor above; GIO_EXTRA_MODULES is a list that adds to the
-- defaults, so it can't hide the system's own modules. pcall'd for the same reason.
pcall(function()
    local data = os.getenv("XDG_DATA_HOME") or ((os.getenv("HOME") or "") .. "/.local/share")
    local dir = data .. "/quicktest/gio-modules"
    local f = io.open(dir .. "/libgiolivetheme.so", "r")
    if f then
        f:close()
        hl.env("GIO_EXTRA_MODULES", dir)
    end
end)
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE",    "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- Qt apps follow the shell palette through qt6ct: scripts/generate-qt6ct-colors
-- rewrites ~/.config/qt6ct from the live pywal palette on every theme change, and
-- THIS is what makes a Qt6 binary actually load it. qt6ct, not qt5ct — the
-- desktop is Qt6 and qt5ct can't theme a Qt6 app; a Qt5 holdout needs qt5ct
-- installed alongside and configured separately.
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
