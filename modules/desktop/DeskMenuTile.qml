import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── DeskMenuTile ──────────────────────────────────────────────────────────────
// One button of the desktop menu: a tonal tile with an icon and a name (or the icon alone). `vertical` stacks them (the
// tools row, four across); otherwise the icon sits left of the name (the places grid, two across).
// Lit (`on`, a recording running) it goes rounder and takes the container tone, on a spring, so
// the state reads by shape and not by colour alone. A press dips it, the pointer leans it.
//
// It only shows and signals: DeskMenuBody decides what a press does. `why` dims it and says why it
// can't run here (the blocker() contract), so a missing tool never fails on click.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string symbol: ""
    property string label: ""
    // Said on hover; a blocked tile says `why` instead.
    property string tip: ""
    property string why: ""
    property bool on: false
    property bool vertical: false
    // The icon alone (a row of them, the way Windows has its top row); `tip` names it.
    property bool iconOnly: false
    // The corner radius at rest; lit, it runs to a full pill.
    property int radius: Tokens.radiusSm

    signal activated()

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property bool usable: root.why === ""

    implicitHeight: root.iconOnly ? Tokens.iconXl + Tokens.spacingMd : root.vertical ? Tokens.iconXl * 2 : Tokens.iconXl + Tokens.spacingLg

    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.description: root.usable ? root.tip : root.why
    Accessible.onPressAction: if (root.usable) root.activated()

    opacity: root.usable ? 1 : 0.4

    HoverTip { text: root.usable ? root.tip : Translation.tr(root.why) }

    SpringValue {
        id: lean
        spec: Motion.springSpatialFast
        epsilon: 0.0005
        target: mouse.pressed ? 0.95 : mouse.containsMouse && root.usable ? 1.03 : 1
    }
    SpringValue {
        id: corner
        spec: Motion.springSpatialFast
        epsilon: 0.05
        target: root.on ? plate.height / 2 : root.radius
    }

    Rectangle {
        id: plate
        anchors.fill: parent
        scale: lean.value
        radius: corner.value
        color: root.on ? root.palette.primaryContainer : root.palette.surfaceHigh

        Rectangle {
            anchors.fill: parent
            radius: plate.radius
            color: root.palette.alpha(root.palette.fg, mouse.pressed ? Tokens.statePress : mouse.containsMouse && root.usable ? Tokens.stateHover : 0)
            Behavior on color { ColorAnimation { duration: Motion.respond } }
        }

        GridLayout {
            anchors.centerIn: parent
            width: parent.width - Tokens.spacingMd * 2
            flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
            rows: root.vertical ? 2 : 1
            columns: root.vertical ? 1 : 2
            rowSpacing: Tokens.spacingXs
            columnSpacing: Tokens.spacingMd

            MaterialIcon {
                Layout.alignment: root.vertical || root.iconOnly ? Qt.AlignHCenter : Qt.AlignVCenter
                name: root.symbol
                fill: root.on ? 1 : 0
                font.pixelSize: Tokens.iconLg
                color: root.on ? root.palette.fgOnPrimaryContainer : root.palette.fg
            }
            StyledText {
                Layout.fillWidth: true
                visible: !root.iconOnly
                horizontalAlignment: root.vertical ? Text.AlignHCenter : Text.AlignLeft
                text: root.label
                variant: root.vertical ? "caption" : "label"
                font.weight: root.on ? Font.DemiBold : Font.Medium
                color: root.on ? root.palette.fgOnPrimaryContainer : root.palette.fg
                elide: Text.ElideRight
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: root.usable
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
