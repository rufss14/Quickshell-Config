import QtQuick
import Quickshell
import "../config"

// ── ArrangeHint ───────────────────────────────────────────────────────────────
// What arrange mode says, in the room beside the thing being arranged (the bar's band under it,
// the sidebar's room beside it). A Material 3 Expressive card: a hero badge and the title, then one
// tonal tile per gesture (move, group, take off), each with its own shape on a disc.
//
// Mid-drag the same card answers the gesture: the title becomes the live line `description` names (the
// exact placement under the pointer), the badge morphs into the shape of what is about to happen, and
// the tile for that gesture lifts on a spring and takes the primary container — or a danger tint for
// the take-off. `mode` is the caller's reading of the drop target: "move" | "group" | "off" | "".
//
// Welded (`fused`) the card melts out of the surface it stands on (`edge`: "top" under the bar, "left" /
// "right" / "bottom" off the sidebar) as a lobe of the blob: its box grows from that face and the host hands
// `blob*` to BlobBarLayer, whose fill is the card's own. Unwelded it is a floating popup card. The caller
// gives the resting corner (`restX`, `restY`); `vertical` stacks the tiles (a narrow room beside a sidebar),
// and `maxWidth` is then the card's width and the lines wrap inside it. Horizontally it is as wide as its lines.
// ─────────────────────────────────────────────────────────────────────────────
Surface {
    id: root

    property bool vertical: false
    property bool dragging: false
    // What the pointer would do right now: "move" | "group" | "off", "" for none.
    property string mode: ""
    property string title: ""
    // The line under the title at rest; mid-drag the title's place is the live line and this one names the mode.
    property string subtitle: ""
    // [{ mode: "move", symbol: "swap_vert", title: "Move", detail: "Drag along the sidebar" }, …]
    property var steps: []
    // The live line while a drag is in the air (BarDrag.description / SideDrag.description).
    property string description: ""
    property real maxWidth: 10000

    // ── Where, and how it arrives ─────────────────────────────────────────────
    property bool fused: false
    property string edge: "top"
    property real restX: 0
    property real restY: 0
    property matrix4x4 deformMatrix
    property bool open: false
    Component.onCompleted: root.open = true
    property real grow: root.open ? 1 : 0
    Behavior on grow {
        NumberAnimation {
            duration: Motion.surfaceDuration(root.open)
            easing.bezierCurve: Motion.emphasizedDecel
            easing.type: root.open ? Easing.BezierSpline : Motion.exitCurve
        }
    }
    readonly property real g: root.fused ? root.grow : 1
    readonly property bool alongX: root.edge === "left" || root.edge === "right"
    // The box the host gives the blob, in this item's parent's coordinates; zero unless fused and out.
    readonly property bool lobe: root.fused && root.grow > 0.01
    readonly property real blobX: root.lobe ? root.x : 0
    readonly property real blobY: root.lobe ? root.y : 0
    readonly property real blobW: root.lobe ? root.width : 0
    readonly property real blobH: root.lobe ? root.height : 0

    // The shape each gesture wears while it is the one in the hand.
    readonly property var shapes: ({ move: "sunny", group: "clover", off: "burst" })
    readonly property bool over: root.dragging && root.mode === "off"
    readonly property var pal: Colors.of(QsWindow.window)
    readonly property int pad: Tokens.spacingLg
    // A tile's badge, and the header's bigger one.
    readonly property int badge: Tokens.iconXl + Tokens.spacingSm
    readonly property int heroBadge: Tokens.iconXl + Tokens.spacingXl
    // Side by side every gesture's text is one width, so the tiles are alike; stacked it fills the card.
    readonly property real flatText: 124
    readonly property real headText: 232
    readonly property real innerW: root.maxWidth - root.pad * 2
    readonly property var current: root.dragging ? root.steps.find(s => s.mode === root.mode) ?? null : null
    // The tiles sit one pad inside the card, so their corner is the card's less that gap: concentric.
    readonly property int tileRadius: Math.max(Tokens.radiusSm, Tokens.radiusXl - root.pad)

    elevation:    Tokens.elevationPopup
    cornerRadius: Tokens.radiusXl
    focused:      false
    color:        root.fused ? root.pal.frameFill : root.pal.surface
    borderColor:  root.over ? root.pal.danger : root.pal.outlineFor(Tokens.elevationPopup)
    borderWidth:  root.fused ? 0 : Tokens.borderWidth
    castsShadow:  !root.fused
    clip:         root.fused
    transform:    Matrix4x4 { matrix: root.deformMatrix }
    opacity:      root.fused ? 1 : root.grow
    visible:      root.grow > 0.01

    width:  root.alongX ? root.implicitWidth * root.g : root.implicitWidth
    height: root.alongX ? root.implicitHeight : root.implicitHeight * root.g
    x: root.edge === "right"  ? root.restX + root.implicitWidth * (1 - root.g)  : root.restX
    y: root.edge === "bottom" ? root.restY + root.implicitHeight * (1 - root.g) : root.restY

    implicitWidth:  root.vertical ? root.maxWidth : body.implicitWidth + root.pad * 2
    implicitHeight: body.implicitHeight + root.pad * 2
    Behavior on implicitHeight { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
    Behavior on implicitWidth  { enabled: !root.vertical; NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

    // The header badge's shape and glyph follow the gesture; at rest it is the arrange mode's own.
    readonly property string badgeShape: root.current ? root.shapes[root.current.mode] : "cookie9"
    readonly property string badgeSymbol: root.current ? root.current.symbol : "open_with"

    Item {
        id: body
        // Stays where the whole card would put it while the box grows round it (the clip trims it).
        x: root.pad + (root.restX - root.x)
        y: root.pad + (root.restY - root.y)
        opacity: root.fused ? Math.max(0, root.grow * 2 - 1) : 1
        implicitWidth: lay.implicitWidth
        implicitHeight: lay.implicitHeight

        Grid {
            id: lay
            columns: root.vertical ? 1 : root.steps.length + 2
            spacing: root.vertical ? Tokens.spacingSm : Tokens.spacingMd
            verticalItemAlignment: Grid.AlignVCenter

            // ── Header ────────────────────────────────────────────────────────
            // The hero badge morphs with the gesture; beside it the title, and under it one dim line.
            Item {
                id: head
                readonly property real textMax: root.vertical ? root.innerW - root.heroBadge - Tokens.spacingMd : root.headText
                width: root.vertical ? root.innerW : headRow.implicitWidth
                height: headRow.implicitHeight

                Row {
                    id: headRow
                    spacing: Tokens.spacingMd

                    Item {
                        width: root.heroBadge
                        height: root.heroBadge
                        anchors.verticalCenter: parent.verticalCenter
                        MorphShape {
                            anchors.fill: parent
                            shape: root.badgeShape
                            fillColor: root.over ? root.pal.alpha(root.pal.danger, 0.24) : root.pal.primary
                        }
                        MaterialIcon {
                            anchors.centerIn: parent
                            name: root.badgeSymbol
                            fill: 1
                            font.pixelSize: Tokens.iconLg
                            color: root.over ? root.pal.danger : root.pal.fgOnPrimary
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Tokens.spacingXs
                        StyledText {
                            width: head.textMax
                            wrapMode: root.vertical ? Text.WordWrap : Text.NoWrap
                            elide: root.vertical ? Text.ElideNone : Text.ElideRight
                            variant: "title"
                            font.weight: Font.DemiBold
                            text: root.dragging && root.description !== "" ? root.description : root.title
                            color: root.over ? root.pal.danger : root.dragging ? root.pal.primary : root.pal.fg
                            Behavior on color { ColorAnimation { duration: Motion.standard } }
                        }
                        StyledText {
                            width: head.textMax
                            elide: Text.ElideRight
                            variant: "caption"
                            text: root.dragging && root.description !== "" ? root.title : root.subtitle
                            color: root.pal.fgDim
                            visible: text !== ""
                        }
                    }
                }
            }

            // A hairline between the title and the gestures.
            Rectangle {
                width: root.vertical ? root.innerW : Tokens.borderWidth
                height: root.vertical ? Tokens.borderWidth : head.height * 0.7
                color: root.pal.alpha(root.pal.fg, 0.1)
            }

            // ── One tile per gesture ──────────────────────────────────────────
            Repeater {
                model: root.steps
                delegate: Item {
                    id: tile
                    required property var modelData
                    required property int index

                    readonly property bool on: root.dragging && root.mode === tile.modelData.mode
                    readonly property bool off: tile.on && tile.modelData.mode === "off"
                    readonly property int tpad: Tokens.spacingMd
                    readonly property real textMax: root.vertical ? root.innerW - tile.tpad * 2 - root.badge - Tokens.spacingMd : root.flatText

                    implicitWidth: tileRow.implicitWidth + tile.tpad * 2
                    implicitHeight: tileRow.implicitHeight + tile.tpad * 2
                    width: root.vertical ? root.innerW : tile.implicitWidth
                    height: tile.implicitHeight

                    PopIn { id: pop; active: root.visible; index: tile.index + 1 }
                    SpringValue { id: lift; target: tile.on ? 1 : 0; spec: Motion.springSpatialFast }
                    opacity: pop.opacity
                    scale: pop.scale * (1 + lift.value * 0.04)

                    Rectangle {
                        anchors.fill: parent
                        radius: root.tileRadius
                        color: tile.off ? Qt.tint(root.pal.section, root.pal.alpha(root.pal.danger, 0.28))
                             : tile.on  ? root.pal.primaryContainer
                             :            root.pal.section
                        Behavior on color { ColorAnimation { duration: Motion.standard } }
                    }

                    Row {
                        id: tileRow
                        x: tile.tpad
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Tokens.spacingMd

                        Item {
                            width: root.badge
                            height: root.badge
                            anchors.verticalCenter: parent.verticalCenter
                            MorphShape {
                                anchors.fill: parent
                                shape: tile.on ? root.shapes[tile.modelData.mode] : "circle"
                                fillColor: tile.off ? root.pal.alpha(root.pal.danger, 0.24)
                                         : tile.on  ? root.pal.primary
                                         :            root.pal.surfaceHigh
                            }
                            MaterialIcon {
                                anchors.centerIn: parent
                                name: tile.modelData.symbol
                                fill: tile.on ? 1 : 0
                                font.pixelSize: Tokens.iconLg
                                color: tile.off ? root.pal.danger
                                     : tile.on  ? root.pal.fgOnPrimary
                                     :            root.pal.fgMuted
                            }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0
                            StyledText {
                                width: tile.textMax
                                elide: Text.ElideRight
                                font.weight: Font.DemiBold
                                text: tile.modelData.title
                                color: tile.on && !tile.off ? root.pal.fgOnPrimaryContainer : root.pal.fg
                            }
                            StyledText {
                                width: tile.textMax
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                                variant: "caption"
                                text: tile.modelData.detail
                                color: tile.on && !tile.off ? root.pal.alpha(root.pal.fgOnPrimaryContainer, 0.78) : root.pal.fgDim
                            }
                        }
                    }
                }
            }
        }
    }
}
