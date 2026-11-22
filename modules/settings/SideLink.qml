pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"

// ── SideLink ──────────────────────────────────────────────────────────────────
// One line of Bar & sidebar › Style's "Sidebar" group: whether the SIDEBAR follows one of the bar's
// knobs. The switch is on while it does (the default) and the sidebar wears the bar's value live. Off, the
// sidebar's own control (this item's children) opens under the row, starting from the bar's value, so
// unlinking changes nothing until you move it.
//
// The row stands alone in its group rather than hanging under each bar slider: the link is a property of the
// sidebar, and a grouped card gives every row its own segment. One set of knobs for both surfaces with a
// per-knob escape hatch; the values live in Config.sidebarStyle (surfaces.js STYLE_KEYS).
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root

    // A surfaces.js STYLE_KEYS key.
    required property string key
    // What the sidebar starts from when unlinked: the bar's current value.
    required property var barValue
    // The knob's name, as the row says it.
    property string label: ""
    // The sentence that explains the knob, as a tip on the row.
    property string help: ""

    default property alias content: own.data

    readonly property bool linked: { void Config.sidebarStyle; return Config.sideLinked(root.key) }

    function flip() {
        if (root.linked) Config.setSideStyle(root.key, root.barValue)
        else             Config.linkSideStyle(root.key)
    }

    Layout.fillWidth: true
    Layout.fillHeight: false
    spacing: Tokens.spacingMd

    SettingRow {
        rowTap: true
        label:  root.label
        detail: root.linked ? Translation.tr("Same as the bar") : Translation.tr("Its own")
        help:   root.help
        onTapped: root.flip()

        Toggle {
            accent: Colors.of(QsWindow.window).primary
            accessibleName: Translation.tr("%1 follows the bar").arg(root.label)
            checked: root.linked
            onToggled: root.flip()
        }
    }

    // The sidebar's own control, only while unlinked.
    ColumnLayout {
        id: own
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: !root.linked
        spacing: Tokens.spacingXs
    }
}
