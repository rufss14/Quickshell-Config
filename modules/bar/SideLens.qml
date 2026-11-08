import QtQuick
import Quickshell
import "../../config"
import "../../services"
import "../../state"

// ── SideLens ──────────────────────────────────────────────────────────────────
// The lens (services/Lens) as one sidebar cell: drag out a region and its text is
// read and boxed over a frozen copy of it (LensOverlay) — copy it, search it, or
// translate it in place.
//
//   click   read a region
//   middle  read a region and translate it at once
//   right   Settings › Sidebar
//
// While it works the glyph breathes (a busy indicator — not switched off with
// animations, Motion's category 3); while the overlay is up the cell is lit.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool vertical: true

    implicitWidth:  Config.sidebarCell
    implicitHeight: Config.sidebarCell

    property real breath: 1
    SequentialAnimation on breath {
        running: Lens.busy
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { to: 1.18; duration: Motion.slow; easing.type: Motion.glideCurve }
        NumberAnimation { to: 1;    duration: Motion.slow; easing.type: Motion.glideCurve }
    }

    SideCell {
        anchors.fill: parent
        glyph: Lens.mode === "translate" && Lens.busy ? "\u{F05CA}"     // 󰗊 translate
             :                                          "\u{F113D}"     // 󱄽 text-recognition
        active: Lens.open || Lens.busy
        tint: Lens.blocker() !== "" ? Colors.of(QsWindow.window).fgDim : Colors.of(QsWindow.window).stateIdleFg
        glyphScale: root.breath
        onClicked:       Lens.start("text")
        onMiddleClicked: Lens.start("translate")
        onRightClicked:  UiState.openSettingsTo("SidebarPage.qml")
    }
}
