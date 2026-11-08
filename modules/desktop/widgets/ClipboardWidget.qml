pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── ClipboardWidget ───────────────────────────────────────────────────────────
// The last few things you copied, click to put one back. The desktop face of the
// Clipboard service — which is always recording anyway, so this tile costs nothing but
// the drawing.
//
// ── Material 3 Expressive (2026-10-30) ────────────────────────────────────────
// Each entry is a tonal row with its kind on a small shape (a squircle for a picture, a
// cookie for text), the newest on the accent's container so "what's on the clipboard
// now" is the first thing read. Copying one back flashes its row in the success tone.
Item {
    id: root

    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.of(QsWindow.window).primary

    readonly property int shown: root.opts.rows ?? (root.size === "large" ? 8 : 3)

    HoverHandler { id: tileHover }

    WidgetEmpty {
        visible: Clipboard.count === 0
        icon: "content_paste"
        text: Translation.tr("Nothing copied yet")
    }

    ColumnLayout {
        anchors.fill: parent
        visible: Clipboard.count > 0
        spacing: Tokens.spacingSm

        WidgetHeader {
            icon:   "content_paste"
            shape:  "pentagon"
            title:  Translation.tr("Clipboard")
            accent: root.accent
            TilePill { text: String(Clipboard.count) }
            TileChip {
                icon: "cleaning_services"
                awake: tileHover.hovered
                onActivated: Clipboard.wipe()
            }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Tokens.spacingXs
            boundsBehavior: Flickable.StopAtBounds
            model: Clipboard.entries.slice(0, root.shown)

            delegate: TileRow {
                id: row
                required property var modelData
                required property int index
                readonly property bool copied: Clipboard.justCopied === row.modelData.hash
                readonly property bool newest: row.index === 0
                width: ListView.view.width
                flash: row.copied
                    ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceContainer, Colors.of(QsWindow.window).success, 0.3)
                    : row.newest ? Colors.of(QsWindow.window).primaryContainer : "transparent"
                onTapped: Clipboard.copy(row.modelData)

                Item {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Tokens.iconMd + Tokens.spacingXs
                    implicitHeight: implicitWidth
                    MorphShape {
                        anchors.fill: parent
                        shape: Config.barShape || row.modelData.kind === "image" ? "squircle" : "cookie7"
                        fillColor: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.1)
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: row.copied ? "check" : row.modelData.kind === "image" ? "image" : "description"
                        font.pixelSize: Tokens.iconSm - 2
                        color: row.copied ? Colors.of(QsWindow.window).success
                             : row.newest ? Colors.of(QsWindow.window).fgOnPrimaryContainer
                             : Colors.of(QsWindow.window).fgMuted
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: row.copied ? "Copied" : Clipboard.label(row.modelData)
                    variant: "caption"
                    font.family: Tokens.fontMono
                    color: row.copied ? Colors.of(QsWindow.window).success
                         : row.newest ? Colors.of(QsWindow.window).fgOnPrimaryContainer
                         : Colors.of(QsWindow.window).fgMuted
                    elide: Text.ElideRight
                }
                MaterialIcon {
                    visible: row.hovered && !row.copied
                    name: "content_copy"
                    variant: "caption"
                    emphasis: "dim"
                }
            }
        }
    }
}
