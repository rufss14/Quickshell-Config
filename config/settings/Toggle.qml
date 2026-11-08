import QtQuick
import "../theming" as T

// Toggle — a themed on/off switch reused across settings pages. Opaque, animated.
Item {
    id: t
    property bool on: false
    property bool busy: false        // show a subdued state while an action is in flight
    signal toggled(bool value)

    implicitWidth: 46
    implicitHeight: 24

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: t.on ? T.Theme.accent : T.Theme.surfaceHover
        border.width: 1
        border.color: t.on ? T.Theme.accent : T.Theme.border
        opacity: t.busy ? 0.5 : 1
        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }

        Rectangle {
            height: parent.height - 6
            width: height
            radius: height / 2
            y: 3
            x: t.on ? parent.width - width - 3 : 3
            color: t.on ? T.Theme.inkAccent : T.Theme.ink
            Behavior on x { NumberAnimation { duration: T.Theme.animFast; easing.type: Easing.OutCubic } }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: !t.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: t.toggled(!t.on)
    }
}
