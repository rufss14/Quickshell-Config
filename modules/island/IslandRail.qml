pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/island.js" as Rules

// ── IslandRail ────────────────────────────────────────────────────────────────
// The card's page switch, down its left side: Material 3's navigation rail, made expressive. ONE filled indicator
// travels between the pages on two springs, its leading edge fast and its trailing edge slower, so it stretches into a
// capsule on the way and gathers back on arrival, where it MORPHS into that page's own shape (Rules.TABS[].shape: a
// cookie for the Dashboard, a clover for Media, a burst for Performance, a sunburst for Weather) and the icon on it
// fills. No names on show (no tips either, the user's call): the page itself says where you are; screen readers get the name. Under the pages, the pin.
//
// All three of the bar's islands wear it; `metaOf` names and draws a page (the middle island's own, or a panel's
// from config/islands.js).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Page ids in the order shown, and the one on show.
    property var    pages: []
    property string current: ""
    property bool   pinned: false
    // A page's { label, icon, shape } by id; null = the middle island's own pages.
    property var    metaOf: null

    signal picked(string value)
    signal pinToggled()
    // The settings window wears this rail too: it has nothing to pin, and its eight groups are named on hover.
    property bool pinnable: true
    property bool tips: false

    readonly property var palette: Colors.of(QsWindow.window)
    // A page's slot at its full size, and the one it gets: a rail with more pages than its height holds squeezes
    // them (down to the icon) so the last never runs under the pin.
    readonly property int slotFull: Tokens.iconXl + Tokens.spacingXl
    readonly property int slot: root.single ? root.slotFull
        : Math.max(Tokens.iconLg + Tokens.spacingXs, Math.min(root.slotFull,
            Math.floor((root.height - root.pad * 2 - (root.pinnable ? foot.height : 0) - root.gap) / root.pages.length) - root.gap))
    readonly property int inset: root.pad + (root.slotFull - root.slot) / 2
    readonly property int pad: Tokens.spacingSm
    readonly property int gap: Tokens.spacingXs
    readonly property int index: Math.max(0, root.pages.indexOf(root.current))
    readonly property bool single: root.pages.length < 2
    function slotY(i) { return root.pad + i * (root.slot + root.gap) }
    function _meta(v) { return root.metaOf ? root.metaOf(v) : Rules.tabMeta(v) }

    implicitWidth: root.slotFull + root.pad * 2

    // The rail's own ground: a flat tonal column, the cards' tone.
    Rectangle {
        anchors.fill: parent
        radius: Tokens.radiusCard
        color: root.palette.section
    }

    // ── The indicator ─────────────────────────────────────────────────────────
    // Two springs on the same target: the fast one leads, the slow one trails, and the shape spans both.
    SpringValue { id: lead;  target: root.slotY(root.index); spec: Motion.springSpatialFast; epsilon: 0.2 }
    SpringValue { id: trail; target: root.slotY(root.index); spec: Motion.springSpatial;     epsilon: 0.2 }

    MorphShape {
        id: indicator
        visible: !root.single
        x: root.inset
        y: Math.min(lead.value, trail.value)
        width: root.slot
        height: root.slot + Math.abs(lead.value - trail.value)
        // A capsule while it travels (a circle stretched), the page's shape once it is there.
        shape: Math.abs(lead.value - trail.value) > root.slot * 0.15 ? "circle" : root._meta(root.current).shape
        spec: Motion.springSpatialFast
        fillColor: root.palette.primary
    }

    // ── The pages ─────────────────────────────────────────────────────────────
    Repeater {
        model: root.single ? [] : root.pages
        delegate: Item {
            id: item
            required property string modelData
            required property int index
            readonly property bool on: item.index === root.index
            readonly property var meta: root._meta(item.modelData)

            x: root.inset
            y: root.slotY(item.index)
            width: root.slot
            height: root.slot

            Accessible.role: Accessible.RadioButton
            Accessible.name: Translation.tr(item.meta.label)
            Accessible.checkable: true
            Accessible.checked: item.on
            Accessible.onPressAction: root.picked(item.modelData)

            // The hover wash, on a page that is not the one on show.
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: root.palette.alpha(root.palette.fg, Tokens.stateHover)
                opacity: !item.on && hover.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
            }
            MaterialIcon {
                anchors.centerIn: parent
                name: item.meta.icon
                fill: item.on ? 1 : 0
                font.pixelSize: Tokens.iconLg
                color: item.on ? root.palette.fgOnPrimary : hover.hovered ? root.palette.fg : root.palette.fgMuted
                // A squeezed slot has no room for the lift.
                scale: item.on && root.slot === root.slotFull ? 1.08 : 1
                Behavior on fill  { NumberAnimation { duration: Motion.standard } }
                Behavior on color { ColorAnimation  { duration: Motion.standard } }
                Behavior on scale { NumberAnimation { duration: Motion.standard; easing.type: Motion.overshoot } }
            }

            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.picked(item.modelData) }
            HoverTip { text: root.tips ? Translation.tr(item.meta.label) : "" }
        }
    }

    // ── Pin and close ─────────────────────────────────────────────────────────
    Column {
        id: foot
        visible: root.pinnable
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.pad
        spacing: root.gap

        ChipButton {
            anchors.horizontalCenter: parent.horizontalCenter
            symbol: root.pinned ? "lock" : "lock_open"
            on: root.pinned
            Accessible.name: root.pinned ? Translation.tr("Unpin") : Translation.tr("Keep open")
            onActivated: root.pinToggled()
            HoverTip { text: root.pinned ? Translation.tr("Unpin") : Translation.tr("Keep open") }
        }
    }
}
