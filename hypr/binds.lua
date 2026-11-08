-- ══════════════════════════════════════════════
--  binds.lua — all keybindings
--  Depends on mainMod + app aliases from env.lua.
--  @QUICKSHELL_DIR@ is rewritten by scripts/install-hypr-config.sh.
-- ══════════════════════════════════════════════

-- ── WM & session ────────────────────────────────
hl.bind(mainMod .. " + C",     hl.dsp.window.close())
hl.bind(mainMod .. " + M",     hl.dsp.exit())
-- Lock: the shell's lock screen, or hyprlock if the shell doesn't answer (scripts/lock.sh).
hl.bind(mainMod .. " + L",     hl.dsp.exec_cmd("@QUICKSHELL_DIR@/scripts/lock.sh"))
hl.bind(mainMod .. " + F",     hl.dsp.window.fullscreen())
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen_state({ internal = 1, client = 2, action = "toggle" }),
    { description = "Fake fullscreen focused window" })
hl.bind(mainMod .. " + V",     hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + J",     hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + Space", hl.dsp.exec_cmd("hyprctl switchxkblayout all next"))

-- ── App launchers ───────────────────────────────
hl.bind(mainMod .. " + Q", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager .. " --new-window"))
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd(browser))
-- Screenshots: the shell's own snip tool (drag a box, loop, or click a window; save/copy/edit/OCR/record).
hl.bind(mainMod .. " + P",           hl.dsp.exec_cmd("qs ipc -c @QUICKSHELL_DIR@ call snip save"))
hl.bind(mainMod .. " + SHIFT + P",   hl.dsp.exec_cmd("qs ipc -c @QUICKSHELL_DIR@ call snip copy"))

