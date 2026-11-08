pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import QtQuick.Shapes
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/weather.js" as W
import "../../services/ics.js" as Ics
import "../../services/holidays.js" as H
import "../../services/dayfacts.js" as Facts
import "../../services/dayplan.js" as Plan
import "../../services/quickadd.js" as Quick
import "../../services/alarms.js" as AL
import "../../services/worldclock.js" as Z

// ClockFact — moved out of ClockPanel.qml (2026-11-08), unchanged.
// ── Icon + text, inline ───────────────────────────────────────────────────
// `pops` makes it arrive on a spring, after `popIndex` of its neighbours.
Row {
    id: fact
    property string icon: ""
    property string text: ""
    property string sub:  ""
    property color  tint: Colors.of(QsWindow.window).fgDim
    property real   iconFill: 1
    property real   iconRotation: 0
    property bool   pops: false
    property bool   popActive: false
    property int    popIndex: 0
    property int    popDelay: 0
    spacing: Tokens.spacingSm
    visible: fact.text !== ""

    PopIn { id: factPop; active: fact.popActive; index: fact.popIndex; delay: fact.popDelay }
    opacity: fact.pops ? factPop.opacity : 1
    scale:   fact.pops ? factPop.scale   : 1

    MaterialIcon {
        anchors.verticalCenter: parent.verticalCenter
        name: fact.icon
        fill: fact.iconFill
        font.pixelSize: Tokens.iconMd
        color: fact.tint
        rotation: fact.iconRotation
        Behavior on rotation { RotationAnimation { duration: Motion.spatial; direction: RotationAnimation.Shortest } }
    }
    StyledText {
        anchors.verticalCenter: parent.verticalCenter
        text: fact.text
        variant: "label"
    }
    StyledText {
        anchors.verticalCenter: parent.verticalCenter
        visible: fact.sub !== ""
        text: fact.sub
        variant: "caption"
        emphasis: "dim"
    }
}
