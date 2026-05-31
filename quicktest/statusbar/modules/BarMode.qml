import QtQuick
import "../../theming" as T

// ── BarMode ───────────────────────────────────────────────────────────────────
// Self-contained pill — owns its own background Rectangle like Clock does.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property bool barMode:  false
    property bool barShape: false
    signal toggle()

    implicitWidth:  40
    implicitHeight: T.Theme.pillHeight
    radius: T.Theme.radius(barShape)
    color: btn.pressed ? T.Theme.btnPressBg : (btn.containsMouse ? T.Theme.btnHoverBg : T.Theme.pillBg)

    Behavior on color  { ColorAnimation  { duration: T.Theme.animFast } }
    Behavior on radius { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }

    Image {
        anchors.centerIn: parent
        source: "../../theming/icons/barmode.svg"
        width: 16; height: 16
        fillMode: Image.PreserveAspectFit
    }

    MouseArea {
        id: btn
        anchors.fill: parent
        hoverEnabled: true
        cursorShape:  Qt.PointingHandCursor
        onClicked:    root.toggle()
    }
}
