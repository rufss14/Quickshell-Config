pragma Singleton
import Quickshell
import Quickshell.Io
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
//   quiet    ambient effects should rest: the saver OR Game Mode (or safe mode). The sites that used
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
    // …or safe mode (services/SafeMode): the effects rest while the shell recovers from a crash.
    readonly property bool quiet: root.active || Gamemode.active || SafeMode.on

    // ── Is there a power-profiles daemon? ─────────────────────────────────────
    // Touching Quickshell's `PowerProfiles` singleton makes it try to start the daemon over D-Bus, and
    // on a machine without power-profiles-daemon (or tuned-ppd) that is a warning at every start
    // ("Could not launch service org.freedesktop.UPower.PowerProfiles"). Everything that reads a
    // profile asks `profilesOk &&` first: `&&` short-circuits, so the singleton is never built where
    // the name is neither running nor activatable. False until the probe answers, which only delays
    // the control by a moment.
    property bool profilesOk: false
    Process {
        running: true
        command: ["sh", "-c", "{ busctl --system --activatable list --no-legend; busctl --system list --no-legend; } 2>/dev/null"
                              + " | grep -q '^org.freedesktop.UPower.PowerProfiles '"]
        onExited: function (code) { root.profilesOk = code === 0 }
    }

    // Wallpaper Engine's frame cap while saving. A launch argument, so a change means a
    // relaunch (WallpaperEngine does it once per transition, only when it matters).
    readonly property int wpeFpsCap: 30
}
