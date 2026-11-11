import QtQuick
import QtQuick.Effects
import Quickshell
import "../../config"
import "../../services"
import "../../state"

// ── ArrangeBackdrop ───────────────────────────────────────────────────────────
// What arranging does to the screen, as the desktop widgets do it (WidgetLayer): the desktop dims and the snap
// dots fade in, so the bar and the sidebar are the thing to look at. Fills Bar.qml's window under everything
// it draws. Draws nothing and takes no input at rest: the dots are only built while it is up or fading.
//
// The Settings window is where arranging is driven from, so it is left out of the dim: a hole in the shade the
// size of its Hyprland geometry (the bar's window sits at its monitor's origin, so monitor-local is this item's own
// coordinates), with a primary edge round it as the widgets' tiles wear theirs. Docked, Settings is drawn by this
// window above the dim and needs none of that.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool shown: false
    property var monitor: null

    opacity: root.shown ? 1 : 0
    visible: opacity > 0.005
    Behavior on opacity { NumberAnimation { duration: Motion.standard } }

    readonly property var settingsWin: root.visible
        ? Hypr.windows.find(w => w.appClass === "org.quickshell" && w.title === Translation.tr("Settings")
                                 && w.monitorId === (root.monitor?.id ?? -2)) ?? null
        : null
    readonly property rect hole: root.settingsWin
        ? Qt.rect(root.settingsWin.at[0] - (root.monitor?.x ?? 0), root.settingsWin.at[1] - (root.monitor?.y ?? 0),
                  root.settingsWin.size[0], root.settingsWin.size[1])
        : Qt.rect(0, 0, 0, 0)
    readonly property bool cut: root.hole.width > 0

    // The shade, with the Settings window cut out of it.
    Rectangle {
        anchors.fill: parent
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.45)
        layer.enabled: root.cut
        layer.effect: MultiEffect {
            maskEnabled: true
            maskInverted: true
            maskSource: holeMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        // Dots, not lines: they mark exactly the points a tile's corner can land on.
        Loader {
            anchors.fill: parent
            active: root.visible
            sourceComponent: Canvas {
                id: grid
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.fillStyle = Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.22)
                    const g = Config.widgetGrid
                    for (let x = 0; x < width; x += g)
                        for (let y = 0; y < height; y += g)
                            ctx.fillRect(x, y, 1, 1)
                }
                // Static: it repaints only when the grid or the size changes.
                Component.onCompleted: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                Connections {
                    target: Config
                    function onWidgetGridChanged() { grid.requestPaint() }
                }
            }
        }
    }
    Item {
        id: holeMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle {
            x: root.hole.x
            y: root.hole.y
            width: root.hole.width
            height: root.hole.height
            radius: Tokens.radiusCard
            color: "white"
        }
    }
    // The window's edge, lit.
    Rectangle {
        visible: root.cut
        x: root.hole.x
        y: root.hole.y
        width: root.hole.width
        height: root.hole.height
        radius: Tokens.radiusCard
        color: "transparent"
        border.width: Tokens.borderWidth * 2
        border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.55)
    }
}
