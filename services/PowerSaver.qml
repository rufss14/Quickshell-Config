pragma Singleton
import Quickshell
import Quickshell.Services.UPower
import QtQuick
import "../config"

// ── PowerSaver ────────────────────────────────────────────────────────────────
// Turns the shell's costly AMBIENT effects off while on battery: the cava
// background, wallpaper effects, the music-pulse helper, the floating cookies, and
// Wallpaper Engine above 30 fps. UI animations and Hyprland's own effects are left
// alone — they are cheap next to these, and they carry information.
//
//   Config.powerSaver   "auto" (on while UPower says on battery; the default)
//                       "on" | "off" (forced either way)
//
// Two answers, because Game Mode already quiets the same effects for a different
// reason:
//   active   the saver itself is on (the UI says "Battery saver")
//   quiet    ambient effects should rest: the saver OR Game Mode. The sites that used
//            to read `!Gamemode.active` for this read `!PowerSaver.quiet` instead, so
//            one list of "what rests" serves both.
//
// A machine with no battery never reports onBattery, so "auto" costs a desktop
// nothing.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property bool onBattery: UPower.onBattery
    readonly property bool active: Config.powerSaver === "on"
                                   || (Config.powerSaver === "auto" && root.onBattery)
    readonly property bool quiet: root.active || Gamemode.active

    // Wallpaper Engine's frame cap while saving. A launch argument, so a change means a
    // relaunch (WallpaperEngine does it once per transition, only when it matters).
    readonly property int wpeFpsCap: 30
}
