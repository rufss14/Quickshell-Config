pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"

// ── ScreenTimeDayStrip ── part of ScreenTimeHero ──────────────────────────────────────────────────────
// Today in 24 bars, one per local hour (ScreenTime.todayHours): the shape of the day where the headline number
// says only the sum. The hour you are in is lit in the accent, the hours still to come are a faint stub, and
// the bars rise in one after another when the card builds. Pointing at one sets `hovered` (the hero reads it
// out: "14:00 – 15:00 · 52 m"). Scaled to the busiest hour, but never below 15 minutes, so a quiet morning
// doesn't draw a full-height bar.
//
// Hours exist only from the day the data format gained them; before that the strip is stubs.
// ─────────────────────────────────────────────────────────────────────────────────────────────────────
Item {
    id: strip

    property color ink: Colors.of(QsWindow.window).fg
    property color accent: Colors.of(QsWindow.window).primary
    // The hour under the pointer, -1 for none.
    property int hovered: -1

    readonly property var hrs: ScreenTime.todayHours
    readonly property real peak: Math.max(900, ...strip.hrs)
    // The hour of day now; Clock ticks once a minute, which is all this needs.
    readonly property int nowHour: { void Clock.now; return new Date().getHours() }
    readonly property real barsH: Tokens.iconXl
    readonly property real gap: Tokens.spacingXs
    readonly property real barW: (strip.width - strip.gap * 23) / 24

    implicitHeight: strip.barsH + Tokens.spacingXs + labelRow.implicitHeight

    Repeater {
        model: 24
        delegate: Rectangle {
            id: bar
            required property int index
            readonly property real v: strip.hrs[bar.index] ?? 0
            readonly property bool future: bar.index > strip.nowHour
            readonly property bool lit: bar.index === strip.nowHour

            SpringReveal { id: rise; when: true; delay: Math.min(bar.index * Motion.stagger, Motion.staggerCap * 2); spec: Motion.springSpatial }
            SpringValue { id: level; target: bar.v / strip.peak; spec: Motion.springSpatial; epsilon: 0.0005 }

            x: bar.index * (strip.barW + strip.gap)
            width: strip.barW
            height: Math.max(2, strip.barsH * Math.min(1, Math.max(0, level.value)) * Math.max(0, rise.value))
            y: strip.barsH - height
            radius: Math.min(width / 2, Tokens.radiusSm)
            color: bar.lit ? strip.accent
                 : bar.v > 0 ? Colors.of(QsWindow.window).alpha(strip.ink, strip.hovered === bar.index ? 0.9 : 0.55)
                 : Colors.of(QsWindow.window).alpha(strip.ink, bar.future ? 0.08 : 0.16)
            Behavior on color { ColorAnimation { duration: Motion.respond } }
        }
    }

    // The hours, as far as is useful.
    Item {
        id: labelRow
        anchors.left: parent.left
        anchors.right: parent.right
        y: strip.barsH + Tokens.spacingXs
        implicitHeight: Math.round(Tokens.fontMicro * 1.4)
        Repeater {
            model: [0, 6, 12, 18]
            delegate: StyledText {
                required property int modelData
                x: modelData * (strip.barW + strip.gap)
                text: modelData
                variant: "micro"
                color: Colors.of(QsWindow.window).alpha(strip.ink, 0.6)
            }
        }
    }

    MouseArea {
        anchors.left: parent.left
        anchors.right: parent.right
        height: strip.barsH
        hoverEnabled: true
        onPositionChanged: mouse => strip.hovered = Math.max(0, Math.min(23, Math.floor(mouse.x / (strip.width / 24))))
        onExited: strip.hovered = -1
    }
}
