import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"

// ── MixerPlate ────────────────────────────────────────────────────────────────
// A plate of the mixer's pages, as the wallpaper page's Material plates are: a flat `section` tone with a title
// row (a small shape badge, a title, a note), and what belongs to it under that. Children go into the plate's
// column. A `foldable` plate folds its body away when its title row is pressed (a critically damped height, a
// chevron that turns), so a long page can be read at a glance.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property string symbol: ""
    property string title: ""
    property string note: ""
    property string shape: "cookie9"
    property bool foldable: false
    property bool folded: false
    // Whatever stands at the right of the title row (a count, a button).
    default property alias content: body.data
    property alias trailing: trail.data
    signal toggled()

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property real pad: Tokens.spacingLg

    radius: Tokens.radiusXl
    color: root.palette.section
    implicitHeight: col.implicitHeight + root.pad * 2

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: root.pad
        spacing: Tokens.spacingMd

        RowLayout {
            id: head
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd

            Item {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Tokens.iconXl
                Layout.preferredHeight: Tokens.iconXl
                MorphShape {
                    anchors.fill: parent
                    shape: root.shape
                    fillColor: root.palette.primary
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    name: root.symbol
                    fill: 1
                    font.pixelSize: Tokens.iconMd
                    color: root.palette.fgOnPrimary
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    variant: "label"
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.note !== ""
                    text: root.note
                    variant: "micro"
                    color: root.palette.fgMuted
                    elide: Text.ElideRight
                }
            }
            Row {
                id: trail
                Layout.alignment: Qt.AlignVCenter
                spacing: Tokens.spacingSm
            }
            MaterialIcon {
                visible: root.foldable
                Layout.alignment: Qt.AlignVCenter
                name: "keyboard_arrow_down"
                font.pixelSize: Tokens.iconLg
                color: root.palette.fgMuted
                rotation: -90 * (1 - foldK.value)
            }

            HoverHandler { id: headHover; enabled: root.foldable; cursorShape: Qt.PointingHandCursor }
            TapHandler { enabled: root.foldable; onTapped: root.toggled() }
            Accessible.role: Accessible.Button
            Accessible.name: root.title
            Accessible.onPressAction: if (root.foldable) root.toggled()
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: foldK.value * body.implicitHeight
            visible: foldK.value > 0.005
            clip: foldK.value < 0.995
            SpringValue { id: foldK; target: root.folded ? 0 : 1; spec: Motion.springSpatial; epsilon: 0.002 }

            ColumnLayout {
                id: body
                width: parent.width
                spacing: Tokens.spacingMd
                opacity: foldK.value
            }
        }
    }
}
