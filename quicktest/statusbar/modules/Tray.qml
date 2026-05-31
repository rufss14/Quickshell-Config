import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import Quickshell.DBusMenu
import QtQuick
import "../../theming" as T

Item {
    id: root

    property var  parentWindow: null
    property bool barShape:     false

    readonly property int itemCount: SystemTray.items.values.length

    implicitWidth:  itemCount * 26 + Math.max(0, itemCount - 1) * 4
    implicitHeight: T.Theme.pillHeight

    // Background pill
    Rectangle {
        anchors.centerIn: parent
        width:  root.implicitWidth
        height: T.Theme.pillHeight
        radius: T.Theme.radius(root.barShape)
        color:  T.Theme.pillBg
        Behavior on color  { ColorAnimation  { duration: T.Theme.animFast } }
        Behavior on radius { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }
    }

    Row {
        anchors.centerIn: parent
        spacing: 4

        Repeater {
            model: SystemTray.items

            Item {
                id: delegate
                required property var modelData
                property var  sni:         modelData
                property bool killVisible: false

                width: 26
                height: T.Theme.pillHeight

                opacity: 0.0
                scale:   0.5
                Component.onCompleted: { opacity = 0; scale = 0.5; entryAnim.start() }

                SequentialAnimation {
                    id: entryAnim
                    ParallelAnimation {
                        NumberAnimation { target: delegate; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutQuad }
                        NumberAnimation { target: delegate; property: "scale";   to: 1; duration: 220; easing.type: Easing.OutBack }
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 22; height: 22
                    radius: T.Theme.radius(root.barShape)
                    color: iconArea.containsMouse && !delegate.killVisible
                           ? T.Theme.hoverAccent : "transparent"
                    Behavior on color  { ColorAnimation  { duration: T.Theme.animFast } }
                    Behavior on radius { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }
                }

                IconImage {
                    id: appIcon
                    anchors.centerIn: parent
                    implicitSize: 16
                    source:  delegate.sni?.icon ?? ""
                    visible: source !== ""
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 16; height: 16
                    visible: !appIcon.visible
                    radius:  T.Theme.radius(root.barShape)
                    color:   T.Theme.pw(T.Theme.pal?.colors?.color9 || "#7dcfff", 0.28)
                    Behavior on radius { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }
                }

                Rectangle {
                    visible: (delegate.sni?.status === 2) && !delegate.killVisible
                    width: 5; height: 5; radius: 3
                    color: T.Theme.color1
                    anchors { bottom: parent.bottom; right: parent.right; margins: 1 }
                    SequentialAnimation on opacity {
                        running: delegate.sni?.status === 2
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.2; duration: 600; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                    }
                }

                Rectangle {
                    id: killBadge
                    width: 13; height: 13
                    radius: root.barShape ? 2 : 6
                    color:  killMa.containsMouse
                            ? T.Theme.color1
                            : T.Theme.pw(T.Theme.pal?.colors?.color1 || "#f7768e", 0.82)
                    anchors { top: parent.top; right: parent.right; topMargin: -3; rightMargin: -3 }
                    z: 10
                    opacity: delegate.killVisible ? 1.0 : 0.0
                    scale:   delegate.killVisible ? 1.0 : 0.4
                    Behavior on opacity { NumberAnimation { duration: T.Theme.animFast; easing.type: Easing.OutCubic } }
                    Behavior on scale   { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutBack } }
                    Behavior on color   { ColorAnimation  { duration: T.Theme.animFast } }
                    Behavior on radius  { NumberAnimation { duration: T.Theme.animSlow } }

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: T.Theme.bg
                        font { family: T.Theme.fontFamily; pixelSize: 7; weight: Font.Bold }
                    }

                    MouseArea {
                        id: killMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            delegate.killVisible = false
                            root.doKill(delegate.sni)
                        }
                    }
                }

                QsMenuAnchor {
                    id: nativeMenuAnchor
                    menu: delegate.sni?.menu ?? null
                    anchor.window: root.parentWindow
                    anchor.rect: Qt.rect(
                        delegate.mapToItem(root.parentWindow?.contentItem, 0, 0).x,
                        delegate.mapToItem(root.parentWindow?.contentItem, 0, 0).y + delegate.height + 4,
                        delegate.width, 0)
                }

                MouseArea {
                    id: iconArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onEntered: delegate.killVisible = true
                    onExited:  delegate.killVisible = false
                    onPressed:  delegate.scale = 0.82
                    onReleased: bounceAnim.restart()
                    SequentialAnimation {
                        id: bounceAnim
                        NumberAnimation { target: delegate; property: "scale"; to: 1.10; duration: 70;  easing.type: Easing.OutQuad }
                        NumberAnimation { target: delegate; property: "scale"; to: 1.0;  duration: 110; easing.type: Easing.InOutQuad }
                    }
                    onClicked: function(mouse) {
                        if (mouse.button === Qt.MiddleButton) {
                            delegate.sni?.secondaryActivate()
                            return
                        }
                        if (mouse.button === Qt.RightButton) {
                            nativeMenuAnchor.open()
                            return
                        }
                        delegate.sni?.activate()
                    }
                }
            }
        }
    }

    // Kill process (unchanged from your original)
    Process {
        id: killProc
        running: false
        stdout: SplitParser { onRead: function(line) { console.log("[kill] " + line) } }
        stderr: SplitParser { onRead: function(line) { console.log("[kill] ERR " + line) } }
        onExited: function(code) { console.log("[kill] exit=" + code) }
    }

    function doKill(sni) {
        // (your original long kill logic — unchanged)
        var rawId = (sni?.id ?? "")
        var rawTitle = (sni?.title ?? "")
        // ... (the rest of your original doKill function goes here)
        console.log("[kill] sni.id=" + rawId + " sni.title=" + rawTitle)
        // (keep the rest of your original doKill code exactly as it was)
    }
}