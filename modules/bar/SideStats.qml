pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── SideStats ─────────────────────────────────────────────────────────────────
// The system stats as a sidebar button: a glance at rest — a level bar for each of
// its first three metrics (Config.sidebarStatsMetrics' order, what this machine can
// read), gliding the way the rings did — and the whole picture in a panel beside
// it (StatsPanel, in SidePanelDock). It replaced the stats pill, whose rings and
// hover cards are that panel now.
//
//   click     the panel, beside this button (again: shut it)
//   middle    the system monitor in a terminal (SysStats.openMonitor)
//   right     Settings › Sidebar › Stats
//
// The bars wear the cell's tint like a glyph does (SideCell): idle at rest, the
// accent under the pointer or while its panel is open. Never recoloured by value:
// an alert says so in the panel, not here (the rings' rule).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Along the edge: a column on a side, a row along the bottom (SideGroupHost).
    property bool vertical: true
    // The screen this sidebar is on: its panel opens here.
    property var screen: null
    // On screen: the sidebar is out and this isn't sunk under a panel.
    property bool shown: true

    readonly property var glance: SysStats.metrics.slice(0, 3)
    readonly property bool ownsPanel: UiState.sidePanelScreen
        ? UiState.sidePanelScreen === root.screen : root.screen === Quickshell.screens[0]
    readonly property bool open: UiState.sidePanel === "stats" && root.ownsPanel
    readonly property bool hovered: mouse.containsMouse
    readonly property color tint: root.hovered || root.open ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).stateIdleFg

    // Sampling while it's on screen; the peripherals' once-a-minute poll even while
    // auto-hidden (StatsSampler says why).
    StatsSampler {
        metrics: Config.sidebarStatsMetrics
        active: root.shown
        devicesActive: !UiState.sidebarHidden
    }

    implicitWidth:  Config.sidebarCell
    implicitHeight: Config.sidebarCell

    CellFeedback {
        id: feedback
        anchors.fill: parent
        hovered: root.hovered
        active: root.open
    }

    // ── The glance ────────────────────────────────────────────────────────────
    // A glyph's box: three bars rising from its floor, each on a faint track.
    readonly property int barW: Math.max(Tokens.borderWidth * 2, Math.round(Config.sidebarGlyphPx / 5))
    Row {
        anchors.centerIn: parent
        height: Config.sidebarGlyphPx
        spacing: Math.max(Tokens.borderWidth, Math.round((Config.sidebarGlyphPx - root.barW * 3) / 2))
        visible: root.glance.length > 0

        Repeater {
            model: root.glance
            delegate: Item {
                id: bar
                required property string modelData
                readonly property real level: Math.max(0, Math.min(1, SysStats.readout(bar.modelData).ratio))
                width: root.barW
                height: parent.height

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Colors.of(QsWindow.window).alpha(root.tint, 0.18)
                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                }
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    // Never thinner than round: an idle metric is a dot, not nothing.
                    height: Math.max(parent.width, parent.height * bar.shown)
                    radius: width / 2
                    color: root.tint
                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                }
                // Eased the way the rings are (Motion.glide): at a one-second
                // sample it rests a moment each second rather than never.
                property real shown: bar.level
                Behavior on shown { NumberAnimation { duration: Motion.glide; easing.type: Motion.glideCurve } }
            }
        }
    }
    // Nothing it can read: the part's glyph, so the button still says what it is.
    MaterialIcon {
        anchors.centerIn: parent
        visible: root.glance.length === 0
        glyph: "\u{F0EE0}"                                                   // 󰻠 cpu-64-bit
        font.pixelSize: Config.sidebarGlyphPx
        color: root.tint
    }

    SideHover {
        hovered: mouse.containsMouse
        from:    "stats"
        arg:     "stats"
        screen:  root.screen
        enabled: !root.open
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onPressed: function (m) { feedback.press(m.x, m.y) }
        onReleased: feedback.release()
        onCanceled: feedback.release()
        onClicked: function (m) {
            if (m.button === Qt.RightButton)       UiState.openSettingsTo("SidebarStatsPage.qml")
            else if (m.button === Qt.MiddleButton) SysStats.openMonitor()
            else                                   UiState.toggleSidePanel("stats", "stats", root.screen)
        }
    }
}
