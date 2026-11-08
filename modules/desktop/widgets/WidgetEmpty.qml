import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"

// ── WidgetEmpty ───────────────────────────────────────────────────────────────
// The "nothing to show yet" / "set me up in Settings" face. Nine widgets each
// drew their own — some centred, some pinned to the top, some with a glyph and
// some a bare line of grey text — so an unconfigured desktop read as nine
// different kinds of broken. One centred glyph-over-caption, everywhere.
//
// Fills its parent and centres itself, so the caller is just:
//   WidgetEmpty { visible: !ready; glyph: "󰖐"; text: "Set a location…" }
// ─────────────────────────────────────────────────────────────────────────────
// The glyph rests on a soft cookie (surfaceHigh): the same shape vocabulary as the
// tiles' heroes, one tone quieter, so an empty tile still looks like part of the set.
Item {
    id: root

    property string glyph: ""
    property string icon: ""
    property string text: ""

    anchors.fill: parent

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.max(0, parent.width - Tokens.spacingXl * 2)
        spacing: Tokens.spacingSm

        Item {
            visible: root.glyph !== "" || root.icon !== ""
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: Tokens.iconXl * 2
            implicitHeight: implicitWidth
            MorphShape {
                anchors.fill: parent
                shape: Config.barShape ? "squircle" : "cookie9"
                fillColor: Colors.of(QsWindow.window).surfaceHigh
            }
            MaterialIcon {
                anchors.centerIn: parent
                name: root.icon
                glyph: root.glyph
                font.pixelSize: Tokens.iconXl
                color: Colors.of(QsWindow.window).fgDim
            }
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.text
            variant: "caption"
            emphasis: "dim"
            wrapMode: Text.WordWrap
        }
    }
}
