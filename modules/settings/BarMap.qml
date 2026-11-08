pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../state"

// ── BarMap ────────────────────────────────────────────────────────────────────
// Your bar, small: the REAL widgets (PreviewModules, inert) in the real groups from
// Config.layout, left / centre / right, on a strip of the bar's own material. Click a
// widget to pick it — the page's inspector edits whatever `UiState.barInspectModule`
// names, the same selection pressing a module on the real bar makes in arrange mode.
//
// ── Why a picture of the bar, when the bar is right there ─────────────────────
// A preview of the bar was removed once on the grounds that the real one is a few
// pixels above this window. True, and it still left the page as a column of text chips
// naming modules you then had to go and find. This is not a second bar to look at; it
// is the bar as a PICKER — the one place a module can be chosen without arming arrange
// mode and aiming at a 24px pill on another surface. It is built from the same
// components the bar uses, so it can't drift from it.
//
// It scales as a whole to the card's width (down for a long bar, up a little for a short
// one) rather than wrapping: a wrapped bar is not a bar.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property var componentFor: null
    readonly property string selected: UiState.barInspectModule

    readonly property var regions: ["left", "centre", "right"]
    readonly property real gap: Tokens.spacingLg

    // The strip at natural size, then fitted.
    readonly property real naturalW: strip.implicitWidth
    // Down to fit a wide bar, and up (a little) when there's room, so a short bar
    // doesn't sit tiny in the middle of the card. Text re-renders at the new size.
    readonly property real fit: root.naturalW > 0 ? Math.min(1.35, root.width / root.naturalW) : 1

    implicitHeight: strip.implicitHeight * root.fit

    Rectangle {
        id: strip
        implicitWidth: Math.max(regionRow.implicitWidth + root.gap * 2, 640)
        implicitHeight: Config.barSurfaceHeight + Tokens.spacingMd * 2
        width: implicitWidth
        height: implicitHeight
        anchors.horizontalCenter: parent.horizontalCenter
        transformOrigin: Item.Top
        scale: root.fit

        radius: Config.barShape ? 0 : Config.barRoundness + Tokens.spacingSm
        color: Colors.of(QsWindow.window).frameFill
        border.width: Tokens.borderWidth
        border.color: Colors.of(QsWindow.window).frameLine

        // Three regions, the centre one held at the middle like the bar's.
        Item {
            id: regionRow
            anchors.fill: parent
            anchors.leftMargin: root.gap
            anchors.rightMargin: root.gap
            // The centre is held at the middle, so the wider side decides the width.
            implicitWidth: Math.max(leftR.implicitWidth, rightR.implicitWidth) * 2
                         + centreR.implicitWidth + root.gap * 4

            Region { id: leftR;   key: "left";   anchors.left: parent.left;  anchors.verticalCenter: parent.verticalCenter }
            Region { id: centreR; key: "centre"; anchors.centerIn: parent }
            Region { id: rightR;  key: "right";  anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter }
        }
    }

    // ── One region: its groups, side by side ──────────────────────────────────
    component Region: Row {
        id: region
        property string key: ""
        spacing: Tokens.spacingSm

        Repeater {
            model: Config.layout[region.key] ?? []

            // ── One group: a pill holding its modules ──────────────────────────
            delegate: Rectangle {
                id: group
                required property var modelData
                implicitWidth: groupRow.implicitWidth + Tokens.spacingSm * 2
                implicitHeight: Config.barSurfaceHeight - Tokens.spacingSm
                width: implicitWidth
                height: implicitHeight
                radius: Config.barShape ? Tokens.radiusXs : Math.max(Tokens.radiusSm, Config.barRoundness - Tokens.spacingXs)
                color: Config.barInnerPill
                    ? Colors.of(QsWindow.window).surfaceFor(Tokens.elevationNested)
                    : "transparent"

                Row {
                    id: groupRow
                    anchors.centerIn: parent
                    spacing: Tokens.spacingXs

                    Repeater {
                        model: group.modelData

                        delegate: Item {
                            id: cell
                            required property string modelData
                            readonly property bool picked: root.selected === cell.modelData

                            implicitWidth: Math.max(Tokens.pillHeight, widget.implicitWidth + Tokens.spacingXs * 2)
                            implicitHeight: group.height - Tokens.spacingXs * 2
                            width: implicitWidth
                            height: implicitHeight

                            // The selection: a ring that springs in, so a pick reads as
                            // a move rather than a recolour.
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -Tokens.spacingXs
                                radius: Tokens.radiusSm
                                color: cell.picked ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.22)
                                     : cellHover.hovered ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
                                     : "transparent"
                                border.width: cell.picked ? 2 : 0
                                border.color: Colors.of(QsWindow.window).primary
                                scale: cell.picked ? 1 : 0.9
                                Behavior on color { ColorAnimation { duration: Motion.respond } }
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: Motion.standard
                                        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring
                                    }
                                }
                            }

                            // `enabled: false` makes it a picture: it reaches into every
                            // MouseArea in the real widget, so the volume pill here
                            // changes nothing and the tap below is all that happens.
                            Loader {
                                id: widget
                                anchors.centerIn: parent
                                enabled: false
                                sourceComponent: root.componentFor ? root.componentFor(cell.modelData) : null
                            }

                            HoverHandler { id: cellHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: UiState.inspectBarModule(cell.modelData) }
                        }
                    }
                }
            }
        }
    }
}
