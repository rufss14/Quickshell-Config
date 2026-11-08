#!/usr/bin/env lua5.4
-- check-blend.lua — sanity-check blend.lua (the file hypr + quickshell share).
-- Run:  lua5.4 ~/.config/hypr/scripts/check-blend.lua
-- Fails loudly if a key the other side expects is missing or out of range.

local dir = os.getenv("XDG_CONFIG_HOME")
dir = (dir and dir .. "/hypr") or (os.getenv("HOME") .. "/.config/hypr")

local b = assert(dofile(dir .. "/blend.lua"))
assert(type(b) == "table", "blend.lua must return a table")

local nums = {
    rounding = {1, 64}, rounding_power = {1, 4}, border_size = {0, 20},
    gaps_in = {0, 60}, gaps_out = {0, 120},
    active_opacity = {0.1, 1.0}, inactive_opacity = {0.1, 1.0},
    blur_size = {0, 40}, blur_passes = {0, 10}, blur_vibrancy = {0, 1},
    border_active_wal = {0, 15}, border_inactive_wal = {0, 15}, shadow_wal = {0, 15},
}
for k, range in pairs(nums) do
    local v = b[k]
    assert(type(v) == "number", "blend.lua: missing or non-number key: " .. k)
    assert(v >= range[1] and v <= range[2],
        string.format("blend.lua: %s = %s out of [%s, %s]", k, v, range[1], range[2]))
end

assert(type(b.curve_points) == "table" and #b.curve_points == 4,
    "blend.lua: curve_points must be a 4-number list")
for i, n in ipairs(b.curve_points) do
    assert(type(n) == "number", "blend.lua: curve_points[" .. i .. "] not a number")
end

print("blend.lua OK")
