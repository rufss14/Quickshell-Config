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

    Component.onCompleted: KeyLocks.acquire()
    Component.onDestruction: KeyLocks.release()

    SideCell {
        anchors.fill: parent
        glyph: KeyLocks.caps || KeyLocks.num ? "\u{F0A9B}" : "\u{F030C}"   // 󰪛 caps lock / 󰌌 keyboard
        tint: KeyLocks.submap !== "" ? Colors.of(QsWindow.window).warning
            : KeyLocks.any ? Colors.of(QsWindow.window).primary
            : Colors.of(QsWindow.window).stateIdleFg
        active: KeyLocks.any
        onRightClicked: UiState.openSettingsTo("SidebarPage.qml")
    }
}
