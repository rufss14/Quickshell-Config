import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../"

// ── TabletPlateTitle ──────────────────────────────────────────────────────────
// The title row of a plate on the Tablet page: a small badge that blooms into a shape of its own, a name, and
// one line of what is true now. The wallpaper page's material plates open the same way.
// ─────────────────────────────────────────────────────────────────────────────
RowLayout {
    id: root

    property string symbol: ""
    property string shape: "cookie9"
    property string title: ""
    property string note: ""
    property color ink: Colors.of(QsWindow.window).fg
    property color inkDim: Colors.of(QsWindow.window).fgMuted

    Layout.fillWidth: true
    Layout.fillHeight: false
    spacing: Tokens.spacingMd

    IslandBadge {
        size: Tokens.iconXl + Tokens.spacingSm
        symbol: root.symbol
        shape: root.shape
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        StyledText {
            Layout.fillWidth: true
            text: root.title
            variant: "label"
            font.weight: Font.DemiBold
            color: root.ink
            elide: Text.ElideRight
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.note !== ""
            text: root.note
            variant: "caption"
            color: root.inkDim
            elide: Text.ElideRight
        }
    }
}
