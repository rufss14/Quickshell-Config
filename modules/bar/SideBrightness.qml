import QtQuick
import Quickshell
import "../../config"
import "../../services"
import "../../state"

// ── SideBrightness ────────────────────────────────────────────────────────────
// The brightness module on the sidebar: scroll dims the monitor this sidebar is on,
// click opens every display's slider beside it (BrightnessPanel — the bar's panel too).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool vertical: true
    property var screen: null

    readonly property bool ownsPanel: UiState.sidePanelScreen
        ? UiState.sidePanelScreen === root.screen : root.screen === Quickshell.screens[0]

    implicitWidth:  Config.sidebarCell
    implicitHeight: Config.sidebarCell

    Component.onCompleted: Brightness.ensureProbed()

    function index() {
        const name = root.screen ? root.screen.name : ""
        for (let i = 0; i < Brightness.monitors.count; i++)
            if (Brightness.monitors.get(i).port === name) return i
        return -1
    }

    SideCell {
        anchors.fill: parent
        glyph: "\u{F00DF}"                                               // 󰃟 brightness
        active: UiState.sidePanel === "brightness" && root.ownsPanel
        wheel: true
        onScrolled: function (d) {
            const i = root.index()
            if (i < 0) return
            const m = Brightness.monitors.get(i)
            Brightness.requestBrightness(i, Brightness.clampFor(m.type, m.brightness + d * 5))
        }
        onClicked:      UiState.toggleSidePanel("brightness", "brightness", root.screen)
        onRightClicked: UiState.openSettingsTo("SidebarPage.qml")
    }
}
