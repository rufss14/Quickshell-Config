import QtQuick
import Quickshell
import "../../config"
import "../../components"

// ── OverviewHints ─────────────────────────────────────────────────────────────
// The keys that do something RIGHT NOW, as keycaps and one word each, in the workspaces' footer.
// `mode` follows the overview's state:
//
//   idle    nothing picked, nothing typed
//   switch  Alt+Tab is being held
//   search  there is a query
//   pick    a window is picked (the inspector's keys, with Ctrl held)
//   marks   a selection (Ctrl+click / Ctrl+A)
//
// The row clips at its own width rather than reflowing: what does not fit is the last, least important hint.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string mode: "idle"
    implicitHeight: row.implicitHeight
    clip: true

    readonly property var sets: ({
        idle:   [["Right-click", "inspect"], ["Ctrl+click", "select"], ["Shift", "all ten"]],
        switch: [["Tab", "next"], ["Let go of Alt", "go"], ["Esc", "stay"]],
        search: [["Enter", "go"], ["Tab", "next"], ["Esc", "clear"]],
        pick:   [["Ctrl+F", "float"], ["Ctrl+P", "pin"], ["Ctrl+1–0", "send"], ["Ctrl+W", "close"]],
        marks:  [["Drag", "move all"], ["Ctrl+F", "float"], ["Esc", "clear"]]
    })
    // Held, so a change of mode swaps through a fade instead of a cut (SwapFade's rhythm, kept simple).
    property var shown: root.sets.idle
    property string shownMode: "idle"
    onModeChanged: swap.restart()
    SequentialAnimation {
        id: swap
        NumberAnimation { target: row; property: "opacity"; to: 0; duration: Motion.fast }
        ScriptAction { script: { root.shown = root.sets[root.mode] ?? root.sets.idle; root.shownMode = root.mode } }
        NumberAnimation { target: row; property: "opacity"; to: 1; duration: Motion.standard }
    }

    Row {
        id: row
        // Against the footer's right edge.
        x: Math.max(0, root.width - row.width)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.spacingMd

        Repeater {
            model: root.shown
            Row {
                id: hint
                required property var modelData
                spacing: Tokens.spacingXs
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: cap.implicitWidth + Tokens.spacingSm * 2
                    height: cap.implicitHeight + Tokens.spacingXs
                    radius: Tokens.radiusXs
                    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
                    border.width: Tokens.borderWidth
                    border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.16)
                    StyledText {
                        id: cap
                        anchors.centerIn: parent
                        text: hint.modelData[0]
                        variant: "caption"
                        font.weight: Font.DemiBold
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: hint.modelData[1]
                    variant: "caption"
                    emphasis: "muted"
                }
            }
        }
    }
}
