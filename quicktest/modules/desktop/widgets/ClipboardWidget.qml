pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── ClipboardWidget ───────────────────────────────────────────────────────────
// The last few things you copied, click to put one back. The desktop face of the
// Clipboard service — which is always recording anyway, so this tile costs nothing but
// the drawing.
Item {
    id: root
    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.primary

    readonly property int shown: root.size === "large" ? 8 : 4

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingXs

        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                text: "Clipboard"
                variant: "caption"
                font.bold: true
                color: Colors.fg
            }
            StyledText {
                text: Clipboard.count
                variant: "caption"
                emphasis: "dim"
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: Clipboard.count === 0
            text: "Nothing copied yet."
            variant: "caption"
            emphasis: "dim"
            verticalAlignment: Text.AlignVCenter
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: Clipboard.count > 0
            clip: true
            spacing: 1
            boundsBehavior: Flickable.StopAtBounds
            model: Clipboard.entries.slice(0, root.shown)

            delegate: Item {
                id: row
                required property var modelData
                width: ListView.view.width
                implicitHeight: 20

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Clipboard.copy(row.modelData)
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: Tokens.spacingSm

                    StyledText {
                        text: row.modelData.kind === "image" ? "󰋩" : "󰈚"
                        variant: "caption"
                        color: Clipboard.justCopied === row.modelData.hash
                               ? Colors.success : Colors.fgDim
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Clipboard.justCopied === row.modelData.hash
                              ? "Copied" : Clipboard.label(row.modelData)
                        variant: "caption"
                        font.family: Tokens.fontMono
                        color: Clipboard.justCopied === row.modelData.hash
                               ? Colors.success : Colors.fgMuted
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
