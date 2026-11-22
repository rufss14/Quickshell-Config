import QtQuick
import Quickshell
import "../../config"
import "../../components"

// ── IslandTile ────────────────────────────────────────────────────────────────
// A card you press, on an island page: a shape holding a symbol over a label (and a second line).
// `on` puts it on the accent container and turns the shape into a cookie; `danger` tints the symbol.
// It is an IslandPlate, so it arrives in the page's cascade (`order`) and wears the plate's state
// layer. A disabled one dims and says why on hover (`help`).
// ─────────────────────────────────────────────────────────────────────────────
IslandPlate {
    id: root

    property string symbol: ""
    property string label: ""
    property string sub: ""
    property string help: ""
    property bool   on: false
    property bool   danger: false
    // Side by side (a wide tile in a list) instead of stacked (a square one in a grid).
    property bool   row: false

    hero: root.on
    clickable: root.enabled
    opacity: root.enabled ? 1 : 0.45

    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.description: root.sub
    Accessible.onPressAction: if (root.enabled) root.clicked()

    HelpTip { text: root.help }

    Grid {
        anchors.centerIn: root.row ? undefined : parent
        anchors.left: root.row ? parent.left : undefined
        anchors.leftMargin: Tokens.spacingMd
        anchors.verticalCenter: root.row ? parent.verticalCenter : undefined
        columns: root.row ? 2 : 1
        spacing: root.row ? Tokens.spacingMd : Tokens.spacingXs
        horizontalItemAlignment: root.row ? Grid.AlignLeft : Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter

        IslandBadge {
            size: Tokens.iconXl + Tokens.spacingSm
            shape: root.on ? "cookie7" : "circle"
            filled: root.on
            symbol: root.symbol
            solid: root.on
        }
        Column {
            width: root.row ? root.width - Tokens.iconXl - Tokens.spacingSm - Tokens.spacingMd * 3
                            : root.width - Tokens.spacingSm * 2
            spacing: 0
            StyledText {
                width: parent.width
                text: root.label
                variant: "label"
                font.weight: Font.DemiBold
                color: root.danger && !root.on ? root.palette.danger : root.ink
                horizontalAlignment: root.row ? Text.AlignLeft : Text.AlignHCenter
                elide: Text.ElideRight
            }
            StyledText {
                width: parent.width
                visible: root.sub !== ""
                text: root.sub
                variant: "caption"
                color: root.inkDim
                horizontalAlignment: root.row ? Text.AlignLeft : Text.AlignHCenter
                elide: Text.ElideRight
            }
        }
    }
}
