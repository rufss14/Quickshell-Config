pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../components"
import "../../state"

// ── SideTools ─────────────────────────────────────────────────────────────────
// Shell tools, a click away: the app launcher and the keybind cheatsheet — things
// that were a keybind (or, the cheatsheet, only an IPC call) and nothing else.
// Each cell lights while what it opens is open, the top bar's `active`. They open
// on this sidebar's screen. Right-click: the sidebar's settings.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Along the edge: a column on a side, a row along the bottom (SideGroupHost).
    property bool vertical: true
    // The screen this sidebar is on, so what a cell opens opens here.
    property var screen: null

    // Config's `cells` for "tools" is this list's length (SideRail.cellsFor).
    readonly property var tools: [
        { key: "launcher",   glyph: "\u{F003B}" },                     // 󰀻 apps
        { key: "cheatsheet", glyph: "\u{F030C}" }                      // 󰌌 keyboard
    ]

    function isOpen(key) {
        return key === "launcher" ? UiState.launcherOpen
             : key === "cheatsheet" ? UiState.cheatsheetOpen
             : false
    }

    // The launcher as the dock's own button opens it: over whatever else was up,
    // on this screen, and a second click puts it away.
    function open(key) {
        UiState.overviewOpen = false
        if (key === "launcher") {
            if (UiState.launcherOpen) { UiState.launcherOpen = false; return }
            UiState.activeScreen = root.screen
            UiState.launcherOpen = true
        } else if (key === "cheatsheet") {
            UiState.toggleCheatsheet()
        }
    }

    implicitWidth:  root.vertical ? Config.sidebarCell : Config.sidebarRun(root.tools.length)
    implicitHeight: root.vertical ? Config.sidebarRun(root.tools.length) : Config.sidebarCell

    Grid {
        columns: root.vertical ? 1 : root.tools.length
        spacing: Config.sidebarCellGap

        Repeater {
            model: root.tools

            SideCell {
                id: tool
                required property var modelData

                glyph:  tool.modelData.glyph
                active: root.isOpen(tool.modelData.key)

                onClicked: root.open(tool.modelData.key)
                onRightClicked: UiState.openSettingsTo("SidebarPage.qml")
            }
        }
    }
}
