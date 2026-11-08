import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"

// ── TileRow ───────────────────────────────────────────────────────────────────
// One row of a list on a desktop tile — a clipboard entry, a reminder, a disk, a city.
// Material 3 Expressive's list item at tile scale: a solid tonal container one step above
// the tile (`surfaceHigh` on `surfaceContainer`), the shell's row corner, and Material's
// state layer over it (8% hover, a 10% wave from the press point) instead of each widget's
// own hand-tuned hover wash — four of them disagreed between 0.06 and 0.16.
//
// Content is laid out in a RowLayout (the default property), so a caller writes its
// cells as plain children. `flash` holds a state colour over the fill (a clipboard row
// just copied back). `interactive: false` for a row that only displays.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: row

    property bool interactive: true
    property color flash: "transparent"
    signal tapped()

    default property alias content: inner.data

    Layout.fillWidth: true
    implicitHeight: Math.max(Tokens.iconLg + Tokens.spacingSm * 2, inner.implicitHeight + Tokens.spacingSm * 2)
    radius: Tokens.corner(Config.barShape, Tokens.radiusSm)
    color: row.flash.a > 0 ? row.flash : Colors.of(QsWindow.window).surfaceHigh
    Behavior on color { ColorAnimation { duration: Motion.respond } }

    StateLayer {
        id: feel
        anchors.fill: parent
        radius: row.radius
        hovered: row.interactive && mouse.containsMouse
    }

    // Under the content, so a control in the row (a delete cross) takes its own press.
    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: row.interactive
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: function (e) { feel.press(e.x, e.y) }
        onReleased: feel.release()
        onCanceled: feel.release()
        onClicked: row.tapped()
    }

    RowLayout {
        id: inner
        anchors.fill: parent
        anchors.leftMargin: Tokens.spacingMd
        anchors.rightMargin: Tokens.spacingMd
        spacing: Tokens.spacingSm
    }

    readonly property bool hovered: mouse.containsMouse
}
