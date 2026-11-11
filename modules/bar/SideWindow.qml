import QtQuick
import QtQuick.Effects
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/sidemodules.js" as Side

// ── SideWindow ────────────────────────────────────────────────────────────────
// The focused-window module on the sidebar: the window's APP ICON with the app's NAME
// under it — one short line, across the cell, shrunk to fit and then elided — the way
// SideCell's `caption` sets a reading under a glyph. There is no room across the edge for
// a title; the title, the class, the window's state and what a click does are in the
// hover card (components/SideHover → modules/panels/HoverCard, kind "window"). A turned
// title was tried and read badly (2026-10-17). Click opens the window's actions beside
// it (WindowPanel — the bar's panel too). An empty workspace shows a dimmed desktop mark
// and "Desktop" rather than leaving a hole in the row.
//
// Since 2026-10-31 (the user's picks for a quieter sidebar) it is the icon ALONE, at the
// dock's size — the name is the hover card's — and it STEPS ASIDE (no length, the rail
// closes the gap) when the dock on this edge already draws the focused app, its mark saying
// which is in front, and on an empty workspace (sidemodules.js windowCells; arranging
// always shows it). So it only appears for something the edge doesn't already show.
//
// The icon is the app's own colours, unless the shell asks for silhouettes
// (Config.colorizeIcons, Settings › Appearance — the tray pill's and the dock's rule).
//
// ── Focus moving animates; a title changing does not ──────────────────────────
// WindowPill's rule (its comments say why): `shown` is the window the cell DRAWS, held
// back from `win` so the old one can finish fading out. Only a change of WINDOW swaps;
// a terminal rewriting its title every second changes nothing visible here at all.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool vertical: true
    property var screen: null

    readonly property bool ownsPanel: UiState.sidePanelScreen
        ? UiState.sidePanelScreen === root.screen : root.screen === Quickshell.screens[0]
    readonly property var win: ActiveWindow.byMonitor[root.screen ? root.screen.name : ""] ?? null
    readonly property bool open: UiState.sidePanel === "window" && root.ownsPanel

    // One cell, or none: it steps aside when the dock on this edge already shows the focused
    // app (its mark says which is in front) and on an empty workspace — sidemodules.js
    // windowCells, the rule SideRail lays the edge out by.
    readonly property int cells: Side.windowCells(root.win !== null,
        root.win !== null && Config.dockEnabled && Taskbar.onDock(root.win.key ?? ""), UiState.sidebarArrange)
    readonly property real run: Config.sidebarRun(root.cells)
    implicitWidth:  root.vertical ? Config.sidebarCell : root.run
    implicitHeight: root.vertical ? root.run : Config.sidebarCell
    visible: root.cells > 0

    readonly property string winKey: root.win ? (root.win.address ?? "") : ""
    property var shown: null
    Component.onCompleted: root.shown = root.win
    onWinChanged: if (root.winKey === (root.shown ? (root.shown.address ?? "") : "")) root.shown = root.win

    readonly property bool hasIcon: !!(root.shown && root.shown.icon)
    // The dock's icon size: the cell is an app icon alone now (2026-10-31: the name under it
    // went, the user's pick for a quieter sidebar — the hover card still names it).
    readonly property int iconPx: Config.sidebarIconPx
    readonly property color ink: feedback.hovered || root.open ? Config.moduleAccent("window", Colors.of(QsWindow.window).primary)
        : root.shown ? Colors.of(QsWindow.window).stateIdleFg : Colors.of(QsWindow.window).fgDim

    CellFeedback {
        id: feedback
        anchors.fill: parent
        hovered: mouse.containsMouse
        active: root.open
    }

    SwapFade {
        target:   content
        key:      root.winKey
        shownKey: root.shown ? (root.shown.address ?? "") : ""
        onSwapped: root.shown = root.win
    }

    Column {
        id: content
        anchors.centerIn: parent
        spacing: Tokens.spacingXs

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width:  root.iconPx
            height: root.iconPx

            Image {
                anchors.fill: parent
                visible: root.hasIcon
                source: root.hasIcon ? root.shown.icon : ""
                sourceSize: Qt.size(root.iconPx, root.iconPx)
                fillMode: Image.PreserveAspectFit
                smooth: true
                asynchronous: true
                // Under the pointer it lifts a little, on the plate's own spring (CellFeedback.lift).
                scale: feedback.lift
                // Colorized, the dock's tint (MonoIconEffect), so the two read as one set.
                layer.enabled: Config.colorizeIcons
                layer.smooth: true
                layer.effect: MonoIconEffect {}
            }
            MaterialIcon {
                anchors.centerIn: parent
                visible: !root.hasIcon
                name: root.shown ? "window" : "desktop_mac"
                fill: root.open ? 1 : 0
                weight: Config.sidebarGlyphWeight
                font.pixelSize: Config.sidebarGlyphPx
                color: root.ink
                Behavior on color { ColorAnimation { duration: Motion.respond } }
            }
        }

        // (The app's name under its icon was here; the hover card names it.)
    }

    SideHover {
        hovered: mouse.containsMouse
        from: "window"
        arg: "window"
        screen: root.screen
        // Its own panel, once opened, is the better card.
        enabled: !root.open
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onPressed: function (m) { feedback.press(m.x, m.y) }
        onReleased: feedback.release()
        onCanceled: feedback.release()
        onClicked: function (m) {
            if (m.button === Qt.RightButton) UiState.openSettingsTo("SidebarPage.qml")
            else                             UiState.toggleSidePanel("window", "window", root.screen)
        }
    }
}
