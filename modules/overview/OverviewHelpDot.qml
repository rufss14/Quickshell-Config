import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── OverviewHelpDot ───────────────────────────────────────────────────────────
// A small "?" that, CLICKED, opens a card above it (the user, 2026-10-24: not on hover — a
// card that jumps up as the pointer crosses it is noise): a title, then sections, each a
// heading and a few lines with their own icon. A click anywhere else (or Escape, Overview)
// closes it, and the click still lands where it was aimed. For the keys the overview has no room
// to explain on its face (OverviewModifiers). The card is this item's child, so it opens where the
// "?" is and goes with it.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string title: ""
    // Each: { title, accent (a colour), lines: [{ symbol, text }] }.
    property var sections: []
    property bool open: false
    // Where the card opens: above and from the left (bottom-left placement), or — `below` — under the
    // "?" and right-aligned to it (the top-right corner of the workspaces' card, since 2026-10-24).
    property bool below: false

    implicitWidth: Tokens.iconXl + Tokens.spacingXs
    implicitHeight: Tokens.iconXl + Tokens.spacingXs

    Rectangle {
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        radius: height / 2
        color: root.open ? Colors.of(QsWindow.window).primaryContainer
             : dotHover.hovered ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
             : "transparent"
        SpringValue { id: dotLean; target: dotTap.pressed ? 0.88 : dotHover.hovered ? 1.06 : 1; spec: Motion.springSpatialFast; epsilon: 0.001 }
        scale: dotLean.value
        Behavior on color { ColorAnimation { duration: Motion.respond } }
        MaterialIcon {
            anchors.centerIn: parent
            name: "help"
            fill: root.open ? 1 : 0
            color: root.open ? Colors.of(QsWindow.window).fgOnPrimaryContainer : dotHover.hovered ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgMuted
            font.pixelSize: Tokens.iconMd
            Behavior on color { ColorAnimation { duration: Motion.respond } }
        }
    }
    HoverHandler { id: dotHover; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: dotTap; onTapped: root.open = !root.open }

    // A click outside closes it — and is NOT eaten (accepted = false), so it still does what it
    // was aimed at. Over the whole window while open; the "?" and the card let the press through.
    Item {
        parent: root.Window.window ? root.Window.window.contentItem : root
        anchors.fill: parent
        z: 10000
        visible: root.open
        MouseArea {
            id: catcher
            anchors.fill: parent
            onPressed: function (mouse) {
                mouse.accepted = false
                const inPop = pop.contains(pop.mapFromItem(catcher, mouse.x, mouse.y))
                const inDot = root.contains(root.mapFromItem(catcher, mouse.x, mouse.y))
                if (!inPop && !inDot) root.open = false
            }
        }
    }

    Surface {
        id: pop
        z: 950
        elevation: Tokens.elevationPopup
        cornerRadius: Tokens.radiusCard
        width: Tokens.sideCardUnit * 7
        height: popCol.implicitHeight + Tokens.spacingLg * 2
        x: root.below ? root.width - pop.width + Tokens.spacingMd : -Tokens.spacingMd
        y: root.below ? root.height + Tokens.spacingMd : -pop.height - Tokens.spacingMd
        visible: opacity > 0.01
        opacity: root.open ? 1 : 0
        SpringValue { id: cardPop; target: root.open ? 1 : 0.94; spec: Motion.springSpatial; epsilon: 0.001 }
        scale: cardPop.value
        transformOrigin: root.below ? Item.TopRight : Item.BottomLeft
        Behavior on opacity { NumberAnimation { duration: root.open ? Motion.standard : Motion.fast } }

        Column {
            id: popCol
            x: Tokens.spacingLg
            y: Tokens.spacingLg
            width: pop.width - Tokens.spacingLg * 2
            spacing: Tokens.spacingLg

            Row {
                spacing: Tokens.spacingSm
                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "keyboard"
                    color: Colors.of(QsWindow.window).primary
                    font.pixelSize: Tokens.iconMd
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.title
                    variant: "title"
                    font.weight: Font.DemiBold
                }
            }
            Repeater {
                model: root.sections
                delegate: Column {
                    id: section
                    required property var modelData
                    width: popCol.width
                    spacing: Tokens.spacingSm
                    // The key, as a keycap.
                    Rectangle {
                        width: capText.implicitWidth + Tokens.spacingMd * 2
                        height: capText.implicitHeight + Tokens.spacingXs * 2
                        radius: Tokens.radiusSm
                        color: Colors.of(QsWindow.window).primaryContainer
                        StyledText {
                            id: capText
                            anchors.centerIn: parent
                            text: section.modelData.title
                            variant: "label"
                            font.weight: Font.DemiBold
                            color: Colors.of(QsWindow.window).fgOnPrimaryContainer
                        }
                    }
                    Repeater {
                        model: section.modelData.lines
                        delegate: Row {
                            id: line
                            required property var modelData
                            width: section.width
                            spacing: Tokens.spacingMd
                            MaterialIcon {
                                id: lineIcon
                                name: line.modelData.symbol
                                color: Colors.of(QsWindow.window).fgMuted
                                font.pixelSize: Tokens.iconMd
                            }
                            StyledText {
                                width: parent.width - lineIcon.width - Tokens.spacingMd
                                text: line.modelData.text
                                variant: "caption"
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }
        }
    }
}
