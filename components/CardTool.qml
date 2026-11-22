import QtQuick
import Quickshell
import "../config"

// One round tool inside a card's tools capsule (a wallpaper's, a scheme's): a glyph that leans toward the pointer and dips under a
// press on springs, washes in its `hoverTint` while the pointer is on it, and can bump (`bump()`) so a state
// that just changed (a star taken) answers. `filled` fills the glyph (the FILL axis), as a lit state does
// everywhere else. No tooltip: the card is a clipping surface and a tip is cut by it; the name is the
// accessible name.
Item {
    id: root

    property string symbol: ""
    property bool   filled: false
    property color  tint: Colors.of(QsWindow.window).fg
    property color  hoverTint: root.tint
    property string name: ""
    signal activated()

    function bump() { popAnim.restart() }

    implicitWidth: Tokens.iconXl
    implicitHeight: Tokens.iconXl

    property real pop: 1
    SequentialAnimation {
        id: popAnim
        NumberAnimation { target: root; property: "pop"; to: 1.5; duration: Motion.respond; easing.type: Motion.travel }
        NumberAnimation { target: root; property: "pop"; to: 1; duration: Motion.standard; easing.type: Motion.overshoot }
    }

    SpringValue {
        id: lean
        target: tap.pressed ? 0.8 : hover.hovered ? 1.12 : 1
        spec: Motion.springSpatialFast
        epsilon: 0.001
    }

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Colors.of(QsWindow.window).alpha(root.hoverTint, 0.18)
        opacity: hover.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
    }
    MaterialIcon {
        anchors.centerIn: parent
        name: root.symbol
        fill: root.filled ? 1 : 0
        font.pixelSize: Tokens.iconLg
        color: hover.hovered ? root.hoverTint : root.tint
        scale: lean.value * root.pop
        Behavior on fill  { NumberAnimation { duration: Motion.standard } }
        Behavior on color { ColorAnimation { duration: Motion.respond } }
    }

    // A MouseArea, not a TapHandler: a handler's passive grab lets the press fall through to the card's own
    // click underneath, which would apply the wallpaper as well.
    HoverHandler { id: hover }
    MouseArea {
        id: tap
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }

    Accessible.role: Accessible.Button
    Accessible.name: root.name
    Accessible.onPressAction: root.activated()
}
