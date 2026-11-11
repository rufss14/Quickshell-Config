pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"

// ── SideLink ──────────────────────────────────────────────────────────────────
// Under one of Bar & sidebar › Style's knobs: whether the SIDEBAR follows it. Linked (the
// default), a quiet chip says so and the sidebar wears the bar's value live. Unlinked, the
// chip lights and the sidebar's own control (this item's children) appears beneath it,
// starting from the bar's value, so unlinking changes nothing until you move it.
//
// One set of knobs for both surfaces with a per-knob escape hatch was the user's pick
// (2026-11-08); the values live in Config.sidebarStyle (surfaces.js STYLE_KEYS).
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root

    // A surfaces.js STYLE_KEYS key.
    required property string key
    // What the sidebar starts from when unlinked: the bar's current value.
    required property var barValue

    default property alias content: own.data

    readonly property bool linked: { void Config.sidebarStyle; return Config.sideLinked(root.key) }

    Layout.fillWidth: true
    Layout.fillHeight: false
    spacing: Tokens.spacingXs

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Item { Layout.fillWidth: true }
        ChipButton {
            symbol: root.linked ? "link" : "link_off"
            label:  root.linked ? Translation.tr("Sidebar: same as bar") : Translation.tr("Sidebar: its own")
            on:     !root.linked
            tint:   Colors.of(QsWindow.window).primary
            onActivated: {
                if (root.linked) Config.setSideStyle(root.key, root.barValue)
                else             Config.linkSideStyle(root.key)
            }
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
