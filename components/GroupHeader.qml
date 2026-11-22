import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"

// ── GroupHeader ─────────────────────────────────────────────────────────
// A heading between the groups of the colour scheme page's Presets view (the wallpaper's own colours, yours,
// the classics): a small accent badge, the group's name in capitals, and how many are showing in a pill. It is as
// wide as the Flow it sits in, which is what puts the next card on a new row. A foldable one folds its group away
// when pressed (`folded` is the caller's).
// ─────────────────────────────────────────────────────────────────────────────
RowLayout {
    id: root

    property string symbol: ""
    property string title:  ""
    property int    count:  -1
    // A group that can be folded away: the whole heading is the button, its chevron turns.
    property bool   foldable: false
    property bool   folded:   false
    signal toggled()

    readonly property var palette: Colors.of(QsWindow.window)

    implicitHeight: Tokens.iconLg + Tokens.spacingSm
    spacing: Tokens.spacingSm

    MaterialIcon {
        Layout.alignment: Qt.AlignVCenter
        name: root.symbol
        fill: 1
        color: root.palette.primary
        font.pixelSize: Tokens.iconMd
    }
    StyledText {
        Layout.alignment: Qt.AlignVCenter
        text: root.title.toUpperCase()
        variant: "caption"
        font.weight: Font.Bold
        font.letterSpacing: 1
        color: root.palette.fgMuted
    }
    Rectangle {
        visible: root.count >= 0
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: countText.implicitWidth + Tokens.spacingMd * 2
        implicitHeight: countText.implicitHeight + Tokens.spacingXs
        radius: height / 2
        color: root.palette.section
        StyledText {
            id: countText
            anchors.centerIn: parent
            text: String(root.count)
            variant: "micro"
            font.weight: Font.DemiBold
            font.features: ({ tnum: 1 })
            color: root.palette.fgMuted
        }
    }
    Item { Layout.fillWidth: true }
    MaterialIcon {
        visible: root.foldable
        Layout.alignment: Qt.AlignVCenter
        name: "keyboard_arrow_down"
        font.pixelSize: Tokens.iconLg
        color: root.palette.fgMuted
        rotation: -90 * foldK.value
        SpringValue { id: foldK; target: root.folded ? 1 : 0; spec: Motion.springSpatialFast; epsilon: 0.002 }
    }

    HoverHandler { id: hover; enabled: root.foldable; cursorShape: Qt.PointingHandCursor }
    TapHandler { enabled: root.foldable; onTapped: root.toggled() }
    opacity: root.foldable && hover.hovered ? 1 : 0.9
    Accessible.role: Accessible.Button
    Accessible.name: root.title
    Accessible.onPressAction: if (root.foldable) root.toggled()
}
