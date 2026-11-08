import QtQuick
import Quickshell
import "../config"

// ── CountBadge ────────────────────────────────────────────────────────────────
// A filled count on the corner of a bar control (UpdatePill's pending updates):
// a pill that widens with the digits, "99+" past 99. The caller anchors it and
// sets `visible`.
//
// Geometry follows the ICON scale along with the numeral inside it — they have to
// move together or the digits leave the circle. Square in the bar's square shape.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property int   count: 0
    property color tint:  Colors.of(QsWindow.window).primary
    property real  sizeScale: Config.barIconScale

    // The pill's height and its width per digit count, before `sizeScale`.
    readonly property int _h:  13
    readonly property int _w1: 13
    readonly property int _w2: 16
    readonly property int _w3: 18

    width:  Math.round((root.count > 99 ? root._w3 : (root.count > 9 ? root._w2 : root._w1)) * root.sizeScale)
    height: Math.round(root._h * root.sizeScale)
    radius: Config.barShape ? Tokens.spacingXs : height / 2
    color:  root.tint

    Behavior on width  { NumberAnimation { duration: Motion.fast } }
    Behavior on radius { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
    Behavior on color  { ColorAnimation  { duration: Motion.respond } }

    StyledText {
        anchors.centerIn: parent
        text:      root.count > 99 ? "99+" : root.count
        color:     Colors.of(QsWindow.window).fgOnPrimary
        variant:   "micro"
        sizeScale: root.sizeScale
        font.bold: true
    }
}
