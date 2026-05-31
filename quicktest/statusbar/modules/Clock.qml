import QtQuick
import QtQuick.Layouts
import "../../theming" as T

// ── Clock ─────────────────────────────────────────────────────────────────────
// Right-side pill with analog clock + date + time
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property bool barShape:  false
    property bool clockOpen: false
    signal toggleClock()

    implicitHeight: T.Theme.pillHeight
    implicitWidth:  clockRow.implicitWidth + 16
    radius: T.Theme.radius(barShape)
    color:  T.Theme.pillBg

    Behavior on radius { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.03) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.03) }
        }
    }

    RowLayout {
        id: clockRow
        anchors.centerIn: parent
        spacing: 8

        Canvas {
            id: analogClock
            width: 16
            height: 16
            Layout.alignment: Qt.AlignVCenter

            Timer {
                interval: 1000; running: true; repeat: true
                onTriggered: analogClock.requestPaint()
            }

            onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)

                var cx = width / 2
                var cy = height / 2
                var r  = width / 2 - 1.5

                var now  = new Date()
                var hrs  = now.getHours() % 12
                var mins = now.getMinutes()
                var secs = now.getSeconds()

                var minAngle  = ((mins + secs / 60) / 60) * Math.PI * 2 - Math.PI / 2
                var hourAngle = ((hrs  + mins / 60) / 12) * Math.PI * 2 - Math.PI / 2

                var accent = T.Theme.color1
                var fg     = T.Theme.fg

                ctx.lineCap = "round"

                // Circle border
                ctx.beginPath()
                ctx.arc(cx, cy, r, 0, Math.PI * 2)
                ctx.strokeStyle = Qt.rgba(accent.r, accent.g, accent.b, 0.7)
                ctx.lineWidth = 1.2
                ctx.stroke()

                // Hour ticks
                for (var i = 0; i < 12; i++) {
                    var angle = (i / 12) * Math.PI * 2 - Math.PI / 2
                    var isMajor = i % 3 === 0
                    ctx.beginPath()
                    ctx.moveTo(cx + Math.cos(angle) * (r - 0.5),
                               cy + Math.sin(angle) * (r - 0.5))
                    ctx.lineTo(cx + Math.cos(angle) * (r - (isMajor ? 2.5 : 1.5)),
                               cy + Math.sin(angle) * (r - (isMajor ? 2.5 : 1.5)))
                    ctx.strokeStyle = isMajor
                        ? Qt.rgba(accent.r, accent.g, accent.b, 0.5)
                        : Qt.rgba(fg.r, fg.g, fg.b, 0.2)
                    ctx.lineWidth = isMajor ? 0.8 : 0.5
                    ctx.stroke()
                }

                // Hour hand
                ctx.beginPath()
                ctx.moveTo(cx, cy)
                ctx.lineTo(cx + Math.cos(hourAngle) * r * 0.45,
                           cy + Math.sin(hourAngle) * r * 0.45)
                ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 1.0)
                ctx.lineWidth = 1.5
                ctx.stroke()

                // Minute hand
                ctx.beginPath()
                ctx.moveTo(cx, cy)
                ctx.lineTo(cx + Math.cos(minAngle) * r * 0.72,
                           cy + Math.sin(minAngle) * r * 0.72)
                ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.85)
                ctx.lineWidth = 1.0
                ctx.stroke()

                // Center dot
                ctx.beginPath()
                ctx.arc(cx, cy, 1.2, 0, Math.PI * 2)
                ctx.fillStyle = Qt.rgba(accent.r, accent.g, accent.b, 1.0)
                ctx.fill()
            }
        }

        Rectangle { width: 1; height: 14; color: T.Theme.dimFg }

        Text {
            id: dateText
            color: T.Theme.fg
            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 2; weight: Font.Medium }
            text: Qt.formatDateTime(new Date(), "ddd, MMM dd")
        }

        Rectangle { width: 1; height: 14; color: T.Theme.dimFg }

        Text {
            id: clockText
            color: T.Theme.color1
            font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1; weight: Font.Bold; letterSpacing: 0.5 }
            text: Qt.formatDateTime(new Date(), "HH:mm")
        }
    }

    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            clockText.text = Qt.formatDateTime(new Date(), "HH:mm")
            dateText.text  = Qt.formatDateTime(new Date(), "ddd, MMM dd")
        }
    }

    // Tint overlay when open/hovered
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: clockMa.containsMouse
            ? (root.clockOpen ? T.Theme.btnPressBg  : T.Theme.btnHoverBg)
            : (root.clockOpen ? T.Theme.btnActiveBg : "transparent")
        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
    }

    MouseArea {
        id: clockMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggleClock()
    }
}
