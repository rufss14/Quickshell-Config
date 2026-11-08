import QtQuick
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"

// ── LocksPill ─────────────────────────────────────────────────────────────────
// Only while something is on: the active Hyprland submap (its name), Caps Lock, Num
// Lock — as one short label, "RESIZE · CAPS". BarModules hides it otherwise, so it
// costs no room. Holding KeyLocks is what puts its tiny key hook into Hyprland; taking
// this off the bar takes the hook out.
// ─────────────────────────────────────────────────────────────────────────────
BarIconPill {
    id: root

    moduleId: "locks"
    active: true
    label: {
        const parts = []
        if (KeyLocks.submap !== "") parts.push(KeyLocks.submap.toUpperCase())
        if (KeyLocks.caps) parts.push("CAPS")
        if (KeyLocks.num)  parts.push("NUM")
        return parts.join(" · ")
    }
    iconColor: KeyLocks.submap !== "" ? Colors.of(QsWindow.window).warning : root.accent
    interactive: false

    Component.onCompleted: KeyLocks.acquire()
    Component.onDestruction: KeyLocks.release()
}
