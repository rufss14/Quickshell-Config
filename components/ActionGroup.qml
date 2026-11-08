import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"

// ── ActionGroup — a rounded tray of header buttons, bar-style ──────────────────
// Header controls read as one or two clusters instead of a loose row. The buttons
// inside are plain PanelButtons: `ghost` for actions, `primary` for a toggle that
// is currently ON (grid mode, debug mode, active view) — a filled accent IS the
// on/off indicator.
//
// Lived inline in WallpaperPanel first; the colours panel wanted the same tray, so
// it moved here rather than being copied. `groupShown` collapses the whole tray
// (and its border) when a sub-view has taken over the header.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property bool groupShown: true
    default property alias items: row.data

    Layout.alignment: Qt.AlignVCenter
    implicitWidth:  row.implicitWidth + 6
    implicitHeight: 34
    radius: Tokens.radiusSm
    color:  Colors.of(QsWindow.window).surfaceContainer
    border.width: Tokens.borderWidth
    border.color: Colors.of(QsWindow.window).outline
    visible: root.groupShown && row.implicitWidth > 1

    Row {
        id: row
        anchors.centerIn: parent
        height: 32
        spacing: 1
    }
}
