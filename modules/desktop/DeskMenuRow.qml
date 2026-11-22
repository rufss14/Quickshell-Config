import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── DeskMenuRow ───────────────────────────────────────────────────────────────
// One line of the desktop menu, the way a Windows context menu has them: an icon, a name, and at the
// end either a chevron (the row is a group: children go inside it and it unfolds INLINE, under the
// row, on a spring, since a floating sub-menu over a menu is the popup the island style rejects) or a
// small switch (`showSwitch`, for a view option that is on or off). A plain row just runs `activated`.
//
// `subtitle` is a live second line (what is true now). `actionSymbol` adds a round button at the end for
// the row's second job (edit the widgets, keep the sidebar hidden), lit while `actionLit`; it signals
// `actionActivated` and never `activated`.
//
// Only shows and signals: DeskMenuBody decides what a press does. `why` dims the row and says why it
// can't run here (the blocker() contract).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string symbol: ""
    property string label: ""
    property string tip: ""
    property string why: ""
    // A group: shows a chevron, and `open` unfolds what is inside it.
    property bool group: false
    property bool open: false
    // A view option: a switch at the end, on while `checked`.
    property bool checked: false
    property bool showSwitch: false
    // What is true now, under the name.
    property string subtitle: ""
    // The row's second job, as a round button at the end.
    property string actionSymbol: ""
    property string actionTip: ""
    property bool actionLit: false
    property int radius: Tokens.radiusSm

    // The group's children.
    default property alias drawer: items.data

    signal activated()
    signal actionActivated()

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property bool usable: root.why === ""
    // The unfolded plate's height: what is inside, and a little round it.
    readonly property real inner: items.implicitHeight + Tokens.spacingSm * 2

    implicitWidth: head.implicitWidth
    implicitHeight: head.height + fold.height

    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.description: root.usable ? root.tip : root.why
    Accessible.onPressAction: if (root.usable) root.activated()

    // Boxes do not wobble: a critically damped spring for the unfolding drawer.
    SpringValue {
        id: unfold
        spec: ({ stiffness: 420, damping: 1.0 })
        epsilon: 0.01
        target: root.open ? root.inner : 0
    }
    SpringValue {
        id: lean
        spec: Motion.springSpatialFast
        epsilon: 0.0005
        target: mouse.pressed ? 0.97 : 1
    }
    SpringValue {
        id: turn
        spec: Motion.springSpatialFast
        epsilon: 0.1
        target: root.open ? 180 : 0
    }

    Rectangle {
        id: head
        width: parent.width
        height: Math.max(Tokens.iconXl + Tokens.spacingMd, line.implicitHeight + Tokens.spacingSm * 2)
        implicitWidth: line.implicitWidth + Tokens.spacingMd * 2
        radius: root.radius
        scale: lean.value
        opacity: root.usable ? 1 : 0.4
        color: root.open ? root.palette.section
             : root.palette.alpha(root.palette.fg, mouse.pressed ? Tokens.statePress : mouse.containsMouse && root.usable ? Tokens.stateHover : 0)
        Behavior on color { ColorAnimation { duration: Motion.respond } }

        RowLayout {
            id: line
            z: 1
            anchors.fill: parent
            anchors.leftMargin: Tokens.spacingMd
            anchors.rightMargin: Tokens.spacingMd
            spacing: Tokens.spacingMd

            MaterialIcon {
                name: root.symbol
                fill: root.open ? 1 : 0
                font.pixelSize: Tokens.iconLg
                color: root.open ? root.palette.primary : root.palette.fg
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: root.label
                    variant: "label"
                    font.weight: root.open ? Font.DemiBold : Font.Medium
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.subtitle !== ""
                    text: root.subtitle
                    variant: "caption"
                    emphasis: "dim"
                    elide: Text.ElideRight
                }
            }
            // The row's second job: a round button that sits above the row's own press.
            Item {
                visible: root.actionSymbol !== ""
                Layout.preferredWidth: Tokens.iconXl - Tokens.spacingXs
                Layout.preferredHeight: Tokens.iconXl - Tokens.spacingXs

                SpringValue {
                    id: actLean
                    spec: Motion.springSpatialFast
                    epsilon: 0.0005
                    target: actMouse.pressed ? 0.88 : actMouse.containsMouse ? 1.1 : 1
                }
                Rectangle {
                    anchors.fill: parent
                    scale: actLean.value
                    radius: root.actionLit ? width / 2 : Tokens.radiusSm
                    color: root.actionLit ? root.palette.primaryContainer : root.palette.surfaceHigh
                    Behavior on radius { NumberAnimation { duration: Motion.respond } }
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: root.actionSymbol
                        fill: root.actionLit ? 1 : 0
                        font.pixelSize: Tokens.iconMd
                        color: root.actionLit ? root.palette.fgOnPrimaryContainer : root.palette.fgMuted
                    }
                }
                HoverTip { text: root.actionTip }
                MouseArea {
                    id: actMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.actionActivated()
                }
            }
            // A view option's switch: the thumb grows and slides on a spring.
            Item {
                visible: root.showSwitch
                Layout.preferredWidth: 30
                Layout.preferredHeight: 18

                SpringValue {
                    id: thumbAt
                    spec: Motion.springSpatialFast
                    epsilon: 0.0005
                    target: root.checked ? 1 : 0
                }
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: root.checked ? root.palette.primary : root.palette.surfaceHigh
                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                    Rectangle {
                        readonly property real d: 10 + 4 * thumbAt.value
                        width: d
                        height: d
                        radius: d / 2
                        y: (parent.height - d) / 2
                        x: 4 + (parent.width - 8 - 10) * thumbAt.value - (d - 10) * thumbAt.value
                        color: root.checked ? root.palette.fgOnPrimary : root.palette.fgMuted
                    }
                }
            }
            MaterialIcon {
                visible: root.group
                name: "expand_more"
                rotation: turn.value
                font.pixelSize: Tokens.iconLg
                color: root.palette.fgMuted
            }
        }

        HoverTip { text: root.usable ? root.tip : Translation.tr(root.why) }

        MouseArea {
            id: mouse
            anchors.fill: parent
            enabled: root.usable
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.activated()
        }
    }

    // What is inside, on a plate one tone up, clipped to the unfolding height.
    Item {
        id: fold
        anchors.top: head.bottom
        width: parent.width
        height: unfold.value
        clip: true
        visible: height > 0.5

        Rectangle {
            width: parent.width
            height: root.inner
            radius: root.radius
            color: root.palette.section
            opacity: Math.min(1, unfold.value / Math.max(1, root.inner))

            ColumnLayout {
                id: items
                x: Tokens.spacingSm
                y: Tokens.spacingSm
                width: parent.width - Tokens.spacingSm * 2
                spacing: Tokens.spacingXs
            }
        }
    }
}
