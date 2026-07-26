import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Wayland
import QtQuick
import "../../config"

PanelWindow {
    id: popup

    property var  menuHandle:   null
    property var  anchorItem:   null
    property bool barShape:     false
    property var  parentWindow: null   // API compat only

    // Drives the fade/scale animation; `visible` stays true until the
    // closing animation finishes so the panel can animate out like the
    // other overlay panels do.
    property bool expanded: false

    function open(handle, anchor) {
        menuHandle = handle
        anchorItem = anchor
        expanded   = true
    }

    function close() {
        expanded = false
    }

    // Right margin: distance from anchor's right edge to screen right,
    // offset by half the popup width so it centres under the icon.
    readonly property real _marginRight: {
        if (!anchorItem) return 12
        var pt = anchorItem.mapToGlobal(anchorItem.width, 0)
        var sw = popup.screen?.width ?? 1920
        return Math.max(4, sw - pt.x - popup.implicitWidth / 2)
    }

    anchors.top:   true
    anchors.right: true
    margins.top:   Config.barThickness + 2
    margins.right: _marginRight

    implicitWidth:  150
    implicitHeight: card.implicitHeight
    color:          "transparent"
    visible:        expanded || card.opacity > 0.005

    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "quickshell-traymenu"
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: expanded ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    HyprlandFocusGrab {
        windows: [popup]
        active:  popup.expanded
        onCleared: popup.close()
    }

    QsMenuOpener {
        id: opener
        menu: popup.menuHandle
    }

    Item {
        id: popupFocusItem
        anchors.fill: parent
        Keys.onEscapePressed: popup.close()
        Connections {
            target: popup
            function onExpandedChanged() {
                if (popup.expanded) popupFocusItem.forceActiveFocus()
            }
        }
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius:       barShape ? 4 : Tokens.radiusPill + 4
        clip:         true
        color:        Colors.surface
        border.color: cardHover.hovered ? Colors.focus : Colors.outline
        border.width: 1

        implicitHeight: col.implicitHeight

        opacity: popup.expanded ? 1.0 : 0.0
        scale:   popup.expanded ? 1.0 : 0.96
        transformOrigin: Item.TopRight

        Behavior on opacity      { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic } }
        Behavior on scale        { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutBack  } }
        Behavior on border.color { ColorAnimation  { duration: Motion.respond } }

        HoverHandler { id: cardHover }

        Column {
            id: col
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 3 }
            topPadding:    3
            bottomPadding: 3
            spacing:       0

            // App title header
            Item {
                width:   parent.width
                height:  17
                visible: (popup.menuHandle?.title ?? "") !== ""
                Text {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 7; rightMargin: 5 }
                    text:  popup.menuHandle?.title ?? ""
                    color: Colors.fgDim
                    font { family: Tokens.fontFamily; pixelSize: Tokens.fontBody - 3; weight: Font.Medium }
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                width:   parent.width - 6
                height:  1
                anchors.horizontalCenter: parent.horizontalCenter
                color:   Colors.outline
                visible: (popup.menuHandle?.title ?? "") !== ""
            }

            // Menu items
            Repeater {
                model: opener.children.values

                delegate: Item {
                    required property var modelData
                    readonly property var  entry:     modelData
                    readonly property bool isSep:     entry?.isSeparator ?? false
                    readonly property bool isEnabled: entry?.enabled ?? true
                    readonly property bool hasSub:    entry?.hasChildren ?? false

                    width:  col.width
                    height: isSep ? 6 : 20

                    Rectangle {
                        visible: isSep
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 5; rightMargin: 5 }
                        height: 1
                        color:  Colors.outline
                    }

                    Rectangle {
                        visible: !isSep && isEnabled && ma.containsMouse
                        anchors { fill: parent; leftMargin: 2; rightMargin: 2; topMargin: 1; bottomMargin: 1 }
                        radius:  barShape ? 3 : 5
                        color:   Colors.alpha(Colors.primary, 0.25)
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                    }

                    IconImage {
                        id: rowIcon
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 7 }
                        implicitSize: 11
                        source:  entry?.icon ?? ""
                        visible: !isSep && source !== ""
                        opacity: isEnabled ? 1.0 : 0.35
                    }

                    Text {
                        anchors {
                            left: parent.left; right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin:  rowIcon.visible ? 21 : 7
                            rightMargin: hasSub ? 14 : 5
                        }
                        visible: !isSep
                        text:    entry?.text ?? ""
                        color:   !isEnabled        ? Colors.fgDim
                                 : ma.containsMouse ? Colors.primary
                                 : Colors.fg
                        font { family: Tokens.fontFamily; pixelSize: Tokens.fontBody - 2 }
                        elide: Text.ElideRight
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                    }

                    Text {
                        visible: hasSub && !isSep
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 5 }
                        text:  "›"
                        color: ma.containsMouse ? Colors.primary : Colors.fgDim
                        font { family: Tokens.fontFamily; pixelSize: Tokens.fontBody - 1 }
                    }

                    MouseArea {
                        id: ma
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled:      isEnabled && !isSep
                        cursorShape:  Qt.PointingHandCursor
                        onClicked: {
                            if (hasSub) return
                            entry?.triggered()
                            popup.close()
                        }
                    }
                }
            }
        }
    }
}
