pragma Singleton
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import QtQuick
import "../config"

// ── BarModules ────────────────────────────────────────────────────────────────
// May this bar module appear on THIS machine, right now?
//
// Not a preference — a module the user does not want is simply not in
// `Config.layout`. This answers the separate question of whether a module the user
// HAS placed has anything to show: an empty tray, a battery pill on a desktop, a
// bluetooth pill with no adapter.
//
// ── Why it is a singleton and not a method on the bar ─────────────────────────
// It lived in Bar.qml as `moduleVisible(id)` once, which was right while the bar
// was the only thing that ever asked. The settings page's Bar › Modules view briefly
// rendered a second copy of the bar through the same BarGroupRow (BarPreview,
// removed — the real bar a few pixels above the window made it redundant), and a
// private method couldn't answer "does this machine have a battery" for both.
//
// The failure that would cause is quiet and slow: the preview shows a battery pill
// the real bar does not, so the strip claims a layout you cannot actually get, and
// nothing anywhere reports a disagreement. Config.qml cannot hold this — it sits
// BELOW the services layer and must not import UPower or SystemTray — so it lives
// here, one level up, where both callers can reach it.
//
// Everything below is live: plugging a bluetooth dongle in makes the pill appear
// without a reload, and it appears in the preview at the same instant.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    function visible(id) {
        // The tray hides when empty. An empty tray has nothing to draw, so its group
        // would render as an empty pill.
        if (id === "tray") return SystemTray.items.values.length > 0

        // The one entry here that IS a preference, and it earns its place: the
        // notifications pill can be configured to hide unless DND is on, turning it
        // from a permanent bell into a discreet "do not disturb is active"
        // indicator. That is a module choosing to hide itself, which is this
        // function's subject, rather than the user choosing not to have it.
        if (id === "notifications")
            return !Config.notifShowOnlyDnd() || Notifications.quiet

        // Battery is the one that matters most for a config other people install: a
        // desktop must not show a charge indicator for a battery it does not have.
        if (id === "battery") return UPower.displayDevice?.isLaptopBattery ?? false

        // No adapter, no pill.
        if (id === "bluetooth") return Bt.available

        // Only while a submap, Caps Lock or Num Lock is on.
        if (id === "locks") return KeyLocks.any

        return true
    }

    // ── Why a module can't be placed on this machine, or "" ───────────────────
    // The other question: not "has it anything to show right now" (visible, above)
    // but "would placing it ever work here". A missing optional tool disables the
    // control with a reason rather than failing on click (CLAUDE.md › Portability), so
    // the module library and the inspector ask this and grey the module out with the
    // answer. Each service owns its own probe and wording; this only routes to it.
    function blocker(id) {
        if (id === "colour")     return ColorPicker.blocker()
        if (id === "lens")       return Lens.blocker()
        if (id === "nightlight") return NightLight.blocker()
        if (id === "clips")      return Clips.blocker()
        if (id === "bluetooth")  return Bt.available ? "" : "No Bluetooth adapter on this machine"
        if (id === "battery")
            return (UPower.displayDevice?.isLaptopBattery ?? false) ? "" : "No battery on this machine"
        return ""
    }
}
