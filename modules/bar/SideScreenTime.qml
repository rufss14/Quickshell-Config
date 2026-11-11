import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── SideScreenTime ────────────────────────────────────────────────────────────
// Screen time (services/ScreenTime) as one sidebar cell: an hourglass, monochrome like
// every glyph on the edge; hovered, today's total in its place ("3.2h"). Dimmed while
// tracking is off.
//
//   click   the panel beside it (again: shut it)
//   right   Settings › Screen time
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool vertical: true
    property var screen: null

    readonly property bool ownsPanel: UiState.sidePanelScreen
        ? UiState.sidePanelScreen === root.screen : root.screen === Quickshell.screens[0]
    readonly property bool open: UiState.sidePanel === "screentime" && root.ownsPanel
    readonly property bool reading: cell.hovered && Config.screenTime

    // The glyph steps aside for the reading (SideCell doesn't ease its glyphScale).
    property real glyphS: root.reading ? 0 : 1
    Behavior on glyphS { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

    implicitWidth:  Config.sidebarCell
    implicitHeight: Config.sidebarCell

    SideCell {
        id: cell

        moduleId: "screentime"
        anchors.fill: parent
        glyph: "\u{F051F}"
        active: root.open
        tint: Config.screenTime ? Colors.of(QsWindow.window).stateIdleFg : Colors.of(QsWindow.window).fgDim
        glyphScale: root.glyphS
        onClicked:      UiState.toggleSidePanel("screentime", "screentime", root.screen)
        onRightClicked: UiState.openSettingsTo("ScreenTimePage.qml")
    }

    // Today, in the glyph's place.
    StyledText {
        anchors.centerIn: parent
        text: ScreenTime.short(ScreenTime.todayTotal)
        font.family: Tokens.fontMono
        font.weight: Font.Bold
        font.pixelSize: Math.round(Config.sidebarGlyphPx * 0.5)
        color: Colors.of(QsWindow.window).primary
        opacity: root.reading ? 1 : 0
        scale: root.reading ? 1 : 0.8
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
        Behavior on scale { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
    }
}
