import Quickshell
import Quickshell.Wayland
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Layouts
import "../theming" as T
import "../config"
import "pages"

// ── SettingsWindow ──────────────────────────────────────────────────────────
// The "Windows Settings, but beautiful" app. Implemented as a Wayland OVERLAY
// layer (not a tiled toplevel) so it floats ABOVE the current apps on a dim
// scrim and never pushes/tiles/splits them — closing returns to what was there.
// One instance per screen; only the instance on Settings.activeScreen (the
// monitor whose bar button was clicked) is shown, so it appears where you are.
//
// A left navigation rail grouped into labeled SECTIONS routes a content area.
// Add a page = one entry in `allPages` (id/title/glyph/section/component).
// ──────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: win
    required property var modelData
    screen: modelData
    readonly property string screenName: modelData ? modelData.name : ""

    // Only the initiating monitor shows the overlay (no duplication, no double
    // scanning — the content Loader below is gated on this too).
    readonly property bool active: Settings.shown && Settings.activeScreen === win.screenName
    visible: active

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-settings"
    WlrLayershell.keyboardFocus: active ? (Settings.grabKeys ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand)
                                        : WlrKeyboardFocus.None

    // A battery is present only on a laptop — used to hide the Battery page on
    // desktops so it "turns off" cleanly there.
    readonly property bool hasBattery: UPower.displayDevice && UPower.displayDevice.isLaptopBattery

    // The bar's current cross-axis thickness, so an anchored panel clears the bar.
    readonly property int barThick: {
        var horiz = Config.barEdge === "top" || Config.barEdge === "bottom"
        var thick = Config.barThickness !== "thin"
        return horiz ? (thick ? T.Theme.barThickness  : T.Theme.barThicknessThin)
                     : (thick ? T.Theme.barThicknessV : T.Theme.barThicknessVThin)
    }

    // ── Page registry (grouped into sections) ────────────────────────────────────
    readonly property var sections: ["Network", "Sound & Power", "Personalization", "System"]
    readonly property var allPages: [
        { id: "wifi",      title: "Wi-Fi",     glyph: 0xF05A9, section: "Network",         comp: wifiComp,    hidden: false },
        { id: "bluetooth", title: "Bluetooth", glyph: 0xF00AF, section: "Network",         comp: btComp,      hidden: false },
        { id: "sound",     title: "Sound",     glyph: 0xF057E, section: "Sound & Power",   comp: soundComp,   hidden: false },
        { id: "battery",   title: "Battery",   glyph: 0xF0079, section: "Sound & Power",   comp: batteryComp, hidden: !hasBattery },
        { id: "wallpaper", title: "Appearance", glyph: 0xF1904, section: "Personalization", comp: appearanceComp, hidden: false },
        { id: "customization", title: "Panels & Bar", glyph: 0xF0210, section: "Personalization", comp: customComp, hidden: false },
        { id: "updates",   title: "Updates",   glyph: 0xF06B0, section: "System",          comp: updatesComp, hidden: false },
        { id: "language",  title: "Language & Region", glyph: 0xF05CA, section: "System",  comp: langComp,    hidden: false },
        { id: "keyboard",  title: "Keyboard",  glyph: 0xF030C, section: "System",          comp: keyboardComp, hidden: false },
        { id: "keybinds",  title: "Keybinds",  glyph: 0xF030C, section: "System",          comp: keybindsComp, hidden: false },
        { id: "plugins",   title: "Plugins",   glyph: 0xF0431, section: "System",          comp: pluginsComp, hidden: false },
        { id: "about",     title: "About",     glyph: 0xF02FC, section: "System",          comp: aboutComp,   hidden: false },
    ]
    readonly property var pages: allPages.filter(function(p){ return !p.hidden })
    function pagesIn(section) { return pages.filter(function(p){ return p.section === section }) }
    function pageComp(id) {
        for (var i = 0; i < pages.length; i++) if (pages[i].id === id) return pages[i].comp
        return pages.length ? pages[0].comp : null
    }

    // ── Dim scrim (click to dismiss) ─────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.5
        MouseArea { anchors.fill: parent; onClicked: Settings.close() }
    }
    // Escape closes.
    Item {
        anchors.fill: parent
        focus: win.active
        Keys.onEscapePressed: Settings.close()
    }

    // ── Floating panel ───────────────────────────────────────────────────────────
    // Centered by default; when opened from an anchored source (the gear module)
    // it biases toward that screen side and aligns with the icon along the edge,
    // so it feels like it opens "out of" the icon. Still floats on the overlay —
    // never tiled. `Behavior`s ease it into place.
    Rectangle {
        id: panel
        width: Math.min(960, win.width - 80)
        height: Math.min(660, win.height - 80)

        // Where to place the panel. "center" forces dead-centre regardless of what
        // the opener asked for; "anchored" honours the opener's edge/pos so the
        // window opens "out of" the button/result that launched it.
        readonly property string ae: Config.settingsPlacement === "center" ? "" : Settings.anchorEdge
        readonly property int m: 16          // gap from the non-bar screen edges
        readonly property int be: win.barThick + 14   // gap from the bar's own edge

        // Dragging: once the user drags the header, `moved` takes over and x/y
        // follow px/py (see the header MouseArea below). Reset to the anchored
        // position each time the window is (re)opened.
        property bool moved: false
        property real px: 0
        property real py: 0
        Connections { target: Settings; function onShownChanged() { if (Settings.shown) panel.moved = false } }

        x: {
            if (panel.moved) return panel.px
            if (ae === "left")  return be
            if (ae === "right") return win.width - width - be
            if (ae === "top" || ae === "bottom")
                return Math.max(m, Math.min(Settings.anchorPos * win.width - width / 2, win.width - width - m))
            return (win.width - width) / 2
        }
        y: {
            if (panel.moved) return panel.py
            if (ae === "top")    return be
            if (ae === "bottom") return win.height - height - be
            if (ae === "left" || ae === "right")
                return Math.max(m, Math.min(Settings.anchorPos * win.height - height / 2, win.height - height - m))
            return (win.height - height) / 2
        }
        // No easing while dragging (instant follow); ease only the anchored moves.
        Behavior on x { enabled: !panel.moved; NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutCubic } }
        Behavior on y { enabled: !panel.moved; NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutCubic } }

        radius: T.Theme.radiusLarge
        color: T.Theme.background
        border.width: 1
        border.color: T.Theme.border
        clip: true

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ── Navigation rail (grouped) ─────────────────────────────────────────
            Rectangle {
                Layout.preferredWidth: 250
                Layout.fillHeight: true
                color: T.Theme.surface

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 14
                    contentHeight: navCol.implicitHeight
                    clip: true

                    ColumnLayout {
                        id: navCol
                        width: parent.width
                        spacing: 4

                        Text {
                            Layout.fillWidth: true
                            Layout.bottomMargin: 10
                            text: "Settings"
                            color: T.Theme.ink
                            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 7; bold: true }
                        }

                        Repeater {
                            model: win.sections
                            delegate: ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.topMargin: 8
                                spacing: 3

                                // Section header.
                                Text {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: 4
                                    text: modelData.toUpperCase()
                                    color: T.Theme.inkDim
                                    font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 4; bold: true; letterSpacing: 1 }
                                }

                                Repeater {
                                    model: win.pagesIn(modelData)
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool sel: Settings.page === modelData.id
                                        Layout.fillWidth: true
                                        implicitHeight: 38
                                        radius: T.Theme.moduleRadius
                                        color: sel ? T.Theme.surfaceActive
                                             : navMa.containsMouse ? T.Theme.surfaceHover
                                             : "transparent"
                                        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12; anchors.rightMargin: 12
                                            spacing: 12
                                            Text {
                                                text: String.fromCodePoint(modelData.glyph)
                                                color: sel ? T.Theme.accent : T.Theme.inkDim
                                                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 2 }
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.title
                                                color: sel ? T.Theme.ink : T.Theme.inkDim
                                                elide: Text.ElideRight
                                                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize; bold: sel }
                                            }
                                        }
                                        MouseArea {
                                            id: navMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Settings.page = modelData.id
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: T.Theme.border }

            // ── Content ───────────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: T.Theme.background

                // Close button (top-right).
                Rectangle {
                    anchors.top: parent.top; anchors.right: parent.right
                    anchors.topMargin: 14; anchors.rightMargin: 14
                    implicitWidth: 30; implicitHeight: 30; radius: T.Theme.radiusFull
                    z: 2
                    color: closeMa.containsMouse ? T.Theme.surfaceHover : T.Theme.surfaceAlt
                    Text { anchors.centerIn: parent; text: String.fromCodePoint(0xF0156); color: T.Theme.ink; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize + 1 } }
                    MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Settings.close() }
                }

                Loader {
                    anchors.fill: parent
                    anchors.margins: 26
                    // Only instantiate the page while THIS overlay is up — stops
                    // network/bluetooth scanning when closed or on the other monitor.
                    active: win.active
                    sourceComponent: win.pageComp(Settings.page)
                }
            }
        }

        // ── Drag handle (nav-rail header) ─────────────────────────────────────
        // Drag the "Settings" header (top of the nav rail) to reposition the
        // panel. Scoped to the nav header so page content stays fully interactive.
        // z above the rail so it catches drags; a subtle grip hints it's movable.
        MouseArea {
            id: dragHandle
            anchors { top: parent.top; left: parent.left }
            width: 250
            height: 52
            z: 5
            cursorShape: Qt.SizeAllCursor
            property real sx: 0
            property real sy: 0
            property real spx: 0
            property real spy: 0
            onPressed: function(m) {
                if (!panel.moved) { panel.px = panel.x; panel.py = panel.y; panel.moved = true }
                var p = mapToItem(null, m.x, m.y)
                dragHandle.sx = p.x; dragHandle.sy = p.y
                dragHandle.spx = panel.px; dragHandle.spy = panel.py
            }
            onPositionChanged: function(m) {
                if (!pressed) return
                var p = mapToItem(null, m.x, m.y)
                panel.px = Math.max(0, Math.min(win.width  - panel.width,  dragHandle.spx + (p.x - dragHandle.sx)))
                panel.py = Math.max(0, Math.min(win.height - panel.height, dragHandle.spy + (p.y - dragHandle.sy)))
            }

            // Grip affordance (top-centre).
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 6
                width: 42; height: 4
                radius: T.Theme.radiusFull
                color: T.Theme.inkDim
                opacity: 0.5
            }
        }
    }

    Component { id: customComp;    CustomizationPage {} }
    Component { id: appearanceComp; AppearancePage {} }
    Component { id: wifiComp;      WifiPage {} }
    Component { id: btComp;        BluetoothPage {} }
    Component { id: soundComp;     SoundPage {} }
    Component { id: batteryComp;   BatteryPage {} }
    Component { id: langComp;      LanguagePage {} }
    Component { id: keyboardComp;  KeyboardPage {} }
    Component { id: updatesComp;   UpdatesPage {} }
    Component { id: pluginsComp;   PluginsPage {} }
    Component { id: keybindsComp;  KeybindsPage {} }
    Component { id: aboutComp;     AboutPage {} }
}
