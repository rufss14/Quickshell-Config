import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../../../state"
import "../../island"

// ── QuickFrame ────────────────────────────────────────────────────────────────
// The shape every pill quick card shares, in the islands' dialect (docs/island-style.md): a bento of
// two flat plates on the bar's own material. The HERO is the one loud plate on `primaryContainer`: a
// morphing badge for the module, its name and what it is doing now, and `trailing` for its main switch.
// Under it a section plate holds the controls (`content`), the hero's cascade a beat before it. Plates
// are concentric with the card (its radius less the inset), no outlines, no shadows.
//
// Width is fixed so a card is the same size whichever pill it hangs from; height follows the content.
// ─────────────────────────────────────────────────────────────────────────────
Column {
    id: root

    property string symbol: ""
    property string shape: "cookie9"
    property string title: ""
    property string value: ""
    // Hero, right side: a ChipButton or two.
    property alias trailing: trail.data
    // The controls plate.
    default property alias content: body.data
    // False for a card whose body is empty in some state (nothing paired): the plate goes with it.
    property bool bodyVisible: true

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property int inset: Tokens.spacingMd
    readonly property int plateRadius: Math.max(Tokens.radiusSm, Tokens.radiusCard - root.inset)
    readonly property int cardWidth: 300

    width: root.cardWidth
    spacing: Tokens.spacingSm

    // A card's way to the full panel, on the screen this bar is on.
    function openPanel(name) {
        UiState.activeScreen = QsWindow.window?.screen ?? UiState.activeScreen
        UiState.openPanel(name)
    }

    IslandPlate {
        id: hero
        hero: true
        order: 0
        width: parent.width
        radius: root.plateRadius
        implicitHeight: heroRow.implicitHeight + root.inset * 2

        RowLayout {
            id: heroRow
            anchors { fill: parent; margins: root.inset }
            spacing: Tokens.spacingMd

            Item {
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
            Column {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    width: parent.width
                    text: root.title
                    variant: "label"
                    font.weight: Font.DemiBold
                    color: hero.ink
                    elide: Text.ElideRight
                }
                StyledText {
                    width: parent.width
                    visible: root.value !== ""
                    text: root.value
                    variant: "caption"
                    color: hero.inkDim
                    elide: Text.ElideRight
                }
            }
            Row {
                id: trail
                spacing: Tokens.spacingSm
            }
        }
    }

    IslandPlate {
        order: 1
        visible: root.bodyVisible
        width: parent.width
        radius: root.plateRadius
        implicitHeight: body.implicitHeight + root.inset * 2

        Column {
            id: body
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: root.inset }
            spacing: Tokens.spacingSm
        }
    }
}
