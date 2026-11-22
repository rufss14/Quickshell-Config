import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/hyprcurves.js" as Curves

// ── MotionStage ───────────────────────────────────────────────────────────────
// A little stage that plays one Hyprland animation as it is configured: a mock window grows in and
// out (windows), dissolves (fade), slides across (workspaces, moves) or lights its outline
// (border), over the animation's real duration and curve — so a speed or an on/off switch is seen
// before the next window opens. The curve is drawn beside it. (Duration, curve and kind are
// services/hyprcurves.js.)
//
// It plays while `playing` (the page sets it while the pointer is on a row or its slider is held)
// and rests at the end of the movement otherwise: nothing loops behind an idle page.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string leaf: ""
    property real speed: 0
    property bool on: true
    property string curveName: ""
    property bool playing: false

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property string kind: Curves.kindFor(root.leaf)
    readonly property bool out: Curves.leaving(root.leaf)
    readonly property int ms: Curves.durationMs(root.speed, root.on)
    readonly property var curve: Curves.curveFor(root.curveName, Motion.emphasizedDecel)

    // Progress of the movement. 0 = not there yet, 1 = arrived; a curve may overshoot it.
    property real t: 1

    implicitHeight: 132

    SequentialAnimation {
        running: root.playing && root.leaf !== ""
        loops: Animation.Infinite
        // Arrives from nothing, or (an "Out" leaf) leaves from there.
        PropertyAction { target: root; property: "t"; value: root.out ? 1 : 0 }
        NumberAnimation {
            target: root
            property: "t"
            to: root.out ? 0 : 1
            duration: Math.max(1, root.ms)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.curve
        }
        PauseAnimation { duration: 900 }
    }

    // When it stops, it rests where the movement ends.
    onPlayingChanged: if (!root.playing) root.t = root.out ? 0 : 1

    Rectangle {
        id: stage
        anchors.fill: parent
        radius: Tokens.radiusCard
        color: root.palette.surfaceHigh
        clip: true

        // The mock window.
        Rectangle {
            id: win
            readonly property real k: Math.max(0, Math.min(1, root.t))

            width: Math.round(stage.width * 0.34)
            height: Math.round(stage.height * 0.6)
            radius: Math.max(Tokens.spacingSm, Tokens.radiusCard - Tokens.spacingLg)
            color: root.palette.primaryContainer
            border.width: root.kind === "border" ? Tokens.borderWidth + 2 : 0
            border.color: root.palette.alpha(root.palette.primary, win.k)

            x: root.kind === "slide"
                ? Math.round((stage.width - width) / 2 + (1 - root.t) * stage.width * 0.55 * (root.out ? -1 : 1))
                : Math.round((stage.width - width) / 2) - Math.round(stage.width * 0.1)
            y: Math.round((stage.height - height) / 2 + (root.kind === "window" ? (1 - root.t) * stage.height * 0.18 : 0))
            opacity: root.kind === "slide" || root.kind === "border" ? 1 : win.k
            scale: root.kind === "window" ? 0.78 + 0.22 * root.t : 1

            // Two bars of "content".
            Column {
                anchors.centerIn: parent
                spacing: Tokens.spacingSm
                Repeater {
                    model: 2
                    Rectangle {
                        required property int index
                        width: win.width * (index === 0 ? 0.6 : 0.4)
                        height: Tokens.spacingSm
                        radius: height / 2
                        color: root.palette.alpha(root.palette.fgOnPrimaryContainer, 0.3)
                    }
                }
            }
        }

        // The curve, drawn: time across, progress up.
        Item {
            id: plot
            width: Math.round(stage.height * 0.46)
            height: width
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.spacingLg
            visible: root.leaf !== ""

            Rectangle {
                anchors.fill: parent
                radius: Tokens.spacingSm
                color: root.palette.alpha(root.palette.fg, 0.06)
            }
            Shape {
                anchors.fill: parent
                anchors.margins: Tokens.spacingSm
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    id: curvePath
                    // PathCubic is not in this object's scope: it reads these through the id.
                    readonly property real w: plot.width - Tokens.spacingSm * 2
                    readonly property real h: plot.height - Tokens.spacingSm * 2
                    strokeColor: root.palette.primary
                    strokeWidth: 2
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    startX: 0
                    startY: curvePath.h
                    PathCubic {
                        x: curvePath.w
                        y: 0
                        control1X: root.curve[0] * curvePath.w
                        control1Y: curvePath.h - root.curve[1] * curvePath.h
                        control2X: root.curve[2] * curvePath.w
                        control2Y: curvePath.h - root.curve[3] * curvePath.h
                    }
                }
            }
        }

        // What is playing.
        ColumnLayout {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: Tokens.spacingLg
            spacing: 0
            StyledText {
                text: root.leaf !== "" ? root.leaf : Translation.tr("Point at an animation below")
                variant: "label"
                font.weight: Font.DemiBold
            }
            StyledText {
                visible: root.leaf !== ""
                text: root.ms === 0 ? Translation.tr("Off, instant") : root.ms + " ms · " + (root.curveName || Translation.tr("no curve"))
                variant: "caption"
                emphasis: "dim"
            }
        }
    }
}
