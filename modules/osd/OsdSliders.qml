pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "osdmetrics.js" as Metrics

// ── OsdSliders ────────────────────────────────────────────────────────────────
// The OSD — its levels and its announcement tiles — as a FLOATING overlay window, and
// only while a window is fullscreen on this monitor. Normally it is welded into the
// screen frame (modules/bar/OsdDock, inside the bar's own window, where the blob can fuse
// it with the frame), but Hyprland hides the bar's layer under a fullscreen window, so for
// exactly that case this Overlay-layer copy answers instead. The notification deck
// makes the same hand-off (BarToastHost → NotificationOverlay), on the same
// `Fullscreen.byMonitor` flag. What is in it is OsdColumn, shared with the dock.
//
// Never takes the keyboard (it appears unprompted), and takes the pointer only over
// the card (the mask).
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: win

    // `screen` is PanelWindow's own, assigned by shell.qml — never redeclared.

    // Its own namespace: two layer surfaces sharing one fight over keyboard focus.
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "quickshell-osd-sliders"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: -1

    // ── The screen is cached, not read live ───────────────────────────────────
    // `screen` is a WINDOW property: it re-notifies when this window is created or
    // destroyed, and this window's own `visible` is derived from `shown`, which read it —
    // shown → visible → map/unmap → screenChanged → shown (the "Binding loop detected for
    // property shown" in the log). CavaBG has the whole story. A non-null screen is copied
    // here on change, so the map/unmap flicker never reaches the binding.
    property var homeScreen: null
    property string monitorName: ""
    function _syncScreen() {
        if (!win.screen) return
        win.homeScreen = win.screen
        win.monitorName = win.screen.name ?? ""
    }
    onScreenChanged: win._syncScreen()
    Component.onCompleted: win._syncScreen()

    readonly property bool owns: screenOwner.owns
    ScreenOwner {
        id: screenOwner
        screen: win.homeScreen
        open: Osd.active
    }

    // The dock answers everywhere except under a fullscreen window.
    readonly property bool shown: Osd.active && win.owns
                                  && Fullscreen.byMonitor[win.monitorName] === true

    // The window is bigger than the card only so its shadow has somewhere to land (paint
    // stops at a surface edge) — and it is sized for the WIDEST and TALLEST the column can
    // be (a tile's width, all three levels' height), so a row appearing or a tile replacing
    // the levels never resizes the surface. The numbers are OsdColumn's own, from the same
    // call (osdmetrics.js).
    readonly property int room: Tokens.shadowRoom(Tokens.elevationCard)
    readonly property var m: Metrics.of(Tokens.pillHeight, Tokens.spacingMd, Tokens.spacingLg, Tokens.spacingXl)

    anchors.right: true
    margins.right: Tokens.spacingXl - win.room

    implicitWidth:  win.m.maxCardW + win.room * 2
    implicitHeight: win.m.maxCardH + win.room * 2
    color: "transparent"
    visible: win.shown || card.opacity > 0.005

    // ── The mask is NOT optional ──────────────────────────────────────────────
    // A layer surface with no input region takes the pointer over its WHOLE surface; the
    // shadow halo would swallow clicks over whatever is underneath. Input region only —
    // paint is unaffected.
    mask: Region { item: card }

    Surface {
        id: card

        // The column's own size, held by the Loader for as long as the window is visible
        // (fade-out included). No Behavior on it: `x` below is derived from the width, and
        // a Behavior on x would chase a width that is itself moving.
        width:  loader.item ? loader.item.implicitWidth : 0
        height: loader.item ? loader.item.implicitHeight : 0
        anchors.verticalCenter: parent.verticalCenter
        elevation: Tokens.elevationCard

        // Slides in from the screen edge, its right side `spacingXl` off it. The arrival is
        // faster than the departure: this answers a keypress, and any easing-in is latency
        // you can feel.
        x: win.shown ? win.width - win.room - card.width : win.width
        opacity: win.shown ? 1 : 0

        Behavior on x {
            NumberAnimation {
                duration: win.shown ? Motion.respond : Motion.exit
                easing.type: win.shown ? Motion.respondCurve : Motion.exitCurve
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: win.shown ? Motion.respond : Motion.exit
                easing.type: win.shown ? Motion.respondCurve : Motion.exitCurve
            }
        }

        // Present for as long as it is visible, fade-out included.
        Loader {
            id: loader
            active: win.visible
            sourceComponent: OsdColumn { forScreen: win.screen }
        }
    }

    // ── The wave (components/Infection.qml) ──────────────────────────────────
    // A wallpaper/colour change reaches this window when the front does. It stands at
    // the right edge, vertically centred.
    Infection {
        host: win.contentItem
        screen: win.screen
        hostVisible: win.visible
        windowX: (win.screen ? win.screen.width : win.width) - win.width - win.margins.right
        windowY: ((win.screen ? win.screen.height : win.height) - win.height) / 2
    }
}
