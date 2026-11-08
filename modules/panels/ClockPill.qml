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

// ClockPill — moved out of ClockPanel.qml (2026-11-08), unchanged.
// ── A pill of content ─────────────────────────────────────────────────────
// The footer's facts, and the "next up" line. Arrives like a Fact does; `dim` lets the
// whole pill recede (another day on the ring).
Rectangle {
    id: pill
    default property alias content: pillRow.data
    property color fill: Colors.of(QsWindow.window).section
    property real  dim: 1
    property bool  popActive: false
    property int   popIndex: 0
    property int   popDelay: 0

    implicitWidth:  pillRow.implicitWidth + Tokens.spacingLg * 2
    implicitHeight: Tokens.iconXl + Tokens.spacingXs
    radius: height / 2
    color: pill.fill

    PopIn { id: pillPop; active: pill.popActive; index: pill.popIndex; delay: pill.popDelay }
    opacity: pill.dim * pillPop.opacity
    scale:   pillPop.scale
    Behavior on dim { NumberAnimation { duration: Motion.standard } }

    Row {
        id: pillRow
        anchors.centerIn: parent
        spacing: Tokens.spacingSm
    }
}
