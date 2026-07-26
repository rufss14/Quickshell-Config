import Quickshell
import Quickshell.Wayland
import QtQuick
import "../../config"
import "../../components"
import "../../state"

// ── DesktopClock ──────────────────────────────────────────────────────────────
// A large clock pinned to the desktop, behind every window. Toggled by the bar's
// clock pill (UiState.desktopClockOpen).
//
// This file came in referencing `Theme.fg`, `Theme.dimFg` and `Theme.pw()` — the
// compatibility shim, which no longer exists — and with no import for it at all,
// so it could not have loaded. It's on Colors/Tokens/Motion now.
//
// Two other things changed:
//   • It rewrote both labels' `text` imperatively from inside a Timer. They're
//     bindings off a single `now` property instead, so the two can't disagree.
//   • It was always visible. It's now gated on the toggle, and its timer only
//     runs while it's actually on screen — a background clock nobody has enabled
//     shouldn't be waking the process once a second.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: root

    // Background layer: sits behind every normal window, like a wallpaper element.
    WlrLayershell.layer:     WlrLayer.Background
    WlrLayershell.namespace: "quickshell-desktop-clock"

    color:         "transparent"
    exclusiveZone: 0
    focusable:     false

    // Never intercept input — clicks fall through to the desktop.
    mask: Region {}

    // Stays mapped while it fades out, then unmaps.
    visible: UiState.desktopClockOpen || content.opacity > 0.005

    anchors.right:  true
    anchors.bottom: true
    margins.right:  48
    margins.bottom: 48

    implicitWidth:  content.implicitWidth  + Tokens.spacingXxl
    implicitHeight: content.implicitHeight + Tokens.spacingXl

    // ── Time ──────────────────────────────────────────────────────────────────
    // One source, one timer, and it only ticks while the clock is actually shown.
    property date now: new Date()

    Timer {
        interval: 1000
        repeat:   true
        running:  UiState.desktopClockOpen
        onTriggered: root.now = new Date()
    }
    // Snap to the current time the moment it's re-enabled, rather than showing a
    // stale minute for up to a second.
    Connections {
        target: UiState
        function onDesktopClockOpenChanged() {
            if (UiState.desktopClockOpen) root.now = new Date()
        }
    }

    Column {
        id: content
        anchors.centerIn: parent
        spacing: Tokens.spacingSm + 2

        opacity: UiState.desktopClockOpen ? 1.0 : 0.0
        scale:   UiState.desktopClockOpen ? 1.0 : 0.96
        Behavior on opacity {
            NumberAnimation {
                duration:    Motion.surfaceDuration(UiState.desktopClockOpen)
                easing.type: Motion.surfaceEasing(UiState.desktopClockOpen)
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration:    Motion.surfaceDuration(UiState.desktopClockOpen)
                easing.type: Motion.surfaceEasing(UiState.desktopClockOpen)
            }
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(root.now, "hh:mm")

            font.family:    Tokens.fontMono
            font.pixelSize: 72
            font.weight:    Font.Bold
            font.letterSpacing: 4

            color: Colors.fg
            // Outlined, because this sits directly on the wallpaper — it has no
            // surface behind it, so it needs to stay legible over anything.
            style:      Text.Outline
            styleColor: Colors.alpha(Colors.surface, 0.7)
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(root.now, "dddd, MMMM d").toUpperCase()

            font.family:    Tokens.fontMono
            font.pixelSize: Tokens.fontLabel + 2
            font.weight:    Font.Bold
            font.letterSpacing: 3

            color: Colors.fgDim
            style:      Text.Outline
            styleColor: Colors.alpha(Colors.surface, 0.7)
        }
    }
}
