import QtQuick
import QtQuick.Layouts
import Quickshell
import "../config"
import "../services"
import "../services/deskmenu.js" as Menus

// ── PickOrderList ─────────────────────────────────────────────────────────────
// A list you pick from and put in order, for the settings that are "which of these, and in what
// sequence" (the hot corner's sections, the desktop menu's places). Tap a row to show it or drop it;
// the arrows move a shown row. The shown ones come first, in their order; the rest follow, dimmed.
// It edits nothing itself: `picked(list)` carries the new list for the caller to store.
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root

    // id → { label, symbol, detail? }
    property var table: ({})
    // Every id, in the order Settings lists them.
    property var allIds: []
    // The ids that are on, in their order.
    property var shown: []
    property int max: 99

    signal picked(var list)

    readonly property var _on: Menus.known(root.shown, root.table)
    readonly property var rows: root._on.concat(root.allIds.filter(id => root._on.indexOf(id) < 0))

    spacing: Tokens.spacingXs

    Repeater {
        model: root.rows
        delegate: PanelRow {
            id: row
            required property string modelData
            readonly property bool on: root._on.indexOf(row.modelData) >= 0
            readonly property int at: root._on.indexOf(row.modelData)
            Layout.fillWidth: true
            symbol: root.table[row.modelData].symbol
            title: Translation.tr(root.table[row.modelData].label)
            subtitle: root.table[row.modelData].detail ? Translation.tr(root.table[row.modelData].detail) : ""
            // Quiet rows: a list of six chosen things is not six loud cards (one filled accent per
            // region). A chosen row says so with its mark and its arrows; the rest are dimmed.
            active: false
            opacity: row.on ? 1 : 0.6
            clickable: true
            onActivated: root.picked(Menus.flip(root._on, row.modelData, root.max))

            MaterialIcon {
                Layout.alignment: Qt.AlignVCenter
                name: row.on ? "check_circle" : "radio_button_unchecked"
                fill: row.on ? 1 : 0
                font.pixelSize: Tokens.iconMd
                color: row.on ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgDim
            }

            ChipButton {
                visible: row.on
                enabled: row.at > 0
                symbol: "keyboard_arrow_up"
                Accessible.name: Translation.tr("Move up")
                onActivated: root.picked(Menus.move(root._on, row.modelData, -1))
            }
            ChipButton {
                visible: row.on
                enabled: row.at < root._on.length - 1
                symbol: "keyboard_arrow_down"
                Accessible.name: Translation.tr("Move down")
                onActivated: root.picked(Menus.move(root._on, row.modelData, 1))
            }
        }
    }
}
