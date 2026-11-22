import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/weather.js" as W

// ── WeatherSunPlate ───────────────────────────────────────────────────────────
// The day's sun as an arc from sunrise to sunset with a bead where it is now, the daylight in the middle of
// the arc and the two times under its ends. Only today has a bead: another day
// shows the arc whole.
// ─────────────────────────────────────────────────────────────────────────────
IslandPlate {
    id: root

    // weather.js sunArc / goldenHour results (null without a reading), and the two times as text.
    property var arc: null
    property string riseText: "—"
    property string setText: "—"
    property bool isToday: true

    readonly property real frac: root.isToday && root.arc ? root.arc.frac : 0
    readonly property bool lit: root.isToday && root.arc !== null && root.arc.state === "day"
    SpringValue { id: pos; target: root.frac; spec: Motion.springSpatial; epsilon: 0.001 }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingLg
        spacing: Tokens.spacingXs

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm
            IslandBadge {
                size: Tokens.iconXl
                shape: "sunny"
                symbol: root.lit ? "sunny" : "bedtime"
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Daylight")
                variant: "caption"
                font.weight: Font.DemiBold
                emphasis: "dim"
                elide: Text.ElideRight
            }
        }

        Item {
            id: sky
            Layout.fillWidth: true
            Layout.fillHeight: true
            readonly property real bead: Tokens.spacingMd + 2
            readonly property real cx: width / 2
            readonly property real cy: height - 1
            readonly property real rx: Math.max(1, width / 2 - bead / 2)
            readonly property real ry: Math.max(1, height - bead)

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: root.palette.alpha(root.ink, 0.16)
                    strokeWidth: Tokens.spacingXs + 1
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: sky.cx; centerY: sky.cy
                        radiusX: sky.rx; radiusY: sky.ry
                        startAngle: 180; sweepAngle: 180
                    }
                }
                ShapePath {
                    strokeColor: root.palette.warning
                    strokeWidth: Tokens.spacingXs + 1
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: sky.cx; centerY: sky.cy
                        radiusX: sky.rx; radiusY: sky.ry
                        startAngle: 180; sweepAngle: Math.max(0.01, 180 * pos.value * root.arrive)
                    }
                }
            }
            Rectangle {
                visible: root.isToday && root.arc !== null
                readonly property real a: (180 + 180 * pos.value) * Math.PI / 180
                width: sky.bead
                height: width
                radius: width / 2
                x: sky.cx + sky.rx * Math.cos(a) - width / 2
                y: sky.cy + sky.ry * Math.sin(a) - height / 2
                scale: root.arrive
                color: root.lit ? root.palette.warning : root.inkDim
                Behavior on color { ColorAnimation { duration: Motion.respond } }
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                text: !root.arc ? "—"
                    : root.lit ? Translation.tr("%1 left").arg(W.duration(root.arc.leftS))
                    : W.duration(root.arc.lengthS)
                variant: "caption"
                font.weight: Font.DemiBold
                font.features: ({ tnum: 1 })
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            StyledText {
                text: root.riseText
                variant: "micro"
                emphasis: "dim"
                font.features: ({ tnum: 1 })
            }
            Item { Layout.fillWidth: true }
            StyledText {
                text: root.setText
                variant: "micro"
                emphasis: "dim"
                font.features: ({ tnum: 1 })
            }
        }
    }
}
