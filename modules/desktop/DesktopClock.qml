import Quickshell
import Quickshell.Wayland
import QtQuick
import "../../config"
import "../../components"
import "../../services"
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

    // Bottom layer: sits behind every normal window, like a wallpaper element.
    //
    // Not Background — same reasoning as CavaBG and WidgetLayer: linux-wallpaperengine
    // runs on the `background` layer, and relaunching it for an animated wallpaper
    // change would map a fresh surface after this one, burying the clock until a
    // manual reload. `Bottom` sits above `Background` unconditionally.
    WlrLayershell.layer:     WlrLayer.Bottom
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
    // The shared wall clock (services/Clock.qml). This used to own a 1000ms Timer to
    // render `hh:mm` — fifty-nine wakeups a minute to redraw identical pixels — and it
    // does not acquire second resolution, because nothing here displays seconds.
    //
    // The "snap to the current time when re-enabled" Connections that used to sit here
    // has gone with it: it existed because a gated timer left `now` frozen at whatever
    // it was when the clock was hidden, so reopening showed a stale minute until the
    // next tick. A shared clock is never stale, so there is nothing to snap.
    readonly property date now: Clock.now

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
            font.pixelSize: Tokens.fontClock
            font.weight:    Font.Bold
            font.letterSpacing: 4

            color: Colors.of(QsWindow.window).fg
            // Outlined, because this sits directly on the wallpaper — it has no
            // surface behind it, so it needs to stay legible over anything.
            style:      Text.Outline
            styleColor: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surface, 0.7)
        }

        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(root.now, "dddd, MMMM d").toUpperCase()

            font.family:    Tokens.fontMono
            font.pixelSize: Tokens.fontLabel + 2
            font.weight:    Font.Bold
            font.letterSpacing: 3

            color: Colors.of(QsWindow.window).fgDim
            style:      Text.Outline
            styleColor: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surface, 0.7)
        }
    }

    // ── The wave (components/Infection.qml) ───────────────────────────────────
    // The clock takes a wallpaper/colour change when the front reaches ITS corner.
    // It respects the exclusive zones (exclusiveZone 0), so its margins count from
    // where Hyprland's reserved edges end.
    readonly property var _reserved: Hypr.reservedOf(Hypr.monitorFor(root.screen))
    Infection {
        host: root.contentItem
        screen: root.screen
        hostVisible: root.visible
        windowX: (root.screen ? root.screen.width : root.width)
                 - root._reserved[2] - root.margins.right - root.width
        windowY: (root.screen ? root.screen.height : root.height)
                 - root._reserved[3] - root.margins.bottom - root.height
    }
}
