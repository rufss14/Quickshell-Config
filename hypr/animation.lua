-- ══════════════════════════════════════════════
--  animation.lua — animation curves and per-leaf timing
--
--  The `wind` curve (windows, moves, fades, workspaces) takes its control
--  points from blend.lua, shared with the shell's Motion.emphasizedDecel — so a
--  window and a panel enter with the same ease. Per-leaf `speed` stays here:
--  the shell's Hyprland settings page edits these lines directly.
-- ══════════════════════════════════════════════

local blend = require("blend")
local cp = blend.curve_points

hl.curve("wind",   { type = "bezier", points = { { cp[1], cp[2] }, { cp[3], cp[4] } } })
hl.curve("winIn",  { type = "bezier", points = { { 0.1,  1.1  }, { 0.1,  1.1 } } })
hl.curve("winOut", { type = "bezier", points = { { 0.3,  -0.3 }, { 0,    1   } } })
hl.curve("liner",  { type = "bezier", points = { { 1,    1    }, { 1,    1   } } })

hl.animation({ leaf = "windows",     enabled = true, speed = 6,    bezier = "wind",   style = "slide" })
hl.animation({ leaf = "windowsIn",   enabled = true, speed = 6,    bezier = "winIn",  style = "slide" })
hl.animation({ leaf = "windowsOut",  enabled = true, speed = 5,    bezier = "winOut", style = "slide" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 5,    bezier = "wind",   style = "slide" })
hl.animation({ leaf = "border",      enabled = true, speed = 6.4,  bezier = "liner"   })
-- Off: `loop` re-renders every output every frame, forever, to rotate the border's
-- gradient — and wal-reload.sh writes a SOLID colour (one stop), so the rotation is
-- invisible. It kept the compositor busy at the full refresh rate on an idle desktop.
-- Only worth turning back on alongside a multi-stop col.active_border.
hl.animation({ leaf = "borderangle", enabled = false, speed = 30,   bezier = "liner",  style = "loop"  })
hl.animation({ leaf = "fade",        enabled = true, speed = 10,   bezier = "wind"    })
hl.animation({ leaf = "workspaces",  enabled = true, speed = 5,    bezier = "wind"    })
