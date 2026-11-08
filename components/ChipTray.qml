import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"

// ── ChipTray ──────────────────────────────────────────────────────────────────
// A pill of solid container fill holding a row of ChipButtons — a panel header's actions as
// one object with presence, in the same language as SegmentSwitch (a full pill, springs,
// filled on-states). The media panel's header uses it; ActionGroup (a quiet rounded-rectangle
// tray of PanelButtons) is still what every other panel's header wears, and is not touched.
//
// `groupShown` collapses it when a sub-view takes the header over, as ActionGroup's does, and
// it collapses on its own when every chip inside is hidden — an empty pill would be a dot.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property bool groupShown: true
    default property alias items: row.data

    Layout.alignment: Qt.AlignVCenter
    readonly property int pad: Tokens.spacingXs + 1
    implicitWidth:  row.implicitWidth + root.pad * 2
    implicitHeight: Tokens.iconXl + Tokens.spacingMd
    radius: height / 2
    color:  Colors.of(QsWindow.window).surfaceContainer
    border.width: Tokens.borderWidth
    border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
    visible: root.groupShown && row.implicitWidth > 1

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Tokens.spacingXs
    }
}
