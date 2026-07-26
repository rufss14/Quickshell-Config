import QtQuick
import "../config"

// ── Toggle ────────────────────────────────────────────────────────────────────
// A switch. On = the accent; off = a muted track.
//
// `primary` would be wrong here: a switch shows STATE, not an invitation to act,
// so it takes `focus` — the same role as the slider fill and the "this is open"
// outline.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property bool  checked: false
    property color accent:  Colors.focus

    signal toggled()

    implicitWidth:  44
    implicitHeight: 24
    radius: height / 2

    color: checked ? Colors.alpha(accent, 0.80) : Colors.alpha(Colors.fg, 0.15)
    border.width: Tokens.borderWidth
    border.color: checked ? Colors.alpha(accent, 0.40) : Colors.outline

    Behavior on color        { ColorAnimation { duration: Motion.fast } }
    Behavior on border.color { ColorAnimation { duration: Motion.fast } }

    Rectangle {
        width:  18
        height: 18
        radius: height / 2
        color:  Colors.surface
        opacity: root.checked ? 1.0 : 0.55
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? parent.width - width - 3 : 3

        Behavior on x       { NumberAnimation { duration: Motion.fast; easing.type: Motion.travel } }
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
