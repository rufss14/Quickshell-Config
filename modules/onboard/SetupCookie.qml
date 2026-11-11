import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── SetupCookie ───────────────────────────────────────────────────────────────
// A glyph on a scalloped plate — the shell's own shape, as the setup's icon holder: a step's mark, a
// page's header, the hero on the welcome page. `lit` fills it (this is happening / this is the one);
// otherwise it is a tinted outline. Pointing at it (`hot`, driven by the card it sits in) winds it and
// deepens its petals, like ScallopChip. `turning` lets the plate itself turn slowly — the glyph on it
// never rotates (CookieButton's rule: a re-rasterised icon shimmers).
//
// `badge` puts a small verdict dot on the corner: "ok" or "bad" — Verdict colours, because a palette is
// free to land on red and the tick would then say the opposite.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string name: ""
    property color  tint: Colors.of(QsWindow.window).primary
    property bool   lit: false
    property bool   hot: false
    property bool   turning: false
    property string badge: ""
    property real   size: 36

    implicitWidth: root.size
    implicitHeight: root.size

    // Wind on hover; springy, so it overshoots and settles (ScallopChip's curve).
    readonly property real _wind: root.hot ? -9 : 0
    Behavior on scale {
        NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring }
    }
    scale: root.hot ? 1.08 : 1.0

    // Two items, one property each: the outer winds on hover, the inner turns — a Behavior and an
    // animator on the same `rotation` would chase each other.
    Item {
        id: plate
        anchors.fill: parent
        rotation: root._wind
        Behavior on rotation {
            NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring }
        }

        Item {
            id: spinner
            anchors.fill: parent
            // Slow turn, only while it is on screen and motion is on.
            RotationAnimator on rotation {
                from: 0; to: 360; duration: 28000; loops: Animation.Infinite
                running: root.turning && Motion.ambientOn && root.visible
            }
            ShapeBox {
                anchors.fill: parent
                fallback: "cookie"
                extraPetal: root.hot ? 0.06 : 0
                fillColor: root.lit ? root.tint : Colors.of(QsWindow.window).alpha(root.tint, root.hot ? 0.26 : 0.16)
                strokeColor: root.lit ? "transparent" : Colors.of(QsWindow.window).alpha(root.tint, 0.32)
                Behavior on fillColor { ColorAnimation { duration: Motion.standard } }
            }
        }
    }

    MaterialIcon {
        anchors.centerIn: parent
        name: root.name
        fill: root.lit ? 1 : 0
        color: root.lit ? Colors.of(QsWindow.window).fgOnPrimary : root.tint
        font.pixelSize: Math.round(root.size * 0.46)
        Behavior on color { ColorAnimation { duration: Motion.standard } }
    }

    // The verdict dot.
    Rectangle {
        id: dot
        readonly property real d: Math.max(12, Math.round(root.size * 0.36))
        width: dot.d; height: dot.d; radius: dot.d / 2
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: -2
        anchors.bottomMargin: -2
        visible: root.badge !== "" || scale > 0.05
        color: Verdict.tint(root.badge === "ok")
        border.width: 2
        border.color: Colors.of(QsWindow.window).surfaceHigh
        scale: root.badge !== "" ? 1 : 0
        Behavior on scale {
            NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring }
        }
        MaterialIcon {
            anchors.centerIn: parent
            name: root.badge === "bad" ? "close" : "check"
            fill: 1
            // The palette's constant black reads on both verdict colours.
            color: Colors.of(QsWindow.window).shadow
            font.pixelSize: Math.round(dot.d * 0.7)
        }
    }
}
