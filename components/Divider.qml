import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"

// ── Divider ───────────────────────────────────────────────────────────────────
// A hairline between sections. Every panel declared its own, all at
// `alpha(fg, 0.07)` — the same line, six times over.
//
// `orientation` because a vertical hairline is the SAME hairline, and the settings
// rail wanting one is not a reason for a second component that then has to be kept
// at the same alpha by hand. Horizontal by default — that's every existing use, and
// the Layout hints only bind in a layout anyway (the anchored uses ignore them).
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property int orientation: Qt.Horizontal

    readonly property bool _vertical: root.orientation === Qt.Vertical

    Layout.fillWidth:  !root._vertical
    Layout.fillHeight:  root._vertical
    implicitWidth:  root._vertical ? 1 : 0
    implicitHeight: root._vertical ? 0 : 1

    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.09)
}
