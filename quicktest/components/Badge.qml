import QtQuick
import "../config"

// ── Badge ─────────────────────────────────────────────────────────────────────
// A small tinted chip: "Internal", "eDP-1", "saved", "connected", "99+".
//
// Five panels each grew their own. They disagreed on height (13 / 16 / 18), on
// radius (3 / 4 / 5 / 9), on font size (8 / 9), and on fill/border alpha. Same
// object, five slightly different objects.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property string label: ""
    property color  tint:  Colors.focus

    // A filled badge reads as a COUNT or a live state (the update count, "needs
    // attention"). An outlined one reads as METADATA about the thing next to it
    // (which port, which security type). Different jobs, so different weights.
    property bool filled: false

    implicitWidth:  Math.ceil(text.implicitWidth) + Tokens.spacingMd + 2
    implicitHeight: 16

    radius: Tokens.radiusXs + 1

    color:        filled ? root.tint : Colors.alpha(root.tint, 0.15)
    border.color: Colors.alpha(root.tint, filled ? 0.0 : 0.38)
    border.width: filled ? 0 : Tokens.borderWidth

    Behavior on color { ColorAnimation { duration: Motion.respond } }

    StyledText {
        id: text
        anchors.centerIn: parent
        text:  root.label
        color: root.filled ? Colors.fgOnPrimary : Colors.alpha(root.tint, 0.85)
        font.pixelSize: 8
        font.bold: true
    }
}
