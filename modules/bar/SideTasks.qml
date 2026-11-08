pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── SideTasks ─────────────────────────────────────────────────────────────────
// The to-do list as a sidebar button, its list in a panel beside it (TasksPanel, in
// SidePanelDock). A checklist glyph at rest; while anything is open, a wavy ring round it
// filling as tasks get done — done of all, the timer's ring (2026-10-31, the user's pick:
// "richer glances"; it was a count badge, which the hover chip now says).
//
//   click     the panel, beside this button (again: shut it)
//   right     Settings › Sidebar
//
// All of it is services/Tasks; this only looks.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Along the edge: a column on a side, a row along the bottom (SideGroupHost).
    property bool vertical: true
    // The screen this sidebar is on: its panel opens here.
    property var screen: null

    readonly property bool ownsPanel: UiState.sidePanelScreen
        ? UiState.sidePanelScreen === root.screen : root.screen === Quickshell.screens[0]
    readonly property bool open: UiState.sidePanel === "tasks" && root.ownsPanel

    implicitWidth:  Config.sidebarCell
    implicitHeight: Config.sidebarCell

    readonly property bool ringed: Tasks.openCount > 0
    readonly property int total: Tasks.openCount + Tasks.doneCount
    // The ring is SideTimer's: the cell less the plate's gap, a glyph half its size inside.
    readonly property real ringSize: Config.sidebarCell - Tokens.spacingXs * 2
    property real glyphFit: root.ringed ? Math.round(root.ringSize / 2) / Config.sidebarGlyphPx : 1
    Behavior on glyphFit { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

    SideCell {
        anchors.fill: parent
        glyph: "\u{F0139}"                                                  // 󰄹 checklist
        active: root.open
        hoverKind: "tasks"
        glyphScale: root.glyphFit
        onClicked:      UiState.toggleSidePanel("tasks", "tasks", root.screen)
        onRightClicked: UiState.openSettingsTo("SidebarPage.qml")
    }

    RadialGauge {
        anchors.centerIn: parent
        width:  root.ringSize
        height: width
        thickness: Math.max(Tokens.spacingXs, Math.round(width / 11))
        wavy: true
        glide: true
        accent: Colors.of(QsWindow.window).focus
        value: root.total > 0 ? Tasks.doneCount / root.total : 0
        opacity: root.ringed ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
    }
}
