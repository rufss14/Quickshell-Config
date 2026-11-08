import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"

// ── SettingRow ────────────────────────────────────────────────────────────────
// Label + detail on the left, one control on the right. The standard shape for a
// single settings line — a toggle, a button row — across every settings page.
//
// Promoted out of BarPage.qml, which declared it as a local `component` with a
// comment saying exactly this: "exists nowhere else in the shell yet. It moves out
// the moment a second page needs it." That moment already passed — WidgetsPage's
// settings column hand-rolls this same label+control row shape inline instead of
// sharing it — so this is that move, not a new abstraction.
// ─────────────────────────────────────────────────────────────────────────────
RowLayout {
    id: settingRow

    property string label:  ""
    property string detail: ""
    // The sentence that explains the row — a tip on its label (HelpTip). `detail`
    // is for a short state ("11 apps remembered"), not this.
    property string help:   ""

    // Let the detail run to a second line instead of eliding. Off by default —
    // a column of rows that each silently change height as their detail text
    // changes is a page that jitters, so wrapping is opt-in for the rows whose
    // detail is genuinely a sentence (an explanation of the option you just
    // picked) rather than a few words of metadata.
    property bool wrapDetail: false

    // ── Optional leading icon ─────────────────────────────────────────────────
    // Additive, same shape as PanelButton's symbol/symbolFill: unset (the default)
    // renders nothing, so every existing caller is unaffected. `symbolFill` and
    // `symbolColor` are left to the caller to bind to whatever state the row shows —
    // MaterialIcon's own Behavior on fill animates the on/off transition for free.
    property string symbol:      ""
    property real   symbolFill:  0
    property color  symbolColor: Colors.of(QsWindow.window).fgMuted
    Behavior on symbolColor { ColorAnimation { duration: Motion.fast } }

    default property alias control: controlSlot.data

    // No `property bool enabled` — RowLayout is an Item, which already has one,
    // and redeclaring it would shadow the property QML uses to gate input.
    Layout.fillWidth: true
    // Pinned here, once: a layout nested in a ColumnLayout defaults fillHeight to TRUE
    // and splits the column's surplus height (docs/settings-style.md §7).
    Layout.fillHeight: false
    // A floor, not a height: a row with a two-line detail is still allowed to be
    // taller. It exists because the label and its control were the same weight and
    // the same size with nothing between them, so a column of rows had no rhythm to
    // scan — the eye couldn't find where one row ended. Tall enough that a 32px
    // control sits in it with air on both sides.
    Layout.minimumHeight: 40
    spacing: Tokens.spacingMd

    MaterialIcon {
        visible: settingRow.symbol !== ""
        Layout.alignment: Qt.AlignVCenter
        name:  settingRow.symbol
        fill:  settingRow.symbolFill
        color: settingRow.symbolColor
        variant: "body"
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: 0

        HelpTip { id: rowTip; text: settingRow.help }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm

            StyledText {
                Layout.fillWidth: true
                Layout.maximumWidth: Math.ceil(implicitWidth)
                text:    settingRow.label
                variant: "body"
                // The label is the row's anchor and the detail is a footnote to it;
                // at the same weight they read as one run-on line.
                font.weight: Font.Medium
                elide:   Text.ElideRight
            }
            MaterialIcon {
                visible: settingRow.help !== ""
                name: "info"
                color: Colors.of(QsWindow.window).fgDim
                font.pixelSize: Tokens.iconSm
                opacity: rowTip.active ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            }
            Item { Layout.fillWidth: true }
        }
        StyledText {
            Layout.fillWidth: true
            visible:  settingRow.detail !== ""
            text:     settingRow.detail
            variant:  "caption"
            emphasis: "dim"
            wrapMode: settingRow.wrapDetail ? Text.WordWrap : Text.NoWrap
            elide:    settingRow.wrapDetail ? Text.ElideNone : Text.ElideRight
        }
    }

    Item {
        id: controlSlot
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth:  childrenRect.width
        Layout.preferredHeight: childrenRect.height
        // A Toggle/slider has no text of its own; a screen reader names it by this row's
        // label, unless the caller already gave it one.
        Component.onCompleted: {
            for (const c of controlSlot.children)
                if (c.accessibleName !== undefined && c.accessibleName === "")
                    c.accessibleName = Qt.binding(() => settingRow.label)
        }
    }
}
