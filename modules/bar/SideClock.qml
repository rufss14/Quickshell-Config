import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── SideClock ─────────────────────────────────────────────────────────────────
// The bar's clock (widgets/ClockPill), turned onto the sidebar: the same face — the
// time with seconds, the date, the temperature once a location is set — stacked for a
// narrow edge (hours over minutes, then the seconds, then the short date). It was a
// generic cell, a clock glyph over a tiny "14:23", and moving the clock between the
// surfaces made it look like a different module (the user, 2026-11-08: "same face on
// both"). Along a bottom edge it reads as the bar's: "14:23:05" over the date.
// Two cells long on a side (config/modules.js). Click: the clock panel beside it.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool vertical: true
    property var screen: null
    property string moduleId: "clock"

    readonly property bool ownsPanel: UiState.sidePanelScreen
        ? UiState.sidePanelScreen === root.screen : root.screen === Quickshell.screens[0]
    readonly property bool open: UiState.sidePanel === "clock" && root.ownsPanel
    readonly property bool hero: Config.moduleHero("clock")
    readonly property date now: Clock.now
    readonly property color ink: root.hero ? Colors.of(QsWindow.window).fgOnPrimaryContainer
                                           : Config.moduleAccent("clock", Colors.of(QsWindow.window).primary)
    readonly property color sub: root.hero ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fgOnPrimaryContainer, 0.78)
                                           : Colors.of(QsWindow.window).fgMuted

    implicitWidth:  root.vertical ? Config.sidebarCell : Config.sidebarRun(2)
    implicitHeight: root.vertical ? Config.sidebarRun(2) : Config.sidebarCell

    // Seconds and the weather, refcounted, as ClockPill holds them.
    Component.onCompleted:   { Clock.acquireSeconds(); Weather.acquire() }
    Component.onDestruction: { Clock.releaseSeconds(); Weather.release() }

    CellFeedback {
        id: feedback
        anchors.fill: parent
        hovered: mouse.containsMouse
        active: root.open
        pointerX: mouse.mouseX
        pointerY: mouse.mouseY
    }

    // On a side: stacked.
    Column {
        anchors.centerIn: parent
        visible: root.vertical
        spacing: 0
        BarLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(root.now, "HH")
            sizeScale: Config.sideFontScale
            font.weight: Font.DemiBold
            color: root.ink
        }
        BarLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(root.now, "mm")
            sizeScale: Config.sideFontScale
            font.weight: Font.DemiBold
            color: root.ink
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(root.now, "ss")
            variant: "micro"
            sizeScale: Config.sideFontScale
            font.features: ({ tnum: 1 })
            color: root.sub
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: Tokens.spacingXs
            text: Qt.formatDateTime(root.now, "ddd d")
            variant: "micro"
            sizeScale: Config.sideFontScale
            color: root.sub
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: Weather.ready && Weather.hasLocation
            text: Weather.temp(Weather.tempC) + Weather.unit
            variant: "micro"
            sizeScale: Config.sideFontScale
            color: root.sub
        }
    }

    // Along the bottom: the bar's own two lines.
    Column {
        anchors.centerIn: parent
        visible: !root.vertical
        spacing: 0
        BarLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(root.now, "HH:mm:ss")
            sizeScale: Config.sideFontScale
            color: root.ink
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(root.now, "ddd, MMM d")
                  + (Weather.ready && Weather.hasLocation ? "  " + Weather.temp(Weather.tempC) + Weather.unit : "")
            variant: "micro"
            sizeScale: Config.sideFontScale
            color: root.sub
        }
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
            else UiState.toggleSidePanel("clock", root.moduleId, root.screen)
        }
    }
}
