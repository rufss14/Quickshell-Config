pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"
import "../"

// ── TabletTestView ────────────────────────────────────────────────────────────
// A pad to try the pen on: the line is as thick as you press, so a pressure range that is too stiff or too
// loose shows itself in a few strokes, and the numbers beside it say what the tablet reported (pressure,
// reports per second, the pen's buttons).
//
// The strokes follow the POINTER, which is where the profile maps the pen, so this also shows the area
// and the screen mapping working. The thickness and the numbers come from the helper's raw reports, which
// need the live pen (Tablet.liveBlocker() says what is missing); without it the line is a steady medium.
//
// Drawn on a Canvas that is only painted for the segments added since the last paint, never redrawn whole.
// ─────────────────────────────────────────────────────────────────────────────
IslandPlate {
    id: root

    order: 1

    readonly property var pen: Tablet.pen
    readonly property real pressure: root.pen !== null && root.pen.in === true ? root.pen.p : 0
    readonly property string blocker: Tablet.liveBlocker()

    // Segments waiting to be painted: [x0, y0, x1, y1, width].
    property var _queue: []
    function _line(x0, y0, x1, y1) {
        const p = root.pen !== null && root.pen.in === true ? root.pen.p : 0.55
        root._queue.push([x0, y0, x1, y1, 1.5 + p * Tokens.iconMd * 1.2])
        paper.requestPaint()
    }
    function clear() {
        root._queue = []
        const ctx = paper.getContext("2d")
        ctx.clearRect(0, 0, paper.width, paper.height)
        paper.requestPaint()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingLg
        spacing: Tokens.spacingMd

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd

            TabletPlateTitle {
                Layout.fillWidth: true
                symbol: "edit"
                shape: "sunny"
                title: Translation.tr("Test pad")
                note: Translation.tr("Draw here. The line follows how hard you press")
            }
            ChipButton {
                tonal: true
                symbol: "undo"
                label: Translation.tr("Clear")
                onActivated: root.clear()
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingMd

            // The paper: a lifted canvas with a hairline.
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Tokens.radiusSm
                color: root.palette.surfaceHigh
                border.width: Tokens.borderWidth
                border.color: root.palette.outline
                clip: true

                Canvas {
                    id: paper
                    anchors.fill: parent
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.lineCap = "round"
                        ctx.strokeStyle = String(root.palette.primary)
                        const q = root._queue
                        root._queue = []
                        for (let i = 0; i < q.length; i++) {
                            ctx.lineWidth = q[i][4]
                            ctx.beginPath()
                            ctx.moveTo(q[i][0], q[i][1])
                            ctx.lineTo(q[i][2], q[i][3])
                            ctx.stroke()
                        }
                    }
                }

                MouseArea {
                    property real lx: 0
                    property real ly: 0
                    anchors.fill: parent
                    cursorShape: Qt.CrossCursor
                    onPressed: m => { lx = m.x; ly = m.y; root._line(m.x, m.y, m.x + 0.01, m.y) }
                    onPositionChanged: m => {
                        if (!pressed) return
                        root._line(lx, ly, m.x, m.y)
                        lx = m.x
                        ly = m.y
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: root.blocker !== "" && Tablet.rate === 0
                    width: parent.width - Tokens.spacingXl * 2
                    horizontalAlignment: Text.AlignHCenter
                    text: root.blocker
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                }
            }

            // What the tablet reported.
            ColumnLayout {
                Layout.fillWidth: false
                Layout.preferredWidth: Tokens.iconXl * 4
                Layout.fillHeight: true
                spacing: Tokens.spacingMd

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: root.blocker === "" ? Math.round(root.pressure * 100) + "%" : "–"
                        font.pixelSize: Tokens.fontDisplay * 1.5
                        font.weight: Font.Bold
                        font.features: ({ tnum: 1 })
                        color: root.palette.fg
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("pressure")
                        variant: "caption"
                        color: root.palette.fgMuted
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: Tablet.rate > 0 ? String(Tablet.rate) : "–"
                        font.pixelSize: Tokens.fontDisplay
                        font.weight: Font.Bold
                        font.features: ({ tnum: 1 })
                        color: root.palette.fg
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("reports a second")
                        variant: "caption"
                        color: root.palette.fgMuted
                    }
                }
                // The pen's two buttons: a dot that lights while one is held.
                Repeater {
                    model: [
                        { label: Translation.tr("Button 1"), held: root.pen !== null && root.pen.b1 === true },
                        { label: Translation.tr("Button 2"), held: root.pen !== null && root.pen.b2 === true }
                    ]
                    delegate: RowLayout {
                        id: btn
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Tokens.spacingSm
                        Rectangle {
                            Layout.preferredWidth: Tokens.spacingMd
                            Layout.preferredHeight: Tokens.spacingMd
                            radius: width / 2
                            color: btn.modelData.held ? root.palette.primary : root.palette.alpha(root.palette.fg, 0.18)
                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: btn.modelData.label
                            variant: "caption"
                            font.weight: btn.modelData.held ? Font.DemiBold : Font.Medium
                            color: btn.modelData.held ? root.palette.fg : root.palette.fgMuted
                        }
                    }
                }
                Item { Layout.fillHeight: true }
            }
        }
    }
}
