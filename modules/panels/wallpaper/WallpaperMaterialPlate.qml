import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"

// One card of the Material page: a lifted tonal plate with a small shape for a badge, a title, and an
// optional note at the right; what goes inside it goes under the title, in a column. It stands on the
// island's section plate, so it is the next tone up (the gallery's canvases are the same one).
Rectangle {
    id: root

    property string title:  ""
    property string symbol: ""
    property string shape:  "cookie9"
    // A short line at the right of the title (how many looks, which part is chosen).
    property string note:   ""

    default property alias content: body.data

    readonly property var palette: Colors.of(QsWindow.window)

    Layout.fillWidth: true
    Layout.fillHeight: false
    implicitHeight: col.implicitHeight + Tokens.spacingMd * 2
    radius: Tokens.radiusCard
    color: root.palette.plate

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: Tokens.spacingMd
        spacing: Tokens.spacingSm

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm

            Item {
                Layout.preferredWidth: Tokens.iconXl - Tokens.spacingSm
                Layout.preferredHeight: Tokens.iconXl - Tokens.spacingSm
                MorphShape {
                    anchors.fill: parent
                    shape: root.shape
                    fillColor: root.palette.primaryContainer
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    name: root.symbol
                    fill: 1
                    font.pixelSize: Tokens.iconSm
                    color: root.palette.fgOnPrimaryContainer
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: root.title
                variant: "label"
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            StyledText {
                visible: root.note !== ""
                text: root.note
                variant: "caption"
                emphasis: "dim"
            }
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm
        }
    }
}
