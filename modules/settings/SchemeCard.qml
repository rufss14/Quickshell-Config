pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../services/palette.js" as Palette

// ── SchemeCard ────────────────────────────────────────────────────────────────
// One colour scheme, as the bar's Colours panel shows it in its library: a pill in the scheme's own
// ground, its name in its own text colour over a ribbon of its fifteen colours, and which modes it
// holds (lit when it has that version). It is the scheme's colours, not the shell's: it is chosen
// by looking at it.
//
// `variants` is { dark, light } (ColorScheme.presets / .classics). The card shows the version for
// the shell's mode; a scheme with only the other one shows that, dimmed, so it is not mistaken for
// the real thing, and wearing it puts the shell in that mode.
//
// `current` is the page's say (ColorScheme.worn): a ring and a check, so it cannot disagree with
// what is on screen.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string name:     ""
    property var    variants: null
    property bool   current:  false
    property int    index:    0

    signal picked()

    readonly property var   pick: Palette.pickVariant(root.variants, Config.themeMode)
    readonly property var   pal:  root.pick.palette
    readonly property color ground: root.pal ? Palette.slotValue(root.pal, "background") : "transparent"
    readonly property color ink:    root.pal ? Palette.slotValue(root.pal, "foreground") : "transparent"
    readonly property bool  hasDark:  !!(root.variants && root.variants.dark)
    readonly property bool  hasLight: !!(root.variants && root.variants.light)

    Layout.fillWidth: true
    Layout.fillHeight: false
    implicitHeight: col.implicitHeight + Tokens.spacingMd * 2
    visible: root.pal !== null

    Accessible.role: Accessible.Button
    Accessible.name: root.name
    Accessible.checkable: true
    Accessible.checked: root.current
    Accessible.onPressAction: root.picked()

    // Arrives on a spring a beat after its neighbour, leans toward the pointer and dips on a press.
    PopIn { id: pop; active: root.visible; index: root.index }
    SpringValue {
        id: lean
        target: tap.pressed ? 0.97 : hover.hovered ? 1.02 : 1.0
        spec: Motion.springSpatialFast
        epsilon: 0.0005
    }
    opacity: pop.opacity
    scale:   lean.value * pop.scale

    Rectangle {
        anchors.fill: parent
        radius: Tokens.radiusPill
        color: root.ground
        border.width: root.current ? Tokens.borderWidth * 2 : Tokens.borderWidth
        border.color: root.current ? Colors.of(QsWindow.window).primary
                                   : Colors.of(QsWindow.window).alpha(root.ink, 0.14)
        Behavior on border.color { ColorAnimation { duration: Motion.respond } }
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin:  Tokens.spacingLg
        anchors.rightMargin: Tokens.spacingLg
        anchors.topMargin:   Tokens.spacingMd
        spacing: Tokens.spacingXs
        opacity: root.pick.exact ? 1 : 0.6

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Tokens.iconLg
            spacing: Tokens.spacingXs

            MaterialIcon {
                visible: root.current
                name: "check_circle_outline"; fill: 1
                color: root.ink; variant: "caption"
            }
            StyledText {
                Layout.fillWidth: true
                text: root.name
                variant: "caption"
                font.weight: root.current ? Font.DemiBold : Font.Medium
                color: root.ink
                elide: Text.ElideRight
            }
            // Which modes it holds: lit when it has that version, faint when not.
            MaterialIcon {
                name: "light_mode"; fill: 0
                opacity: root.hasLight ? 0.9 : 0.25
                color: root.ink; font.pixelSize: Tokens.iconSm
            }
            MaterialIcon {
                name: "dark_mode"; fill: 0
                opacity: root.hasDark ? 0.9 : 0.25
                color: root.ink; font.pixelSize: Tokens.iconSm
            }
        }

        // The palette, as a ribbon. Cells placed by arithmetic, not a layout: the edges are rounded to
        // whole pixels, so there are no hairline seams between them.
        Item {
            id: rib
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Tokens.iconSm

            Repeater {
                model: 15
                delegate: Rectangle {
                    required property int index
                    x:      Math.round(index * rib.width / 15)
                    width:  Math.round((index + 1) * rib.width / 15) - x
                    height: rib.height
                    topLeftRadius:     index === 0  ? height / 2 : 0
                    bottomLeftRadius:  index === 0  ? height / 2 : 0
                    topRightRadius:    index === 14 ? height / 2 : 0
                    bottomRightRadius: index === 14 ? height / 2 : 0
                    color: root.pal ? Palette.slotValue(root.pal, "color" + (index + 1)) : "transparent"
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: "transparent"
                border.width: Tokens.borderWidth
                border.color: Colors.of(QsWindow.window).alpha(root.ink, 0.18)
            }
        }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler   { id: tap; onTapped: root.picked() }

    HelpTip {
        text: root.pick.exact ? "" : Translation.tr("No version for this mode: wearing it switches the shell's mode")
    }
}
