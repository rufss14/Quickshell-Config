import QtQuick
import "../../../config"
import "../../../components"
import "../../../state"

// ── ClockPill ─────────────────────────────────────────────────────────────────
// Analog face + date + time. Click opens the clock panel.
//
// The two 1s timers (one repainting the Canvas, one rewriting the text) are now
// a single timer driving a single `now` property — both consumers derive from
// it, so they can't tick out of step, and there is one wakeup a second instead
// of two. Previously this ran twice over, because the bar built both layouts.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // ── accent ────────────────────────────────────────────────────────────────
    // Settable per module (Settings → Bar → pick a module). Defaults to the role this
    // widget already used, so an untouched module is unchanged.
    property color accent: Colors.primary

    property bool active: false
    signal toggled()

    implicitWidth:  pill.width
    implicitHeight: Tokens.pillHeight

    // One clock source for both the face and the text.
    property date now: new Date()

    Timer {
        interval: 1000
        running:  true
        repeat:   true
        onTriggered: {
            root.now = new Date()
            face.requestPaint()
        }
    }

    IconButton {
        id: pill
        height: Tokens.pillHeight
        // Ceil: the row contains text, so its width is fractional. See IconButton.
        width:  Math.ceil(content.implicitWidth) + Tokens.pillPadding * 2

        squareMode: Config.barShape
        active:     root.active
        onClicked:  root.toggled()

        Row {
            id: content
            anchors.centerIn: parent
            spacing: Tokens.spacingMd

            Canvas {
                id: face
                width:  Tokens.iconMd
                height: Tokens.iconMd
                anchors.verticalCenter: parent.verticalCenter

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)

                    const cx = width / 2
                    const cy = height / 2
                    const r  = width / 2 - 1.5

                    const hrs  = root.now.getHours() % 12
                    const mins = root.now.getMinutes()
                    const secs = root.now.getSeconds()

                    const minAngle  = ((mins + secs / 60) / 60) * Math.PI * 2 - Math.PI / 2
                    const hourAngle = ((hrs + mins / 60) / 12) * Math.PI * 2 - Math.PI / 2

                    const accent = root.accent
                    const fg     = Colors.fg

                    ctx.lineCap = "round"

                    ctx.beginPath()
                    ctx.arc(cx, cy, r, 0, Math.PI * 2)
                    ctx.strokeStyle = Colors.alpha(accent, 0.7)
                    ctx.lineWidth = 1.2
                    ctx.stroke()

                    for (let i = 0; i < 12; i++) {
                        const angle = (i / 12) * Math.PI * 2 - Math.PI / 2
                        const major = i % 3 === 0
                        const inner = r - (major ? 2.5 : 1.5)
                        ctx.beginPath()
                        ctx.moveTo(cx + Math.cos(angle) * (r - 0.5), cy + Math.sin(angle) * (r - 0.5))
                        ctx.lineTo(cx + Math.cos(angle) * inner,     cy + Math.sin(angle) * inner)
                        ctx.strokeStyle = major
                            ? Colors.alpha(accent, 0.5)
                            : Colors.alpha(fg, 0.2)
                        ctx.lineWidth = major ? 0.8 : 0.5
                        ctx.stroke()
                    }

                    ctx.beginPath()
                    ctx.moveTo(cx, cy)
                    ctx.lineTo(cx + Math.cos(hourAngle) * r * 0.45, cy + Math.sin(hourAngle) * r * 0.45)
                    ctx.strokeStyle = Colors.alpha(fg, 1.0)
                    ctx.lineWidth = 1.5
                    ctx.stroke()

                    ctx.beginPath()
                    ctx.moveTo(cx, cy)
                    ctx.lineTo(cx + Math.cos(minAngle) * r * 0.72, cy + Math.sin(minAngle) * r * 0.72)
                    ctx.strokeStyle = Colors.alpha(fg, 0.85)
                    ctx.lineWidth = 1.0
                    ctx.stroke()

                    ctx.beginPath()
                    ctx.arc(cx, cy, 1.2, 0, Math.PI * 2)
                    ctx.fillStyle = Colors.alpha(accent, 1.0)
                    ctx.fill()
                }

                // Repaint when the palette changes, not just when time moves —
                // otherwise the face keeps the old accent until the next tick.
                // Handler names track the PROPERTY names: `primary` → onPrimaryChanged,
                // `fg` → onFgChanged. (This is the legitimate use of the `on` prefix —
                // a handler for a change signal — as opposed to declaring a property
                // with that prefix, which QML silently swallows.)
                Connections {
                    target: Colors
                    function onPrimaryChanged() { face.requestPaint() }
                    function onFgChanged()      { face.requestPaint() }
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1; height: 14
                color: Colors.fgDim
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text:    Qt.formatDateTime(root.now, "ddd, MMM dd")
                variant: "label"
                sizeScale: Config.barFontScale
                font.weight: Font.Medium
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1; height: 14
                color: Colors.fgDim
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text:    Qt.formatDateTime(root.now, "HH:mm")
                variant: "body"
                sizeScale: Config.barFontScale
                color:   root.accent
                font.weight: Font.Bold
                font.letterSpacing: 0.5
            }
        }
    }
}
