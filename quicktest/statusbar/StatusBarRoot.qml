import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../theming" as T
import "modules"
import "../overlay/modules"

PanelWindow {
    id: root
    Component.onCompleted: console.log("[StatusBarRoot] ready")

    PersistentProperties {
        id: persist
        reloadableId: "statusBarPersist"
        property bool barShape:       false
        property bool barMode:        false
        property bool wallpaperOpen:  false
        property bool clockOpen:      false
        property bool wifiOpen:       false
        property bool brightnessOpen: false
        property bool equalizerOpen:  false
        property bool bgmOpen:        false
        onLoaded: {
            root.barShape        = persist.barShape
            root.barMode         = persist.barMode
            root.wallpaperOpen   = persist.wallpaperOpen
            root.clockOpen       = persist.clockOpen
            root.wifiOpen        = persist.wifiOpen
            root.brightnessOpen  = persist.brightnessOpen
            root.equalizerOpen   = persist.equalizerOpen
            root.bgmOpen         = persist.bgmOpen
        }
    }

    property bool barShape:       false
    property bool barMode:        false
    property bool wallpaperOpen:  false
    property bool clockOpen:      false
    property bool wifiOpen:       false
    property bool brightnessOpen: false
    property bool equalizerOpen:  false
    property bool bgmOpen:        false
    property var  updatePanel:    null

    onBarShapeChanged:       persist.barShape       = barShape
    onBarModeChanged:        persist.barMode        = barMode
    onWallpaperOpenChanged:  persist.wallpaperOpen  = wallpaperOpen
    onClockOpenChanged:      persist.clockOpen      = clockOpen
    onWifiOpenChanged:       persist.wifiOpen       = wifiOpen
    onBrightnessOpenChanged: persist.brightnessOpen = brightnessOpen
    onEqualizerOpenChanged:  persist.equalizerOpen  = equalizerOpen
    onBgmOpenChanged:        persist.bgmOpen        = bgmOpen

    anchors.top:   true
    anchors.left:  true
    anchors.right: true
    implicitHeight: T.Theme.barHeight
    color: "transparent"

    readonly property int splitMargin: root.barShape ? 0 : T.Theme.barMargin
    readonly property int splitRadius: root.barShape ? 0 : T.Theme.pillRadius

    readonly property int fadeOutDur: T.Theme.animNormal
    readonly property int fadeGap:    20
    readonly property int fadeInDur:  T.Theme.animNormal
    readonly property int shapeAnim:  T.Theme.animSlow

    // ── Unified mode ──────────────────────────────────────────────────────────
    PillRect {
        anchors.fill:    parent
        anchors.margins: root.splitMargin
        radius:          root.splitRadius
        border.color:    T.Theme.barBorder

        visible: unifiedInner.opacity > 0.005 || root.barMode

        Behavior on anchors.margins { NumberAnimation { duration: root.shapeAnim; easing.type: Easing.OutCubic } }
        Behavior on radius          { NumberAnimation { duration: root.shapeAnim; easing.type: Easing.OutCubic } }
        Behavior on border.color    { ColorAnimation  { duration: T.Theme.animFast } }

        Item {
            id: unifiedInner
            anchors.fill: parent
            opacity: 0.0
            y: 0

            SequentialAnimation {
                id: unifiedOut
                running: false
                NumberAnimation { target: unifiedInner; property: "opacity"; to: 0.0; duration: root.fadeOutDur; easing.type: Easing.InCubic }
            }
            SequentialAnimation {
                id: unifiedIn
                running: false
                PauseAnimation { duration: root.fadeOutDur + root.fadeGap }
                NumberAnimation { target: unifiedInner; property: "opacity"; to: 1.0; duration: root.fadeInDur; easing.type: Easing.OutCubic }
            }
            ParallelAnimation {
                id: unifiedSlideOut
                running: false
                NumberAnimation { target: unifiedInner; property: "y"; to: -5; duration: root.fadeOutDur; easing.type: Easing.InCubic }
            }
            ParallelAnimation {
                id: unifiedSlideIn
                running: false
                NumberAnimation { target: unifiedInner; property: "y"; to: 0; duration: root.fadeInDur; easing.type: Easing.OutCubic }
            }

            // Left group
            // Order (left→right): BarShape | BarMode | Equalizer | BGM | Wallpaper | Brightness
            RowLayout {
                id: unifiedLeft
                anchors.left:           parent.left
                anchors.leftMargin:     8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                BarShape {
                    id: shapeInner
                    implicitWidth:  Math.round(T.Theme.pillHeight * 1.6)
                    implicitHeight: T.Theme.pillHeight
                    barShape: root.barShape
                    onToggle: root.barShape = !root.barShape
                }
                BarMode {
                    id: modeInner
                    implicitWidth:  Math.round(T.Theme.pillHeight * 1.6)
                    implicitHeight: T.Theme.pillHeight
                    barMode: root.barMode; barShape: root.barShape
                    onToggle: root.barMode = !root.barMode
                }

                // ── BGM ──
                BgmButton {
                    id: bgmInner
                    implicitWidth:  Math.round(T.Theme.pillHeight * 1.6)
                    implicitHeight: T.Theme.pillHeight
                    barShape: root.barShape
                    bgmOpen:  Panels.bgmOpen
                    onToggleBgm: { Panels.activeScreen = root.screen; Panels.bgmOpen = !Panels.bgmOpen }
                }

                // ── Wallpaper + Brightness ──
                WallpaperButton {
                    id: wpInner
                    implicitWidth:  Math.round(T.Theme.pillHeight * 1.6)
                    implicitHeight: T.Theme.pillHeight
                    barShape: root.barShape
                    wallpaperOpen: Panels.wallpaperOpen
                    onToggleWallpaper: { Panels.activeScreen = root.screen; Panels.wallpaperOpen = !Panels.wallpaperOpen }
                }
                BrightnessButton {
                    id: brInner
                    implicitWidth:  Math.round(T.Theme.pillHeight * 1.6)
                    implicitHeight: T.Theme.pillHeight
                    barShape: root.barShape
                    brightnessOpen: Panels.brightnessOpen
                    onToggleBrightness: { Panels.activeScreen = root.screen; Panels.brightnessOpen = !Panels.brightnessOpen }
                }

                // ── Equalizer ──
                EqualizerButton {
                    implicitWidth:  Math.round(T.Theme.pillHeight * 1.6)
                    implicitHeight: T.Theme.pillHeight
                    barShape: root.barShape
                    equalizerOpen: Panels.equalizerOpen
                    onToggleEqualizer: { Panels.activeScreen = root.screen; Panels.equalizerOpen = !Panels.equalizerOpen }
                }
            }

            // Center group
            RowLayout {
                id: unifiedCenter
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter:   parent.verticalCenter
                spacing: 6

                KeyboardLayout { barShape: root.barShape }
                UpdateButton { barShape: root.barShape; updatePanel: root.updatePanel }
                Workspaces   { barShape: root.barShape; monitor: Hyprland.monitors.values.find(m => m.name === root.screen.name) }
                ReloadButton { barShape: root.barShape }
                Tray         { id: trayBalance; barShape: root.barShape; parentWindow: root }
            }

            // Right group
            RowLayout {
                id: unifiedRight
                anchors.right:          parent.right
                anchors.rightMargin:    8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                AudioVisualizer { barShape: root.barShape }
                WifiButton { barShape: root.barShape; wifiOpen:  Panels.wifiOpen;  onToggleWifi:  { Panels.activeScreen = root.screen; Panels.wifiOpen  = !Panels.wifiOpen  }}
                Clock      { barShape: root.barShape; clockOpen: Panels.clockOpen; onToggleClock: { Panels.activeScreen = root.screen; Panels.clockOpen = !Panels.clockOpen }}
            }
        }
    }

    // ── Split mode ────────────────────────────────────────────────────────────
    SplitPill {
        id: splitLeftPill
        barMode: root.barMode
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.topMargin:    root.splitMargin
        anchors.bottomMargin: root.splitMargin
        anchors.leftMargin:   root.splitMargin
        implicitWidth: Math.round(T.Theme.pillHeight * 1.6) * 2 + 6 + 16
        radius: root.splitRadius

        Row {
            anchors.centerIn: parent
            spacing: 6
            BarShape {
                id: splitShapeInner
                implicitWidth:  Math.round(T.Theme.pillHeight * 1.6)
                implicitHeight: T.Theme.pillHeight
                barShape: root.barShape
                onToggle: root.barShape = !root.barShape
            }
            BarMode {
                implicitWidth:  Math.round(T.Theme.pillHeight * 1.6)
                implicitHeight: T.Theme.pillHeight
                barMode: root.barMode; barShape: root.barShape
                onToggle: root.barMode = !root.barMode
            }
        }
    }

    // BGM pill
    SplitPill {
        id: splitBgmPill
        barMode: root.barMode
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: splitLeftPill.right
        anchors.topMargin:    root.splitMargin
        anchors.bottomMargin: root.splitMargin
        anchors.leftMargin:   root.splitMargin
        implicitWidth: bgmBtn.implicitWidth + 16
        radius: root.splitRadius

        BgmButton {
            id: bgmBtn
            anchors.centerIn: parent
            barShape: root.barShape
            bgmOpen:  Panels.bgmOpen
            onToggleBgm: { Panels.activeScreen = root.screen; Panels.bgmOpen = !Panels.bgmOpen }
        }
    }

    // Wallpaper + Brightness pill
    SplitPill {
        id: splitWallpaperPill
        barMode: root.barMode
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: splitBgmPill.right
        anchors.topMargin:    root.splitMargin
        anchors.bottomMargin: root.splitMargin
        anchors.leftMargin:   root.splitMargin
        implicitWidth: Math.round(T.Theme.pillHeight * 1.6) * 2 + 6 + 16
        radius: root.splitRadius

        Row {
            anchors.centerIn: parent
            spacing: 6
            WallpaperButton {
                id: splitWpInner
                implicitWidth:  Math.round(T.Theme.pillHeight * 1.6)
                implicitHeight: T.Theme.pillHeight
                barShape: root.barShape
                wallpaperOpen: Panels.wallpaperOpen
                onToggleWallpaper: { Panels.activeScreen = root.screen; Panels.wallpaperOpen = !Panels.wallpaperOpen }
            }
            BrightnessButton {
                implicitWidth:  Math.round(T.Theme.pillHeight * 1.6)
                implicitHeight: T.Theme.pillHeight
                barShape: root.barShape
                brightnessOpen: Panels.brightnessOpen
                onToggleBrightness: { Panels.activeScreen = root.screen; Panels.brightnessOpen = !Panels.brightnessOpen }
            }
        }
    }

    // Equalizer pill
    SplitPill {
        id: splitEqualizerPill
        barMode: root.barMode
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: splitWallpaperPill.right
        anchors.topMargin:    root.splitMargin
        anchors.bottomMargin: root.splitMargin
        anchors.leftMargin:   root.splitMargin
        implicitWidth: eqBtn.implicitWidth + 16
        radius: root.splitRadius

        EqualizerButton {
            id: eqBtn
            anchors.centerIn: parent
            barShape: root.barShape
            equalizerOpen: Panels.equalizerOpen
            onToggleEqualizer: { Panels.activeScreen = root.screen; Panels.equalizerOpen = !Panels.equalizerOpen }
        }
    }

    SplitPill {
        id: splitKeyboardPill
        barMode: root.barMode
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: splitCenterPill.left
        anchors.topMargin:    root.splitMargin
        anchors.bottomMargin: root.splitMargin
        anchors.rightMargin:  root.splitMargin
        implicitWidth: kbBtn.implicitWidth + 16
        radius: root.splitRadius

        KeyboardLayout {
            id: kbBtn
            anchors.centerIn: parent
            barShape: root.barShape
        }
    }

    SplitPill {
        id: splitCenterPill
        barMode: root.barMode
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin:    root.splitMargin
        anchors.bottomMargin: root.splitMargin
        implicitWidth: centerBtns.implicitWidth + 16
        radius: root.splitRadius

        RowLayout {
            id: centerBtns
            anchors.centerIn: parent
            spacing: 10
            UpdateButton { barShape: root.barShape; updatePanel: root.updatePanel }
            Workspaces   { barShape: root.barShape; monitor: Hyprland.monitors.values.find(m => m.name === root.screen.name) }
            ReloadButton { barShape: root.barShape }
        }
    }

    SplitPill {
        id: splitTrayPill
        barMode: root.barMode
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: splitCenterPill.right
        anchors.topMargin:    root.splitMargin
        anchors.bottomMargin: root.splitMargin
        anchors.leftMargin:   root.splitMargin
        implicitWidth: SystemTray.items.values.length * 26 + Math.max(0, SystemTray.items.values.length - 1) * 4 + 16
        radius: root.splitRadius
        visible: (opacity > 0.005 || !root.barMode) && SystemTray.items.values.length > 0

        Tray {
            anchors.centerIn: parent
            barShape: root.barShape
            parentWindow: root
        }
    }

    SplitPill {
        id: splitVizPill
        barMode: root.barMode
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: splitWifiPill.left
        anchors.topMargin:    root.splitMargin
        anchors.bottomMargin: root.splitMargin
        anchors.rightMargin:  root.splitMargin
        implicitWidth: vizComp.implicitWidth + 16
        radius: root.splitRadius

        AudioVisualizer {
            id: vizComp
            anchors.centerIn: parent
            barShape: root.barShape
        }
    }

    SplitPill {
        id: splitWifiPill
        barMode: root.barMode
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: splitRightPill.left
        anchors.topMargin:    root.splitMargin
        anchors.bottomMargin: root.splitMargin
        anchors.rightMargin:  root.splitMargin
        implicitWidth: wifiBtn.implicitWidth + 16
        radius: root.splitRadius

        WifiButton {
            id: wifiBtn
            anchors.centerIn: parent
            barShape: root.barShape
            wifiOpen: Panels.wifiOpen
            onToggleWifi: { Panels.activeScreen = root.screen; Panels.wifiOpen = !Panels.wifiOpen }
        }
    }

    SplitPill {
        id: splitRightPill
        barMode: root.barMode
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.topMargin:    root.splitMargin
        anchors.bottomMargin: root.splitMargin
        anchors.rightMargin:  root.splitMargin
        implicitWidth: rightBtns.implicitWidth + 16
        radius: root.splitRadius

        RowLayout {
            id: rightBtns
            anchors.centerIn: parent
            spacing: 8
            Clock { barShape: root.barShape; clockOpen: Panels.clockOpen; onToggleClock: { Panels.activeScreen = root.screen; Panels.clockOpen = !Panels.clockOpen }}
        }
    }

    Connections {
        target: root
        function onBarModeChanged() {
            if (root.barMode) {
                unifiedIn.restart()
                unifiedSlideIn.restart()
            } else {
                unifiedOut.restart()
                unifiedSlideOut.restart()
            }
        }
    }
}