-- ── Quickshell ──────────────────────────────────
hl.bind(mainMod .. " + R",      hl.dsp.exec_cmd("qs ipc -c @QUICKSHELL_DIR@ call launcher toggle"))
hl.bind(mainMod .. " + TAB",    hl.dsp.exec_cmd("qs ipc -c @QUICKSHELL_DIR@ call overview toggle"))
hl.bind(mainMod .. " + G",      hl.dsp.exec_cmd("qs ipc -c @QUICKSHELL_DIR@ call gamemode toggle"))
hl.bind(mainMod .. " + D",      hl.dsp.exec_cmd("qs ipc -c @QUICKSHELL_DIR@ call dock toggle"))
-- The whole sidebar (dock + stats) sinks into the frame and back.
hl.bind(mainMod .. " + SHIFT + D", hl.dsp.exec_cmd("qs ipc -c @QUICKSHELL_DIR@ call sidebar toggle"))
-- Keyboard onto the dock (Windows' Win+T), and SUPER+ALT+n for its nth app.
hl.bind(mainMod .. " + T",      hl.dsp.exec_cmd("qs ipc -c @QUICKSHELL_DIR@ call dock focus"))
-- The lens (services/Lens): drag a region to read its text; with SHIFT, translate it.
hl.bind(mainMod .. " + O",         hl.dsp.exec_cmd("qs ipc -c @QUICKSHELL_DIR@ call lens text"))
hl.bind(mainMod .. " + SHIFT + O", hl.dsp.exec_cmd("qs ipc -c @QUICKSHELL_DIR@ call lens translate"))
for i = 1, 9 do
    hl.bind(mainMod .. " + ALT + " .. i, hl.dsp.exec_cmd("qs ipc -c @QUICKSHELL_DIR@ call dock activate " .. i))
end
-- Alt+Tab (services/Switcher, the overview's recent-windows row). Posted as CUSTOM EVENTS
-- on the event socket the shell already reads — no `qs ipc` process per Tab — carrying
-- Hyprland's own focus history (most recent first), so the shell needs no refresh to
-- know the order. Letting go of Alt is a non-consuming release bind: it fires on every
-- Alt release, apps still see it, and the shell ignores it unless it's switching.
local function switchKey(kind)
    return function()
        pcall(function()
            local ws = {}
            for _, w in ipairs(hl.get_windows()) do
                if w.mapped and w.workspace and (w.workspace.id or 0) > 0 then ws[#ws + 1] = w end
            end
            table.sort(ws, function(a, b) return (a.focus_history_id or 1e9) < (b.focus_history_id or 1e9) end)
            local out = {}
            for i = 1, math.min(#ws, 64) do out[i] = ws[i].address end
            hl.dispatch(hl.dsp.event("qs-switch:" .. kind .. ":" .. table.concat(out, ",")))
        end)
    end
end
local function altUp() pcall(function() hl.dispatch(hl.dsp.event("qs-switch:up")) end) end
hl.bind("ALT + TAB",         switchKey("next"))
hl.bind("ALT + SHIFT + TAB", switchKey("prev"))
hl.bind("ALT_L", altUp, { release = true, ignore_mods = true, non_consuming = true })
hl.bind("ALT_R", altUp, { release = true, ignore_mods = true, non_consuming = true })
-- The magnifier (services/Magnifier): Hyprland's cursor zoom, eased by the shell. Same
-- custom-event channel as Alt+Tab. SUPER+scroll is workspaces and SUPER+ALT+scroll is
-- volume, so it's SUPER+CTRL+scroll; SUPER+CTRL+Z toggles 2× (or your last level) / off.
hl.bind(mainMod .. " + CTRL + mouse_up",   hl.dsp.event("qs-zoom:in"))
hl.bind(mainMod .. " + CTRL + mouse_down", hl.dsp.event("qs-zoom:out"))
hl.bind(mainMod .. " + CTRL + Z",          hl.dsp.event("qs-zoom:toggle"))
-- Clips (services/Clips): ShadowPlay's own keys, so a game's muscle memory works.
-- ALT+F10 saves a clip (the replay buffer), ALT+F9 starts/stops a recording; with SHIFT,
-- clipping on/off (keeps the buffer running) and a dragged-region recording; ALT+F8 is the library.
hl.bind("ALT + F10",         hl.dsp.exec_cmd("qs ipc -c @QUICKSHELL_DIR@ call clips save"))
hl.bind("ALT + F9",          hl.dsp.exec_cmd("qs ipc -c @QUICKSHELL_DIR@ call clips record"))
hl.bind("ALT + SHIFT + F10", hl.dsp.exec_cmd("qs ipc -c @QUICKSHELL_DIR@ call clips buffer"))
hl.bind("ALT + SHIFT + F9",  hl.dsp.exec_cmd("qs ipc -c @QUICKSHELL_DIR@ call clips region"))
-- ALT+F8 opens the clip library (every clip and recording; a click plays one in the shell).
hl.bind("ALT + F8",          hl.dsp.exec_cmd("qs ipc -c @QUICKSHELL_DIR@ call clips gallery"))
hl.bind("ALT + Q",              hl.dsp.exec_cmd("@QUICKSHELL_DIR@/scripts/reload-quickshell.sh"))

-- ── Focus ───────────────────────────────────────
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left"  }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up"    }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down"  }))

-- ── Workspaces ──────────────────────────────────
for i = 1, 9 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i, on_current_monitor = true }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end
hl.bind(mainMod .. " + 0",          hl.dsp.focus({ workspace = 10, on_current_monitor = true }))
hl.bind(mainMod .. " + SHIFT + 0",  hl.dsp.window.move({ workspace = 10 }))
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- ── Mouse window control ────────────────────────
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Drop a SUPER-dragged window on a workspace in the bar's workspace pill to send
-- it there. Hyprland owns the drag, so the shell never sees it: note the window
-- the press picked up, and on release tell the shell where the pointer is (local
-- to its monitor). Only the shell knows where the pill's dots are, so it decides
-- whether that was a drop (WorkspacesPill, UiState.windowDropped). `begin` lets it
-- follow the pointer meanwhile and light up the slot under it. Both binds are
-- non-consuming; the release one runs on every left release, and does nothing
-- unless a SUPER+press armed it.
local draggedWindow = nil

-- The window under the pointer, topmost first (floating over tiled, then the most
-- recently focused); the focused window if the lookup finds nothing.
local function windowAt(p)
    local best = nil
    for _, w in ipairs(hl.get_windows()) do
        local at, size = w.at, w.size
        if w.mapped and not w.hidden and w.workspace and w.workspace.visible
           and type(at) == "table" and type(size) == "table" then
            local x, y = at.x or at[1], at.y or at[2]
            local ww, wh = size.x or size[1], size.y or size[2]
            if x and y and ww and wh and p.x >= x and p.x < x + ww and p.y >= y and p.y < y + wh then
                if not best
                   or (w.floating and not best.floating)
                   or (w.floating == best.floating and w.focus_history_id < best.focus_history_id) then
                    best = w
                end
            end
        end
    end
    return best
end

hl.bind(mainMod .. " + mouse:272", function()
    local ok, w = pcall(function()
        local p = hl.get_cursor_pos()
        return (p and windowAt(p)) or hl.get_active_window()
    end)
    draggedWindow = (ok and w) and w.address or nil
    if draggedWindow then
        hl.exec_cmd("qs ipc -c @QUICKSHELL_DIR@ call windrag begin " .. draggedWindow)
    end
end, { non_consuming = true })

hl.bind("mouse:272", function()
    if not draggedWindow then return end
    local address = draggedWindow
    draggedWindow = nil
    local p, mon = hl.get_cursor_pos(), hl.get_monitor_at_cursor()
    if not p or not mon then return end
    hl.exec_cmd(string.format("qs ipc -c @QUICKSHELL_DIR@ call windrag drop %s %s %d %d",
        address, mon.name, math.floor(p.x - mon.x), math.floor(p.y - mon.y)))
end, { release = true, ignore_mods = true, non_consuming = true })

-- ── HUD input overlay ───────────────────────────
-- >>> qs-input  (scripts/test-inputkeys.js runs this block under a stub)
-- The mouse buttons for the shell's on-screen input overlay (services/InputKeys).
-- STATIC on purpose: the same binds made at runtime from `hyprctl eval` crashed
-- Hyprland 0.56.2 on every re-install (services/inputkeys.js has the trace). Silent
-- unless the overlay is on screen — the shell's hook sets _G.qs_input_on — and
-- non_consuming, so the click always reaches the app; ignore_mods so Shift+click shows.
-- pcall'd as a whole: an error at the top of a Lua config stops everything after it from
-- loading, and this block must never cost the binds below it.
pcall(function()
    for _, b in ipairs({ { 272, "lmb" }, { 273, "rmb" }, { 274, "mmb" }, { 275, "m4" }, { 276, "m5" } }) do
        local function say(state)
            return function()
                if _G.qs_input_on then
                    pcall(function() hl.dispatch(hl.dsp.event("qs-input:" .. state .. b[2])) end)
                end
            end
        end
        hl.bind("mouse:" .. b[1], say("d"), { non_consuming = true, ignore_mods = true })
        hl.bind("mouse:" .. b[1], say("u"), { release = true, non_consuming = true, ignore_mods = true })
    end
end)
-- <<< qs-input

-- ── Volume & brightness ─────────────────────────
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"))
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"))
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"))

-- Volume on the wheel. ALT is deliberate: plain SUPER + wheel is the workspace
-- switcher above. Needs binds.scroll_event_delay low (hardware.lua).
hl.bind(mainMod .. " + ALT + mouse_up",   hl.dsp.exec_cmd("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+"))
hl.bind(mainMod .. " + ALT + mouse_down", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"))

-- Through the shell, not brightnessctl: the OSD answers it, and DDC monitors respond.
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("qs ipc -c @QUICKSHELL_DIR@ call brightness step up"))
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("qs ipc -c @QUICKSHELL_DIR@ call brightness step down"))

-- ── Media playback ───────────────────────────────
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"))
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"))
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"))
