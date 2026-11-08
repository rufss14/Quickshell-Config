import QtQuick
import Quickshell
import "../config"

// ── IconLine ──────────────────────────────────────────────────────────────────
// One fact with its icon, then its text. Every fact in the sidebar's panels has an
// icon (the stats' rule), so this is the one shape they share — StatsPanel,
// ClipsPanel, ClipsPeek, and the clip editor.
// ─────────────────────────────────────────────────────────────────────────────
Row {
    id: line
    property string glyph: ""
    property string text: ""
    property bool warn: false     // the alert line: both in the danger role
    property bool dim: false      // a section label or a hint, not a fact
    spacing: Tokens.spacingSm
    MaterialIcon {
        anchors.verticalCenter: parent.verticalCenter
        glyph: line.glyph
        color: line.warn ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).focus
        opacity: line.dim ? 0.7 : 1
        variant: "label"
    }
    StyledText {
        anchors.verticalCenter: parent.verticalCenter
        text: line.text
        variant: "caption"
        color: line.warn ? Colors.of(QsWindow.window).danger : line.dim ? Colors.of(QsWindow.window).fgMuted : Colors.of(QsWindow.window).fg
    }
}
