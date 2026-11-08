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

// ClockRibbon — moved out of ClockPanel.qml (2026-11-08), unchanged.
// ── A zone's day, as a ribbon ─────────────────────────────────────────────
// 24 hours of YOUR timeline (worldclock.js windowStart): dim where it is night there, warm where it is
// daylight (06–18), in the accent where it is office hours (09–17). Rows' ribbons share one axis, so the
// overlap between places is the stretch where they are lit together.
Item {
    id: rib
    property real off: 0
    property real winStart: 0
    property color accent: Colors.of(QsWindow.window).primary
    implicitHeight: Tokens.spacingMd + 2
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.07)
    }
    Repeater {
        model: Z.bands(rib.winStart, rib.off, 6, 18)
        Rectangle {
            required property var modelData
            x: modelData.a * rib.width
            width: (modelData.b - modelData.a) * rib.width
            height: rib.height
            radius: height / 2
            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).warning, 0.30)
        }
    }
    Repeater {
        model: Z.bands(rib.winStart, rib.off, 9, 17)
        Rectangle {
            required property var modelData
            x: modelData.a * rib.width
            width: (modelData.b - modelData.a) * rib.width
            height: rib.height
            radius: height / 2
            color: Colors.of(QsWindow.window).alpha(rib.accent, 0.85)
        }
    }
}
