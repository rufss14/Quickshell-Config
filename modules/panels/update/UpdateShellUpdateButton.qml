import "../../../services"
import "../../../state"
import QtQuick
import Quickshell
import QtQuick.Layouts
import Quickshell.Io
import "../../../config"
import "../../../components"
import "../../../services/updatefmt.js" as UF

// ── The shell's own update: a gear beside the password field ─────────────
// A square, field-high chip — a password doesn't need the whole width.
// Quickshell's gear, stencilled so it wears the scheme; it spins while checking or installing, fills when
// a release is waiting, and goes danger-red after a failed install. Click = Check, or Update once there's
// something to install. Its words borrow a line the panel already has — see _shellNoteShown — so nothing
// ever changes the panel's height. Settings → Updates has the full card (notes, schedule toggle).
// (Was UpdatePanel's inline `ShellUpdateButton`; `host` is the UpdatePanel.)
ChipButton {
    required property var host
    implicitHeight: host._fieldH
    implicitWidth:  host._fieldH
    on: ShellUpdate.available || ShellUpdate.error !== ""
    tint: ShellUpdate.error !== "" ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).primary
    iconSource: Icons.logo("quickshell-mono.svg")
    iconAngle: ShellUpdate.checking || ShellUpdate.installing ? host._shellPhase : 0
    enabled: !ShellUpdate.installing && !ShellUpdate.checking
             && (!ShellUpdate.available || ShellUpdate.blocker === "")
    onActivated: {
        if (ShellUpdate.available) { ShellUpdate.install(); return }
        host._shellAsked = true
        ShellUpdate.check()
    }
    HoverHandler { onHoveredChanged: host._shellHover = hovered }
}
