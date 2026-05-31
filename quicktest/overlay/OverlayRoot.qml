import Quickshell
import Quickshell.Wayland
import QtQuick
import "."
import "modules" as OV
import "modules"
import "../theming" as T

// ── OverlayRoot ───────────────────────────────────────────────────────────────
// Owns all overlay panel popup windows and their layout logic.
// Open/closed state is driven by the Panels singleton so that any part of the
// shell (status bar, hotkeys, …) can toggle panels without touching this file.
//
// Layout
// ──────
//   TOP-LEFT column (left-anchored, panels stack rightward then downward)
//
//     [ Wallpaper (535) ][ Brightness (300) ]
//     [ Equalizer (460) ][ BGM (528)        ]
//
//   TOP-RIGHT column (right-anchored, panels stack leftward)
//
//     [ WiFi (360) ][ Clock (320) ]
//
// Collision avoidance
// ───────────────────
// Within each row, a sibling panel that would overlap pushes the later panel
// outward. The margin is a computed `readonly property` so QML re-evaluates it
// whenever an open flag changes; a `Behavior` on the PanelWindow margin then
// animates the slide.
// ─────────────────────────────────────────────────────────────────────────────
QtObject {
    id: root

    property var screen  // passed from shell.qml Variants delegate

    // ── Geometry constants ────────────────────────────────────────────────────
    readonly property int topMargin:  T.Theme.barHeight + 2
    readonly property int edgeMargin: T.Theme.barMargin + 8
    readonly property int gap:        8

    // Panel widths — must match each PanelWindow's implicitWidth.
    readonly property int wallpaperW:  535
    readonly property int brightnessW: 300
    readonly property int equalizerW:  460
    readonly property int bgmW:        528
    readonly property int wifiW:       360
    readonly property int clockW:      340

    // ── Left-side layout ──────────────────────────────────────────────────────
    // Default (nothing open): Brightness spawns at the Wallpaper anchor (top-left).
    // Wallpaper open:         Brightness is pushed right, sitting beside it on row 0.
    // Equalizer open:         Brightness is pushed below the Equalizer on row 1.
    // Both open:              Equalizer is on row 1 (pushed down by Wallpaper),
    //                         Brightness is on row 2, below the Equalizer.
    //
    //   Nothing open:
    //     [ Brightness (at wallpaper anchor) ]
    //
    //   Wallpaper open:
    //     [ Wallpaper (535) ][ Brightness (300) ]
    //
    //   Equalizer open:
    //     [ Equalizer (460) ][ BGM (528) ]
    //     [ Brightness (300) ]
    //
    //   Both open:
    //     [ Wallpaper (535) ][ Brightness pushed right... ]
    //     [ Equalizer (460) ][ BGM (528)                 ]
    //     [ Brightness (300) ]

    readonly property real wallpaperLeft: edgeMargin

    // Equalizer — left edge, pushed to row 1 when wallpaper is open
    readonly property real equalizerLeft: wallpaperLeft
    readonly property real equalizerTop: {
        if (Panels.wallpaperOpen)
            return topMargin + 340 + gap
        return topMargin
    }

    // BGM — sits to the right of Equalizer on row 1.
    // If Equalizer is not open it sits at the left edge.
    readonly property real bgmLeft: Panels.equalizerOpen
        ? equalizerLeft + equalizerW + gap
        : edgeMargin
    readonly property real bgmTop: equalizerTop

    // ── Right-side layout ─────────────────────────────────────────────────────
    readonly property real clockRight: edgeMargin

    readonly property real wifiRight: {
        if (Panels.clockOpen)
            return clockRight + clockW + gap
        return edgeMargin
    }

    // ── Popup windows ─────────────────────────────────────────────────────────

    // Wallpaper — top-left, fixed anchor
    property var wallpaperPopup: PanelWindow {
        id: wallpaperWin
        screen:                      root.screen
        WlrLayershell.layer:         WlrLayer.Overlay
        WlrLayershell.namespace:     "quickshell-wallpaper-popup"
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: Panels.wallpaperOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        anchors.top:  true
        anchors.left: true
        margins.top:  root.topMargin
        margins.left: root.wallpaperLeft

        implicitWidth:  root.wallpaperW
        implicitHeight: 340
        color: "transparent"
        visible: Panels.activeScreen === root.screen && (Panels.wallpaperOpen || wallpaperCard.opacity > 0.005)

        Item {
            id: wallpaperWinFocusItem
            Keys.onEscapePressed: Panels.wallpaperOpen = false
            Connections {
                target: Panels
                function onWallpaperOpenChanged() {
                    if (Panels.wallpaperOpen) wallpaperWinFocusItem.forceActiveFocus()
                }
            }
        }

        Rectangle {
            id: wallpaperCard
            anchors.fill: parent
            radius: T.Theme.pillRadius + 4
            color:        T.Theme.bg
            border.color: T.Theme.barBorder
            border.width: 1
            opacity: Panels.wallpaperOpen ? 1.0 : 0.0
            scale:   Panels.wallpaperOpen ? 1.0 : 0.96
            transformOrigin: Item.TopLeft

            Behavior on opacity { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutBack  } }

            OV.WallpaperPanel { anchors.fill: parent }
        }
    }

    // Brightness — row 0 when alone, drops to row 1 when others are open
    property var brightnessPopup: PanelWindow {
        id: brightnessWin
        screen:                      root.screen
        WlrLayershell.layer:         WlrLayer.Overlay
        WlrLayershell.namespace:     "quickshell-brightness-popup"
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: Panels.brightnessOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        anchors.top:  true
        anchors.left: true

        property real targetLeft: root.edgeMargin
        property real targetTop: {
            if (Panels.equalizerOpen || Panels.bgmOpen) {
                var rowH = Math.max(Panels.equalizerOpen ? equalizerWin.implicitHeight : 0,
                                    Panels.bgmOpen       ? bgmWin.implicitHeight       : 0)
                return root.equalizerTop + rowH + root.gap
            }
            if (Panels.wallpaperOpen)
                return root.topMargin + 340 + root.gap
            return root.topMargin
        }
        margins.left: targetLeft
        margins.top:  targetTop
        Behavior on targetLeft { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutCubic } }
        Behavior on targetTop  { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutCubic } }

        implicitWidth:  root.brightnessW
        implicitHeight: brightnessContent.implicitHeight
        color: "transparent"
        visible: Panels.activeScreen === root.screen && (Panels.brightnessOpen || brightnessCard.opacity > 0.005)

        Item {
            id: brightnessWinFocusItem
            Keys.onEscapePressed: Panels.brightnessOpen = false
            Connections {
                target: Panels
                function onBrightnessOpenChanged() {
                    if (Panels.brightnessOpen) brightnessWinFocusItem.forceActiveFocus()
                }
            }
        }

        Rectangle {
            id: brightnessCard
            anchors.fill: parent
            radius: T.Theme.pillRadius + 4
            color:        T.Theme.bg
            border.color: T.Theme.barBorder
            border.width: 1
            opacity: Panels.brightnessOpen ? 1.0 : 0.0
            scale:   Panels.brightnessOpen ? 1.0 : 0.96
            transformOrigin: Item.TopLeft

            Behavior on opacity { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutBack  } }

            OV.BrightnessPanel { id: brightnessContent; anchors.fill: parent }
        }
    }

    // Equalizer — below Wallpaper, left-aligned to it
    property var equalizerPopup: PanelWindow {
        id: equalizerWin
        screen:                      root.screen
        WlrLayershell.layer:         WlrLayer.Overlay
        WlrLayershell.namespace:     "quickshell-equalizer-popup"
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: Panels.equalizerOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        anchors.top:  true
        anchors.left: true
        margins.left: root.equalizerLeft

        property real targetTop: root.equalizerTop
        margins.top: targetTop
        Behavior on targetTop { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutCubic } }

        implicitWidth:  root.equalizerW
        implicitHeight: equalizerContent.implicitHeight

        color: "transparent"
        visible: Panels.activeScreen === root.screen && (Panels.equalizerOpen || equalizerCard.opacity > 0.005)

        Item {
            id: equalizerWinFocusItem
            Keys.onEscapePressed: Panels.equalizerOpen = false
            Connections {
                target: Panels
                function onEqualizerOpenChanged() {
                    if (Panels.equalizerOpen) equalizerWinFocusItem.forceActiveFocus()
                }
            }
        }

        Rectangle {
            id: equalizerCard
            anchors.fill: parent
            radius: T.Theme.pillRadius + 4
            color:        T.Theme.bg
            border.color: T.Theme.barBorder
            border.width: 1
            opacity: Panels.equalizerOpen ? 1.0 : 0.0
            scale:   Panels.equalizerOpen ? 1.0 : 0.96
            transformOrigin: Item.TopLeft

            Behavior on opacity { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutBack  } }

            OV.EqualizerPanel { id: equalizerContent; anchors.fill: parent }
        }
    }

    // BGM — row 1, to the right of Equalizer (or at left edge if Equalizer closed)
    property var bgmPopup: PanelWindow {
        id: bgmWin
        screen:                      root.screen
        WlrLayershell.layer:         WlrLayer.Overlay
        WlrLayershell.namespace:     "quickshell-bgm-popup"
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: Panels.bgmOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        anchors.top:  true
        anchors.left: true

        property real targetLeft: root.bgmLeft
        property real targetTop:  root.bgmTop
        margins.left: targetLeft
        margins.top:  targetTop
        Behavior on targetLeft { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutCubic } }
        Behavior on targetTop  { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutCubic } }

        implicitWidth:  root.bgmW
        implicitHeight: 238
        color: "transparent"
        visible: Panels.activeScreen === root.screen && (Panels.bgmOpen || bgmCard.opacity > 0.005)

        Item {
            id: bgmWinFocusItem
            Keys.onEscapePressed: Panels.bgmOpen = false
            Connections {
                target: Panels
                function onBgmOpenChanged() {
                    if (Panels.bgmOpen) bgmWinFocusItem.forceActiveFocus()
                }
            }
        }

        Rectangle {
            id: bgmCard
            anchors.fill: parent
            radius: T.Theme.pillRadius + 4
            color:        T.Theme.bg
            border.color: T.Theme.barBorder
            border.width: 1
            opacity: Panels.bgmOpen ? 1.0 : 0.0
            scale:   Panels.bgmOpen ? 1.0 : 0.96
            transformOrigin: Item.TopLeft

            Behavior on opacity { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutBack  } }

            OV.BgmPanel { anchors.fill: parent }
        }
    }

    // WiFi — top-right, slides left when Clock is also open
    property var wifiPopup: PanelWindow {
        id: wifiWin
        screen:                      root.screen
        WlrLayershell.layer:         WlrLayer.Overlay
        WlrLayershell.namespace:     "quickshell-wifi-popup"
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: Panels.wifiOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        anchors.top:   true
        anchors.right: true
        margins.top:   root.topMargin

        property real targetRight: root.wifiRight
        margins.right: targetRight
        Behavior on targetRight { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutCubic } }

        implicitWidth:  root.wifiW
        implicitHeight: wifiContent.implicitHeight
        color: "transparent"
        visible: Panels.activeScreen === root.screen && (Panels.wifiOpen || wifiCard.opacity > 0.005)

        Item {
            id: wifiWinFocusItem
            Keys.onEscapePressed: Panels.wifiOpen = false
            Connections {
                target: Panels
                function onWifiOpenChanged() {
                    if (Panels.wifiOpen) wifiWinFocusItem.forceActiveFocus()
                }
            }
        }

        Rectangle {
            id: wifiCard
            anchors.fill: parent
            radius: T.Theme.pillRadius + 4
            color:        T.Theme.bg
            border.color: T.Theme.barBorder
            border.width: 1
            opacity: Panels.wifiOpen ? 1.0 : 0.0
            scale:   Panels.wifiOpen ? 1.0 : 0.96
            transformOrigin: Item.Top

            Behavior on opacity { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutBack  } }

            OV.WifiPanel { id: wifiContent; anchors.fill: parent }
        }
    }

    // Clock — rightmost, fixed anchor
    property var clockPopup: PanelWindow {
        id: clockWin
        screen:                      root.screen
        WlrLayershell.layer:         WlrLayer.Overlay
        WlrLayershell.namespace:     "quickshell-clock-popup"
        WlrLayershell.exclusiveZone: -1
        WlrLayershell.keyboardFocus: Panels.clockOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        anchors.top:   true
        anchors.right: true
        margins.top:   root.topMargin
        margins.right: root.clockRight

        implicitWidth:  root.clockW
        implicitHeight: clockContent.implicitHeight
        color: "transparent"
        visible: Panels.activeScreen === root.screen && (Panels.clockOpen || clockCard.opacity > 0.005)

        Item {
            id: clockWinFocusItem
            Keys.onEscapePressed: Panels.clockOpen = false
            Connections {
                target: Panels
                function onClockOpenChanged() {
                    if (Panels.clockOpen) clockWinFocusItem.forceActiveFocus()
                }
            }
        }

        Rectangle {
            id: clockCard
            anchors.fill: parent
            radius: T.Theme.pillRadius + 4
            color:        T.Theme.bg
            border.color: T.Theme.barBorder
            border.width: 1
            opacity: Panels.clockOpen ? 1.0 : 0.0
            scale:   Panels.clockOpen ? 1.0 : 0.96
            transformOrigin: Item.TopRight

            Behavior on opacity { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutBack  } }

            ClockPanel { id: clockContent; anchors.fill: parent }
        }
    }

    // ── Register panel content references into Panels singleton ───────────────
    Component.onCompleted: {
        Panels.updatePanel     = null
        Panels.wallpaperPanel  = wallpaperPopup
        Panels.brightnessPanel = brightnessPopup
        Panels.wifiPanel       = wifiPopup
        Panels.equalizerPanel  = equalizerPopup
        Panels.clockPanel      = clockPopup
        Panels.bgmPanel        = bgmPopup
        console.log("[OverlayRoot] All panels registered successfully")
    }
}
