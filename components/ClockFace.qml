import QtQuick
import QtQuick.Shapes
import Quickshell
import "../config"

// ── ClockFace ─────────────────────────────────────────────────────────────────
// An analog clock for ANY time you hand it (hours / minutes / seconds as plain numbers), so one
// face serves "now", a time zone, and a time being scrubbed to. Two sizes of the same thing: a
// small disc with two hands beside a world clock's name, and a big scalloped "cookie" (the
// shell's shape — Scallop) with ticks, a ticking second hand and an optional ring.
//
// ── Hands glide, and never go backwards ───────────────────────────────────────
// A hand's angle wraps (354° → 0° every minute), and a Behavior on the wrapped value would spin
// the hand back through the whole dial at that moment. So each hand follows an angle that only
// moves by the SHORTEST way to the new time (`_follow`) and so can run past 360° — which also
// lets a scrub from 23:50 to 00:10 turn the short way — and a spring carries it there. Hours and
// minutes are continuous (a real hour hand is most of the way to 4 at 3:55). The second hand
// springs onto each second and rests between, a data change landing; nothing sweeps.
//
// ── `ring` ────────────────────────────────────────────────────────────────────
// 0..1 sweeps an arc round the rim from 12 o'clock — the clock panel's timer — over a faint
// track; -1 draws neither. It takes room from the face (`inset`), so the arc never sits on the
// scallop's petals.
//
// `tone` tints the face: "day" warm, "night" cool, "" neutral. Colours are the screen's palette.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property int  hours:   0
    property int  minutes: 0
    property int  seconds: 0
    property bool showSeconds: false
    property bool scalloped:   false
    property bool ticks: root.width >= 56
    property bool springy: true
    property string tone: ""
    property real  ring: -1
    property color ringColor: root.accent
    property color accent: Colors.of(QsWindow.window).primary

    implicitWidth:  Tokens.iconXl
    implicitHeight: Tokens.iconXl

    // Room the ring takes from the face.
    readonly property real inset: root.ring >= 0 ? Math.max(3, root.width * 0.07) : 0
    readonly property real r: Math.max(1, Math.min(root.width, root.height) / 2 - root.inset)

    // ── Where the hands should be, and where they are ─────────────────────────
    readonly property real targetH: (root.hours % 12) * 30 + root.minutes * 0.5
    readonly property real targetM: root.minutes * 6 + (root.showSeconds ? root.seconds * 0.1 : 0)
    readonly property real targetS: root.seconds * 6
    property real angleH: root.targetH
    property real angleM: root.targetM
    property real angleS: root.targetS
    function _follow(cur, target) { return cur + ((((target - cur) % 360) + 540) % 360) - 180 }
    onTargetHChanged: root.angleH = root._follow(root.angleH, root.targetH)
    onTargetMChanged: root.angleM = root._follow(root.angleM, root.targetM)
    onTargetSChanged: root.angleS = root._follow(root.angleS, root.targetS)

    property color toneFill: root.tone === "day"   ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).warning, 0.20)
                                    : root.tone === "night" ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).info, 0.16)
                                    :                         Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.07)
    readonly property color hairline: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.12)
    Behavior on toneFill { ColorAnimation { duration: Motion.spatial } }

    // ── The ring ──────────────────────────────────────────────────────────────
    Shape {
        anchors.fill: parent
        visible: root.ring >= 0
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.hairline
            strokeWidth: Math.max(2, root.inset * 0.5)
            fillColor: "transparent"
            PathAngleArc {
                centerX: root.width / 2; centerY: root.height / 2
                radiusX: Math.min(root.width, root.height) / 2 - root.inset / 2
                radiusY: Math.min(root.width, root.height) / 2 - root.inset / 2
                startAngle: -90; sweepAngle: 359.9
            }
        }
        ShapePath {
            strokeColor: root.ringColor
            strokeWidth: Math.max(2, root.inset * 0.5)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: root.width / 2; centerY: root.height / 2
                radiusX: Math.min(root.width, root.height) / 2 - root.inset / 2
                radiusY: Math.min(root.width, root.height) / 2 - root.inset / 2
                startAngle: -90; sweepAngle: 360 * Math.max(0.004, Math.min(1, root.ring))
            }
        }
    }

    // ── The face ──────────────────────────────────────────────────────────────
    Item {
        id: dial
        anchors.fill: parent
        anchors.margins: root.inset

        Rectangle {
            anchors.fill: parent
            visible: !root.scalloped
            radius: width / 2
            color: root.toneFill
            border.width: Tokens.borderWidth
            border.color: root.hairline
        }
        Scallop {
            anchors.fill: parent
            visible: root.scalloped
            points: 12
            petalDepth: 0.05
            fillColor: root.toneFill
            strokeColor: root.hairline
        }

        // Twelve dots, the quarters larger.
        Repeater {
            model: root.ticks ? 12 : 0
            Rectangle {
                id: tick
                required property int index
                readonly property bool quarter: tick.index % 3 === 0
                readonly property real a: tick.index * Math.PI / 6
                width:  quarter ? 4 : 3
                height: width
                radius: width / 2
                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, quarter ? 0.55 : 0.28)
                x: dial.width / 2 + (root.r - 8) * Math.sin(a) - width / 2
                y: dial.height / 2 - (root.r - 8) * Math.cos(a) - height / 2
            }
        }

        Hand { length: root.r * 0.48; thickness: Math.max(1.5, root.r * 0.11); colour: Colors.of(QsWindow.window).fg; angle: root.angleH }
        Hand { length: root.r * 0.72; thickness: Math.max(1.5, root.r * 0.075); colour: Colors.of(QsWindow.window).fg; angle: root.angleM }
        Hand {
            visible: root.showSeconds
            length: root.r * 0.82; thickness: Math.max(1, root.r * 0.035); tail: root.r * 0.18
            colour: root.accent; angle: root.angleS
        }
        Rectangle {
            anchors.centerIn: parent
            width: Math.max(3, root.r * 0.14); height: width; radius: width / 2
            color: root.showSeconds ? root.accent : Colors.of(QsWindow.window).fg
        }
    }

    // A hand: a rounded bar pinned at the dial's centre, turned about it. `tail` is the counterweight
    // out the far side that makes the second hand read as one.
    component Hand: Rectangle {
        id: hand
        property real length: 10
        property real thickness: 2
        property real angle: 0
        property real tail: 0
        property color colour: Colors.of(QsWindow.window).fg

        width:  hand.thickness
        height: hand.length + hand.tail
        radius: hand.thickness / 2
        color:  hand.colour
        antialiasing: true
        x: dial.width / 2 - hand.thickness / 2
        y: dial.height / 2 - hand.length

        transform: Rotation {
            origin.x: hand.thickness / 2
            origin.y: hand.length
            angle: hand.angle
            Behavior on angle {
                enabled: root.springy && Config.motionEnabled
                SpringAnimation { spring: 3.2; damping: 0.36; epsilon: 0.05 }
            }
        }
    }
}
