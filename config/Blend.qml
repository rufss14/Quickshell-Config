pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// ── Blend ────────────────────────────────────────────────────────────────────
// The values ~/.config/hypr and this shell share, read straight from
// ~/.config/hypr/blend.lua and watched live. It is the ONE file that decides a
// window's corner, border, translucency and blur — so the same numbers decide
// the bar's and the panels'. Change blend.lua, `hyprctl reload` repaints the
// windows, and this repaints the shell with no reload.
//
// ── Why a regex parse and not JSON ────────────────────────────────────────────
// blend.lua has to be a Lua module (Hyprland require()s it directly, no JSON in
// its embedded Lua). QML has no Lua runtime, but blend.lua is deliberately flat —
// `key = number` and `key = { n, n, ... }` — and scripts/hypr-config.py already
// reads the rest of the hypr config exactly this way. No subprocess, no new dep.
//
// ── Fallbacks are load-bearing ───────────────────────────────────────────────
// This config is published; a machine without ~/.config/hypr/blend.lua must
// still get a shell that looks right. `v` always resolves to a full set — the
// file only overrides. Consumers (Defaults, Tokens, Motion) read `v.*` and never
// need their own fallback.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property var _defaults: ({
        rounding: 16, rounding_power: 2, border_size: 2,
        gaps_in: 4, gaps_out: 8,
        active_opacity: 0.97, inactive_opacity: 0.93,
        blur_size: 5, blur_passes: 3, blur_vibrancy: 0.7,
        border_active_wal: 4, border_inactive_wal: 2, shadow_wal: 0,
        curve_points: [0.05, 0.7, 0.1, 1.0]
    })

    property var _file: ({})

    // Merged view: file wins, defaults fill every gap.
    readonly property var v: {
        const out = ({})
        for (const k in root._defaults) out[k] = root._defaults[k]
        for (const k in root._file) if (root._file[k] !== undefined) out[k] = root._file[k]
        return out
    }

    function _parse(text) {
        const out = ({})
        const numRe  = /^\s*([a-z_]+)\s*=\s*(-?[0-9.]+)\s*,?\s*$/
        const listRe = /^\s*([a-z_]+)\s*=\s*\{([^}]*)\}/
        for (const raw of text.split("\n")) {
            const line = raw.replace(/--.*$/, "").replace(/\s+$/, "")
            let m = line.match(listRe)
            if (m) {
                out[m[1]] = m[2].split(",")
                    .map(s => parseFloat(s.trim()))
                    .filter(n => !isNaN(n))
                continue
            }
            m = line.match(numRe)
            if (m) out[m[1]] = parseFloat(m[2])
        }
        return out
    }

    FileView {
        id: blendFile
        path: Quickshell.env("HOME") + "/.config/hypr/blend.lua"
        preload: true          // see Colors.qml — without this onLoaded never fires
        printErrors: false      // absent file is a supported state, not an error
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root._file = root._parse(blendFile.text()) }
            catch (e) { console.warn("Blend: could not parse blend.lua —", e) }
        }
        onLoadFailed: root._file = ({})
    }
}
