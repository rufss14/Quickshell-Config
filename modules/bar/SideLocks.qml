import QtQuick
import Quickshell
import "../../config"
import "../../services"
import "../../state"

// ── SideLocks ─────────────────────────────────────────────────────────────────
// Submap / Caps / Num on the sidebar: a cell can't hide like a bar pill (the rail sizes
// it), so it stays and LIGHTS — the keyboard mark dim at rest, Caps Lock's arrow in the
// accent while a lock is on, the warning tint while a submap is active.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool vertical: true

    implicitWidth:  Config.sidebarCell
    implicitHeight: Config.sidebarCell

    readonly property var parts: {
        const p = []
        if (KeyLocks.submap !== "") p.push(KeyLocks.submap.toUpperCase())
        if (KeyLocks.caps) p.push("CAPS")
        if (KeyLocks.num)  p.push("NUM")
        return p
    }

    Component.onCompleted: KeyLocks.acquire()
    Component.onDestruction: KeyLocks.release()

    SideCell {

        moduleId: "locks"
        anchors.fill: parent
        // The bar pill's words (LocksPill: "RESIZE · CAPS"), turned: the first on the
        // cell, the next under it. Nothing on: a keyboard mark, where the bar hides the
        // pill (a cell keeps its slot in the rail).
        glyph: "\u{F030C}"                                               // 󰌌 keyboard
        label: root.parts.length > 0 ? root.parts[0] : ""
        caption: root.parts.length > 1 ? root.parts.slice(1).join(" · ") : ""
        tint: KeyLocks.submap !== "" ? Colors.of(QsWindow.window).warning
            : KeyLocks.any ? Colors.of(QsWindow.window).primary
            : Colors.of(QsWindow.window).stateIdleFg
        active: KeyLocks.any
        onRightClicked: UiState.openSettingsTo("SidebarPage.qml")
    }
}
